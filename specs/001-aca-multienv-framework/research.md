# Research: Multi-Environment ACA Provisioning & Deployment Framework

**Date**: 2026-02-28 | **Branch**: `001-aca-multienv-framework`

All Technical Context unknowns have been researched and resolved. This document captures decisions, rationale, and alternatives for each research area.

---

## R-001: Cross-Resource-Group ACR Role Assignment in Bicep

**Context**: The spec (FR-002) requires ACR pull role assignment where ACR may live in a different resource group than the deployment target.

**Decision**: Use a Bicep module with `scope: resourceGroup(acrResourceGroupName)` to perform cross-RG role assignments. The module uses `existing` keyword with the ACR name (scoped to the target RG) and assigns the role with `scope: acr` on the role assignment resource.

**Rationale**:
- `existing` keyword only works within the current deployment scope — it cannot reference resources by full ARM ID directly. A module with a different `scope:` solves this cleanly.
- ARM creates a nested deployment under the hood; no `targetScope` change needed on `main.bicep`.
- The role assignment `name` uses `guid(acr.id, principalId, roleDefinitionId)` for deterministic idempotency.

**Alternatives Considered**:
- **Inline `existing` with full resource ID**: Not supported — `existing` only accepts `name`, not a full ARM ID.
- **Subscription-scoped deployment**: Overly broad; would require changing `targetScope` and restructuring the entire template.

**Key Findings**:
- Always set `principalType: 'ServicePrincipal'` on role assignments for managed identities to avoid AAD race conditions (403 errors).
- The deploying SP needs `Microsoft.Authorization/roleAssignments/write` on the target ACR's RG.
- To support both same-RG and cross-RG scenarios, we parse the `acrResourceId` parameter to extract the RG name and ACR name using Bicep string functions.

**Parameter Design**:
- Accept `acrResourceId` (full ARM resource ID) instead of `acrName` (plain name).
- Derive `acrResourceGroup` and `acrName` using `split()` and `last()` functions in `main.bicep`.
- This single parameter covers both same-RG and cross-RG without extra boolean flags.

---

## R-002: Conditional Module Deployment (Existing ACA Environment)

**Context**: The spec (FR-004, Clarification #5) requires optionally deploying into an existing ACA managed environment instead of creating a new one.

**Decision**: Use the `if` keyword on the managed environment module statement, gated by `empty(existingManagedEnvironmentId)`. Output resolution uses a ternary operator.

**Rationale**:
- Bicep's `if` keyword on modules is the idiomatic approach for conditional resource creation.
- The ternary pattern `createNew ? module.outputs.id : existingId` is required because Bicep raises a compile-time error if you access outputs of a conditionally-deployed module without guarding.

**Pattern**:
```bicep
var createNewEnvironment = empty(existingManagedEnvironmentId)

module acaEnv './modules/managed-environment.bicep' = if (createNewEnvironment) {
  params: { ... }
}

var resolvedEnvironmentId = createNewEnvironment
  ? acaEnv.outputs.environmentId
  : existingManagedEnvironmentId
```

**Alternatives Considered**:
- **Separate templates per scenario**: Too much duplication; the conditional pattern is cleaner.
- **`count`-based approach**: Bicep doesn't support `count` like Terraform; `if` is the correct mechanism.

**Key Findings**:
- All parameter values are validated even when condition is `false` — so module params needing `@minLength(1)` must receive valid placeholder values or use defaults.
- Use `empty()` function (not `== ''`) for idiomatic empty-string checks in Bicep.

---

## R-003: VNET Integration for ACA Managed Environments

**Context**: The spec (FR-004, Clarification #5) requires optional VNET integration via a `subnetId` parameter.

**Decision**: Add an optional `subnetId` parameter. When non-empty, set `vnetConfiguration.infrastructureSubnetId` on the managed environment resource.

**Rationale**:
- `infrastructureSubnetId` is the correct property — confirmed in the ACA schema since API version `2022-03-01` through current `2024-03-01`.
- VNET integration is a managed-environment-level concern, so it belongs in the `managed-environment.bicep` module.

**Pattern**:
```bicep
param subnetId string = ''

properties: {
  vnetConfiguration: !empty(subnetId) ? {
    infrastructureSubnetId: subnetId
    internal: false
  } : null
}
```

**Key Findings**:
- Subnet must be at least `/23` (Consumption-only) or `/21` (with workload profiles).
- Subnet **must** be delegated to `Microsoft.App/environments` before deployment, or it will fail. This is an external prerequisite (consistent with spec's Clarification #3 approach for external prerequisites).
- `platformReservedCidr` and `dockerBridgeCidr` are optional but recommended for production. For the initial framework, we omit them (Azure auto-assigns ranges) and document them as advanced tuning parameters.
- Setting `internal: false` (default) means the ACA environment gets a public static IP. Users wanting internal-only must customize after initial deployment.

**Alternatives Considered**:
- **Full `vnetConfig` object parameter**: Too complex for initial implementation; `subnetId` alone covers the primary use case.
- **Separate `internal` parameter**: Deferred — `internal: true` requires private DNS zones which are out of scope.

---

## R-004: Bicep Module Structure — Local Path vs Registry

**Context**: The plan calls for 5 Bicep modules extracted from the monolithic `main.bicep`.

**Decision**: Use local path references (`'./modules/identity.bicep'`). No module registry (ACR) for now.

**Rationale**:
- Zero setup overhead — works with standard `az deployment group create`.
- Versioning managed by Git (branch/tag/commit), which is sufficient for a single-repo framework.
- Module registry adds complexity (ACR auth in CI, `bicep publish` workflow, version tagging) with no benefit when modules are consumed only within this repo.

**Alternatives Considered**:
- **ACR-hosted modules**: Better for cross-repo sharing; defer until multiple repos consume these modules.
- **Azure Verified Modules (AVM)**: Public registry modules are too opinionated for this framework's parameter surface.

**Key Findings**:
- `module foo './modules/identity.bicep' = { ... }` is the standard syntax — no `name` property needed.
- Module outputs are accessed via `foo.outputs.propertyName`.
- Modules deploy as nested ARM deployments; each has its own name (defaults to module identifier).

---

## R-005: What-If Output Parsing for Destructive Change Detection

**Context**: The spec (FR-009, Clarification #1) requires what-if to detect destructive changes and auto-abort unless `allow-destructive` is true.

**Decision**: Use `az deployment group what-if --no-pretty-print` with text grep for `Delete` keyword. Reserve JSON/jq parsing as a future enhancement.

**Rationale**:
- `--no-pretty-print` removes ANSI color codes, making grep reliable.
- Text grep for `Delete` is simpler and sufficient — the word "Delete" only appears as a change-type heading in what-if output.
- `jq` is available on `ubuntu-latest` runners, but JSON parsing adds complexity for marginal benefit in this context.

**Pattern**:
```bash
WHATIF_OUTPUT=$(az deployment group what-if \
  --resource-group "$RESOURCE_GROUP" \
  --template-file infra/main.bicep \
  --parameters "infra/parameters.${ENV}.bicepparam" \
  --no-pretty-print 2>&1) || true

if echo "$WHATIF_OUTPUT" | grep -qi "Delete"; then
  echo "has_destructive=true" >> "$GITHUB_OUTPUT"
else
  echo "has_destructive=false" >> "$GITHUB_OUTPUT"
fi
```

**Key Findings**:
- What-if writes its change summary to **stderr**, not stdout. Must capture with `2>&1`.
- What-if returns exit code 0 even when it shows deletions — it's informational only.
- `--result-format ResourceIdOnly` simplifies output but still supports the grep approach.
- What-if is best-effort — can have false positives (especially for conditional resources and extension resources). Gate only on `Delete` type, not on warnings.
- `|| true` prevents the step from failing if what-if itself returns a non-zero exit code (e.g., template compilation errors should be caught separately).

**Alternatives Considered**:
- **JSON/jq parsing**: More precise (`jq '.changes[] | select(.changeType == "Delete")'`), but adds complexity. Can be adopted in a later iteration.
- **`--result-format ResourceIdOnly`**: Cleaner output but loses property-level diff information.

---

## R-006: Reusable Workflow (`workflow_call`) Design

**Context**: The spec (FR-007, FR-008, FR-009) requires a reusable workflow pattern with per-environment callers.

**Decision**: Single reusable workflow (`infra-deploy.yml`) with `on: workflow_call`. Three thin caller workflows set environment-specific inputs and triggers.

**Rationale**:
- Keeps all deployment logic DRY in one file.
- `environment:` must be declared inside the reusable workflow's job (not on the caller's `uses:` job) — this is how GitHub environment protection rules activate.
- `secrets: inherit` simplifies secret passing (available since 2022).

**Reusable Workflow Inputs**:
| Input | Type | Required | Default | Purpose |
|-------|------|----------|---------|---------|
| `environment` | string | yes | — | Target environment name |
| `azure-subscription-id` | string | yes | — | Azure subscription ID |
| `azure-resource-group` | string | yes | — | Target resource group |
| `parameter-file` | string | yes | — | Path to `.bicepparam` file |
| `container-image-tag` | string | no | `''` | Container image tag override |
| `allow-destructive` | boolean | no | `false` | Allow destructive changes |

**Caller Trigger Strategy**:
| Caller | Trigger | Notes |
|--------|---------|-------|
| `deploy-dev.yml` | `push` to `main` on `infra/**` | Auto-deploy on merge |
| `deploy-qa.yml` | `workflow_dispatch` | Manual trigger |
| `deploy-prod.yml` | `workflow_dispatch` | Manual trigger; `prod` environment requires reviewer approval |

**Key Findings**:
- `env:` context from caller is **not** passed into reusable workflow — use `inputs` for everything.
- Reusable workflows inherit caller's `permissions` unless they declare their own.
- `secrets: inherit` passes all caller secrets including org-level and environment-scoped.
- Nesting limit is 4 levels deep (not a concern for this design).
- A skipped job (via `if: false`) counts as successful for `needs:` — use `needs.job.result == 'success'` for strict chaining if needed.

---

## R-007: Container Image Tag Parameter Handling

**Context**: The spec (FR-006) requires a `containerImage` parameter with tag override capability from the workflow.

**Decision**: Accept `container-image-tag` as a workflow input. Pass it to Bicep as `--parameters containerImageTag='${{ inputs.container-image-tag }}'` only when non-empty.

**Rationale**:
- CLI `--parameters` overrides take precedence over `.bicepparam` values.
- Wrapping the value in single quotes prevents shell injection.
- When the input is empty/omitted, the default `containerImage` from the `.bicepparam` file applies (placeholder image for infra-only deployments).

**Key Findings**:
- Multiple `--parameters` flags stack — file first, then individual overrides.
- Don't hardcode `containerImageTag` in `.bicepparam` files — let it flow from CI or default in the Bicep parameter definition.
- For full image reference (registry/repo:tag), the Bicep template composes it from `acrLoginServer` (derived from `acrResourceId`) + `containerImageName` + `containerImageTag`.

---

## Summary

| Research Item | Decision | Risk Level |
|--------------|----------|------------|
| R-001: Cross-RG ACR | Module with `scope: resourceGroup()` | Low — well-documented ARM pattern |
| R-002: Conditional ACA env | `if` on module + ternary output | Low — standard Bicep pattern |
| R-003: VNET integration | Optional `subnetId` param | Medium — subnet delegation is external prerequisite |
| R-004: Module structure | Local path references | Low — simplest viable approach |
| R-005: What-if parsing | Text grep for `Delete` | Low — simple and reliable with `--no-pretty-print` |
| R-006: Reusable workflow | `workflow_call` + 3 callers | Low — standard GitHub Actions pattern |
| R-007: Image tag handling | CLI `--parameters` override | Low — standard `az deployment` behavior |

All NEEDS CLARIFICATION items are resolved. No open questions remain.
