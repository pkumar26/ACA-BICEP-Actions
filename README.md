# Azure Container App — Multi-Environment Infrastructure

Bicep + GitHub Actions framework to provision Azure Container Apps with:

- **Multi-environment** support (dev / qa / prod) with per-environment sizing and secrets
- **Modular Bicep** — 5 reusable modules orchestrated by `main.bicep`
- **User-assigned managed identity** (create new or bring your own)
- **Cross-resource-group ACR** — AcrPull role assignment via full ARM resource ID
- **Key Vault–backed secrets** accessed at runtime via managed identity
- **Reusable GitHub Actions workflow** — `workflow_call` pattern with thin per-env callers
- **Destructive change protection** — what-if preview auto-aborts on detected deletions
- **OIDC / Workload Identity Federation** — passwordless GitHub → Azure auth (no stored secrets)
- **Optional VNET integration** and existing managed environment reuse

## Architecture

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ deploy-dev   │     │ deploy-qa    │     │ deploy-prod  │
│ (push→main)  │     │ (manual)     │     │ (manual+     │
│              │     │              │     │  approval)   │
└──────┬───────┘     └──────┬───────┘     └──────┬───────┘
       │                    │                    │
       └────────────────────┼────────────────────┘
                            ▼
                ┌───────────────────────┐
                │   infra-deploy.yml    │
                │   (reusable workflow) │
                │                       │
                │  1. OIDC Login        │
                │  2. What-If Preview   │
                │  3. Destructive Gate  │
                │  4. Bicep Deploy      │
                │  5. Output Capture    │
                └───────────┬───────────┘
                            ▼
                ┌───────────────────────┐
                │    main.bicep         │
                │    (orchestrator)     │
                │                       │
                │  ┌─ identity.bicep    │
                │  ├─ acr-role-assign.  │
                │  ├─ log-analytics.    │
                │  ├─ managed-env.      │
                │  └─ container-app.    │
                └───────────────────────┘
```

## Repository Structure

```
├── infra/
│   ├── main.bicep                    # Orchestrator — wires all modules
│   ├── modules/
│   │   ├── identity.bicep            # Conditional UAMI creation
│   │   ├── acr-role-assignment.bicep # AcrPull role (cross-RG capable)
│   │   ├── log-analytics.bicep       # Log Analytics workspace
│   │   ├── managed-environment.bicep # ACA environment (optional VNET)
│   │   └── container-app.bicep       # Container app with KV secrets
│   ├── parameters.dev.bicepparam     # Dev overrides
│   ├── parameters.qa.bicepparam      # QA overrides
│   └── parameters.prod.bicepparam    # Prod overrides
├── .github/
│   └── workflows/
│       ├── infra-deploy.yml          # Reusable deployment workflow
│       ├── deploy-dev.yml            # Dev caller (push trigger)
│       ├── deploy-qa.yml             # QA caller (manual)
│       └── deploy-prod.yml           # Prod caller (manual + approval)
├── USAGE_MODELS.md                   # Multi-app consumption guide
└── README.md
```

## Resources Provisioned

| Resource | Naming Convention | Notes |
|----------|-------------------|-------|
| User-Assigned Managed Identity | `id-{appName}-{env}` | Conditional — skipped if using an existing identity |
| ACRPull Role Assignment | deterministic `guid()` | Scoped to ACR (supports cross-RG) |
| Log Analytics Workspace | `law-{appName}-{env}` | 30-day retention, PerGB2018 SKU |
| Container Apps Managed Environment | `cae-{appName}-{env}` | Conditional — skipped if reusing existing; optional VNET |
| Container App | `ca-{appName}-{env}` | Identity-based ACR pull, Key Vault secrets, `allowInsecure: false` |

## Prerequisites

- **Azure CLI** with the Bicep extension (`az bicep install`)
- **An existing Azure Container Registry** (can be in any resource group)
- **An existing Azure Key Vault** per environment (for secret env vars)
- **Key Vault Secrets User** role granted to the managed identity (external prerequisite)
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
| `acrResourceId` | Full ARM resource ID of your existing ACR | `/subscriptions/.../registries/myacr` |
| `location` | Azure region | `eastus` |
| `containerImage` | Image to deploy (placeholder is fine for first run) | `myacr.azurecr.io/api:v1` |
| `targetPort` | Port your container listens on | `8080` |
| `appEnvVars` | Non-sensitive env vars | See parameter file for format |
| `secretEnvVars` | Key Vault–backed secret env vars | See parameter file for format |

#### Using an existing managed identity

Set these parameters in the `.bicepparam` file:

```bicep
param createNewIdentity = false
param existingIdentityResourceId = '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<name>'
```

#### Using an existing ACA managed environment

```bicep
param existingManagedEnvironmentId = '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.App/managedEnvironments/<name>'
```

When set, the framework skips environment creation and deploys the container app into the existing environment.

#### Enabling VNET integration

```bicep
param subnetId = '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>'
```

The subnet must be delegated to `Microsoft.App/environments` (external prerequisite).

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

| Environment | Trigger | How |
|-------------|---------|-----|
| **dev** | Automatic on push to `main` (changes in `infra/`) | Merge a PR |
| **qa** | Manual | Actions → Deploy QA → Run workflow |
| **prod** | Manual + approval | Actions → Deploy Prod → Run workflow (reviewer must approve) |

The reusable workflow runs a **what-if preview** before deploying. If resource **deletions** are detected, the deployment **auto-aborts** unless `allow-destructive` is set to `true`.

#### Overriding the container image tag

When triggering QA or Prod deployments manually, you can provide a `container-image-tag` input. The workflow constructs the full image reference and passes it as a Bicep parameter override.

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
  --name "aca-infra-dev-$(date +%Y%m%d%H%M)" \
  --mode Incremental
```

---

## Reusable Workflow — Cross-Repo Consumption

> **Managing multiple apps?** See [USAGE_MODELS.md](USAGE_MODELS.md) for a detailed guide on centralized vs. fork-based consumption patterns, including directory structures, example workflows, and a comparison table.

Other application repos can call the reusable workflow without duplicating deployment logic:

```yaml
name: Deploy to ACA
on:
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [dev, qa, prod]
      image-tag:
        required: true

jobs:
  deploy:
    uses: <owner>/<framework-repo>/.github/workflows/infra-deploy.yml@main
    with:
      environment: ${{ inputs.environment }}
      azure-subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
      azure-resource-group: ${{ vars.AZURE_RESOURCE_GROUP }}
      parameter-file: infra/parameters.${{ inputs.environment }}.bicepparam
      container-image-tag: ${{ inputs.image-tag }}
    secrets: inherit
```

### Workflow Inputs

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `environment` | `string` | Yes | — | Target environment (`dev`, `qa`, `prod`) |
| `azure-subscription-id` | `string` | Yes | — | Azure subscription ID |
| `azure-resource-group` | `string` | Yes | — | Target resource group |
| `parameter-file` | `string` | Yes | — | Path to `.bicepparam` file |
| `container-image-tag` | `string` | No | `''` | Image tag override |
| `allow-destructive` | `boolean` | No | `false` | Allow destructive changes |

### Workflow Outputs

| Output | Type | Description |
|--------|------|-------------|
| `container-app-name` | `string` | Deployed container app name |
| `container-app-fqdn` | `string` | Container app FQDN |
| `container-app-resource-id` | `string` | Full ARM resource ID |

---

## Recovery from Partial Failures

This framework uses a **fix-forward** approach. Bicep deployments in `Incremental` mode are idempotent — re-running after a failure converges to the desired state.

### Procedure

1. **Diagnose**: Check the GitHub Actions log for the specific error (ARM error code, resource that failed).
2. **Fix root cause**: Correct the parameter file, Bicep code, or external prerequisite (e.g., Key Vault access, subnet delegation).
3. **Re-run the workflow**: The same caller workflow will re-run the full deployment. Already-provisioned resources are left unchanged; only the failed/changed resources are updated.

### Common Failure Scenarios

| Scenario | Root Cause | Fix |
|----------|-----------|-----|
| ACRPull role fails | Insufficient permissions on ACR RG | Grant `User Access Administrator` on ACR resource group |
| Key Vault secret fails | Missing `Key Vault Secrets User` role | Assign the role to the managed identity on the Key Vault |
| VNET integration fails | Subnet not delegated | Delegate subnet to `Microsoft.App/environments` |
| What-if abort | Detected resource deletions | Review changes; re-run with `allow-destructive: true` if intended |
| Image pull fails | Wrong ACR resource ID or image not pushed | Verify `acrResourceId` and push image before deploying |

> **Note**: Rollback is not supported. Always fix forward by correcting the root cause and re-deploying.

---

## Parameters Reference

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `environmentName` | `string` | — | `dev`, `qa`, or `prod` |
| `appName` | `string` | — | Base name for resource naming |
| `location` | `string` | Resource group location | Azure region |
| `createNewIdentity` | `bool` | `true` | Create a new managed identity or use existing |
| `existingIdentityResourceId` | `string` | `''` | Full resource ID of an existing identity |
| `acrResourceId` | `string` | — | Full ARM resource ID of the existing ACR |
| `existingManagedEnvironmentId` | `string` | `''` | Full resource ID of existing ACA environment (empty = create new) |
| `subnetId` | `string` | `''` | Subnet resource ID for VNET integration (empty = no VNET) |
| `containerImage` | `string` | `mcr.microsoft.com/k8se/quickstart:latest` | Container image to deploy |
| `targetPort` | `int` | `80` | Port the container listens on |
| `containerCpu` | `string` | `0.5` | CPU cores |
| `containerMemory` | `string` | `1Gi` | Memory |
| `minReplicas` | `int` | `0` | Minimum replica count |
| `maxReplicas` | `int` | `3` | Maximum replica count |
| `ingressExternal` | `bool` | `false` | Expose external HTTP endpoint |
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

## Bicep Module Reference

| Module | Purpose | Key Inputs | Key Outputs |
|--------|---------|------------|-------------|
| `identity.bicep` | Conditional UAMI creation | `createNewIdentity`, `existingIdentityResourceId` | `identityResourceId`, `identityPrincipalId` |
| `acr-role-assignment.bicep` | AcrPull role on ACR | `acrName`, `principalId` | — |
| `log-analytics.bicep` | Log Analytics workspace | `resourceSuffix`, `location` | `workspaceId`, `customerId`, `primarySharedKey` |
| `managed-environment.bicep` | ACA environment + VNET | `subnetId`, LAW outputs | `environmentId`, `environmentName` |
| `container-app.bicep` | Container app | identity, ACR, env vars, scaling | `containerAppName`, `containerAppFqdn`, `containerAppResourceId` |

## Deployment Outputs

| Output | Description |
|--------|-------------|
| `containerAppName` | Name of the deployed Container App |
| `containerAppFqdn` | Publicly accessible FQDN |
| `containerAppResourceId` | Full ARM resource ID |
| `identityResourceId` | Resource ID of the managed identity |
| `managedEnvironmentName` | Name of the Container Apps Managed Environment |

## Known Limitations

- **Sovereign clouds**: `acrLoginServer` is derived as `${acrName}.azurecr.io`, which assumes Azure public cloud. Sovereign cloud ACR suffixes (e.g., `.azurecr.cn`) are not currently supported.
- **Health probes**: Not configured by default. Add liveness/readiness probes to `container-app.bicep` for production workloads.
- **`maxReplicas` validation**: Deferred — review Azure Container Apps scaling limits before setting values > 30.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
