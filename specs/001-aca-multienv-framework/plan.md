# Implementation Plan: Multi-Environment ACA Provisioning & Deployment Framework

**Branch**: `001-aca-multienv-framework` | **Date**: 2026-02-28 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-aca-multienv-framework/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

Refactor the existing monolithic ACA Bicep template and GitHub Actions workflow into a modular, multi-environment framework. The existing `infra/main.bicep` (251 lines) covers ~70% of spec requirements but needs: modularization into discrete Bicep modules, cross-resource-group ACR support, optional existing ACA environment deployment, optional VNET integration, conversion of the workflow to a reusable `workflow_call` pattern with destructive-change abort logic, and per-environment caller workflows with distinct triggers and approval gates.

## Technical Context

**Language/Version**: Bicep (latest, targeting Azure ARM API 2024-03-01 for Container Apps), YAML (GitHub Actions)
**Primary Dependencies**: Azure CLI (`az deployment group create/what-if`), `azure/login@v2`, `azure/arm-deploy@v2`, `actions/checkout@v4`
**Storage**: N/A (Azure resources provisioned declaratively; state managed by Azure Resource Manager)
**Testing**: `az deployment group what-if` for deployment validation; manual smoke tests per user story acceptance scenarios; no unit test framework (Bicep has no native test runner — validation via what-if + Azure deployment)
**Target Platform**: Azure (Container Apps, ACR, Key Vault, Log Analytics, Managed Identity) + GitHub Actions runners (ubuntu-latest)
**Project Type**: Infrastructure-as-Code framework (Bicep modules + GitHub Actions reusable workflows)
**Performance Goals**: N/A (infrastructure provisioning — ARM deployment latency is Azure-managed)
**Constraints**: All resources must be idempotent; no stored secrets; OIDC-only authentication; pipeline service principal scoped to resource group + ACR RG
**Scale/Scope**: 3 environments (dev/qa/prod); 5 Bicep modules; 1 reusable workflow + 3 caller workflows; reusable by N app repos

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Compliance | Notes |
|---|-----------|------------|-------|
| I | Purpose and Scope | ✅ PASS | Covers ACA, UAMI, ACR, KV, LAW, GitHub Actions — matches constitution scope |
| II | Environment and Tenancy Model | ✅ PASS | 3 envs (dev/qa/prod), separate RGs, naming conventions enforced, tagging required |
| III | Bicep Design Principles | ⚠️ REQUIRES CHANGE | Existing `main.bicep` is monolithic; plan includes modularization into 5 focused modules |
| IV | Multi-Environment Parameters and Configuration | ✅ PASS | Per-env `.bicepparam` files exist; adding `existingManagedEnvironmentId`, `subnetId` |
| V | GitHub Actions and CI/CD Strategy | ⚠️ REQUIRES CHANGE | Current workflow is dispatch-only; must convert to reusable `workflow_call` + add what-if abort + per-env triggers |
| VI | App Lifecycle and Image Deployment | ✅ PASS | Placeholder image default; `containerImage` parameterized; `container-image-tag` override added to workflow |
| VII | Security and Compliance Requirements | ✅ PASS | Identity-based ACR pull, KV secrets, TLS enforced, least-privilege RBAC, no stored secrets |
| VIII | Observability and Operations | ⚠️ PARTIAL | LAW per env with 30-day retention; health probes deferred for placeholder images. **Alerts (scale failure, 5xx, restart loops) deferred to follow-up spec** — documented as non-goal in spec.md. |
| IX | Reusability and Extension for Multiple Apps | ✅ PASS | Reusable workflow + Bicep modules; app repos provide inputs only |

**Gate Result**: PASS (with 2 planned corrective actions for Principles III and V, plus Principle VIII alerts deferred)

## Project Structure

### Documentation (this feature)

```text
specs/001-aca-multienv-framework/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   └── workflow-inputs.md
└── tasks.md             # Phase 2 output (NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
infra/
├── main.bicep                     # Orchestrator — wires modules together
├── modules/
│   ├── identity.bicep             # UAMI creation (conditional)
│   ├── acr-role-assignment.bicep  # AcrPull role on ACR (cross-RG via resource ID)
│   ├── log-analytics.bicep        # Log Analytics workspace
│   ├── managed-environment.bicep  # ACA managed environment (conditional + VNET opt-in)
│   └── container-app.bicep        # Container app (identity, secrets, ingress, scaling)
├── parameters.dev.bicepparam      # Dev environment parameters (updated)
├── parameters.qa.bicepparam       # QA environment parameters (updated)
└── parameters.prod.bicepparam     # Prod environment parameters (updated)

.github/workflows/
├── infra-deploy.yml               # Reusable workflow (workflow_call) — refactored
├── deploy-dev.yml                 # Caller: auto on push to main (infra/**)
├── deploy-qa.yml                  # Caller: manual dispatch or tag
└── deploy-prod.yml                # Caller: manual dispatch, requires approval
```

**Structure Decision**: The existing flat `infra/main.bicep` is refactored into `infra/main.bicep` (orchestrator) + `infra/modules/*.bicep` (5 modules). The existing monolithic workflow is converted to a reusable workflow + 3 thin caller workflows. This aligns with Constitution Principles III (modular Bicep) and V (reusable workflow pattern).

### Changes to Existing Code

**`infra/main.bicep` (MAJOR REFACTOR)**:
- Extract 5 inline resource blocks into discrete modules under `infra/modules/`
- Rewrite as an orchestrator that calls modules with `module` keyword
- Add parameters: `acrResourceId` (string, full resource ID), `existingManagedEnvironmentId` (string, optional), `subnetId` (string, optional)
- Remove: `acrName` parameter (replaced by `acrResourceId`)
- Keep: all outputs, parameter surface area (with additions)

**`infra/parameters.{dev,qa,prod}.bicepparam` (MINOR UPDATE)**:
- Replace `param acrName = 'demoacr'` with `param acrResourceId = '/subscriptions/.../providers/Microsoft.ContainerRegistry/registries/demoacr'`
- Add `param existingManagedEnvironmentId = ''` (empty = create new)
- Add `param subnetId = ''` (empty = no VNET)

**`.github/workflows/infra-deploy.yml` (MAJOR REFACTOR)**:
- Convert from `workflow_dispatch` trigger to `workflow_call` trigger
- Add inputs: `environment`, `azure-subscription-id`, `azure-resource-group`, `parameter-file`, `container-image-tag`, `allow-destructive`
- Add what-if output parsing step (grep for `Delete` operations)
- Add conditional abort step if deletions detected and `allow-destructive` is not true
- Remove `workflow_dispatch` and `push` triggers (moved to caller workflows)

## Constitution Re-Check (Post Phase 1 Design)

*Re-evaluated after data-model.md, contracts/, and quickstart.md are complete.*

| # | Principle | Compliance | Phase 1 Design Notes |
|---|-----------|------------|---------------------|
| I | Purpose and Scope | ✅ PASS | Covers ACA, UAMI, ACR, KV, LAW, GH Actions. Modules defined in data-model.md match scope. |
| II | Environment and Tenancy Model | ✅ PASS | 3 envs, separate RGs, naming `{prefix}-{appName}-{env}`, tags enforced. `existingManagedEnvironmentId` enables shared env per constitution allowance. |
| III | Bicep Design Principles | ✅ PASS (resolved) | 5 modular Bicep files defined in data-model.md §2. Local path references per research R-004. Parameter files per env. |
| IV | Multi-Environment Parameters | ✅ PASS | Full parameter surface in data-model.md §1. Per-env `.bicepparam` files. Secrets via KV URI only. |
| V | GitHub Actions and CI/CD | ✅ PASS (resolved) | Reusable `workflow_call` contract defined in contracts/workflow-inputs.md. Dev auto-deploy, qa manual, prod approval. What-if with destructive abort. OIDC only. |
| VI | App Lifecycle and Image Deployment | ✅ PASS | Placeholder image default. `container-image-tag` input in workflow contract. `Single` revision mode. |
| VII | Security and Compliance | ✅ PASS | Identity-based ACR pull, KV secrets, `allowInsecure: false` hardcoded, RBAC least-privilege. `principalType: ServicePrincipal` per research R-001. |
| VIII | Observability and Operations | ⚠️ PARTIAL | LAW per env (30-day, PerGB2018). Health probes deferred for placeholder images. **Alerts deferred to follow-up spec** — documented in spec.md non-goals. |
| IX | Reusability and Extension | ✅ PASS | Onboarding in <30 min per quickstart.md. Cross-repo caller pattern in contracts. `secrets: inherit` per research R-006. |

**Gate Result**: ✅ ALL PASS (with noted deferral) — The 2 previous "REQUIRES CHANGE" items (Principles III and V) are resolved. Principle VIII alerts are explicitly deferred to a follow-up spec.

## Complexity Tracking

No constitution violations requiring justification. The 2 "REQUIRES CHANGE" items from the initial check (Principles III, V) are now resolved in the Phase 1 design artifacts.
