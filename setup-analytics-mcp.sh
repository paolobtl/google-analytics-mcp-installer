#!/usr/bin/env bash
set -euo pipefail
set -E
trap 'echo "\n❌ Error at line $LINENO: command \`$BASH_COMMAND\` failed." >&2' ERR

# =============================================================
# Configuration
# =============================================================
MCP_REPO="git+https://github.com/googleanalytics/google-analytics-mcp.git"
MCP_NAME="analytics-mcp"
SETTINGS_DIR="${HOME}/.gemini"
SETTINGS_FILE="${SETTINGS_DIR}/settings.json"
REQUIRED_SCOPES="https://www.googleapis.com/auth/analytics.readonly,https://www.googleapis.com/auth/cloud-platform"

MODE="${MODE:-adc}"                       # adc | sa
GOOGLE_PROJECT_ID="${GOOGLE_PROJECT_ID:-}" # mandatory
SA_NAME="${SA_NAME:-mcp-analytics}"       # only for MODE=sa
KEY_DIR="${KEY_DIR:-$HOME/keys}"
KEY_PATH="${KEY_PATH:-}"
AUTO_GCLOUD="${AUTO_GCLOUD:-0}"           # 1 = auto-install on Linux x86_64

# =============================================================
# Helpers
# =============================================================
command_exists(){ command -v "$1" >/dev/null 2>&1; }
fail(){ echo "❌ $*" >&2; exit 1; }
ensure_dir(){ mkdir -p "$1"; }

json_write_settings(){
  local cred_path="$1"
  local project_id="$2"

  ensure_dir "$SETTINGS_DIR"
  local existing="{}"
  [[ -f "$SETTINGS_FILE" ]] && existing="$(cat "$SETTINGS_FILE")"

  echo "$existing" | jq \
    --arg cmd "pipx" \
    --argjson args "[\"run\",\"--spec\",\"${MCP_REPO}\",\"google-analytics-mcp\"]" \
    --arg cred "$cred_path" \
    --arg proj "$project_id" '
    .mcpServers = (.mcpServers // {}) |
    .mcpServers["'$MCP_NAME'"] = {
      "command": $cmd,
      "args": $args,
      "env": {
        "GOOGLE_APPLICATION_CREDENTIALS": $cred,
        "GOOGLE_PROJECT_ID": $proj
      }
    }' > "${SETTINGS_FILE}.tmp"

  mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
  echo "✓ Updated $SETTINGS_FILE"
}

install_gcloud_linux(){
  echo "→ Installing Google Cloud SDK for Linux x86_64…"
  curl -fsSLO https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz
  tar -xf google-cloud-cli-linux-x86_64.tar.gz
  ./google-cloud-sdk/install.sh -q
  export PATH="$(pwd)/google-cloud-sdk/bin:$PATH"
  ./google-cloud-sdk/bin/gcloud version >/dev/null || fail "Google Cloud SDK installation failed."
  echo "✓ gcloud successfully installed."
}

# =============================================================
# Usage
# =============================================================
if [[ -z "$GOOGLE_PROJECT_ID" ]]; then
  fail "Set GOOGLE_PROJECT_ID, e.g.: GOOGLE_PROJECT_ID=my-proj ./setup.sh"
fi

# =============================================================
# Prerequisites
# =============================================================
echo "==> Checking prerequisites..."

command_exists python3 || fail "Python3 not found. Please install it and re-run."

if ! command_exists pipx; then
  echo "→ Installing pipx…"
  python3 -m pip install --user pipx
  python3 -m pipx ensurepath
  export PATH="$HOME/.local/bin:$PATH"
  hash -r
  command_exists pipx || fail "pipx not found after installation."
fi

command_exists jq || fail "jq not found. Install it (e.g. brew install jq / sudo apt install jq) and re-run."

if ! command_exists git; then
  echo "→ Installing git…"
  if command_exists apt; then
    sudo apt update && sudo apt install -y git
  elif command_exists dnf; then
    sudo dnf install -y git
  elif [[ "$OSTYPE" == "darwin"* ]] && command_exists brew; then
    brew install git
  else
    fail "Please install git and re-run."
  fi
fi

echo "✓ git OK"

if ! command_exists gcloud; then
  echo "⚠️  gcloud not found."
  if [[ "$AUTO_GCLOUD" == "1" ]]; then
    case "$(uname -s)-$(uname -m)" in
      Linux-x86_64) install_gcloud_linux ;;
      *) fail "Automatic installation only supported on Linux x86_64. Manual install: https://cloud.google.com/sdk/docs/install" ;;
    esac
  else
    fail "Install gcloud manually: https://cloud.google.com/sdk/docs/install or re-run with AUTO_GCLOUD=1."
  fi
fi

# =============================================================
# Enable required APIs
# =============================================================
echo "==> Enabling APIs…"
gcloud config set project "$GOOGLE_PROJECT_ID" >/dev/null
gcloud services enable analyticsadmin.googleapis.com analyticsdata.googleapis.com \
  || fail "Failed to enable required APIs."

# =============================================================
# Credentials
# =============================================================
CRED_PATH=""
case "$MODE" in
  adc)
    echo "==> Using ADC mode (no manual JSON needed)"
    gcloud auth application-default login --scopes="$REQUIRED_SCOPES"

    # Default ADC location fallback
    DEFAULT_ADC="${HOME}/.config/gcloud/application_default_credentials.json"
    ALT_ADC="${HOME}/Library/Application Support/gcloud/application_default_credentials.json"

    CRED_PATH="$(gcloud auth application-default print-access-token >/dev/null 2>&1 && \
                gcloud config config-helper --format 'value(credential.file)' || true)"

    # If gcloud doesn't report a path, fall back to default locations
    if [[ -z "$CRED_PATH" ]]; then
      if [[ -f "$DEFAULT_ADC" ]]; then
        CRED_PATH="$DEFAULT_ADC"
      elif [[ -f "$ALT_ADC" ]]; then
        CRED_PATH="$ALT_ADC"
      fi
    fi

    [[ -f "$CRED_PATH" ]] || fail \"ADC credentials file not found. Try: gcloud auth application-default login\"

    echo "✓ ADC ready: $CRED_PATH"
    ;;

  sa)
    echo "==> Using Service Account + JSON mode"
    SA_EMAIL="${SA_NAME}@${GOOGLE_PROJECT_ID}.iam.gserviceaccount.com"

    if ! gcloud iam service-accounts describe "$SA_EMAIL" >/dev/null 2>&1; then
      gcloud iam service-accounts create "$SA_NAME" --display-name="MCP Analytics"
      echo "✓ Created Service Account: $SA_EMAIL"
    else
      echo "↺ Service Account already exists: $SA_EMAIL"
    fi

    if ! gcloud projects get-iam-policy "$GOOGLE_PROJECT_ID" \
        --flatten="bindings[].members" \
        --format="value(bindings.members)" \
        --filter="bindings.members:serviceAccount:${SA_EMAIL}" | grep -q .; then
      gcloud projects add-iam-policy-binding "$GOOGLE_PROJECT_ID" \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="roles/analytics.viewer" >/dev/null
      echo "✓ Added Analytics Viewer role for $SA_EMAIL"
    else
      echo "↺ Project role already assigned for $SA_EMAIL"
    fi

    ensure_dir "$KEY_DIR"
    [[ -z "$KEY_PATH" ]] && KEY_PATH="${KEY_DIR}/${SA_NAME}.json"
    if [[ -f "$KEY_PATH" ]]; then
      echo "↺ JSON key already exists: $KEY_PATH (skipping)"
    else
      gcloud iam service-accounts keys create "$KEY_PATH" \
        --iam-account="$SA_EMAIL"
      echo "✓ JSON key saved: $KEY_PATH"
    fi

    CRED_PATH="$KEY_PATH"
    gcloud auth activate-service-account --key-file="$CRED_PATH"

    echo
    echo "⚠️  Manual step required in GA4:"
    echo "    Add ${SA_EMAIL} in Admin > Property Access Management with at least Viewer permissions."
    echo
    ;;

  *)
    fail "Invalid MODE. Use MODE=adc or MODE=sa."
    ;;
esac

# =============================================================
# Write Gemini MCP config
# =============================================================
echo "==> Writing Gemini MCP configuration…"
json_write_settings "$CRED_PATH" "$GOOGLE_PROJECT_ID"

# =============================================================
# Install / verify Gemini CLI
# =============================================================
echo "==> Verifying Gemini CLI…"

if ! command_exists gemini; then
  echo "⚠️  Gemini CLI not found."
  if command_exists npm; then
    echo "→ Installing Gemini CLI via npm…"
    npm install -g @google/gemini-cli || echo "⚠️ npm installation failed."
  elif command_exists brew; then
    echo "→ Installing Gemini CLI via Homebrew…"
    brew install gemini-cli || echo "⚠️ brew installation failed."
  elif command_exists npx; then
    echo "→ Using npx instead."
    alias gemini="npx @google/gemini-cli"
  else
    echo "➡️  Install manually via:"
    echo "   npx @google/gemini-cli"
    echo "   npm install -g @google/gemini-cli"
    echo "   brew install gemini-cli"
    echo "More info: https://github.com/google-gemini/gemini-cli"
  fi
else
  echo "✓ Gemini CLI already installed."
fi

# =============================================================
# Summary
# =============================================================
echo
echo "• Project ID:      $GOOGLE_PROJECT_ID"
echo "• Credentials:     $CRED_PATH"
echo

echo "🥳 Setup complete!"
echo

echo "You can now start Gemini by running:"
echo "   gemini"
echo

echo "Inside Gemini, type:"
echo "   /mcp"
echo "and check that '${MCP_NAME}' appears among the active servers."
