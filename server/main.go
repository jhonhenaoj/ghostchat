package main

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"bytes"
	"encoding/json"
	"sync"
	"os/exec"
	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	_ "github.com/mattn/go-sqlite3"
	"google.golang.org/api/option"
)

var db *sql.DB
var clients = make(map[string]*websocket.Conn)
var clientsMu sync.RWMutex
var upgrader = websocket.Upgrader{
	CheckOrigin:      func(r *http.Request) bool { return true },
	ReadBufferSize:   1024,
	WriteBufferSize:  1024,
	HandshakeTimeout: 10 * time.Second,
}
var users = map[string]string{"user1": "pass1", "user2": "pass2"}
var userIDs = map[string]string{"user1": "1", "user2": "2"}
var fcmTokens = make(map[string]string)

// Salas de llamada grupal
type CallRoom struct {
	ID           string
	Participants []string
	IsVideo      bool
	CreatedAt    time.Time
}
var callRooms = map[string]*CallRoom{}
var callRoomsMu sync.Mutex
var invites = make(map[string]map[string]interface{})
var firebaseApp *firebase.App

func initDB() {
	var err error
	db, err = sql.Open("sqlite3", "./ghost.db")
	if err != nil {
		log.Fatal("❌ Error abriendo DB:", err)
	}
	db.Exec(`CREATE TABLE IF NOT EXISTS sessions (
		id TEXT PRIMARY KEY,
		user_id TEXT NOT NULL,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP
	)`)
	db.Exec(`CREATE TABLE IF NOT EXISTS users (
		id TEXT PRIMARY KEY,
		username TEXT UNIQUE,
		password TEXT,
		display_name TEXT,
		avatar_index INTEGER DEFAULT 0,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP
	)`)
	db.Exec(`CREATE TABLE IF NOT EXISTS messages (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		from_user TEXT,
		to_user TEXT,
		type TEXT,
		message TEXT,
		url TEXT,
		filename TEXT,
		size INTEGER,
		timestamp TEXT,
		read_at DATETIME,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP
	)`)
	db.Exec("ALTER TABLE messages ADD COLUMN read_at DATETIME")
	db.Exec(`CREATE TABLE IF NOT EXISTS groups_table (
		id TEXT PRIMARY KEY,
		name TEXT,
		avatar_index INTEGER DEFAULT 0,
		created_by TEXT,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP
	)`)
	db.Exec(`CREATE TABLE IF NOT EXISTS group_members (
		group_id TEXT,
		user_id TEXT,
		is_admin INTEGER DEFAULT 0,
		joined_at DATETIME DEFAULT CURRENT_TIMESTAMP,
		PRIMARY KEY (group_id, user_id)
	)`)
	db.Exec(`CREATE TABLE IF NOT EXISTS fcm_tokens (
		user_id TEXT PRIMARY KEY,
		token TEXT,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP
	)`)
	// Usuarios hardcodeados
	db.Exec(`INSERT OR IGNORE INTO users (id, username, password, display_name) VALUES ('1', 'user1', 'pass1', 'Usuario 1')`)
	db.Exec(`INSERT OR IGNORE INTO users (id, username, password, display_name) VALUES ('2', 'user2', 'pass2', 'Usuario 2')`)
	log.Println("✅ Base de datos lista")
}

func saveMessage(msg map[string]interface{}) {
	fromUser := fmt.Sprintf("%v", msg["from"])
	toUser := fmt.Sprintf("%v", msg["to"])
	msgType := fmt.Sprintf("%v", msg["type"])
	message := fmt.Sprintf("%v", msg["message"])
	url := fmt.Sprintf("%v", msg["url"])
	filename := fmt.Sprintf("%v", msg["filename"])
	timestamp := fmt.Sprintf("%v", msg["timestamp"])
	size := 0
	if s, ok := msg["size"]; ok {
		fmt.Sscanf(fmt.Sprintf("%v", s), "%d", &size)
	}
	if message == "<nil>" { message = "" }
	if url == "<nil>" { url = "" }
	if filename == "<nil>" { filename = "" }
	db.Exec(`INSERT INTO messages (from_user, to_user, type, message, url, filename, size, timestamp)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)`, fromUser, toUser, msgType, message, url, filename, size, timestamp)
}

func sendPushNotification(toUserID string, title string, msgBody string) {
	token, ok := fcmTokens[toUserID]
	if !ok || token == "" {
		log.Printf("⚠️ No hay token FCM para usuario %s", toUserID)
		return
	}
	if firebaseApp == nil {
		log.Printf("⚠️ Firebase no inicializado")
		return
	}
	ctx := context.Background()
	client, err := firebaseApp.Messaging(ctx)
	if err != nil {
		log.Printf("❌ Error obteniendo cliente FCM: %v", err)
		return
	}
	message := &messaging.Message{
		Token: token,
		// Data-only para que llegue con app muerta
		Data: map[string]string{
			"title":        title,
			"body":         msgBody,
			"from_user":    toUserID,
			"type":         "message",
			"click_action": "FLUTTER_NOTIFICATION_CLICK",
		},
		Android: &messaging.AndroidConfig{
			Priority: "high",
		},
	}
	_, err = client.Send(ctx, message)
	if err != nil {
		log.Printf("❌ Error enviando push a %s: %v", toUserID, err)
	} else {
		log.Printf("🔔 Push enviado a usuario %s: %s", toUserID, msgBody)
	}
	// Enviar también por OneSignal como respaldo
	go sendOneSignalNotification(toUserID, title, msgBody, map[string]string{
		"type": "message",
		"from_user": toUserID,
	})
}


	func sendOneSignalNotification(externalID string, title string, body string, data map[string]string) {
	externalID = "ghostchat_user_" + externalID
	payload := map[string]interface{}{
		"app_id": "265c6d06-d77f-46df-9032-87c803e03906",
		"filters": []map[string]string{
			{"field": "tag", "key": "user_id", "relation": "=", "value": externalID},
		},
		"headings": map[string]string{"en": title},
		"contents": map[string]string{"en": body},
		"data":     data,
		"priority": 10,
		"android_channel_id": "ghost_chat_messages",
	}
	jsonData, _ := json.Marshal(payload)
	req, err := http.NewRequest("POST", "https://onesignal.com/api/v1/notifications", bytes.NewBuffer(jsonData))
	if err != nil { return }
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "os_v2_app_ezog2bwxp5dn7ebsq7eahybza2cyobn2jz2u2hvituysqpr36vc2rhjujco3cwj7ceefjepeuvzjhqas55sxn6vdvtt763biyftpzki")
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		log.Printf("❌ Error OneSignal: %v", err)
		return
	}
	defer resp.Body.Close()
	log.Printf("🔔 OneSignal enviado a %s: %d", externalID, resp.StatusCode)
}

func sendPushNotificationCall(toUserID string, fromUserID string, isVideo bool, callType string) {
		token, ok := fcmTokens[toUserID]
		if !ok || token == "" { return }
		if firebaseApp == nil { return }
		ctx := context.Background()
		client, err := firebaseApp.Messaging(ctx)
		if err != nil { return }
		title := "📞 Llamada entrante"
		if isVideo { title = "📹 Videollamada entrante" }
		isVideoStr := "false"
		if isVideo { isVideoStr = "true" }
		// Obtener nombre real del remitente
		callerName := "Usuario " + fromUserID
		var displayName string
		if err := db.QueryRow(`SELECT COALESCE(display_name, username) FROM users WHERE id = ?`, fromUserID).Scan(&displayName); err == nil && displayName != "" {
			callerName = displayName
		}
        message := &messaging.Message{
                Token: token,
                Data: map[string]string{
                        "type": "call",
                        "from_user": fromUserID,
			"caller_name": callerName,
                        "is_video": isVideoStr,
                        "call_id": fmt.Sprintf("call_%s_%d", fromUserID, time.Now().UnixMilli()),
                        "call_type": callType,
                        "click_action": "FLUTTER_NOTIFICATION_CLICK",
                        "title": title,
                        "body": "Toca para contestar",
                },
                Android: &messaging.AndroidConfig{
                        Priority: "high",
                },
        }
        _, err = client.Send(ctx, message)
        if err != nil {
                log.Printf("❌ Error enviando push call a %s: %v", toUserID, err)
                // Token inválido, eliminarlo para forzar renovación
                delete(fcmTokens, toUserID)
                db.Exec("DELETE FROM fcm_tokens WHERE user_id = ?", toUserID)
        } else {
                log.Printf("🔔 Push call enviado a usuario %s", toUserID)
        }
	// Enviar también por OneSignal como respaldo para llamadas
	callTitle := "📞 Llamada entrante"
	if isVideo { callTitle = "📹 Videollamada entrante" }
	go sendOneSignalNotification(toUserID, callTitle, callerName+" te está llamando", map[string]string{
		"type": "call",
		"from_user": fromUserID,
		"is_video": fmt.Sprintf("%v", isVideo),
		"caller_name": callerName,
		"call_id": fmt.Sprintf("call_%s_%d", fromUserID, time.Now().UnixMilli()),
	})
}

func handleGroupCall(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(400, gin.H{"error": "invalid"})
		return
	}
	action := fmt.Sprintf("%v", body["action"])
	roomID := fmt.Sprintf("%v", body["room_id"])
	userID := fmt.Sprintf("%v", body["user_id"])
	isVideo := body["is_video"] == true

	callRoomsMu.Lock()
	defer callRoomsMu.Unlock()

	switch action {
	case "create":
		participants := []string{userID}
		callRooms[roomID] = &CallRoom{
			ID: roomID, Participants: participants,
			IsVideo: isVideo, CreatedAt: time.Now(),
		}
		// Notificar a todos los invitados
		if invites, ok := body["invites"].([]interface{}); ok {
			for _, inv := range invites {
				invID := fmt.Sprintf("%v", inv)
				// Enviar por WebSocket
				if conn, ok := clients[invID]; ok {
					msg := map[string]interface{}{
						"type": "group_call_invite",
						"room_id": roomID,
						"from": userID,
						"is_video": isVideo,
					}
					data, _ := json.Marshal(msg)
					conn.WriteMessage(1, data)
				}
				// Enviar por OneSignal
				title := "📞 Llamada grupal entrante"
				if isVideo { title = "📹 Videollamada grupal entrante" }
				var callerName string
				db.QueryRow("SELECT COALESCE(display_name, username) FROM users WHERE id = ?", userID).Scan(&callerName)
				if callerName == "" { callerName = userID }
				go sendOneSignalNotification(invID, title, callerName+" te invita a una llamada grupal", map[string]string{
					"type": "group_call",
					"room_id": roomID,
					"from_user": userID,
					"is_video": fmt.Sprintf("%v", isVideo),
					"caller_name": callerName,
				})
			}
		}
		c.JSON(200, gin.H{"room_id": roomID, "status": "created"})

	case "join":
		if room, ok := callRooms[roomID]; ok {
			if len(room.Participants) >= 5 {
				c.JSON(400, gin.H{"error": "room full"})
				return
			}
			if !contains(room.Participants, userID) {
				room.Participants = append(room.Participants, userID)
			}
			// Notificar a todos los participantes
			for _, pid := range room.Participants {
				if pid != userID {
					if conn, ok := clients[pid]; ok {
						msg := map[string]interface{}{
							"type": "group_call_joined",
							"room_id": roomID,
							"user_id": userID,
							"participants": room.Participants,
						}
						data, _ := json.Marshal(msg)
						conn.WriteMessage(1, data)
					}
				}
			}
			c.JSON(200, gin.H{"participants": room.Participants})
		} else {
			c.JSON(404, gin.H{"error": "room not found"})
		}

	case "leave":
		if room, ok := callRooms[roomID]; ok {
			room.Participants = removeFrom(room.Participants, userID)
			if len(room.Participants) == 0 {
				delete(callRooms, roomID)
			} else {
				for _, pid := range room.Participants {
					if conn, ok := clients[pid]; ok {
						msg := map[string]interface{}{
							"type": "group_call_left",
							"room_id": roomID,
							"user_id": userID,
							"participants": room.Participants,
						}
						data, _ := json.Marshal(msg)
						conn.WriteMessage(1, data)
					}
				}
			}
		}
		c.JSON(200, gin.H{"status": "left"})
	}
}

func contains(slice []string, item string) bool {
	for _, s := range slice { if s == item { return true } }
	return false
}

func removeFrom(slice []string, item string) []string {
	result := []string{}
	for _, s := range slice { if s != item { result = append(result, s) } }
	return result
}

func handleValidateSession(c *gin.Context) {
	sessionToken := c.Query("token")
	userID := c.Query("user_id")
	if sessionToken == "" || userID == "" {
		c.JSON(400, gin.H{"valid": false})
		return
	}
	var count int
	db.QueryRow("SELECT COUNT(*) FROM sessions WHERE id = ? AND user_id = ?", sessionToken, userID).Scan(&count)
	c.JSON(200, gin.H{"valid": count > 0})
}

func handleCreateInvite(c *gin.Context) {
        var body map[string]string
        if err := c.ShouldBindJSON(&body); err != nil {
                c.JSON(400, gin.H{"error": "invalid"})
                return
        }
        userID := body["user_id"]
        code := fmt.Sprintf("%08d", time.Now().UnixNano()%100000000)
        invites[code] = map[string]interface{}{
                "user_id": userID,
                "expires": time.Now().Add(24 * time.Hour).Unix(),
        }
        link := "ghostchat://invite/" + code
        c.JSON(200, gin.H{"code": code, "link": link, "expires_in": "24 horas"})
}

func handleJoinInvite(c *gin.Context) {
        code := c.Query("code")
        invite, ok := invites[code]
        if !ok {
                c.JSON(404, gin.H{"error": "Invitacion no encontrada o expirada"})
                return
        }
        expires := invite["expires"].(int64)
        if time.Now().Unix() > expires {
                delete(invites, code)
                c.JSON(404, gin.H{"error": "Invitacion expirada"})
                return
        }
        userID := invite["user_id"].(string)
        var id, username, displayName, avatarURL string
        err := db.QueryRow(`SELECT id, username, COALESCE(display_name,''), COALESCE(avatar_url,'') FROM users WHERE id = ?`, userID).Scan(&id, &username, &displayName, &avatarURL)
        if err != nil {
                c.JSON(404, gin.H{"error": "Usuario no encontrado"})
                return
        }
        delete(invites, code)
        c.JSON(200, gin.H{"user_id": id, "username": username, "display_name": displayName, "avatar_url": avatarURL})
}

func handleLogin(c *gin.Context) {
	var body map[string]string
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(400, gin.H{"error": "Datos invalidos"})
		return
	}
	username := strings.TrimSpace(body["username"])
	password := strings.TrimSpace(body["password"])
	var userID, displayName string
	var avatarIndex int
	err := db.QueryRow(`SELECT id, display_name, avatar_index FROM users WHERE username = ? AND password = ?`,
		username, password).Scan(&userID, &displayName, &avatarIndex)
	if err == nil {
		log.Printf("🔐 Login DB exitoso: %s -> %s", username, userID)
		sessionToken := fmt.Sprintf("%s_%d", userID, time.Now().UnixNano())
		db.Exec("INSERT OR REPLACE INTO sessions (id, user_id) VALUES (?, ?)", sessionToken, userID)
		c.JSON(200, gin.H{"user_id": userID, "username": username, "display_name": displayName, "avatar_index": avatarIndex, "session_token": sessionToken})
		return
	}
	expectedPass, ok := users[username]
	if !ok || expectedPass != password {
		c.JSON(401, gin.H{"error": "Usuario o contrasena incorrectos"})
		return
	}
	userID = userIDs[username]
	log.Printf("🔐 Login hardcoded: %s -> %s", username, userID)
	sessionToken := fmt.Sprintf("%s_%d", userID, time.Now().UnixNano())
	db.Exec("INSERT OR REPLACE INTO sessions (id, user_id) VALUES (?, ?)", sessionToken, userID)
	c.JSON(200, gin.H{"user_id": userID, "username": username, "session_token": sessionToken})
}

func handleRegister(c *gin.Context) {
	var body map[string]string
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(400, gin.H{"error": "Datos invalidos"})
		return
	}
	username := strings.TrimSpace(body["username"])
	password := strings.TrimSpace(body["password"])
	displayName := strings.TrimSpace(body["display_name"])
	if username == "" || password == "" {
		c.JSON(400, gin.H{"error": "Usuario y contrasena requeridos"})
		return
	}
	if displayName == "" { displayName = username }
	userID := fmt.Sprintf("%d", time.Now().UnixNano())
	_, err := db.Exec(`INSERT INTO users (id, username, password, display_name) VALUES (?, ?, ?, ?)`,
		userID, username, password, displayName)
	if err != nil {
		c.JSON(400, gin.H{"error": "Usuario ya existe"})
		return
	}
	log.Printf("✅ Usuario registrado: %s (%s)", username, userID)
	c.JSON(200, gin.H{"user_id": userID, "username": username, "display_name": displayName})
}

func handleGetUsers(c *gin.Context) {
	myID := c.Query("my_id")
	rows, err := db.Query(`SELECT id, username, display_name, avatar_index FROM users WHERE id != ?`, myID)
	if err != nil {
		c.JSON(500, gin.H{"error": "Error"})
		return
	}
	defer rows.Close()
	var userList []map[string]interface{}
	for rows.Next() {
		var id, username, displayName string
		var avatarIndex int
		rows.Scan(&id, &username, &displayName, &avatarIndex)
		userList = append(userList, map[string]interface{}{
			"id": id, "username": username,
			"display_name": displayName, "avatar_index": avatarIndex,
		})
	}
	if userList == nil { userList = []map[string]interface{}{} }
	c.JSON(200, gin.H{"users": userList})
}

func handleHistory(c *gin.Context) {
	userID := c.Query("user_id")
	otherID := c.Query("other_id")
	if userID == "" || otherID == "" {
		c.JSON(400, gin.H{"error": "Faltan parametros"})
		return
	}
	rows, err := db.Query(`
		SELECT from_user, to_user, type, message, url, filename, size, timestamp, COALESCE(read_at,""), ""
		FROM messages
		WHERE (from_user = ? AND to_user = ?) OR (from_user = ? AND to_user = ?)
		ORDER BY created_at ASC LIMIT 500
	`, userID, otherID, otherID, userID)
	if err != nil {
		c.JSON(500, gin.H{"error": "Error consultando historial"})
		return
	}
	defer rows.Close()
	var messages []map[string]interface{}
	for rows.Next() {
		var fromUser, toUser, msgType, message, url, filename, timestamp, readAt, sticker string
		var size int
		rows.Scan(&fromUser, &toUser, &msgType, &message, &url, &filename, &size, &timestamp, &readAt, &sticker)
		msg := map[string]interface{}{"from": fromUser, "to": toUser, "type": msgType, "timestamp": timestamp}
			if readAt != "" { msg["read_at"] = readAt }
			if sticker != "" { msg["sticker"] = sticker }
			if sticker != "" { msg["sticker"] = sticker }
		if message != "" { msg["message"] = message }
		if url != "" { msg["url"] = url }
		if filename != "" { msg["filename"] = filename; msg["size"] = size }
		messages = append(messages, msg)
	}
	if messages == nil { messages = []map[string]interface{}{} }
	c.JSON(200, gin.H{"messages": messages})
}

func handleMarkRead(c *gin.Context) {
	var body map[string]string
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(400, gin.H{"error": "invalid"})
		return
	}
	fromUser := body["from_user"]
	toUser := body["to_user"]
	db.Exec(`UPDATE messages SET read_at = CURRENT_TIMESTAMP WHERE from_user = ? AND to_user = ? AND read_at IS NULL`, fromUser, toUser)
	if conn, ok := clients[fromUser]; ok {
		conn.WriteJSON(map[string]interface{}{"type": "read_receipt", "from": toUser})
	}
	c.JSON(200, gin.H{"ok": true})
}

func handleUpload(c *gin.Context) {
	file, err := c.FormFile("file")
	if err != nil {
		file, err = c.FormFile("audio")
		if err != nil {
			c.JSON(400, gin.H{"error": "No file"})
			return
		}
	}
	os.MkdirAll("./uploads", os.ModePerm)
	ext := ""
	parts := strings.Split(file.Filename, ".")
	if len(parts) > 1 { ext = "." + parts[len(parts)-1] }
	filename := fmt.Sprintf("img_%d%s", time.Now().UnixNano(), ext)
	path := "./uploads/" + filename
	if err := c.SaveUploadedFile(file, path); err != nil {
		c.JSON(500, gin.H{"error": "Error guardando"})
		return
	}
	url := "http://162.243.174.252:9090/uploads/" + filename
	c.JSON(200, gin.H{"url": url, "filename": file.Filename, "size": file.Size})
}

func handleUploadAvatar(c *gin.Context) {
	userID := c.PostForm("user_id")
	file, err := c.FormFile("avatar")
	if err != nil {
		c.JSON(400, gin.H{"error": "No file"})
		return
	}
	os.MkdirAll("./avatars", os.ModePerm)
	// Guardar archivo temporal
	tmpPath := "./avatars/" + userID + "_tmp"
	if err := c.SaveUploadedFile(file, tmpPath); err != nil {
		c.JSON(500, gin.H{"error": "Error guardando"})
		return
	}
	// Redimensionar con python3
	outPath := "./avatars/" + userID + ".jpg"
	cmd := fmt.Sprintf("python3 -c \"from PIL import Image; img=Image.open('%s'); img=img.convert('RGB'); img=img.resize((300,300)); img.save('%s','JPEG',quality=85)\"", tmpPath, outPath)
	if err := exec.Command("bash", "-c", cmd).Run(); err != nil {
		// Si falla python, usar archivo original
		os.Rename(tmpPath, outPath)
	} else {
		os.Remove(tmpPath)
	}
	url := fmt.Sprintf("http://162.243.174.252:9090/avatars/%s.jpg", userID)
	// Actualizar avatar_url en DB
	db.Exec("UPDATE users SET avatar_url = ? WHERE id = ?", url, userID)
	c.JSON(200, gin.H{"url": url})
}

func handleGetAvatar(c *gin.Context) {
	userID := c.Param("user_id")
	path := "./avatars/" + userID + ".jpg"
	if _, err := os.Stat(path); os.IsNotExist(err) {
		c.JSON(404, gin.H{"error": "No avatar"})
		return
	}
	c.File(path)
}

func handleUpdateProfile(c *gin.Context) {
        var body map[string]string
        if err := c.ShouldBindJSON(&body); err != nil {
                c.JSON(400, gin.H{"error": "invalid"})
                return
        }
        userID := body["user_id"]
        if name, ok := body["display_name"]; ok && name != "" {
                db.Exec(`UPDATE users SET display_name = ? WHERE id = ?`, name, userID)
        }
        if info, ok := body["info"]; ok {
                db.Exec(`UPDATE users SET info = ? WHERE id = ?`, info, userID)
        }
        c.JSON(200, gin.H{"ok": true})
}

func handleGetProfile(c *gin.Context) {
        userID := c.Query("user_id")
        var id, username, displayName, avatarURL, info, lastSeen string
        err := db.QueryRow(`SELECT id, username, COALESCE(display_name,''), COALESCE(avatar_url,''), COALESCE(info,''), COALESCE(last_seen,'') FROM users WHERE id = ?`, userID).Scan(&id, &username, &displayName, &avatarURL, &info, &lastSeen)
        if err != nil {
                c.JSON(404, gin.H{"error": "not found"})
                return
        }
        c.JSON(200, gin.H{"id": id, "username": username, "display_name": displayName, "avatar_url": avatarURL, "info": info, "last_seen": lastSeen})
}

func handleUpdateName(c *gin.Context) {
        var body map[string]string
        if err := c.ShouldBindJSON(&body); err != nil {
                c.JSON(400, gin.H{"error": "invalid"})
                return
        }
        userID := body["user_id"]
        displayName := body["display_name"]
        db.Exec(`UPDATE users SET display_name = ? WHERE id = ?`, displayName, userID)
        log.Printf("✏️ Nombre actualizado para usuario %s: %s", userID, displayName)
        c.JSON(200, gin.H{"ok": true})
}

func handleRegisterToken(c *gin.Context) {
	var body map[string]string
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(400, gin.H{"error": "invalid"})
		return
	}
	userID := body["user_id"]
	token := body["token"]
	fcmTokens[userID] = token
	db.Exec(`INSERT OR REPLACE INTO fcm_tokens (user_id, token) VALUES (?, ?)`, userID, token)
	log.Printf("🔔 Token FCM registrado para usuario %s", userID)
	c.JSON(200, gin.H{"ok": true})
}

func handleDeleteAll(c *gin.Context) {
	userID := c.Query("user_id")
	if userID == "" {
		c.JSON(400, gin.H{"error": "Falta user_id"})
		return
	}
	db.Exec(`DELETE FROM messages WHERE from_user = ? OR to_user = ?`, userID, userID)
	os.RemoveAll("./uploads")
	os.MkdirAll("./uploads", os.ModePerm)
	log.Printf("🗑️ Todo eliminado para usuario %s", userID)
	c.JSON(200, gin.H{"ok": true})
}

func handleSaveContacts(c *gin.Context) {
        var body map[string]interface{}
        if err := c.ShouldBindJSON(&body); err != nil {
                c.JSON(400, gin.H{"error": "invalid"})
                return
        }
        userID := fmt.Sprintf("%v", body["user_id"])
        contacts := fmt.Sprintf("%v", body["contacts"])
        db.Exec(`UPDATE users SET contacts = ? WHERE id = ?`, contacts, userID)
        c.JSON(200, gin.H{"ok": true})
}

func handleGetContacts(c *gin.Context) {
        userID := c.Query("user_id")
        var contacts string
        err := db.QueryRow(`SELECT COALESCE(contacts,'') FROM users WHERE id = ?`, userID).Scan(&contacts)
        if err != nil {
                c.JSON(404, gin.H{"error": "not found"})
                return
        }
        c.JSON(200, gin.H{"contacts": contacts})
}

func handleCreateGroup(c *gin.Context) {
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(400, gin.H{"error": "Datos invalidos"})
		return
	}
	name := fmt.Sprintf("%v", body["name"])
	createdBy := fmt.Sprintf("%v", body["created_by"])
	avatarIndex := 0
	if v, ok := body["avatar_index"]; ok {
		fmt.Sscanf(fmt.Sprintf("%v", v), "%d", &avatarIndex)
	}
	groupID := fmt.Sprintf("g_%d", time.Now().UnixNano())
	db.Exec(`INSERT INTO groups_table (id, name, avatar_index, created_by) VALUES (?, ?, ?, ?)`,
		groupID, name, avatarIndex, createdBy)
	db.Exec(`INSERT INTO group_members (group_id, user_id, is_admin) VALUES (?, ?, 1)`, groupID, createdBy)
	if members, ok := body["members"].([]interface{}); ok {
		for _, m := range members {
			memberID := fmt.Sprintf("%v", m)
			if memberID != createdBy {
				db.Exec(`INSERT OR IGNORE INTO group_members (group_id, user_id) VALUES (?, ?)`, groupID, memberID)
			}
		}
	}
	c.JSON(200, gin.H{"group_id": groupID, "name": name})
}

func handleAddMember(c *gin.Context) {
	var body map[string]string
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(400, gin.H{"error": "Datos invalidos"})
		return
	}
	db.Exec(`INSERT OR IGNORE INTO group_members (group_id, user_id) VALUES (?, ?)`, body["group_id"], body["user_id"])
	c.JSON(200, gin.H{"ok": true})
}

func handleRemoveMember(c *gin.Context) {
	var body map[string]string
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(400, gin.H{"error": "Datos invalidos"})
		return
	}
	db.Exec(`DELETE FROM group_members WHERE group_id = ? AND user_id = ?`, body["group_id"], body["user_id"])
	c.JSON(200, gin.H{"ok": true})
}

func handleGetGroups(c *gin.Context) {
	userID := c.Query("user_id")
	rows, err := db.Query(`
		SELECT g.id, g.name, g.avatar_index, g.created_by
		FROM groups_table g
		INNER JOIN group_members gm ON g.id = gm.group_id
		WHERE gm.user_id = ?`, userID)
	if err != nil {
		c.JSON(500, gin.H{"error": "Error"})
		return
	}
	defer rows.Close()
	var groups []map[string]interface{}
	for rows.Next() {
		var id, name, createdBy string
		var avatarIndex int
		rows.Scan(&id, &name, &avatarIndex, &createdBy)
		groups = append(groups, map[string]interface{}{
			"id": id, "name": name,
			"avatar_index": avatarIndex, "created_by": createdBy,
		})
	}
	if groups == nil { groups = []map[string]interface{}{} }
	c.JSON(200, gin.H{"groups": groups})
}

func handleGetGroupMembers(c *gin.Context) {
	groupID := c.Query("group_id")
	rows, err := db.Query(`
		SELECT u.id, u.username, u.display_name, u.avatar_index, gm.is_admin
		FROM users u
		INNER JOIN group_members gm ON u.id = gm.user_id
		WHERE gm.group_id = ?`, groupID)
	if err != nil {
		c.JSON(500, gin.H{"error": "Error"})
		return
	}
	defer rows.Close()
	var members []map[string]interface{}
	for rows.Next() {
		var id, username, displayName string
		var avatarIndex, isAdmin int
		rows.Scan(&id, &username, &displayName, &avatarIndex, &isAdmin)
		members = append(members, map[string]interface{}{
			"id": id, "username": username,
			"display_name": displayName, "avatar_index": avatarIndex,
			"is_admin": isAdmin == 1,
		})
	}
	if members == nil { members = []map[string]interface{}{} }
	c.JSON(200, gin.H{"members": members})
}

func handleWebSocket(c *gin.Context) {
	userID := strings.TrimSpace(c.Query("user_id"))
	if userID == "" { return }
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil { return }
	// Cerrar conexión anterior si existe
	if oldConn, ok := clients[userID]; ok {
		oldConn.Close()
		log.Printf("🔄 Reemplazando conexión existente de: %s", userID)
	}
	clients[userID] = conn
	log.Printf("✅ Cliente conectado: %s", userID)
	defer func() {
		delete(clients, userID)
		log.Printf("❌ Cliente desconectado: %s", userID)
		conn.Close()
	}()
	conn.SetReadDeadline(time.Time{})
	conn.SetWriteDeadline(time.Time{})
	conn.SetPingHandler(func(data string) error {
		return conn.WriteControl(websocket.PongMessage, []byte(data), time.Now().Add(10*time.Second))
	})
	for {
		var msg map[string]interface{}
		err := conn.ReadJSON(&msg)
		if err != nil { break }
		toUser := strings.TrimSpace(fmt.Sprintf("%v", msg["to"]))
		msgType := fmt.Sprintf("%v", msg["type"])
                if msgType == "ping" || toUser == "server" || toUser == "0" { continue }
                if msgType == "typing" || msgType == "typing_stop" {
                        msg["from"] = userID
                        if toConn, ok := clients[toUser]; ok {
                                data, _ := json.Marshal(msg)
                                toConn.WriteMessage(1, data)
                        }
                        continue
                }
		log.Printf("📡 [%s] %s → %s", msgType, userID, toUser)
			// Reenviar mensajes WebRTC grupales
			if msgType == "group_offer" || msgType == "group_answer" || msgType == "group_ice" {
				msg["from"] = userID
				data, _ := json.Marshal(msg)
				if toConn, ok := clients[toUser]; ok {
					toConn.WriteMessage(1, data)
				}
				continue
			}
		msg["from"] = userID
		msg["timestamp"] = fmt.Sprintf("%d", time.Now().UnixMilli())
                if msgType == "delete_for_all" {
                        targetTs := fmt.Sprintf("%v", msg["target_timestamp"])
                        db.Exec(`DELETE FROM messages WHERE timestamp = ?`, targetTs)
                        if client, ok := clients[toUser]; ok { client.WriteJSON(msg) }
                        continue
                }
		if msgType == "text" || msgType == "image" || msgType == "audio" || msgType == "file" || msgType == "edit" || msgType == "location" || msgType == "live_location" || msgType == "sticker" || msgType == "giphy" || msgType == "call_status" {
			saveMessage(msg)
		}
		if groupID, ok := msg["group_id"]; ok && groupID != nil && fmt.Sprintf("%v", groupID) != "" {
			gID := fmt.Sprintf("%v", groupID)
			rows, err := db.Query("SELECT user_id FROM group_members WHERE group_id = ?", gID)
			if err == nil {
				for rows.Next() {
					var memberID string
					rows.Scan(&memberID)
					if memberID != userID {
						if conn2, ok2 := clients[memberID]; ok2 {
							conn2.WriteJSON(msg)
						}
					}
				}
				rows.Close()
			}
			continue
		}
		if client, ok := clients[toUser]; ok {
			err := client.WriteJSON(msg)
			if err != nil {
				log.Printf("⚠️ Error enviando a %s, conexión muerta: %v", toUser, err)
				delete(clients, toUser)
			}
                                // Siempre mandar FCM/OneSignal para mensajes aunque este conectado
                                var sName string
                                db.QueryRow(`SELECT COALESCE(display_name, username) FROM users WHERE id = ?`, userID).Scan(&sName)
                                if sName == "" { sName = userID }
                                switch msgType {
                                case "text":
                                        mTxt := fmt.Sprintf("%v", msg["message"])
                                        if len(mTxt) > 50 { mTxt = mTxt[:50] + "..." }
                                        go sendPushNotification(toUser, sName, mTxt)
                                        go sendOneSignalNotification(toUser, sName, mTxt, map[string]string{"type": "message", "from_user": userID})
                                case "image":
                                        go sendPushNotification(toUser, sName, "📷 Te envió una imagen")
                                case "audio":
                                        go sendPushNotification(toUser, sName, "🎤 Te envió un audio")
                                case "location", "live_location":
                                        go sendPushNotification(toUser, sName, "📍 Compartió su ubicación")
                                case "sticker", "giphy":
                                        go sendPushNotification(toUser, sName, "😀 Te envió un sticker")
                                }
			// Siempre mandar FCM en llamadas aunque esté conectado (puede estar suspendido)
			if msgType == "call" {
				isVideo := fmt.Sprintf("%v", msg["isVideo"]) == "true"
				callType := "audio"
				if isVideo { callType = "video" }
				go sendPushNotificationCall(toUser, userID, isVideo, callType)
				// También enviar por OneSignal para Huawei
				callTitleOs := "📞 Llamada entrante"
				if isVideo { callTitleOs = "📹 Videollamada entrante" }
				var callerNameOs string
				db.QueryRow(`SELECT COALESCE(display_name, username) FROM users WHERE id = ?`, userID).Scan(&callerNameOs)
				if callerNameOs == "" { callerNameOs = userID }
				go sendOneSignalNotification(toUser, callTitleOs, callerNameOs+" te está llamando", map[string]string{
					"type": "call",
					"from_user": userID,
					"is_video": fmt.Sprintf("%v", isVideo),
					"caller_name": callerNameOs,
					"call_id": fmt.Sprintf("call_%s_%d", userID, time.Now().UnixMilli()),
				})
			}
		} else {
			switch msgType {
			case "text":
				senderName := userID
				var senderDisplayName string
				dbErr := db.QueryRow(`SELECT COALESCE(display_name, username) FROM users WHERE id = ?`, userID).Scan(&senderDisplayName)
				if dbErr == nil && senderDisplayName != "" { senderName = senderDisplayName }
				msgText := fmt.Sprintf("%v", msg["message"])
				if len(msgText) > 50 { msgText = msgText[:50] + "..." }
				go sendPushNotification(toUser, senderName, msgText)
			case "image":
				go sendPushNotification(toUser, userID, "📷 Te envió una imagen")
			case "audio":
				go sendPushNotification(toUser, userID, "🎤 Te envió un audio")
			case "file":
				go sendPushNotification(toUser, userID, "📎 Te envió un archivo")
			case "giphy":
				go sendPushNotification(toUser, userID, "🎬 Te envió un GIF")
			case "sticker":
				go sendPushNotification(toUser, userID, "🎭 Te envió un sticker")
			case "location", "live_location":
				go sendPushNotification(toUser, userID, "📍 Compartió su ubicación")
				case "call_status":
					status := fmt.Sprintf("%v", msg["status"])
					if status == "missed" {
						isVid := fmt.Sprintf("%v", msg["isVideo"])=="true"
						missedText := "📞 Llamada perdida"
						if isVid { missedText = "📹 Videollamada perdida" }
						var callerN string
						db.QueryRow(`SELECT COALESCE(display_name, username) FROM users WHERE id = ?`, userID).Scan(&callerN)
						if callerN == "" { callerN = userID }
						go sendPushNotification(toUser, callerN, missedText)
					}
			case "call":
				isVideoPush := fmt.Sprintf("%v", msg["isVideo"]) == "true"
				callTypePush := "audio"
				if isVideoPush { callTypePush = "video" }
				go sendPushNotificationCall(toUser, userID, isVideoPush, callTypePush)
				callTitlePush := "📞 Llamada entrante"
				if isVideoPush { callTitlePush = "📹 Videollamada entrante" }
				var callerNamePush string
				db.QueryRow(`SELECT COALESCE(display_name, username) FROM users WHERE id = ?`, userID).Scan(&callerNamePush)
				if callerNamePush == "" { callerNamePush = userID }
				go sendOneSignalNotification(toUser, callTitlePush, callerNamePush+" te está llamando", map[string]string{
					"type": "call",
					"from_user": userID,
					"is_video": fmt.Sprintf("%v", isVideoPush),
					"caller_name": callerNamePush,
					"call_id": fmt.Sprintf("call_%s_%d", userID, time.Now().UnixMilli()),
				})
			}
		}
	}
}


func handleAdminApprove(c *gin.Context) {
	adminPass := c.Query("pass")
	if adminPass != "GhostAdmin2024!" {
		c.JSON(401, gin.H{"error": "No autorizado"})
		return
	}
	userID := c.Query("user_id")
	status := c.Query("status") // approved, suspended, rejected
	if userID == "" || status == "" {
		c.JSON(400, gin.H{"error": "Faltan datos"})
		return
	}
	db.Exec("UPDATE users SET status = ? WHERE id = ?", status, userID)
	if status == "suspended" || status == "rejected" {
		db.Exec("DELETE FROM sessions WHERE user_id = ?", userID)
	}
	c.JSON(200, gin.H{"ok": true, "status": status})
}

func handleAdminPanel(c *gin.Context) {
	c.Redirect(302, "/admin/panel")
}

func handleAdminPanelPage(c *gin.Context) {
	c.File("./admin.html")
}

func handleAdminUsers(c *gin.Context) {
	adminPass := c.Query("pass")
	if adminPass != "GhostAdmin2024!" {
		c.JSON(401, gin.H{"error": "No autorizado"})
		return
	}
	rows, err := db.Query("SELECT id, username, COALESCE(display_name,''), COALESCE(created_at,''), COALESCE(status,'pending') FROM users ORDER BY created_at DESC")
	if err != nil {
		c.JSON(500, gin.H{"error": "Error"})
		return
	}
	defer rows.Close()
	var users []map[string]interface{}
	for rows.Next() {
		var id, username, displayName, createdAt, status string
		rows.Scan(&id, &username, &displayName, &createdAt, &status)
		users = append(users, map[string]interface{}{
			"id": id, "username": username,
			"display_name": displayName, "created_at": createdAt, "status": status,
		})
	}
	c.JSON(200, gin.H{"users": users})
}

func handleGenerateReset(c *gin.Context) {
	adminPass := c.Query("pass")
	if adminPass != "GhostAdmin2024!" {
		c.JSON(401, gin.H{"error": "No autorizado"})
		return
	}
	userID := c.Query("user_id")
	if userID == "" {
		c.JSON(400, gin.H{"error": "Falta user_id"})
		return
	}
	code := fmt.Sprintf("%06d", time.Now().UnixNano()%1000000)
	expires := time.Now().Add(30 * time.Minute)
	db.Exec("DELETE FROM reset_codes WHERE user_id = ?", userID)
	db.Exec("INSERT INTO reset_codes (code, user_id, expires_at) VALUES (?, ?, ?)", code, userID, expires.Format("2006-01-02 15:04:05"))
	c.JSON(200, gin.H{"code": code, "expires_in": "30 minutos"})
}

func handleResetPassword(c *gin.Context) {
	var body map[string]string
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(400, gin.H{"error": "Error"})
		return
	}
	code := body["code"]
	newPass := body["new_password"]
	username := body["username"]
	if code == "" || newPass == "" || username == "" {
		c.JSON(400, gin.H{"error": "Faltan datos"})
		return
	}
	var userID string
	db.QueryRow("SELECT id FROM users WHERE username = ?", username).Scan(&userID)
	if userID == "" {
		c.JSON(400, gin.H{"error": "Usuario no encontrado"})
		return
	}
	var codeUserID, expiresAt string
	var used int
	db.QueryRow("SELECT user_id, expires_at, used FROM reset_codes WHERE code = ?", code).Scan(&codeUserID, &expiresAt, &used)
	if codeUserID == "" {
		c.JSON(400, gin.H{"error": "Código inválido"})
		return
	}
	if codeUserID != userID {
		c.JSON(400, gin.H{"error": "Código no corresponde"})
		return
	}
	if used == 1 {
		c.JSON(400, gin.H{"error": "Código ya utilizado"})
		return
	}
	// expires check desactivado
	if false {
		c.JSON(400, gin.H{"error": "Código expirado"})
		return
	}
	db.Exec("UPDATE users SET password = ? WHERE id = ?", newPass, userID)
	db.Exec("UPDATE reset_codes SET used = 1 WHERE code = ?", code)
	c.JSON(200, gin.H{"message": "Contraseña actualizada"})
}

func main() {
	initDB()
	// Cargar tokens FCM de la DB
	rows, errFCM := db.Query("SELECT user_id, token FROM fcm_tokens")
	if errFCM == nil {
		for rows.Next() {
			var uid, tok string
			rows.Scan(&uid, &tok)
			fcmTokens[uid] = tok
			log.Printf("🔔 Token FCM cargado para usuario %s", uid)
		}
		rows.Close()
	}
	// Inicializar Firebase
	opt := option.WithCredentialsFile("firebase-key.json")
	app, err := firebase.NewApp(context.Background(), nil, opt)
	if err != nil {
		log.Printf("⚠️ Firebase no disponible: %v", err)
	} else {
		firebaseApp = app
		log.Println("✅ Firebase inicializado")
	}
	r := gin.Default()
	r.Static("/uploads", "./uploads")
	r.Static("/web", "../web")
	r.StaticFile("/", "../web/index.html")
	r.StaticFile("/terms", "../web/terms.html")
	r.StaticFile("/privacy", "../web/privacy.html")
	r.StaticFile("/GhostChat.apk", "/root/ghostchat/server/GhostChat.apk")
	r.Static("/avatars", "./avatars")
	r.POST("/login", handleLogin)
	r.POST("/register", handleRegister)
	r.GET("/users", handleGetUsers)
	r.GET("/ws", handleWebSocket)
	r.GET("/history", handleHistory)
	r.POST("/upload", handleUpload)
	r.POST("/upload-file", handleUpload)
	r.POST("/upload-audio", handleUpload)
	r.POST("/upload-avatar", handleUploadAvatar)
	r.GET("/avatar/:user_id", handleGetAvatar)
	r.POST("/register-token", handleRegisterToken)
	r.POST("/read", handleMarkRead)
	r.DELETE("/delete-all", handleDeleteAll)
        r.POST("/update-profile", handleUpdateProfile)
        r.GET("/profile", handleGetProfile)
        r.POST("/invite/create", handleCreateInvite)
        r.GET("/invite/join", handleJoinInvite)
        r.GET("/online", func(c *gin.Context) {
                online := []string{}
                for uid := range clients {
                        online = append(online, uid)
                }
                c.JSON(200, gin.H{"online": online})
        })
	r.POST("/contacts/save", handleSaveContacts)
	r.GET("/validate-session", handleValidateSession)
	r.POST("/group-call", handleGroupCall)
	r.GET("/contacts/load", handleGetContacts)
	r.POST("/group/create", handleCreateGroup)
	r.POST("/group/add-member", handleAddMember)
	r.POST("/group/remove-member", handleRemoveMember)
	r.GET("/group/list", handleGetGroups)
	r.GET("/group/members", handleGetGroupMembers)
	log.Println("🚀 Servidor en http://192.168.100.21:9090")
	r.SetTrustedProxies(nil)
	r.GET("/admin", handleAdminPanel)
	r.GET("/admin/panel", handleAdminPanelPage)
	r.GET("/admin/users", handleAdminUsers)
	r.GET("/admin/generate-reset", handleGenerateReset)
	r.GET("/admin/approve", handleAdminApprove)
	r.POST("/reset-password", handleResetPassword)
	r.Run(":9090")
}
