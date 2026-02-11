#!/usr/bin/env bash
set -e

function cleanup() {
  rm -rf signing.gpg
  gpg --delete-keys
  gpg --delete-secret-keys
}

# Run the cleanup on failure / exit
trap cleanup EXIT

export GPG_TTY=$(tty)
echo $GPG_SIGNING_KEY | base64 -d > signing.gpg
gpg --batch --import signing.gpg

# Deploy to Maven Central (or custom repository) using already-built artifacts
# Flags explanation:
#   -DskipTests: Skip test execution
#   -Dmaven.main.skip=true: Skip compilation of main sources (use already compiled)
#   -Dmaven.test.skip=true: Skip compilation of test sources
#   -Dmaven.install.skip=true: Skip install phase
#   -P central: Always use central profile for GPG signing and plugin configuration

# Deploy Maven command
MVN_CMD="GPG_EXECUTABLE=gpg mvn $MVN_ARGS \
  -DskipTests \
  -Dmaven.main.skip=true \
  -Dmaven.test.skip=true \
  -Dmaven.install.skip=true \
  -s $SETTINGS_PATH \
  -pl $MODULES \
  -P central"

# Override deployment repository if custom URL provided (for testing with local Nexus)
if [ -n "$DEPLOYMENT_URL" ]; then
  echo "Deploying to custom repository: $DEPLOYMENT_URL"
  # Use centralBaseUrl and centralSnapshotsUrl to override Maven Central URLs
  # This is the proper way according to Sonatype documentation for central-publishing-maven-plugin
  # The plugin will automatically choose the right URL based on the artifact version
  MVN_CMD="$MVN_CMD -DcentralBaseUrl=${DEPLOYMENT_URL}/maven-releases -DcentralSnapshotsUrl=${DEPLOYMENT_URL}/maven-snapshots"
else
  echo "Deploying to Maven Central (default)"
fi

MVN_CMD="$MVN_CMD deploy"

# Execute
eval $MVN_CMD

cleanup