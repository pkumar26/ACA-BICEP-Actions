# Contract: Reusable Workflow Inputs & Outputs

**Date**: 2026-02-28 | **Branch**: `001-aca-multienv-framework`

This document defines the interface contract for the reusable GitHub Actions workflow (`infra-deploy.yml`) and the caller workflow conventions. It is the primary external contract of this framework — app repos consume it.

---

## 1. Reusable Workflow: `infra-deploy.yml`

### Trigger

```yaml
on:
  workflow_call:
    inputs: ...
    secrets: ...
```

This workflow is **only** callable via `workflow_call`. It does not have `push`, `workflow_dispatch`, or any other direct trigger.

### Inputs

| Input | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `environment` | `string` | Yes | — | Target environment name. Must match a GitHub Environment and a `.bicepparam` file suffix (`dev`, `qa`, `prod`). |
| `azure-subscription-id` | `string` | Yes | — | Azure subscription ID for the deployment target. |
| `azure-resource-group` | `string` | Yes | — | Azure resource group name for the deployment target. |
| `parameter-file` | `string` | Yes | — | Relative path to the Bicep parameter file (e.g., `infra/parameters.dev.bicepparam`). |
| `container-image-tag` | `string` | No | `''` | Container image tag to override. When non-empty, passed as `--parameters containerImageTag='<value>'` to the Bicep deployment. When empty, the default from the parameter file applies. |
| `allow-destructive` | `boolean` | No | `false` | When `true`, allows deployment to proceed even if what-if detects resource deletions. When `false` (default), the workflow auto-aborts on detected deletions. |

### Secrets

| Secret | Required | Description |
|--------|----------|-------------|
| (inherited) | — | Callers use `secrets: inherit` to pass all secrets (including environment-scoped `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`). |

**Note**: No explicit secret declarations on the reusable workflow. `secrets: inherit` is the recommended pattern, which passes org-level and environment-scoped secrets automatically.

### Permissions Required

```yaml
permissions:
  id-token: write    # Required for OIDC authentication
  contents: read     # Required for actions/checkout
```

### Jobs

The reusable workflow defines a single job:

#### Job: `deploy`

| Property | Value |
|----------|-------|
| `runs-on` | `ubuntu-latest` |
| `environment` | `${{ inputs.environment }}` — triggers GitHub Environment protection rules |

**Steps** (in order):

| # | Step | Action/Command | Notes |
|---|------|----------------|-------|
| 1 | Checkout | `actions/checkout@v4` | — |
| 2 | Azure Login | `azure/login@v2` with OIDC | Uses `client-id`, `tenant-id`, `subscription-id` from env secrets/vars |
| 3 | What-If Preview | `az deployment group what-if` | `--no-pretty-print`, captures output, writes to `$GITHUB_STEP_SUMMARY` |
| 4 | Destructive Change Gate | Conditional abort | Fails if `Delete` detected and `allow-destructive != true` |
| 5 | Deploy | `az deployment group create` | Incremental mode, deployment name includes timestamp |
| 6 | Surface Outputs | Capture deployment outputs | Writes `containerAppName`, `containerAppFqdn`, `containerAppResourceId` to `$GITHUB_OUTPUT` |
| 7 | Azure Logout | `azure/CLI` logout | Cleanup |

### Outputs

| Output | Type | Description |
|--------|------|-------------|
| `container-app-name` | `string` | Name of the deployed container app |
| `container-app-fqdn` | `string` | FQDN of the container app |
| `container-app-resource-id` | `string` | Full ARM resource ID |

---

## 2. Caller Workflow Conventions

### Required GitHub Environment Configuration

Each environment must have these configured (Settings → Environments):

| Environment | Secrets | Variables | Protection Rules |
|-------------|---------|-----------|-----------------|
| `dev` | `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` | `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP` | None |
| `qa` | `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` | `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP` | Optional: required reviewers |
| `prod` | `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` | `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP` | **Required reviewers** (1+) |

### Caller: `deploy-dev.yml`

```yaml
name: Deploy Dev
on:
  push:
    branches: [main]
    paths: ['infra/**']

jobs:
  deploy:
    uses: ./.github/workflows/infra-deploy.yml
    with:
      environment: dev
      azure-subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
      azure-resource-group: ${{ vars.AZURE_RESOURCE_GROUP }}
      parameter-file: infra/parameters.dev.bicepparam
    secrets: inherit
```

### Caller: `deploy-qa.yml`

```yaml
name: Deploy QA
on:
  workflow_dispatch:
    inputs:
      container-image-tag:
        description: 'Container image tag to deploy'
        required: false
        default: ''
      allow-destructive:
        description: 'Allow destructive changes'
        type: boolean
        default: false

jobs:
  deploy:
    uses: ./.github/workflows/infra-deploy.yml
    with:
      environment: qa
      azure-subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
      azure-resource-group: ${{ vars.AZURE_RESOURCE_GROUP }}
      parameter-file: infra/parameters.qa.bicepparam
      container-image-tag: ${{ inputs.container-image-tag }}
      allow-destructive: ${{ inputs.allow-destructive }}
    secrets: inherit
```

### Caller: `deploy-prod.yml`

```yaml
name: Deploy Prod
on:
  workflow_dispatch:
    inputs:
      container-image-tag:
        description: 'Container image tag to deploy'
        required: true
      allow-destructive:
        description: 'Allow destructive changes'
        type: boolean
        default: false

jobs:
  deploy:
    uses: ./.github/workflows/infra-deploy.yml
    with:
      environment: prod
      azure-subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
      azure-resource-group: ${{ vars.AZURE_RESOURCE_GROUP }}
      parameter-file: infra/parameters.prod.bicepparam
      container-image-tag: ${{ inputs.container-image-tag }}
      allow-destructive: ${{ inputs.allow-destructive }}
    secrets: inherit
    # Prod environment protection rules enforce manual approval
```

### Cross-Repo Caller (External App Repo)

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

---

## 3. Bicep Deployment Contract

### CLI Invocation (by the reusable workflow)

**What-If**:
```bash
az deployment group what-if \
  --resource-group "$RESOURCE_GROUP" \
  --template-file infra/main.bicep \
  --parameters "$PARAMETER_FILE" \
  --no-pretty-print
```

**Deploy**:
```bash
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file infra/main.bicep \
  --parameters "$PARAMETER_FILE" \
  --name "aca-infra-${ENVIRONMENT}-$(date +%Y%m%d%H%M%S)" \
  --mode Incremental
```

**With image tag override** (when `container-image-tag` is non-empty):
```bash
az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file infra/main.bicep \
  --parameters "$PARAMETER_FILE" \
  --parameters containerImageTag='$IMAGE_TAG' \
  --name "aca-infra-${ENVIRONMENT}-$(date +%Y%m%d%H%M%S)" \
  --mode Incremental
```

### Deployment Outputs

The `az deployment group create` command outputs these values (from Bicep `output` declarations):

| Output Key | Type | Used By |
|------------|------|---------|
| `containerAppName` | `string` | Workflow output, downstream jobs |
| `containerAppFqdn` | `string` | Workflow output, smoke tests |
| `containerAppResourceId` | `string` | Workflow output, downstream jobs |
| `identityResourceId` | `string` | Informational |
| `managedEnvironmentName` | `string` | Informational |

---

## 4. Contract Versioning

This contract is v1.0 (initial). Breaking changes to the reusable workflow inputs or Bicep parameter surface require:
1. A new spec/plan cycle via speckit.
2. A semver bump in the contract document.
3. Communication to all consuming app repos.

| Version | Date | Change |
|---------|------|--------|
| v1.0 | 2026-02-28 | Initial contract definition |
