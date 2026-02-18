#!/usr/bin/env bash
set -e

# Setup Nexus for GitHub Actions testing
# This script:
# 1. Waits for Nexus to be ready
# 2. Retrieves the admin password
# 3. Accepts the EULA
# 4. Configures anonymous access
# 5. Creates Maven settings.xml

NEXUS_URL="${NEXUS_URL:-http://localhost:8081}"
NEXUS_IMAGE="${NEXUS_IMAGE:-sonatype/nexus3:3.87.2}"
SETTINGS_DIR="${SETTINGS_DIR:-github-actions/.github/test-settings}"
GITHUB_ENV="${GITHUB_ENV:-/dev/null}"

echo "=== Nexus Setup Script ==="
echo "Nexus URL: $NEXUS_URL"
echo ""

# Step 1: Start nexus
echo ">>> Starting Nexus container..."
docker run -d \
    --name nexus \
    -p 8081:8081 \
    ${NEXUS_IMAGE}

# Step 2: Wait for Nexus to be ready
echo ">>> Waiting for Nexus to start..."
timeout 180 bash -c "until curl -sf $NEXUS_URL/ > /dev/null; do sleep 5; done"
echo "✓ Nexus is responding"

# Step 3: Wait for full initialization and get admin password
echo ">>> Waiting for Nexus to fully initialize..."
sleep 10

echo ">>> Retrieving admin password..."
NEXUS_PASSWORD=$(docker exec $(docker ps -q --filter ancestor=$NEXUS_IMAGE) cat /nexus-data/admin.password 2>/dev/null)

if [ -z "$NEXUS_PASSWORD" ]; then
    echo "ERROR: Could not retrieve Nexus admin password"
    exit 1
fi

echo "✓ Admin password retrieved"

# Export to GitHub Actions environment if available
if [ "$GITHUB_ENV" != "/dev/null" ]; then
    echo "NEXUS_PASSWORD=$NEXUS_PASSWORD" >> $GITHUB_ENV
fi

# Step 4: Accept EULA
echo ">>> Accepting Nexus EULA..."
# First, get the current EULA to see what disclaimer is expected
EULA_INFO=$(curl -s -u admin:$NEXUS_PASSWORD "$NEXUS_URL/service/rest/v1/system/eula" | jq .disclaimer 2>/dev/null)
echo "Current EULA info: $EULA_INFO"

# Accept EULA with the exact disclaimer from the API
curl -X POST -u admin:$NEXUS_PASSWORD \
    -H "Content-Type: application/json" \
    -d "{\"accepted\": true, \"disclaimer\": $EULA_INFO}" \
    "$NEXUS_URL/service/rest/v1/system/eula" \
    2>/dev/null || echo "⚠️  EULA acceptance may have already been done"

sleep 2

# Step 5: Configure anonymous access (disable for security)
echo ">>> Disable anonymous access..."
curl -u admin:$NEXUS_PASSWORD -X PUT \
    "$NEXUS_URL/service/rest/v1/security/anonymous" \
    -H "Content-Type: application/json" \
    -d '{"enabled": false, "userId": "anonymous", "realmName": "NexusAuthorizingRealm"}' \
    2>/dev/null || echo "⚠️  Anonymous access configuration may have already been disabled"

echo "✓ Nexus setup complete"

echo "=== Nexus Setup Complete ==="
echo "Admin password: $NEXUS_PASSWORD"