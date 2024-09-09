package main

import (
	"flag"
	"io"
	"log"
	"net"
)

func main() {
	// Parse command-line arguments for proxy and target addresses
	proxyAddr := flag.String("proxy", "127.1.1.1:1111", "Address to listen on (e.g., localhost:8080)")
	targetAddr := flag.String("target", "127.2.2.2:2222", "Target address to forward traffic to (e.g., example.com:80)")
	flag.Parse()

	// Start listening for incoming connections
	listener, err := net.Listen("tcp", *proxyAddr)
	if err != nil {
		log.Fatalf("Failed to listen on %s: %v", *proxyAddr, err)
	}
	defer listener.Close()
	log.Printf("Proxy started on %s, forwarding to %s", *proxyAddr, *targetAddr)

	for {
		// Accept an incoming connection
		clientConn, err := listener.Accept()
		if err != nil {
			log.Printf("Failed to accept connection: %v", err)
			continue
		}
		// Handle the connection in a new goroutine
		go handleConnection(clientConn, *targetAddr)
	}
}

func handleConnection(clientConn net.Conn, targetAddr string) {
	defer clientConn.Close()

	// Connect to the target server
	targetConn, err := net.Dial("tcp", targetAddr)
	if err != nil {
		log.Printf("Failed to connect to target %s: %v", targetAddr, err)
		return
	}
	defer targetConn.Close()

	// Channel data between client and target
	go func() {
		// Copy data from client to target
		if _, err := io.Copy(targetConn, clientConn); err != nil {
			log.Printf("Error copying data from client to target: %v", err)
		}
		clientConn.Close()
		targetConn.Close()
	}()

	// Copy data from target to client
	if _, err := io.Copy(clientConn, targetConn); err != nil {
		log.Printf("Error copying data from target to client: %v", err)
	}
}
