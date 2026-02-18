#!/bin/bash
set -e

# Setup Docker Registry with authentication and TLS for testing
#
# Architecture:
#   Docker CLI -> Registry (HTTPS, port 443)
#
# Environment variables:
#   REGISTRY_PORT - Port for the registry (default: 443)
#   REGISTRY_USERNAME - Username for registry auth (default: testuser)
#   REGISTRY_PASSWORD - Password for registry auth (default: testpass)
#   REGISTRY_HOSTNAME - Hostname for the registry (default: registry.strimzi)

REGISTRY_PORT="${REGISTRY_PORT:-443}"
REGISTRY_USERNAME="${REGISTRY_USERNAME:-testuser}"
REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-testpass}"
REGISTRY_HOSTNAME="${REGISTRY_HOSTNAME:-registry.strimzi}"
REGISTRY_URL="${REGISTRY_HOSTNAME}:${REGISTRY_PORT}"
REGISTRY_IMAGE="${REGISTRY_IMAGE:-"registry:3"}"

echo ">>> Setting up Docker Registry with TLS..."
echo "Registry URL: $REGISTRY_URL (HTTPS)"
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

# Configure Docker to trust the certificate
echo ">>> Configuring Docker to trust the registry certificate..."
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

# Start registry with authentication and TLS
echo ">>> Starting Docker Registry with TLS on port ${REGISTRY_PORT}..."
$CONTAINER_CMD run -d \
    --name test-registry \
    -p ${REGISTRY_PORT}:443 \
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
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --cacert "$CERTS_DIR/domain.crt" -u "${REGISTRY_USERNAME}:${REGISTRY_PASSWORD}" "https://${REGISTRY_URL}/v2/" 2>/dev/null || echo "000")

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

# Test docker login
echo ">>> Testing docker login..."
if $CONTAINER_CMD login "$REGISTRY_URL" -u "$REGISTRY_USERNAME" -p "$REGISTRY_PASSWORD" > /dev/null 2>&1; then
    echo "✓ Docker login successful"
else
    echo "❌ Docker login failed"
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
echo "Registry URL: $REGISTRY_URL (HTTPS)"
echo "Hostname: $REGISTRY_HOSTNAME"
echo "Username: $REGISTRY_USERNAME"
echo "Password: $REGISTRY_PASSWORD"
echo "=========================================="