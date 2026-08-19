#!/usr/bin/env bash
#
# cleanup.sh - Remove all local Terraform and dev_overrides artifacts.
#
# This script removes files created during local testing inside the current
# directory. It does NOT touch your global ~/.terraformrc or any credentials
# stored outside this directory.
#
# After running this, unset the environment variables in your shell:
#   unset TF_CLI_CONFIG_FILE FORTIAPPSECCLOUD_API_TOKEN
#   unset FORTIAPPSECCLOUD_USERNAME FORTIAPPSECCLOUD_PASSWORD
#   unset FORTIAPPSECCLOUD_HOSTNAME

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${script_dir}"

echo "Cleaning up local Terraform artifacts in ${script_dir}..."
echo

# Remove Terraform working directory
if [[ -d ".terraform" ]]; then
  rm -rf .terraform
  echo "Removed .terraform/"
fi

# Remove local variable files (may contain sensitive identifiers)
for f in terraform.tfvars terraform.tfvars.json; do
  if [[ -f "$f" ]]; then
    rm -f "$f"
    echo "Removed ${f}"
  fi
done

# Remove state files (contain remote object IDs and possibly sensitive data)
for pattern in "*.tfstate" "*.tfstate.backup" "*.tfstate.json"; do
  for f in $pattern; do
    if [[ -f "$f" ]]; then
      rm -f "$f"
      echo "Removed ${f}"
    fi
  done
done

# Remove saved plan files
for pattern in plan tfplan*; do
  if [[ -f "$pattern" ]]; then
    rm -f "$pattern"
    echo "Removed ${pattern}"
  fi
done

# Remove built provider binary directory
if [[ -d ".provider-bin" ]]; then
  rm -rf .provider-bin
  echo "Removed .provider-bin/"
fi

# Remove standalone provider binary (if built directly in this dir)
if [[ -f "terraform-provider-fortiappseccloud" ]]; then
  rm -f terraform-provider-fortiappseccloud
  echo "Removed terraform-provider-fortiappseccloud"
fi

# Remove generated dev override config
if [[ -f "dev.tfrc.local" ]]; then
  rm -f dev.tfrc.local
  echo "Removed dev.tfrc.local"
fi

echo
echo "Local cleanup complete."
echo
echo "To finish, unset the following environment variables in your shell:"
echo
echo "  unset TF_CLI_CONFIG_FILE FORTIAPPSECCLOUD_API_TOKEN"
echo "  unset FORTIAPPSECCLOUD_USERNAME FORTIAPPSECCLOUD_PASSWORD"
echo "  unset FORTIAPPSECCLOUD_HOSTNAME"
echo
