# Feature Specification: Multi-Environment ACA Provisioning & Deployment Framework

**Feature Branch**: `001-aca-multienv-framework`  
**Created**: 2026-02-28  
**Status**: Draft  
**Input**: User description: "Create a reusable multi-environment Azure Container Apps (ACA) provisioning and deployment framework using Bicep and GitHub Actions across dev, qa, and prod."

---

## 1. Goals and Non-Goals

### Goals

- Provide a **single, reusable set of Bicep modules** that provision ACA infrastructure consistently across `dev`, `qa`, and `prod` environments.
- Establish a **secure identity model** where a user-assigned managed identity (UAMI) is created per environment and used by container apps to pull images from ACR and read secrets from Key Vault — with no stored credentials.
- Deliver a **GitHub Actions CI/CD pattern** that authenticates to Azure via workload identity federation (OIDC), selects the correct per-environment parameter file, and supports what-if previews before every deployment.
- Enable **application teams to onboard** by forking or referencing this framework, supplying only their app-specific inputs (app name, image, env vars, Key Vault URIs), and deploying through the same pipeline.
- Enforce **security guardrails** (no registry passwords, no secrets in parameter files, TLS-only ingress, least-privilege RBAC) as part of the baseline rather than as optional add-ons.

### Non-Goals

- Supporting non-ACA compute targets (App Service, AKS, Azure Functions, VMs) in this iteration.
- Managing on-premises or multi-cloud deployments.
- Provisioning the ACR or Key Vault resources themselves — they are assumed to exist.
- Providing application-level business logic, runtime frameworks, or language-specific build toolchains.
- Implementing a full GitOps reconciliation loop; this framework is imperative (CI/CD pushes state to Azure).

---

## Clarifications

### Session 2026-02-28

- Q: What should happen if what-if output reveals destructive changes (resource deletions)? → A: Auto-abort on resource deletions; manual re-run with an explicit override flag required to proceed.
- Q: What is the recovery model for partial deployment failures? → A: Fix-forward only; operator fixes root cause and re-runs the workflow, relying on Bicep idempotency to converge to desired state. No automated or manual rollback mechanism.
- Q: Should this framework manage the `Key Vault Secrets User` role assignment on Key Vault? → A: No. The Key Vault role assignment is an external prerequisite, pre-configured outside this framework. The spec documents it as a required precondition.
- Q: Should the framework support cross-resource-group ACR role assignment? → A: Yes. The ACR resource ID is passed as a full parameter; the role assignment is scoped to the ACR regardless of its resource group.
- Q: Should v1 include VNET integration, and should Bicep support deploying into an existing ACA environment? → A: Yes to both. Bicep accepts optional `subnetId`/`vnetConfig` parameters for VNET-integrated ACA deployments. Additionally, the framework supports deploying container apps into an existing ACA managed environment (via an optional `existingManagedEnvironmentId` parameter) instead of always creating a new one.

---

## 2. User Scenarios & Testing *(mandatory)*

### User Story 1 — First-Time Environment Provisioning (Priority: P1)

A platform engineer runs the framework for the first time against an empty resource group for the `dev` environment. The pipeline provisions the managed identity, assigns `AcrPull` on the existing ACR, creates a Log Analytics workspace, creates the ACA managed environment, and deploys a container app using a placeholder image. After the run, all resources exist with correct names, tags, and identity bindings.

**Why this priority**: Without the ability to stand up a complete environment from scratch, no other stories can proceed. This is the foundational "happy path."

**Independent Test**: Run `az deployment group create` with `parameters.dev.bicepparam` against an empty resource group. Verify all five resource types exist (`id-`, `law-`, `cae-`, `ca-`, role assignment) with correct naming and tags.

**Acceptance Scenarios**:

1. **Given** an empty resource group and an existing ACR, **When** the Bicep template is deployed with `parameters.dev.bicepparam`, **Then** the managed identity, Log Analytics workspace, ACA managed environment, and container app are all created with names following the `{prefix}-{appName}-{env}` convention.
2. **Given** the same deployment, **When** the container app resource is inspected, **Then** its identity section references the newly created UAMI and its registry configuration uses identity-based ACR pull (no password).
3. **Given** the same deployment, **When** the ACR is inspected, **Then** a role assignment granting `AcrPull` to the UAMI's principal ID exists.

---

### User Story 2 — Key Vault–Backed Secret Injection (Priority: P1)

An application developer adds a new secret to Key Vault (e.g., a database connection string), then adds a corresponding entry in the environment's parameter file under `secretEnvVars`. On the next deployment, the container app receives the secret as an environment variable backed by the Key Vault reference, accessible at runtime without the secret value ever appearing in source control or pipeline logs.

**Why this priority**: Secret management is a non-negotiable security requirement and a core differentiator of this framework.

**Independent Test**: Add a test secret to Key Vault, reference it in `parameters.dev.bicepparam`, deploy, and verify the container app's secret configuration contains a `keyVaultUrl` pointing to the correct Key Vault secret URI, using the UAMI for access.

**Acceptance Scenarios**:

1. **Given** a Key Vault with a secret named `db-connection`, **When** the parameter file includes a `secretEnvVars` entry referencing its URI, **Then** the deployed container app's secrets array contains an entry with `keyVaultUrl` matching the URI and `identity` matching the UAMI resource ID.
2. **Given** the deployed container app, **When** the container starts, **Then** the environment variable `DB_CONNECTION` is available to the application process with the value from Key Vault.
3. **Given** the Bicep parameter file and GitHub Actions logs, **When** reviewed, **Then** no secret values appear in plaintext anywhere.

---

### User Story 3 — Multi-Environment Promotion (Priority: P1)

A release engineer promotes an application from `dev` to `qa` to `prod` by triggering the appropriate GitHub Actions workflow for each environment. Each environment uses its own parameter file, resulting in different resource sizing (CPU, memory, replicas), different Key Vault URIs, and different deployment protections (auto for dev, manual approval for prod).

**Why this priority**: Multi-environment separation is the core value proposition of this framework.

**Independent Test**: Deploy sequentially to `dev`, `qa`, and `prod` resource groups using the three parameter files. Confirm that resource names include the correct environment suffix, CPU/memory/replica settings match each parameter file, and `prod` deployment requires manual approval.

**Acceptance Scenarios**:

1. **Given** three GitHub Actions environments (`dev`, `qa`, `prod`) with matching Bicep parameter files, **When** each is deployed, **Then** the Container App in each environment reflects the sizing and configuration from its parameter file (e.g., dev: 0.25 CPU / 0.5Gi / 0–1 replicas; prod: 1 CPU / 2Gi / 1–10 replicas).
2. **Given** a push to `main` modifying `infra/`, **When** GitHub Actions triggers, **Then** `dev` deploys automatically with no approval gate.
3. **Given** a manual workflow dispatch targeting `prod`, **When** the workflow runs, **Then** it pauses for manual approval before executing the deployment.

---

### User Story 4 — OIDC Authentication from GitHub to Azure (Priority: P2)

A platform engineer configures workload identity federation so the GitHub Actions workflow authenticates to Azure without any long-lived client secrets. The workflow uses OIDC tokens scoped to the repository and environment to obtain short-lived Azure credentials.

**Why this priority**: OIDC eliminates stored secrets and is required by the constitution, but it is a one-time configuration step that can initially be done manually while other stories proceed.

**Independent Test**: Run the GitHub Actions workflow with OIDC credentials configured. Verify the `az login` step succeeds using federated identity (no `AZURE_CREDENTIALS` secret present).

**Acceptance Scenarios**:

1. **Given** a GitHub Environment with `AZURE_CLIENT_ID` and `AZURE_TENANT_ID` configured as secrets and an Entra ID app registration with a federated credential for `repo:owner/repo:environment:dev`, **When** the workflow runs, **Then** `az login --federated-token` succeeds and the deployment proceeds.
2. **Given** the GitHub repository settings, **When** inspected, **Then** no `AZURE_CREDENTIALS` JSON secret exists; only `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` are present.

---

### User Story 5 — Reusable Workflow Consumption by Another App Repo (Priority: P2)

An application team in a separate repository calls this framework's reusable workflow to deploy their own container app. They supply inputs (environment name, subscription, resource group, parameter file path, container image tag) and the shared workflow handles authentication, Bicep deployment, and what-if preview.

**Why this priority**: Multi-repo reuse is a strategic goal but is dependent on the core provisioning (P1) being stable first.

**Independent Test**: Create a minimal calling workflow in a separate repository that invokes the reusable workflow with test inputs. Verify the deployment runs end-to-end and the container app is created in the caller's resource group.

**Acceptance Scenarios**:

1. **Given** a separate app repository with a workflow that calls the shared `infra-deploy` reusable workflow, **When** the calling workflow provides environment name, subscription, resource group, and parameter file path, **Then** the reusable workflow authenticates, runs what-if, and deploys the Bicep template to the correct resource group.
2. **Given** the calling workflow passes a container image tag as input, **When** the Bicep deployment runs, **Then** the deployed container app uses the provided image tag.

---

### User Story 6 — Existing Managed Identity Reuse (Priority: P3)

An application team already has a UAMI provisioned outside this framework (e.g., by a central identity team). They set `createNewIdentity = false` and provide the existing identity's resource ID in the parameter file. The framework skips identity creation but still uses the provided identity for ACR pull and Key Vault access.

**Why this priority**: Useful for teams with pre-existing identity governance, but most teams will use the default path of creating a new identity.

**Independent Test**: Deploy with `createNewIdentity = false` and a valid `existingIdentityResourceId`. Verify no new identity resource is created, the container app references the provided identity, and ACR/Key Vault access works.

**Acceptance Scenarios**:

1. **Given** `createNewIdentity = false` and a valid `existingIdentityResourceId` in the parameter file, **When** the Bicep template is deployed, **Then** no `Microsoft.ManagedIdentity/userAssignedIdentities` resource is created.
2. **Given** the same deployment, **When** the container app is inspected, **Then** its `userAssignedIdentities` section references the provided resource ID.

---

### Edge Cases

- What happens when the ACR is in a different resource group than the container app? The framework handles this natively: the `AcrPull` role assignment uses the full ACR resource ID (passed as a parameter), making it scope-agnostic. The pipeline service principal must have `User Access Administrator` on the ACR's resource group.
- What happens when Key Vault secrets referenced in `secretEnvVars` do not exist? The container app deployment should fail with a clear error at provisioning time, not silently at runtime.
- What happens when a deployment is re-run without changes? All resources must remain unchanged (idempotency); no duplicate role assignments, no resource recreation.
- What happens when `maxReplicas` is set to 0? The parameter must be validated (minimum 1 if `minReplicas` > 0) to prevent invalid configurations.
- What happens when the OIDC federated credential subject doesn't match the branch/environment? The `az login` step must fail with an actionable error message.
- What happens when a deployment partially succeeds (e.g., identity created but container app fails)? The operator fixes the root cause and re-runs the workflow. Bicep's idempotent `Incremental` mode converges already-created resources to their declared state without duplication. No automated rollback is attempted.

---

## 3. High-Level Architecture

### Components

- **ACA Managed Environment** (`cae-{appName}-{env}`): The hosting platform for container apps in each environment. One per environment, shared by all container apps in that environment.
- **Container App** (`ca-{appName}-{env}`): The deployed application workload. Configured with identity-based ACR pull, Key Vault–backed secrets, environment-specific scaling, and optional external ingress.
- **User-Assigned Managed Identity** (`id-{appName}-{env}`): Created per environment (or brought externally). Granted `AcrPull` on ACR (assigned by this framework) and `Key Vault Secrets User` on Key Vault (external prerequisite). Associated with the container app for pull and secret access.
- **Azure Container Registry (ACR)**: Pre-existing, organization-wide. Holds container images. No credentials stored; the UAMI's `AcrPull` role enables identity-based pulls.
- **Azure Key Vault** (`kv-{appName}-{env}`): Pre-existing per environment. Stores sensitive configuration (connection strings, API keys). The container app references secrets via Key Vault URIs.
- **Log Analytics Workspace** (`law-{appName}-{env}`): Created by the framework. Receives ACA logs and metrics with a minimum 30-day retention.
- **Bicep Modules and Parameter Files**: Declarative infrastructure definitions (`infra/main.bicep`) and per-environment parameter files (`infra/parameters.{env}.bicepparam`).
- **GitHub Actions Workflows**: Reusable deployment workflow (`infra-deploy.yml`) that handles OIDC auth, what-if preview, and Bicep deployment. Per-environment triggers and protection rules.

### Interaction Flow (per environment)

1. Developer pushes code or a platform engineer triggers the workflow.
2. GitHub Actions authenticates to Azure via OIDC (federated credential scoped to repo + environment).
3. The workflow selects the correct `parameters.{env}.bicepparam` file.
4. `az deployment group what-if` runs to preview changes.
5. `az deployment group create` deploys the Bicep template, provisioning or updating all resources.
6. The container app starts, pulls the image from ACR using the UAMI, and receives secrets from Key Vault.

---

## 4. Identity and Authentication Model

### GitHub-to-Azure Authentication (Workload Identity Federation)

- An **Entra ID app registration** is configured with federated credentials for each GitHub environment (`dev`, `qa`, `prod`).
- Each federated credential has: issuer = `https://token.actions.githubusercontent.com`, subject = `repo:{owner}/{repo}:environment:{env}`, audience = `api://AzureADTokenExchange`.
- The app registration is granted `Contributor` and `User Access Administrator` roles scoped to the target resource group.
- GitHub Actions uses `azure/login@v2` with `client-id`, `tenant-id`, and `subscription-id` — no `AZURE_CREDENTIALS` JSON blob.

### Container App Identity (User-Assigned Managed Identity)

- A UAMI is created per environment by default (`id-{appName}-{env}`), or an existing UAMI can be referenced.
- Required role assignments:
  - `AcrPull` (role ID `7f951dda-4ed3-4680-a7ca-43fe172d538d`) scoped to the existing ACR — **assigned by this framework**.
  - `Key Vault Secrets User` (role ID `4633458b-17de-408a-b874-0445c86b69e6`) scoped to the environment's Key Vault — **external prerequisite**, must be pre-assigned before deployment.
- The UAMI is associated with the container app in two ways:
  - `identity.userAssignedIdentities` — makes the identity available to the app.
  - `configuration.registries[].identity` — tells ACA to use this identity for image pulls.
  - `configuration.secrets[].identity` — tells ACA to use this identity for Key Vault secret access.

---

## 5. Infrastructure Modeling in Bicep

### Required Modules and Responsibilities

- **Identity module**: Creates the UAMI (conditionally, based on `createNewIdentity`). Outputs the resource ID and principal ID.
- **Role assignment module**: Assigns `AcrPull` on the ACR to the UAMI's principal ID, using the full ACR resource ID to support cross-resource-group scenarios. Must be idempotent (uses deterministic `guid()` for assignment names). Note: `Key Vault Secrets User` is NOT assigned by this module — it is an external prerequisite.
- **Log Analytics module**: Creates the Log Analytics workspace (`law-{appName}-{env}`) with `PerGB2018` SKU and configurable retention.
- **ACA environment module**: Creates the managed environment (`cae-{appName}-{env}`), wired to the Log Analytics workspace for log ingestion. Conditionally skipped if `existingManagedEnvironmentId` is provided, in which case the container app deploys into the existing environment. Accepts optional VNET parameters (`subnetId`) to deploy a VNET-integrated managed environment when provided.
- **Container app module**: Creates the container app (`ca-{appName}-{env}`) with:
  - Identity-based ACR registry configuration.
  - Key Vault–backed secrets mapped to environment variables.
  - Plain environment variables from the parameter file.
  - Configurable ingress (external/internal, target port, TLS).
  - Configurable scaling (min/max replicas).
  - Resource allocation (CPU, memory).

### Per-Environment Parameter Files

Each `parameters.{env}.bicepparam` controls:

| Category | Parameters | Varies by env? |
|----------|-----------|----------------|
| Naming | `appName`, `environmentName` | `environmentName` varies |
| Sizing | `containerCpu`, `containerMemory`, `minReplicas`, `maxReplicas` | Yes |
| Image | `containerImage` | Yes (tag differs) |
| Networking | `ingressExternal`, `targetPort` | May vary |
| Configuration | `appEnvVars` (log level, feature flags, runtime settings) | Yes |
| Secrets | `secretEnvVars` (Key Vault URIs per env) | Yes |
| Tags | `tags` (Environment, Project, ManagedBy) | `Environment` tag varies |
| Identity | `createNewIdentity`, `existingIdentityResourceId` | May vary |
| ACA Environment | `existingManagedEnvironmentId` (optional) | May vary |
| VNET | `subnetId` (optional) | May vary |

### Naming and Tagging Conventions

- Naming pattern: `{prefix}-{appName}-{environmentName}` where prefix is resource-type-specific (`id-`, `law-`, `cae-`, `ca-`).
- Tags required on every resource: `Environment`, `Project`, `ManagedBy` (value: `bicep`).
- Additional tags (e.g., `CostCenter`, `Owner`) are encouraged and passed via the `tags` parameter.

---

## 6. Configuration and Secrets Handling

### Sensitive Values

- All secrets are stored in **Azure Key Vault**, one Key Vault per environment.
- Bicep references secrets via `keyVaultSecretUri` in the `secretEnvVars` array parameter.
- ACA secrets are configured with `keyVaultUrl` and the UAMI's resource ID as `identity`.
- The container app exposes these as environment variables via `secretRef` mappings.
- Constraint: secret values MUST NOT appear in Bicep parameter files, GitHub repository settings, or workflow logs.

### Non-Sensitive Values

- Passed as plain environment variables in the `appEnvVars` array parameter in each `parameters.{env}.bicepparam`.
- Typical entries: `ASPNETCORE_ENVIRONMENT`, `LOG_LEVEL`, `FEATURE_FLAG_*`.
- These values are visible in source control and are environment-specific.

### Parameter File Schema

```
appEnvVars: [
  { name: string, value: string }
]

secretEnvVars: [
  { name: string, secretRef: string, keyVaultSecretUri: string }
]
```

- `name`: Environment variable name exposed to the container.
- `value`: Plaintext value (non-sensitive only).
- `secretRef`: Internal ACA secret name (unique per container app).
- `keyVaultSecretUri`: Full Key Vault secret URI (e.g., `https://kv-{app}-{env}.vault.azure.net/secrets/{secret-name}`).

---

## 7. GitHub Actions Workflows and Orchestration

### Workflow Behaviors per Environment

| Environment | Trigger | Approval | Protections |
|-------------|---------|----------|-------------|
| `dev` | Auto on push to `main` (when `infra/` modified) | None | None |
| `qa` | Manual dispatch or tagged commit | Optional | Environment protection rules |
| `prod` | Manual dispatch only | Required (manual approval) | Protected branch + required reviewers |

### Workflow Steps

1. **Checkout** the repository.
2. **Authenticate** to Azure using `azure/login@v2` with OIDC (client-id, tenant-id, subscription-id from GitHub Environment secrets/variables).
3. **Select parameter file** based on environment input: `infra/parameters.{env}.bicepparam`.
4. **Run what-if** preview: `az deployment group what-if --template-file infra/main.bicep --parameters infra/parameters.{env}.bicepparam`.
5. **Evaluate what-if output**: Parse the what-if result for resource deletions. If deletions are detected and the `allow-destructive` input is not `true`, **abort the workflow** with a clear error message listing the resources that would be deleted. The operator must re-run the workflow with `allow-destructive: true` to proceed.
6. **Deploy**: `az deployment group create --template-file infra/main.bicep --parameters infra/parameters.{env}.bicepparam --name "aca-infra-{env}-{timestamp}"`.
7. **Surface outputs** (container app name, FQDN, resource ID) as step outputs for downstream jobs.

### Reusable Workflow Pattern

The shared `infra-deploy` workflow accepts these inputs:

| Input | Type | Required | Description |
|-------|------|----------|-------------|
| `environment` | `string` | Yes | Target environment name (`dev`, `qa`, `prod`) |
| `azure-subscription-id` | `string` | Yes | Azure subscription ID |
| `azure-resource-group` | `string` | Yes | Target resource group name |
| `parameter-file` | `string` | Yes | Path to the Bicep parameter file |
| `container-image-tag` | `string` | No | Container image tag to override in the deployment |
| `allow-destructive` | `boolean` | No (default: `false`) | When `true`, allows deployment to proceed even if what-if detects resource deletions |

App repositories call this workflow and supply their own inputs. The shared workflow handles authentication, what-if, and deployment.

---

## 8. Multi-App and Multi-Repo Reuse

### Consumption Model

- This repository serves as a **shared infrastructure framework**.
- App repositories consume it by either:
  1. Calling the reusable GitHub Actions workflow with their own inputs.
  2. Referencing the Bicep modules from a shared registry or Git path.
  3. Forking the repository and maintaining their own parameter files.

### What Each App Repo Must Provide

- `appName`: Base name for resource naming.
- `acrName`: Name of the existing ACR holding the app's images.
- `containerImage`: Full image reference (registry/repo:tag).
- Per-environment parameter files with app-specific `appEnvVars`, `secretEnvVars`, sizing, and Key Vault URIs.
- GitHub Environment secrets (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`) and variables (`AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`).

### What the Shared Framework Guarantees

- Correct UAMI creation and role assignment pattern.
- Key Vault secret integration into ACA secrets.
- Log Analytics observability baseline.
- Consistent naming and tagging.
- OIDC authentication pattern.
- What-if preview before every deployment.
- Idempotent, re-runnable deployments.

---

## 9. Security, Compliance, and Guardrails

### Non-Negotiable Security Properties

- **No registry passwords**: Container images are pulled using the UAMI's `AcrPull` role via identity-based authentication. No `docker login` credentials stored anywhere.
- **No secrets in source control**: All sensitive values live in Key Vault. Bicep parameters reference Key Vault URIs, not plaintext values. GitHub Actions secrets contain only OIDC identifiers (client ID, tenant ID), not application secrets.
- **TLS enforced**: External endpoints must have `allowInsecure: false`. HTTP-to-HTTPS redirection is handled by ACA's ingress layer.
- **Least-privilege RBAC**: The UAMI receives only `AcrPull` and `Key Vault Secrets User`. The GitHub Actions service principal receives only `Contributor` and `User Access Administrator` scoped to the target resource group.
- **No manual portal changes**: All infrastructure configuration is defined in Bicep and deployed via CI/CD. Break-glass portal changes must be back-ported to Bicep within 24 hours.

### Audit and Logging

- All ACA environments log to a dedicated Log Analytics workspace.
- GitHub Actions workflow runs provide an audit trail of every deployment, including what-if output.
- Git history serves as the change log for all infrastructure modifications.
- Resource tags (`Environment`, `Project`, `ManagedBy`) enable cost allocation and ownership tracking.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The framework MUST provision a user-assigned managed identity per environment with the naming convention `id-{appName}-{env}`, or accept an existing identity resource ID.
- **FR-002**: The framework MUST assign the `AcrPull` role to the managed identity on the specified ACR using the full ACR resource ID (supporting cross-resource-group scenarios), with a deterministic role assignment name to ensure idempotency.
- **FR-003**: The framework MUST create a Log Analytics workspace per environment (`law-{appName}-{env}`) with a minimum 30-day retention.
- **FR-004**: The framework MUST create an ACA managed environment per environment (`cae-{appName}-{env}`) wired to the Log Analytics workspace, OR accept an existing managed environment resource ID (`existingManagedEnvironmentId`) and deploy the container app into it. When creating a new environment, if a `subnetId` parameter is provided, the managed environment MUST be deployed with VNET integration into the specified subnet.
- **FR-005**: The framework MUST deploy a container app per environment (`ca-{appName}-{env}`) configured with identity-based ACR pull, Key Vault–backed secrets, configurable scaling, and configurable ingress.
- **FR-006**: The framework MUST support per-environment parameter files that control sizing (CPU, memory, replicas), environment variables, Key Vault secret references, and tags.
- **FR-007**: The framework MUST enforce `allowInsecure: false` on all container app ingress configurations.
- **FR-008**: The framework MUST provide a GitHub Actions reusable workflow that accepts environment name, subscription, resource group, parameter file path, and optional image tag as inputs.
- **FR-009**: The reusable workflow MUST run a what-if preview before every deployment and surface deployment outputs (app name, FQDN, resource ID). If the what-if output detects resource deletions, the workflow MUST auto-abort the deployment. To proceed despite deletions, the operator must manually re-run the workflow with an explicit `allow-destructive` override flag set to `true`.
- **FR-010**: The framework MUST authenticate to Azure using workload identity federation (OIDC) with no long-lived client secrets.
- **FR-011**: The framework MUST support `dev` auto-deploy on push, `qa` on manual dispatch or tag, and `prod` with required manual approval.
- **FR-012**: All deployments MUST be idempotent — re-running the same deployment with the same parameters must produce no changes. The recovery model for partial failures is fix-forward: the operator corrects the issue and re-runs the workflow; no automated rollback is supported.
- **FR-013**: The framework MUST apply the tags `Environment`, `Project`, and `ManagedBy` to every provisioned resource.
- **FR-014**: Secret values MUST NOT appear in Bicep parameter files, GitHub repository settings (except OIDC identifiers), or workflow logs.

### Key Entities

- **Managed Identity**: Per-environment UAMI used by container apps for ACR pull and Key Vault access. Key attributes: name, resource ID, principal ID.
- **Role Assignment**: Binding between a managed identity and an Azure role on a target resource. Key attributes: role definition ID, principal ID, scope.
- **ACA Managed Environment**: Hosting environment for container apps in a deployment stage. Key attributes: name, location, Log Analytics binding.
- **Container App**: The deployed application workload. Key attributes: name, image, identity, ingress config, secrets, env vars, scaling rules.
- **Parameter File**: Per-environment configuration file. Key attributes: environment name, sizing, env vars, secret references, tags.
- **Reusable Workflow**: GitHub Actions callable workflow. Key attributes: inputs (environment, subscription, resource group, parameter file, image tag), OIDC auth, what-if step, deploy step.

---

## 10. Open Questions and Assumptions

### Assumptions

- The ACR already exists in a known resource group and subscription (which may differ from the container app's resource group). This framework does not create it. The ACR's full resource ID is provided as a parameter, enabling cross-resource-group role assignment.
- One Key Vault per environment already exists and contains the required secrets. This framework does not create or populate Key Vault.
- The UAMI's `Key Vault Secrets User` role assignment on the environment's Key Vault is pre-configured externally (e.g., by the Key Vault owner or identity team) before the first deployment. This framework does not assign Key Vault roles.
- The pipeline service principal has `User Access Administrator` on the ACR's resource group (which may differ from the deployment target resource group) to enable `AcrPull` role assignment.
- Each environment has its own Azure resource group following the convention `rg-{appName}-{env}`.
- Networking is the default ACA public ingress model. When a `subnetId` parameter is provided, the ACA managed environment is deployed with VNET integration into the specified subnet. NSG and subnet delegation are the caller's responsibility.
- An existing ACA managed environment may be reused across multiple apps or deployments by providing `existingManagedEnvironmentId`. When provided, the framework skips managed environment creation and deploys the container app into the existing environment.
- A single container per container app is the default. Multi-container sidecars are supported via parameter extension but not specified here.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A new application team can onboard to this framework and deploy a container app to `dev` within 30 minutes by providing only `appName`, `acrName`, `containerImage`, and per-environment parameter files.
- **SC-002**: All three environments (`dev`, `qa`, `prod`) can be provisioned from scratch using the framework, each with correct naming, sizing, and identity bindings, in a single pipeline run per environment.
- **SC-003**: 100% of secrets consumed by the container app are sourced from Key Vault; zero secrets appear in parameter files, workflow logs, or GitHub repository settings.
- **SC-004**: Re-running any environment's deployment with unchanged parameters produces zero resource modifications (full idempotency).
- **SC-005**: The `prod` deployment cannot proceed without manual approval — 100% enforcement via GitHub Environment protection rules.
- **SC-006**: No long-lived Azure client secrets exist in GitHub repository or environment settings; all Azure authentication uses OIDC federated credentials.
- **SC-007**: Every provisioned resource carries the required tags (`Environment`, `Project`, `ManagedBy`), verifiable via Azure Resource Graph query.
