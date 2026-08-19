# Living Unit-Test Plan

**Created:** 2026-08-04
**Repository branch at creation:** `feat-fas-terraform-v2`
**Code baseline:** `1a0386905c`
**Plan status:** passed; unit baseline completed by `UT-2026-08-04-01`, the
coupled three-status caching/compression contract was confirmed by direct curl,
and the corrected provider passed focused T05 plus the complete credentialed
dev1 Gate 5 matrix with `A=34/34`, `D=34/34`, and `T=31/31`

## 1. Goal and scope

This plan gives every served Terraform object a traceable, credential-free test
result. The current inventory is:

| Object | Count |
|---|---:|
| Framework resources | 69 |
| App-scoped WAF module resources | 34 |
| Template-scoped WAF module resources | 31 |
| Core resources outside the module pairs | 4 |
| Data sources | 2 |

The 69 resources are the 34 app modules, the 31 matching template modules, and
the four core resources: application, origin servers, template, and template
attachment. OpenAPI validation is counted as the app-scoped `api_protection`
module.

In this plan, **unit test** means a deterministic Go test using a fake service
or `httptest.Server`. It must not require `TF_ACC`, credentials, DNS, or a live
FortiAppSec Cloud tenant. A local Terraform CLI lifecycle is a stronger local
integration layer, but is still credential-free. Live acceptance is a separate
gate and is not required to call a unit-test row complete.

The template disable-on-destroy contract also has a separately authorized
credentialed dev1 regression gate. It does not replace the deterministic unit
evidence. Its purpose is to prove that each of the 31 served Terraform template
resources executes the preserving destroy path against the real API and that
the API reports the module disabled afterward.

The recorded live module campaign remains in
[`plan/2026-07-29-waf-complete-live-test-plan.md`](2026-07-29-waf-complete-live-test-plan.md).
Do not use its historical result as a substitute for a deterministic unit test.

## 2. Status and evidence rules

Use these values in this document:

| Value | Meaning |
|---|---|
| `[ ]` | Not implemented or not executed for the current run |
| `[x]` | Implemented and the named assertion passed for the recorded commit |
| `N/A` | The object intentionally does not exist; the contract test must prove that absence |
| `BLOCKED(reason)` | Test cannot proceed; record the exact reason without marking it passed |

Keep two facts separate:

1. **Implemented** — a named test or table-driven subtest exists for the exact
   resource type.
2. **Run passed** — that test passed on the commit recorded in the run ledger.

A package-level pass does not prove that every resource in the package was
exercised. A shared lifecycle-engine test does not, by itself, pass every real
descriptor. Each app/template row below must appear as a named test or named
subtest in test output.

Descriptor-driven resources use a composed evidence bundle: the named real
descriptor subtest verifies registration, schema, public GET/PUT ownership,
provider-data rejection, and import identity; the shared `wafmodule` tests
verify lifecycle/error/destroy behavior; and focused codec or local Terraform
CLI tests verify the representative module fields. This composition avoids 65
copies of the same engine harness while still testing each real resource.

## 3. Common verification pattern

Every resource test uses `Arrange -> Act -> Assert -> Reconcile`:

1. **Arrange:** build the real resource constructor with an isolated fake
   client, a fresh lock registry, and a complete remote document containing at
   least one unknown/unowned field.
2. **Act:** execute schema validation, create, read, update, import, and the
   reviewed destroy behavior. Inject one not-found case and one API failure or
   conflict case.
3. **Assert:** verify the exact endpoint/method/body, owned state, preservation
   of unowned fields, diagnostics, identity, sensitive values, collection
   ordering, and destroy semantics.
4. **Reconcile:** read again and require the final state to match the remote
   result. For a Terraform CLI case, require a second plan with exit code `0`
   and an empty state after destroy.

### Pattern U-R: every resource

For every one of the 69 resources, its exact test or composed evidence bundle
must verify:

- exact Terraform type name and unique provider registration;
- schema flags, validators, defaults, sensitive fields, and identity shape;
- provider-data type rejection and safe handling of unknown/null values;
- create/read/update request order and flattening of the verification GET;
- import ID parsing and state hydration;
- parent or resource not-found behavior;
- API error diagnostics retain state and do not expose credentials or content;
- the reviewed delete contract: real delete, disable-and-verify, or
  forget-with-warning with no mutating request.

**Expected result:** no diagnostics on valid input; invalid input fails before a
write; exact owned fields converge; unowned fields survive; import is stable;
delete behavior matches the contract; no goroutine, request, or state leak.

### Pattern U-AM: app-scoped module extension

In addition to U-R:

- test `template=false` with local `configs`;
- where supported, test `template=true` suppresses `configs` in state and sends
  no local-config patch;
- exercise collection ownership as three different cases: omitted preserves,
  explicit empty clears, populated replaces in Terraform order;
- for disable-on-destroy, use a fresh GET, change only `template=false` and the
  reviewed status field, PUT, then verify with another GET;
- for forget-only modules, require one warning and zero PUTs during delete.

**Expected result:** `GET -> PUT -> GET` is exact, a second reconciliation is a
no-op, inheritance does not leak effective configuration into owned state, and
destroy changes no unreviewed field.

### Pattern U-TM: template-scoped module extension

In addition to U-R:

- require `template_id`; reject/omit app-only `ep_id` and `template` fields;
- reuse the reviewed typed `configs` codec from the corresponding app module;
- require the wire envelope to use `template=false`;
- verify create/read/update/import for the exact real descriptor;
- require disable-on-destroy to perform a preserving GET, apply only the
  descriptor's reviewed false status fields, PUT, and verify with another GET;
  caching/compression owns top-level, cache, and compression statuses, while
  the other 30 template resources own only top-level status.

**Expected result:** state contains `template_id + configs`, the matching public
template endpoint is used, a second reconciliation is a no-op, and destroy
disables the remote template module without changing unowned configuration.

### Pattern L-TD: credentialed dev template destroy regression

For every one of the 31 template-module resources, the guarded complete dev1
matrix must:

- use an unbound disposable template created by the run;
- snapshot the complete remote module document before the Terraform lifecycle;
- apply `configs.status=false`, update it to `true`, require a no-op plan, and
  verify import identity;
- destroy the actual served Terraform resource and independently GET the same
  template-module endpoint;
- require `template=false` and top-level `configs.status=false` after destroy;
- for caching/compression, additionally require `configs.cache.status=false`
  and `configs.compress.status=false`;
- rely on the resource's own post-PUT semantic verification to prove every
  other field was preserved; and
- restore and verify the complete pre-test snapshot, then delete and verify
  absence of every disposable parent created by the run.

**Expected result:** all `T01`-`T31` cases pass through the served
GET/PUT/GET destroy path, Terraform state is empty, all 31 snapshot
restorations pass, and disposable template/application cleanup passes. Do not
record credentials, tenant identities, request/response bodies, or Terraform
state in this plan.

### Pattern U-CORE: core resources

Use the resource-specific API rather than the module GET/PUT engine. Test full
lifecycle, stable identity, imports, replacement-only attributes, preservation
of related remote objects, and exact delete/absence verification.

### Pattern U-DS: data sources

Verify metadata/schema, configuration, exact GET path, deterministic ordering,
empty results, malformed results, not-found/status errors, and no write method.

## 4. Required test targets

The final implementation should expose these stable targets. Table-driven
tests are preferred so adding a registered resource without a row fails the
inventory test immediately.

| Target | Purpose | Required result |
|---|---|---|
| `TestFrameworkProviderSchema` | Exact 69-resource and 2-data-source protocol-5 schema inventory | Exact set; no missing/extra/duplicate type |
| `TestAllAppModuleResourceContracts/<module>` | U-R + U-AM for each of 34 real app descriptors | 34 named subtests pass |
| `TestAllTemplateModuleResourceContracts/<module>` | U-R + U-TM for each of 31 real template descriptors | 31 named subtests pass |
| Focused tests in each core resource package | U-CORE for four core resources | 4 resources pass |
| Focused tests in each data-source package | U-DS for two data sources | 2 data sources pass |
| `TestGeneratedManifestCoversRegisteredModules` | Manifest, generated constructors, contract inventory, docs/examples, and plan inventory agree | Exact bijection; generated output has no diff |

The two `TestAll...ResourceContracts` targets are implemented in
`internal/provider/module_resource_contracts_test.go`. Existing shared
`wafmodule` tests supply the common lifecycle behavior, while each real
descriptor now produces its own schema, public-operation, configuration, and
import-identity subtest.

## 5. Core-resource and data-source matrix

The result checkboxes are reset for each full run. Record the run ID in the
final column when checking a row.

| ID | Object | Test focus | Pattern | Implemented | Run passed / run ID |
|---|---|---|---|---|---|
| C01 | `fortiappseccloud_waf_app` | create placement/bootstrap origin; update block mode/domains/certificate mode; import by `ep_id` and legacy name; replacement fields; delete and wait for absence; state upgrades | U-CORE | [x] | [x] `UT-2026-08-04-01` |
| C02 | `fortiappseccloud_waf_origin_servers` | pool/server codec, stable indices, SSL encryption requirement, fresh GET-merge-PUT-GET, import, forget destroy | U-CORE | [x] | [x] `UT-2026-08-04-01` |
| C03 | `fortiappseccloud_waf_template` | create `201` identity, read, import, predefined-delete rejection, delete/absence | U-CORE | [x] | [x] `UT-2026-08-04-01` |
| C04 | `fortiappseccloud_waf_template_attachment` | preserve unrelated memberships, attach one app, import, detach only managed membership | U-CORE | [x] | [x] `UT-2026-08-04-01` |
| DS01 | `data.fortiappseccloud_waf_modules` | canonical module ordering/status, empty inventory, malformed/status errors, read-only behavior | U-DS | [x] | [x] `UT-2026-08-04-01` |
| DS02 | `data.fortiappseccloud_waf_signature_exception` | identity, optional template, response codec, empty/malformed/status errors, read-only behavior | U-DS | [x] | [x] `UT-2026-08-04-01` |

## 6. WAF module/resource matrix

“Focus” is the representative domain shape that must be added to the common
U-AM/U-TM assertions. The app and template resource names are written out so
each of the 65 module resources can be checked independently.

| ID | Module and representative focus | App resource | App implemented / run | Template resource | Template implemented / run |
|---|---|---|---|---|---|
| M01 | `account_takeover`: status/action; inheritance; verified disable | `fortiappseccloud_waf_account_takeover` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_account_takeover` | [x] / [x] `UT-2026-08-04-01` |
| M02 | `api_gateway`: action, rule/user lists, nested users | `fortiappseccloud_waf_api_gateway` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_api_gateway` | [x] / [x] `UT-2026-08-04-01` |
| M03 | `biometrics_based_detection`: timing/gesture flags, exception, URL | `fortiappseccloud_waf_biometrics_based_detection` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_biometrics_based_detection` | [x] / [x] `UT-2026-08-04-01` |
| M04 | `bot_deception`: action, deception URL, exception, URL | `fortiappseccloud_waf_bot_deception` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_bot_deception` | [x] / [x] `UT-2026-08-04-01` |
| M05 | `caching_compression`: coupled top/cache/compression states, cache rule/cookie, content type; forget-only app destroy | `fortiappseccloud_waf_caching_compression` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_caching_compression` | [x] / [x] `UT-2026-08-04-01` |
| M06 | `cookie_security`: action/mode/SameSite/security fields, exception | `fortiappseccloud_waf_cookie_security` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_cookie_security` | [x] / [x] `UT-2026-08-04-01` |
| M07 | `csrf_protection`: action, page list, URL list, omission/empty/replace | `fortiappseccloud_waf_csrf_protection` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_csrf_protection` | [x] / [x] `UT-2026-08-04-01` |
| M08 | `ddos_prevention`: action/challenge/block period, limits, IP exception | `fortiappseccloud_waf_ddos_prevention` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_ddos_prevention` | [x] / [x] `UT-2026-08-04-01` |
| M09 | `file_protection`: scanner/size, file type, custom type/content rule | `fortiappseccloud_waf_file_protection` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_file_protection` | [x] / [x] `UT-2026-08-04-01` |
| M10 | `graphql_protection`: action and rule integer defaults/bounds | `fortiappseccloud_waf_graphql_protection` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_graphql_protection` | [x] / [x] `UT-2026-08-04-01` |
| M11 | `http_header_security`: bounded scalar header/referrer controls and nullable fields | `fortiappseccloud_waf_http_header_security` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_http_header_security` | [x] / [x] `UT-2026-08-04-01` |
| M12 | `information_leakage`: action/flags, header string, signature exception | `fortiappseccloud_waf_information_leakage` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_information_leakage` | [x] / [x] `UT-2026-08-04-01` |
| M13 | `json_protection`: action/bucket/prefix and file entry | `fortiappseccloud_waf_json_protection` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_json_protection` | [x] / [x] `UT-2026-08-04-01` |
| M14 | `known_attacks`: action/sensitivity, flags, signature and syntax exceptions | `fortiappseccloud_waf_known_attacks` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_known_attacks` | [x] / [x] `UT-2026-08-04-01` |
| M15 | `known_bots`: good/bad actions and lists, nested allow/deny ownership | `fortiappseccloud_waf_known_bots` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_known_bots` | [x] / [x] `UT-2026-08-04-01` |
| M16 | `mitb_protection`: action/request/post URL, domain, parameter | `fortiappseccloud_waf_mitb_protection` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_mitb_protection` | [x] / [x] `UT-2026-08-04-01` |
| M17 | `ml_bot_detection`: action/model/challenge/count/duration, exception/IP/URL | `fortiappseccloud_waf_ml_bot_detection` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_ml_bot_detection` | [x] / [x] `UT-2026-08-04-01` |
| M18 | `mobile_api_protection`: action, dummy token values, URL; token redaction | `fortiappseccloud_waf_mobile_api_protection` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_mobile_api_protection` | [x] / [x] `UT-2026-08-04-01` |
| M19 | `parameter_validation`: complete ordered rule and nested defaults | `fortiappseccloud_waf_parameter_validation` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_parameter_validation` | [x] / [x] `UT-2026-08-04-01` |
| M20 | `request_limits`: bounds/actions and allowed-method entry | `fortiappseccloud_waf_request_limits` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_request_limits` | [x] / [x] `UT-2026-08-04-01` |
| M21 | `rewriting_requests`: IP/header fields, rewrite rule, removed header, string wire index | `fortiappseccloud_waf_rewriting_requests` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_rewriting_requests` | [x] / [x] `UT-2026-08-04-01` |
| M22 | `threshold_detection`: action/challenge/count/range/detectors, exception | `fortiappseccloud_waf_threshold_detection` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_threshold_detection` | [x] / [x] `UT-2026-08-04-01` |
| M23 | `url_access`: one slash-prefixed `url_type=string` rule; ordered ownership | `fortiappseccloud_waf_url_access` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_url_access` | [x] / [x] `UT-2026-08-04-01` |
| M24 | `waiting_room`: bounded users/rate/session/path and bypass rule | `fortiappseccloud_waf_waiting_room` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_waiting_room` | [x] / [x] `UT-2026-08-04-01` |
| M25 | `web_socket_security`: action and one ordered rule | `fortiappseccloud_waf_web_socket_security` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_web_socket_security` | [x] / [x] `UT-2026-08-04-01` |
| M26 | `xml_protection_policy`: action/bucket/prefix/file and required entity check | `fortiappseccloud_waf_xml_protection_policy` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_xml_protection_policy` | [x] / [x] `UT-2026-08-04-01` |
| M27 | `global_trust_list_parameter`: status and named URL; no app template envelope; forget-only destroy | `fortiappseccloud_waf_global_trust_list_parameter` | [x] / [x] `UT-2026-08-04-01` | N/A; contract proved no template resource | N/A |
| M28 | `anomaly_detection`: action/list type, one IP, omission/empty/order | `fortiappseccloud_waf_anomaly_detection` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_anomaly_detection` | [x] / [x] `UT-2026-08-04-01` |
| M29 | `cors_protection`: complete four-policy CORS shape and scalar bounds | `fortiappseccloud_waf_cors_protection` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_cors_protection` | [x] / [x] `UT-2026-08-04-01` |
| M30 | `ip_protection`: reputation/trust IP and reviewed null-placeholder normalization | `fortiappseccloud_waf_ip_protection` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_ip_protection` | [x] / [x] `UT-2026-08-04-01` |
| M31 | `routings`: root status, default policy/pool reference, ordered rules; no template envelope; forget-only destroy | `fortiappseccloud_waf_content_routing` | [x] / [x] `UT-2026-08-04-01` | N/A; contract proved no template resource | N/A |
| M32 | `custom_rule`: alert/source-IP rule, filters, cross-field validation | `fortiappseccloud_waf_custom_rule` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_custom_rule` | [x] / [x] `UT-2026-08-04-01` |
| M33 | `ml_api_protection`: threat action/list type, IP/path ownership | `fortiappseccloud_waf_ml_api_protection` | [x] / [x] `UT-2026-08-04-01` | `fortiappseccloud_waf_template_ml_api_protection` | [x] / [x] `UT-2026-08-04-01` |
| M34 | `api_protection` / OpenAPI validation: mode-0600 file, hash-only state, upload/update/read/import, disable clears remote files, content redaction | `fortiappseccloud_waf_openapi_validation` | [x] / [x] `UT-2026-08-04-01` | N/A; contract proved no typed template resource | N/A |

## 7. Supporting-module matrix

These are not Terraform resources, but a resource run is not complete unless
their shared behavior passes.

| ID | Go module/package | Test focus | Implemented | Run passed / run ID |
|---|---|---|---|---|
| S01 | root provider server | complete protocol-5 schema, implemented owners served, state upgrade | [x] | [x] `UT-2026-08-04-01` |
| S02 | `internal/provider` | provider schema, resource/data-source registration, configure and client injection | [x] | [x] `UT-2026-08-04-01` |
| S03 | `internal/providerconfig` | HCL/environment precedence, auth-mode validation, hostname normalization | [x] | [x] `UT-2026-08-04-01` |
| S04 | `internal/client` | authentication, URLs, retries, cancellation, strict codecs, error/secret redaction | [x] | [x] `UT-2026-08-04-01` |
| S05 | `internal/contract` | pinned OpenAPI classification, ownership, exclusions, destroy policy, inventory | [x] | [x] `UT-2026-08-04-01` |
| S06 | `internal/generator` and WAF profile | deterministic generation, manifest checksum, schema constraints, fail-closed overrides | [x] | [x] `UT-2026-08-04-01` |
| S07 | `internal/locking` | same-key serialization and different-key concurrency | [x] | [x] `UT-2026-08-04-01` |
| S08 | `internal/resources/wafmodule` | shared app/template lifecycle engines, conflict retry, inheritance, import, destroy policies | [x] | [x] `UT-2026-08-04-01` |
| S09 | legacy SDK v2 packages `fortiappseccloud` and `fortiappseccloud/waf` | retained compatibility boundary: provider configure/resource schemas, token client, auth rejection, and pure helper smoke tests | [x] | [x] `UT-2026-08-04-01` |

## 8. Execution gates

Run from the repository root. Do not set `TF_ACC` for this unit plan.

### Gate 1 — fast deterministic tests

```shell
go test ./... -count=1
```

Pass condition: exit `0`; no unexpected skip in a required U-R/U-AM/U-TM/core
or data-source target. Environment-gated live tests may skip.

### Gate 2 — race detector

```shell
go test -race ./internal/... -count=1
```

Pass condition: exit `0` and no race report. This is mandatory for client,
locking, and shared module lifecycle changes.

### Gate 3 — static/build/generated consistency

```shell
go vet ./...
go build ./...
go test ./internal/generator ./internal/generator/profile/waf -count=1
git diff --check
```

Pass condition: every command exits `0`; generated tests report that committed
output matches the pinned OpenAPI and profile.

### Gate 4 — credential-free Terraform CLI lifecycle

```shell
TF_CLI_TEST=1 go test . -run '^TestTerraformCLI' -count=1 -v
```

Pass condition for each declared CLI case: apply succeeds, update succeeds,
second plan exits `0` with no changes, import hydrates the stable identity,
post-import plan is empty, destroy follows the reviewed policy, and final state
is empty. No request may leave the local `httptest` server.

Gate 4 currently has named app-module cases and one representative template
module case. Expanding it to all 31 template resources is recommended as a
local integration improvement, but the exact per-template U-TM subtests are
the unit-test completion requirement.

### Gate 5 — credentialed dev1 template destroy regression

This gate is mutating, is not part of the credential-free unit baseline, and
must run only with explicit authorization for dev1. The wrapper pins
`https://api.dev1.fortiappsec.com`, supplies the exact write gate, runs Gates
1-4 first, creates unique disposable application/template parents, and invokes
the complete serial live matrix:

```shell
export FORTIAPPSECCLOUD_API_TOKEN="<environment credential>"
./scripts/run-dev-waf-matrix.sh
```

Pass condition: the sanitized summary reports `A=34/34`, `D=34/34`, and
`T=31/31`; every attempted restoration passes; application and template
cleanup both pass; and no template case skips. For the change covered by this
plan, `T01`-`T31` must be produced by the served template resource Delete path,
not by a direct client-only status toggle. Record only the sanitized summary
facts and the tested commit identity.

## 9. Per-run completion checklist

Create a run ID such as `UT-2026-08-04-01`, then update the row checkboxes and
this summary. Never copy credentials, response bodies, app IDs, or tenant data
into the ledger.

- [x] Record run ID, date/time zone, branch, full commit, Go version, Terraform
      version, and operator/CI job.
- [x] Confirm `git status --short` before the run and identify unrelated user
      changes.
- [x] Confirm the inventory is exactly 69 resources and 2 data sources.
- [x] Confirm all 34 app-module named subtests exist and pass.
- [x] Confirm all 31 template-module named subtests exist and pass.
- [x] Confirm all 4 core-resource rows pass.
- [x] Confirm both data-source rows pass.
- [x] Confirm all applicable supporting-module rows pass; S09 is retained and tested.
- [x] Run Gate 1 and record the result.
- [x] Run Gate 2 and record the result.
- [x] Run Gate 3 and record the result.
- [x] Run Gate 4 and record every named case, failure, or expected skip.
- [x] For every failure, record the row ID, failing test, sanitized error class,
      owner, and follow-up issue; leave the row unchecked.
- [x] Confirm no network credential was required and no secret/content appeared
      in test output or artifacts.
- [x] Confirm `git status --short` after the run; tests generated no unexplained
      repository changes.
- [x] Record the totals: resources `69/69`, data sources `2/2`, app modules
      `34/34`, template modules `31/31`, failed `0`, blocked `0`.
- [x] Codex reviewed the implementation diff, sanitized gate results, and ledger.

## 10. Run ledger

| Run ID | Date | Commit/toolchain | Gates run | Result | Scope note |
|---|---|---|---|---|---|
| `BASELINE-2026-08-04` | 2026-08-04 Asia/Taipei | `1a0386905c`; Go 1.24.5; Terraform 1.15.2 | `go test ./...`; `TF_CLI_TEST=1 go test . -count=1` | PASS; CLI package completed in 120.325s | Baseline proves the existing suite is green. It does **not** close the new exact 34-app/31-template named unit-subtest requirement or S09. |
| `UT-2026-08-04-01` | 2026-08-04 16:00 Asia/Taipei | `1a0386905c8904fe8a0606f393a76a767b48c9b5`; Go 1.24.5; Terraform 1.15.2; Codex local workspace | G1/G2/G3/G4, with `TF_ACC` and all API credential/session variables removed from each child environment | PASS; G4 completed in 119.509s | Resources `69/69`; data sources `2/2`; app modules `34/34`; template modules `31/31`; failed `0`; blocked `0`; no live API access. |

Copy this blank row for the next run:

| `UT-YYYY-MM-DD-NN` | YYYY-MM-DD TZ | commit; Go; Terraform | G1/G2/G3/G4 | PASS/FAIL/BLOCKED | resources `__/69`; DS `__/2`; app `__/34`; template `__/31`; failed row IDs |

### Credentialed dev1 template-destroy checklist

- [x] Record the implementation commit, UTC timestamp, Go version, Terraform
      version, and sanitized summary path.
- [x] Confirm the runner is pinned to dev1 and the exact master write gate is
      supplied only by the wrapper.
- [x] Confirm all `T01`-`T31` cases exercise the served Terraform resource
      lifecycle and pass the post-destroy independent GET.
- [x] Confirm corrected caching/compression destroy sets top-level
      `configs.status`, `configs.cache.status`, and `configs.compress.status`
      false together and preserves every other field by exact semantic
      verification.
- [x] Confirm all 31 attempted template snapshots are restored.
- [x] Confirm disposable application and template cleanup both pass.
- [x] Confirm the sanitized evidence contains no credential, tenant identity,
      request/response body, or Terraform state.
- [x] Record any failure or blocked cleanup without marking this gate passed.

### Credentialed dev1 live ledger

| Run ID | Date | Commit/toolchain | Gate | Result | Sanitized scope note |
|---|---|---|---|---|---|
| `LIVE-TD-2026-08-06-01` | 2026-08-06 Asia/Taipei | direct curl against dev1 with the same environment credential; disposable unbound template | focused caching/compression API control | **PASS (diagnostic)** | Baseline PUT/GET reported top/cache/compress `true/true/true`. A complete-document PUT changing only top-level status to false returned HTTP 200, but immediate and repeated GETs continued to report `true/true/true`. A coupled PUT setting all three statuses false returned HTTP 200 and GET reported `false/false/false`. Snapshot restore returned 200, template delete returned 200, absence returned 403, and template inventory found zero remaining curl-probe templates. No identity or response body was recorded. |
| `LIVE-TD-2026-08-06-02` | 2026-08-06 15:38-15:39 Asia/Taipei | `f7f05ea45d23a40510132944bd0f05f6b5d5ddb3-dirty-coupled-fix-t05`; Go 1.24.5 | focused corrected G5 `T05` | **PASS** | The served caching/compression Delete path passed in 23.011s, including the independent GET of all three false statuses, exact snapshot restoration, application cleanup, and template cleanup. Sanitized summary: `/tmp/fortiappseccloud-dev-waf-matrix-3526238474.json`. |
| `LIVE-TD-2026-08-06-03` | 2026-08-06 15:42-16:05 Asia/Taipei | `f7f05ea45d23a40510132944bd0f05f6b5d5ddb3-dirty`; Go 1.24.5; Terraform 1.15.2 | G5 complete local + live matrix | **PASS** | Local gate passed, including Terraform CLI in 124.458s. Live: `A=34/34`, `D=34/34`, `T=31/31`, failed `0`; `T05` passed in 14.028s; restorations `99/99` passed; application cleanup passed; template cleanup passed. Sanitized summary: `/tmp/fortiappseccloud-dev-waf-matrix-2651449473.json`. |

### Gate 5 observed result

Direct curl control established the accepted caching/compression API contract:
starting from `true/true/true`, a preserving full-document PUT with top-level,
cache, and compression statuses all false returned HTTP 200 and the next GET
returned `false/false/false`. Snapshot restoration and disposable-template
cleanup also passed.

The generated caching/compression destroy policy therefore owns only `status`,
`cache.status`, and `compress.status`. The shared engine requires all three
boolean fields in the fresh GET, sets them false in the preserving PUT, and
requires the unmodified verification GET to match the complete intended
result. The focused served-resource T05 lifecycle passed, followed by a
complete Gate 5 run with `A=34/34`, `D=34/34`, and `T=31/31`. All 99 attempted
snapshots were restored and both disposable parents were deleted. This
credentialed regression gate is complete and passed.

## 11. Maintenance rule

Any provider change that adds or removes a resource/module must update, in the
same change:

1. provider registration and the exact protocol schema inventory;
2. the app/template contract inventory and generated manifest where applicable;
3. this plan's counts and matrix;
4. a named U-R/U-AM/U-TM subtest for the exact resource;
5. documentation/example contract tests where applicable; and
6. the run ledger after all required gates pass.

A change is not unit-test complete when only the shared engine, only a live
tenant test, or only `go test ./...` package status is available without a
named row for the resource.
