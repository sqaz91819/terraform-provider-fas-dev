# Local Testing of the FortiAppSecCloud Terraform Provider

This directory lets you manually test the **unpublished** FortiAppSecCloud
Terraform provider **directly from this repository** using the Terraform CLI,
without publishing it to the public Terraform Registry.

It uses Terraform's **`dev_overrides`** mechanism: `terraform plan/apply`
loads the provider binary you just built from this source tree, instead of
downloading `sqaz91819/fas-dev` from the registry.

> This is the "manual Terraform CLI" testing path. It targets a **dev/test
> environment** (`dev1` by default) with a disposable application. Never point
> it at production unless you explicitly intend to.

---

## 1. Prerequisites

| Component | Requirement |
|---|---|
| Go | **1.23 or newer** (`go mod` declares Go 1.23). Check: `go version` |
| Terraform CLI | A maintained Terraform 1.x (this project is tested on 1.15.x). Check: `terraform version` |
| Git | `git --version` |
| Network | HTTPS access to your target API host (`api.dev1.fortiappsec.com`). May require corporate VPN. |
| Access | A **dev/test** API token able to create/delete WAF applications & modules, plus an approved disposable domain and origin. |

---

## 2. Quick start (TL;DR)

```shell
# 1) In the provider repository root, do a quick sanity build
cd GlobalAndWAF/third-party-integration/terraform-provider-fortiappseccloud
go build ./...

# 2) Build the provider binary + write the dev_overrides file
cd examples/test
./setup.sh

# 3) Load the dev_overrides in this shell
export TF_CLI_CONFIG_FILE="$(pwd)/dev.tfrc.local"

# 4) Set your token (never in a file, never in git)
read -rsp "Dev API token: " FORTIAPPSECCLOUD_API_TOKEN; export FORTIAPPSECCLOUD_API_TOKEN; unset FORTIAPPSECCLOUD_USERNAME FORTIAPPSECCLOUD_PASSWORD

# 5) Open main.tf and fill in the values at the top (the locals { } block)
$EDITOR main.tf

# 6) Plan and apply
terraform init
terraform plan
terraform apply
```

---

## 3. Step-by-step

### Step 1 — Build the provider for local use

The `setup.sh` script builds the provider and writes a ready-to-use
`dev.tfrc.local` for you:

```shell
./setup.sh
```

It creates this directory's `.provider-bin/` and places
`terraform-provider-fortiappseccloud` there. It never touches your
`~/.terraformrc`.

> Alternatively, build manually:
>
> ```shell
> go build -o .provider-bin/terraform-provider-fortiappseccloud ../..
> ```
>
> and substitute `.provider-bin` into `dev.tfrc` (replace
> `__PROVIDER_BUILD_DIR__`).

### Step 2 — Activate the dev override

Terraform reads its CLI config from `TF_CLI_CONFIG_FILE`. Export it in the
shell where you will run `terraform`:

```shell
export TF_CLI_CONFIG_FILE="$(pwd)/dev.tfrc.local"
```

You must re-export this in every new shell. If you prefer, you can instead
merge the `provider_installation` block from `dev.tfrc` into your real
`~/.terraformrc` — but the file-scoped approach avoids touching your global
config.

### Step 3 — Provide a token

Use only environment variables; never put tokens in `.tf` files or tfvars:

```shell
read -rsp "Dev API token: " FORTIAPPSECCLOUD_API_TOKEN
export FORTIAPPSECCLOUD_API_TOKEN
unset FORTIAPPSECCLOUD_USERNAME
unset FORTIAPPSECCLOUD_PASSWORD
```

The provider requires **either** an API token **or** a
username+password pair (via `FORTIAPPSECCLOUD_USERNAME` +
`FORTIAPPSECCLOUD_PASSWORD`) — not both.

### Step 4 — Set the test values (no variables, no prompts)

This directory uses plain `locals {}` in `main.tf` instead of `variables.tf`
so that `terraform plan` never prompts for interactive input. Edit the values
at the top of `main.tf` directly:

```hcl
locals {
  hostname       = "https://api.dev1.fortiappsec.com"
  app_name       = "yuchen_test_dev1"
  domain_name    = "developers.cloudflare.com"
  origin_address = "1.1.1.1"
  platform       = "AWS"
  region         = "us-east-1"
}
```

At minimum, set a unique `app_name`, your `domain_name`, and an
`origin_address` (the placeholder values above are examples). Save `main.tf`
and `terraform plan` will read them with no prompting.

### Step 5 — Initialize, plan, apply

```shell
terraform init
terraform plan
terraform apply
```

During `terraform init` you will see a warning that the provider is
"overridden by a dev override configuration". **This is expected** — it means
Terraform is using your locally built binary instead of the registry.

### Step 6 — Test more

Edit `main.tf` to add/change resources, then apply again to exercise update /
no-op / import paths:

```shell
terraform plan     # should be empty after a no-op change
terraform import fortiappseccloud_waf_csrf_protection.test <ep_id>
terraform plan
```

### Step 7 — Destroy the remote resources

```shell
terraform destroy
```

Destroying the app-module resources follows the provider's reviewed
disable/forget semantics described in `examples/waf/README.md`, then deletes
the disposable application.

### Step 8 — Completely clear the local setup

`terraform destroy` only removes the resources in cloud. The local files and
overrides that this directory's workflow created remain behind. To fully reset
your machine back to a clean state, run the provided cleanup script:

```shell
./cleanup.sh
```

`cleanup.sh` removes, **within the current shell**:
- `.terraform/` (provider cache / backend files)
- `terraform.tfvars` (your local variable values — treat as sensitive)
- `*.tfstate` and `*.tfstate.backup` (Terraform state)
- `plan` (a saved plan file, if any)
- `.provider-bin/` and `terraform-provider-fortiappseccloud` (the built provider)
- `dev.tfrc.local` (the generated dev override config)

It then checks whether this shell still has the environment variables set and
tells you to unset them (an `unset` inside a script cannot affect your shell,
so it prints the commands for you to run):

```shell
unset TF_CLI_CONFIG_FILE FORTIAPPSECCLOUD_API_TOKEN
unset FORTIAPPSECCLOUD_USERNAME FORTIAPPSECCLOUD_PASSWORD
unset FORTIAPPSECCLOUD_HOSTNAME
```

If instead you merged the `provider_installation` block into your real
`~/.terraformrc`, remove that block manually to fully undo the override.

> If you want to clear the state but keep everything else so you can run again,
> use `terraform state rm` / don't run cleanup — or simply re-run `./setup.sh`
> (your values in `main.tf`'s `locals {}` block are preserved).

---

## 4. Files in this directory

| File | Purpose |
|---|---|
| `main.tf` | All-in-one config: tunable `locals {}` block at top + disposable app + WAF modules. Edit values directly here — no variables, no prompts. |
| `openapi.yaml` | Minimal OpenAPI document used by the enabled OpenAPI validation module. |
| `dev.tfrc` | Template `dev_overrides` config (contains `__PROVIDER_BUILD_DIR__`). |
| `setup.sh` | Builds the provider and emits `dev.tfrc.local` with the correct path. |
| `cleanup.sh` | Removes all local artifacts and prints the env vars to unset (see Step 8). |
| `.gitignore` | Keeps `.terraform/`, `*.tfstate`, `*.tfvars`, and build artifacts out of git. |

---

## 5. Important notes & safety

- **Do not commit** `.terraform/`, `*.tfstate`, or any credentials (there is no
  `terraform.tfvars` in this setup — values live in `main.tf`).
- **Use your own unique `app_name`.** The provider/API rejects onboarding an
  application name that already exists. If a prior run leaked an app, delete
  it (console or API) before re-running.
- **Origin details matter.** When the origin uses SSL, you must set its
  encryption level explicitly (e.g. `mozilla_modern`); the API rejects an
  origin PUT that omits it, and the provider will not invent one. This example
  uses `protocol = "https"` + `port = 443`; adjust `initial_origin` to match
  your origin or add `encryption_level` if required by your environment.
- **`certificate_mode`** only switches between `automatic` and `custom`
  certificate management — the provider does **not** upload certificate content.
- **Use a disposable account/application.** This is real API traffic against
  the target environment.
- When you're done, remove the cloud resources with `terraform destroy` and
  fully clear the local setup with `./cleanup.sh` (see **Step 8**) so the
  override and token are not accidentally reused.

---

## 6. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `terraform init` tries to download from registry / errors | `TF_CLI_CONFIG_FILE` not exported in this shell, or `dev.tfrc.local` has the wrong path. Re-run `./setup.sh` and re-export. |
| "Provider ... overridden by a dev override configuration" warning | Normal — means the local build is being used. |
| `terraform plan` says provider requires credentials / token | `FORTIAPPSECCLOUD_API_TOKEN` not set in this shell, or username+password being combined with a token. |
| Origin PUT rejected | Add explicit `encryption_level`/cipher policy to `initial_origin` matching your origin. |
| App already exists error | Change `app_name` to a new unique value, or delete the prior app. |
| You changed Go source and results are stale | The provider must be rebuilt: re-run `./setup.sh` (or `go build`) before the next `terraform plan/apply`. |

---

For a fuller API of accepted resources, see the sibling `../waf` directory and
the generated docs under `website/docs/r/`. For automated live-testing against
dev1, see `guide/waf-v2-live-testing.md`.
