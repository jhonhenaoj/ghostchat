package main

import (
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"sync"

	"golang.org/x/crypto/nacl/box"
)

// userKeyStore almacena las claves públicas de los usuarios registrados.
var (
	userKeyStore = make(map[string][32]byte)
	keyMutex     sync.RWMutex
)

// registerRequest es la estructura del JSON que esperamos en el endpoint /register.
type registerRequest struct {
	UserID      string `json:"user_id"`
	PublicKeyB64 string `json:"public_key"`
}

// registerHandler maneja las peticiones POST para registrar un nuevo usuario y su clave pública.
func registerHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Método no permitido", http.StatusMethodNotAllowed)
		return
	}

	var req registerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "JSON inválido", http.StatusBadRequest)
		return
	}

	// Decodificar la clave pública desde Base64.
	publicKeyBytes, err := base64.StdEncoding.DecodeString(req.PublicKeyB64)
	if err != nil || len(publicKeyBytes) != 32 {
		http.Error(w, "Clave pública inválida", http.StatusBadRequest)
		return
	}

	var publicKey [32]byte
	copy(publicKey[:], publicKeyBytes)

	// Guardar la clave de forma segura en el mapa.
	keyMutex.Lock()
	userKeyStore[req.UserID] = publicKey
	keyMutex.Unlock()

	log.Printf("Usuario %s registrado con éxito.", req.UserID)
	w.WriteHeader(http.StatusCreated)
	fmt.Fprintf(w, "Usuario %s registrado con éxito.", req.UserID)
}

// getKeyHandler maneja las peticiones GET para obtener la clave pública de un usuario.
func getKeyHandler(w http.ResponseWriter, r *http.Request) {
	// Extraer el ID del usuario de la URL.
	pathParts := strings.Split(r.URL.Path, "/")
	if len(pathParts) < 3 || pathParts[2] == "" {
		http.Error(w, "ID de usuario no proporcionado", http.StatusBadRequest)
		return
	}
	userID := pathParts[2]

	// Obtener la clave de forma segura del mapa.
	keyMutex.RLock()
	publicKey, found := userKeyStore[userID]
	keyMutex.RUnlock()

	if !found {
		http.Error(w, "Usuario no encontrado", http.StatusNotFound)
		return
	}

	// Devolver la clave pública codificada en Base64.
	response := map[string]string{
		"user_id":    userID,
		"public_key": base64.StdEncoding.EncodeToString(publicKey[:]),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func main() {
	// Esto "usa" la librería para silenciar el error del compilador hasta que la implementemos.
	var _ = box.Seal

	// Cargar el certificado y la clave autofirmados.
	cert, err := tls.LoadX509KeyPair("cert.pem", "key.pem")
	if err != nil {
		log.Fatal("Error cargando certificados: ", err)
	}

	// Configurar TLS para cifrado fuerte y compatibilidad con HTTP/2.
	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{cert},
		MinVersion:   tls.VersionTLS12,
		CipherSuites: []uint16{
			tls.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
			tls.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
			tls.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
		},
	}

	// Crear el servidor con nuestra configuración TLS personalizada.
	server := &http.Server{
		Addr:      ":8443",
		TLSConfig: tlsConfig,
	}

	// Registrar los endpoints de nuestra API.
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "¡Bienvenido al backend fantasma de la app segura!")
	})
	http.HandleFunc("/register", registerHandler)
	http.HandleFunc("/key/", getKeyHandler)

	// Iniciar el servidor de forma segura.
	fmt.Println("Servidor fantasma seguro escuchando en https://localhost:8443")
	log.Fatal(server.ListenAndServeTLS("", "")) // Los certificados ya están cargados en tlsConfig.
}
