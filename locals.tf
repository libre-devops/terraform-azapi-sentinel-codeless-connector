# -------------------------------------------------------------------------------------------------
# Two things get built: the connector's UI page (dataConnectorDefinition) and its poller
# connections (dataConnectors). The UI page's boilerplate (ingestion graph, sample query, data-type
# freshness query, connectivity check, workspace permissions) is derived from the destination table
# name so a minimal call gets a complete, correct page; every derived section is overridable.
# -------------------------------------------------------------------------------------------------

locals {
  ui    = var.connector_ui
  table = local.ui.graph_table

  # The connectorUiConfig is assembled by merge, not ternaries: the base carries the DEFAULT for
  # each section (derived from the table), and each override overlays its key only when provided.
  # merge replaces a key with the later value without unifying the two value types, which a ternary
  # would fail on (an OAuthForm instruction step and the plain default default carry different
  # attributes). resource_provider_permissions feeds the permissions object, so it resolves first.
  resource_provider_permissions = local.ui.resource_provider_permissions != null ? local.ui.resource_provider_permissions : [
    {
      provider               = "Microsoft.OperationalInsights/workspaces"
      providerDisplayName    = "Workspace"
      permissionsDisplayText = "Read and Write permissions are required."
      scope                  = "Workspace"
      requiredPermissions    = { read = true, write = true, delete = true }
    },
  ]

  permissions = merge(
    { resourceProvider = local.resource_provider_permissions },
    local.ui.custom_permissions != null ? { customs = local.ui.custom_permissions } : {},
  )

  connector_ui_config = merge(
    {
      title                 = local.ui.title
      id                    = coalesce(local.ui.id, var.definition_name)
      publisher             = local.ui.publisher
      descriptionMarkdown   = local.ui.description
      graphQueriesTableName = local.table
      availability          = { status = 1, isPreview = local.ui.is_preview }
      permissions           = local.permissions

      # Defaults, derived from the table; overridden by the merges below when supplied.
      graphQueries         = [{ metricName = "Records received", legend = local.table, baseQuery = "{{graphQueriesTableName}}" }]
      sampleQueries        = [{ description = "First 10 records", query = "{{graphQueriesTableName}}\n| take 10" }]
      dataTypes            = [{ name = "{{graphQueriesTableName}}", lastDataReceivedQuery = "{{graphQueriesTableName}}\n| summarize Time = max(TimeGenerated)\n| where isnotempty(Time)" }]
      connectivityCriteria = [{ type = "HasDataConnectors" }]
      instructionSteps     = [{ title = "Connect ${local.ui.title} to Microsoft Sentinel", description = "Provide the credentials for the source API to start polling." }]
    },
    local.ui.graph_queries != null ? { graphQueries = local.ui.graph_queries } : {},
    local.ui.sample_queries != null ? { sampleQueries = local.ui.sample_queries } : {},
    local.ui.data_types != null ? { dataTypes = local.ui.data_types } : {},
    local.ui.connectivity_criteria != null ? { connectivityCriteria = local.ui.connectivity_criteria } : {},
    local.ui.instruction_steps != null ? { instructionSteps = local.ui.instruction_steps } : {},
    local.ui.logo != null ? { logo = local.ui.logo } : {},
    can(keys(local.ui.extra_ui)) ? local.ui.extra_ui : {},
  )

  # Exposed for the advisory check.
  instruction_steps = local.ui.instruction_steps != null ? local.ui.instruction_steps : []
}

# -------------------------------------------------------------------------------------------------
# Poller connections: build each auth, request and response object from the typed inputs, dropping
# nulls and merging the raw escape hatches last.
# -------------------------------------------------------------------------------------------------
locals {
  auth_bodies = {
    for k, c in var.connections : k => merge(
      {
        for ak, av in {
          type = c.auth.type

          # Basic + JwtToken credentials
          UserName = c.auth.user_name
          Password = c.auth.password

          # APIKey
          ApiKey                = c.auth.api_key
          ApiKeyName            = c.auth.api_key_name
          ApiKeyIdentifier      = c.auth.api_key_identifier
          IsApiKeyInPostPayload = c.auth.is_api_key_in_post_payload

          # OAuth2
          ClientId              = c.auth.client_id
          ClientSecret          = c.auth.client_secret
          GrantType             = c.auth.grant_type
          TokenEndpoint         = c.auth.token_endpoint
          Scope                 = c.auth.scope
          AuthorizationEndpoint = c.auth.authorization_endpoint
          AuthorizationCode     = c.auth.authorization_code
          RedirectUri           = c.auth.redirect_uri

          # JwtToken specifics
          JwtTokenJsonPath       = c.auth.jwt_token_json_path
          IsCredentialsInHeaders = c.auth.is_credentials_in_headers
          IsJsonRequest          = c.auth.is_json_request
        } : ak => av if av != null
      },
      can(keys(c.auth.extra)) ? c.auth.extra : {},
    )
  }

  request_bodies = {
    for k, c in var.connections : k => merge(
      {
        for rk, rv in {
          apiEndpoint            = c.api_endpoint
          httpMethod             = c.http_method
          queryWindowInMin       = c.query_window_in_min
          queryTimeFormat        = c.query_time_format
          startTimeAttributeName = c.start_time_attribute_name
          endTimeAttributeName   = c.end_time_attribute_name
          rateLimitQPS           = c.rate_limit_qps
          retryCount             = c.retry_count
          timeoutInSeconds       = c.timeout_in_seconds
          headers                = c.headers
          queryParameters        = c.query_parameters
        } : rk => rv if rv != null
      },
      can(keys(c.request_extra)) ? c.request_extra : {},
    )
  }

  response_bodies = {
    for k, c in var.connections : k => {
      for rk, rv in {
        eventsJsonPaths       = c.response.events_json_paths
        format                = c.response.format
        successStatusJsonPath = c.response.success_status_json_path
        successStatusValue    = c.response.success_status_value
        isGzipCompressed      = c.response.is_gzip_compressed
      } : rk => rv if rv != null
    }
  }

  connection_bodies = {
    for k, c in var.connections : k => merge(
      {
        connectorDefinitionName = var.definition_name
        dcrConfig = {
          dataCollectionEndpoint        = c.dcr.data_collection_endpoint
          dataCollectionRuleImmutableId = c.dcr.data_collection_rule_immutable_id
          streamName                    = c.dcr.stream_name
        }
        auth     = local.auth_bodies[k]
        request  = local.request_bodies[k]
        response = local.response_bodies[k]
      },
      c.data_type != null ? { dataType = c.data_type } : {},
      c.paging != null ? { paging = { for pk, pv in c.paging : pk => pv if pv != null } } : {},
      can(keys(c.properties_extra)) ? c.properties_extra : {},
    )
  }
}
