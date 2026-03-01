// ============================================================================
// Module: ACR Pull Role Assignment
// ============================================================================
// Assigns the AcrPull role to a managed identity on the specified ACR.
// Deployed with scope: resourceGroup(acrResourceGroup) from the orchestrator
// to support cross-resource-group ACR access.
// See: specs/001-aca-multienv-framework/data-model.md §2.2, research.md R-001
// ============================================================================

@description('Name of the Azure Container Registry.')
param acrName string

@description('Principal ID of the managed identity to grant AcrPull.')
param principalId string

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

// ---------------------------------------------------------------------------
// Resources
// ---------------------------------------------------------------------------

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, principalId, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
