[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/strimzi/github-actions/badge)](https://scorecard.dev/viewer/?uri=github.com/strimzi/github-actions)
[![Build Status - dependencies](https://github.com/strimzi/github-actions/actions/workflows/test-dependencies.yml/badge.svg)](https://github.com/strimzi/github-actions/actions/workflows/test-dependencies.yml)
[![Build Status - integrations](https://github.com/strimzi/github-actions/actions/workflows/test-integrations.yml/badge.svg)](https://github.com/strimzi/github-actions/actions/workflows/test-integrations.yml)
[![Build Status - utils](https://github.com/strimzi/github-actions/actions/workflows/test-utils.yml/badge.svg)](https://github.com/strimzi/github-actions/actions/workflows/test-utils.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0)
[![Twitter Follow](https://img.shields.io/twitter/follow/strimziio?style=social)](https://twitter.com/strimziio)

# Strimzi GitHub Actions

Shared GitHub Actions and CI workflows used across [Strimzi](https://strimzi.io/) repositories.

> [!IMPORTANT]
> All the actions within this repository are designed for internal usage within Strimzi projects.
> We do not support usage of the actions outside the Strimzi organization.

## Actions

### Dependency Actions

Actions for installing tools and setting up Kubernetes clusters.

| Action                              | Description                                                        | Key Inputs                                                                                    |
|-------------------------------------|--------------------------------------------------------------------|-----------------------------------------------------------------------------------------------|
| `dependencies/install-docker`       | Sets up Docker with QEMU and Buildx for multi-platform builds      | —                                                                                             |
| `dependencies/setup-java`           | Installs Java and Maven                                            | `javaVersion` (21), `mavenVersion` (3.9.9), `javaDistro` (temurin)                            |
| `dependencies/install-helm`         | Installs Helm and helm-unittest plugin                             | `helmVersion` (v3.20.0), `helmUnitTestVersion` (v1.0.3)                                       |
| `dependencies/install-yq`           | Installs yq YAML processor                                         | `version` (v4.6.3), `architecture` (amd64)                                                    |
| `dependencies/install-shellcheck`   | Installs ShellCheck linter                                         | `version` (0.11.0), `architecture` (amd64)                                                    |
| `dependencies/install-syft`         | Installs Syft SBOM generation tool                                 | `version` (1.20.0), `architecture` (amd64)                                                    |
| `dependencies/install-ascii-doctor` | Installs Ascii Doctor tool                                         | `rubyVersion` (3.2)                                                                           |
| `dependencies/setup-kind`           | Creates a Kind cluster with local registry and cloud-provider-kind | `kindVersion` (0.31.0), `controlNodes` (1), `workerNodes` (1), `cloudProviderVersion` (0.6.0) |
| `dependencies/setup-minikube`       | Creates a Minikube cluster with local registry                     | `minikubeVersion` (v1.38.0), `kubeVersion` (v1.38.0)                                          |

### Build Actions

Actions for building, testing, and releasing Strimzi components.

| Action                     | Description                                              | Key Inputs                                                                           |
|----------------------------|----------------------------------------------------------|--------------------------------------------------------------------------------------|
| `build/build-binaries`     | Builds and tests Java binaries using Makefile targets    | `clusterOperatorBuild` (false), `mainBuild` (true), `artifactSuffix` (binaries)      |
| `build/build-containers`   | Builds and archives container images                     | `architecture` (amd64), `imagesLocation` (required), `containerTag` (latest)              |
| `build/push-containers`    | Pushes container images and creates multi-arch manifests | `architectures` (required), `registryUser` (required), `registryPassword` (required) |
| `build/load-containers`    | Loads container images into Kind/Minikube registry       | `registry` (required: minikube/kind/external)                                        |
| `build/deploy-java`        | Deploys Java artifacts to Maven Central                  | `projects` (required), `settingsPath` (required)                                     |
| `build/release-artifacts`  | Builds release artifacts using Makefile                  | `releaseVersion` (required), `artifactSuffix` (required)                             |
| `build/publish-helm-chart` | Publishes Helm Chart as OCI artifact                     | `releaseVersion` (required), `helmChartName` (required)                              |
| `build/attest-artifact`    | Creates provenance or SBOM attestation for artifacts     | `mode` (required: blob/oci/sbom), see [Artifact Attestation](#artifact-attestation)  |

> [!IMPORTANT]
> Build actions do **not** install their own dependencies (Java, yq, Helm, Docker, Shellcheck, Syft, etc.).
> Callers must install the required dependencies using the appropriate dependency actions **before** invoking a build action.

> [!IMPORTANT]
> The `build-binaries` action supports an `clusterOperatorBuild` input (default `false`) that enables Strimzi Kafka Operator specific build steps — Helm chart generation, CRD distribution, dashboard setup, documentation checks, and uncommitted changes verification.
> Other repositories should leave this disabled.

### Artifact Attestation

The `attest-artifact` action creates [SLSA build provenance](https://slsa.dev/provenance/v1) and [SBOM attestations](https://spdx.dev/Document/v2.3) using GitHub's Attestation API ([`actions/attest`](https://github.com/actions/attest)).
Attestations are signed with Sigstore (keyless, via GitHub OIDC) and stored in the GitHub Attestation API.
Consumers verify with `gh attestation verify`.

The action supports three modes:

| Mode   | Use case                            | Key inputs                                              |
|--------|-------------------------------------|---------------------------------------------------------|
| `blob` | Release archives (.tar.gz, .zip)    | `subject-path` (glob)                                   |
| `oci`  | Container/Helm image provenance     | `subject-prefix`, `image-name`, `subject-digest`        |
| `sbom` | SBOM attestation for OCI image      | `subject-prefix`, `image-name`, `subject-digest`, `sbom-path` |

#### Built-in attestation

The following actions include attestation automatically (on push events only, skipped on PRs):

- **`release-artifacts`** — attests release archives in `blob` mode, includes `.intoto.jsonl` provenance bundle in the release tarball (required for [OpenSSF Scorecard Signed-Releases](https://github.com/ossf/scorecard/blob/main/docs/checks.md#signed-releases) check)
- **`publish-helm-chart`** — attests the Helm OCI artifact in `oci` mode after `helm push`

#### Container image attestation

Container images require a separate attestation job because each image needs its own `actions/attest` call.
The `push-containers` action discovers images from the SBOM directory and outputs a JSON array for use in a matrix job.

**Required permissions** in the release workflow:

```yaml
permissions:
  contents: read
  id-token: write       # OIDC token for Sigstore signing
  attestations: write   # GitHub Attestation API
```

**Example** — add to your project's `release.yml` after the push-containers job:

```yaml
  attest-containers:
    needs: push-containers
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      attestations: write
    strategy:
      fail-fast: false
      matrix:
        image: ${{ fromJson(needs.push-containers.outputs.images) }}
    steps:
      - name: Download SBOM artifact
        uses: actions/download-artifact@v4
        with:
          name: SBOMs-operators-${{ env.RELEASE_VERSION }}.tar.gz

      - name: Extract SBOMs
        run: tar -xzf sbom.tar.gz

      - name: Attest container provenance
        uses: ./.github/actions/build/attest-artifact
        with:
          mode: oci
          subject-prefix: quay.io/strimzi
          image-name: ${{ matrix.image.name }}
          subject-digest: ${{ matrix.image.digest }}

      - name: Attest container SBOM
        uses: ./.github/actions/build/attest-artifact
        with:
          mode: sbom
          subject-prefix: quay.io/strimzi
          image-name: ${{ matrix.image.name }}
          subject-digest: ${{ matrix.image.digest }}
          sbom-path: ./${{ matrix.image.sbom }}
```

#### Verification

```bash
# Release archives
gh attestation verify <artifact-file> --repo strimzi/<project>

# Container images
gh attestation verify oci://quay.io/strimzi/<image>@<digest> --repo strimzi/<project>

# Helm charts
gh attestation verify oci://quay.io/strimzi-helm/<chart>@<digest> --repo strimzi/<project>
```

### Security Actions

Actions for security scanning of dependencies and container images.

| Action                              | Description                                                          | Key Inputs                                              |
|-------------------------------------|----------------------------------------------------------------------|---------------------------------------------------------|
| `security/snyk-maven-scan`         | Run Snyk scan on Maven dependencies with SARIF upload                | `scanName` (required), `snykMonitor`, `exclude`         |
| `security/snyk-container-scan`     | Scan a container image with Snyk, upload results to Code Scanning    | `imageFile` (required), `image` (required), `snykMonitor` |
| `security/fossa-maven-scan`        | Run FOSSA scan on Maven dependencies for license and vulnerability analysis | `scanName` (required), `fossaTest`, `exclude`    |
| `security/fossa-container-scan`    | Scan a container image with FOSSA for license and vulnerability analysis | `imageFile` (required), `image` (required), `fossaTest` |

### Utils Actions

Actions used as utils mostly in operators repository.

| Action                     | Description                                                               | Key Inputs |
|----------------------------|---------------------------------------------------------------------------|------------|
| `utils/check-permissions`  | Check whether users who leave the comment has rights to trigger actions   | none       |
| `utils/determine-ref`      | Determine checkout ref based on PR metadata                               | none       |
| `utils/should-run`         | Determine whether STs pipeline should be run or not based on comment body | none       |

## Test Workflows

### `test-dependencies.yml`

Tests all dependency actions with version matrix combinations:

- **Docker** — Buildx multi-platform support verification
- **Helm** — version matrix, unittest plugin verification
- **ShellCheck** — version matrix, functional test
- **Syft** — version matrix
- **yq** — version matrix, functional test
- **Java/Maven** — Java 17/21 + Maven 3.9.9/3.8.8 matrix
- **Kind** — single/multi-node clusters, K8s version verification, registry access from inside cluster, node labels, cloud-provider-kind
- **Minikube** — version matrix with `latest`, K8s version verification, registry access

### `test-integrations.yml` / `reusable-test-integrations.yml`

End-to-end integration tests that run the full build pipeline (build binaries, deploy Java, build/push containers, release artifacts, publish Helm) against multiple Strimzi repositories:

- strimzi-kafka-operator (with `clusterOperatorBuild: true`)
- strimzi-kafka-bridge
- kafka-access-operator
- strimzi-mqtt-bridge
- drain-cleaner
- client-examples
- kafka-quotas-plugin

> [!WARNING]
> The rest of Strimzi repositories are not compatible yet and will be added in the future.

## Usage

Reference actions from another Strimzi repository:

```yaml
- uses: strimzi/github-actions/.github/actions/dependencies/setup-kind@main
  with:
    controlNodes: 1
    workerNodes: 3
```

## Cross-repo testing

With shared repository with our specific actions we unfortunately have chicken-egg problem for several parts of the build process.
In case we do update `push-container` or `release` flows in respective repositories, we are not able to catch issues during the PRs with current checks.
The result will be shown only in tests within `github-actions` repository, because it tests flow for all parts of build process.
To mitigate this, we have to run the same integration tests we have in this repository also in other repositories, just with different configurations.

The main difference is in `githubActionsRef` parameter.
This parameter says which branch of `github-actions` repo will be used for running the tests which should align with branch or version used in build/release workflows.
So for example in case we use version `1.0.0` in build workflow, we should keep the same in the tests to ensure that current actions will work with new changes.

The following code snippet shows the workflow for Bridge repository:

```yaml
name: Test github-actions integration

on:
  pull_request:
    branches:
      - "*"
  push:
    branches:
      - "main"

permissions:
  contents: read
  id-token: write
  attestations: write

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test-github-actions-integration:
    uses: strimzi/github-actions/.github/workflows/reusable-test-integrations.yml@main
    with:
      repo: ${{ github.repository }}
      ref: ${{ github.sha }}
      architecture: "amd64"
      artifactSuffix: "kafka-bridge"
      buildContainers: true
      modules: "./"
      nexusCheck: "kafka-bridge"
      javaVersion: "17"
      helmChartName: "none"
      releaseVersion: "6.6.6"
      imagesLocation: "kafka-bridge-amd64.tar.gz"
      clusterOperatorBuild: false
      githubActionsRef: "1.0.0"
    secrets: inherit
```

## Versioning

This repository uses `vX.Y` release tags (e.g., `v1.0`, `v1.3`) with floating `vX` major tags that always point to the latest release within a major version.
Releases are created from `release-X.x` branches using an automated workflow.
See [RELEASE.md](RELEASE.md) for full details on the versioning scheme and release process.

> [!WARNING]
> To ensure that actions remain functional across all Strimzi projects, compatibility between N and N-1 versions of the `github-actions` repository must be maintained.
> This must be honored by every change made after the first release.

## License

This project is licensed under the [Apache License 2.0](LICENSE).
