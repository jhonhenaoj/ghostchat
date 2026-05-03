package websocket

import (
	"encoding/json"
	"log"

	"github.com/gorilla/websocket"
)

// Estructura del mensaje que se enviará por WebSocket
type Message struct {
	SenderID    string `json:"sender_id"`
	RecipientID string `json:"recipient_id"`
	Payload     string `json:"payload"`
	Timestamp   string `json:"timestamp"`
}

// El Hub gestiona todas las conexiones de cliente activas
type Hub struct {
	// Clientes registrados. La clave es el ID de usuario.
	clients map[string]*Client

	// Peticiones de registro de clientes (PÚBLICO)
	Register chan *Client

	// Peticiones de desregistro de clientes (PÚBLICO)
	Unregister chan *Client

	// Mensajes entrantes de los clientes (PÚBLICO)
	Broadcast chan []byte
}

// El Client representa una conexión WebSocket
type Client struct {
	// Hub, Conn, UserID y Send son PÚBLICOS
	Hub    *Hub
	Conn   *websocket.Conn
	UserID string
	Send   chan []byte
}

// Constructor del Hub
func NewHub() *Hub {
	return &Hub{
		clients:    make(map[string]*Client),
		Register:   make(chan *Client), // Canal público
		Unregister: make(chan *Client), // Canal público
		Broadcast:  make(chan []byte),  // Canal público
	}
}

// El bucle principal del Hub, se ejecuta en su propia goroutine
// MÉTODO PÚBLICO
func (h *Hub) Run() {
	for {
		select {
		case client := <-h.Register: // Usamos canal público
			h.clients[client.UserID] = client
			log.Printf("Cliente registrado: %s. Total conectados: %d", client.UserID, len(h.clients))

		case client := <-h.Unregister: // Usamos canal público
			if _, ok := h.clients[client.UserID]; ok {
				delete(h.clients, client.UserID)
				close(client.Send)
				log.Printf("Cliente desconectado: %s. Total conectados: %d", client.UserID, len(h.clients))
			}

		case message := <-h.Broadcast: // Usamos canal público
			// Decodificamos el mensaje para saber a quién enviarlo
			var msg Message
			json.Unmarshal(message, &msg)

			// Buscamos al destinatario y le enviamos el mensaje
			if recipientClient, ok := h.clients[msg.RecipientID]; ok {
				select {
				case recipientClient.Send <- message:
					log.Printf("Mensaje enviado de %s a %s", msg.SenderID, msg.RecipientID)
				default:
					// El canal está bloqueado, el cliente no recibe
					log.Printf("Error: no se pudo enviar el mensaje a %s, canal bloqueado.", msg.RecipientID)
					close(recipientClient.Send)
					delete(h.clients, recipientClient.UserID)
				}
			} else {
				log.Printf("Error: destinatario %s no encontrado.", msg.RecipientID)
			}
		}
	}
}

// Bucle que lee mensajes del cliente
// MÉTODO PÚBLICO
func (c *Client) ReadPump() {
	defer func() {
		c.Hub.Unregister <- c // Usamos canal público
		c.Conn.Close()
	}()
	for {
		_, message, err := c.Conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("Error: %v", err)
			}
			break
		}
		// Cuando recibimos un mensaje, lo pasamos al hub para que lo distribuya
		c.Hub.Broadcast <- message // Usamos canal público
	}
}

// Bucle que escribe mensajes al cliente
// MÉTODO PÚBLICO
func (c *Client) WritePump() {
	defer c.Conn.Close()
	for {
		select {
		case message, ok := <-c.Send:
			if !ok {
				// El hub cerró el canal
				c.Conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			c.Conn.WriteMessage(websocket.TextMessage, message)
		}
	}
}
