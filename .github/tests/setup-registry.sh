#!/bin/bash
set -e

# Setup Docker Registry with authentication and TLS for testing
# Uses nginx as HTTP reverse proxy to work around docker manifest push bug
# (docker manifest push incorrectly uses HTTP even when HTTPS is configured)
#
# Architecture:
#   Docker CLI -> nginx (HTTP, port 5000) -> Registry (HTTPS, port 443)
#
# Environment variables:
#   REGISTRY_PORT - Port for nginx proxy (default: 5000)
#   REGISTRY_USERNAME - Username for registry auth (default: testuser)
#   REGISTRY_PASSWORD - Password for registry auth (default: testpass)
#   REGISTRY_HOSTNAME - Hostname for the registry (default: registry.strimzi)

REGISTRY_PORT="${REGISTRY_PORT:-5000}"
REGISTRY_INTERNAL_PORT="443"
REGISTRY_USERNAME="${REGISTRY_USERNAME:-testuser}"
REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-testpass}"
REGISTRY_HOSTNAME="${REGISTRY_HOSTNAME:-registry.strimzi}"
REGISTRY_URL="${REGISTRY_HOSTNAME}:${REGISTRY_PORT}"
REGISTRY_INTERNAL_URL="${REGISTRY_HOSTNAME}:${REGISTRY_INTERNAL_PORT}"
REGISTRY_IMAGE="${REGISTRY_IMAGE:-"registry:3"}"

echo ">>> Setting up Docker Registry with nginx HTTP proxy..."
echo "Registry URL (external): $REGISTRY_URL (HTTP via nginx)"
echo "Registry URL (internal): $REGISTRY_INTERNAL_URL (HTTPS)"
echo "Username: $REGISTRY_USERNAME"

# Detect container runtime (podman or docker)
if command -v docker &> /dev/null; then
    CONTAINER_CMD="docker"
    echo "Using docker"
elif command -v podman &> /dev/null; then
    CONTAINER_CMD="podman"
    echo "Using podman"
else
    echo "❌ Neither podman nor docker found"
    exit 1
fi

# Add hostname to /etc/hosts
echo ">>> Adding ${REGISTRY_HOSTNAME} to /etc/hosts..."
echo "127.0.0.1 ${REGISTRY_HOSTNAME}" | sudo tee -a /etc/hosts > /dev/null
echo "✓ Hostname added to /etc/hosts"

# Configure Docker daemon with insecure-registries for the HTTP nginx endpoint
echo ">>> Configuring Docker daemon with insecure-registries for HTTP endpoint..."
DAEMON_JSON="/etc/docker/daemon.json"
if [ -f "$DAEMON_JSON" ]; then
    EXISTING=$(cat "$DAEMON_JSON")
    if echo "$EXISTING" | jq -e '.["insecure-registries"]' >/dev/null 2>&1; then
        echo "$EXISTING" | jq --arg reg "$REGISTRY_URL" '.["insecure-registries"] += [$reg] | .["insecure-registries"] |= unique' | sudo tee "$DAEMON_JSON" > /dev/null
    else
        echo "$EXISTING" | jq --arg reg "$REGISTRY_URL" '. + {"insecure-registries": [$reg]}' | sudo tee "$DAEMON_JSON" > /dev/null
    fi
else
    echo "{\"insecure-registries\": [\"$REGISTRY_URL\"]}" | sudo tee "$DAEMON_JSON" > /dev/null
fi
echo "✓ Docker daemon.json configured for HTTP endpoint"
cat "$DAEMON_JSON"

# Create auth and certs directories
AUTH_DIR=$(mktemp -d)
CERTS_DIR=$(mktemp -d)
echo "Auth directory: $AUTH_DIR"
echo "Certs directory: $CERTS_DIR"

# Generate self-signed certificate for the registry hostname
echo ">>> Generating self-signed TLS certificate for ${REGISTRY_HOSTNAME}..."
openssl req -newkey rsa:4096 -nodes -sha256 \
    -keyout "$CERTS_DIR/domain.key" \
    -x509 -days 365 \
    -out "$CERTS_DIR/domain.crt" \
    -subj "/CN=${REGISTRY_HOSTNAME}" \
    -addext "subjectAltName=DNS:${REGISTRY_HOSTNAME},IP:127.0.0.1" 2>/dev/null

if [ ! -s "$CERTS_DIR/domain.crt" ]; then
    echo "❌ Failed to generate TLS certificate"
    exit 1
fi
echo "✓ TLS certificate generated"

# Trust the certificate on the system
echo ">>> Installing certificate to system trust store..."
if [ -d "/usr/local/share/ca-certificates" ]; then
    # Debian/Ubuntu
    sudo cp "$CERTS_DIR/domain.crt" /usr/local/share/ca-certificates/${REGISTRY_HOSTNAME}.crt
    sudo update-ca-certificates
elif [ -d "/etc/pki/ca-trust/source/anchors" ]; then
    # RHEL/CentOS/Fedora
    sudo cp "$CERTS_DIR/domain.crt" /etc/pki/ca-trust/source/anchors/${REGISTRY_HOSTNAME}.crt
    sudo update-ca-trust
else
    echo "⚠ Could not find system CA directory, skipping system trust"
fi

# Configure Docker to trust the certificate (for both internal registry and nginx)
echo ">>> Configuring Docker to trust the registry certificate..."
sudo mkdir -p "/etc/docker/certs.d/${REGISTRY_INTERNAL_URL}"
sudo cp "$CERTS_DIR/domain.crt" "/etc/docker/certs.d/${REGISTRY_INTERNAL_URL}/ca.crt"
sudo mkdir -p "/etc/docker/certs.d/${REGISTRY_URL}"
sudo cp "$CERTS_DIR/domain.crt" "/etc/docker/certs.d/${REGISTRY_URL}/ca.crt"
echo "✓ Docker configured to trust registry certificate"

# Restart Docker daemon to pick up the certificate configuration
if [ "$CONTAINER_CMD" = "docker" ]; then
    echo ">>> Restarting Docker daemon to apply certificate configuration..."
    sudo systemctl restart docker

    # Wait for Docker to be ready
    echo ">>> Waiting for Docker daemon to be ready..."
    DOCKER_TIMEOUT=30
    DOCKER_ELAPSED=0
    while [ $DOCKER_ELAPSED -lt $DOCKER_TIMEOUT ]; do
        if docker info >/dev/null 2>&1; then
            echo "✓ Docker daemon restarted and ready"
            break
        fi
        sleep 1
        DOCKER_ELAPSED=$((DOCKER_ELAPSED + 1))
    done
    if [ $DOCKER_ELAPSED -ge $DOCKER_TIMEOUT ]; then
        echo "❌ Docker daemon failed to restart within ${DOCKER_TIMEOUT} seconds"
        exit 1
    fi
fi

# Generate htpasswd file
echo ">>> Generating htpasswd file..."
$CONTAINER_CMD run --rm --entrypoint htpasswd \
    httpd:2 -Bbn "$REGISTRY_USERNAME" "$REGISTRY_PASSWORD" > "$AUTH_DIR/htpasswd"

if [ ! -s "$AUTH_DIR/htpasswd" ]; then
    echo "❌ Failed to generate htpasswd file"
    exit 1
fi

echo "✓ htpasswd file generated"

# Stop and remove existing registry container if it exists
if $CONTAINER_CMD ps -a --format '{{.Names}}' | grep -q "^test-registry$"; then
    echo ">>> Stopping existing registry container..."
    $CONTAINER_CMD stop test-registry || true
    $CONTAINER_CMD rm test-registry || true
fi

# Start registry with authentication and TLS on internal port
echo ">>> Starting Docker Registry with TLS on port ${REGISTRY_INTERNAL_PORT}..."
$CONTAINER_CMD run -d \
    --name test-registry \
    -p ${REGISTRY_INTERNAL_PORT}:443 \
    -v "$AUTH_DIR:/auth" \
    -v "$CERTS_DIR:/certs" \
    -e REGISTRY_AUTH=htpasswd \
    -e REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm" \
    -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
    -e REGISTRY_HTTP_ADDR=0.0.0.0:443 \
    -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
    -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
    ${REGISTRY_IMAGE}

# Wait for registry to be ready
echo ">>> Waiting for registry to be ready..."
TIMEOUT=60
ELAPSED=0
INTERVAL=2

while [ $ELAPSED -lt $TIMEOUT ]; do
    # Check with authentication since registry requires it (using HTTPS)
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --cacert "$CERTS_DIR/domain.crt" -u "${REGISTRY_USERNAME}:${REGISTRY_PASSWORD}" "https://${REGISTRY_INTERNAL_URL}/v2/" 2>/dev/null || echo "000")

    if [ "$HTTP_CODE" = "200" ]; then
        echo "✓ Registry is ready and accepting authenticated HTTPS requests"
        break
    fi

    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
    echo "Waiting... (${ELAPSED}s/${TIMEOUT}s) [HTTP $HTTP_CODE]"
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo "❌ Registry failed to start within ${TIMEOUT} seconds"
    $CONTAINER_CMD logs test-registry
    exit 1
fi

# Create nginx configuration with protocol detection (HTTP and HTTPS on same port)
# This works around docker manifest bugs where create needs HTTPS but push sends HTTP
echo ">>> Setting up nginx with protocol detection..."
NGINX_CONF_DIR=$(mktemp -d)

# Copy certificates to nginx config dir
cp "$CERTS_DIR/domain.crt" "$NGINX_CONF_DIR/"
cp "$CERTS_DIR/domain.key" "$NGINX_CONF_DIR/"

cat > "$NGINX_CONF_DIR/nginx.conf" << 'NGINX_EOF'
# Protocol detection: route HTTP and HTTPS to different backends
stream {
    upstream https_backend {
        server 127.0.0.1:5001;
    }

    upstream http_backend {
        server 127.0.0.1:5002;
    }

    map $ssl_preread_protocol $upstream {
        default https_backend;
        "" http_backend;
    }

    server {
        listen 5000;
        proxy_pass $upstream;
        ssl_preread on;
    }
}

events {
    worker_connections 1024;
}

http {
    upstream registry {
        server REGISTRY_HOSTNAME:REGISTRY_INTERNAL_PORT;
    }

    # HTTPS server (receives TLS connections)
    server {
        listen 5001 ssl;
        server_name REGISTRY_HOSTNAME;

        ssl_certificate /etc/nginx/domain.crt;
        ssl_certificate_key /etc/nginx/domain.key;

        client_max_body_size 0;
        chunked_transfer_encoding on;

        location /v2/ {
            proxy_pass https://registry;
            proxy_ssl_verify off;
            proxy_set_header Host $host:REGISTRY_PORT;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_read_timeout 900;
            proxy_buffering off;
        }
    }

    # HTTP server (receives plain HTTP connections)
    server {
        listen 5002;
        server_name REGISTRY_HOSTNAME;

        client_max_body_size 0;
        chunked_transfer_encoding on;

        location /v2/ {
            proxy_pass https://registry;
            proxy_ssl_verify off;
            proxy_set_header Host $host:REGISTRY_PORT;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto http;
            proxy_read_timeout 900;
            proxy_buffering off;
        }
    }
}
NGINX_EOF

# Replace placeholders in nginx config
sed -i "s/REGISTRY_HOSTNAME/${REGISTRY_HOSTNAME}/g" "$NGINX_CONF_DIR/nginx.conf"
sed -i "s/REGISTRY_INTERNAL_PORT/${REGISTRY_INTERNAL_PORT}/g" "$NGINX_CONF_DIR/nginx.conf"
sed -i "s/REGISTRY_PORT/${REGISTRY_PORT}/g" "$NGINX_CONF_DIR/nginx.conf"

echo "Nginx config:"
cat "$NGINX_CONF_DIR/nginx.conf"

# Stop and remove existing nginx container if it exists
if $CONTAINER_CMD ps -a --format '{{.Names}}' | grep -q "^test-nginx$"; then
    echo ">>> Stopping existing nginx container..."
    $CONTAINER_CMD stop test-nginx || true
    $CONTAINER_CMD rm test-nginx || true
fi

# Start nginx with protocol detection
echo ">>> Starting nginx with HTTP/HTTPS protocol detection on port ${REGISTRY_PORT}..."
$CONTAINER_CMD run -d \
    --name test-nginx \
    --add-host ${REGISTRY_HOSTNAME}:host-gateway \
    -p ${REGISTRY_PORT}:5000 \
    -v "$NGINX_CONF_DIR/nginx.conf:/etc/nginx/nginx.conf:ro" \
    -v "$NGINX_CONF_DIR/domain.crt:/etc/nginx/domain.crt:ro" \
    -v "$NGINX_CONF_DIR/domain.key:/etc/nginx/domain.key:ro" \
    nginx:alpine

# Wait for nginx to be ready
echo ">>> Waiting for nginx to be ready..."
sleep 3

# Check nginx started successfully
if ! $CONTAINER_CMD ps --format '{{.Names}}' | grep -q "^test-nginx$"; then
    echo "❌ Nginx failed to start"
    $CONTAINER_CMD logs test-nginx
    exit 1
fi

# Test HTTP through nginx proxy
echo ">>> Testing HTTP through nginx proxy..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "${REGISTRY_USERNAME}:${REGISTRY_PASSWORD}" "http://${REGISTRY_URL}/v2/" 2>/dev/null || echo "000")
echo "HTTP test: $HTTP_CODE"

# Test HTTPS through nginx proxy
echo ">>> Testing HTTPS through nginx proxy..."
HTTPS_CODE=$(curl -s -o /dev/null -w "%{http_code}" --cacert "$CERTS_DIR/domain.crt" -u "${REGISTRY_USERNAME}:${REGISTRY_PASSWORD}" "https://${REGISTRY_URL}/v2/" 2>/dev/null || echo "000")
echo "HTTPS test: $HTTPS_CODE"

if [ "$HTTP_CODE" = "200" ] && [ "$HTTPS_CODE" = "200" ]; then
    echo "✓ Nginx proxy accepting both HTTP and HTTPS"
elif [ "$HTTP_CODE" = "200" ] || [ "$HTTPS_CODE" = "200" ]; then
    echo "⚠ Nginx partially working (HTTP: $HTTP_CODE, HTTPS: $HTTPS_CODE)"
else
    echo "⚠ Nginx proxy tests failed (HTTP: $HTTP_CODE, HTTPS: $HTTPS_CODE)"
    $CONTAINER_CMD logs test-nginx
fi

# Test docker login through nginx
echo ">>> Testing docker login through nginx..."
if $CONTAINER_CMD login "$REGISTRY_URL" -u "$REGISTRY_USERNAME" -p "$REGISTRY_PASSWORD" > /dev/null 2>&1; then
    echo "✓ Docker login successful through nginx"
else
    echo "❌ Docker login failed"
    $CONTAINER_CMD logs test-nginx
    $CONTAINER_CMD logs test-registry
    exit 1
fi

# Export credentials for use in workflow
echo "REGISTRY_URL=$REGISTRY_URL" >> $GITHUB_ENV
echo "REGISTRY_USERNAME=$REGISTRY_USERNAME" >> $GITHUB_ENV
echo "REGISTRY_PASSWORD=$REGISTRY_PASSWORD" >> $GITHUB_ENV

echo ""
echo "=========================================="
echo "Docker Registry Setup Complete"
echo "=========================================="
echo "Registry URL: $REGISTRY_URL"
echo "Internal URL: $REGISTRY_INTERNAL_URL (HTTPS)"
echo "Hostname: $REGISTRY_HOSTNAME"
echo "Username: $REGISTRY_USERNAME"
echo "Password: $REGISTRY_PASSWORD"
echo ""
echo "Architecture (nginx protocol detection):"
echo "  HTTPS requests -> nginx:${REGISTRY_PORT} -> TLS termination -> registry:${REGISTRY_INTERNAL_PORT}"
echo "  HTTP requests  -> nginx:${REGISTRY_PORT} -> proxy -> registry:${REGISTRY_INTERNAL_PORT}"
echo ""
echo "This works around docker manifest bugs:"
echo "  - manifest create uses HTTPS"
echo "  - manifest push uses HTTP (bug)"
echo "=========================================="