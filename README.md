# FRP — Containerized Deployment

[![Docker Build & Push](https://github.com/DynamicKarabo/frp-deployment/actions/workflows/docker-build.yml/badge.svg)](https://github.com/DynamicKarabo/frp-deployment/actions/workflows/docker-build.yml)
[![GitHub Stars](https://img.shields.io/badge/dynamic/json?logo=github&label=stars&color=gold&query=stargazers_count&url=https%3A%2F%2Fapi.github.com%2Frepos%2Ffatedier%2Ffrp)](https://github.com/fatedier/frp)

**frp** (Fast Reverse Proxy) — **106k⭐** on GitHub. A high-performance reverse proxy for exposing local servers behind NAT or firewalls to the internet.

## Why This Deployment

The upstream [fatedier/frp](https://github.com/fatedier/frp) ships Dockerfiles in `dockerfiles/` using Node + Go multi-stage builds. This repo delivers a clean, unified deployment with CI/CD, GHCR push, and k3s manifests.

## Image Specs

| Property | Value |
|----------|-------|
| **Size** | **44.3MB** (Alpine 3.21 runtime) |
| **Base image** | `alpine:3.21` |
| **Go version** | 1.25 |
| **User** | Non-root (UID 10001) |
| **HEALTHCHECK** | Dashboard health endpoint |
| **Architecture** | x86_64, single-binary per target |

## Multi-Stage Build

The Dockerfile builds in 3 stages:

1. **Web builder** — Node 22 Alpine. Builds the Vue.js dashboard (npm workspaces pattern)
2. **Go builder** — Golang 1.25 Alpine. Builds the binary with embedded web assets
3. **Runtime** — Alpine 3.21. Only the binary + ca-certificates + tzdata

Build with a target selection arg:
```bash
docker build --build-arg TARGET=frps -t frp:latest .   # Server
docker build --build-arg TARGET=frpc -t frp:latest .   # Client
```

## Troubleshooting

### npm Workspace Lockfile

The web dashboard uses npm workspaces with a shared `package-lock.json` at the parent `web/` level. The initial Dockerfile tried to copy the lockfile from `web/frps/package-lock.json` which doesn't exist:

```
ERROR: failed to calculate checksum: "/src/web/frps/package-lock.json": not found
```

**Fix:** Restructured the web build stage to copy all workspace files from the root `web/` directory, then run `npm ci` and `--workspace=${TARGET}` build.

### Binary Name Path

The Go builder outputs to `/usr/local/bin/${TARGET}` (e.g., `frps` or `frpc`), not a generic `app` name. The runtime stage copies from the correct path using the same build arg.

## Deployment

### k3s

The k3s deployment runs frps with:
- NodePort :30700 (control port)
- NodePort :30750 (dashboard)
- ConfigMap-driven `frps.toml` config
- GHCR image pull via `ghcr-auth` secret

```bash
kubectl apply -f k8s/deployment.yaml
```

### Docker Compose

```bash
docker run -d --name frps -p 7000:7000 -p 7500:7500 ghcr.io/dynamickarabo/frp-deployment:latest
```

## CI/CD

Every push to `main` triggers the [Docker Build & Push](.github/workflows/docker-build.yml) workflow:
- Builds the Docker image with BuildKit layer caching
- Pushes to `ghcr.io/dynamickarabo/frp-deployment:latest`
- Also tags with the short commit SHA

Trigger a manual build with a custom target:
```bash
gh workflow run "Docker Build & Push" --repo DynamicKarabo/frp-deployment --ref main -f target=frpc
```

## Repo Structure

```
├── Dockerfile          # Multi-stage frp build
├── .dockerignore       # Excludes .git, test data, docs from build context
├── k8s/
│   └── deployment.yaml # k3s manifests (namespace, ConfigMap, deployment, service)
├── .github/
│   └── workflows/
│       └── docker-build.yml
├── src/                # Git submodule → DynamicKarabo/frp-fork
└── .gitmodules
```
