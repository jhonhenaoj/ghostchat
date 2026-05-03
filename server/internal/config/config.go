package config

import (
	"os"
)

type Config struct {
	Port            string
	DBHost          string
	DBPort          string
	DBUser          string
	DBPassword      string
	DBName          string
}

func LoadConfig() Config {
	return Config{
		Port:       getEnv("PORT", "8080"),
		DBHost:     getEnv("DB_HOST", "localhost"),
		DBPort:     getEnv("DB_PORT", "5432"),
		DBUser:     getEnv("DB_USER", "ghostuser"),
		DBPassword: getEnv("DB_PASSWORD", "Comcel10."), // ¡CAMBIA ESTO si usaste otra!
		DBName:     getEnv("DB_NAME", "ghostdb"),
	}
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}
