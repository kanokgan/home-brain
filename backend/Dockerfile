# Build Stage
FROM golang:1.23-alpine AS builder

WORKDIR /app

# Cache dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy source
COPY . .

# Build API (Static binary)
# CGO_ENABLED=0 ensures it runs on any Linux distro (Alpine/Ubuntu/Scratch)
RUN CGO_ENABLED=0 GOOS=linux go build -o home-brain-api ./cmd/server

# Run Stage (Distroless for security - smaller than Alpine)
FROM gcr.io/distroless/static-debian12

WORKDIR /root/

COPY --from=builder /app/home-brain-api .

EXPOSE 8080

CMD ["./home-brain-api"]