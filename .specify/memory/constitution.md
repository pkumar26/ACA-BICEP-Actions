<!--
  Sync Impact Report
  ===========================================================================
  Version change: N/A → 1.0.0 (initial ratification)
  Modified principles: N/A (initial creation)
  Added sections:
    - I. Purpose and Scope
    - II. Environment and Tenancy Model
    - III. Bicep Design Principles
    - IV. Multi-Environment Parameters and Configuration
    - V. GitHub Actions and CI/CD Strategy
    - VI. App Lifecycle and Image Deployment
    - VII. Security and Compliance Requirements
    - VIII. Observability and Operations
    - IX. Reusability and Extension for Multiple Apps
    - Governance, Reviews, and Evolution
  Removed sections: N/A
  Templates requiring updates:
    - .specify/templates/plan-template.md          ✅ no changes needed
    - .specify/templates/spec-template.md           ✅ no changes needed
    - .specify/templates/tasks-template.md          ✅ no changes needed
  Follow-up TODOs: none
  ===========================================================================
-->

# ACA-BICEP-Actions Constitution

This constitution governs the **ACA-BICEP-Actions** framework — a
reusable, multi-environment Azure Container Apps infrastructure and
deployment framework implemented with Bicep and GitHub Actions.

All contributors, app teams consuming these templates, and framework
maintainers MUST adhere to the principles and guardrails defined here.

## Core Principles

### I. Purpose and Scope

This repository provides a standard, opinionated baseline for
provisioning and deploying Azure Container Apps (ACA) workloads
across multiple environments (dev, qa, prod, and any future stages).

- The framework MUST cover: ACA managed environments, container
  apps, user-assigned managed identities, ACR integration, Key
  Vault–backed secrets, Log Analytics observability, and CI/CD
  pipelines via GitHub Actions.
- The framework MUST be reusable across multiple applications and
  teams by exposing Bicep modules and GitHub Actions reusable
  workflows — not copy-pasted templates.
- Scope is limited to **infrastructure provisioning and deployment
  orchestration**. Application business logic, runtime frameworks,
  and language-specific toolchains remain the responsibility of
  consuming app repositories.

### II. Environment and Tenancy Model

- Each deployment stage (dev, qa, prod) MUST be modeled as a
  distinct **Azure resource group** with a consistent naming
  convention: `rg-{appName}-{env}`.
- Multiple environments MAY reside in the same Azure subscription
  when cost or organizational constraints require it, but MUST be
  isolated via separate resource groups, naming conventions, and
  resource tags.
- One **ACA managed environment** (`cae-{appName}-{env}`) MUST
  exist per deployment stage. Multiple container apps within the
  same stage share this managed environment by default.
- A dedicated ACA managed environment for a single app is permitted
  only when documented isolation requirements (compliance, network,
  performance) justify the cost.
- **Naming conventions** (enforced via Bicep variables):
  - Managed Identity: `id-{appName}-{env}`
  - Log Analytics Workspace: `law-{appName}-{env}`
  - ACA Managed Environment: `cae-{appName}-{env}`
  - Container App: `ca-{appName}-{env}`
  - Key Vault: `kv-{appName}-{env}`
  - ACR: organization-wide, shared, no hyphens (e.g., `demoacr`)
- **Tagging** MUST be applied to every resource and MUST include at
  minimum: `Environment`, `Project`, and `ManagedBy` (value:
  `bicep`). Additional tags (e.g., `CostCenter`, `Owner`) SHOULD
  be added per organizational policy.

### III. Bicep Design Principles

- Infrastructure MUST be expressed as **modular Bicep**: small,
  focused modules for identity, ACR role assignment, Log Analytics,
  ACA environment, container app, and any future shared resources
  (networking, storage, Key Vault provisioning).
- Every module MUST be parameterized to support reuse across apps
  and environments. Required parameters include at minimum:
  `appName`, `environmentName`, `location`, and resource-specific
  configuration (image tag, CPU/memory, ingress, scaling rules,
  secret references).
- There MUST be a clear separation between:
  - **Environment-agnostic modules** (`infra/main.bicep` and any
    child modules) — core building blocks reused everywhere.
  - **Environment-specific parameter files**
    (`infra/parameters.{env}.bicepparam`) — per-stage sizing,
    SKUs, feature flags, and connectivity.
- Consuming app repositories SHOULD reference these modules via
  one of the following patterns (in order of preference):
  1. **Bicep module registry** (ACR-hosted Bicep modules) for
     organization-wide reuse.
  2. **Git submodule or path reference** to a shared templates
     repo.
  3. **Local copy** with a thin wrapper and overrides — permitted
     for bootstrapping but MUST migrate to pattern 1 or 2 once
     the framework stabilizes.

### IV. Multi-Environment Parameters and Configuration

- Parameters MUST be organized as:
  1. **Module defaults** — sensible defaults declared in
     `main.bicep` (e.g., `containerImage` defaults to a
     quickstart placeholder, `minReplicas` defaults to 0).
  2. **Per-environment parameter files** — one
     `parameters.{env}.bicepparam` per stage, overriding defaults
     with environment-appropriate values.
  3. **Per-app overrides** — consuming repos provide their own
     parameter files that import or extend the shared defaults.
- The following MUST vary by environment:
  - CPU and memory allocations (`containerCpu`, `containerMemory`)
  - Replica counts (`minReplicas`, `maxReplicas`)
  - Log level and feature flags (`appEnvVars`)
  - Key Vault URIs for secrets (`secretEnvVars`)
  - Environment tags (`tags.Environment`)
- The following MUST remain consistent across environments:
  - Naming patterns (`{prefix}-{appName}-{env}`)
  - Security baselines (TLS, private registry, Key Vault secrets)
  - Bicep module structure and parameter schemas
- **Secrets** MUST reside in Azure Key Vault. Bicep templates
  reference secrets via `keyVaultSecretUri` and the container
  app's managed identity. GitHub Actions workflows MUST NOT
  hard-code secret values; they MUST use GitHub Environment
  secrets or OIDC federation to authenticate.

### V. GitHub Actions and CI/CD Strategy

- All Azure infrastructure changes MUST be deployed via CI/CD
  (GitHub Actions). Manual portal changes are prohibited except
  for documented break-glass scenarios that MUST be back-ported to
  Bicep within 24 hours.
- The framework MUST provide a **reusable workflow**
  (`infra-deploy.yml` or equivalent callable workflow) that
  accepts clear inputs:
  - Target environment name
  - Azure subscription ID, resource group, tenant ID
  - Parameter file path
  - Container image tag (optional, for app-deploy scenarios)
- Environment triggers and protections:
  - **dev**: deploy automatically on every push to `main` that
    modifies `infra/`.
  - **qa**: deploy on tagged commits, PR merges to a release
    branch, or manual dispatch.
  - **prod**: MUST require **manual approval** via GitHub
    Environment protection rules and MUST deploy only from
    protected branches.
- **What-if preview** (`az deployment group what-if`) MUST run
  before every deployment. Deployment proceeds only if what-if
  succeeds.
- Authentication MUST use **Workload Identity Federation (OIDC)**
  with federated credentials on an Entra ID app registration.
  Long-lived `AZURE_CREDENTIALS` secrets are prohibited for new
  setups. Where legacy secrets exist, a migration plan MUST be
  filed.

### VI. App Lifecycle and Image Deployment

- Application container images MUST be built via GitHub Actions,
  pushed to a **private Azure Container Registry** (ACR), and
  the resulting image tag passed into Bicep parameters
  (`containerImage`).
- Initial infrastructure provisioning MAY use a placeholder image
  (e.g., `mcr.microsoft.com/k8se/quickstart:latest`). The
  placeholder MUST be replaced once the app image is available.
- When ACA revision-based traffic splitting is available and the
  app team opts in, blue/green or canary rollouts SHOULD use ACA's
  `activeRevisionsMode: 'Multiple'` with weighted traffic rules.
  The default is `Single` revision mode for simplicity.
- All infrastructure and application deployments MUST be
  **idempotent** — safe to re-run without side effects. Bicep's
  declarative model enforces this for infrastructure; app
  workflows MUST verify idempotency in their pipeline logic.

### VII. Security and Compliance Requirements

- Minimum security baseline (NON-NEGOTIABLE):
  - Container images MUST be pulled only from **private container
    registries** (ACR) using identity-based authentication (the
    container app's user-assigned managed identity with the
    `AcrPull` role).
  - Secrets MUST be stored in **Azure Key Vault** and accessed
    via Key Vault references in the container app configuration.
    Hard-coded secrets in parameter files, environment variables,
    or workflow files are forbidden.
  - Public ingress MUST be disabled (`ingressExternal: false`)
    unless explicitly required and documented with a security
    rationale.
  - TLS MUST be enforced for all external endpoints
    (`allowInsecure: false`).
  - VNET integration MUST be used when the container app accesses
    private back-end resources or when compliance policy requires
    network isolation.
- **Role assignments** MUST follow least-privilege:
  - Container app identity → `AcrPull` on ACR, `Key Vault
    Secrets User` on Key Vault.
  - GitHub Actions service principal → `Contributor` + `User
    Access Administrator` scoped to the target resource group
    only.
- Consistent **tagging for ownership and cost allocation** MUST be
  applied (see Principle II).
- **Logging to Log Analytics** MUST be enabled on every ACA
  managed environment.

### VIII. Observability and Operations

- Every ACA managed environment MUST be wired to a **Log Analytics
  Workspace** (`law-{appName}-{env}`) with a minimum 30-day
  retention.
- Application Insights MAY be added for application-level
  telemetry; when used, the instrumentation key or connection
  string MUST be injected via Key Vault or environment variables,
  never hard-coded.
- Container apps MUST define **health probes** (liveness and
  readiness) once the application supports them. Placeholder
  images are exempt.
- Alerts MUST be configured for critical conditions:
  - Failure to scale (min replicas not met)
  - Sustained high error rates (HTTP 5xx > threshold)
  - Container restart loops
- The **source of truth** for all operational and infrastructure
  configuration is Bicep + parameter files committed to Git.
  Portal changes that are not codified in Bicep are considered
  drift and MUST be reconciled.

### IX. Reusability and Extension for Multiple Apps

- New applications onboard to this framework by:
  1. Forking or referencing this repository.
  2. Providing minimum required inputs: `appName`, `acrName`,
     `location`, and per-environment parameter files.
  3. Creating app-specific Bicep parameter files (or thin wrapper
     modules) that extend the shared templates.
  4. Connecting to shared infrastructure (shared ACR, shared Key
     Vault, shared Log Analytics) by referencing existing resource
     names in parameters.
- App teams MAY add app-specific Bicep modules (e.g., custom
  networking, storage accounts) alongside the shared modules.
  App-specific modules MUST NOT modify shared modules in place.
- New **reusable modules** SHOULD be added to the shared framework
  when two or more app teams need the same capability. One-off
  customizations MUST remain local to the consuming app repo.
- Shared modules MUST maintain **backward compatibility**. When a
  breaking change is unavoidable:
  - The module version MUST be incremented (see Governance).
  - A changelog entry MUST document the breaking change, migration
    steps, and affected parameters.
  - Downstream app teams MUST be notified via a GitHub issue or
    pull request review before the change merges.

## Governance, Reviews, and Evolution

- This constitution **supersedes** all ad-hoc practices. All pull
  requests and reviews MUST verify compliance with these
  principles.
- **Roles**:
  - **Framework maintainers**: own and review changes to shared
    Bicep modules, reusable workflows, and this constitution.
  - **App team contributors**: consume the framework, submit PRs
    for shared module enhancements or bug fixes, and maintain
    their own parameter files and app-specific modules.
- **Architecture and security review** is REQUIRED for changes
  that affect:
  - Multi-environment structure or naming conventions.
  - Security posture (identity, networking, secret management).
  - CI/CD workflow patterns or authentication mechanisms.
- **Amendment process**:
  1. Propose changes via a pull request modifying this file.
  2. At least one framework maintainer MUST review and approve.
  3. Changes that affect security or multi-environment structure
     require approval from a security reviewer.
  4. Merged amendments take effect immediately; downstream teams
     are notified via release notes or a dedicated communication
     channel.
- **Versioning**: This constitution follows semantic versioning:
  - **MAJOR**: Backward-incompatible principle removal or
    redefinition.
  - **MINOR**: New principle or materially expanded guidance.
  - **PATCH**: Clarifications, wording fixes, non-semantic
    refinements.
- **Shared module versioning**: Bicep modules published to a
  registry MUST be tagged with semver. Consuming repos MUST pin
  to a specific version and upgrade deliberately.

**Version**: 1.0.0 | **Ratified**: 2026-02-28 | **Last Amended**: 2026-02-28
