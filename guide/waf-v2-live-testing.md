# WAF v2.0 Live Testing Guide

This guide records the completed 30-resource live-validation flow and the
separately gated custom-module campaign prepared for the newer locally
implemented resources:

1. create one new disposable application with the v2.0 Framework provider;
2. use runtime-resolved `ep_id` values to configure and update the exact
   resources authorized by each fixed-suite gate;
3. exercise empty plans and imports for those resources;
4. destroy the managed resources and disposable applications, verify restoration and cleanup; and
5. separately verify an untouched v1.0.5 state with the current v2 provider.

It does not require `FORTIAPPSECCLOUD_TEST_EP_ID`. The application vertical,
generated-module campaign, and custom-module campaign all resolve the fixture
identity after public application onboarding. Operators never know or export an
endpoint ID.

The captured-state migration is independently gated and plan-only. Do not combine it with a write-enabled lifecycle campaign.

## Safety contract

- Use credentials from environment variables only. Never place tokens or passwords in Terraform configuration, command arguments, test output, or this guide.
- Use a non-production account or explicitly disposable application.
- Review the exact HCL and lifecycle in `internal/acceptance/waf_live_test.go`,
  `internal/acceptance/waf_all_resources_live_test.go`, or
  `internal/acceptance/waf_custom_modules_live_test.go` before setting the
  corresponding write gate.
- The write-gate value includes the exact new application name; changing the target invalidates the authorization.
- Every mutation of a pre-existing remote object snapshots its complete state and registers unconditional restoration immediately. The newly created app is instead identified by its unique name and deleted with observable-absence verification.
- Treat restoration failure as the primary failure. Stop further live tests until the remote state is repaired and verified.
- Do not enable multiple writers for the same application. Provider locks are process-local and cannot prevent another Terraform process from racing.
- Run the captured-state migration gate by itself. It must use a protected state copy and reviewed v2 configuration; it never authorizes an apply.

## Local preflight

Run the non-live baseline first:

```shell
go generate ./...
go test ./...
go test -race ./internal/...
go vet ./...
go build ./...
TF_CLI_TEST=1 go test . -run '^TestTerraformCLI' -count=1
terraform fmt -check -recursive examples
git diff --check
```

The second `go generate ./...` must produce identical output. No command in this section needs live credentials.

## Common live environment

Provide credentials through a secret manager or the invoking shell environment:

```shell
export TF_ACC=1
export FORTIAPPSECCLOUD_ACC_PLAN_REVIEWED=yes
export FORTIAPPSECCLOUD_HOSTNAME="https://api.appsec.fortinet.com"
# FORTIAPPSECCLOUD_API_TOKEN must already be exported securely.
```

`FORTIAPPSECCLOUD_HOSTNAME` may be omitted when the provider's production default is intended. API-token authentication is preferred. Do not source any repository credential file.

## Captured v1.0.5 state migration

`TestAccCapturedV105StateMigration` verifies an untouched full state captured from the public provider v1.0.5. The fixture must contain schema-version-0 `fortiappseccloud_waf_app` and `fortiappseccloud_waf_openapi_validation` instances. The reviewed v2 configuration must keep both resource addresses and must include every file referenced by OpenAPI validation.

The test copies the state, v2 configuration, and optional assets into a mode-restricted temporary directory. It builds the current provider, refreshes the copied state, and requires `terraform plan -detailed-exitcode` to return `0`. It does not apply and cannot write WAF configuration.

Keep captured state and target-specific configuration outside commits. Run the gate separately with:

```shell
export TF_ACC=1
export FORTIAPPSECCLOUD_ACC_PLAN_REVIEWED=yes
export FORTIAPPSECCLOUD_ACC_V1_MIGRATION_READ=captured_v1_0_5_refresh_noop_v1
export FORTIAPPSECCLOUD_ACC_V1_STATE_PATH="<protected-v1.0.5-state-path>"
export FORTIAPPSECCLOUD_ACC_V2_CONFIG_PATH="<reviewed-v2-config-path>"
export FORTIAPPSECCLOUD_ACC_V2_ASSET_PATHS="<openapi-document-path>"
go test . -run '^TestAccCapturedV105StateMigration$' -count=1 -v
```

`FORTIAPPSECCLOUD_ACC_V2_ASSET_PATHS` is an operating-system path list and can contain multiple local documents. Omit it when no referenced assets are required. The accepted result and v1.0.5 OpenAPI refresh caveat are recorded in `progress/2026-08-05-v105-to-v2-migration.md`.

## Phase A: application vertical

This serial acceptance test covers five served Framework resources:

| Resource | Live behavior exercised |
|---|---|
| `fortiappseccloud_waf_app` | Create, refresh, block-mode update, legacy-name import, no-op plan, delete, and observable absence |
| `fortiappseccloud_waf_origin_servers` | Complete pool write, server-weight update, import, refresh, and parent-app cleanup |
| `fortiappseccloud_waf_template_attachment` | Snapshot, add one membership, import, detach, and exact membership restoration |
| `fortiappseccloud_waf_openapi_validation` | Upload one temporary document, action update, import, disable/clear on destroy |
| `fortiappseccloud_waf_csrf_protection` | Enable with `alert`, update to `alert_deny`, import, and remote verification |

Choose a unique, disposable application name and domain. The origin must be safe for connectivity testing, and the template must already exist and be safe for temporary membership changes. When the origin uses SSL, choose its encryption level explicitly; the production API rejects an origin PUT that omits this cipher policy, and the provider must not invent one.

The harness derives origin `type` as `ip` for an IP literal and `domain` otherwise; operators do not supply an existing application or endpoint ID.

```shell
export FORTIAPPSECCLOUD_ACC_APP_NAME="<unique-disposable-app-name>"
export FORTIAPPSECCLOUD_ACC_DISPOSABLE_APP=yes
export FORTIAPPSECCLOUD_ACC_APP_LIFECYCLE_WRITE="application_origin_template_openapi_csrf_v4:${FORTIAPPSECCLOUD_ACC_APP_NAME}"
export FORTIAPPSECCLOUD_ACC_DOMAIN="<disposable-protected-domain>"
export FORTIAPPSECCLOUD_ACC_ORIGIN_ADDRESS="<authorized-origin-address>"
export FORTIAPPSECCLOUD_ACC_ORIGIN_ENCRYPTION_LEVEL="<mozilla_modern|mozilla_intermediate|mozilla_old|customized|high|medium>"
export FORTIAPPSECCLOUD_ACC_PLATFORM="<AWS|Azure|GCP|OCI|C8T>"
export FORTIAPPSECCLOUD_ACC_REGION="<public-logical-region>"
export FORTIAPPSECCLOUD_ACC_TEMPLATE_ID="<authorized-template-id>"
```

The `v4` gate authorizes the explicit origin encryption policy in addition to the previously reviewed lifecycle. A stale `v3` gate cannot authorize this payload.

Run the complete lifecycle test. Do not interrupt it after creation or update because final destruction and verification are part of the test:

```shell
go test ./internal/acceptance -run '^TestAccApplicationVerticalSlice$' -count=1 -v
```

### Stage 1: create

- The test first refuses to continue if the selected application name already exists.
- `fortiappseccloud_waf_app` onboards the application and stores the returned stable `ep_id` as a computed attribute.
- Terraform passes that computed value directly to origin servers, template attachment, OpenAPI validation, and CSRF protection. No endpoint ID is supplied by the operator.

### Stage 2: configure and change resources

- The initial apply creates the application and configures all four dependent resources in the table above.
- The update changes application block mode, origin-server weight, OpenAPI action, and CSRF action.
- Independent API reads verify that the changed values reached the remote service.
- A second Terraform plan must be empty.
- Import verification must successfully hydrate all five resource states.

### Stage 3: destroy and verify cleanup

- Terraform destroys the dependent resources before destroying their parent application.
- OpenAPI validation is disabled and its files are cleared.
- Template attachment removes the new app and restores the template's original membership exactly.
- CSRF protection and origin servers follow their documented forget behavior; their remote configuration disappears when the disposable parent application is deleted.
- Application deletion must become observable through an independent API read.
- The emergency cleanup also restores template membership first, then searches for and deletes only the exact disposable application name if Terraform stopped after onboarding.

### Success criteria

The test succeeds only when:

- onboarding returned a stable `ep_id`;
- the update was visible through independent API reads;
- the second Terraform plan was empty;
- all five import paths hydrated successfully;
- Terraform destroy removed the managed resources and new application;
- application absence was independently observable; and
- template membership matched the pre-test snapshot.

The repository also contains separately gated regression tests for pre-existing applications. Those tests are outside this procedure and must not be mixed into this create-to-destroy flow.

## Phase B: every app-module resource

After Phase A has passed and its disposable application is absent, run the all-module campaign. It creates one fresh disposable app through the public onboarding API, resolves the returned application identity at runtime, and runs 26 resource lifecycles serially. Each subtest uses an isolated Terraform state directory.

Only one additional suite gate is required. It is bound to the same exact disposable application name and to the fixed resource list in the acceptance test; do not create per-resource environment variables:

```shell
export FORTIAPPSECCLOUD_ACC_ALL_RESOURCES_WRITE="all_implemented_modules_serial_v1:${FORTIAPPSECCLOUD_ACC_APP_NAME}"
go test ./internal/acceptance -run '^TestAccAllImplementedModuleResources$' -count=1 -v
```

For each module, the harness performs:

1. a complete GET snapshot and immediate unconditional restore registration;
2. Terraform apply with `status=false`;
3. Terraform update to `status=true` and an independent API assertion;
4. a second, empty Terraform plan;
5. import by the runtime-resolved `ep_id`, with identity and status hydration checks;
6. Terraform destroy-policy verification;
7. exact semantic comparison after restoring the complete snapshot.

Caching/compression changes its top-level, cache, and compression status flags together because production treats them as coupled. Account takeover verifies disable-on-destroy. The 25 generated resources verify their current forget-on-destroy contract by confirming the applied remote configuration remains before the snapshot is restored. After the last resource, the harness deletes only the exact disposable application and waits until absence is observable.

| Resource | Production lifecycle covered |
|---|---|
| `fortiappseccloud_waf_account_takeover` | Apply, update, no-op, import, disable-on-destroy, restore |
| `fortiappseccloud_waf_api_gateway` | Apply, update, no-op, import, forget, restore |
| `fortiappseccloud_waf_biometrics_based_detection` | Apply, update, no-op, import, forget, restore |
| `fortiappseccloud_waf_bot_deception` | Apply, update, no-op, import, forget, restore |
| `fortiappseccloud_waf_caching_compression` | Coupled apply/update, no-op, import, forget, restore |
| `fortiappseccloud_waf_cookie_security` | Apply, update, no-op, import, forget, restore |
| `fortiappseccloud_waf_csrf_protection` | Apply, update, no-op, import, forget, restore |
| `fortiappseccloud_waf_ddos_prevention` | Apply, update, no-op, import, forget, restore |
| `fortiappseccloud_waf_file_protection` | Apply, update, no-op, import, forget, restore |
| `fortiappseccloud_waf_graphql_protection` | Apply, update, no-op, import, forget, restore |
| `fortiappseccloud_waf_http_header_security` | Apply, update, no-op, import, forget, restore |
| `fortiappseccloud_waf_information_leakage` | Apply, update, no-op, import, forget, restore |
| `fortiappseccloud_waf_json_protection` | Apply, update, no-op, import, forget, restore |
| `fortiappseccloud_waf_known_attacks` | Apply, update, no-op, import, forget, restore |
| `fortiappseccloud_waf_known_bots` | Apply, update, no-op, import, forget, restore |
| `fortiappseccloud_waf_mitb_protection` | Apply, update, no-op, import, forget, restore |
| `fortiappseccloud_waf_ml_bot_detection` | Apply, alias-normalized update/no-op/import, forget, restore |
| `fortiappseccloud_waf_mobile_api_protection` | Apply, update, no-op, import, forget, restore |
| `fortiappseccloud_waf_parameter_validation` | Apply, update, no-op, import, forget, restore |
| `fortiappseccloud_waf_request_limits` | Apply, response-compatible update/no-op/import, forget, restore |
| `fortiappseccloud_waf_rewriting_requests` | Apply, update, no-op, import, forget, restore |
| `fortiappseccloud_waf_threshold_detection` | Apply, update, no-op, import, forget, restore |
| `fortiappseccloud_waf_url_access` | Apply, update, no-op, import, forget, restore |
| `fortiappseccloud_waf_waiting_room` | Apply, update, no-op, import, forget, restore |
| `fortiappseccloud_waf_web_socket_security` | Apply, update, no-op, import, forget, restore |
| `fortiappseccloud_waf_xml_protection_policy` | Apply, update, no-op, import, forget, restore |

Together, Phase A and Phase B cover the 30 resources with recorded production
evidence. CSRF is intentionally covered in both phases: once as a Terraform
dependency of the newly created app and once through the uniform module
lifecycle. The provider now serves additional locally implemented custom
resources; the prepared, not-yet-authorized non-certificate campaign is Phase C.

### Phase B success criteria

The campaign succeeds only when all 26 subtests pass, no restore cleanup reports an error, the parent disposable app is deleted, and a separate cleanup check confirms absence:

```shell
export FORTIAPPSECCLOUD_ACC_APP_LIFECYCLE_WRITE="application_origin_template_openapi_csrf_v4:${FORTIAPPSECCLOUD_ACC_APP_NAME}"
go test ./internal/acceptance -run '^TestAccApplicationVerticalCleanupState$' -count=1 -v
```

The recorded July 22, 2026 run passed all 26 subtests in 367.20 seconds. The independent cleanup check also passed. The earlier Phase A run passed all five vertical resources in 39.57 seconds.

## Phase C: non-certificate custom resources (verified)

`TestAccCustomModuleResources` is a new fixed-suite campaign for exactly these
seven resources:

| Resource | Production result |
|---|---|
| `fortiappseccloud_waf_global_trust_list_parameter` | Full lifecycle and exact restoration passed |
| `fortiappseccloud_waf_anomaly_detection` | Full lifecycle and exact restoration passed |
| `fortiappseccloud_waf_cors_protection` | Full lifecycle and exact restoration passed after empty/singleton-array response compatibility was added |
| `fortiappseccloud_waf_ip_protection` | Full lifecycle and exact normalized restoration passed with the production fixed-slot `ip: null` response |
| `fortiappseccloud_waf_content_routing` | Full lifecycle and exact restoration passed |
| `fortiappseccloud_waf_custom_rule` | Full lifecycle and exact restoration passed with the checked-in API request example's source-IP shape |
| `fortiappseccloud_waf_ml_api_protection` | Full lifecycle and exact restoration passed |

The campaign creates a uniquely named disposable application, derives its
`ep_id`, and runs each resource serially in isolated Terraform state. Before
each mutation it snapshots the complete typed/raw-preserving result and
registers restoration. After Terraform destroy it verifies the resource's
current reviewed disable-or-forget contract, then restores and semantically
compares the complete snapshot. Final cleanup deletes
only the exact disposable application and waits for observable absence.

This is a separate authorization surface. Do not reuse the Phase B gate.
The current gate value is:

```shell
export FORTIAPPSECCLOUD_ACC_CUSTOM_MODULES_WRITE="custom_modules_serial_v4:${FORTIAPPSECCLOUD_ACC_APP_NAME}"
go test ./internal/acceptance -run '^TestAccCustomModuleResources$' -count=1 -v
```

The common live environment and disposable-application variables above are
also required. The v4 gate retains the verified IP Protection compatibility
rule and uses the checked-in Custom Rule PUT example's request shape. The
completed v2/v3/v4 results are recorded in
`progress/2026-07-27-waf-custom-modules-phase-c-live-verification.md`.

## Complete dev1 WAF matrix

The one-command matrix in
`plan/2026-07-29-waf-complete-live-test-plan.md` is implemented and passed
against `https://api.dev1.fortiappsec.com` on 2026-07-31. The accepted result
contains 99 planned evidence rows:

- 34 app-configuration rows passed;
- 34 destroy-policy rows passed;
- 31 template-module rows passed;
- all attempted module snapshots restored; and
- disposable application and template cleanup passed.

Ninety-four rows were direct module subtests. D01, D05, D27, D31, and D34
reuse the matching destroy assertions performed by their A lifecycle and are
recorded as derived D evidence. The other 29 D rows directly exercised the
shared guarded disable engine against each exact module endpoint.

The user accepted dev1 as sufficient live API evidence; production repetition
is not required. The 29 candidates were subsequently promoted in their
reviewed descriptors/contracts, and deterministic tests confirmed every
served Terraform destroy path. No additional live API campaign was needed.

Run the complete campaign with:

```shell
export FORTIAPPSECCLOUD_API_TOKEN="<environment credential>"
./scripts/run-dev-waf-matrix.sh
```

The wrapper pins dev1, supplies the exact master gate, runs the complete local
gate first, creates all disposable identities, restores snapshots, verifies
parent cleanup, and writes only a sanitized mode-`0600` summary.

## Per-module app disable-on-destroy promotion

App-module disable promotion is deliberately separate from the broad Phase B
and Phase C campaigns. A previous apply/update lifecycle does not establish
destroy semantics. Each candidate must pass its own exact target-bound
GET/PUT/GET test before its served policy changes from forget-with-warning to
disable.

All 29 candidates passed that exact lifecycle in the accepted complete dev1
matrix on 2026-07-31. They are now active disable-on-destroy policies, and the
deterministic served Terraform Delete suite passed for every one. No
additional production or live API verification is required.

There are 29 structural candidates: 24 generated modules with a standalone
writable boolean `configs.status` (all generated modules except
`caching_compression`) and five hand-written modules (`anomaly_detection`,
`cors_protection`, `custom_rule`, `ip_protection`, and
`ml_api_protection`). `caching_compression` is excluded because production
requires its top-level, cache, and compression statuses to move together.
`global_trust_list_parameter` and `routings` do not expose the standard
`template + configs.status` envelope and are also excluded. Account takeover
and OpenAPI validation retain their already reviewed destroy implementations.
All 31 template-module resources now use their separate reviewed
disable-on-destroy policy. Thirty resources use the standard
`configs.status=false` contract. Direct dev1 curl control proved that template
caching/compression instead requires top-level, cache, and compression statuses
to be false together: a top-level-only PUT returned HTTP 200 but GET retained
all three true, while the coupled PUT returned all three false. Rerunning the
complete matrix exercises the served preserving Delete path and requires
explicit authorization for those template writes.

The older exact-one-candidate gate remains available for focused regression
against one explicitly authorized disposable application:

```shell
export FORTIAPPSECCLOUD_TEST_EP_ID="<authorized-disposable-ep-id>"
export FORTIAPPSECCLOUD_TEST_APP_NAME="<matching-application-name>"
export FORTIAPPSECCLOUD_TEST_MODULE="<one-reviewed-module-name>"
export FORTIAPPSECCLOUD_ACC_MODULE_DISABLE_WRITE="disable_v1:${FORTIAPPSECCLOUD_TEST_MODULE}:${FORTIAPPSECCLOUD_TEST_EP_ID}"
go test ./internal/resources/wafmodule -run '^TestAccDescriptorDrivenDisable$' -count=1 -v
```

The common `TF_ACC=1`, `FORTIAPPSECCLOUD_ACC_PLAN_REVIEWED=yes`, and
`FORTIAPPSECCLOUD_ACC_DISPOSABLE_APP=yes` gates are also required. The test
confirms the application name and endpoint ID match, snapshots the complete
module result in memory, prepares `template=false/configs.status=true`, then
executes the shared destroy engine:

1. fresh GET;
2. clone the complete result without projecting away unknown fields;
3. set only `template=false` and `configs.status=false`;
4. PUT the complete result;
5. GET and require complete semantic equality with the expected result; and
6. restore and verify the original complete snapshot in cleanup.

No request/response body is written to logs or disk. Outside the accepted
complete matrix, a passing targeted test is evidence for only the selected
module. Record the sanitized pass, restoration result, environment, date, and
code identity; then separately change only that module's reviewed policy to
verified disable and run the complete local gate.

### IP Protection wire capture

`TestAccIPProtectionWireCapture` is a separately gated diagnostic for the open
populated-`ip_list` contract mismatch. It creates a fresh disposable
application, snapshots IP Protection, sends the same fresh-GET-merged
`trust-ip`/`1.1.1.1` PUT used by the failed lifecycle, captures the PUT response
and following GET, attempts exact restoration, and then deletes the disposable
parent with observable-absence verification.

The generated artifact is mode `0600` in the system temporary directory. It
contains only allowlisted IP Protection JSON fields and UTC event timestamps.
It cannot contain request/response headers, hostname, URL path, application
name, `ep_id`, authorization material, or unknown response-field contents.

This diagnostic has its own target-bound gate and does not reuse the broader
Phase C gate:

```shell
export FORTIAPPSECCLOUD_ACC_IP_PROTECTION_CAPTURE_WRITE="ip_protection_wire_capture_v1:${FORTIAPPSECCLOUD_ACC_APP_NAME}"
go test ./internal/acceptance -run '^TestAccIPProtectionWireCapture$' -count=1 -v
```

Run it only for an explicitly authorized backend investigation. The
2026-07-27 capture proved that PUT retains the configured slot and GET adds
null-IP placeholders for the other two rule types; restoring `[]` returns all
three null placeholders. A capture does not by itself authorize another
complete Phase C campaign.

## Phase D: retired

Phase D and `TestAccIntermediateCertificateIdentityProbe` were removed on
2026-07-27. `log_settings` and all certificate/CRL content upload or attachment
families are explicit provider non-goals, so no certificate upload probe or
campaign is required or permitted by this guide.

Application-level automatic/custom certificate mode is a separate implemented
non-upload configuration. Its numeric `cert_type` mapping, local Terraform
lifecycle, and a dedicated disposable dev1 automatic → custom → automatic
lifecycle are reviewed; it never accepts certificate content. The live test is
implemented as `TestAccDevApplicationCertificateModeLifecycle`, is restricted
to the exact dev1 hostname, and requires
`FORTIAPPSECCLOUD_ACC_DEV_CERTIFICATE_MODE_WRITE=certificate_mode_v1` plus the
same `FORTIAPPSECCLOUD_ACC_ORIGIN_ADDRESS` verified for disposable dev apps.

## Dev template lifecycle

Template creation is currently a dev-only authorization surface. Both tests
refuse any hostname other than `https://api.dev1.fortiappsec.com` and require a
preflight-unique disposable template name.

The wire-contract probe preserves the CRUD request and responses in a
mode-`0600` temporary artifact without authorization or cookie headers:

```shell
export FORTIAPPSECCLOUD_ACC_DISPOSABLE_TEMPLATE=yes
export FORTIAPPSECCLOUD_ACC_TEMPLATE_NAME="<unique-disposable-name>"
export FORTIAPPSECCLOUD_ACC_TEMPLATE_LIFECYCLE_WRITE="template_crud_v1:${FORTIAPPSECCLOUD_ACC_TEMPLATE_NAME}"
go test ./internal/acceptance -run '^TestAccTemplateCRUDWireCapture$' -count=1 -v
```

The historical generated `known_attacks` Terraform lifecycle changes only an
unbound template, verifies apply/update/no-op/import/disable, and then deletes
the parent:

```shell
export FORTIAPPSECCLOUD_ACC_TEMPLATE_MODULE_WRITE="template_known_attacks_v1:${FORTIAPPSECCLOUD_ACC_TEMPLATE_NAME}"
go test ./internal/acceptance -run '^TestAccTemplateKnownAttacksLifecycle$' -count=1 -v
```

Both historical gates also require `TF_ACC=1`,
`FORTIAPPSECCLOUD_ACC_PLAN_REVIEWED=yes`, the dev hostname, and an
environment-provided API token. Unset both template write gates and the
disposable-template variables after the run.

The complete 2026-07-31 dev1 matrix supersedes the single-module evidence:
base-template CRUD and all 31 typed template-module lifecycles passed. Template
status=false writes were verified for every typed module. Thirty template
modules use top-level status alone; caching/compression uses its separately
reviewed coupled three-status disable contract. Template destroy now uses the
served guarded GET/PUT/GET path; rerunning this gate is a mutating regression
and requires the explicit template write authorization above.

## Failure and cleanup procedure

1. Do not start another test after any cleanup or template-restoration error.
2. Use a read-only GET or the FortiAppSec Cloud console to verify the application and module state.
3. Compare only sanitized structural facts; never paste complete API bodies into logs or issues.
4. Restore the template's pre-test membership before retrying.
5. If the app-creation test leaked its uniquely named application, delete that exact disposable app and verify it is absent.
6. Unset exact write gates after the run so later commands cannot reuse stale authorization.

Example cleanup of shell authorization flags:

```shell
unset FORTIAPPSECCLOUD_ACC_APP_LIFECYCLE_WRITE
unset FORTIAPPSECCLOUD_ACC_ALL_RESOURCES_WRITE
unset FORTIAPPSECCLOUD_ACC_CUSTOM_MODULES_WRITE
unset FORTIAPPSECCLOUD_ACC_MODULE_DISABLE_WRITE
unset FORTIAPPSECCLOUD_TEST_MODULE
unset FORTIAPPSECCLOUD_TEST_EP_ID
unset FORTIAPPSECCLOUD_TEST_APP_NAME
unset FORTIAPPSECCLOUD_ACC_DISPOSABLE_APP
unset FORTIAPPSECCLOUD_ACC_PLAN_REVIEWED
```

## Recording results

Record only:

- UTC timestamp and provider commit/diff identity;
- test name and pass/fail/skip status;
- whether apply, second-plan, import, destroy, and restoration checks passed;
- sanitized structural observations needed to narrow provenance.

Never record credentials, endpoint IDs, application/domain/origin names, template IDs, complete request or response bodies, validation document contents, or Terraform state.
