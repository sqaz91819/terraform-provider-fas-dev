# FortiAppSec Cloud Terraform Provider — Claude Recovery Guide

This file is the durable entry point for continuing work after context compaction, a new session, or a complete loss of conversation history.

## Mandatory context recovery

Before changing code:

1. Read [`progress/CURRENT.md`](progress/CURRENT.md) for the concise current state, verification record, working-tree status, and recommended next step.
2. Read the latest detailed progress records:
   - [`progress/2026-07-29-waf-app-module-disable-on-destroy.md`](progress/2026-07-29-waf-app-module-disable-on-destroy.md);
   - [`progress/2026-07-29-waf-app-certificate-mode.md`](progress/2026-07-29-waf-app-certificate-mode.md).
3. Read [`plan/2026-07-10-fortiappseccloud-terraform-full-waf-support-revised-design.md`](plan/2026-07-10-fortiappseccloud-terraform-full-waf-support-revised-design.md) for the complete v2 roadmap and locked architectural decisions.
4. Read the focused historical slice plans only when their subsystem is relevant:
   - [`plan/graceful-floating-babbage.md`](plan/graceful-floating-babbage.md) — historical account-takeover/Framework/mux slice.
   - [`plan/2026-07-06-fortiappseccloud-terraform-full-waf-support-design.md`](plan/2026-07-06-fortiappseccloud-terraform-full-waf-support-design.md) — original design, retained for history.
5. Run `git status --short` and inspect the current diff before editing. The CSRF/URL-access generator implementation was committed as `5ceb51f`; never assume the working tree is still clean or that later progress is committed.

The 2026-07-10 revised design supersedes the 2026-07-06 design for implementation. The latest progress document supersedes older progress documents for current counts and status. Do not restore stale resource counts or statements from historical files.

## Current project state

The provider is on branch `tf_ver2` and is served directly as a protocol-5 Plugin Framework provider. The temporary SDKv2/Framework mux has been removed.

Framework owns 69 registered resources: the previous 37 app-scoped resources, one base `waf_template` lifecycle resource, twenty-five generated typed template modules, and six hand-written typed template modules. The two legacy public names remain unchanged and have protocol-5 schema-version upgrades from representative v1.0.5-shaped state. Inactive SDKv2 source and the SDK acceptance-test helper remain in the repository, but SDKv2 resources are not registered or served.

The disposable Phase 2 application vertical passed its complete live create/update/no-op/import/destroy gate on 2026-07-22, including four dependent resources and verified cleanup. The follow-on complete dev1 matrix passed every app and all 31 typed template-module apply/update/no-op/import lifecycles. `waf_app.certificate_mode` supports authoritative `cert_type` automatic/custom switching without certificate content and passed its separately gated dev1 lifecycle. The app-module disable framework has 29 active guarded `configs.status` disables; app caching/compression, global trust list, and content routing remain ineligible for that exact app lifecycle. All 31 typed template modules use a separate guarded disable-on-destroy policy: thirty set `configs.status=false`, while caching/compression uses the curl-verified coupled top-level/cache/compression false values. The served runtime preserves and verifies the complete result. Captured v1 migration testing remains separately gated and its test code must stay intact. Do not resume certificate upload, `log_settings`, unrelated module, or data-source breadth without new user direction. See `progress/CURRENT.md` and `guide/waf-v2-live-testing.md` for exact gates, limitations, and verification status.

The generator is multi-resource, schema/policy-driven, deterministic, and supports the reviewed module shapes used by all twenty-five generated app/template pairs: integer config scalars and item fields with reviewed `minimum`/`maximum` ranges (enforced in schema, build, and response decode); optional item fields with `use_state_for_unknown` that preserve prior state on update and fall back to a reviewed non-boolean default only on first create (GraphQL integer defaults and known_attacks nested `type` default); scalar-string-array collections with reviewed `required` flags (a missing owned remote array fails closed); collectionless configs; per-collection item schemas with different shapes; nested-object item fields (`SingleNestedBlock` sub-objects) with recursive one-level unknown-key fail-closed validation; nested array-of-objects item fields (`SingleNestedBlock` ownership wrappers containing `ListNestedBlock` `item` blocks inside items, one level deep) reusing the ownership omission/empty/populated semantics; integer-enum config scalars; optional integer item fields; optional config scalars whose response decode distinguishes a missing key (stable null state) from an explicit JSON null (accepted only when the pinned schema or an exact reviewed response-only compatibility policy permits it; required scalars still reject missing); OpenAPI readOnly config scalars rendered as computed-only Terraform state; strict `x-fortinet-cross-field-v1` conditional-range and integer-comparison validation; exact reviewed response enum aliases that normalize to documented Terraform values; string `minLength`/`maxLength` on config scalars (enforced in schema and response decode) and item fields (enforced in schema, build, and response decode); unbounded object-item collections (`MaxItems: 0`, no `SizeAtMost` validator, no max-items diagnostic); unindexed item schemas (no positional `idx`; items send in Terraform order and decode in order without idx validation/sort, identity is the whole object, fail-closed unknown keys still apply); and item-level scalar-string-array fields (`SingleNestedBlock` ownership wrappers inside items carrying a synthetic string attribute, reusing the scalar-string-array omission/empty/populated semantics one level deep). Nested-object item fields decode with parent-and-child requiredness: a missing required nested object is rejected, a missing optional nested sub-field is accepted, and an explicit null is accepted only for nullable or wire-nullable fields. Collection-item optional fields distinguish a missing key (omission) from an explicit null (rejected unless the field is nullable or wire-nullable). Generated documentation examples include required boolean and nested-block item fields and document scalar-string arrays, required item fields, ordinary optional booleans, read-only fields, and cross-field rules. The complete public WAF matrix contains 256 classified public operations and six non-public operations. Twenty-five manifest module definitions generate fifty typed resources, zero operations are `selected_next`, and the manifest intentionally has no `next_generated_resource` field.

## Sources of truth

Use these in this order:

1. Pinned OpenAPI bytes: `openapi_spec/openapi.json`. This is the single source
   of truth for API paths, request/response schemas, wire names, defaults,
   enums, bounds, nullability, read-only fields, and cross-field validation.
2. Exact reviewed contracts: `internal/contract/`. These pin selected OpenAPI
   facts as drift guards; they must not introduce API schema facts.
3. Reviewed Terraform policy: `internal/generator/profile/waf/overrides.json`
   and `overrides.go`. This owns Terraform naming, ownership, sensitivity,
   lifecycle, and presentation only; it must not enrich the API schema.
4. Deterministic normalized manifest: `internal/generator/manifest/waf_modules.generated.json`.
5. Generated resources/docs, which must match generator output exactly.
6. Progress records for observed local/live verification provenance.

Pinned OpenAPI facts:

- Version: `26.3.a`.
- SHA-256: `463015364e7d4d7cbd8f346a2e238928d1c7c741271656fec06bd8ed87e58e63`.
- 262 WAF operations total: 256 public and six tagged `Non Public`.

The template-create response is now pinned in OpenAPI 26.3.a. It requires
`201 Created`, `Location: /v2/waf/template/{template_id}`, and
`result.template_id`. The exact contract has dev live provenance; do not infer
production support until production deploys it and a separately authorized
production lifecycle passes.

An approved OpenAPI checksum update must not silently change provider behavior. Exact reviewed defaults, enums, string limits, patterns, and collection bounds are separately pinned in the generated-resource contracts and validated during generation. Cross-field rules are machine-readable through `x-fortinet-cross-field-v1`; the generator parses the closed v1 grammar strictly and emits Terraform configuration, apply-path, response, and documentation checks. If a wire-schema fact is missing or incorrect, fix the canonical OpenAPI and update its reviewed checksum; do not add a second schema source or a provider-side schema enrichment.

### Aligning schema facts

OpenAPI 26.3.a is the sole machine-readable API source. Do not override it with
an older release assumption or encode an API-schema fact in Terraform policy.

- **Requiredness of nested-object sub-fields.** A parent object can be required while every nested sub-field is optional (e.g. `SignatureBasedExceptionRule` marks `cookie` required, but `SignatureBasedExceptionCookie` has `required: []`). The OpenAPI `required` arrays for parent and child are independent; never infer child requiredness from the parent or vice-versa. This inversion was a real, repeated defect.
- **`nullable` vs wire-nullable.** Confirm whether a field is genuinely `nullable` in OpenAPI 3.0 before treating an explicit JSON `null` as accepted. An optional-but-non-nullable field (e.g. JSON `md5`, HTTP `header_value`) must reject an explicit null, while a nullable field (e.g. CSRF `name`/`value`) accepts it.
- **Defaults, enums, length bounds, and `idx` defaults** when the OpenAPI representation is unclear or differs from backend behavior.
- **Integer and cross-field bounds.** Use ordinary OpenAPI `minimum`/`maximum` for unconditional bounds and `x-fortinet-cross-field-v1` for conditional ranges or comparisons. If a future proven backend constraint is absent, fix OpenAPI first; do not silently hard-code it in a generated resource or override.
- **Source-requiredness vs Terraform-policy requiredness.** An item field can be `required` in the pinned OpenAPI (source-required: a missing response key is malformed) while its Terraform policy is `optional_computed` with a provider default. These are independent: the render model carries `SourceRequired` (wire-requiredness) separately from `Required` (Terraform policy). A source-required field rejects a missing decode key (e.g. CSRF `filter`); a source-optional field with a provider default decodes a missing key to the reviewed default (e.g. `value_check`→false, known_bots item `status`→true). Do not infer one from the other.

Before changing a contract, profile field, or decode/build helper, inspect the
exact request/response schema graph in `openapi_spec/openapi.json`, including
its `required`, `nullable`, `readOnly`, defaults, enums, ranges, collection
bounds, and `x-fortinet-cross-field-v1` rules. Pin the selected facts in
`internal/contract/`; keep Terraform-only behavior in the reviewed profile.
Never guess an absent or ambiguous API fact—correct OpenAPI first and update
the checksum in the same reviewed change.

### Review discipline (lessons from the codex review cycle)

Slices are most often rejected for test/docs gaps and "tests that pass for the wrong reason," not core logic. Before requesting a review:

- A negative ("rejects X") test needs a matching **in-range/valid control** that succeeds, proving the failure is the validator (not an HCL parse error such as a duplicate attribute).
- A missing-optional test should assert the decoded reviewed default (false/true), not just "no diagnostic."
- `idx`-absent and required-item-field-in-example checks must cover **every** collection and **every** required item field, not one representative.
- A new render-model flag must be consumed in **all four** sites (schema, build/encode, decode, docs) and gate its import; wiring only the schema path is incomplete.
- When the generated-resource count changes, update the lifecycle-test regex in the verification block of **both** `CLAUDE.md` and `progress/CURRENT.md`, not just the prose counts.
- Run the `generator-constraints` skill's pre-codex self-review checklist before requesting a review.

## Non-negotiable security rules

- Never read `fortiappsec_api_key.txt`, `fortiappsec_api_key_location.txt`, `api_request_format.txt`, or any credential-related file.
- Never print, log, persist, or place credential values into diagnostics, generated files, examples, progress documents, tests, or chat.
- Tests use local dummy literals only. Live credentials may come from environment variables only.
- Never log complete sensitive request or response bodies.
- TLS verification remains enabled by default. Insecure TLS is an explicit opt-in only.
- `api_token`, passwords, certificate contents, private keys, and secret fields must remain sensitive and redacted.
- Do not run live API requests, acceptance tests, or credentialed probes unless the user explicitly authorizes that exact activity.
- Live PUT probes require `TF_ACC=1`, a user-named disposable endpoint, an exact endpoint-specific or fixed-suite write opt-in, a reviewed plan, an in-memory complete snapshot, and unconditional restoration. Restoration failure is the primary failure. The only fixed-suite gate is the static serial all-module campaign documented in `guide/waf-v2-live-testing.md`.
- Existing CSRF write authorization is endpoint-specific: `FORTIAPPSECCLOUD_ALLOW_CSRF_PUT=csrf_protection:<ep_id>`. It grants no permission for URL access or any other endpoint.
- URL access live provenance on 2026-07-16 now includes both the sampled non-template empty-list lifecycle and one corrected populated lifecycle. The supplied specification and pinned OpenAPI omitted backend-required `url_type`; reviewed production v2 backend evidence identified `string|regex` as required, and the generator now injects it as explicit required Terraform intent. An authorized one-rule `url_type=string` apply succeeded, returned `idx=1` with no unknown item keys, produced no-op and import/no-op plans, preserved status, cleared back to the original empty list, restored the complete envelope exactly, and was followed by an independent empty-list GET. Multi-rule ordering, `url_type=regex`, other rule combinations, disable, destroy, and template behavior remain unverified. Any future URL-access write still requires a separately reviewed exact endpoint-specific gate and saved plan.

## Architectural invariants

- Keep Go at 1.23 unless a separate migration is approved.
- Keep Terraform Plugin Framework v1.13.0 and protocol 5 stable during the migration.
- Keep the test-fork provider address `registry.terraform.io/sqaz91819/fas-dev` and `terraform-registry-manifest.json` protocol unchanged.
- Do not add dependencies without a demonstrated need and explicit review.
- Preserve unknown API fields with GET–merge–PUT–GET. A fresh GET is required before every PUT.
- Use the descriptor-driven runtime in `internal/resources/wafmodule/`; do not duplicate endpoint lifecycle logic in generated resources.
- Use published wire paths under `/waf/apps/{ep_id}/...`. Do not introduce internal aliases without an explicit tested mapping.
- `template = false` requires `configs`; `template = true` forbids `configs`. Template-inherited state keeps `configs` null while replaying the complete effective wire request as required by the runtime.
- Template module resources have `template_id` plus a required typed `configs`
  block and expose neither app `ep_id` nor the app inheritance `template`
  switch. Their runtime always writes `template=false`, shares the
  `waf-template:<template_id>` lock with template membership/lifecycle, and
  uses GET–merge–PUT–GET.
- Protocol-5 collection ownership uses `SingleNestedBlock` wrappers containing `ListNestedBlock` `item` blocks. Never emit `ListNestedAttribute`.
- Omitted collection wrapper: preserve the complete opaque remote array and keep state null.
- Present empty wrapper: send `[]`.
- Present populated wrapper: replace the complete ordered array in Terraform order.
- Wire-only `idx` is never exposed in Terraform state. Generate sequential one-based indices on write, validate and sort by `idx` on owned/imported reads, reject invalid/duplicate indices, and preserve omitted arrays opaquely. Every reviewed item schema pins `idx` default 1 except `GraphQLProtectionRule`, whose pinned `idx` carries no default, and `file_protection`'s `custom_file_types` item and its nested `file_content_match_rule` sub-item, whose pinned `idx` carries default 0. The generator accepts the no-default shape for GraphQL only and the zero-default shape for file_protection's custom_file_types/file_content_match_rule only (the runtime always writes one-based indices and rejects non-positive idx on read, so the zero default is a source-schema fact only); it requires default 1 for every other resource/collection so a schema change that drops or changes the default is detected as drift.
- Unknown nested item keys fail closed when Terraform owns or imports the collection. The fail-closed unknown-key check is recursive one level into nested-object item fields: a remote nested object carrying an unsupported key is rejected, not silently ignored.
- Configs scalar and item-field constraints pinned in the reviewed contract (integer `minimum`/`maximum`, string `maxLength`/`minLength`, enums, `nullable`) must propagate through the render model into both schema-level validators and imperative build/decode checks. Nullable optional config scalars decode a null remote value to stable null state (`*string`) instead of a malformed-result error; the PUT patch path keeps the non-pointer type so omission preserves the remote value.
- Scalar-string-array collections carry a reviewed `required` flag. A required array that Terraform owns fails closed when the remote key is absent instead of being silently coerced to `[]`; a present empty array still decodes cleanly.
- Every writable module must have an explicit reviewed destroy policy. Do not generalize destroy semantics between modules:
  - account takeover uses its separately verified disable behavior;
  - OpenAPI validation uses its separately reviewed disable-and-clear behavior;
  - twenty-four generated app resources have an active standalone
    `configs.status` disable; app caching/compression remains ineligible because
    its three statuses are coupled;
  - anomaly detection, CORS, custom rule, IP protection, and ML API protection
    have active status disables; global trust list and content routing are
    ineligible for the standard app envelope lifecycle;
  - an active app-module disable must perform fresh GET, preserve the complete
    response, set only `template=false/configs.status=false`, PUT, and GET with
    complete semantic verification. Missing, null, or non-boolean status and
    any unowned-field change fail closed;
  - all thirty-one template module resources use guarded disable-on-destroy.
    They preserve the complete template result, apply their reviewed disable
    status fields, PUT, and verify the normalized GET. Thirty set only
    `template=false/configs.status=false`; caching/compression also sets
    `configs.cache.status=false/configs.compress.status=false`; IP protection
    additionally applies its reviewed GET-to-PUT normalization.
- Process-local keyed locking prevents same-process interleaving only. The API has no ETag/revision contract, so cross-process last-writer-wins races remain possible.
- Resource identity is stable `ep_id` unless a reviewed specialized resource defines a composite import identity.

## Generator rules

- Never edit files marked `Code generated; DO NOT EDIT.` directly. Change the contract, reviewed profile, render model, or templates, then run `go generate ./...`.
- Generated output must be byte-deterministic and gofmt-clean.
- Presentation-only helpers belong in `internal/generator/render_model.go`, not in the JSON manifest.
- Keep resource rendering data-driven. Do not add per-resource full-template branches.
- Config/item enum symbols and pattern symbols must remain collision-safe.
- Collection bounds must be attached independently to each ownership wrapper.
- Imports must reflect emitted features so a newly supported resource shape cannot generate unused imports.
- The generator must fail rather than guess on unsupported schema constructs, ambiguous mappings, collisions, missing reviewed policy, GET/PUT incompatibility, unclassified public operations, or unsupported custom resource shapes.
- Constraint/default/null metadata pinned in the contract must flow end-to-end: `ItemFieldRender` and `ScalarRender` carry `use_state_for_unknown`, non-boolean defaults, integer `Min`/`Max`, `MinLength`/`MaxLength`, and `AllowNull`; the schema expressions, imperative validators, and decode paths all consume them. Never drop a reviewed constraint during rendering.
- Backend field enrichments must remain path-driven and provenance-backed, preserve the pinned OpenAPI graph separately, reject collisions/drift, and appear explicitly as `backend_enriched` fields in the manifest; never patch generated templates per resource.
- A future generated resource must have its own exact reviewed contract, policy, provenance, tests, and classification transition. Do not invent a third candidate merely to keep a pipeline populated.
- Implement one reviewed endpoint slice at a time; never generate the entire API surface in one change.

## Provenance rules

- Preserve CSRF live-verification language exactly unless new evidence supersedes it.
- Preserve URL-access live provenance narrowly: the empty-list lifecycle remains verified, and exactly one non-template `url_type=string` rule was verified with preserved status, `idx=1`, no unknown item keys, no-op convergence, import/no-op, clearing back to empty, exact restoration, and an independent empty-list GET. OpenAPI 26.3.a now carries `url_type` natively. Do not generalize the live evidence to multiple rules, ordering beyond one item, `url_type=regex`, other combinations, template behavior, status=false disable, or destroy.
- Distinguish OpenAPI facts, local mock/Terraform CLI facts, and live observed facts.
- Do not promote assumptions into provenance.
- When a live probe is authorized, report only sanitized structural facts; do not include credentials, complete bodies, endpoint-sensitive data, or synthetic secret values.

## Verification required before declaring a slice complete

Run without live credentials or write gates unless the user separately authorizes live work:

```text
go generate ./...
go test ./...
go test -race ./internal/...
go vet ./...
go build ./...
TF_CLI_TEST=1 go test . -run '^(TestTerraformCLIGeneratedCSRFLifecycle|TestTerraformCLIGeneratedURLAccessLifecycle|TestTerraformCLIGeneratedRequestLimitsLifecycle|TestTerraformCLIGeneratedKnownAttacksLifecycle|TestTerraformCLIGeneratedHttpHeaderSecurityLifecycle|TestTerraformCLIGeneratedGraphQLProtectionLifecycle|TestTerraformCLIGeneratedJSONProtectionLifecycle|TestTerraformCLIGeneratedParameterValidationLifecycle|TestTerraformCLIGeneratedWebSocketSecurityLifecycle|TestTerraformCLIGeneratedInformationLeakageLifecycle|TestTerraformCLIGeneratedDDoSPreventionLifecycle|TestTerraformCLIGeneratedCookieSecurityLifecycle|TestTerraformCLIGeneratedKnownBotsLifecycle|TestTerraformCLIGeneratedBotDeceptionLifecycle|TestTerraformCLIGeneratedBiometricsBasedDetectionLifecycle|TestTerraformCLIGeneratedWaitingRoomLifecycle|TestTerraformCLIGeneratedMITBProtectionLifecycle|TestTerraformCLIGeneratedThresholdDetectionLifecycle|TestTerraformCLIGeneratedMLBotDetectionLifecycle|TestTerraformCLIGeneratedFileProtectionLifecycle|TestTerraformCLIGeneratedMobileAPIProtectionLifecycle|TestTerraformCLIGeneratedXMLProtectionPolicyLifecycle|TestTerraformCLIGeneratedRewritingRequestsLifecycle|TestTerraformCLIGeneratedAPIGatewayLifecycle|TestTerraformCLIGeneratedCachingCompressionLifecycle)$' -count=1 -v
TF_CLI_TEST=1 go test . -run '^TestTerraformCLIGeneratedKnownBotsOmissionPreservesItemStringArray$' -count=1 -v
TF_CLI_TEST=1 go test . -run '^TestTerraformCLITemplateAndGeneratedModuleLifecycle$' -count=1 -v
TF_CLI_TEST=1 go test . -run '^TestTerraformCLIApplicationCertificateModeLifecycle$' -count=1 -v
terraform fmt -check -recursive examples
git diff --check
```

Also verify:

- a second `go generate ./...` produces identical bytes;
- manifest counts remain 256 public, six non-public, and twenty-five generated resources;
- no operation remains accidentally `selected_next`;
- generated Go contains no `ListNestedAttribute`;
- provider/registry resource names are unique and exact and no mux dependency/import remains;
- integer item fields render `int64validator.Between` and `use_state_for_unknown`; config and item string fields render reviewed `minLength`/`maxLength`; nullable optional config scalars decode null to stable null state; nested-object decode rejects unknown keys; required scalar-string-arrays fail closed when the remote key is absent; the `idx` no-default exception is scoped to GraphQL only;
- CSRF behavior and provenance did not regress;
- URL-access provenance contains only the verified empty-list lifecycle and the exact sampled one-rule `url_type=string` apply/no-op/import/clear/restore facts; multi-rule ordering, regex, other rule combinations, disable/destroy, and template claims remain explicitly unverified;
- no credential file, live endpoint, dependency, commit, push, issue, merge request, or release was used without explicit authorization.

## Git and external actions

- Do not discard, reset, overwrite, or clean the current working tree. It contains the active implementation.
- Do not commit, push, create a branch, create an issue, open a merge request, approve, merge, or publish anything unless the user explicitly asks for that exact external action.
- Before any destructive or outward-facing action, inspect the target and confirm when required.

## Whole-roadmap priorities

The complete roadmap is in the revised design. The current work order is intentionally narrower:

1. Keep `progress/CURRENT.md` and the public-operation inventory truthful; local implementation is not live verification.
2. Keep captured v1.0.5 migration testing temporarily paused without deleting or weakening its implementation.
3. Preserve the passed application vertical and 26-module campaign evidence without generalizing it to untested fields, enum members, collection shapes, or template behavior.
4. Keep the pre-existing-application regression tests outside the required flow; run them only under separate target-specific authorization.
5. Run the separately gated descriptor-driven enable-to-disable lifecycle for
   exactly one selected candidate before promoting only that app module from
   `forget` to `disable`.
6. Resolve or explicitly contract the public API limitation that prevents refreshing global-versus-continent CDN placement.
7. Wait for new user direction before starting certificate-content upload,
   broader data-source, migration, live certificate-mode, or any selected live
   app-module disable work.

The next recommended slice is recorded in `progress/CURRENT.md`. Re-evaluate it against the current diff and user direction before starting.
