# Usage Models — Multi-App Consumption Guide

![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-CI%2FCD-2088FF?logo=githubactions&logoColor=white)
![Bicep](https://img.shields.io/badge/Bicep-IaC-0078D4?logo=microsoftazure)
![Azure](https://img.shields.io/badge/Azure-Container%20Apps-0078D4?logo=microsoftazure)

This document explains how teams with multiple application repositories (e.g., App1, App2, App3) can consume the ACA-BICEP-Actions framework.

Two models are supported:

| | Model A — Centralized Framework | Model B — Fork / Self-Contained |
|-|--------------------------------|--------------------------------|
| **Summary** | Single shared framework repo; app repos contain only params + thin callers | Each app repo contains a full copy of the framework |
| **Best for** | Platform teams managing 3+ apps | Small teams or highly divergent infrastructure needs |

---

## Model A — Centralized Framework Repo (Recommended)

![GitHub Actions](https://img.shields.io/badge/workflow__call-reusable-2088FF?logo=githubactions&logoColor=white)
![YAML](https://img.shields.io/badge/YAML-workflow-CB171E?logo=yaml)

This repo (`ACA-BICEP-Actions`) acts as a **shared infrastructure framework**. Each application repository contains only:

1. Its own parameter files (`parameters.*.bicepparam`)
2. A thin caller workflow that references this repo's reusable workflow

```
┌─────────────────────────────────────────────────┐
│         ACA-BICEP-Actions (this repo)           │
│                                                 │
│  infra/main.bicep                               │
│  infra/modules/*.bicep                          │
│  .github/workflows/infra-deploy.yml  ◄──────┐   │
│                                              │   │
└──────────────────────────────────────────────┤───┘
                                               │
        ┌──────────────────────────────────────┘
        │  uses: <owner>/ACA-BICEP-Actions/
        │        .github/workflows/infra-deploy.yml@main
        │
   ┌────┴────┐     ┌─────────┐     ┌─────────┐
   │  App1   │     │  App2   │     │  App3   │
   │  repo   │     │  repo   │     │  repo   │
   │         │     │         │     │         │
   │ infra/  │     │ infra/  │     │ infra/  │
   │  params │     │  params │     │  params │
   │ .github/│     │ .github/│     │ .github/│
   │  caller │     │  caller │     │  caller │
   └─────────┘     └─────────┘     └─────────┘
```

### App Repo Directory Structure (Model A)

Each application repository needs only these infrastructure files:

```
my-app-repo/
├── src/                          # Application source code
├── Dockerfile                    # App container build
├── infra/
│   ├── parameters.dev.bicepparam
│   ├── parameters.qa.bicepparam
│   └── parameters.prod.bicepparam
└── .github/
    └── workflows/
        └── deploy.yml            # Thin caller workflow
```

> **Note**: No Bicep modules or `main.bicep` in the app repo — all infrastructure logic lives in the framework repo.

### Example Caller Workflow (Model A)

```yaml
# .github/workflows/deploy.yml — inside the App repo
name: Deploy My App
on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [dev, qa, prod]
        default: dev
      image-tag:
        required: false
        description: "Container image tag override"

jobs:
  deploy:
    uses: <owner>/ACA-BICEP-Actions/.github/workflows/infra-deploy.yml@main
    with:
      environment: ${{ inputs.environment || 'dev' }}
      azure-subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
      azure-resource-group: ${{ vars.AZURE_RESOURCE_GROUP }}
      parameter-file: infra/parameters.${{ inputs.environment || 'dev' }}.bicepparam
      container-image-tag: ${{ inputs.image-tag || github.sha }}
    secrets: inherit
```

Replace `<owner>/ACA-BICEP-Actions` with the actual org/owner and repo name (e.g., `pkumar26/ACA-BICEP-Actions`).

### How It Works (Model A)

1. **Platform team** maintains `ACA-BICEP-Actions` — updates modules, adds features, fixes bugs.
2. **App teams** customize only their `parameters.*.bicepparam` files with app-specific values (name, CPU, memory, secrets, env vars).
3. When the app repo's workflow runs, GitHub Actions fetches the reusable workflow from the framework repo at the pinned ref (`@main`, `@v1`, or a commit SHA).
4. Infrastructure changes propagate to all apps automatically when the framework repo is updated (if using `@main`).

### Pinning Strategy

| Ref | Behavior | Risk |
|-----|----------|------|
| `@main` | Always uses latest framework version | Breaking changes propagate immediately |
| `@v1` | Uses a tagged release | Stable; update by changing the tag |
| `@abc1234` | Uses a specific commit SHA | Most stable; requires manual updates |

**Recommendation**: Use a tagged release (`@v1`, `@v2`) for production callers, `@main` for dev/experimentation.

---

## Model B — Fork / Self-Contained

![Bicep](https://img.shields.io/badge/Bicep-full%20copy-0078D4?logo=microsoftazure)
![GitHub](https://img.shields.io/badge/GitHub-fork-181717?logo=github)

Each application repository contains a **full copy** of the framework. This is a fork of `ACA-BICEP-Actions` merged into the app repo.

```
   ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
   │     App1 repo    │   │     App2 repo    │   │     App3 repo    │
   │                  │   │                  │   │                  │
   │ infra/           │   │ infra/           │   │ infra/           │
   │   main.bicep     │   │   main.bicep     │   │   main.bicep     │
   │   modules/       │   │   modules/       │   │   modules/       │
   │   parameters.*   │   │   parameters.*   │   │   parameters.*   │
   │ .github/         │   │ .github/         │   │ .github/         │
   │   workflows/     │   │   workflows/     │   │   workflows/     │
   │     infra-deploy │   │     infra-deploy │   │     infra-deploy │
   │     deploy-dev   │   │     deploy-dev   │   │     deploy-dev   │
   │     deploy-qa    │   │     deploy-qa    │   │     deploy-qa    │
   │     deploy-prod  │   │     deploy-prod  │   │     deploy-prod  │
   └──────────────────┘   └──────────────────┘   └──────────────────┘
         (independent)          (independent)          (independent)
```

### App Repo Directory Structure (Model B)

```
my-app-repo/
├── src/                                  # Application source code
├── Dockerfile
├── infra/
│   ├── main.bicep                        # Full orchestrator (copied from framework)
│   ├── modules/
│   │   ├── identity.bicep
│   │   ├── log-analytics.bicep
│   │   ├── acr-role-assignment.bicep
│   │   ├── managed-environment.bicep
│   │   └── container-app.bicep
│   ├── parameters.dev.bicepparam
│   ├── parameters.qa.bicepparam
│   └── parameters.prod.bicepparam
└── .github/
    └── workflows/
        ├── infra-deploy.yml              # Reusable workflow (local copy)
        ├── deploy-dev.yml
        ├── deploy-qa.yml
        └── deploy-prod.yml
```

### Example Caller Workflow (Model B)

Caller workflows reference the **local** reusable workflow:

```yaml
# .github/workflows/deploy-dev.yml — inside the App repo
name: Deploy Dev
on:
  push:
    branches: [main]

jobs:
  deploy:
    uses: ./.github/workflows/infra-deploy.yml   # Local path
    with:
      environment: dev
      azure-subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
      azure-resource-group: ${{ vars.AZURE_RESOURCE_GROUP }}
      parameter-file: infra/parameters.dev.bicepparam
    secrets: inherit
```

### How It Works (Model B)

1. **Fork** or copy `ACA-BICEP-Actions` into each app repo.
2. **Customize** parameter files and optionally modify Bicep modules for app-specific needs.
3. Each repo is fully independent — changes to modules in one repo do not affect others.
4. To pull upstream framework updates, merge from the original repo manually.

---

## Comparison

| Factor | Model A (Centralized) | Model B (Fork) |
|--------|----------------------|----------------|
| **Module updates** | Automatic (or controlled via pinning) | Manual merge from upstream |
| **App team autonomy** | Low — constrained to parameter customization | High — full control over all Bicep files |
| **Drift risk** | None — single source of truth | High — copies diverge over time |
| **Repo complexity (per app)** | Minimal (params + caller only) | Full framework in every repo |
| **Team size** | Ideal for platform team + many app teams | Ideal for small teams or solo devs |
| **Custom modules per app** | Not supported without forking | Fully supported |
| **Debugging** | Must check framework repo for module issues | Everything in one place |
| **CI/CD coupling** | App deploys depend on framework repo availability | Fully independent |

---

## Recommendation

| Scenario | Recommended Model |
|----------|-------------------|
| 3+ apps with shared infra patterns | **Model A** — centralized framework |
| 1–2 apps, or apps with very different infra needs | **Model B** — fork per app |
| Regulated environment requiring change control | **Model A** with tagged releases (`@v1`) |
| Rapid prototyping / experimentation | **Model B** — full local control |
| Platform team governs infra, app teams own code | **Model A** |

---

## Getting Started

![Shell Script](https://img.shields.io/badge/Shell-Script-4EAA25?logo=gnubash&logoColor=white)
![Azure CLI](https://img.shields.io/badge/Azure%20CLI-2.x-0078D4?logo=microsoftazure)

### Model A Setup (per app repo)

1. Create `infra/` directory with your parameter files (copy from this repo's examples and customize).
2. Create `.github/workflows/deploy.yml` using the [caller example above](#example-caller-workflow-model-a).
3. Configure GitHub repo secrets/variables:
   - `AZURE_SUBSCRIPTION_ID` (variable)
   - `AZURE_RESOURCE_GROUP` (variable)
   - `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` (for OIDC — set per environment)
4. Push to trigger deployment.

### Model B Setup (per app repo)

1. Fork this repository, or copy the `infra/` and `.github/workflows/` directories into your app repo.
2. Customize `parameters.*.bicepparam` files for your app.
3. Update caller workflow paths if your directory structure differs.
4. Configure GitHub repo secrets/variables (same as Model A).
5. Push to trigger deployment.

---

## FAQ

**Q: Can I mix models?**
Yes. Some apps can use Model A (centralized) while others use Model B (forked). They are independent consumption patterns.

**Q: What if I need a custom Bicep module for one app?**
Use Model B for that app, or extend the framework repo with optional modules and conditional parameters.

**Q: How do I update my forked copy (Model B) with upstream changes?**
```bash
git remote add upstream https://github.com/<owner>/ACA-BICEP-Actions.git
git fetch upstream
git merge upstream/main --no-commit
# Resolve conflicts, then commit
```

**Q: Does Model A require the framework repo to be public?**
For cross-repo `workflow_call`, the reusable workflow repo must be either:
- **Public**, or
- **Internal** (within the same GitHub Enterprise organization), or
- **Private** with [Actions access settings](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#allowing-access-to-components-in-a-private-repository) configured to allow the calling repos.
