# Azure Container App — Multi-Environment Infrastructure

Bicep + GitHub Actions templates to provision an Azure Container App with:

- **Multi-environment** support (dev / qa / prod)
- **User-assigned managed identity** (create new or bring your own)
- **ACRPull role assignment** on an existing Azure Container Registry
- **Key Vault–backed secrets** accessed at runtime by the container app
- **Per-environment configuration** via `.bicepparam` parameter files
- **OIDC / Workload Identity Federation** for passwordless GitHub → Azure auth

## Repository Structure

```
├── infra/
│   ├── main.bicep                    # Main Bicep template (all resources)
│   ├── parameters.dev.bicepparam     # Dev overrides
│   ├── parameters.qa.bicepparam      # QA overrides
│   └── parameters.prod.bicepparam    # Prod overrides
├── .github/
│   └── workflows/
│       └── infra-deploy.yml          # GitHub Actions deployment workflow
└── README.md
```

## Resources Provisioned

| Resource | Naming Convention | Notes |
|----------|-------------------|-------|
| User-Assigned Managed Identity | `id-{appName}-{env}` | Conditional — skipped if using an existing identity |
| ACRPull Role Assignment | — | Scoped to the existing ACR |
| Log Analytics Workspace | `law-{appName}-{env}` | 30-day retention, PerGB2018 SKU |
| Container Apps Managed Environment | `cae-{appName}-{env}` | Wired to Log Analytics |
| Container App | `ca-{appName}-{env}` | Identity-based ACR pull, Key Vault secrets |

## Prerequisites

- **Azure CLI** with the Bicep extension (`az bicep install`)
- **An existing Azure Container Registry** in the same resource group
- **An existing Azure Key Vault** per environment (for secret env vars)
- **A GitHub repository** with Environments configured (see [Setup](#3-configure-github-environments))

---

## Setup

### 1. Fork / Clone

```bash
git clone <your-repo-url>
cd <repo-name>
```

### 2. Customise Parameter Files

Edit each `infra/parameters.{env}.bicepparam` file to match your environment. At a minimum, update:

| Parameter | Description | Example |
|-----------|-------------|---------|
| `appName` | Base name for all resources | `aca-myapp` |
| `acrName` | Name of your existing ACR (no hyphens) | `myappacr` |
| `location` | Azure region | `eastus` |
| `containerImage` | Image to deploy (placeholder is fine for first run) | `myappacr.azurecr.io/api:v1` |
| `targetPort` | Port your container listens on | `8080` |
| `appEnvVars` | Non-sensitive env vars | See parameter file for format |
| `secretEnvVars` | Key Vault–backed secret env vars | See parameter file for format |

#### Using an existing managed identity

Set these parameters in the `.bicepparam` file:

```bicep
param createNewIdentity = false
param existingIdentityResourceId = '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<name>'
```

#### Environment variable format

```bicep
// Non-sensitive
param appEnvVars = [
  { name: 'LOG_LEVEL', value: 'Debug' }
  { name: 'ASPNETCORE_ENVIRONMENT', value: 'Development' }
]

// Secret (Key Vault reference)
param secretEnvVars = [
  {
    name: 'DB_CONNECTION'
    secretRef: 'db-connection'
    keyVaultSecretUri: 'https://kv-myapp-dev.vault.azure.net/secrets/db-connection'
  }
]
```

### 3. Configure GitHub Environments

Create three GitHub Environments — `dev`, `qa`, `prod` — in your repository settings (**Settings → Environments**).

For each environment, add:

| Type | Name | Value |
|------|------|-------|
| **Secret** | `AZURE_CLIENT_ID` | App registration client ID (the one with federated credentials) |
| **Secret** | `AZURE_TENANT_ID` | Your Entra ID tenant ID |
| **Variable** | `AZURE_SUBSCRIPTION_ID` | Target Azure subscription ID |
| **Variable** | `AZURE_RESOURCE_GROUP` | Target resource group name |

> **Tip:** For `prod`, enable **required reviewers** as a protection rule so deploys need manual approval.

### 4. Set Up Workload Identity Federation (OIDC)

This eliminates the need for long-lived secrets in GitHub.

1. **Create an App Registration** in Entra ID (or reuse an existing one).

2. **Add a federated credential** for each environment:

   | Setting | Value |
   |---------|-------|
   | Issuer | `https://token.actions.githubusercontent.com` |
   | Subject | `repo:<org>/<repo>:environment:<env>` |
   | Audience | `api://AzureADTokenExchange` |

   Repeat for `dev`, `qa`, and `prod`.

3. **Grant the app registration** the following roles on the target resource group:

   | Role | Purpose |
   |------|---------|
   | Contributor | Create / update resources |
   | User Access Administrator | Assign ACRPull role to the managed identity |

### 5. Create Key Vaults and Populate Secrets

For each environment, create a Key Vault and add your application secrets:

```bash
# Example for dev
az keyvault create --name kv-myapp-dev --resource-group rg-myapp-dev --location eastus
az keyvault secret set --vault-name kv-myapp-dev --name db-connection --value "<connection-string>"
az keyvault secret set --vault-name kv-myapp-dev --name api-key --value "<api-key>"
```

Grant the managed identity read access:

```bash
# Get the identity principal ID (after first deploy, or if pre-existing)
IDENTITY_PRINCIPAL_ID=$(az identity show --name id-aca-myapp-dev --resource-group rg-myapp-dev --query principalId -o tsv)

az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee-object-id "$IDENTITY_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --scope "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/kv-myapp-dev"
```

---

## Deploying

### Via GitHub Actions (recommended)

**Automatic:** Push changes to the `infra/` folder on `main` → deploys to **dev** automatically.

**Manual:** Go to **Actions → Deploy ACA Infrastructure → Run workflow** and select the target environment.

The workflow runs a **what-if** preview before deploying, so you can inspect changes in the Actions log.

### Via Azure CLI (local)

```bash
# Validate (dry run)
az deployment group validate \
  --resource-group rg-myapp-dev \
  --template-file infra/main.bicep \
  --parameters infra/parameters.dev.bicepparam

# What-If preview
az deployment group what-if \
  --resource-group rg-myapp-dev \
  --template-file infra/main.bicep \
  --parameters infra/parameters.dev.bicepparam

# Deploy
az deployment group create \
  --resource-group rg-myapp-dev \
  --template-file infra/main.bicep \
  --parameters infra/parameters.dev.bicepparam \
  --name "aca-infra-dev-$(date +%Y%m%d%H%M)"
```

---

## Parameters Reference

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `environmentName` | `string` | — | `dev`, `qa`, or `prod` |
| `appName` | `string` | — | Base name for resource naming |
| `location` | `string` | Resource group location | Azure region |
| `createNewIdentity` | `bool` | `true` | Create a new managed identity or use existing |
| `existingIdentityResourceId` | `string` | `''` | Full resource ID of an existing identity |
| `acrName` | `string` | — | Existing ACR name (no `.azurecr.io`) |
| `containerImage` | `string` | `mcr.microsoft.com/k8se/quickstart:latest` | Container image to deploy |
| `targetPort` | `int` | `80` | Port the container listens on |
| `containerCpu` | `string` | `0.5` | CPU cores |
| `containerMemory` | `string` | `1Gi` | Memory |
| `minReplicas` | `int` | `0` | Minimum replica count |
| `maxReplicas` | `int` | `3` | Maximum replica count |
| `ingressExternal` | `bool` | `true` | Expose external HTTP endpoint |
| `appEnvVars` | `array` | `[]` | Non-sensitive env vars (`{ name, value }`) |
| `secretEnvVars` | `array` | `[]` | Key Vault secret refs (`{ name, secretRef, keyVaultSecretUri }`) |
| `tags` | `object` | `{}` | Tags applied to all resources |

## Environment Sizing Defaults

| Setting | Dev | QA | Prod |
|---------|-----|----|------|
| CPU | 0.25 | 0.5 | 1 |
| Memory | 0.5Gi | 1Gi | 2Gi |
| Min Replicas | 0 | 1 | 1 |
| Max Replicas | 1 | 3 | 10 |
| Log Level | Debug | Information | Warning |

---

## Outputs

The Bicep template emits these outputs (also surfaced as GitHub Actions step outputs):

| Output | Description |
|--------|-------------|
| `containerAppName` | Name of the deployed Container App |
| `containerAppFqdn` | Publicly accessible FQDN |
| `containerAppResourceId` | Full ARM resource ID |
| `identityResourceId` | Resource ID of the managed identity |
| `managedEnvironmentName` | Name of the Container Apps Managed Environment |

## Notes

- **ACR must be in the same resource group** as the Container App. If your ACR is in a different resource group, extract the role assignment into a separate Bicep module scoped to that resource group.
- The template uses a **placeholder container image** (`mcr.microsoft.com/k8se/quickstart:latest`) for the initial infrastructure deploy. Update `containerImage` in the parameter file (or via a separate app-deploy workflow) once your image is pushed to ACR.
- **BCP318 warning** during `az bicep build` is expected — it flags that a conditional resource _could_ be null. At runtime the ternary expression guarantees the correct branch is evaluated.

## License

MIT
