# Quickstart: Deploy Your First ACA Environment

**Time to complete**: ~30 minutes (per SC-001)

This guide walks through onboarding a new application to the Multi-Environment ACA Framework. By the end, you'll have a container app running in `dev`.

---

## Prerequisites

Before starting, ensure these external resources exist:

| Resource | Who Creates It | Example |
|----------|---------------|---------|
| Azure Container Registry (ACR) | Platform / Shared team | `demoacr.azurecr.io` |
| Azure Key Vault (per env) | Platform / App team | `kv-myapp-dev` |
| Azure Resource Group (per env) | Platform team | `rg-myapp-dev` |
| Entra ID App Registration + OIDC federated credential | Platform team | Subject: `repo:org/repo:environment:dev` |
| `Key Vault Secrets User` role for UAMI on KV | Key Vault owner | Pre-assigned before first deploy |
| Service Principal with `Contributor` + `User Access Administrator` on target RG + ACR RG | Platform team | Same app registration used for OIDC |
| Subnet delegated to `Microsoft.App/environments` | Network team | Only if using VNET integration |

---

## Step 1: Clone or Fork the Framework

```bash
git clone https://github.com/<owner>/ACA-BICEP-Actions.git
cd ACA-BICEP-Actions
```

Or fork the repo and clone your fork.

---

## Step 2: Configure Your Parameter File

Edit `infra/parameters.dev.bicepparam`:

```bicep
using './main.bicep'

// --- Core ---
param environmentName = 'dev'
param appName = 'myapp'                          // Replace with your app name

// --- ACR ---
param acrResourceId = '/subscriptions/<sub-id>/resourceGroups/<acr-rg>/providers/Microsoft.ContainerRegistry/registries/<acr-name>'

// --- Container App ---
param containerImage = 'mcr.microsoft.com/k8se/quickstart:latest'   // Placeholder for initial deploy
param containerCpu = '0.25'
param containerMemory = '0.5Gi'
param minReplicas = 0
param maxReplicas = 1
param targetPort = 80
param ingressExternal = true

// --- Environment Variables ---
param appEnvVars = [
  { name: 'ASPNETCORE_ENVIRONMENT', value: 'Development' }
  { name: 'LOG_LEVEL', value: 'Debug' }
]

// --- Secrets (Key Vault references) ---
param secretEnvVars = [
  // Uncomment and configure when your KV secrets are ready:
  // { name: 'DB_CONNECTION', secretRef: 'db-connection', keyVaultSecretUri: 'https://kv-myapp-dev.vault.azure.net/secrets/db-connection' }
]

// --- Tags ---
param tags = {
  Environment: 'dev'
  Project: 'myapp'
  ManagedBy: 'bicep'
}

// --- Optional: Existing Resources ---
param existingManagedEnvironmentId = ''           // Leave empty to create new
param subnetId = ''                                // Leave empty for no VNET
```

**Key items to replace**:
- `<sub-id>`, `<acr-rg>`, `<acr-name>` in `acrResourceId`
- `appName` — your application's base name
- `secretEnvVars` — your Key Vault secret URIs

---

## Step 3: Configure GitHub Environment

In your GitHub repo, go to **Settings → Environments** and create a `dev` environment with:

| Setting | Value |
|---------|-------|
| Secret: `AZURE_CLIENT_ID` | Your Entra ID app registration client ID |
| Secret: `AZURE_TENANT_ID` | Your Azure AD tenant ID |
| Variable: `AZURE_SUBSCRIPTION_ID` | Your Azure subscription ID |
| Variable: `AZURE_RESOURCE_GROUP` | `rg-myapp-dev` (your dev resource group) |

No protection rules needed for `dev`.

---

## Step 4: Push and Deploy

```bash
git add infra/
git commit -m "Configure dev environment for myapp"
git push origin main
```

The `deploy-dev.yml` workflow triggers automatically on push to `main` when files under `infra/` change. It will:

1. Authenticate to Azure via OIDC
2. Run `what-if` preview (check the workflow summary for changes)
3. Deploy the Bicep template
4. Output the container app name and FQDN

---

## Step 5: Verify

```bash
# Check the deployment
az containerapp show \
  --name ca-myapp-dev \
  --resource-group rg-myapp-dev \
  --query "{name:name, fqdn:properties.configuration.ingress.fqdn, status:properties.provisioningState}"

# Check the identity role assignment
az role assignment list \
  --assignee $(az identity show --name id-myapp-dev --resource-group rg-myapp-dev --query principalId -o tsv) \
  --scope "/subscriptions/<sub-id>/resourceGroups/<acr-rg>/providers/Microsoft.ContainerRegistry/registries/<acr-name>" \
  --query "[].{role:roleDefinitionName, scope:scope}"
```

Expected verification:
- Container app `ca-myapp-dev` exists with `Succeeded` provisioning state
- FQDN is accessible via HTTPS
- `AcrPull` role assignment exists on the ACR for the UAMI
- All resources tagged with `Environment: dev`, `Project: myapp`, `ManagedBy: bicep`

---

## Next Steps

### Deploy to QA

1. Edit `infra/parameters.qa.bicepparam` with qa-specific values (larger sizing, qa Key Vault URIs).
2. Create a `qa` GitHub Environment with appropriate secrets/variables.
3. Trigger `deploy-qa.yml` manually via workflow dispatch.

### Deploy to Prod

1. Edit `infra/parameters.prod.bicepparam` with prod-specific values.
2. Create a `prod` GitHub Environment with **required reviewers** protection rule.
3. Trigger `deploy-prod.yml` manually. Approve when prompted.

### Deploy Your App Image

Once your real container image is in ACR:

1. Trigger the deployment workflow with `container-image-tag` set to your image tag.
2. Or update `containerImage` in the parameter file to the full image reference.

### VNET Integration

To deploy into a VNET:

1. Ensure you have a subnet delegated to `Microsoft.App/environments` (minimum `/23`).
2. Set `subnetId` in the parameter file to the full subnet resource ID.
3. Deploy — the managed environment will be created with VNET integration.

### Use an Existing ACA Environment

To deploy into a pre-existing managed environment:

1. Set `existingManagedEnvironmentId` to the full ARM resource ID of the existing environment.
2. Deploy — the framework skips environment creation and deploys the container app into the existing one.

### Configure Health Probes

After replacing the placeholder image with your real application image, configure liveness and readiness probes:

1. Add `livenessProbe` and `readinessProbe` to your container app's template in the Bicep parameter file or module.
2. Example: `{ type: 'HTTP', httpGet: { path: '/healthz', port: 80 }, initialDelaySeconds: 5, periodSeconds: 10 }`.
3. This ensures ACA can detect unhealthy containers and restart them automatically.
