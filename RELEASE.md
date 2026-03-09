# Release Process

This document describes the versioning scheme and release process for the `strimzi/github-actions` repository.

## Versioning Scheme

| Concept            | Format        | Example        | Description                                         |
|--------------------|---------------|----------------|-----------------------------------------------------|
| Release tag        | `vX.Y`        | `v1.0`, `v1.3` | Immutable tag pointing to a specific release commit |
| Floating major tag | `vX`          | `v1`, `v2`     | Always points to the latest `vX.Y` release          |
| Release branch     | `release-X.x` | `release-1.x`  | Branch for a major version series                   |

We will then pin to a specific version (`v1.2`) for full reproducibility, or use the floating major tag (`v1`) to automatically get the latest patch within a major version.

## Creating a Release Branch

Before the first release of a new major version, create a release branch from `main`:

```bash
git checkout main
git pull
git checkout -b release-1.x
git push origin release-1.x
```

Once you will push the changes, the tests will be automatically triggered and can be review in Actions UI or in commits list.

## Running the Release Workflow

The release is performed via the **Release** workflow (`release.yml`), triggered manually using `workflow_dispatch` on a `release-X.x` branch.

### Inputs

| Input         | Required | Description                                                                                                |
|---------------|----------|------------------------------------------------------------------------------------------------------------|
| `version`     | No       | Release version (e.g., `1.3`). If empty, the minor version is auto-incremented from the latest `vX.Y` tag. |
| `description` | No       | Custom release description prepended before the auto-generated changelog.                                  |

### Auto-increment behavior

When `version` is left empty, the workflow finds the latest `vX.Y` tag for the branch's major version and increments the minor number. 
If no tags exist yet, it starts at `X.0`.

### Steps to release

1. Go to **Actions** > **Release** in GitHub.
2. Click **Run workflow**.
3. Select the target `release-X.x` branch.
4. Optionally enter a version and/or description.
5. Click **Run workflow**.

### What the workflow does

1. **Validates** the branch matches the `release-X.x` pattern and extracts the major version.
2. **Determines the version** — either from the manual input or by auto-incrementing.
3. **Checks** that the tag does not already exist.
4. **Creates and pushes** the `vX.Y` tag.
5. **Force-updates** the floating `vX` tag to point to the same commit.
6. **Generates release notes** using GitHub's auto-generated changelog, optionally prepended with a custom description.
7. **Creates a GitHub Release** with the generated notes.

## Compatibility

> [!WARNING]
> To ensure that actions remain functional across all Strimzi projects, compatibility between N and N-1 versions of the `github-actions` repository must be maintained.
> This must be honored by every change made after the first release.
