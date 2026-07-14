variable "connections" {
  description = <<DESC
The poller connections (RestApiPoller dataConnectors) keyed by connection name, all linked to this
module's definition. One definition can carry several connections that poll different endpoints.

IMPORTANT: Sentinel runs a LIVE connectivity check when it creates a connection, actually calling the
api_endpoint (and, for OAuth2, acquiring a token from token_endpoint) before the resource is
accepted. A connection therefore needs a reachable endpoint and working credentials to apply;
placeholder hosts or fake credentials fail create with a 400 "Connectivity check failed". The bounded
create timeout (see resource_timeouts) keeps that failure fast rather than a long hang.

Per connection:

- api_endpoint (required): the source REST URL to poll.
- dcr (required): where polled events land, an object of:
    - data_collection_endpoint (required): the DCE ingestion URL.
    - data_collection_rule_immutable_id (required): the DCR immutable id.
    - stream_name (required): the DCR stream, must begin Custom-.
  Compose these from the Libre DevOps data-collection module by id (pass-ids).
- auth (required): the authentication object, exactly one type populated:
    - type (required): Basic | APIKey | OAuth2 | JwtToken.
    - the fields for that type (user_name/password; api_key/api_key_name/api_key_identifier/
      is_api_key_in_post_payload; client_id/client_secret/grant_type/token_endpoint/scope/
      authorization_endpoint/redirect_uri; jwt user_name/password/token_endpoint/
      jwt_token_json_path/...). Prefer feeding secrets from a Key Vault data source or a variable,
      never a literal.
- data_type (optional): the connector's dataType label.
- http_method (optional): GET (default) or POST.
- query_window_in_min (optional): poll window minutes (min 1, default 5).
- query_time_format (optional): the endpoint's time format (default ISO 8601 UTC).
- start_time_attribute_name / end_time_attribute_name (optional, paired): the query parameter
  names for the poll window bounds.
- headers / query_parameters (optional): request header and query maps.
- rate_limit_qps / retry_count (1..6) / timeout_in_seconds (1..180) (optional): throttling and
  resilience.
- response (optional): { events_json_paths (list, default ["$"]), format (json|csv|xml, default
  json), success_status_json_path, success_status_value, is_gzip_compressed }.
- paging (optional): raw paging object (pagingType plus its fields), passed through.
- request_extra / properties_extra (optional): raw attributes merged over the generated request /
  properties last, for fields this module does not model.
DESC

  type = map(object({
    api_endpoint = string

    dcr = object({
      data_collection_endpoint          = string
      data_collection_rule_immutable_id = string
      stream_name                       = string
    })

    auth = object({
      type = string

      # Basic
      user_name = optional(string)
      password  = optional(string)

      # APIKey
      api_key                    = optional(string)
      api_key_name               = optional(string)
      api_key_identifier         = optional(string)
      is_api_key_in_post_payload = optional(bool)

      # OAuth2
      client_id              = optional(string)
      client_secret          = optional(string)
      grant_type             = optional(string)
      token_endpoint         = optional(string)
      scope                  = optional(string)
      authorization_endpoint = optional(string)
      authorization_code     = optional(string)
      redirect_uri           = optional(string)

      # JwtToken (user_name/password reused above; token_endpoint reused)
      jwt_token_json_path       = optional(string)
      is_credentials_in_headers = optional(bool)
      is_json_request           = optional(bool)

      # Raw escape hatch merged over the generated auth object last.
      extra = optional(any, {})
    })

    data_type           = optional(string)
    http_method         = optional(string, "Get")
    query_window_in_min = optional(number)
    query_time_format   = optional(string)

    start_time_attribute_name = optional(string)
    end_time_attribute_name   = optional(string)

    headers          = optional(map(string))
    query_parameters = optional(map(string))

    rate_limit_qps     = optional(number)
    retry_count        = optional(number)
    timeout_in_seconds = optional(number)

    response = optional(object({
      events_json_paths        = optional(list(string), ["$"])
      format                   = optional(string, "json")
      success_status_json_path = optional(string)
      success_status_value     = optional(string)
      is_gzip_compressed       = optional(bool)
    }), {})

    # The union of the paging surface across all pagingType values, every field optional. A typed
    # object (rather than any) is required so connections with and without paging unify into the
    # map; set pagingType plus the fields that type needs (see the README paging table).
    paging = optional(object({
      pagingType = string

      pageSize              = optional(number)
      pageSizeParameterName = optional(string)
      pagingInfoPlacement   = optional(string)
      pagingQueryParamOnly  = optional(bool)

      # Link/URL based
      linkHeaderTokenJsonPath            = optional(string)
      nextPageUrl                        = optional(string)
      nextPageParaName                   = optional(string)
      nextPageRequestHeader              = optional(string)
      nextPageUrlQueryParameters         = optional(map(string))
      nextPageUrlQueryParametersTemplate = optional(string)

      # Token based
      nextPageTokenJsonPath       = optional(string)
      nextPageTokenResponseHeader = optional(string)
      hasNextFlagJsonPath         = optional(string)

      # Offset / count based
      offsetParaName       = optional(string)
      pageNumberParaName   = optional(string)
      zeroBasedIndexing    = optional(bool)
      totalResultsJsonPath = optional(string)
      pageNumberJsonPath   = optional(string)
      pageCountJsonPath    = optional(string)
    }))

    request_extra    = optional(map(string), {})
    properties_extra = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for c in values(var.connections) : contains(["Basic", "APIKey", "OAuth2", "JwtToken"], c.auth.type)])
    error_message = "each connection's auth.type must be Basic, APIKey, OAuth2, or JwtToken."
  }

  validation {
    condition     = alltrue([for c in values(var.connections) : startswith(c.dcr.stream_name, "Custom-")])
    error_message = "each connection's dcr.stream_name must begin with Custom-."
  }

  validation {
    condition     = alltrue([for c in values(var.connections) : contains(["Get", "Post", "GET", "POST"], c.http_method)])
    error_message = "http_method must be Get or Post."
  }

  validation {
    condition     = alltrue([for c in values(var.connections) : (c.start_time_attribute_name == null) == (c.end_time_attribute_name == null)])
    error_message = "start_time_attribute_name and end_time_attribute_name must be set together (the API pairs them)."
  }

  validation {
    condition     = alltrue([for c in values(var.connections) : c.retry_count == null || try(c.retry_count >= 1 && c.retry_count <= 6, false)])
    error_message = "retry_count must be between 1 and 6."
  }

  validation {
    condition     = alltrue([for c in values(var.connections) : c.timeout_in_seconds == null || try(c.timeout_in_seconds >= 1 && c.timeout_in_seconds <= 180, false)])
    error_message = "timeout_in_seconds must be between 1 and 180."
  }

  validation {
    condition     = alltrue([for c in values(var.connections) : contains(["json", "csv", "xml"], c.response.format)])
    error_message = "response.format must be json, csv, or xml."
  }
}

variable "connector_api_version" {
  description = "API version for Microsoft.SecurityInsights/dataConnectors. 2025-09-01 is the current stable version; variablised so consumers are never pinned to this module's release cadence."
  type        = string
  default     = "2025-09-01"
}

variable "connector_ui" {
  description = <<DESC
The connector's UI page (connectorUiConfig on the Customizable dataConnectorDefinition). Only the
human-facing text is required: title, publisher, and description; the rest of the page (the
ingestion graph, sample queries, data types, connectivity check, and prerequisite permissions) is
auto-derived from graph_table so a minimal call gets a complete, correct page for free. Every
derived section can be overridden for an ISV-grade page.

- title / publisher / description (required): the page heading, provider, and markdown blurb.
- graph_table (required): the destination custom table name (the poller's stream target, ending
  _CL). Drives the default graph query, sample query, data-type freshness query, and the
  {{graphQueriesTableName}} placeholder.
- id (optional): internal connector id; defaults to definition_name.
- logo (optional): path to an SVG logo; the platform default is used when null.
- is_preview (optional): mark the connector preview in the gallery.
- graph_queries / sample_queries / data_types (optional): override the auto-derived query sets
  (each a list of the documented shapes); null keeps the derived defaults.
- connectivity_criteria (optional): override the connectivity check; defaults to HasDataConnectors
  (the recommended check for API pollers, connected once a connection is active).
- resource_provider_permissions (optional): override the prerequisite permission rows; defaults to
  read+write on the workspace.
- custom_permissions (optional): extra prerequisite notes (name/description), for example the
  source API credential the analyst must supply.
- instruction_steps (optional): the Instructions tab widgets (raw, passed through); defaults to a
  single explanatory step. Build credential inputs here (Textbox, OAuthForm, ...).
- extra_ui (optional): raw connectorUiConfig attributes merged over the generated config last, for
  fields this module does not model.
DESC

  type = object({
    title       = string
    publisher   = string
    description = string
    graph_table = string

    id         = optional(string)
    logo       = optional(string)
    is_preview = optional(bool, false)

    graph_queries         = optional(list(any))
    sample_queries        = optional(list(any))
    data_types            = optional(list(any))
    connectivity_criteria = optional(list(any))

    resource_provider_permissions = optional(list(any))
    custom_permissions            = optional(list(object({ name = string, description = string })))
    instruction_steps             = optional(list(any))
    extra_ui                      = optional(any, {})
  })

  validation {
    condition     = endswith(var.connector_ui.graph_table, "_CL")
    error_message = "connector_ui.graph_table must be a custom log table name ending _CL."
  }

  validation {
    condition     = trimspace(var.connector_ui.title) != "" && trimspace(var.connector_ui.publisher) != ""
    error_message = "connector_ui.title and connector_ui.publisher must be non-empty."
  }
}

variable "definition_api_version" {
  description = "API version for Microsoft.SecurityInsights/dataConnectorDefinitions. 2025-09-01 is the current stable version; variablised so consumers are never pinned to this module's release cadence."
  type        = string
  default     = "2025-09-01"
}

variable "definition_name" {
  description = "Name of the dataConnectorDefinition resource (the connector's page in Sentinel). Also the connectorDefinitionName every poller connection links to."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,88}$", var.definition_name))
    error_message = "definition_name must start with a letter or digit and use letters, digits, dots, underscores, or hyphens."
  }
}

variable "resource_timeouts" {
  description = <<DESC
azapi operation timeouts for the definition and connection resources. The create timeout is
deliberately bounded (default 15m, below the azapi provider default of 30m): a misconfigured
connector otherwise leaves azapi polling a stuck Sentinel provisioning operation for the full
default, masking the real error behind a long hang. A shorter create makes CI fail fast and surface
the underlying error. Delete stays generous because tearing a connector down can be slow.
DESC
  type = object({
    create = optional(string, "15m")
    read   = optional(string, "5m")
    update = optional(string, "15m")
    delete = optional(string, "30m")
  })
  default = {}
}

variable "retry_error_message_regex" {
  description = <<DESC
Regular expressions azapi retries on when a connector call fails. The default covers only the
genuinely transient races: the Sentinel onboarding propagation race (a workspace onboarded in the
same apply can still report "not onboarded to Microsoft Sentinel" for a short while when the
connector reads it), the freshly created workspace race, and throttling. It deliberately does NOT
retry generic "not found" or 5xx errors, because for a connector those are usually persistent
configuration faults that should fail fast (with the bounded create timeout) rather than be retried
for the whole timeout window. Add patterns here if your endpoint needs them. Set null to disable
retries.
DESC
  type        = list(string)
  default     = ["(?i)not onboarded to Microsoft Sentinel", "(?i)workspace could not be found", "(?i)too many requests"]
}

variable "workspace_id" {
  description = "Resource id of the Sentinel-onboarded Log Analytics workspace the connector definition and its poller connections are created under (the azapi parent), per the pass-ids principle."
  type        = string

  validation {
    condition     = can(regex("(?i)/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+$", var.workspace_id))
    error_message = "workspace_id must be a Log Analytics workspace resource id."
  }
}
