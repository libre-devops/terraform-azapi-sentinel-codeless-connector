# Complete call: the maximum applyable surface. Two poller connections on one connector (both
# API-key pollers of the public GitHub advisories feed, one paged via the Link header, one filtered
# by a query parameter), a fully overridden UI page (custom graph and sample queries, an instruction
# step, custom prerequisite permissions, preview flag), and the whole supporting stack composed so it
# is runnable. Applied then destroyed in one CI run. OAuth2 and other credentialed auth types are
# modelled and documented in variables.tf but are not shown live here: Sentinel connectivity-checks a
# connection on create (it really calls the endpoint and acquires the token), so a public runnable
# example cannot use them without real credentials.
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
    description = "Demonstrates multiple API-key pollers landing on one Sentinel connector."
    graph_table = local.table
    is_preview  = true

    graph_queries = [
      { metricName = "Events received", legend = local.table, baseQuery = "{{graphQueriesTableName}}" },
    ]
    sample_queries = [
      { description = "Recent events", query = "{{graphQueriesTableName}}\n| sort by TimeGenerated desc\n| take 20" },
    ]

    custom_permissions = [
      { name = "API credentials", description = "For a private source, an API key or token for the endpoint is required." },
    ]

    # An overridden instruction step (title + description, the shape the connectorUiConfig accepts).
    # A widget-bearing step such as an OAuthForm would only make sense with an OAuth2 connection.
    instruction_steps = [
      {
        title       = "Connect the source"
        description = "The public advisories feed needs no credential beyond a User-Agent. For a private source, supply its API key in the connection's request headers."
      },
    ]
  }

  # Two connections on one definition, exercising the connection surface (multiple pollers, query
  # parameters, response shaping, paging, rate limiting). IMPORTANT: Sentinel runs a LIVE
  # connectivity check when it creates a RestApiPoller connection, actually calling the endpoint (and
  # acquiring the token for OAuth2). So a runnable example must point at reachable endpoints with
  # working request settings; placeholder hosts or credentials fail the check. Both connections poll
  # the public GitHub advisories API (no credential beyond a User-Agent). OAuth2 and other
  # credentialed auth types are fully modelled and documented in variables.tf, but cannot be shown in
  # a public runnable example because the connectivity check would need real credentials.
  connections = {
    # A paged poll: GitHub paginates with the RFC 5988 Link header.
    "advisories-recent" = {
      api_endpoint = "https://api.github.com/advisories"

      dcr = {
        data_collection_endpoint          = module.data_collection.data_collection_endpoints[local.dce_name].logs_ingestion_endpoint
        data_collection_rule_immutable_id = module.data_collection.data_collection_rule_immutable_ids[local.dcr_name]
        stream_name                       = local.stream
      }

      auth = {
        type         = "APIKey"
        api_key      = "unused"
        api_key_name = "X-Poll-Client"
      }

      http_method         = "Get"
      query_window_in_min = 5
      rate_limit_qps      = 10
      timeout_in_seconds  = 60
      headers = {
        Accept       = "application/vnd.github+json"
        "User-Agent" = "libre-devops-sentinel-ccf"
      }

      response = {
        format            = "json"
        events_json_paths = ["$"]
      }
      paging = { pagingType = "LinkHeader" }
    }

    # A filtered poll of the same source into the same table, showing query parameters.
    "advisories-critical" = {
      api_endpoint = "https://api.github.com/advisories"

      dcr = {
        data_collection_endpoint          = module.data_collection.data_collection_endpoints[local.dce_name].logs_ingestion_endpoint
        data_collection_rule_immutable_id = module.data_collection.data_collection_rule_immutable_ids[local.dcr_name]
        stream_name                       = local.stream
      }

      auth = {
        type         = "APIKey"
        api_key      = "unused"
        api_key_name = "X-Poll-Client"
      }

      http_method      = "Get"
      query_parameters = { severity = "critical" }
      headers = {
        Accept       = "application/vnd.github+json"
        "User-Agent" = "libre-devops-sentinel-ccf"
      }

      # response present on both so the map unifies (response and paging are the object-typed
      # optionals that must be consistently shaped across elements).
      response = {
        format            = "json"
        events_json_paths = ["$"]
      }
      paging = null
    }
  }
}
