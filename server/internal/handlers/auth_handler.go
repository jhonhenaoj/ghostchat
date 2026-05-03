package handlers

import (
	"encoding/json"
	"log"
	"net/http"
	"time"

	"ghost-server/internal/db"
	"github.com/google/uuid"
)

// RequestRegistrationHandler genera un token de registro de un solo uso
func RequestRegistrationHandler(w http.ResponseWriter, r *http.Request) {
	// 1. Generar un token UUID único
	token := uuid.New()

	// 2. Establecer la fecha de expiración (60 segundos desde ahora)
	expiresAt := time.Now().Add(60 * time.Second)

	// 3. Insertar el token en la base de datos
	sqlStatement := `
	INSERT INTO registration_tokens (token, expires_at)
	VALUES ($1, $2);`
	
	_, err := db.DB.Exec(sqlStatement, token, expiresAt)
	if err != nil {
		log.Printf("Error al insertar token de registro: %v", err)
		http.Error(w, "Error interno del servidor", http.StatusInternalServerError)
		return
	}

	// 4. Devolver el token al cliente
	response := map[string]string{
		"registration_token": token.String(),
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}
