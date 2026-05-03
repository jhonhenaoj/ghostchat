package models

import "time"

type Message struct {
	ID           string    `json:"id" db:"id"`
	SenderID     string    `json:"sender_id" db:"sender_id"`
	RecipientID  string    `json:"recipient_id" db:"recipient_id"`
	CipherText   string    `json:"cipher_text" db:"cipher_text"` // Contenido del mensaje cifrado
	CreatedAt    time.Time `json:"created_at" db:"created_at"`
	Read         bool      `json:"read" db:"read"`
}

type ChatPreview struct {
	ContactID     string    `json:"contact_id"`
	ContactName   string    `json:"contact_name"`
	LastMessage   string    `json:"last_message"`
	LastMessageAt time.Time `json:"last_message_at"`
}
