package db

import (
	"database/sql"
	"fmt"
	"log"

	_ "github.com/lib/pq"
)

var DB *sql.DB

// InitDB se conecta a la base de datos y la asigna a la variable global DB.
// No crea ni borra tablas, solo establece la conexión.
func InitDB() {
	var err error
	// Conexión usando el usuario y la base de datos que configuramos
	connStr := "user=ghost_app_user password=mi_password_123 dbname=ghostdb host=localhost sslmode=disable"
	DB, err = sql.Open("postgres", connStr)
	if err != nil {
		log.Fatal("No se puede conectar a la base de datos:", err)
	}

	err = DB.Ping()
	if err != nil {
		log.Fatal("No se puede hacer ping a la base de datos:", err)
	}

	fmt.Println("¡Conectado exitosamente a la base de datos desde db.go!")
}
