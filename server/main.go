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
	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	_ "github.com/mattn/go-sqlite3"
	"google.golang.org/api/option"
)

var db *sql.DB
var clients = make(map[string]*websocket.Conn)
var upgrader = websocket.Upgrader{
	CheckOrigin:      func(r *http.Request) bool { return true },
	ReadBufferSize:   1024,
	WriteBufferSize:  1024,
	HandshakeTimeout: 10 * time.Second,
}
var users = map[string]string{"user1": "pass1", "user2": "pass2"}
var userIDs = map[string]string{"user1": "1", "user2": "2"}
var fcmTokens = make(map[string]string)
var firebaseApp *firebase.App

func initDB() {
	var err error
	db, err = sql.Open("sqlite3", "./ghost.db")
	if err != nil {
		log.Fatal("❌ Error abriendo DB:", err)
	}
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
		Notification: &messaging.Notification{
			Title: title,
			Body:  msgBody,
		},
		Android: &messaging.AndroidConfig{
			Priority: "high",
			Notification: &messaging.AndroidNotification{
				Sound: "default",
				ChannelID: "ghost_chat_messages",
			},
		},
		Data: map[string]string{
			"from_user": toUserID,
			"click_action": "FLUTTER_NOTIFICATION_CLICK",
		},
	}
	_, err = client.Send(ctx, message)
	if err != nil {
		log.Printf("❌ Error enviando push a %s: %v", toUserID, err)
	} else {
		log.Printf("🔔 Push enviado a usuario %s: %s", toUserID, msgBody)
	}
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
        message := &messaging.Message{
                Token: token,
                Data: map[string]string{
                        "type": "call",
                        "from_user": fromUserID,
                        "caller_name": "Usuario " + fromUserID,
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
		c.JSON(200, gin.H{"user_id": userID, "username": username, "display_name": displayName, "avatar_index": avatarIndex})
		return
	}
	expectedPass, ok := users[username]
	if !ok || expectedPass != password {
		c.JSON(401, gin.H{"error": "Usuario o contrasena incorrectos"})
		return
	}
	userID = userIDs[username]
	log.Printf("🔐 Login hardcoded: %s -> %s", username, userID)
	c.JSON(200, gin.H{"user_id": userID, "username": username})
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
		SELECT from_user, to_user, type, message, url, filename, size, timestamp
		FROM messages
		WHERE (from_user = ? AND to_user = ?) OR (from_user = ? AND to_user = ?)
		ORDER BY created_at ASC LIMIT 200
	`, userID, otherID, otherID, userID)
	if err != nil {
		c.JSON(500, gin.H{"error": "Error consultando historial"})
		return
	}
	defer rows.Close()
	var messages []map[string]interface{}
	for rows.Next() {
		var fromUser, toUser, msgType, message, url, filename, timestamp string
		var size int
		rows.Scan(&fromUser, &toUser, &msgType, &message, &url, &filename, &size, &timestamp)
		msg := map[string]interface{}{"from": fromUser, "to": toUser, "type": msgType, "timestamp": timestamp}
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
	url := "http://192.168.100.21:9090/uploads/" + filename
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
	path := "./avatars/" + userID + ".jpg"
	if err := c.SaveUploadedFile(file, path); err != nil {
		c.JSON(500, gin.H{"error": "Error guardando"})
		return
	}
	url := "http://192.168.100.21:9090/avatars/" + userID + ".jpg"
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
		log.Printf("📡 [%s] %s → %s", msgType, userID, toUser)
		msg["from"] = userID
		msg["timestamp"] = fmt.Sprintf("%d", time.Now().UnixMilli())
		if msgType == "text" || msgType == "image" || msgType == "audio" || msgType == "file" || msgType == "edit" || msgType == "location" || msgType == "live_location" {
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
			// Siempre mandar FCM en llamadas aunque esté conectado (puede estar suspendido)
			if msgType == "call" {
				isVideo := fmt.Sprintf("%v", msg["isVideo"]) == "true"
				callType := "audio"
				if isVideo { callType = "video" }
				go sendPushNotificationCall(toUser, userID, isVideo, callType)
			}
		} else {
			switch msgType {
			case "text":
				go sendPushNotification(toUser, "Nuevo mensaje", fmt.Sprintf("%v", msg["message"]))
			case "image":
				go sendPushNotification(toUser, "Nuevo mensaje", "📷 Imagen")
			case "audio":
				go sendPushNotification(toUser, "Nuevo mensaje", "🎤 Audio")
			case "file":
				go sendPushNotification(toUser, "Nuevo mensaje", "📎 Archivo")
			case "call":
				isVideo := fmt.Sprintf("%v", msg["isVideo"]) == "true"
					callType := "audio"
					if isVideo { callType = "video" }
					go sendPushNotificationCall(toUser, userID, isVideo, callType)
			}
		}
	}
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
	r.StaticFile("/GhostChat.apk", "/home/william-kalinux/Escritorio/GhostChat.apk")
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
	r.POST("/group/create", handleCreateGroup)
	r.POST("/group/add-member", handleAddMember)
	r.POST("/group/remove-member", handleRemoveMember)
	r.GET("/group/list", handleGetGroups)
	r.GET("/group/members", handleGetGroupMembers)
	log.Println("🚀 Servidor en http://192.168.100.21:9090")
	r.SetTrustedProxies(nil)
	r.Run(":9090")
}
