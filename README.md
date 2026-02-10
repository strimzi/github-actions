[![Build Status - dependencies](https://github.com/strimzi/github-actions/actions/workflows/test-dependencies.yml/badge.svg)](https://github.com/strimzi/github-actions/actions/workflows/test-dependencies.yml)
[![Build Status - integrations](https://github.com/strimzi/github-actions/actions/workflows/test-integrations.yml/badge.svg)](https://github.com/strimzi/github-actions/actions/workflows/test-integrations.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](http://www.apache.org/licenses/LICENSE-2.0)
[![Twitter Follow](https://img.shields.io/twitter/follow/strimziio?style=social)](https://twitter.com/strimziio)

# Strimzi GitHub Actions

Shared GitHub Actions and CI workflows used across [Strimzi](https://strimzi.io/) repositories.

## Actions

### Dependency Actions

Actions for installing tools and setting up Kubernetes clusters.

| Action                            | Description                                                        | Key Inputs                                                                                    |
|-----------------------------------|--------------------------------------------------------------------|-----------------------------------------------------------------------------------------------|
| `dependencies/install-docker`     | Sets up Docker with QEMU and Buildx for multi-platform builds      | —                                                                                             |
| `dependencies/setup-java`         | Installs Java and Maven                                            | `javaVersion` (21), `mavenVersion` (3.9.9), `javaDistro` (temurin)                            |
| `dependencies/install-helm`       | Installs Helm and helm-unittest plugin                             | `helmVersion` (v3.20.0), `helmUnitTestVersion` (v1.0.3)                                       |
| `dependencies/install-yq`         | Installs yq YAML processor                                         | `version` (v4.6.3), `architecture` (amd64)                                                    |
| `dependencies/install-shellcheck` | Installs ShellCheck linter                                         | `version` (0.11.0), `architecture` (amd64)                                                    |
| `dependencies/install-syft`       | Installs Syft SBOM generation tool                                 | `version` (0.90.0), `architecture` (amd64)                                                    |
| `dependencies/setup-kind`         | Creates a Kind cluster with local registry and cloud-provider-kind | `kindVersion` (0.31.0), `controlNodes` (1), `workerNodes` (1), `cloudProviderVersion` (0.6.0) |
| `dependencies/setup-minikube`     | Creates a Minikube cluster with local registry                     | `minikubeVersion` (v1.38.0), `kubeVersion` (v1.38.0)                                          |

### Build Actions

Actions for building, testing, and releasing Strimzi components.

| Action                     | Description                                              | Key Inputs                                                                           |
|----------------------------|----------------------------------------------------------|--------------------------------------------------------------------------------------|
| `build/build-binaries`     | Builds and tests Java binaries using Makefile targets    | `operatorBuild` (false), `mainBuild` (true), `artifactSuffix` (binaries)             |
| `build/build-containers`   | Builds and archives container images                     | `architecture` (amd64), `imagesDir` (required), `containerTag` (latest)              |
| `build/push-containers`    | Pushes container images and creates multi-arch manifests | `architectures` (required), `registryUser` (required), `registryPassword` (required) |
| `build/load-containers`    | Loads container images into Kind/Minikube registry       | `registry` (required: minikube/kind/external)                                        |
| `build/deploy-java`        | Deploys Java artifacts to Maven Central                  | `projects` (required), `settingsPath` (required)                                     |
| `build/release-artifacts`  | Builds release artifacts using Makefile                  | `releaseVersion` (required), `artifactSuffix` (required)                             |
| `build/publish-helm-chart` | Publishes Helm Chart as OCI artifact                     | `releaseVersion` (required), `helmChartName` (required)                              |

> [!IMPORTANT]
> Build actions do **not** install their own dependencies (Java, yq, Helm, Docker, Shellcheck, Syft, etc.).
> Callers must install the required dependencies using the appropriate dependency actions **before** invoking a build action.

> [!IMPORTANT]
> The `build-binaries` action supports an `operatorBuild` input (default `false`) that enables Strimzi Kafka Operator specific build steps — Helm chart generation, CRD distribution, dashboard setup, documentation checks, and uncommitted changes verification.
> Other repositories should leave this disabled.

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

- strimzi-kafka-operator (with `operatorBuild: true`)
- strimzi-kafka-bridge
- kafka-access-operator
- strimzi-mqtt-bridge
- drain-cleaner
- client-examples

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

## License

This project is licensed under the [Apache License 2.0](LICENSE).
