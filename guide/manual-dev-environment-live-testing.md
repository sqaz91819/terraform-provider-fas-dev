# Manual Dev-Environment Live Testing

This guide explains how to build the provider from the current source tree and
exercise it manually against the FortiAppSec Cloud `dev1` environment. It also
explains when to use the repository's automated 99-case WAF matrix instead of a
hand-written Terraform configuration.

The dev API base URL used by this repository is:

```text
https://api.dev1.fortiappsec.com
```

Use that exact value. Include `https://`, and do not append `/v2` or a trailing
API path. The provider adds API paths itself.

> **Safety:** The examples create, update, and delete real objects in the dev
> account. Use only a dev credential and uniquely named disposable objects.
> Never point this procedure at production.

This procedure covers the supported WAF app, origin, module, template, and
template-binding resources. `log_settings` and certificate/private-key/CA/CRL
content upload are intentionally outside provider scope and should not be added
to a manual test configuration.

## 1. Choose the test method

There are two useful ways to perform a dev live test:

| Method | Use it for | Who supplies the test data? |
|---|---|---|
| Manual Terraform sandbox | Learning the provider, debugging one resource, inspecting plans, and testing a specific lifecycle interactively | The operator supplies a unique app/template name and editable `.tf` files |
| Complete dev WAF matrix | Release/regression evidence for all implemented WAF module lifecycles | The test harness generates names, domains, placement, parents, and cleanup automatically |

Start with the manual sandbox when learning or investigating one resource. Run
the complete matrix when the question is whether the entire WAF provider still
passes.

## 2. Prerequisites

### Required software

| Component | Version or requirement | Check command |
|---|---|---|
| Go | **1.23 or newer**. `go.mod` declares Go 1.23. | `go version` |
| Terraform CLI | Use a maintained Terraform 1.x release. This guide uses features available in Terraform 1.5 and later. | `terraform version` |
| Git | Any maintained version | `git --version` |
| Shell | Bash on Linux or WSL is recommended | `bash --version` |
| Network | DNS and HTTPS access to `api.dev1.fortiappsec.com:443` | Check through the normal corporate network/VPN path |

The manual Terraform steps also work on macOS. The complete matrix wrapper is
a Bash/Linux-oriented script and uses commands such as `sha256sum`, `awk`,
`sed`, and `mktemp`; install GNU core utilities or use Linux/WSL if those are
not available.

`jq` is optional. It is not needed for the procedure below, and avoiding raw
JSON output reduces the chance of copying identifiers or sensitive values into
logs.

### Required access and test data

Prepare the following before starting:

- A dev-account API token with permission to create/delete WAF applications
  and templates and to read/write the modules being tested.
- A unique disposable application name.
- A unique disposable protected domain. The accepted automated matrix uses a
  unique subdomain of `example.com` in dev; use a domain approved for your dev
  account if its policy is stricter.
- An origin address safe to reference from dev. `origin.example.com` is used by
  the automated matrix, but an origin controlled by your team is preferable
  when testing connectivity or `precheck = true`.
- A supported platform and logical region. `AWS` and `us-east-1` are examples,
  not a promise that every dev account exposes that pair. Confirm the current
  choices in the dev console if the API rejects placement.

Do not prepare an application endpoint ID. A newly created
`fortiappseccloud_waf_app` returns `ep_id`, and Terraform passes it directly to
dependent resources.

### Repository preflight

From the repository root:

```shell
go version
terraform version
git version
go mod download
go test ./...
go build ./...
git diff --check
```

Run `git status --short` before and after testing. A live test should not hide
unrelated source changes. The full matrix performs a larger local gate,
including generation, race tests, vetting, Terraform CLI tests, and example
format checks.

## 3. Keep credentials out of Terraform files

The preferred authentication method is an API token in the process
environment. Read it without placing it in shell history:

```shell
read -rsp "Dev API token: " FORTIAPPSECCLOUD_API_TOKEN
export FORTIAPPSECCLOUD_API_TOKEN
unset FORTIAPPSECCLOUD_USERNAME
unset FORTIAPPSECCLOUD_PASSWORD
test -n "${FORTIAPPSECCLOUD_API_TOKEN}"
```

The provider also supports username/password authentication through
`FORTIAPPSECCLOUD_USERNAME` and `FORTIAPPSECCLOUD_PASSWORD`, but do not combine
those variables with an API token.

Never put a token or password in:

- `main.tf`, `terraform.tfvars`, or a Terraform CLI configuration file;
- a command-line `-var` argument;
- Git, issue comments, test reports, or copied provider logs.

Terraform state can contain resource configuration and should be treated as
sensitive even though provider credentials are not resource state. Use a
private, disposable working directory.

## 4. Build the current provider source locally

Testing a registry release does not test the current checkout. Build the
provider and expose it through an isolated Terraform filesystem mirror.

From the provider repository root:

```shell
export FAS_PROVIDER_REPO="$(pwd)"
export FAS_LIVE_ROOT="/tmp/fortiappseccloud-dev-live"
export FAS_PROVIDER_VERSION="2.0.0-rc.1"
export FAS_PROVIDER_TARGET="$(go env GOOS)_$(go env GOARCH)"
export FAS_MIRROR_ROOT="${FAS_LIVE_ROOT}/provider-mirror"
export FAS_PACKAGE_DIR="${FAS_MIRROR_ROOT}/registry.terraform.io/sqaz91819/fas-dev/${FAS_PROVIDER_VERSION}/${FAS_PROVIDER_TARGET}"

mkdir -p "${FAS_PACKAGE_DIR}" "${FAS_LIVE_ROOT}/config"
go build -trimpath \
  -o "${FAS_PACKAGE_DIR}/terraform-provider-fortiappseccloud_v${FAS_PROVIDER_VERSION}" \
  "${FAS_PROVIDER_REPO}"
```

The `2.0.0-rc.1` value is a local package label for the mirror. It does not publish
anything and does not have to match a registry release.

Create `${FAS_LIVE_ROOT}/terraform.rc` with the following content. Terraform
CLI configuration does not expand shell variables inside this file, so replace
`/tmp/fortiappseccloud-dev-live/provider-mirror` if `FAS_LIVE_ROOT` is
different.

```hcl
provider_installation {
  filesystem_mirror {
    path    = "/tmp/fortiappseccloud-dev-live/provider-mirror"
    include = ["registry.terraform.io/sqaz91819/fas-dev"]
  }

  direct {
    exclude = ["registry.terraform.io/sqaz91819/fas-dev"]
  }
}
```

Point only this shell at the isolated CLI configuration:

```shell
export TF_CLI_CONFIG_FILE="${FAS_LIVE_ROOT}/terraform.rc"
```

This avoids modifying a user-wide Terraform configuration. After rebuilding
the provider at the same local version, run `terraform init -upgrade` in the
test configuration directory so Terraform refreshes its local installation.
If a checksum error remains, create a fresh disposable test directory or use a
new local semantic version in both the mirror path and `required_providers`.

## 5. Prepare the manual Terraform files

Create the following files in `${FAS_LIVE_ROOT}/config`:

```text
config/
├── .gitignore
├── main.tf
├── terraform.tfvars
├── variables.tf
└── versions.tf
```

### `.gitignore`

```gitignore
.terraform/
.terraform.lock.hcl
*.tfplan
*.tfstate
*.tfstate.*
crash.log
state-before-import.json
terraform.tfvars
```

This is a disposable sandbox policy. In a normal maintained Terraform project,
the dependency lock file is usually committed.

### `versions.tf`

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    fortiappseccloud = {
      source  = "sqaz91819/fas-dev"
      version = "= 2.0.0-rc.1"
    }
  }
}

provider "fortiappseccloud" {
  # Keep the dev hostname explicit. Do not append /v2.
  hostname        = "https://api.dev1.fortiappsec.com"
  timeout_seconds = 300
}
```

The literal dev hostname is intentional: the provider's default hostname is
production, so an explicit value is safer for a destructive dev sandbox. An
equivalent alternative is to omit `hostname` from HCL and export:

```shell
export FORTIAPPSECCLOUD_HOSTNAME="https://api.dev1.fortiappsec.com"
```

Do not set `insecure = true` for a normal dev1 test. If the environment uses an
approved private CA, prefer `cacert_file = "/path/to/approved-ca.pem"`.
`insecure` and `cacert_file` cannot be used together.

### `variables.tf`

```hcl
variable "app_name" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "origin_address" {
  type = string
}

variable "platform" {
  type = string
}

variable "region" {
  type = string
}

variable "certificate_mode" {
  type    = string
  default = "automatic"

  validation {
    condition     = contains(["automatic", "custom"], var.certificate_mode)
    error_message = "certificate_mode must be automatic or custom."
  }
}

variable "manage_csrf" {
  type    = bool
  default = true
}

variable "csrf_status" {
  type    = bool
  default = false
}

variable "csrf_action" {
  type    = string
  default = "alert"
}
```

### `main.tf`

```hcl
resource "fortiappseccloud_waf_app" "manual" {
  app_name         = var.app_name
  domain_name      = var.domain_name
  services         = ["https"]
  https_port       = 443
  platform         = var.platform
  region           = var.region
  cdn              = false
  block_mode       = false
  certificate_mode = var.certificate_mode
  precheck         = false

  initial_origin {
    address  = var.origin_address
    protocol = "https"
    port     = 443
  }
}

resource "fortiappseccloud_waf_csrf_protection" "manual" {
  count = var.manage_csrf ? 1 : 0

  ep_id    = fortiappseccloud_waf_app.manual.ep_id
  template = false

  configs {
    action = var.csrf_action
    status = var.csrf_status
  }
}

output "app_ep_id" {
  description = "Runtime application identity. Do not copy it into reports."
  value       = fortiappseccloud_waf_app.manual.ep_id
  sensitive   = true
}
```

The provider automatically sends `creation_origin = "fas_terraform"` during
application creation. It is not a user-settable Terraform attribute. The dev
backend uses it to create a clean Terraform-owned application without enabling
the usual default modules.

`initial_origin` is creation-only. Use
`fortiappseccloud_waf_origin_servers` for ongoing origin-pool management.

### `terraform.tfvars`

Replace the names with values unique to this run:

```hcl
app_name       = "tf-manual-waf-20260803-yourname"
domain_name    = "tf-20260803-yourname.example.com"
origin_address = "origin.example.com"

platform = "AWS"
region   = "us-east-1"

certificate_mode = "automatic"
manage_csrf       = true
csrf_status       = false
csrf_action       = "alert"
```

Before applying, confirm that no existing application uses `app_name` and that
all values are approved for the dev account. Keep `precheck = false` unless the
domain and origin are intentionally ready for public DNS/connectivity checks.

## 6. Initialize and prove the provider is usable

```shell
cd "${FAS_LIVE_ROOT}/config"
test "${TF_CLI_CONFIG_FILE}" = "${FAS_LIVE_ROOT}/terraform.rc"
test -n "${FORTIAPPSECCLOUD_API_TOKEN}"

terraform fmt -check
terraform init
terraform providers
terraform validate
```

Check that Terraform selected
`registry.terraform.io/sqaz91819/fas-dev` at the exact local version in
`versions.tf`. If `terraform init` tries to install this provider from the
public registry, stop and fix `TF_CLI_CONFIG_FILE`, the mirror path, or the
`linux_amd64`-style target directory before running `plan`.

`terraform validate` loads the provider schema but does not prove that the dev
credential is authorized. The first refreshing `terraform plan` is the first
API-backed check.

## 7. Manual test sequence

### Case 1: Plan and create the application

```shell
terraform plan -out=create.tfplan
terraform apply create.tfplan
terraform state list
terraform state show fortiappseccloud_waf_app.manual
```

Before approving the plan, verify:

- the hostname in `versions.tf` is dev1;
- the application name and domain are the unique disposable values;
- exactly one WAF application and the intended CSRF resource will be managed;
- no pre-existing application or template is being replaced or deleted.

Expected result:

- application create returns a stable `ep_id`;
- the CSRF module is written with `template = false`, `status = false`, and
  `action = "alert"`;
- no certificate, private key, CA, or CRL content is uploaded.

Do not paste the complete `terraform state show` output into an issue. Record
only sanitized values needed to identify the test case.

### Case 2: Refresh and no-drift plan

Run the same configuration again:

```shell
terraform plan -detailed-exitcode
```

The expected exit code is `0` and the expected message is `No changes`. Exit
code `2` means Terraform found a diff; inspect it before continuing. Exit code
`1` means the plan failed.

This step catches response normalization and state-stability problems that a
successful create alone does not catch.

### Case 3: Update one app module

Edit `terraform.tfvars`:

```hcl
csrf_status = true
csrf_action = "alert_deny"
```

Then run:

```shell
terraform plan -out=csrf-update.tfplan
terraform apply csrf-update.tfplan
terraform plan -detailed-exitcode
```

Expected result:

- the plan changes only the CSRF module;
- the apply succeeds;
- the following plan is empty;
- the dev console shows CSRF enabled with the requested action.

Use the console or an approved read-only API client as an independent check.
Do not enable Terraform `TRACE` logging just to inspect HTTP traffic; verbose
logs can contain sensitive context.

### Case 4: Switch certificate-management mode

Edit `terraform.tfvars`:

```hcl
certificate_mode = "custom"
```

Plan and apply, then change it back to `automatic` and repeat:

```shell
terraform plan -out=certificate-custom.tfplan
terraform apply certificate-custom.tfplan
terraform plan -detailed-exitcode
```

After the empty plan, set `certificate_mode = "automatic"` and run another
plan/apply/no-drift cycle.

Expected result:

- the existing application is updated in place;
- `ep_id` remains stable;
- automatic maps to API certificate type `0` and custom maps to type `1`;
- no real certificate material is accepted or uploaded.

The custom-mode test verifies only mode selection. Certificate, key, CA, and
CRL content upload is intentionally unsupported.

### Case 5: Verify module disable-on-destroy while keeping the app

First leave CSRF enabled, then edit `terraform.tfvars`:

```hcl
manage_csrf = false
```

Run:

```shell
terraform plan -out=csrf-destroy.tfplan
terraform apply csrf-destroy.tfplan
terraform state list
```

The plan must destroy only
`fortiappseccloud_waf_csrf_protection.manual[0]`; it must not destroy the app.
The provider performs a fresh GET, preserves the full module response, sets
`template = false` and `configs.status = false`, PUTs that response, verifies a
following GET, and only then forgets the module resource.

Expected result:

- the WAF app remains in Terraform state and in dev;
- the CSRF resource is absent from Terraform state;
- an independent dev-console/API read shows CSRF disabled;
- other CSRF fields, such as the selected action and unowned lists, remain
  preserved.

Set `manage_csrf = true` again and apply to bring the resource back under
Terraform management before testing another change.

This pattern can be used for each app module whose documentation says
`disable-on-destroy`. Some exceptional resources still use
forget-with-warning because they have no independently safe writable status.
Always read the resource's **Destroy Behavior** section under
`website/docs/r/` before interpreting a destroy result.

### Case 6: Optional import check

Import is easiest to verify in a second empty Terraform state. For a quick
disposable-state check, back up the current state, remove only the module
address from state without destroying it, and import it again:

```shell
terraform state pull > state-before-import.json
export FAS_TEST_EP_ID="$(terraform output -raw app_ep_id)"
terraform state rm 'fortiappseccloud_waf_csrf_protection.manual[0]'
terraform import 'fortiappseccloud_waf_csrf_protection.manual[0]' "${FAS_TEST_EP_ID}"
terraform plan -detailed-exitcode
unset FAS_TEST_EP_ID
```

Run this only in the disposable sandbox. `terraform state rm` does not change
the remote module, but it does remove Terraform's ownership record until the
import succeeds. Keep `state-before-import.json` private because it is a state
backup.

Expected result: import hydrates the module by application `ep_id`, and the
following plan is empty. App resources can be imported by stable `ep_id` or a
unique legacy app name; template modules are imported by `template_id`.

### Case 7: Final destroy and cleanup

Ensure all temporarily removed resources are managed again, then create and
review a destroy plan:

```shell
terraform plan -destroy -out=destroy.tfplan
terraform apply destroy.tfplan
terraform state list
```

Expected result:

- dependent resources are handled before the parent;
- the disposable application is deleted;
- `terraform state list` is empty;
- the dev console or an independent read confirms the application is absent.

Do not delete the local state or test directory until remote absence is
confirmed. If destroy fails, keep the state, inspect the exact remaining
object, retry the scoped operation, and confirm cleanup before starting another
live test.

## 8. Optional template CRUD and template-module test

Add the following variables to `variables.tf`:

```hcl
variable "template_name" {
  type = string
}

variable "template_csrf_status" {
  type    = bool
  default = false
}

variable "template_csrf_action" {
  type    = string
  default = "alert"
}
```

Add unique values to `terraform.tfvars`:

```hcl
template_name        = "tf-manual-template-20260803-yourname"
template_csrf_status = false
template_csrf_action = "alert"
```

Create `template.tf`:

```hcl
resource "fortiappseccloud_waf_template" "manual" {
  name = var.template_name
}

resource "fortiappseccloud_waf_template_csrf_protection" "manual" {
  template_id = fortiappseccloud_waf_template.manual.template_id

  configs {
    action = var.template_csrf_action
    status = var.template_csrf_status
  }
}
```

Run the same lifecycle:

1. plan and apply the template plus module;
2. require an empty second plan;
3. change status to `true` and action to `alert_deny`;
4. plan, apply, and require another empty plan;
5. optionally import the base template by `template_id` in a disposable state;
6. destroy the template module and base template;
7. independently verify that the unique template name is absent.

Important template behavior:

- `fortiappseccloud_waf_template` owns template CRUD and stable `template_id`.
- Changing the template name replaces it because the API has no rename
  operation.
- Template creation starts with no application endpoints.
- App/template membership belongs to the separate
  `fortiappseccloud_waf_template_attachment` resource.
- The 31 template-module resources disable on destroy. Deleting a
  template-module resource preserves the complete result, sets
  `template=false` and its reviewed status fields, PUTs, verifies, and then
  removes Terraform state. Caching/compression requires top-level, cache, and
  compression statuses to be false together. Deleting the disposable parent
  template separately cleans up the template itself.

To test binding, add:

```hcl
resource "fortiappseccloud_waf_template_attachment" "manual" {
  ep_id       = fortiappseccloud_waf_app.manual.ep_id
  template_id = fortiappseccloud_waf_template.manual.template_id
}
```

The attachment resource owns only this app/template membership. Its destroy
removes the managed app from the template without deleting either parent.
Import uses `template_id:ep_id`.

To test app-module inheritance after attaching the template, change the app
CSRF resource to:

```hcl
resource "fortiappseccloud_waf_csrf_protection" "manual" {
  count = var.manage_csrf ? 1 : 0

  ep_id    = fortiappseccloud_waf_app.manual.ep_id
  template = true

  depends_on = [fortiappseccloud_waf_template_attachment.manual]
}
```

When `template = true`, remove the `configs` block. When switching back to
`template = false`, restore the block. The switch applies only to this module;
it does not change another module's independent template switch.

## 9. Optional ongoing origin-server test

The app's `initial_origin` bootstraps creation and is replacement-only. To test
the mutable `/waf/apps/{ep_id}/servers` configuration, add a separate
`fortiappseccloud_waf_origin_servers` resource:

```hcl
resource "fortiappseccloud_waf_origin_servers" "manual" {
  ep_id = fortiappseccloud_waf_app.manual.ep_id

  server_pools {
    name = "default_pool"

    health {
      enabled = false
    }

    persistence {
      type = "disable"
    }

    servers {
      address          = var.origin_address
      port             = 443
      ssl              = true
      encryption_level = "mozilla_intermediate"
      status           = "enable"
      type             = "domain"
      weight           = 1
    }
  }
}
```

If `origin_address` is an IP literal, set `type = "ip"`. Confirm the account's
accepted encryption policy before applying. Test create/read, change `weight`
to `2`, require a no-drift plan, and optionally import by app `ep_id`.

Origin-server destroy is currently forget-with-warning: it does not rewrite
the remote pool because a universally safe replacement pool has not been
established. The pool disappears when the disposable parent app is deleted.

## 10. Testing another WAF module manually

Use the generated documentation in `website/docs/r/` as the schema reference.
For example:

- app module: `website/docs/r/waf_known_attacks.html.markdown`;
- template module: `website/docs/r/waf_template_known_attacks.html.markdown`;
- custom module: the corresponding `waf_<name>.html.markdown` file.

Copy the documented resource, replace its hard-coded app identity with:

```hcl
ep_id = fortiappseccloud_waf_app.manual.ep_id
```

For an app module:

- `template = false` requires a `configs` block;
- `template = true` forbids a `configs` block;
- omitted optional ownership wrappers preserve their complete remote arrays;
- an explicitly present empty ownership wrapper usually means send an empty
  collection;
- cross-field rules generated from `x-fortinet-cross-field-v1` should fail at
  Terraform validation/plan time before any PUT.

For each module, record these separate results:

1. initial configuration apply;
2. independent remote observation;
3. configuration update;
4. empty follow-up plan;
5. import hydration;
6. the documented destroy policy;
7. restoration or disposable-parent cleanup.

Passing one module does not prove that another module with a different API
schema passes.

## 11. Run the complete automated dev WAF matrix

The repository already contains the broad regression campaign described in
`plan/2026-07-29-waf-complete-live-test-plan.md`. It runs 99 fixed evidence
cases covering app configuration, app-module destroy behavior, and template
module configuration. It also creates and deletes its own disposable
application/templates, selects a supported placement from dev settings,
restores snapshots, and writes a sanitized mode-`0600` summary.

Only the dev API token is required from the operator:

```shell
cd "${FAS_PROVIDER_REPO}"
read -rsp "Dev API token: " FORTIAPPSECCLOUD_API_TOKEN
export FORTIAPPSECCLOUD_API_TOKEN
unset FORTIAPPSECCLOUD_HOSTNAME

./scripts/run-dev-waf-matrix.sh
```

The wrapper pins the run to
`https://api.dev1.fortiappsec.com`, supplies the exact internal master write
gate, and refuses a conflicting hostname override. It can take a long time;
its acceptance-test timeout is 180 minutes. Do not interrupt it after remote
parent creation unless necessary, because restoration and cleanup are part of
the run. The matrix compiles the provider into its Go test process, so it does
not use the manual sandbox's filesystem mirror or `TF_CLI_CONFIG_FILE`.

To run only its non-live checks:

```shell
./scripts/run-dev-waf-matrix.sh --local-only
```

The wrapper runs `go generate ./...`, so start from a known worktree and inspect
`git diff` afterward. A generation diff is source output to review, not live
test evidence.

Matrix success requires all of the following, not only a zero exit from one
module:

- the local generation/test/race/vet/build/CLI/format gates pass;
- all 99 evidence rows pass;
- every attempted module snapshot is restored;
- the disposable application and templates are absent;
- the sanitized summary is produced.

Use the manual sandbox for a focused reproduction. Use the matrix result for a
claim that the complete implemented WAF surface passed.

## 12. Troubleshooting

### Terraform tries to download the provider

Check all three values:

```shell
test -f "${TF_CLI_CONFIG_FILE}"
test -x "${FAS_PACKAGE_DIR}/terraform-provider-fortiappseccloud_v${FAS_PROVIDER_VERSION}"
terraform providers
```

The source address, exact version, mirror version directory, target directory,
and binary suffix must agree.

### Authentication returns 401 or 403

- Confirm the token belongs to dev, has not expired, and has WAF write scope.
- Confirm username/password variables are unset when token auth is used.
- Do not print the token while debugging.
- A 403 on only one operation can mean the token lacks that operation's scope,
  even if application reads work.

### Requests reach the wrong environment or return a base-path 404

Use exactly:

```text
https://api.dev1.fortiappsec.com
```

Do not use the production default, and do not append `/v2`. In the manual
sandbox, keep the literal dev hostname in the provider block. The full matrix
independently pins and verifies dev1.

### Application creation rejects placement

The example `AWS`/`us-east-1` pair may not be enabled for every account or may
change. Select a platform/logical-region pair shown by the dev WAF settings or
console. The full matrix discovers and selects a supported pair automatically.

### Application or template name already exists

Stop and choose a new unique name. Do not import, update, or delete an existing
object merely to make a disposable create test pass. The full matrix refuses
pre-existing names before mutation.

### A second plan is not empty

Do not accept repeated drift. Check:

- whether someone changed the same remote object in the dev console;
- whether command-line variables differ from `terraform.tfvars`;
- whether an omitted collection means preserve while an empty wrapper means
  clear;
- whether the API canonicalizes aliases, ordering, or null collection slots;
- whether the local provider binary was rebuilt after the source change.

Save a sanitized plan description and identify the exact changing attribute.
Avoid attaching full raw state or API bodies.

### Apply times out or is interrupted

The provider timeout may be set from 1 to 3600 seconds. Increase
`timeout_seconds` only when the backend operation is known to be slow. Before
retrying, inspect Terraform state and use a read-only dev console/API check to
determine whether the remote object was already created or updated.

Keep the state file. Import a successfully created object when appropriate, or
destroy only the uniquely named disposable object. Never start a second writer
against the same app while the first run may still be active.

### TLS verification fails

Confirm the system clock, VPN/proxy, and normal dev certificate chain first. If
an approved private CA is required, configure `cacert_file`. Use
`insecure = true` only for an explicitly trusted temporary endpoint and never
carry that setting into production configuration.

## 13. Recording and closing the test

Record a small, sanitized test result containing:

- UTC date/time and `dev1` environment;
- Git commit and whether the worktree was dirty;
- `go version` and `terraform version`;
- resource/test-case names and pass/fail result;
- whether the follow-up plan was empty;
- whether restoration and parent cleanup were independently verified.

Do not record the API token, passwords, request headers, full state, full API
bodies, application endpoint ID, or template ID.

After remote cleanup is confirmed:

```shell
unset FORTIAPPSECCLOUD_API_TOKEN
unset FORTIAPPSECCLOUD_HOSTNAME
unset TF_CLI_CONFIG_FILE
unset FAS_TEST_EP_ID
```

Then remove the disposable local test directory using a scoped path you have
verified. Do not remove the directory before checking remote cleanup; the state
is the recovery record if a destroy operation fails.
