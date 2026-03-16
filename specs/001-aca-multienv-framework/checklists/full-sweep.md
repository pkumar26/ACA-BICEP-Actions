# Full Sweep Checklist: Multi-Environment ACA Framework

**Purpose**: Validate completeness, clarity, consistency, and measurability of requirements across all domains (Bicep, CI/CD, Security, Multi-App Reuse)  
**Created**: 2026-02-28  
**Depth**: Standard (~30 items)  
**Audience**: Reviewer (PR review)  
**Feature**: [spec.md](../spec.md)

---

## Requirement Completeness

- [ ] CHK001 - Are health probe (liveness/readiness) requirements defined for container apps, or is the omission explicitly scoped out with criteria for when to add them? [Gap, Spec §5 Container app module]
- [ ] CHK002 - Are Azure Monitor alert requirements (scale failure, HTTP 5xx, container restart loops) documented as a deferred follow-up with a tracking reference, or only mentioned in Non-Goals? [Completeness, Spec §1 Non-Goals]
- [ ] CHK003 - Are requirements defined for what happens when the `containerImage` default placeholder is used in production (guard rails, warnings, validation)? [Gap, Spec §6]
- [ ] CHK004 - Are subnet delegation prerequisites (`Microsoft.App/environments`) specified for VNET integration, or only assumed? [Completeness, Spec §10 Assumptions]
- [ ] CHK005 - Are logging/retention requirements specified per environment (e.g., 30-day dev vs. 90-day prod), or is 30-day retention a blanket requirement regardless of environment? [Gap, Spec §FR-003]

## Requirement Clarity

- [ ] CHK006 - Is the `parameter-file` input's path resolution unambiguous — relative to repo root, workspace, or checkout path? [Clarity, Contract §1 Inputs]
- [ ] CHK007 - Is "manual dispatch or tagged commit" for QA trigger precisely defined — which tag pattern, and is it `or` or `and`? [Ambiguity, Spec §7 Workflow Behaviors / FR-011]
- [ ] CHK008 - Is the `container-image-tag` override behavior specified when the tag is provided but the image doesn't exist in ACR? [Clarity, Contract §1 Inputs]
- [ ] CHK009 - Is "30 minutes onboarding" (SC-001) measurable — does it include Entra ID app registration, federated credential setup, and Key Vault role assignment, or only framework-specific steps? [Measurability, Spec §SC-001]
- [ ] CHK010 - Is the `@secure()` annotation on Log Analytics `primarySharedKey` output documented as a requirement, or only an implementation detail in the data model? [Clarity, Data Model §2.3]

## Requirement Consistency

- [ ] CHK011 - Are the `ingressExternal` default values consistent between the spec (FR-007 mandates `allowInsecure: false`) and the data model (default `false` for `ingressExternal`)? These are two different properties — is the distinction clear? [Consistency, Spec §FR-007, Data Model §1]
- [ ] CHK012 - Does the spec's statement that callers use `secrets: inherit` (Contract §1 Secrets) align with the security requirement that no secrets are stored in GitHub (Spec §FR-014)? Is the boundary between OIDC identifiers and "secrets" clearly drawn? [Consistency, Spec §FR-014, Contract §1]
- [ ] CHK013 - Are the environment sizing defaults in the README consistent with what the parameter files actually define, and is there a single source of truth specified? [Consistency, Spec §FR-006]
- [ ] CHK014 - Are the `tags` requirements consistent — Spec §FR-013 requires `Environment`, `Project`, `ManagedBy` on every resource, but are module-level tag propagation rules defined to ensure child resources inherit parent tags? [Consistency, Spec §FR-013]

## Acceptance Criteria Quality

- [ ] CHK015 - Can SC-004 ("zero resource modifications on re-run") be objectively measured — is a specific verification method defined (e.g., what-if output showing "no changes")? [Measurability, Spec §SC-004]
- [ ] CHK016 - Is acceptance scenario US2.2 ("environment variable is available to the application process") testable without deploying application code — how should this be verified? [Measurability, Spec §US2 scenario 2]
- [ ] CHK017 - Is SC-007 ("every provisioned resource carries required tags") verifiable — is the Azure Resource Graph query or verification command specified? [Measurability, Spec §SC-007]

## Scenario Coverage

- [ ] CHK018 - Are requirements defined for deploying multiple container apps into the same existing ACA managed environment (via `existingManagedEnvironmentId`)? Does the naming scheme prevent collisions? [Coverage, Spec §FR-004]
- [ ] CHK019 - Are requirements specified for the workflow behavior when `what-if` itself fails (e.g., ARM throttling, network timeout), as distinct from when what-if succeeds but detects deletions? [Coverage, Spec §FR-009]
- [ ] CHK020 - Are requirements defined for concurrent deployments to the same environment from different workflow runs? Is there a locking or serialization mechanism specified? [Coverage, Gap]
- [ ] CHK021 - Are requirements specified for the `allow-destructive` override audit trail — how is the decision to force-deploy despite deletions tracked? [Coverage, Spec §FR-009]

## Edge Case Coverage

- [ ] CHK022 - Is the behavior specified when `existingIdentityResourceId` is provided but the identity doesn't exist or has been deleted? [Edge Case, Spec §US6]
- [ ] CHK023 - Is the behavior defined when `acrResourceId` points to an ACR the service principal cannot access (wrong subscription, no permissions)? [Edge Case, Spec §FR-002]
- [ ] CHK024 - Are requirements defined for `secretEnvVars` containing duplicate `secretRef` values or `appEnvVars` containing duplicate `name` entries? [Edge Case, Data Model §1]
- [ ] CHK025 - Is the behavior specified when `maxReplicas < minReplicas` is set in a parameter file? The spec mentions validation is deferred — is that gap acceptable? [Edge Case, Spec §Edge Cases]

## Non-Functional Requirements

- [ ] CHK026 - Are sovereign cloud requirements explicitly scoped out with the specific limitation documented (ACR login server suffix hardcoded as `.azurecr.io`)? [Coverage, Spec §10 Assumptions]
- [ ] CHK027 - Are deployment timeout requirements specified — what happens if `az deployment group create` exceeds the default ARM timeout? [Gap]
- [ ] CHK028 - Are GitHub Actions runner requirements specified beyond `ubuntu-latest` — is there a minimum toolset version (az CLI, Bicep CLI) assumed? [Gap, Plan §Technical Context]

## Dependencies & Assumptions

- [ ] CHK029 - Is the assumption that "one Key Vault per environment already exists" validated — are alternative patterns (shared Key Vault, no Key Vault) addressed or explicitly excluded? [Assumption, Spec §10]
- [ ] CHK030 - Is the dependency on `User Access Administrator` role on the ACR resource group clearly documented as a prerequisite with actionable setup steps, not just as an assumption? [Dependency, Spec §10 Assumptions]
- [ ] CHK031 - Is the requirement for Entra ID app registration with federated credentials documented with step-by-step prerequisites, or only described conceptually in Spec §4? [Dependency, Spec §4]

## Notes

- Check items off as completed: `[x]`
- Add inline comments or link to spec sections when resolving items
- Items referencing `[Gap]` indicate missing requirements — add to spec or document as intentionally deferred
- Items referencing `[Ambiguity]` indicate requirements needing clarification — update spec language
