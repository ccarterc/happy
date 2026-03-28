#!/usr/bin/env bash
#
# setup-https-proxy.sh — HTTPS reverse proxy for self-hosted Happy Server
#
# Sets up a Caddy reverse proxy with a self-signed certificate so that mobile
# apps (Android Play Store, iOS App Store) can connect over HTTPS. Android
# blocks cleartext HTTP by default, so HTTPS is required when self-hosting.
#
# Usage:
#   ./setup-https-proxy.sh [OPTIONS]
#
# Options:
#   --ip <IP>             LAN IP address (auto-detected if omitted)
#   --port <PORT>         HTTPS port to expose (default: 443)
#   --backend <HOST:PORT> Happy Server backend (default: happy-server:3005)
#   --cert-dir <DIR>      Where to store certs (default: ./certs)
#   --cert-days <DAYS>    Certificate validity in days (default: 3650)
#   --network <NAME>      Docker network name (default: happy-net)
#   --container <NAME>    Proxy container name (default: happy-proxy)
#   --server-container <NAME>  Happy Server container to connect to network
#                              (default: happy-server)
#   --dry-run             Print what would be done without executing
#   --help                Show this help message
#
# Examples:
#   # Auto-detect IP, use defaults:
#   ./setup-https-proxy.sh
#
#   # Specify IP and custom port:
#   ./setup-https-proxy.sh --ip 192.168.1.100 --port 8443
#
#   # Just regenerate certs (stop proxy first, then re-run):
#   docker stop happy-proxy && docker rm happy-proxy
#   ./setup-https-proxy.sh

set -euo pipefail

# Defaults
IP=""
PORT=443
BACKEND="happy-server:3005"
CERT_DIR="./certs"
CERT_DAYS=3650
NETWORK="happy-net"
CONTAINER="happy-proxy"
SERVER_CONTAINER="happy-server"
DRY_RUN=false

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

usage() {
    sed -n '/^# Usage:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ip)             IP="$2"; shift 2 ;;
        --port)           PORT="$2"; shift 2 ;;
        --backend)        BACKEND="$2"; shift 2 ;;
        --cert-dir)       CERT_DIR="$2"; shift 2 ;;
        --cert-days)      CERT_DAYS="$2"; shift 2 ;;
        --network)        NETWORK="$2"; shift 2 ;;
        --container)      CONTAINER="$2"; shift 2 ;;
        --server-container) SERVER_CONTAINER="$2"; shift 2 ;;
        --dry-run)        DRY_RUN=true; shift ;;
        --help|-h)        usage ;;
        *)                die "Unknown option: $1" ;;
    esac
done

# Auto-detect LAN IP if not provided
if [[ -z "$IP" ]]; then
    IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    [[ -n "$IP" ]] || die "Could not auto-detect LAN IP. Use --ip <IP>."
fi

info "LAN IP: $IP"
info "HTTPS port: $PORT"
info "Backend: $BACKEND"
info "Cert dir: $CERT_DIR"

# Check prerequisites
command -v docker >/dev/null 2>&1 || die "Docker is required but not installed."
command -v openssl >/dev/null 2>&1 || die "OpenSSL is required but not installed."

if $DRY_RUN; then
    info "[dry-run] Would generate cert for IP $IP in $CERT_DIR"
    info "[dry-run] Would create Docker network $NETWORK"
    info "[dry-run] Would connect $SERVER_CONTAINER to $NETWORK"
    info "[dry-run] Would start Caddy container $CONTAINER on port $PORT"
    exit 0
fi

# Check if proxy container already exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    die "Container '$CONTAINER' already exists. Stop and remove it first:\n  docker stop $CONTAINER && docker rm $CONTAINER"
fi

# Generate self-signed certificate
info "Generating self-signed certificate..."
mkdir -p "$CERT_DIR"
openssl req -x509 -newkey rsa:2048 -nodes -sha256 \
    -keyout "$CERT_DIR/server.key" \
    -out "$CERT_DIR/server.crt" \
    -days "$CERT_DAYS" \
    -subj "/CN=Happy Server Local" \
    -addext "subjectAltName=IP:$IP" \
    2>/dev/null

# Copy cert with a friendly name for installing on devices
cp "$CERT_DIR/server.crt" "$CERT_DIR/happy-server-ca.crt"

CERT_DIR_ABS=$(cd "$CERT_DIR" && pwd)
info "Certificate generated: $CERT_DIR_ABS/server.crt"

# Write Caddyfile
CADDYFILE="$CERT_DIR_ABS/Caddyfile"
cat > "$CADDYFILE" <<CADDY
:443 {
    tls /certs/server.crt /certs/server.key
    reverse_proxy $BACKEND
}
CADDY
info "Caddyfile written: $CADDYFILE"

# Create Docker network (ignore if exists)
docker network create "$NETWORK" 2>/dev/null || true

# Connect happy-server to network (ignore if already connected)
if docker ps --format '{{.Names}}' | grep -q "^${SERVER_CONTAINER}$"; then
    docker network connect "$NETWORK" "$SERVER_CONTAINER" 2>/dev/null || true
    info "Connected $SERVER_CONTAINER to network $NETWORK"
else
    echo "WARNING: Container '$SERVER_CONTAINER' is not running."
    echo "         Start it and connect manually: docker network connect $NETWORK $SERVER_CONTAINER"
fi

# Start Caddy reverse proxy
info "Starting Caddy HTTPS reverse proxy..."
docker run -d \
    --name "$CONTAINER" \
    --restart unless-stopped \
    --network "$NETWORK" \
    -p "${PORT}:443" \
    -v "$CADDYFILE:/etc/caddy/Caddyfile:ro" \
    -v "$CERT_DIR_ABS:/certs:ro" \
    caddy:2

# Wait and verify
sleep 3
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    info "Caddy proxy is running."
else
    die "Caddy container failed to start. Check: docker logs $CONTAINER"
fi

# Test connectivity
HTTPS_URL="https://$IP$([ "$PORT" = "443" ] && echo "" || echo ":$PORT")"
if curl -sk "$HTTPS_URL/health" 2>/dev/null | grep -q '"ok"'; then
    info "HTTPS proxy verified: $HTTPS_URL"
else
    echo "WARNING: Could not verify $HTTPS_URL/health"
    echo "         The proxy is running but the backend may not be ready yet."
fi

echo ""
echo "============================================"
echo "  HTTPS proxy ready: $HTTPS_URL"
echo "============================================"
echo ""
echo "Next steps:"
echo ""
echo "1. CONFIGURE THE CLI"
echo "   Add to your shell profile (~/.bashrc or ~/.zshrc):"
echo "     export HAPPY_SERVER_URL=$HTTPS_URL"
echo "     export NODE_EXTRA_CA_CERTS=$CERT_DIR_ABS/server.crt"
echo ""
echo "2. INSTALL CA CERT ON YOUR PHONE"
echo "   Transfer this file to your phone:"
echo "     $CERT_DIR_ABS/happy-server-ca.crt"
echo ""
echo "   Quick method — serve it over HTTP and download on phone:"
echo "     python3 -m http.server 8080 -d $CERT_DIR_ABS"
echo "     Then open http://$IP:8080/happy-server-ca.crt on your phone."
echo ""
echo "   Android: Settings > Security > Encryption & credentials"
echo "            > Install a certificate > CA certificate"
echo ""
echo "   iOS: Open the .crt file > Install Profile > Settings"
echo "         > General > About > Certificate Trust Settings > Enable"
echo ""
echo "3. CONFIGURE THE MOBILE APP"
echo "   In the Happy app, go to the server config screen and enter:"
echo "     $HTTPS_URL"
echo ""
