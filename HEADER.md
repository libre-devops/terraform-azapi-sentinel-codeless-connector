<!--
  Keep the title and badges OUTSIDE the centered <div>: the Terraform Registry's markdown renderer
  does not parse markdown inside an HTML block, so a # heading or [![badge]] in the div renders as
  literal text on the registry. Only the logo (HTML) goes in the div.
-->
<div align="center">
  <a href="https://libredevops.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://libredevops.org/assets/libre-devops-white.png">
      <img alt="Libre DevOps" src="https://libredevops.org/assets/libre-devops-black.png" width="300">
    </picture>
  </a>
</div>

# Terraform AzAPI Sentinel Codeless Connector

Microsoft Sentinel **Codeless Connector Framework (CCF)** connectors as code, via the
[Azure/azapi](https://registry.terraform.io/providers/Azure/azapi/latest) provider. A CCF connector
is Sentinel's managed poller-as-a-service: it polls any REST API on a schedule (no Azure Function to
run or maintain) and lands the results in a Log Analytics table through a data collection rule. This
module builds both halves, the connector's page in Sentinel and its poller connections, from a small
typed surface.

[![CI](https://github.com/libre-devops/terraform-azapi-sentinel-codeless-connector/actions/workflows/ci.yml/badge.svg)](https://github.com/libre-devops/terraform-azapi-sentinel-codeless-connector/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/libre-devops/terraform-azapi-sentinel-codeless-connector?sort=semver&label=release)](https://github.com/libre-devops/terraform-azapi-sentinel-codeless-connector/releases/latest)
[![Terraform Registry](https://img.shields.io/badge/registry-libre--devops-7B42BC?logo=terraform&logoColor=white)](https://registry.terraform.io/namespaces/libre-devops)
[![License](https://img.shields.io/github/license/libre-devops/terraform-azapi-sentinel-codeless-connector)](./LICENSE)

---

## The two halves, one small surface

- **The connector page** (`dataConnectorDefinition`, kind `Customizable`): only `title`, `publisher`,
  `description` and `graph_table` are required. The rest of the page (the ingestion graph, sample
  query, data-type freshness query, the `HasDataConnectors` connectivity check, and the workspace
  prerequisite permissions) is **auto-derived from the table name**, so a minimal call gets a
  complete, correct page for free. Every derived section is overridable for an ISV-grade page, and
  the Instructions tab widgets (Textbox, OAuthForm, CopyableLabel, ...) pass through raw.
- **The poller connections** (`RestApiPoller` `dataConnectors`), a map keyed by connection name, all
  linked to the definition. Each has a typed `auth` (Basic, APIKey, OAuth2, or JwtToken), request
  surface (endpoint, poll window, the paired time-window attributes, rate limits, retries), response
  parsing (JSON, CSV, XML), and typed `paging` covering all seven CCF paging types. The DCR
  coordinates (`dcr` block) compose straight from the Libre DevOps
  [data-collection](https://registry.terraform.io/modules/libre-devops/data-collection/azurerm/latest)
  module by id, per the estate's pass-ids principle.

## What the module enforces

At plan: the auth type enum, the `Custom-` DCR stream prefix, the paired start/end time-window
attributes, the retry (1 to 6) and timeout (1 to 180) ranges, the response format enum, and the
`_CL` table suffix. Unset optionals are dropped from every body rather than sent as null. An
advisory check warns when the UI offers an OAuthForm but no connection actually uses OAuth2 (a
common copy-paste mismatch). Both API versions are variables, so consumers are never pinned to this
module's release cadence.

## Notes worth knowing

- The azapi embedded schema lags the CCF surface, so `schema_validation_enabled = false` is set on
  both resources: the service validates the whole body on the PUT, which is the real authority.
- Escaping: the Microsoft docs show auth parameters written as `[[parameters('x')]`. That is an ARM
  *deployment template* artefact; through azapi you feed plain Terraform values (a variable, or a
  Key Vault data source), never that form.
- Secrets: pass `client_secret`, `api_key` and passwords from a variable or a `azurerm_key_vault_secret`
  data source. They land in the request body, so treat them as sensitive.
