# Plan: Multi-Environment ACA Provisioning with Bicep + GitHub Actions

Use **Bicep** for declarative infrastructure and **GitHub Actions** for orchestration across `dev`, `qa`, and `prod`. A **user-assigned managed identity** is created first, granted `AcrPull` on the existing ACR, then referenced by the Container App — avoiding the bootstrap problem where the app needs to pull an image before its identity has permissions. Sensitive env vars are stored as ACA secrets sourced from **Azure Key Vault** (accessed via the same managed identity), while non-sensitive config is passed as plain env vars through per-environment Bicep parameter files. Authentication uses **workload identity federation (OIDC)**.

---

## Steps

### 1. Create the Bicep template — `infra/main.bicep`

Define Bicep `param` declarations for all environment-varying inputs: `environmentName` (dev/qa/prod), resource name suffixes, `appEnvVars` (array of `{name, value}` objects), `secretEnvVars` (array of `{name, secretRef, keyVaultSecretUri}` objects), scaling rules, ACR server name, etc.

#### Identity: create new or use existing

Add the following parameters to control identity provisioning:

```bicep
@description('Set to true to create a new user-assigned managed identity; false to use an existing one.')
param createNewIdentity bool = true

@description('Resource ID of an existing user-assigned managed identity. Required when createNewIdentity is false.')
param existingIdentityResourceId string = ''
```

Use a **conditional resource** for the identity:

```bicep
resource newIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (createNewIdentity) {
  name: 'id-${appName}-${environmentName}'
  location: location
}

resource existingIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = if (!createNewIdentity) {
  name: last(split(existingIdentityResourceId, '/'))
  scope: resourceGroup(split(existingIdentityResourceId, '/')[2], split(existingIdentityResourceId, '/')[4])
}
```

Derive resolved values used by downstream resources:

```bicep
var identityResourceId = createNewIdentity ? newIdentity.id : existingIdentityResourceId
var identityPrincipalId = createNewIdentity ? newIdentity.properties.principalId : existingIdentity.properties.principalId
```

The role assignment and container app then reference `identityResourceId` and `identityPrincipalId` regardless of which path was taken.

Define the following resources in order:

| # | Resource | Key details |
|---|----------|-------------|
| 1 | `Microsoft.ManagedIdentity/userAssignedIdentities` | **Conditional** — only created when `createNewIdentity == true`. Named with env suffix, e.g. `id-myapp-dev`. Skipped when using an existing identity. |
| 2 | `Microsoft.Authorization/roleAssignments` | Scope: existing ACR (referenced via `existing` keyword). Role: `AcrPull` (`7f951dda-4ed3-4680-a7ca-43fe172d538d`). Principal: `identityPrincipalId`. **Skipped if you also add a `createRoleAssignment` flag** (useful when the existing identity already has `AcrPull`). |
| 3 | `Microsoft.OperationalInsights/workspaces` | One per environment for ACA logging |
| 4 | `Microsoft.App/managedEnvironments` | Links to the Log Analytics workspace |
| 5 | `Microsoft.App/containerApps` | System identity **off**, user-assigned identity **on** via `identityResourceId`. `configuration.registries` references the ACR server with `identity` set to `identityResourceId`. `template.containers[].env` merges plain env vars + secret-referenced env vars. `configuration.secrets` wired to Key Vault secret URIs using the same identity |

The `dependsOn` chain ensures the role assignment (when created) completes before the container app attempts to pull.

Use a placeholder/init image (e.g., `mcr.microsoft.com/k8se/quickstart:latest`) for the initial deployment — your existing app-deploy workflow will update it to the real image afterward.

### 2. Create per-environment parameter files

Create three Bicep parameter files:

- `infra/parameters.dev.bicepparam` — dev-specific values: resource names with `-dev` suffix, lower scaling (min 0, max 1), `LOG_LEVEL=Debug`, dev Key Vault URI, etc.
- `infra/parameters.qa.bicepparam` — QA values: `-qa` suffix, moderate scaling, `LOG_LEVEL=Information`, QA Key Vault URI.
- `infra/parameters.prod.bicepparam` — prod values: `-prod` suffix, higher scaling (min 1, max 10), `LOG_LEVEL=Warning`, prod Key Vault URI.

Example structure of the parameters:

```bicep
// Identity — create new (default for most environments)
createNewIdentity = true

// OR — use existing (e.g., a shared identity already provisioned)
// createNewIdentity = false
// existingIdentityResourceId = '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-shared-dev'

appEnvVars = [
  { name: 'LOG_LEVEL', value: 'Debug' }
  { name: 'FEATURE_FLAG_X', value: 'true' }
]
secretEnvVars = [
  { name: 'DB_CONNECTION', secretRef: 'db-connection', keyVaultSecretUri: 'https://kv-myapp-dev.vault.azure.net/secrets/db-connection' }
]
```

### 3. Configure GitHub Environments

Set up three GitHub environments — `dev`, `qa`, `prod` — each with:

- **Environment variables**: `AZURE_RESOURCE_GROUP`, `AZURE_SUBSCRIPTION_ID` (if different per env).
- **Environment secrets**: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` (for OIDC federated login per environment).
- **Protection rules**: `prod` requires manual approval; `qa` optionally requires approval; `dev` auto-deploys.

### 4. Configure OIDC federated credentials in Azure

For each environment, add a federated credential on the Azure AD app registration (or user-assigned managed identity used for deployment) scoped to the GitHub repo + environment:

- Subject: `repo:<org>/<repo>:environment:dev` (and similarly for `qa`, `prod`).
- Issuer: `https://token.actions.githubusercontent.com`
- Audience: `api://AzureADTokenExchange`

### 5. Create the infrastructure workflow — `.github/workflows/infra-deploy.yml`

A reusable/callable workflow triggered on pushes to `infra/**` or manual `workflow_dispatch` with an environment input.

Job structure:
1. **Checkout** the repo.
2. **`azure/login@v2`** — OIDC login using `client-id`, `tenant-id`, `subscription-id` from the GitHub environment.
3. **`azure/arm-deploy@v2`** — deploy `infra/main.bicep` with `infra/parameters.<env>.bicepparam`. Set `deploymentMode: Incremental`. Capture outputs (e.g., container app name, FQDN) as job outputs.

Use a **matrix strategy** or `workflow_call` with an `environment` input so the same workflow serves all three environments. Example trigger options:
- `workflow_dispatch` with environment dropdown for on-demand infra changes.
- Automatic on push to `main` for `dev`; manual promotion for `qa`/`prod`.

### 6. Wire into your existing app-deploy workflow

Your existing workflow that deploys the application image should:
- Optionally add a `needs: infra` job dependency if you combine both in one workflow.
- Or remain separate (recommended) — it already expects the ACA to exist, and after Step 5 runs once, it will.

### 7. Grant the deploying service principal the necessary Azure RBAC roles

The Azure AD app (used by GitHub Actions OIDC) needs:
- `Contributor` on the resource group (to create ACA, managed environment, Log Analytics, identity).
- `User Access Administrator` or `Role Based Access Control Administrator` on the ACR (to create the `AcrPull` role assignment).
- (Optionally) `Key Vault Secrets User` if the deployment needs to validate Key Vault references.

---

## Verification

1. **Dry-run validation**: Run `az deployment group validate --template-file infra/main.bicep --parameters infra/parameters.dev.bicepparam` locally or in CI to catch Bicep errors before deploying.
2. **What-if check**: Run `az deployment group what-if ...` in the workflow (or locally) to preview changes before applying.
3. **Post-deploy smoke test**: After the infra workflow succeeds, verify:
   - `az containerapp show -n <app-name> -g <rg>` returns the app with the correct identity and registry config.
   - `az role assignment list --scope <acr-resource-id>` shows the `AcrPull` assignment for the managed identity.
   - Trigger your existing app-deploy workflow — it should successfully pull the image from ACR and create a new revision.
4. **Environment variable check**: `az containerapp show ... --query "properties.template.containers[0].env"` returns the expected env vars for the target environment.

---

## Decisions

- **User-assigned identity** over system-assigned — avoids the bootstrapping problem where the app needs ACRPull before it exists. Supports both **creating a new identity** and **reusing an existing one** via a simple boolean toggle + resource ID parameter, so teams with shared identities aren't forced to create duplicates.
- **Bicep + GitHub Actions** over pure CLI — declarative, reviewable, idempotent infrastructure with CI/CD orchestration.
- **Bicep parameter files** (`.bicepparam`) per environment — keeps the template DRY; all env-specific config in one place per environment.
- **Key Vault–backed secrets** over GitHub Secrets for app env vars — secrets are managed in Azure, rotatable without re-deploying, and accessed via managed identity (no secret in the pipeline).
- **Placeholder image** for initial ACA creation — the real image is deployed by the existing app-deploy workflow; this avoids coupling infra provisioning to a specific app version.
