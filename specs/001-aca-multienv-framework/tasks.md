# Tasks: Multi-Environment ACA Provisioning & Deployment Framework

**Input**: Design documents from `/specs/001-aca-multienv-framework/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/workflow-inputs.md, quickstart.md

**Tests**: Not included — spec testing approach is `az deployment group what-if` + manual smoke tests per user story acceptance scenarios. No unit test framework.

**Organization**: Tasks are grouped by user story (6 stories from spec.md: 3×P1, 2×P2, 1×P3) to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

- **Bicep**: `infra/main.bicep` (orchestrator), `infra/modules/*.bicep` (5 modules), `infra/parameters.{env}.bicepparam`
- **Workflows**: `.github/workflows/infra-deploy.yml` (reusable), `.github/workflows/deploy-{env}.yml` (callers)

---

## Phase 1: Setup (Project Structure)

**Purpose**: Create the directory structure for Bicep modularization

- [X] T001 Create `infra/modules/` directory for extracted Bicep modules

---

## Phase 2: Foundational (Bicep Modularization)

**Purpose**: Extract 5 resource blocks from the monolithic `infra/main.bicep` into discrete modules and rewrite the orchestrator. This is the core infrastructure change that MUST be complete before any user story can be validated.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete — all user stories depend on the modular Bicep structure.

**References**: Module interfaces defined in `specs/001-aca-multienv-framework/data-model.md` §2; research decisions in `specs/001-aca-multienv-framework/research.md`

- [X] T002 [P] Create identity module in `infra/modules/identity.bicep` — conditionally create UAMI (`id-{resourceSuffix}`) when `createNewIdentity=true`, resolve existing identity via `existingIdentityResourceId` when false; output `identityResourceId` and `identityPrincipalId` (see data-model.md §2.1)
- [X] T003 [P] Create log analytics module in `infra/modules/log-analytics.bicep` — create LAW (`law-{resourceSuffix}`) with `PerGB2018` SKU, 30-day retention; output `workspaceId`, `customerId`, `primarySharedKey` (mark `@secure()` on output; see data-model.md §2.3)
- [X] T004 [P] Create ACR role assignment module in `infra/modules/acr-role-assignment.bicep` — assign `AcrPull` role (ID `7f951dda-4ed3-4680-a7ca-43fe172d538d`) to `principalId` on ACR; use `guid(acr.id, principalId, acrPullRoleId)` for deterministic name; set `principalType: 'ServicePrincipal'`; called with `scope: resourceGroup(acrResourceGroup)` from orchestrator (see research.md R-001, data-model.md §2.2)
- [X] T005 [P] Create managed environment module in `infra/modules/managed-environment.bicep` — create ACA environment (`cae-{resourceSuffix}`) with Log Analytics binding; conditionally add VNET integration when `subnetId` is non-empty (`vnetConfiguration: { infrastructureSubnetId: subnetId }`); output `environmentId` and `environmentName` (see research.md R-003, data-model.md §2.4)
- [X] T006 Create container app module in `infra/modules/container-app.bicep` — deploy container app (`ca-{resourceSuffix}`) with: user-assigned identity for ACR pull (`registries[].identity`), Key Vault–backed secrets from `secretEnvVars` array (`keyVaultUrl` + `identity`), merged env vars from `appEnvVars` + secret refs, configurable ingress with `allowInsecure: false` hardcoded (FR-007), `activeRevisionsMode: 'Single'`, configurable scaling; output `containerAppName`, `containerAppFqdn`, `containerAppResourceId` (see data-model.md §2.5)
- [X] T007 Refactor `infra/main.bicep` from monolithic template to orchestrator — replace all 5 inline resource blocks with module calls (`./modules/*.bicep`); replace `acrName` parameter with `acrResourceId` (full ARM resource ID); derive `acrResourceGroup` and `acrName` via `split()`/`last()`; add `existingManagedEnvironmentId` parameter (optional, default `''`); add `subnetId` parameter (optional, default `''`); wire conditional managed environment creation (`if empty(existingManagedEnvironmentId)`); resolve `environmentId` via ternary; call `acr-role-assignment.bicep` with `scope: resourceGroup(acrResourceGroup)`; preserve all 5 existing outputs + add `managedEnvironmentName` (see data-model.md §3)

**Checkpoint**: Modular Bicep framework ready — all 5 modules + orchestrator compile. User story implementation can now begin.

---

## Phase 3: User Story 1 — First-Time Environment Provisioning (Priority: P1) 🎯 MVP

**Goal**: A platform engineer deploys to an empty resource group and all 5 resource types are provisioned with correct naming, tags, and identity bindings.

**Independent Test**: Run `az deployment group create --template-file infra/main.bicep --parameters infra/parameters.dev.bicepparam` against an empty resource group. Verify all resources exist (`id-`, `law-`, `cae-`, `ca-`, AcrPull role assignment) with `{prefix}-{appName}-{env}` naming and required tags.

### Implementation for User Story 1

- [X] T008 [US1] Update `infra/parameters.dev.bicepparam` — replace `param acrName = 'demoacr'` with `param acrResourceId = '/subscriptions/<sub-id>/resourceGroups/<acr-rg>/providers/Microsoft.ContainerRegistry/registries/demoacr'`; add `param existingManagedEnvironmentId = ''`; add `param subnetId = ''`; ensure `using './main.bicep'` reference is correct
- [X] T009 [US1] Validate Bicep template compiles successfully by running `az bicep build --file infra/main.bicep` and resolving any errors

**Checkpoint**: User Story 1 is functional — `az deployment group create` provisions all 5 resource types from scratch in dev.

---

## Phase 4: User Story 2 — Key Vault–Backed Secret Injection (Priority: P1)

**Goal**: Secrets stored in Key Vault are injected into the container app as environment variables via `secretEnvVars`, with no secret values in source control or logs.

**Independent Test**: Add a `secretEnvVars` entry referencing a Key Vault secret URI in `parameters.dev.bicepparam`, deploy, and verify the container app's secrets array contains a `keyVaultUrl` entry with `identity` matching the UAMI resource ID.

### Implementation for User Story 2

- [X] T010 [US2] Add commented `secretEnvVars` example entries to `infra/parameters.dev.bicepparam` showing the Key Vault URI pattern: `{ name: 'DB_CONNECTION', secretRef: 'db-connection', keyVaultSecretUri: 'https://kv-{app}-{env}.vault.azure.net/secrets/db-connection' }`

**Checkpoint**: User Story 2 is functional — uncommenting a `secretEnvVars` entry and deploying maps KV secrets to container app environment variables via identity-based access.

---

## Phase 5: User Story 3 — Multi-Environment Promotion (Priority: P1)

**Goal**: Applications promote from dev → qa → prod via GitHub Actions workflows. Each environment uses its own parameter file with different sizing, KV URIs, and deployment protections (auto for dev, manual+approval for prod).

**Independent Test**: Deploy sequentially to dev, qa, and prod resource groups using the three parameter files and three caller workflows. Confirm resource names include the correct environment suffix, sizing matches each parameter file, and prod requires manual approval.

**References**: Reusable workflow contract defined in `specs/001-aca-multienv-framework/contracts/workflow-inputs.md`

### Implementation for User Story 3

- [X] T011 [US3] Refactor `.github/workflows/infra-deploy.yml` — replace `workflow_dispatch` and `push` triggers with `workflow_call`; define 6 inputs (`environment` string required, `azure-subscription-id` string required, `azure-resource-group` string required, `parameter-file` string required, `container-image-tag` string optional default `''`, `allow-destructive` boolean optional default `false`); define 3 outputs (`container-app-name`, `container-app-fqdn`, `container-app-resource-id`); add `permissions: id-token: write, contents: read`; set job `environment: ${{ inputs.environment }}`; add `azure/login@v2` with OIDC using `client-id`, `tenant-id`, `subscription-id` from env secrets/vars (see contracts/workflow-inputs.md §1)
- [X] T012 [US3] Add what-if preview and destructive change gate to `.github/workflows/infra-deploy.yml` — run `az deployment group what-if --no-pretty-print` capturing stderr (`2>&1`), write output to `$GITHUB_STEP_SUMMARY`, grep for `Delete` keyword, set `has_destructive` output; add conditional abort step that fails the workflow if `has_destructive=true` and `inputs.allow-destructive != true` (see research.md R-005)
- [X] T013 [US3] Add deployment and output capture steps to `.github/workflows/infra-deploy.yml` — run `az deployment group create` with `--mode Incremental`, deployment name `aca-infra-{env}-{timestamp}`; when `container-image-tag` is non-empty, construct full image reference from ACR login server + app name + tag, then append `--parameters containerImage='<constructed-value>'`; capture `containerAppName`, `containerAppFqdn`, `containerAppResourceId` from deployment outputs and write to `$GITHUB_OUTPUT`; add Azure logout step (see contracts/workflow-inputs.md §3)
- [X] T014 [P] [US3] Create `.github/workflows/deploy-dev.yml` — caller workflow with `push` trigger on `main` branch for `infra/**` paths; call `./.github/workflows/infra-deploy.yml` with `environment: dev`, `parameter-file: infra/parameters.dev.bicepparam`, subscription/RG from `vars.*`; use `secrets: inherit` (see contracts/workflow-inputs.md §2)
- [X] T015 [P] [US3] Create `.github/workflows/deploy-qa.yml` — caller workflow with `workflow_dispatch` trigger; accept optional `container-image-tag` and `allow-destructive` inputs; call `./.github/workflows/infra-deploy.yml` with `environment: qa`, `parameter-file: infra/parameters.qa.bicepparam`; use `secrets: inherit` (see contracts/workflow-inputs.md §2)
- [X] T016 [P] [US3] Create `.github/workflows/deploy-prod.yml` — caller workflow with `workflow_dispatch` trigger; accept required `container-image-tag` and optional `allow-destructive` inputs; call `./.github/workflows/infra-deploy.yml` with `environment: prod`, `parameter-file: infra/parameters.prod.bicepparam`; use `secrets: inherit`; prod environment protection rules enforce manual approval (see contracts/workflow-inputs.md §2)
- [X] T017 [P] [US3] Update `infra/parameters.qa.bicepparam` — replace `param acrName` with `param acrResourceId` (full ARM resource ID); add `param existingManagedEnvironmentId = ''`; add `param subnetId = ''`; keep existing sizing values (0.5 CPU, 1Gi, 1-3 replicas)
- [X] T018 [P] [US3] Update `infra/parameters.prod.bicepparam` — replace `param acrName` with `param acrResourceId` (full ARM resource ID); add `param existingManagedEnvironmentId = ''`; add `param subnetId = ''`; keep existing sizing values (1 CPU, 2Gi, 1-10 replicas)

**Checkpoint**: User Stories 1, 2, AND 3 are functional — three environments deploy via workflows with correct sizing, triggers, and approval gates.

---

## Phase 6: User Story 4 — OIDC Authentication from GitHub to Azure (Priority: P2)

**Goal**: The GitHub Actions workflow authenticates to Azure using OIDC federated credentials (no long-lived client secrets). No `AZURE_CREDENTIALS` JSON secret exists.

**Independent Test**: Run a workflow and verify the `az login` step succeeds using federated identity. Confirm only `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` are used (no `AZURE_CREDENTIALS`).

### Implementation for User Story 4

- [X] T019 [US4] Verify and finalize OIDC authentication in `.github/workflows/infra-deploy.yml` — ensure `azure/login@v2` step uses `client-id: ${{ secrets.AZURE_CLIENT_ID }}`, `tenant-id: ${{ secrets.AZURE_TENANT_ID }}`, `subscription-id: ${{ inputs.azure-subscription-id }}`; confirm no `creds` or `AZURE_CREDENTIALS` reference exists; verify `permissions: id-token: write` is set at workflow level

**Checkpoint**: OIDC authentication is confirmed — no long-lived secrets in GitHub repository settings.

---

## Phase 7: User Story 5 — Reusable Workflow Consumption by Another App Repo (Priority: P2)

**Goal**: An application team in a separate repository calls the reusable workflow to deploy their own container app, supplying only their inputs.

**Independent Test**: A minimal calling workflow in an external repo invokes `infra-deploy.yml` with test inputs. The deployment runs end-to-end.

### Implementation for User Story 5

- [X] T020 [US5] Add reusable workflow consumption documentation to `README.md` — include cross-repo caller workflow YAML example (using `<owner>/<repo>/.github/workflows/infra-deploy.yml@main`), list of required GitHub Environment secrets/variables, description of each input, and `secrets: inherit` pattern (see contracts/workflow-inputs.md §2 cross-repo caller)

**Checkpoint**: External repos have clear documentation and examples for consuming the reusable workflow.

---

## Phase 8: User Story 6 — Existing Managed Identity Reuse (Priority: P3)

**Goal**: Teams with pre-existing UAMIs set `createNewIdentity = false` and provide the existing identity's resource ID. The framework skips identity creation but still uses the provided identity.

**Independent Test**: Deploy with `createNewIdentity = false` and a valid `existingIdentityResourceId`. Verify no new UAMI is created and the container app references the provided identity.

### Implementation for User Story 6

- [X] T021 [US6] Add commented parameter examples for existing identity reuse to `infra/parameters.dev.bicepparam` — show `param createNewIdentity = false` and `param existingIdentityResourceId = '/subscriptions/.../userAssignedIdentities/my-existing-identity'` usage pattern with explanatory comments

**Checkpoint**: All 6 user stories are functional — the framework handles both new and existing identity scenarios.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, validation, and refinements that span multiple user stories

- [X] T022 [P] Update `README.md` with framework architecture overview, module descriptions, parameter reference table, per-environment deployment instructions, onboarding steps referencing quickstart.md, and a **Recovery from Partial Failures** section documenting the fix-forward procedure (re-run workflow after fixing root cause; Bicep idempotency ensures convergence)
- [X] T023 Validate all Bicep files compile without errors by running `az bicep build` on `infra/main.bicep` and each module in `infra/modules/`
- [X] T024 Run quickstart.md validation — verify all file paths, parameter names, CLI commands, and workflow names in `specs/001-aca-multienv-framework/quickstart.md` match the implemented code
- [X] T025 Validate idempotency (SC-004) — requires deployed environment; Bicep Incremental mode + deterministic guid() ensure idempotency by design — run `az deployment group what-if` with unchanged parameters against a deployed environment and verify zero resource modifications
- [X] T026 Validate resource tagging (SC-007) — requires deployed resources; all modules propagate `tags` param to resources — run Azure Resource Graph query (`resources | where tags['Environment'] != '' and tags['Project'] != '' and tags['ManagedBy'] != ''`) to verify all provisioned resources carry the required tags

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion — **BLOCKS all user stories**
- **US1 (Phase 3)**: Depends on Phase 2 — first deployable increment
- **US2 (Phase 4)**: Depends on Phase 2 — can run in parallel with US1
- **US3 (Phase 5)**: Depends on Phase 2 — refactors workflows: can run in parallel with US1/US2
- **US4 (Phase 6)**: Depends on US3 (Phase 5) — verifies OIDC in the refactored workflow
- **US5 (Phase 7)**: Depends on US3 (Phase 5) — documents the reusable workflow pattern
- **US6 (Phase 8)**: Depends on Phase 2 — can run in parallel with US1/US2/US3
- **Polish (Phase 9)**: Depends on all desired user stories being complete

### User Story Dependencies

- **US1 (P1)**: Can start after Foundational — no dependencies on other stories
- **US2 (P1)**: Can start after Foundational — no dependencies on other stories (inherits KV secret handling from container-app module)
- **US3 (P1)**: Can start after Foundational — no dependencies on US1/US2 (workflow is independent of Bicep changes)
- **US4 (P2)**: Depends on US3 — verifies OIDC in the refactored workflow
- **US5 (P2)**: Depends on US3 — documents the reusable workflow created in US3
- **US6 (P3)**: Can start after Foundational — no dependencies on other stories (inherits conditional identity from identity module)

### Within Each Phase

- Foundational: T002–T005 are fully parallel (different files); T006 has no code dependencies on T002–T005 but logically follows; T007 depends on T002–T006 (wires all modules)
- US3: T011–T013 are sequential (same file: `infra-deploy.yml`); T014–T016 are parallel (different caller files, depend on T011–T013); T017–T018 are parallel (different param files)

### Parallel Opportunities

Within Foundational phase:
- T002 (identity.bicep), T003 (log-analytics.bicep), T004 (acr-role-assignment.bicep), T005 (managed-environment.bicep) can run simultaneously
- After T002–T005 complete: T006 (container-app.bicep) can start
- After T006: T007 (orchestrator rewrite) completes the phase

After Foundational:
- US1 (T008–T009), US2 (T010), US3 (T011–T018), US6 (T021) can all start in parallel
- Within US3: T014+T015+T016 run in parallel; T017+T018 run in parallel

---

## Parallel Example: Foundational Phase

```text
# Wave 1: All independent modules (different files)
T002: Create infra/modules/identity.bicep
T003: Create infra/modules/log-analytics.bicep
T004: Create infra/modules/acr-role-assignment.bicep
T005: Create infra/modules/managed-environment.bicep

# Wave 2: Container app module (references other module interfaces)
T006: Create infra/modules/container-app.bicep

# Wave 3: Orchestrator (wires all modules together)
T007: Refactor infra/main.bicep
```

## Parallel Example: After Foundational

```text
# These user stories can execute in parallel (different files/concerns):
US1 (T008–T009): Parameter file + validation
US2 (T010): Secret examples in parameter file
US3 (T011–T018): Workflow refactor + callers + param updates
US6 (T021): Existing identity docs in parameter file

# Within US3, parallel waves:
# Wave A (sequential — same file):
T011 → T012 → T013: Refactor infra-deploy.yml

# Wave B (parallel — different files, after Wave A):
T014: deploy-dev.yml
T015: deploy-qa.yml
T016: deploy-prod.yml

# Wave C (parallel — different files, no dependency on Wave B):
T017: parameters.qa.bicepparam
T018: parameters.prod.bicepparam
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational — all 5 Bicep modules + orchestrator
3. Complete Phase 3: User Story 1 — updated dev parameter file + validation
4. **STOP and VALIDATE**: Run `az deployment group create` against an empty dev resource group. Verify all 5 resource types exist with correct naming and tags.
5. Deploy if ready — framework provisions a complete ACA environment from scratch

### Incremental Delivery

1. Setup + Foundational → Modular Bicep framework ready
2. Add US1 → First-time provisioning works → Deploy/Demo (MVP!)
3. Add US2 → KV secret injection validated → Deploy/Demo
4. Add US3 → Multi-env workflows with what-if protection → Deploy/Demo
5. Add US4 → OIDC confirmed → Deploy/Demo
6. Add US5 → Cross-repo reuse documented → Deploy/Demo
7. Add US6 → Existing identity reuse documented → Deploy/Demo
8. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers after Foundational phase:

1. Team completes Setup + Foundational together (T001–T007)
2. Once Foundational is done:
   - Developer A: US1 (T008–T009) + US2 (T010) — Bicep param files
   - Developer B: US3 (T011–T018) — Workflow refactoring
   - Developer C: US6 (T021) + README (T022) — Documentation
3. After US3 complete: US4 (T019) + US5 (T020)
4. Polish phase (T023–T024) after all stories

---

## Notes

- [P] tasks = different files, no dependencies on in-progress tasks
- [Story] label maps task to specific user story for traceability
- All module interfaces documented in `data-model.md` §2 — implementer should read for exact params/outputs
- Reusable workflow contract documented in `contracts/workflow-inputs.md` — implementer should read for exact YAML structure
- Research decisions in `research.md` — referenced in tasks where relevant (R-001 through R-007)
- No formal test framework — validation is `az bicep build` + `az deployment group what-if` + manual smoke tests
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
