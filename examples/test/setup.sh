#!/usr/bin/env bash
#
# setup.sh - Build the local FortiAppSecCloud provider and prepare a
# dev_overrides config for testing with the Terraform CLI.
#
# Usage:
#   ./setup.sh              # build provider + write dev.tfrc with this repo's path
#   source ./setup.sh       # same, and then export TF_CLI_CONFIG_FILE in this shell
#
# Safe and non-destructive: it never touches ~/.terraformrc. Everything happens
# inside this examples/test directory (and the provider build directory).

set -euo pipefail

# Locate the provider repository root (this file lives at examples/test/setup.sh).
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_dir="${script_dir}"
provider_root="$(cd "${script_dir}/../.." && pwd)"

# Build the provider binary. dev_overrides needs an executable named
# terraform-provider-<provider> sitting in a directory that Terraform looks in.
build_dir="${test_dir}/.provider-bin"
mkdir -p "${build_dir}"

echo "Building provider from: ${provider_root}"
(
  cd "${provider_root}"
  go build -o "${build_dir}/terraform-provider-fortiappseccloud" .
)

# Write dev.tfrc with the absolute build directory substituted in.
sed "s|__PROVIDER_BUILD_DIR__|${build_dir}|" \
  "${test_dir}/dev.tfrc" > "${test_dir}/dev.tfrc.local"

chmod 600 "${test_dir}/dev.tfrc.local"

echo
echo "Provider built and dev_overrides written to: ${test_dir}/dev.tfrc.local"
echo
echo "Next step (in your shell):"
echo "  export TF_CLI_CONFIG_FILE=\"${test_dir}/dev.tfrc.local\""
echo
echo "Then, from this directory, run:"
echo "  terraform init"
echo "  terraform plan"
echo "  terraform apply"
