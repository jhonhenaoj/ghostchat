package main

import (
	"crypto/tls"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

func handler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintln(w, "GhostChat OK")
}

func main() {
	http.HandleFunc("/", handler)

	certFile := "cert.pem"
	keyFile := "key.pem"

	// validar certificados
	if _, err := os.Stat(certFile); err != nil {
		log.Fatal("missing cert.pem")
	}
	if _, err := os.Stat(keyFile); err != nil {
		log.Fatal("missing key.pem")
	}

	// 🔥 SERVER PRODUCCIÓN
	server := &http.Server{
		Addr: "127.0.0.1:8443", // 👈 CLAVE: SOLO LOCAL

		Handler: http.DefaultServeMux,

		// 🧠 estabilidad (anti crash / anti freeze)
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,

		// 🔐 TLS seguro mínimo
		TLSConfig: &tls.Config{
			MinVersion: tls.VersionTLS12,
		},
	}

	log.Println("🚀 GhostChat running on 127.0.0.1:8443")

	err := server.ListenAndServeTLS(certFile, keyFile)
	if err != nil {
		log.Fatal(err)
	}
}
