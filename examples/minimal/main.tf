# Minimal call: one codeless connector polling a public REST API (the GitHub security advisories
# endpoint, which needs no credential) into a custom table. It composes the whole supporting stack
# so it is genuinely runnable: a Sentinel-onboarded workspace with the destination custom table, a
# DCE and DCR (with a matching stream declaration) from the data-collection module, then the
# connector itself. Applied then destroyed in one CI run.
locals {
  location = lookup(var.regions, var.loc, "uksouth")
  rg_name  = "rg-${var.short}-${var.loc}-${terraform.workspace}-001"
  law_name = "log-${var.short}-${var.loc}-${terraform.workspace}-001"
  dce_name = "dce-${var.short}-${var.loc}-${terraform.workspace}-001"
  dcr_name = "dcr-${var.short}-${var.loc}-${terraform.workspace}-001"

  table  = "GitHubAdvisories_CL"
  stream = "Custom-GitHubAdvisories"
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

# A Sentinel-onboarded workspace with the destination custom table (its columns are the connector's
# output shape).
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
            { name = "GhsaId", type = "string" },
            { name = "Summary", type = "string" },
            { name = "Severity", type = "string" },
          ]
        }
      ]
    }
  }
}

# The DCE and DCR the poller ingests through. The DCR declares the Custom- stream the connector
# targets and flows it to the custom table.
module "data_collection" {
  source  = "libre-devops/data-collection/azurerm"
  version = "~> 4.0"

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
            { name = "GhsaId", type = "string" },
            { name = "Summary", type = "string" },
            { name = "Severity", type = "string" },
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
      }]
    }
  }
}

module "codeless_connector" {
  source = "../../"

  workspace_id    = module.law.workspace_ids[local.law_name]
  definition_name = "ldo-github-advisories"

  connector_ui = {
    title       = "GitHub Security Advisories"
    publisher   = "Libre DevOps"
    description = "Polls the public GitHub security advisories API into Microsoft Sentinel."
    graph_table = local.table
  }

  connections = {
    "github-advisories" = {
      api_endpoint = "https://api.github.com/advisories"

      dcr = {
        data_collection_endpoint          = module.data_collection.data_collection_endpoints[local.dce_name].logs_ingestion_endpoint
        data_collection_rule_immutable_id = module.data_collection.data_collection_rule_immutable_ids[local.dcr_name]
        stream_name                       = local.stream
      }

      # The public advisories endpoint needs no key; APIKey with an empty header keeps the request
      # unauthenticated while satisfying the auth contract.
      auth = {
        type         = "APIKey"
        api_key      = "unused"
        api_key_name = ""
      }

      http_method = "Get"
      headers     = { Accept = "application/vnd.github+json" }

      response = {
        format            = "json"
        events_json_paths = ["$"]
      }
    }
  }
}
