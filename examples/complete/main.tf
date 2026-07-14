# Complete call: every feature. Two poller connections on one connector (an OAuth2 client-
# credentials poll of Microsoft Graph and an API-key poll), a fully overridden UI page (custom
# graph and sample queries, an OAuthForm instruction, custom prerequisite permissions, preview
# flag), and the whole supporting stack composed so it is runnable. Applied then destroyed in one
# CI run.
locals {
  location = lookup(var.regions, var.loc, "uksouth")
  rg_name  = "rg-${var.short}-${var.loc}-${terraform.workspace}-002"
  law_name = "log-${var.short}-${var.loc}-${terraform.workspace}-002"
  dce_name = "dce-${var.short}-${var.loc}-${terraform.workspace}-002"
  dcr_name = "dcr-${var.short}-${var.loc}-${terraform.workspace}-002"

  table  = "ExampleApiLogs_CL"
  stream = "Custom-${local.table}" # the DCR output stream must name the destination custom table (Custom-<table>)
}

module "tags" {
  source  = "libre-devops/tags/azurerm"
  version = "~> 4.0"

  cost_centre     = "1888/67"
  owner           = "soc@example.com"
  deployed_branch = var.deployed_branch
  deployed_repo   = var.deployed_repo
}

module "rg" {
  source  = "libre-devops/rg/azurerm"
  version = "~> 4.0"

  resource_groups = [{ name = local.rg_name, location = local.location, tags = module.tags.tags }]
}

module "law" {
  source  = "libre-devops/log-analytics-workspace/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  log_analytics_workspaces = {
    (local.law_name) = {
      onboard_to_sentinel = true

      custom_tables = [
        {
          name = local.table
          columns = [
            { name = "TimeGenerated", type = "dateTime" },
            { name = "EventId", type = "string" },
            { name = "Message", type = "string" },
          ]
        }
      ]
    }
  }
}

module "data_collection" {
  source  = "libre-devops/data-collection/azurerm"
  version = "~> 4.0"

  # The DCR output stream (Custom-<table>) targets the destination custom table, so the table must
  # exist first. The workspace id output resolves once the workspace exists, not once its custom
  # tables finish, so order the whole workspace module ahead of the DCR explicitly.
  depends_on = [module.law]

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  data_collection_endpoints = {
    (local.dce_name) = {}
  }

  data_collection_rules = {
    (local.dcr_name) = {
      data_collection_endpoint = local.dce_name

      stream_declarations = {
        (local.stream) = {
          columns = [
            { name = "TimeGenerated", type = "datetime" },
            { name = "EventId", type = "string" },
            { name = "Message", type = "string" },
          ]
        }
      }

      destinations = {
        log_analytics = [{ name = "law", workspace_resource_id = module.law.workspace_ids[local.law_name] }]
      }

      data_flows = [{
        streams       = [local.stream]
        destinations  = ["law"]
        output_stream = local.stream
        # A custom-stream direct-ingestion data flow needs a transform; "source" passes rows
        # through unchanged into the destination table.
        transform_kql = "source"
      }]
    }
  }
}

module "codeless_connector" {
  source = "../../"

  # The connector definition is created under the Sentinel-onboarded workspace. Onboarding is a
  # separate resource inside the workspace module that the workspace id output does not wait for, so
  # order the whole module ahead of the connector; the module's retry regex covers residual
  # onboarding propagation lag after that.
  depends_on = [module.law]

  workspace_id    = module.law.workspace_ids[local.law_name]
  definition_name = "ldo-example-multi-connector"

  # API versions are variablised (never hardcoded); the defaults are restated to show the override
  # point.
  definition_api_version = "2025-09-01"
  connector_api_version  = "2025-09-01"

  connector_ui = {
    title       = "Example Multi-Source Connector"
    publisher   = "Libre DevOps"
    description = "Demonstrates OAuth2 and API-key polling into one Sentinel connector."
    graph_table = local.table
    is_preview  = true

    graph_queries = [
      { metricName = "Events received", legend = local.table, baseQuery = "{{graphQueriesTableName}}" },
    ]
    sample_queries = [
      { description = "Recent events", query = "{{graphQueriesTableName}}\n| sort by TimeGenerated desc\n| take 20" },
    ]

    custom_permissions = [
      { name = "API credentials", description = "The source API's client id and secret (OAuth2) or key are required." },
    ]

    instruction_steps = [
      {
        title       = "Authorize the connector"
        description = "Provide the OAuth2 application credentials, then connect."
        instructions = [
          {
            type = "OAuthForm"
            parameters = {
              clientIdLabel         = "Client ID"
              clientSecretLabel     = "Client Secret"
              connectButtonLabel    = "Connect"
              disconnectButtonLabel = "Disconnect"
            }
          },
        ]
      },
    ]
  }

  connections = {
    # OAuth2 client-credentials poll of Microsoft Graph audit logs.
    "graph-audit" = {
      api_endpoint = "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits"

      dcr = {
        data_collection_endpoint          = module.data_collection.data_collection_endpoints[local.dce_name].logs_ingestion_endpoint
        data_collection_rule_immutable_id = module.data_collection.data_collection_rule_immutable_ids[local.dcr_name]
        stream_name                       = local.stream
      }

      auth = {
        type           = "OAuth2"
        grant_type     = "client_credentials"
        client_id      = "00000000-0000-0000-0000-000000000000"
        client_secret  = "example-secret-supply-from-key-vault"
        token_endpoint = "https://login.microsoftonline.com/common/oauth2/v2.0/token"
        scope          = "https://graph.microsoft.com/.default"
      }

      http_method               = "Get"
      query_window_in_min       = 15
      query_time_format         = "yyyy-MM-ddTHH:mm:ssZ"
      start_time_attribute_name = "startDateTime"
      end_time_attribute_name   = "endDateTime"
      rate_limit_qps            = 10
      retry_count               = 4
      timeout_in_seconds        = 60
      headers                   = { Accept = "application/json" }

      response = {
        format                   = "json"
        events_json_paths        = ["$.value"]
        success_status_json_path = "$.status"
        success_status_value     = "ok"
      }

      paging = {
        pagingType            = "NextPageUrl"
        nextPageTokenJsonPath = "$.\"@odata.nextLink\""
        hasNextFlagJsonPath   = "$.\"@odata.nextLink\""
      }
    }

    # API-key poll of a second source into the same table.
    "vendor-events" = {
      api_endpoint = "https://api.example-vendor.com/v2/events"

      dcr = {
        data_collection_endpoint          = module.data_collection.data_collection_endpoints[local.dce_name].logs_ingestion_endpoint
        data_collection_rule_immutable_id = module.data_collection.data_collection_rule_immutable_ids[local.dcr_name]
        stream_name                       = local.stream
      }

      auth = {
        type               = "APIKey"
        api_key            = "example-key-supply-from-key-vault"
        api_key_name       = "X-Api-Key"
        api_key_identifier = "Bearer"
      }

      data_type   = "VendorEvents"
      http_method = "Get"

      # The response and paging attributes are set here too so both connection objects present the
      # same attribute shape: Terraform converts a heterogeneous object map to map(object(...)) only
      # when every element carries the same optional attributes.
      response = {
        format            = "json"
        events_json_paths = ["$.events"]
      }
      paging = null
    }
  }
}
