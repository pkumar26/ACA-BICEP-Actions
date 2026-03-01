// ============================================================================
// Module: Log Analytics Workspace
// ============================================================================
// Creates a Log Analytics workspace for ACA log ingestion.
// Always runs — even when existingManagedEnvironmentId is provided —
// to serve as an independent log sink for custom KQL queries.
// See: specs/001-aca-multienv-framework/data-model.md §2.3
// ============================================================================

@description('Resource suffix for naming: {appName}-{environmentName}')
param resourceSuffix string

@description('Azure region for the workspace.')
param location string

@description('Tags to apply to the workspace.')
param tags object

// ---------------------------------------------------------------------------
// Resources
// ---------------------------------------------------------------------------

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${resourceSuffix}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the Log Analytics workspace.')
output workspaceId string = logAnalytics.id

@description('Customer ID of the Log Analytics workspace (for ACA binding).')
output customerId string = logAnalytics.properties.customerId

@secure()
@description('Primary shared key for the Log Analytics workspace.')
output primarySharedKey string = logAnalytics.listKeys().primarySharedKey
