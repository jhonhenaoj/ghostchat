package models

import "time"

type User struct {
	ID        string    `json:"id" db:"id"`
	Username  string    `json:"username" db:"username"`
	PublicKey string    `json:"public_key" db:"public_key"`
	CreatedAt time.Time `json:"created_at" db:"created_at"`
}
