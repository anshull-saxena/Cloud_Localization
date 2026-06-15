#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_PATH="${PROJECT_ROOT}/config.json"
AZURE_DIR="${AZURE_CONFIG_DIR:-${PROJECT_ROOT}/.azure}"

RESOURCE_GROUP=""
STORAGE_ACCOUNT=""
WRITE_CONFIG=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [--resource-group NAME] [--storage-account NAME] [--write-config]

Sets up Azure CLI for the base_version project using a project-local AZURE_CONFIG_DIR.

Options:
  --resource-group NAME   Azure resource group for the storage account lookup
  --storage-account NAME  Storage account name. Defaults to config.json StorageAccountName
  --write-config          Write the resolved connection string back to config.json
  -h, --help              Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --resource-group)
            RESOURCE_GROUP="${2:-}"
            shift 2
            ;;
        --storage-account)
            STORAGE_ACCOUNT="${2:-}"
            shift 2
            ;;
        --write-config)
            WRITE_CONFIG=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if ! command -v az >/dev/null 2>&1; then
    echo "Azure CLI is not installed." >&2
    echo "Install it first, for example on macOS: brew install azure-cli" >&2
    exit 1
fi

mkdir -p "${AZURE_DIR}"
export AZURE_CONFIG_DIR="${AZURE_DIR}"

echo "Azure CLI config dir: ${AZURE_CONFIG_DIR}"
echo "Project config file: ${CONFIG_PATH}"
echo

az version >/dev/null
echo "Azure CLI is available."

if az account show >/dev/null 2>&1; then
    echo "Azure login detected:"
    az account show --query "{subscription:name, user:user.name, tenant:tenantId}" -o table
else
    echo "No active Azure login found for this project config."
    echo "Run the following command, then re-run this script:"
    echo "  AZURE_CONFIG_DIR=\"${AZURE_CONFIG_DIR}\" az login --use-device-code"
    exit 0
fi

if [[ -z "${STORAGE_ACCOUNT}" && -f "${CONFIG_PATH}" ]]; then
    STORAGE_ACCOUNT="$(python3 - <<'PY' "${CONFIG_PATH}"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)

print(data.get("StorageAccountName", ""))
PY
)"
fi

if [[ -z "${RESOURCE_GROUP}" || -z "${STORAGE_ACCOUNT}" ]]; then
    echo
    echo "Azure CLI is ready for base_version."
    echo "Pass --resource-group and --storage-account to resolve the storage connection string."
    if [[ -n "${STORAGE_ACCOUNT}" ]]; then
        echo "Detected storage account from config.json: ${STORAGE_ACCOUNT}"
    fi
    exit 0
fi

echo
echo "Resolving storage connection string for ${STORAGE_ACCOUNT} in ${RESOURCE_GROUP}..."
CONNECTION_STRING="$(az storage account show-connection-string \
    --name "${STORAGE_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query connectionString \
    -o tsv)"

if [[ -z "${CONNECTION_STRING}" ]]; then
    echo "Azure CLI did not return a connection string." >&2
    exit 1
fi

echo "Connection string resolved successfully."

if [[ "${WRITE_CONFIG}" == true ]]; then
    python3 - <<'PY' "${CONFIG_PATH}" "${CONNECTION_STRING}" "${STORAGE_ACCOUNT}"
import json
import sys

config_path, connection_string, storage_account = sys.argv[1:4]

with open(config_path, "r", encoding="utf-8") as f:
    data = json.load(f)

data["ConnectionString"] = connection_string
data["StorageAccountName"] = storage_account

with open(config_path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
PY
    echo "Updated config.json with the resolved connection string."
else
    echo "Run again with --write-config to store it in config.json."
fi

