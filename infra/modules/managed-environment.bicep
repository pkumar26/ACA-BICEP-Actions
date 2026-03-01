// ============================================================================
// Module: ACA Managed Environment
// ============================================================================
// Creates an ACA managed environment wired to Log Analytics, with optional
// VNET integration. Conditionally deployed at orchestrator level when
// existingManagedEnvironmentId is empty.
// See: specs/001-aca-multienv-framework/data-model.md §2.4, research.md R-003
// ============================================================================

@description('Resource suffix for naming: {appName}-{environmentName}')
param resourceSuffix string

@description('Azure region for the managed environment.')
param location string

@description('Tags to apply to the managed environment.')
param tags object

@description('Log Analytics workspace customer ID.')
param logAnalyticsCustomerId string

@secure()
@description('Log Analytics workspace primary shared key.')
param logAnalyticsPrimarySharedKey string

@description('Optional subnet resource ID for VNET integration. Empty string = no VNET.')
param subnetId string = ''

// ---------------------------------------------------------------------------
// Resources
// ---------------------------------------------------------------------------

resource managedEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${resourceSuffix}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalyticsPrimarySharedKey
      }
    }
    vnetConfiguration: !empty(subnetId) ? {
      infrastructureSubnetId: subnetId
      internal: false
    } : null
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the managed environment.')
output environmentId string = managedEnv.id

@description('Name of the managed environment.')
output environmentName string = managedEnv.name
