output "connection_ids_zipmap" {
  description = "Connection name to {name, id}."
  value       = module.codeless_connector.connection_ids_zipmap
}

output "definition_id" {
  description = "The connector definition (page) id."
  value       = module.codeless_connector.definition_id
}
