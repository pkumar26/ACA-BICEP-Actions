# Data Model: Multi-Environment ACA Provisioning & Deployment Framework

**Date**: 2026-02-28 | **Branch**: `001-aca-multienv-framework`
**Prerequisite**: [research.md](research.md) complete

This document defines the parameter surface area (the "data model" for this IaC framework), module interfaces, resource entities, and state transitions.

---

## 1. Bicep Parameter Surface Area (`main.bicep` Orchestrator)

These are the top-level parameters accepted by `infra/main.bicep`. Each parameter is consumed by one or more modules.

### Core Parameters

| Parameter | Type | Required | Default | Consumed By | Change from Existing |
|-----------|------|----------|---------|-------------|---------------------|
| `environmentName` | `string` (`dev`\|`qa`\|`prod`) | Yes | — | All modules (naming) | No change |
| `appName` | `string` | Yes | — | All modules (naming) | No change |
| `location` | `string` | No | `resourceGroup().location` | All modules | No change |

### Identity Parameters

| Parameter | Type | Required | Default | Consumed By | Change from Existing |
|-----------|------|----------|---------|-------------|---------------------|
| `createNewIdentity` | `bool` | No | `true` | `identity.bicep` | No change |
| `existingIdentityResourceId` | `string` | No | `''` | `identity.bicep`, `container-app.bicep` | No change |

### ACR Parameters

| Parameter | Type | Required | Default | Consumed By | Change from Existing |
|-----------|------|----------|---------|-------------|---------------------|
| `acrResourceId` | `string` | Yes | — | `acr-role-assignment.bicep`, `container-app.bicep` | **NEW** — replaces `acrName` |

**Migration**: The existing `acrName` parameter (plain string) is replaced by `acrResourceId` (full ARM resource ID). The orchestrator derives `acrName` and `acrResourceGroup` using:
```bicep
var acrResourceGroup = split(acrResourceId, '/')[4]
var acrName = last(split(acrResourceId, '/'))
```

### ACA Environment Parameters

| Parameter | Type | Required | Default | Consumed By | Change from Existing |
|-----------|------|----------|---------|-------------|---------------------|
| `existingManagedEnvironmentId` | `string` | No | `''` | `managed-environment.bicep`, `container-app.bicep` | **NEW** |
| `subnetId` | `string` | No | `''` | `managed-environment.bicep` | **NEW** |

### Container App Parameters

| Parameter | Type | Required | Default | Consumed By | Change from Existing |
|-----------|------|----------|---------|-------------|---------------------|
| `containerImage` | `string` | No | `'mcr.microsoft.com/k8se/quickstart:latest'` | `container-app.bicep` | No change |
| `targetPort` | `int` | No | `80` | `container-app.bicep` | No change |
| `containerCpu` | `string` | No | `'0.5'` | `container-app.bicep` | No change |
| `containerMemory` | `string` | No | `'1Gi'` | `container-app.bicep` | No change |
| `minReplicas` | `int` | No | `0` | `container-app.bicep` | No change |
| `maxReplicas` | `int` | No | `3` | `container-app.bicep` | No change |
| `ingressExternal` | `bool` | No | `true` | `container-app.bicep` | No change |

### Configuration Parameters

| Parameter | Type | Required | Default | Consumed By | Change from Existing |
|-----------|------|----------|---------|-------------|---------------------|
| `appEnvVars` | `array` | No | `[]` | `container-app.bicep` | No change |
| `secretEnvVars` | `array` | No | `[]` | `container-app.bicep` | No change |
| `tags` | `object` | No | `{}` | All modules | No change |

---

## 2. Module Interfaces

Each module is a Bicep file under `infra/modules/` with defined inputs (params) and outputs.

### 2.1 `identity.bicep` — User-Assigned Managed Identity

**Purpose**: Conditionally create a UAMI or resolve an existing one.

**Parameters**:
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `resourceSuffix` | `string` | Yes | `{appName}-{environmentName}` for naming |
| `location` | `string` | Yes | Azure region |
| `tags` | `object` | Yes | Resource tags |
| `createNewIdentity` | `bool` | Yes | Whether to create a new identity |
| `existingIdentityResourceId` | `string` | No | Full resource ID of existing identity |

**Outputs**:
| Output | Type | Description |
|--------|------|-------------|
| `identityResourceId` | `string` | Resource ID of the UAMI (new or existing) |
| `identityPrincipalId` | `string` | Principal ID for role assignments |

**Condition**: The internal `newIdentity` resource uses `if (createNewIdentity)`. The `existingIdentity` resource uses `if (!createNewIdentity)`.

---

### 2.2 `acr-role-assignment.bicep` — AcrPull Role on ACR

**Purpose**: Assign the `AcrPull` role to a principal on a specified ACR. Deployed with `scope: resourceGroup(acrResourceGroup)` to support cross-RG.

**Parameters**:
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `acrName` | `string` | Yes | Name of the ACR (derived from resource ID by orchestrator) |
| `principalId` | `string` | Yes | Principal ID of the managed identity |

**Outputs**: None (role assignments have no meaningful outputs).

**Notes**:
- The role definition ID (`7f951dda-4ed3-4680-a7ca-43fe172d538d`) is hardcoded as a variable.
- Assignment name uses `guid(acr.id, principalId, acrPullRoleId)` for idempotency.
- `principalType: 'ServicePrincipal'` is always set.
- The module is called with `scope: resourceGroup(acrResourceGroup)` from the orchestrator.

---

### 2.3 `log-analytics.bicep` — Log Analytics Workspace

**Purpose**: Create a Log Analytics workspace for ACA log ingestion.

**Parameters**:
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `resourceSuffix` | `string` | Yes | `{appName}-{environmentName}` for naming |
| `location` | `string` | Yes | Azure region |
| `tags` | `object` | Yes | Resource tags |

**Outputs**:
| Output | Type | Description |
|--------|------|-------------|
| `workspaceId` | `string` | Resource ID of the workspace |
| `customerId` | `string` | Workspace customer ID (for ACA binding) |
| `primarySharedKey` | `string` | Shared key (for ACA log analytics config) |

**Notes**:
- SKU is hardcoded to `PerGB2018`.
- Retention is hardcoded to 30 days (per spec FR-003).
- If retention needs vary, add a `retentionInDays` param with default `30`.

---

### 2.4 `managed-environment.bicep` — ACA Managed Environment

**Purpose**: Create an ACA managed environment wired to Log Analytics, with optional VNET integration.

**Parameters**:
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `resourceSuffix` | `string` | Yes | `{appName}-{environmentName}` for naming |
| `location` | `string` | Yes | Azure region |
| `tags` | `object` | Yes | Resource tags |
| `logAnalyticsCustomerId` | `string` | Yes | LAW customer ID |
| `logAnalyticsPrimarySharedKey` | `string` | Yes | LAW shared key (secure) |
| `subnetId` | `string` | No | Subnet resource ID for VNET integration |

**Outputs**:
| Output | Type | Description |
|--------|------|-------------|
| `environmentId` | `string` | Resource ID of the managed environment |
| `environmentName` | `string` | Name of the managed environment |

**Conditional Logic**:
- This module is conditionally deployed at the orchestrator level: `if (empty(existingManagedEnvironmentId))`.
- Internally, VNET configuration is conditional: `vnetConfiguration: !empty(subnetId) ? { infrastructureSubnetId: subnetId } : null`.

---

### 2.5 `container-app.bicep` — Container App

**Purpose**: Deploy a container app with identity-based ACR, KV secrets, environment variables, ingress, and scaling.

**Parameters**:
| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `resourceSuffix` | `string` | Yes | `{appName}-{environmentName}` for naming |
| `appName` | `string` | Yes | Base app name (used as container name) |
| `location` | `string` | Yes | Azure region |
| `tags` | `object` | Yes | Resource tags |
| `managedEnvironmentId` | `string` | Yes | Resolved ACA env ID (new or existing) |
| `identityResourceId` | `string` | Yes | UAMI resource ID |
| `acrLoginServer` | `string` | Yes | ACR login server (e.g., `demoacr.azurecr.io`) |
| `containerImage` | `string` | Yes | Full container image reference |
| `targetPort` | `int` | Yes | Container listen port |
| `containerCpu` | `string` | Yes | CPU allocation |
| `containerMemory` | `string` | Yes | Memory allocation |
| `minReplicas` | `int` | Yes | Min replicas |
| `maxReplicas` | `int` | Yes | Max replicas |
| `ingressExternal` | `bool` | Yes | External ingress enabled |
| `appEnvVars` | `array` | No | Plain environment variables |
| `secretEnvVars` | `array` | No | Key Vault-backed secrets |

**Outputs**:
| Output | Type | Description |
|--------|------|-------------|
| `containerAppName` | `string` | Name of the container app |
| `containerAppFqdn` | `string` | FQDN of the container app |
| `containerAppResourceId` | `string` | Resource ID of the container app |

**Internal Logic**:
- Builds `containerAppSecrets` array from `secretEnvVars` (KV URL + identity mapping).
- Builds merged `containerEnvVars` from `appEnvVars` + secret ref mappings.
- Sets `allowInsecure: false` (hardcoded, per FR-007).
- Sets `activeRevisionsMode: 'Single'`.
- Sets `dependsOn` on the role assignment module (ensured at orchestrator level).

---

## 3. Orchestrator Wiring (`main.bicep`)

The orchestrator calls modules in dependency order and resolves conditional outputs:

```text
┌─────────────────────────────┐
│    main.bicep (orchestrator) │
│                             │
│  param acrResourceId ─────────►  var acrResourceGroup = split(...)[4]
│                             │    var acrName = last(split(...))
│                             │    var acrLoginServer = '${acrName}.azurecr.io'
│                             │
│  ┌─── identity.bicep ──────┐│    (always runs; internal condition)
│  │ → identityResourceId    ││
│  │ → identityPrincipalId   ││
│  └──────────────────────────┘│
│                             │
│  ┌─── acr-role-assignment ──┐│    scope: resourceGroup(acrResourceGroup)
│  │   (acrName, principalId) ││
│  └──────────────────────────┘│
│                             │
│  ┌─── log-analytics.bicep ──┐│    (always runs)
│  │ → workspaceId            ││
│  │ → customerId             ││
│  │ → primarySharedKey       ││
│  └──────────────────────────┘│
│                             │
│  ┌─── managed-environment ──┐│    if (empty(existingManagedEnvironmentId))
│  │ → environmentId          ││
│  └──────────────────────────┘│
│                             │
│  var resolvedEnvId = ...    │    ternary: new or existing
│                             │
│  ┌─── container-app.bicep ──┐│    (always runs)
│  │ → containerAppName       ││
│  │ → containerAppFqdn       ││
│  │ → containerAppResourceId ││
│  └──────────────────────────┘│
│                             │
│  outputs: (bubble up from   │
│            container-app +  │
│            identity modules)│
└─────────────────────────────┘
```

---

## 4. Entity Definitions

### 4.1 User-Assigned Managed Identity

| Field | ARM Property | Type | Example |
|-------|-------------|------|---------|
| Name | `name` | string | `id-myapp-dev` |
| Location | `location` | string | `eastus2` |
| Resource ID | `id` | string | `/subscriptions/.../userAssignedIdentities/id-myapp-dev` |
| Principal ID | `properties.principalId` | string | GUID |
| Tags | `tags` | object | `{ Environment: 'dev', Project: 'myapp', ManagedBy: 'bicep' }` |

**State Transitions**: Created → Exists (idempotent on re-deploy) | Skipped (when `createNewIdentity = false`)

---

### 4.2 Role Assignment

| Field | ARM Property | Type | Example |
|-------|-------------|------|---------|
| Name | `name` | GUID | `guid(acr.id, principalId, roleId)` |
| Scope | `scope` | resource ref | ACR resource |
| Role Definition ID | `properties.roleDefinitionId` | string | `7f951dda-...` (AcrPull) |
| Principal ID | `properties.principalId` | string | UAMI's principal ID |
| Principal Type | `properties.principalType` | string | `ServicePrincipal` |

**State Transitions**: Created → Exists (idempotent via deterministic GUID name)

---

### 4.3 Log Analytics Workspace

| Field | ARM Property | Type | Example |
|-------|-------------|------|---------|
| Name | `name` | string | `law-myapp-dev` |
| Location | `location` | string | `eastus2` |
| SKU | `properties.sku.name` | string | `PerGB2018` |
| Retention | `properties.retentionInDays` | int | `30` |
| Customer ID | `properties.customerId` | string | GUID |
| Tags | `tags` | object | Standard tags |

**State Transitions**: Created → Updated (retention changes) → Exists (no-change re-deploy)

---

### 4.4 ACA Managed Environment

| Field | ARM Property | Type | Example |
|-------|-------------|------|---------|
| Name | `name` | string | `cae-myapp-dev` |
| Location | `location` | string | `eastus2` |
| Log Analytics Binding | `properties.appLogsConfiguration` | object | LAW customer ID + shared key |
| VNET Config | `properties.vnetConfiguration` | object \| null | `{ infrastructureSubnetId: '...' }` or null |
| Tags | `tags` | object | Standard tags |

**State Transitions**: Created → Exists (idempotent) | Skipped (when `existingManagedEnvironmentId` provided)

---

### 4.5 Container App

| Field | ARM Property | Type | Example |
|-------|-------------|------|---------|
| Name | `name` | string | `ca-myapp-dev` |
| Location | `location` | string | `eastus2` |
| Identity | `identity.userAssignedIdentities` | object | `{ '<uamiId>': {} }` |
| Managed Env ID | `properties.managedEnvironmentId` | string | Resource ID |
| Ingress | `properties.configuration.ingress` | object | `{ external: true, targetPort: 80, allowInsecure: false }` |
| Registry | `properties.configuration.registries` | array | `[{ server: 'acr.azurecr.io', identity: '<uamiId>' }]` |
| Secrets | `properties.configuration.secrets` | array | KV-backed secrets |
| Containers | `properties.template.containers` | array | Image, CPU, memory, env vars |
| Scale | `properties.template.scale` | object | `{ minReplicas, maxReplicas }` |
| Tags | `tags` | object | Standard tags |

**State Transitions**: Created → Updated (image change, scaling change, env var change) → Exists (no-change re-deploy)

---

## 5. Parameter File Schema Changes

### Parameters Being Changed

| Parameter | Old Value | New Value | Example |
|-----------|-----------|-----------|---------|
| `acrName` | `'demoacr'` | **REMOVED** — replaced by `acrResourceId` | — |
| `acrResourceId` | N/A (new) | Full ARM resource ID | `'/subscriptions/xxx/resourceGroups/rg-shared/providers/Microsoft.ContainerRegistry/registries/demoacr'` |
| `existingManagedEnvironmentId` | N/A (new) | Optional ARM resource ID | `''` (default = create new) |
| `subnetId` | N/A (new) | Optional subnet resource ID | `''` (default = no VNET) |

### appEnvVars Schema (unchanged)

```bicep
[
  { name: 'ASPNETCORE_ENVIRONMENT', value: 'Development' }
  { name: 'LOG_LEVEL', value: 'Debug' }
]
```

### secretEnvVars Schema (unchanged)

```bicep
[
  {
    name: 'DB_CONNECTION'           // env var name exposed to container
    secretRef: 'db-connection'      // ACA secret name (unique per app)
    keyVaultSecretUri: 'https://kv-myapp-dev.vault.azure.net/secrets/db-connection'
  }
]
```

### Validation Rules

| Rule | Applies To | Enforcement |
|------|-----------|-------------|
| `acrResourceId` must be a valid ARM resource ID | `acrResourceId` | Bicep runtime (ARM validates resource existence) |
| `maxReplicas >= minReplicas` | Scaling params | ACA API validation |
| `maxReplicas >= 1` when `minReplicas > 0` | Scaling params | ACA API validation |
| `containerCpu` must be valid ACA tier | CPU param | ACA API validation (0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 4) |
| `secretEnvVars[*].secretRef` must be unique | Secret env vars | ACA API validation |
| `tags` must include `Environment`, `Project`, `ManagedBy` | Tags | Convention (not enforced by template) |

---

## 6. Outputs (from `main.bicep`)

| Output | Type | Source Module | Description |
|--------|------|--------------|-------------|
| `containerAppName` | `string` | `container-app.bicep` | Name of the deployed container app |
| `containerAppFqdn` | `string` | `container-app.bicep` | FQDN for HTTP access |
| `containerAppResourceId` | `string` | `container-app.bicep` | Full ARM resource ID |
| `identityResourceId` | `string` | `identity.bicep` | UAMI resource ID |
| `managedEnvironmentName` | `string` | `managed-environment.bicep` or derived from `existingManagedEnvironmentId` | ACA environment name |
