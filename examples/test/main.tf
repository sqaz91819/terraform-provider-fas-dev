# Local dev testing configuration for the FortiAppSecCloud Terraform provider
#
# All tunable values are defined up here so you can edit them in one place,
# without interactive variable prompts. Change these, then `terraform plan`.
#
# IMPORTANT: Set your API token before running (never in this file):
#   export FORTIAPPSECCLOUD_API_TOKEN="<your-dev-token>"

# =============================================================================
# EDIT THESE VALUES
# =============================================================================

locals {
  # API hostname. Defaults to dev1 for local testing.
  hostname = "https://api.dev1.fortiappsec.com"

  # Unique, disposable application name. Must not already exist in the target.
  app_name = "yuchen_test_dev1"

  # Protected domain that you can verify/own in the target account.
  domain_name = "developers.cloudflare.com"

  # Origin server address (IPv4 literal or domain) reachable from FortiAppSecCloud.
  origin_address = "1.1.1.1"

  # Platform where the app is hosted. One of: AWS, Azure, GCP, OCI, C8T.
  # NOTE: the AWS/us-east-1 pair may not be enabled for every account.
  platform = "AWS"
  region   = "us-west-2"

  # Dummy signing secret used only by the disposable mobile API protection test.
  mobile_api_token_secret = "terraform-matrix-dummy-signing-secret"
}

# =============================================================================
# PROVIDER
# =============================================================================

terraform {
  required_providers {
    fortiappseccloud = {
      source  = "sqaz91819/fas-dev"
      version = "2.0.0-rc.3"
    }
  }
  # Do NOT lock provider version when using dev_overrides - the local build is used.
}

provider "fortiappseccloud" {
  hostname = local.hostname
  # Authentication is via FORTIAPPSECCLOUD_API_TOKEN environment variable.
  # Alternatively, use username + password, or api_token in this block (not recommended).
}

# =============================================================================
# RESOURCES
# =============================================================================

resource "fortiappseccloud_waf_app" "test" {
  app_name         = local.app_name
  domain_name      = local.domain_name
  services         = ["http", "https"]
  http_port        = 80
  https_port       = 443
  platform         = local.platform
  region           = local.region
  cdn              = false
  block_mode       = false
  certificate_mode = "automatic"

  initial_origin {
    address  = local.origin_address
    protocol = "https"
    port     = 443
  }
}

# =============================================================================
# WAF MODULES
# =============================================================================

# Module: Account Takeover Protection
resource "fortiappseccloud_waf_account_takeover" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status                = true
    action                = "alert_deny"
    auth_url              = "/login"
    cred_stuffing_protect = true
    sess_fixation_protect = true
    sess_id_name          = "session_id"
    username              = "username"
    password              = "password"
  }
}

# Module: API Gateway
resource "fortiappseccloud_waf_api_gateway" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status = true
    action = "alert_deny"

    rule_list {
      item {
        name              = "example-rule"
        api_key_verify    = true
        api_key_loc       = "http-header"
        field_name        = "X-API-Key"
        rate_limit_period = 60
        rate_limit_req    = 100

        url_list {
          item {
            frontend = "/api"
            backend  = "/backend"
          }
        }

        user_list {
          item {
            user = "example-user"
          }
        }
      }
    }

    user_list {
      item {
        name     = "example-user"
        email    = "user@example.com"
        comments = "example user"

        ip_list {
          item {
            ip = "10.0.0.1"
          }
        }

        referer_list {
          item {
            referer = "example.com"
          }
        }
      }
    }
  }
}

# Module: Biometrics-Based Detection
resource "fortiappseccloud_waf_biometrics_based_detection" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status             = true
    action             = "alert_deny"
    click              = true
    keyboard           = true
    mouse_movement     = true
    screen_touch       = false
    scroll             = false
    bot_effect_time    = 5
    event_collect_time = 15

    url_list {
      item {
        url = "/login"
      }
    }

    exception_list {
      item {
        concatenate_type = "AND"
        match_target     = "COOKIE"
        operator         = "REGEXP_MATCH"
        value_name       = "session_id"
        value_check      = true
        value            = "terraform-matrix"
      }
    }
  }
}

# Module: Bot Deception
resource "fortiappseccloud_waf_bot_deception" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status        = true
    action        = "alert_deny"
    deception_url = "/url.html"

    url_list {
      item {
        url = "/login"
      }
    }

    exception_list {
      item {
        concatenate_type = "AND"
        match_target     = "COOKIE"
        operator         = "REGEXP_MATCH"
        value_name       = "session_id"
        value_check      = true
        value            = "terraform-matrix"
      }
    }
  }
}

# Module: Caching and Compression
resource "fortiappseccloud_waf_caching_compression" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status = true

    cache {
      status            = true
      cache_timeout     = 120
      timeout_type      = "minutes"
      allow_method      = "GET,HEAD"
      allow_return_code = "200"
    }

    compress {
      status = true
    }

    cookie_list {
      item {
        name = "session-cookie"
      }
    }

    content_type_list {
      item {
        type = "text/html"
      }
    }
  }
}

# Module: Cookie Security
resource "fortiappseccloud_waf_cookie_security" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status            = true
    action            = "alert_deny"
    mode              = "signed"
    replay_protection = true
    max_age           = 180
    secure_cookie     = true
    http_only         = true
    samesite          = false
    samesite_value    = "Lax"

    cookie_except_list {
      item {
        name     = "__utma"
        wildcard = false
      }
    }
  }
}

# Module: CSRF Protection
resource "fortiappseccloud_waf_csrf_protection" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status = true
    action = "alert_deny"

    page_list {
      item {
        filter = true
        url    = "/checkout"
        name   = "csrf_token"
        value  = "expected"
      }
    }

    url_list {
      item {
        filter = true
        url    = "/api/orders"
        name   = "csrf_token"
        value  = "expected"
      }
    }
  }
}

# Module: DDoS Prevention
resource "fortiappseccloud_waf_ddos_prevention" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status             = true
    action             = "block_period"
    challenge          = "real-browser-enforcement"
    http_access_limit  = true
    http_request_limit = 1000
    conn_flood_check   = true
    conn_flood_limit   = 100
    http_flood_prevent = true
    http_session_limit = 500
    tcp_flood_prevent  = false
    tcp_conn_num_limit = 255
    block_period       = 600

    ip_exception {
      item {
        ip = "1.1.1.1-1.1.1.2,1.1.1.4"
      }
    }
  }
}

# Module: File Protection
resource "fortiappseccloud_waf_file_protection" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status            = true
    action            = "alert_deny"
    trojan            = false
    sandbox           = false
    av_scan           = true
    file_action       = "Allow"
    file_size         = 10240
    url               = "/1"
    json_file_support = false

    file_types {
      item {
        type = "GIF"
        tid  = "00001"
      }
    }

    custom_file_types {
      item {
        name           = "custom-archive"
        file_extension = "foo"

        file_content_match_rule {
          item {
            data_value       = "magic-bytes"
            offset_from      = "beginning"
            offset           = 0
            operation        = "equal"
            data_type        = "string"
            concatenate_type = "AND"
          }
        }
      }
    }
  }
}

# Module: GraphQL Protection
resource "fortiappseccloud_waf_graphql_protection" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status = true
    action = "alert_deny"

    rule_list {
      item {
        name        = "graphql-default"
        request_url = "/graphql"
      }
    }
  }
}

# Module: HTTP Header Security
resource "fortiappseccloud_waf_http_header_security" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status                       = true
    content_security_policy      = true
    header_value                 = "default-src 'self'"
    referrer_policy              = true
    referrer_policy_header_value = "strict-origin-when-cross-origin"
    x_content_type_options       = true
    x_frame_options              = true
    x_xss_protection             = true
  }
}

# Module: Information Leakage
resource "fortiappseccloud_waf_information_leakage" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status               = true
    action               = "deny_erase_no_log"
    cloak_error_pages    = true
    erase_http_headers   = true
    personal_info        = true
    server_info_disclose = true

    http_headers {
      item {
        header = "Server"
      }
    }

    sig_except_rules {
      item {
        sig_id   = "030000010"
        sig_name = "SQL Injection"
        cookie {
          status = true
          type   = "string"
          value  = "sessionid"
        }
        host {
          status = true
          type   = "string"
          value  = "www.example.com"
        }
        http_header {
          status = true
          type   = "string"
          value  = "X-Example"
        }
        json {
          status = true
          type   = "string"
          value  = "data"
        }
        param {
          status = true
          type   = "string"
          value  = "query"
        }
        url {
          status = true
          type   = "regex"
          value  = "^/admin"
        }
      }
    }
  }
}

# Module: JSON Protection
resource "fortiappseccloud_waf_json_protection" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status = true
    action = "alert_deny"
  }
}

# Module: Known Attacks
resource "fortiappseccloud_waf_known_attacks" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status            = true
    sensitivity_level = 2
    action            = "alert_deny"
    cross_site_script = true
    sql_inject        = true
    trojans           = true

    sig_except_rules {
      item {
        sig_id   = "030000010"
        sig_name = "SQL Injection"
        cookie {
          status = true
          type   = "string"
          value  = "sessionid"
        }
        host {
          status = true
          type   = "string"
          value  = "www.example.com"
        }
        http_header {
          status = true
          type   = "string"
          value  = "X-Example"
        }
        json {
          status = true
          type   = "string"
          value  = "data"
        }
        param {
          status = true
          type   = "string"
          value  = "query"
        }
        url {
          status = true
          type   = "regex"
          value  = "^/admin"
        }
      }
    }
  }
}

# Module: Known Bots
resource "fortiappseccloud_waf_known_bots" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status           = true
    bad_bots         = true
    bad_bots_action  = "block_period"
    good_bots_action = "bypass"

    bad_bots_list {
      item {
        cat    = "DoS"
        status = true
        allow_list {
          item {
            value = "AB"
          }
        }
      }
    }

    good_bots_list {
      item {
        cat    = "Known Search Engines"
        status = true
        deny_list {
          item {
            value = "Ask"
          }
        }
      }
    }

    exception_list {
      item {
        concatenate_type = "AND"
        match_target     = "COOKIE"
        operator         = "REGEXP_MATCH"
        value_name       = "session_id"
        value_check      = true
        value            = "terraform-matrix"
      }
    }
  }
}

# Module: Man-in-the-Browser Protection
resource "fortiappseccloud_waf_mitb_protection" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status      = true
    action      = "alert_deny"
    request_url = "/login"
    post_url    = "/submit"

    param_list {
      item {
        type            = "regular-input"
        name            = "password"
        obfuscate       = true
        encrypt         = false
        anti_key_logger = false
      }
    }

    domain_list {
      item {
        domain = "https://maps.googleapis.com"
      }
    }
  }
}

# Module: ML Bot Detection
resource "fortiappseccloud_waf_ml_bot_detection" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status                = true
    action                = "block_period"
    identification_method = "IP-and-User-Agent"
    model_type            = "Strict"
    anomaly_count         = 1
    challenge             = "Real-Browser-Enforcement"
    block_duration        = 600

    ip_list {
      item {
        ip = "1.1.1.1"
      }
    }

    url_list {
      item {
        url = "/login"
      }
    }

    exception_list {
      item {
        concatenate_type = "AND"
        match_target     = "COOKIE"
        operator         = "REGEXP_MATCH"
        value_name       = "session_id"
        value_check      = true
        value            = "terraform-matrix"
      }
    }
  }
}

# Module: Mobile API Protection
resource "fortiappseccloud_waf_mobile_api_protection" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status       = true
    action       = "alert_deny"
    token_header = "Jwt_Token"
    token_secret = local.mobile_api_token_secret

    url_list {
      item {
        url = "/login"
      }
    }
  }
}

# Module: Parameter Validation
resource "fortiappseccloud_waf_parameter_validation" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status = true

    rule_list {
      item {
        name         = "param-rule"
        url          = "/api/params"
        action       = "alert_deny"
        block_period = 60

        sub_rule_list {
          item {
            name       = "username"
            arg_type   = "data-type"
            arg_val    = "string"
            max_len    = 128
            required   = true
            type_check = true
          }
        }
      }
    }
  }
}

# Module: Request Limits
resource "fortiappseccloud_waf_request_limits" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status              = true
    body_param_len      = 8192
    cookie_num          = 128
    http_req_len        = 2048
    malformed_url_check = true
    range_num           = 5
    http_header_action  = "alert_deny"

    allow_methods {
      item { method = "get" }
      item { method = "post" }
      item { method = "head" }
    }
  }
}

# Module: Rewriting Requests
resource "fortiappseccloud_waf_rewriting_requests" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status               = true
    x_forwarded_for      = true
    identify_original_ip = true
    x_header             = "X-Forwarded-For"

    rule_list {
      item {
        name                = "rewrite-example"
        action              = "rewrite-header-advanced"
        host_filter         = true
        host_expression     = "^(example\\.com)$"
        header_status       = true
        insert_header_name  = "X-Terraform-Matrix"
        insert_header_value = "enabled"

        remove_header {
          item {
            header = "X-Old-Header"
          }
        }
      }
    }
  }
}

# Module: Threshold Detection
resource "fortiappseccloud_waf_threshold_detection" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status                 = true
    action                 = "block_period"
    challenge              = "RBE"
    crawler                = false
    vulnerability_scan     = true
    slow_attack            = false
    content_scraping       = false
    credential_brute_force = true
    request_url            = "/login"
    occurrence             = 10
    range                  = 60

    exception_list {
      item {
        concatenate_type = "AND"
        match_target     = "COOKIE"
        operator         = "REGEXP_MATCH"
        value_name       = "session_id"
        value_check      = true
        value            = "terraform-matrix"
      }
    }
  }
}

# Module: URL Access
resource "fortiappseccloud_waf_url_access" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status = true

    rule_list {
      item {
        action   = "pass"
        name     = "terraform-matrix-string-rule"
        url      = "/terraform-matrix/"
        url_type = "string"
      }
    }
  }
}

# Module: Waiting Room
resource "fortiappseccloud_waf_waiting_room" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status                    = true
    path                      = "/.*"
    enable_total_active_users = true
    total_active_users        = 1000
    enable_new_users_per_min  = false
    new_users_per_min         = 60
    session_duration          = 5
    custom_wt_page            = "Predefined"

    bypass_rules {
      item {
        rule_type  = "source-ip"
        rule_value = "192.0.2.10"
      }
    }
  }
}

# Module: WebSocket Security
resource "fortiappseccloud_waf_web_socket_security" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status = true
    action = "alert_deny"

    rule_list {
      item {
        name              = "ws-rule"
        url               = "/ws"
        allow_binary_text = true
        allow_plain_text  = true
        allow_websocket   = true
        block_attacks     = true
        block_extensions  = false
        max_frm_size      = 64
        max_msg_size      = 1024

        origin_list {
          item {
            origin = "https://example.com"
          }
        }
      }
    }
  }
}

# Module: XML Protection Policy
resource "fortiappseccloud_waf_xml_protection_policy" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status = true
    action = "alert_deny"
  }
}

# Module: Global Trust List Parameter
resource "fortiappseccloud_waf_global_trust_list_parameter" "test" {
  ep_id = fortiappseccloud_waf_app.test.ep_id

  configs {
    status = true

    trust_list {
      item {
        name   = "terraform-custom-module-live"
        status = true
        url    = "/terraform-custom-module-live"
      }
    }
  }
}

# Module: Anomaly Detection
resource "fortiappseccloud_waf_anomaly_detection" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status       = true
    action       = "alert"
    ip_list_type = "Block"

    ip_list {
      item {
        ip = "192.0.2.10"
      }
    }
  }
}

# Module: CORS Protection
resource "fortiappseccloud_waf_cors_protection" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status             = true
    block_cors_traffic = false

    allowed_origins {
      protocol            = "HTTPS"
      origin_name         = "terraform-custom-module-live.invalid"
      port                = 443
      include_sub_domains = false
    }
    allowed_methods {
      status  = true
      methods = ["GET", "HEAD"]
    }
    allowed_headers {
      status  = true
      headers = ["Content-Type"]
    }
    exposed_headers {
      status  = true
      headers = ["X-Terraform-Custom-Module-Live"]
    }
    url_pattern         = "/terraform-custom-module-live"
    allowed_credentials = "FALSE"
    allowed_maximum_age = 60
  }
}

# Module: IP Protection
resource "fortiappseccloud_waf_ip_protection" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status        = true
    ip_reputation = false

    ip_list {
      item {
        type = "trust-ip"
        ip   = "1.1.1.1"
      }
    }
  }
}

# Module: Content Routing
resource "fortiappseccloud_waf_content_routing" "test" {
  ep_id  = fortiappseccloud_waf_app.test.ep_id
  status = true

  policy_list {
    item {
      name        = "terraform-custom-module-live"
      server_pool = "default_pool"
      is_default  = true

      rule_list {}
    }
  }
}

# Module: Custom Rule
resource "fortiappseccloud_waf_custom_rule" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status = true

    rule_list {
      item {
        name      = "terraform-custom-module-live"
        action    = "alert"
        challenge = "real-browser-enforcement"

        filter_list {
          item {
            type          = "source-ip-filter"
            ip            = "1.1.1.1-1.1.1.255"
            reverse_match = true
          }
        }
      }
    }
  }
}

# Module: ML API Protection
resource "fortiappseccloud_waf_ml_api_protection" "test" {
  ep_id    = fortiappseccloud_waf_app.test.ep_id
  template = false

  configs {
    status        = true
    threat_action = "alert"
    ip_list_type  = "Block"

    ip_list {
      item {
        ip = "192.0.2.13"
      }
    }

    path_list {
      item {
        type    = "plain"
        pattern = "/terraform-custom-module-live"
      }
    }
  }
}

# Module: OpenAPI Validation
resource "fortiappseccloud_waf_openapi_validation" "test" {
  ep_id  = fortiappseccloud_waf_app.test.ep_id
  enable = true
  action = "alert_deny"
  validation_files = [
    "${path.module}/openapi.yaml",
  ]
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "app_ep_id" {
  description = "Application endpoint ID (ep_id)"
  value       = fortiappseccloud_waf_app.test.ep_id
}

output "app_name" {
  description = "Application name"
  value       = fortiappseccloud_waf_app.test.app_name
}

output "domain_name" {
  description = "Protected domain"
  value       = fortiappseccloud_waf_app.test.domain_name
}
