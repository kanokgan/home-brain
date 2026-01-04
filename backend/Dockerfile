# Multi-arch Build Stage
FROM --platform=$BUILDPLATFORM golang:1.24-alpine AS builder

ARG TARGETOS
ARG TARGETARCH

WORKDIR /app

# Cache dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy source
COPY . .

# Build API for target platform (Static binary)
# CGO_ENABLED=0 ensures it runs on any Linux distro (Alpine/Ubuntu/Scratch)
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -ldflags="-w -s" -o home-brain-api ./cmd/server

# Run Stage (Distroless for security - smaller than Alpine)
FROM --platform=$TARGETPLATFORM gcr.io/distroless/static-debian12

WORKDIR /root/

COPY --from=builder /app/home-brain-api .

EXPOSE 8080

CMD ["./home-brain-api"]