package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

var clients = make(map[string]*websocket.Conn)

func main() {
	r := gin.Default()
	r.MaxMultipartMemory = 100 << 20
	os.MkdirAll("./uploads", os.ModePerm)
	r.Static("/uploads", "./uploads")
	r.GET("/", func(c *gin.Context) { c.JSON(200, gin.H{"status": "OK"}) })
	r.GET("/ws", handleWebSocket)
	r.POST("/upload", handleUpload)
	r.POST("/upload-audio", handleAudioUpload)
	r.POST("/upload-file", handleFileUpload)
	log.Println("🚀 Servidor en http://192.168.100.21:9090")
	r.Run(":9090")
}

func handleWebSocket(c *gin.Context) {
	userID := strings.TrimSpace(c.Query("user_id"))
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Println("❌ WS error:", err)
		return
	}
	clients[userID] = conn
	log.Println("✅ Cliente conectado:", userID)
	for {
		var msg map[string]interface{}
		err := conn.ReadJSON(&msg)
		if err != nil {
			delete(clients, userID)
			log.Println("❌ Cliente desconectado:", userID)
			break
		}
		msgType := fmt.Sprintf("%v", msg["type"])
		toUser := fmt.Sprintf("%v", msg["to"])

		// 🔥 Señalización WebRTC: reenvía offer, answer e ICE al destinatario
		if msgType == "offer" || msgType == "answer" || msgType == "ice" || msgType == "call" || msgType == "hangup" {
			msg["from"] = userID
			client, ok := clients[toUser]
			if ok {
				client.WriteJSON(msg)
				log.Printf("📡 [%s] %s → %s", msgType, userID, toUser)
			} else {
				log.Printf("⚠️ Usuario %s no conectado", toUser)
			}
			continue
		}

		// Mensajes normales de chat
		client, ok := clients[toUser]
		if ok {
			client.WriteJSON(msg)
		}
	}
}

func handleUpload(c *gin.Context) {
	file, _ := c.FormFile("file")
	ext := filepath.Ext(file.Filename)
	filename := fmt.Sprintf("./uploads/img_%d%s", time.Now().UnixNano(), ext)
	c.SaveUploadedFile(file, filename)
	name := filepath.Base(filename)
	url := "http://192.168.100.21:9090/uploads/" + name
	log.Println("📸 Imagen guardada:", name)
	c.JSON(http.StatusOK, gin.H{"url": url})
}

func handleAudioUpload(c *gin.Context) {
	file, err := c.FormFile("audio")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No audio"})
		return
	}
	ext := filepath.Ext(file.Filename)
	filename := fmt.Sprintf("./uploads/audio_%d%s", time.Now().UnixNano(), ext)
	c.SaveUploadedFile(file, filename)
	name := filepath.Base(filename)
	url := "http://192.168.100.21:9090/uploads/" + name
	log.Println("🎤 Audio guardado:", name)
	c.JSON(http.StatusOK, gin.H{"url": url})
}

func handleFileUpload(c *gin.Context) {
	file, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No file"})
		return
	}
	ext := filepath.Ext(file.Filename)
	filename := fmt.Sprintf("./uploads/file_%d%s", time.Now().UnixNano(), ext)
	c.SaveUploadedFile(file, filename)
	name := filepath.Base(filename)
	url := "http://192.168.100.21:9090/uploads/" + name
	log.Println("📎 Archivo guardado:", name, "| Original:", file.Filename)
	c.JSON(http.StatusOK, gin.H{
		"url":      url,
		"filename": file.Filename,
		"size":     file.Size,
	})
}
