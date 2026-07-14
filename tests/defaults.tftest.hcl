# Plan-time tests with a mocked azapi provider: no cloud, no credentials. They pin the derived UI
# page, the auth/request/response normalisation (typed snake_case in, Graph PascalCase out), the
# null-dropping, and every input validation.

mock_provider "azapi" {}

variables {
  workspace_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.OperationalInsights/workspaces/log-t"
  definition_name = "ldo-example-connector"
  connector_ui = {
    title       = "Example Connector"
    publisher   = "Libre DevOps"
    description = "Polls the example API."
    graph_table = "ExampleLogs_CL"
  }
}

run "derives_the_ui_page_from_the_table" {
  command = plan

  assert {
    condition     = azapi_resource.definition.body.kind == "Customizable"
    error_message = "The definition is a Customizable data connector definition."
  }

  assert {
    condition     = azapi_resource.definition.body.properties.connectorUiConfig.graphQueriesTableName == "ExampleLogs_CL"
    error_message = "The table name drives the graph queries table name."
  }

  assert {
    condition     = azapi_resource.definition.body.properties.connectorUiConfig.connectivityCriteria[0].type == "HasDataConnectors"
    error_message = "The default connectivity check is HasDataConnectors, recommended for pollers."
  }

  assert {
    condition     = azapi_resource.definition.body.properties.connectorUiConfig.permissions.resourceProvider[0].requiredPermissions.write == true
    error_message = "The default permissions require workspace write."
  }

  assert {
    condition     = azapi_resource.definition.body.properties.connectorUiConfig.availability.status == 1
    error_message = "Availability defaults to Available (1)."
  }

  assert {
    condition     = azapi_resource.definition.body.properties.connectorUiConfig.id == "ldo-example-connector"
    error_message = "The connector id defaults to the definition name."
  }
}

run "builds_a_restapipoller_connection" {
  command = plan

  variables {
    connections = {
      "example-logs" = {
        api_endpoint = "https://api.example.com/events"
        dcr = {
          data_collection_endpoint          = "https://dce.example.ingest.monitor.azure.com"
          data_collection_rule_immutable_id = "dcr-0123456789abcdef0123456789abcdef"
          stream_name                       = "Custom-ExampleLogs"
        }
        auth = {
          type    = "APIKey"
          api_key = "secret"
        }
        http_method               = "Get"
        query_window_in_min       = 10
        start_time_attribute_name = "from"
        end_time_attribute_name   = "to"
        headers                   = { Accept = "application/json" }
        retry_count               = 3
        response = {
          format            = "json"
          events_json_paths = ["$.value"]
        }
        paging = { pagingType = "LinkHeader", linkHeaderTokenJsonPath = "$.next" }
      }
    }
  }

  assert {
    condition     = azapi_resource.connections["example-logs"].body.kind == "RestApiPoller"
    error_message = "The connection is a RestApiPoller."
  }

  assert {
    condition     = azapi_resource.connections["example-logs"].body.properties.connectorDefinitionName == "ldo-example-connector"
    error_message = "The connection links to this module's definition by name."
  }

  assert {
    condition     = azapi_resource.connections["example-logs"].body.properties.dcrConfig.streamName == "Custom-ExampleLogs"
    error_message = "The DCR stream is carried into dcrConfig."
  }

  assert {
    condition     = azapi_resource.connections["example-logs"].body.properties.auth.type == "APIKey" && azapi_resource.connections["example-logs"].body.properties.auth.ApiKey == "secret"
    error_message = "Auth normalises to the Graph PascalCase shape."
  }

  assert {
    condition     = azapi_resource.connections["example-logs"].body.properties.request.apiEndpoint == "https://api.example.com/events" && azapi_resource.connections["example-logs"].body.properties.request.queryWindowInMin == 10
    error_message = "Request fields normalise to the Graph camelCase shape."
  }

  assert {
    condition     = azapi_resource.connections["example-logs"].body.properties.request.startTimeAttributeName == "from"
    error_message = "The paired time-window attributes are carried through."
  }

  assert {
    condition     = azapi_resource.connections["example-logs"].body.properties.response.eventsJsonPaths[0] == "$.value"
    error_message = "Response fields normalise and the events path is carried."
  }

  assert {
    condition     = azapi_resource.connections["example-logs"].body.properties.paging.pagingType == "LinkHeader"
    error_message = "Paging passes through raw."
  }

  assert {
    condition     = !contains(keys(azapi_resource.connections["example-logs"].body.properties.request), "rateLimitQPS")
    error_message = "Unset optionals are dropped from the request, never sent null."
  }

  assert {
    condition     = !contains(keys(azapi_resource.connections["example-logs"].body.properties), "dataType")
    error_message = "An unset data_type is omitted, not sent as null."
  }
}

run "stream_prefix_enforced" {
  command = plan

  variables {
    connections = {
      "bad" = {
        api_endpoint = "https://api.example.com"
        dcr          = { data_collection_endpoint = "https://x", data_collection_rule_immutable_id = "dcr-1", stream_name = "ExampleLogs" }
        auth         = { type = "Basic", user_name = "u", password = "p" }
      }
    }
  }

  expect_failures = [var.connections]
}

run "auth_type_enum_enforced" {
  command = plan

  variables {
    connections = {
      "bad" = {
        api_endpoint = "https://api.example.com"
        dcr          = { data_collection_endpoint = "https://x", data_collection_rule_immutable_id = "dcr-1", stream_name = "Custom-X" }
        auth         = { type = "Kerberos" }
      }
    }
  }

  expect_failures = [var.connections]
}

run "paired_time_attributes_enforced" {
  command = plan

  variables {
    connections = {
      "bad" = {
        api_endpoint              = "https://api.example.com"
        dcr                       = { data_collection_endpoint = "https://x", data_collection_rule_immutable_id = "dcr-1", stream_name = "Custom-X" }
        auth                      = { type = "Basic", user_name = "u", password = "p" }
        start_time_attribute_name = "from"
      }
    }
  }

  expect_failures = [var.connections]
}

run "graph_table_suffix_enforced" {
  command = plan

  variables {
    connector_ui = {
      title       = "X"
      publisher   = "Y"
      description = "Z"
      graph_table = "NotCustom"
    }
  }

  expect_failures = [var.connector_ui]
}

run "workspace_id_must_be_a_workspace" {
  command = plan

  variables {
    workspace_id = "/subscriptions/0/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/x"
  }

  expect_failures = [var.workspace_id]
}

run "oauth_ui_advisory_warns" {
  command = plan

  variables {
    connector_ui = {
      title             = "OAuth Connector"
      publisher         = "Libre DevOps"
      description       = "Polls with OAuth."
      graph_table       = "OAuthLogs_CL"
      instruction_steps = [{ title = "Connect", instructions = [{ type = "OAuthForm", parameters = {} }] }]
    }
    connections = {
      "basic-conn" = {
        api_endpoint = "https://api.example.com"
        dcr          = { data_collection_endpoint = "https://x", data_collection_rule_immutable_id = "dcr-1", stream_name = "Custom-X" }
        auth         = { type = "Basic", user_name = "u", password = "p" }
      }
    }
  }

  expect_failures = [check.oauth_ui_matches_auth]
}
