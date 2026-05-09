# =============================================================================
# Multi-stage frp Dockerfile — supports both frps (server) and frpc (client)
# =============================================================================
# Build with: docker build --build-arg TARGET=frps -t frp:latest .
# or:         docker build --build-arg TARGET=frpc -t frp:latest .
# =============================================================================

# Stage 1: Build web dashboard (npm workspaces — shared, frps, frpc)
FROM node:26-alpine AS web-builder
ARG TARGET=frps
WORKDIR /web
COPY src/web/package.json src/web/package-lock.json ./
COPY src/web/shared/ ./shared/
COPY src/web/${TARGET}/ ./${TARGET}/
RUN npm ci && npm run build --workspace=${TARGET}

# Stage 2: Build Go binaries
FROM golang:1.25-alpine AS builder
ARG TARGET=frps
ARG LDFLAGS="-s -w"
RUN apk add --no-cache gcc musl-dev git
WORKDIR /build
COPY src/go.mod src/go.sum ./
RUN go mod download
COPY src/ ./
COPY --from=web-builder /web/${TARGET}/dist /build/web/${TARGET}/dist
RUN CGO_ENABLED=0 go build -trimpath -ldflags="${LDFLAGS}" -tags "${TARGET}" -o /usr/local/bin/${TARGET} ./cmd/${TARGET}

# Stage 3: Minimal runtime
FROM alpine:3.21
ARG TARGET=frps
RUN apk add --no-cache ca-certificates tzdata && \
    addgroup -g 10001 -S app && \
    adduser -u 10001 -S -G app app

COPY --from=builder /usr/local/bin/${TARGET} /usr/local/bin/app

# Default ports for frps: 7000 (control), 7500 (dashboard)
# For frpc: ephemeral outbound ports (no need to expose)
EXPOSE 7000 7500

USER app
WORKDIR /app

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:7400/health 2>/dev/null || exit 1

LABEL org.opencontainers.image.title="frp" \
      org.opencontainers.image.description="Fast Reverse Proxy" \
      org.opencontainers.image.version="0.69.0" \
      org.opencontainers.image.source="https://github.com/DynamicKarabo/frp-deployment"

ENTRYPOINT ["/usr/local/bin/app"]
