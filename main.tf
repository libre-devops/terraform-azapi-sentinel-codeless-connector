# The connector's page in Sentinel: a Customizable data connector definition whose connectorUiConfig
# is derived from the destination table (overridable). Created first so the poller connections can
# link to it by name.
resource "azapi_resource" "definition" {
  type      = "Microsoft.SecurityInsights/dataConnectorDefinitions@${var.definition_api_version}"
  name      = var.definition_name
  parent_id = var.workspace_id

  body = {
    kind = "Customizable"
    properties = {
      connectorUiConfig = local.connector_ui_config
    }
  }

  # The azapi embedded schema lags the CCF surface (it rejects connectorUiConfig fields like
  # graphQueriesTableName and the RestApiPoller poller shapes that the live API accepts), so
  # validation is delegated to the service, which validates the whole body on the PUT.
  schema_validation_enabled = false

  retry = var.retry_error_message_regex == null ? null : { error_message_regex = var.retry_error_message_regex }

  # Bound the create so a misconfigured connector cannot leave azapi polling a stuck Sentinel
  # provisioning operation for the provider default (30m); a shorter create surfaces the real error
  # fast in CI. Delete stays generous because tearing a connector down can be slow.
  timeouts {
    create = var.resource_timeouts.create
    read   = var.resource_timeouts.read
    update = var.resource_timeouts.update
    delete = var.resource_timeouts.delete
  }
}

# One RestApiPoller connection per map entry, each linked to the definition. The poller runs as
# Sentinel's managed poller-as-a-service (no Azure Function), landing events on the connection's DCR
# stream. dataConnectorId must equal the resource name (the API's rule), which the map key provides.
resource "azapi_resource" "connections" {
  for_each = var.connections

  type      = "Microsoft.SecurityInsights/dataConnectors@${var.connector_api_version}"
  name      = each.key
  parent_id = var.workspace_id

  body = {
    kind       = "RestApiPoller"
    properties = local.connection_bodies[each.key]
  }

  # The azapi embedded schema lags the CCF surface (it rejects connectorUiConfig fields like
  # graphQueriesTableName and the RestApiPoller poller shapes that the live API accepts), so
  # validation is delegated to the service, which validates the whole body on the PUT.
  schema_validation_enabled = false

  retry = var.retry_error_message_regex == null ? null : { error_message_regex = var.retry_error_message_regex }

  # Bound the create so a misconfigured connection cannot leave azapi polling a stuck Sentinel
  # provisioning operation for the provider default (30m); a shorter create surfaces the real error
  # fast in CI. Delete stays generous because tearing a connector down can be slow.
  timeouts {
    create = var.resource_timeouts.create
    read   = var.resource_timeouts.read
    update = var.resource_timeouts.update
    delete = var.resource_timeouts.delete
  }

  # The connection references the definition by name; the definition must exist first.
  depends_on = [azapi_resource.definition]
}
