package main

import (
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
)

func main() {
	// 1. Setup Router
	r := gin.Default()

	// 2. Health Check Endpoint (Crucial for Kubernetes Probes)
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "alive",
			"version": "0.1.0",
			"system":  "home-brain",
		})
	})

	// 3. Start Server
	log.Println("🧠 HomeBrain Backend starting on :8080...")
	if err := r.Run(":8080"); err != nil {
		log.Fatal("Server failed to start:", err)
	}
}
