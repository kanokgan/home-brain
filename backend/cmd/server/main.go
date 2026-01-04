package main

import (
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// Service health check helper
func checkServiceHealth(url string, timeout time.Duration) (bool, string) {
	client := &http.Client{Timeout: timeout}
	resp, err := client.Get(url)
	if err != nil {
		return false, err.Error()
	}
	defer resp.Body.Close()
	
	if resp.StatusCode == http.StatusOK {
		return true, "healthy"
	}
	return false, "unhealthy"
}

func main() {
	// 1. Setup Router
	r := gin.Default()

	// 2. Health Check Endpoint (Crucial for Kubernetes Probes)
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "alive",
			"version": "0.2.0",
			"system":  "home-brain",
		})
	})

	// 3. Service Status Endpoints
	r.GET("/api/services", func(c *gin.Context) {
		// Check Immich health
		immichHealthy, immichMsg := checkServiceHealth("http://immich-server.immich.svc.cluster.local/api/server-info/ping", 5*time.Second)
		
		// Check Jellyfin health
		jellyfinHealthy, jellyfinMsg := checkServiceHealth("http://jellyfin.jellyfin.svc.cluster.local:8096/health", 5*time.Second)
		
		c.JSON(http.StatusOK, gin.H{
			"timestamp": time.Now().UTC(),
			"services": gin.H{
				"immich": gin.H{
					"healthy": immichHealthy,
					"status":  immichMsg,
					"url":     "https://immich.kanokgan.com",
				},
				"jellyfin": gin.H{
					"healthy": jellyfinHealthy,
					"status":  jellyfinMsg,
					"url":     "https://jellyfin.kanokgan.com",
				},
			},
		})
	})

	// 4. Individual service health endpoints
	r.GET("/api/services/immich", func(c *gin.Context) {
		healthy, msg := checkServiceHealth("http://immich-server.immich.svc.cluster.local/api/server-info/ping", 5*time.Second)
		status := http.StatusOK
		if !healthy {
			status = http.StatusServiceUnavailable
		}
		c.JSON(status, gin.H{
			"service": "immich",
			"healthy": healthy,
			"status":  msg,
			"url":     "https://immich.kanokgan.com",
		})
	})

	r.GET("/api/services/jellyfin", func(c *gin.Context) {
		healthy, msg := checkServiceHealth("http://jellyfin.jellyfin.svc.cluster.local:8096/health", 5*time.Second)
		status := http.StatusOK
		if !healthy {
			status = http.StatusServiceUnavailable
		}
		c.JSON(status, gin.H{
			"service": "jellyfin",
			"healthy": healthy,
			"status":  msg,
			"url":     "https://jellyfin.kanokgan.com",
		})
	})

	// 5. Start Server
	log.Println("🧠 HomeBrain Backend starting on :8080...")
	if err := r.Run(":8080"); err != nil {
		log.Fatal("Server failed to start:", err)
	}
}
