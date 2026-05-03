package handlers

import (
	"encoding/json"
	"log"
	"net/http"
	"time"

	"ghost-server/internal/db"
)

func SendMessageHandler(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RecipientID string `json:"recipient_id"`
		Payload     string `json:"payload"`
	}

	err := json.NewDecoder(r.Body).Decode(&req)
	if err != nil {
		http.Error(w, "JSON inválido", http.StatusBadRequest)
		return
	}

	if req.RecipientID == "" || req.Payload == "" {
		http.Error(w, "recipient_id y payload son requeridos", http.StatusBadRequest)
		return
	}

	var exists bool
	err = db.DB.QueryRow("SELECT EXISTS(SELECT 1 FROM users WHERE id = $1)", req.RecipientID).Scan(&exists)
	if err != nil || !exists {
		http.Error(w, "Destinatario no encontrado", http.StatusNotFound)
		return
	}

	sqlStatement := `
	INSERT INTO messages (recipient_id, payload)
	VALUES ($1, $2);`
	
	_, err = db.DB.Exec(sqlStatement, req.RecipientID, req.Payload)
	if err != nil {
		log.Printf("Error al guardar el mensaje: %v", err)
		http.Error(w, "Error interno del servidor", http.StatusInternalServerError)
		return
	}

	response := map[string]string{
		"status": "delivered",
	}
	
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

func FetchMessagesHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	if userID == "" {
		http.Error(w, "Header X-User-ID es requerido", http.StatusBadRequest)
		return
	}

	rows, err := db.DB.Query(`
		SELECT id, payload, created_at 
		FROM messages 
		WHERE recipient_id = $1 AND read = FALSE 
		ORDER BY created_at ASC`, userID)
	if err != nil {
		log.Printf("Error buscando mensajes: %v", err)
		http.Error(w, "Error interno del servidor", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	_, err = db.DB.Exec("UPDATE messages SET read = TRUE WHERE recipient_id = $1 AND read = FALSE", userID)
	if err != nil {
		log.Printf("Error marcando mensajes como leídos: %v", err)
	}

	var messages []map[string]interface{}
	for rows.Next() {
		var id, payload string
		var createdAt time.Time
		if err := rows.Scan(&id, &payload, &createdAt); err != nil {
			log.Printf("Error escaneando mensaje: %v", err)
			continue
		}
		messages = append(messages, map[string]interface{}{
			"id":         id,
			"payload":    payload,
			"created_at": createdAt,
		})
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(messages)
}
