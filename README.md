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

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0, < 2.0.0 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | >= 2.0.0, < 3.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | >= 2.0.0, < 3.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azapi_resource.connections](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.definition](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_connections"></a> [connections](#input\_connections) | The poller connections (RestApiPoller dataConnectors) keyed by connection name, all linked to this<br/>module's definition. One definition can carry several connections that poll different endpoints. Per<br/>connection:<br/><br/>- api\_endpoint (required): the source REST URL to poll.<br/>- dcr (required): where polled events land, an object of:<br/>    - data\_collection\_endpoint (required): the DCE ingestion URL.<br/>    - data\_collection\_rule\_immutable\_id (required): the DCR immutable id.<br/>    - stream\_name (required): the DCR stream, must begin Custom-.<br/>  Compose these from the Libre DevOps data-collection module by id (pass-ids).<br/>- auth (required): the authentication object, exactly one type populated:<br/>    - type (required): Basic \| APIKey \| OAuth2 \| JwtToken.<br/>    - the fields for that type (user\_name/password; api\_key/api\_key\_name/api\_key\_identifier/<br/>      is\_api\_key\_in\_post\_payload; client\_id/client\_secret/grant\_type/token\_endpoint/scope/<br/>      authorization\_endpoint/redirect\_uri; jwt user\_name/password/token\_endpoint/<br/>      jwt\_token\_json\_path/...). Prefer feeding secrets from a Key Vault data source or a variable,<br/>      never a literal.<br/>- data\_type (optional): the connector's dataType label.<br/>- http\_method (optional): GET (default) or POST.<br/>- query\_window\_in\_min (optional): poll window minutes (min 1, default 5).<br/>- query\_time\_format (optional): the endpoint's time format (default ISO 8601 UTC).<br/>- start\_time\_attribute\_name / end\_time\_attribute\_name (optional, paired): the query parameter<br/>  names for the poll window bounds.<br/>- headers / query\_parameters (optional): request header and query maps.<br/>- rate\_limit\_qps / retry\_count (1..6) / timeout\_in\_seconds (1..180) (optional): throttling and<br/>  resilience.<br/>- response (optional): { events\_json\_paths (list, default ["$"]), format (json\|csv\|xml, default<br/>  json), success\_status\_json\_path, success\_status\_value, is\_gzip\_compressed }.<br/>- paging (optional): raw paging object (pagingType plus its fields), passed through.<br/>- request\_extra / properties\_extra (optional): raw attributes merged over the generated request /<br/>  properties last, for fields this module does not model. | <pre>map(object({<br/>    api_endpoint = string<br/><br/>    dcr = object({<br/>      data_collection_endpoint          = string<br/>      data_collection_rule_immutable_id = string<br/>      stream_name                       = string<br/>    })<br/><br/>    auth = object({<br/>      type = string<br/><br/>      # Basic<br/>      user_name = optional(string)<br/>      password  = optional(string)<br/><br/>      # APIKey<br/>      api_key                    = optional(string)<br/>      api_key_name               = optional(string)<br/>      api_key_identifier         = optional(string)<br/>      is_api_key_in_post_payload = optional(bool)<br/><br/>      # OAuth2<br/>      client_id              = optional(string)<br/>      client_secret          = optional(string)<br/>      grant_type             = optional(string)<br/>      token_endpoint         = optional(string)<br/>      scope                  = optional(string)<br/>      authorization_endpoint = optional(string)<br/>      authorization_code     = optional(string)<br/>      redirect_uri           = optional(string)<br/><br/>      # JwtToken (user_name/password reused above; token_endpoint reused)<br/>      jwt_token_json_path       = optional(string)<br/>      is_credentials_in_headers = optional(bool)<br/>      is_json_request           = optional(bool)<br/><br/>      # Raw escape hatch merged over the generated auth object last.<br/>      extra = optional(any, {})<br/>    })<br/><br/>    data_type           = optional(string)<br/>    http_method         = optional(string, "Get")<br/>    query_window_in_min = optional(number)<br/>    query_time_format   = optional(string)<br/><br/>    start_time_attribute_name = optional(string)<br/>    end_time_attribute_name   = optional(string)<br/><br/>    headers          = optional(map(string))<br/>    query_parameters = optional(map(string))<br/><br/>    rate_limit_qps     = optional(number)<br/>    retry_count        = optional(number)<br/>    timeout_in_seconds = optional(number)<br/><br/>    response = optional(object({<br/>      events_json_paths        = optional(list(string), ["$"])<br/>      format                   = optional(string, "json")<br/>      success_status_json_path = optional(string)<br/>      success_status_value     = optional(string)<br/>      is_gzip_compressed       = optional(bool)<br/>    }), {})<br/><br/>    # The union of the paging surface across all pagingType values, every field optional. A typed<br/>    # object (rather than any) is required so connections with and without paging unify into the<br/>    # map; set pagingType plus the fields that type needs (see the README paging table).<br/>    paging = optional(object({<br/>      pagingType = string<br/><br/>      pageSize              = optional(number)<br/>      pageSizeParameterName = optional(string)<br/>      pagingInfoPlacement   = optional(string)<br/>      pagingQueryParamOnly  = optional(bool)<br/><br/>      # Link/URL based<br/>      linkHeaderTokenJsonPath            = optional(string)<br/>      nextPageUrl                        = optional(string)<br/>      nextPageParaName                   = optional(string)<br/>      nextPageRequestHeader              = optional(string)<br/>      nextPageUrlQueryParameters         = optional(map(string))<br/>      nextPageUrlQueryParametersTemplate = optional(string)<br/><br/>      # Token based<br/>      nextPageTokenJsonPath       = optional(string)<br/>      nextPageTokenResponseHeader = optional(string)<br/>      hasNextFlagJsonPath         = optional(string)<br/><br/>      # Offset / count based<br/>      offsetParaName       = optional(string)<br/>      pageNumberParaName   = optional(string)<br/>      zeroBasedIndexing    = optional(bool)<br/>      totalResultsJsonPath = optional(string)<br/>      pageNumberJsonPath   = optional(string)<br/>      pageCountJsonPath    = optional(string)<br/>    }))<br/><br/>    request_extra    = optional(map(string), {})<br/>    properties_extra = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_connector_api_version"></a> [connector\_api\_version](#input\_connector\_api\_version) | API version for Microsoft.SecurityInsights/dataConnectors. 2025-09-01 is the current stable version; variablised so consumers are never pinned to this module's release cadence. | `string` | `"2025-09-01"` | no |
| <a name="input_connector_ui"></a> [connector\_ui](#input\_connector\_ui) | The connector's UI page (connectorUiConfig on the Customizable dataConnectorDefinition). Only the<br/>human-facing text is required: title, publisher, and description; the rest of the page (the<br/>ingestion graph, sample queries, data types, connectivity check, and prerequisite permissions) is<br/>auto-derived from graph\_table so a minimal call gets a complete, correct page for free. Every<br/>derived section can be overridden for an ISV-grade page.<br/><br/>- title / publisher / description (required): the page heading, provider, and markdown blurb.<br/>- graph\_table (required): the destination custom table name (the poller's stream target, ending<br/>  \_CL). Drives the default graph query, sample query, data-type freshness query, and the<br/>  {{graphQueriesTableName}} placeholder.<br/>- id (optional): internal connector id; defaults to definition\_name.<br/>- logo (optional): path to an SVG logo; the platform default is used when null.<br/>- is\_preview (optional): mark the connector preview in the gallery.<br/>- graph\_queries / sample\_queries / data\_types (optional): override the auto-derived query sets<br/>  (each a list of the documented shapes); null keeps the derived defaults.<br/>- connectivity\_criteria (optional): override the connectivity check; defaults to HasDataConnectors<br/>  (the recommended check for API pollers, connected once a connection is active).<br/>- resource\_provider\_permissions (optional): override the prerequisite permission rows; defaults to<br/>  read+write on the workspace.<br/>- custom\_permissions (optional): extra prerequisite notes (name/description), for example the<br/>  source API credential the analyst must supply.<br/>- instruction\_steps (optional): the Instructions tab widgets (raw, passed through); defaults to a<br/>  single explanatory step. Build credential inputs here (Textbox, OAuthForm, ...).<br/>- extra\_ui (optional): raw connectorUiConfig attributes merged over the generated config last, for<br/>  fields this module does not model. | <pre>object({<br/>    title       = string<br/>    publisher   = string<br/>    description = string<br/>    graph_table = string<br/><br/>    id         = optional(string)<br/>    logo       = optional(string)<br/>    is_preview = optional(bool, false)<br/><br/>    graph_queries         = optional(list(any))<br/>    sample_queries        = optional(list(any))<br/>    data_types            = optional(list(any))<br/>    connectivity_criteria = optional(list(any))<br/><br/>    resource_provider_permissions = optional(list(any))<br/>    custom_permissions            = optional(list(object({ name = string, description = string })))<br/>    instruction_steps             = optional(list(any))<br/>    extra_ui                      = optional(any, {})<br/>  })</pre> | n/a | yes |
| <a name="input_definition_api_version"></a> [definition\_api\_version](#input\_definition\_api\_version) | API version for Microsoft.SecurityInsights/dataConnectorDefinitions. 2025-09-01 is the current stable version; variablised so consumers are never pinned to this module's release cadence. | `string` | `"2025-09-01"` | no |
| <a name="input_definition_name"></a> [definition\_name](#input\_definition\_name) | Name of the dataConnectorDefinition resource (the connector's page in Sentinel). Also the connectorDefinitionName every poller connection links to. | `string` | n/a | yes |
| <a name="input_retry_error_message_regex"></a> [retry\_error\_message\_regex](#input\_retry\_error\_message\_regex) | Regular expressions azapi retries on when a connector call fails. Defaults to the freshly created workspace propagation race and transient service noise; null disables retries. | `list(string)` | <pre>[<br/>  "(?i)workspace could not be found",<br/>  "(?i)not found",<br/>  "(?i)too many requests",<br/>  "(?i)service unavailable",<br/>  "(?i)internal server error"<br/>]</pre> | no |
| <a name="input_workspace_id"></a> [workspace\_id](#input\_workspace\_id) | Resource id of the Sentinel-onboarded Log Analytics workspace the connector definition and its poller connections are created under (the azapi parent), per the pass-ids principle. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_connection_ids"></a> [connection\_ids](#output\_connection\_ids) | Map of connection name to its RestApiPoller data connector resource id. |
| <a name="output_connection_ids_zipmap"></a> [connection\_ids\_zipmap](#output\_connection\_ids\_zipmap) | Map of connection name to {name, id} for easy composition. |
| <a name="output_definition_id"></a> [definition\_id](#output\_definition\_id) | Resource id of the data connector definition (the connector's page in Sentinel). |
| <a name="output_definition_name"></a> [definition\_name](#output\_definition\_name) | Name of the data connector definition, the connectorDefinitionName every connection links to. |
| <a name="output_graph_table"></a> [graph\_table](#output\_graph\_table) | The destination custom table the connector's UI and its connections target. |
<!-- END_TF_DOCS -->
