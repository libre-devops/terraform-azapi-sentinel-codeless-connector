output "connection_ids" {
  description = "The poller connection ids."
  value       = module.codeless_connector.connection_ids
}

output "definition_id" {
  description = "The connector definition (page) id."
  value       = module.codeless_connector.definition_id
}
