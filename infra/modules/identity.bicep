// ============================================================================
// Module: User-Assigned Managed Identity
// ============================================================================
// Conditionally creates a new UAMI or resolves an existing one.
// See: specs/001-aca-multienv-framework/data-model.md §2.1
// ============================================================================

@description('Resource suffix for naming: {appName}-{environmentName}')
param resourceSuffix string

@description('Azure region for the identity resource.')
param location string

@description('Tags to apply to the identity resource.')
param tags object

@description('Whether to create a new managed identity.')
param createNewIdentity bool

@description('Resource ID of an existing managed identity. Required when createNewIdentity is false.')
param existingIdentityResourceId string = ''

// ---------------------------------------------------------------------------
// Resources
// ---------------------------------------------------------------------------

resource newIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (createNewIdentity) {
  name: 'id-${resourceSuffix}'
  location: location
  tags: tags
}

resource existingIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = if (!createNewIdentity) {
  name: last(split(existingIdentityResourceId, '/'))!
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the managed identity (new or existing).')
output identityResourceId string = createNewIdentity ? newIdentity.id : existingIdentityResourceId

@description('Principal ID of the managed identity (for role assignments).')
output identityPrincipalId string = createNewIdentity ? newIdentity.properties.principalId : existingIdentity!.properties.principalId
