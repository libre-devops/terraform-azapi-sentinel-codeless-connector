output "connection_ids" {
  description = "Map of connection name to its RestApiPoller data connector resource id."
  value       = { for k, r in azapi_resource.connections : k => r.id }
}

output "connection_ids_zipmap" {
  description = "Map of connection name to {name, id} for easy composition."
  value       = { for k, r in azapi_resource.connections : k => { name = k, id = r.id } }
}

output "definition_id" {
  description = "Resource id of the data connector definition (the connector's page in Sentinel)."
  value       = azapi_resource.definition.id
}

output "definition_name" {
  description = "Name of the data connector definition, the connectorDefinitionName every connection links to."
  value       = var.definition_name
}

output "graph_table" {
  description = "The destination custom table the connector's UI and its connections target."
  value       = var.connector_ui.graph_table
}
