package handlers

import (
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"time"

	"ghost-server/internal/db"
	"github.com/google/uuid"
	"github.com/gorilla/mux"
	"github.com/lib/pq"
)

func RegisterUser(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RegistrationToken string `json:"registration_token"`
		PublicKey        string `json:"public_key"`
	}

	err := json.NewDecoder(r.Body).Decode(&req)
	if err != nil {
		http.Error(w, "JSON inválido", http.StatusBadRequest)
		return
	}

	if req.PublicKey == "" {
		http.Error(w, "public_key es requerido", http.StatusBadRequest)
		return
	}

	var tokenExpiresAt time.Time
	var tokenUsedAt *time.Time

	sqlStatement := `SELECT expires_at, used_at FROM registration_tokens WHERE token = $1;`
	err = db.DB.QueryRow(sqlStatement, uuid.MustParse(req.RegistrationToken)).Scan(&tokenExpiresAt, &tokenUsedAt)
	if err != nil {
		http.Error(w, "Token inválido o no encontrado", http.StatusUnauthorized)
		return
	}

	if tokenUsedAt != nil {
		http.Error(w, "Token ya ha sido usado", http.StatusUnauthorized)
		return
	}
	if time.Now().After(tokenExpiresAt) {
		http.Error(w, "Token ha expirado", http.StatusUnauthorized)
		return
	}

	userId := uuid.New()

	_, err = db.DB.Exec("UPDATE registration_tokens SET used_at = NOW() WHERE token = $1", uuid.MustParse(req.RegistrationToken))
	if err != nil {
		log.Printf("Error al marcar el token como usado: %v", err)
		http.Error(w, "Error interno del servidor", http.StatusInternalServerError)
		return
	}

	userInsertStatement := `INSERT INTO users (id, public_key) VALUES ($1, $2);`
	_, err = db.DB.Exec(userInsertStatement, userId, req.PublicKey)
	if err != nil {
		if pqErr, ok := err.(*pq.Error); ok && pqErr.Code == "23505" {
			http.Error(w, "Error de conflicto interno", http.StatusConflict)
		} else {
			log.Printf("Error registrando usuario: %v", err)
			http.Error(w, "Error al registrar usuario", http.StatusInternalServerError)
		}
		return
	}

	response := map[string]string{
		"user_id": userId.String(),
		"status":  "registered",
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(response)
}

// GetPublicKeyHandler devuelve la clave pública de un usuario anónimo
func GetPublicKeyHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	userId := vars["user_id"]

	if userId == "" {
		http.Error(w, "user_id es requerido", http.StatusBadRequest)
		return
	}

	var publicKey string
	sqlStatement := `SELECT public_key FROM users WHERE id = $1;`
	err := db.DB.QueryRow(sqlStatement, userId).Scan(&publicKey)
	if err != nil {
		if err == sql.ErrNoRows {
			http.Error(w, "Usuario no encontrado", http.StatusNotFound)
		} else {
			log.Printf("Error buscando clave pública: %v", err)
			http.Error(w, "Error interno del servidor", http.StatusInternalServerError)
		}
		return
	}

	response := map[string]string{
		"user_id":    userId,
		"public_key": publicKey,
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}
