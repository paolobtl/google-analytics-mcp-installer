#!/usr/bin/env bash
set -euo pipefail
set -E

# =============================================================
# Script Metadata
# =============================================================
SCRIPT_VERSION="2.0.0"
SCRIPT_NAME="$(basename "$0")"

# =============================================================
# Configuration
# =============================================================
MCP_REPO="git+https://github.com/googleanalytics/google-analytics-mcp.git"
MCP_NAME="analytics-mcp"
SETTINGS_DIR="${HOME}/.gemini"
SETTINGS_FILE="${SETTINGS_DIR}/settings.json"
REQUIRED_SCOPES="https://www.googleapis.com/auth/analytics.readonly,https://www.googleapis.com/auth/cloud-platform"
MIN_PYTHON_VERSION="3.9"

# Environment variables with defaults
MODE="${MODE:-adc}"                       # adc | sa
GOOGLE_PROJECT_ID="${GOOGLE_PROJECT_ID:-}" # mandatory
SA_NAME="${SA_NAME:-mcp-analytics}"       # only for MODE=sa
KEY_DIR="${KEY_DIR:-$HOME/keys}"
KEY_PATH="${KEY_PATH:-}"
AUTO_GCLOUD="${AUTO_GCLOUD:-0}"           # 1 = auto-install on Linux x86_64

# Runtime flags
DRY_RUN="${DRY_RUN:-0}"
VERBOSE="${VERBOSE:-0}"
QUIET="${QUIET:-0}"
ACTION="${ACTION:-install}"  # install | uninstall | update | verify

# Color codes (disabled if NO_COLOR is set or not a tty)
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' BOLD='' RESET=''
fi

# =============================================================
# Logging Functions
# =============================================================
log_error() {
  echo -e "${RED}[ERROR]${RESET} $*" >&2
}

log_warn() {
  [[ "$QUIET" == "1" ]] && return 0
  echo -e "${YELLOW}[WARN]${RESET} $*" >&2
}

log_info() {
  [[ "$QUIET" == "1" ]] && return 0
  echo -e "${BLUE}[INFO]${RESET} $*"
}

log_success() {
  [[ "$QUIET" == "1" ]] && return 0
  echo -e "${GREEN}[OK]${RESET} $*"
}

log_verbose() {
  [[ "$VERBOSE" == "1" ]] || return 0
  echo -e "${RESET}[DEBUG]${RESET} $*"
}

log_dry_run() {
  [[ "$DRY_RUN" == "1" ]] || return 0
  echo -e "${YELLOW}[DRY-RUN]${RESET} $*"
}

# =============================================================
# Error Handling
# =============================================================
cleanup_on_error() {
  local exit_code=$?
  log_error "Script failed at line $1: command failed with exit code $exit_code"

  # Restore backup if exists
  if [[ -f "${SETTINGS_FILE}.backup" ]]; then
    log_warn "Restoring settings backup..."
    mv "${SETTINGS_FILE}.backup" "$SETTINGS_FILE" 2>/dev/null || true
  fi

  exit $exit_code
}

trap 'cleanup_on_error $LINENO' ERR

# =============================================================
# Helper Functions
# =============================================================
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

fail() {
  log_error "$*"
  exit 1
}

ensure_dir() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log_dry_run "Would create directory: $1"
    return 0
  fi
  mkdir -p "$1"
}

version_ge() {
  # Compare versions: returns 0 if $1 >= $2
  printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

backup_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    local backup="${file}.backup"
    if [[ "$DRY_RUN" == "1" ]]; then
      log_dry_run "Would backup $file to $backup"
      return 0
    fi
    cp "$file" "$backup"
    log_verbose "Backed up $file to $backup"
  fi
}

detect_platform() {
  local os="$(uname -s)"
  local arch="$(uname -m)"
  echo "${os}-${arch}"
}

is_macos() {
  [[ "$(uname -s)" == "Darwin" ]]
}

is_linux() {
  [[ "$(uname -s)" == "Linux" ]]
}

# =============================================================
# Help & Usage
# =============================================================
show_help() {
  cat <<'EOF'
Google Analytics MCP Setup Script

USAGE:
  GOOGLE_PROJECT_ID=<project-id> ./setup-analytics-mcp.sh [OPTIONS]

REQUIRED:
  GOOGLE_PROJECT_ID    Your Google Cloud project ID

AUTHENTICATION MODES:
  MODE=adc            Use Application Default Credentials (default)
  MODE=sa             Use Service Account with JSON key

SERVICE ACCOUNT OPTIONS (MODE=sa only):
  SA_NAME=<name>      Service account name (default: mcp-analytics)
  KEY_DIR=<path>      Directory for JSON key (default: $HOME/keys)
  KEY_PATH=<path>     Full path for JSON key (overrides KEY_DIR)

OTHER OPTIONS:
  AUTO_GCLOUD=1       Auto-install gcloud (Linux x86_64 only)
  DRY_RUN=1          Show what would be done without executing
  VERBOSE=1          Enable verbose logging
  QUIET=1            Suppress non-error output
  NO_COLOR=1         Disable colored output

ACTIONS:
  ACTION=install      Install and configure MCP (default)
  ACTION=uninstall    Remove MCP configuration
  ACTION=update       Update MCP package
  ACTION=verify       Verify existing installation

FLAGS:
  --help, -h         Show this help message
  --version, -v      Show script version

EXAMPLES:
  # Install with ADC
  GOOGLE_PROJECT_ID="my-project" ./setup-analytics-mcp.sh

  # Install with Service Account
  MODE=sa GOOGLE_PROJECT_ID="my-project" ./setup-analytics-mcp.sh

  # Dry run to preview changes
  DRY_RUN=1 GOOGLE_PROJECT_ID="my-project" ./setup-analytics-mcp.sh

  # Uninstall
  ACTION=uninstall ./setup-analytics-mcp.sh

  # Verify installation
  ACTION=verify ./setup-analytics-mcp.sh

  # Verbose output
  VERBOSE=1 GOOGLE_PROJECT_ID="my-project" ./setup-analytics-mcp.sh

MORE INFO:
  https://github.com/paolobtl/google-analytics-mcp-installer

EOF
  exit 0
}

show_version() {
  echo "$SCRIPT_NAME version $SCRIPT_VERSION"
  exit 0
}

# Parse command line arguments
for arg in "$@"; do
  case "$arg" in
    --help|-h) show_help ;;
    --version|-v) show_version ;;
    *) log_warn "Unknown argument: $arg (use --help for usage)" ;;
  esac
done

# =============================================================
# Validation Functions
# =============================================================
validate_python_version() {
  if ! command_exists python3; then
    fail "Python 3 is required but not found"
  fi

  local python_version
  python_version=$(python3 --version 2>&1 | awk '{print $2}')
  log_verbose "Found Python version: $python_version"

  if ! version_ge "$python_version" "$MIN_PYTHON_VERSION"; then
    fail "Python $MIN_PYTHON_VERSION or higher required (found $python_version)"
  fi

  log_verbose "Python version check passed"
}

validate_json() {
  local json_file="$1"
  if ! jq empty "$json_file" 2>/dev/null; then
    log_error "Invalid JSON in $json_file"
    return 1
  fi
  return 0
}

validate_gcloud_auth() {
  if [[ "$DRY_RUN" == "1" ]]; then
    return 0
  fi

  local active_account
  active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -n1)

  if [[ -z "$active_account" ]]; then
    log_warn "No active gcloud authentication found"
    return 1
  fi

  log_verbose "Active gcloud account: $active_account"

  # Check if authenticated with a service account from a different/deleted project
  if [[ "$active_account" == *"@"*".iam.gserviceaccount.com" ]]; then
    local sa_project
    sa_project=$(echo "$active_account" | sed 's/.*@\(.*\)\.iam\.gserviceaccount\.com/\1/')

    if [[ "$sa_project" != "$GOOGLE_PROJECT_ID" ]]; then
      log_warn "Currently authenticated with service account from different project: $active_account"
      log_warn "Target project: $GOOGLE_PROJECT_ID"
      log_warn "This may cause permission errors"
      log_info ""
      log_info "To fix this, authenticate with your personal account:"
      log_info "  gcloud auth revoke $active_account"
      log_info "  gcloud auth login"
      log_info "  gcloud config set project $GOOGLE_PROJECT_ID"
      log_info ""

      read -p "Continue anyway? (y/N): " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        fail "Aborted by user"
      fi
    fi
  fi

  # Test if we can actually access the project
  log_verbose "Verifying access to project $GOOGLE_PROJECT_ID..."
  if ! gcloud projects describe "$GOOGLE_PROJECT_ID" >/dev/null 2>&1; then
    log_error "Cannot access project: $GOOGLE_PROJECT_ID"
    log_error "This could mean:"
    log_error "  1. The project doesn't exist"
    log_error "  2. You don't have permission to access it"
    log_error "  3. You're authenticated with the wrong account"
    log_info ""
    log_info "Current active account: $active_account"
    log_info ""
    log_info "To fix authentication issues:"
    log_info "  # See all authenticated accounts"
    log_info "  gcloud auth list"
    log_info ""
    log_info "  # Switch to your personal account"
    log_info "  gcloud config set account YOUR_EMAIL@gmail.com"
    log_info ""
    log_info "  # Or login fresh"
    log_info "  gcloud auth login"
    log_info ""
    return 1
  fi

  log_verbose "Project access verified"
  return 0
}

check_file_permissions() {
  local file="$1"
  local perms=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%A" "$file" 2>/dev/null)

  if [[ "$perms" != "600" ]] && [[ "$perms" != "400" ]]; then
    log_warn "File $file has permissions $perms (recommended: 600)"
    return 1
  fi
  return 0
}

# =============================================================
# Platform-Specific Installation
# =============================================================
install_with_package_manager() {
  local package="$1"
  local platform=$(detect_platform)

  log_info "Installing $package..."

  if [[ "$DRY_RUN" == "1" ]]; then
    log_dry_run "Would install $package"
    return 0
  fi

  case "$platform" in
    Darwin-*)
      if command_exists brew; then
        brew install "$package" || return 1
      else
        log_error "Homebrew not found. Install from https://brew.sh"
        return 1
      fi
      ;;
    Linux-*)
      if command_exists apt-get; then
        sudo apt-get update && sudo apt-get install -y "$package" || return 1
      elif command_exists dnf; then
        sudo dnf install -y "$package" || return 1
      elif command_exists yum; then
        sudo yum install -y "$package" || return 1
      else
        log_error "No supported package manager found"
        return 1
      fi
      ;;
    *)
      log_error "Unsupported platform: $platform"
      return 1
      ;;
  esac

  log_success "$package installed"
}

json_write_settings(){
  local cred_path="$1"
  local project_id="$2"

  if [[ "$DRY_RUN" == "1" ]]; then
    log_dry_run "Would update $SETTINGS_FILE with MCP configuration"
    return 0
  fi

  backup_file "$SETTINGS_FILE"
  ensure_dir "$SETTINGS_DIR"

  local existing="{}"
  [[ -f "$SETTINGS_FILE" ]] && existing="$(cat "$SETTINGS_FILE")"

  local temp_file="${SETTINGS_FILE}.tmp"
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
    }' > "$temp_file"

  if ! validate_json "$temp_file"; then
    rm -f "$temp_file"
    fail "Generated invalid JSON configuration"
  fi

  mv "$temp_file" "$SETTINGS_FILE"
  log_success "Updated $SETTINGS_FILE"
}

install_gcloud_linux(){
  log_info "Installing Google Cloud SDK for Linux x86_64..."

  if [[ "$DRY_RUN" == "1" ]]; then
    log_dry_run "Would download and install Google Cloud SDK"
    return 0
  fi

  local archive="google-cloud-cli-linux-x86_64.tar.gz"
  local url="https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/$archive"

  log_verbose "Downloading from $url"
  curl -fsSLO "$url" || fail "Failed to download Google Cloud SDK"

  log_verbose "Extracting $archive"
  tar -xf "$archive" || fail "Failed to extract $archive"

  log_verbose "Running installer"
  ./google-cloud-sdk/install.sh -q || fail "Google Cloud SDK installation failed"

  export PATH="$(pwd)/google-cloud-sdk/bin:$PATH"

  if ! ./google-cloud-sdk/bin/gcloud version >/dev/null 2>&1; then
    fail "Google Cloud SDK installation verification failed"
  fi

  log_success "Google Cloud SDK installed successfully"
}

# =============================================================
# Action Handlers
# =============================================================
action_verify() {
  log_info "Verifying MCP installation..."

  # Check if settings file exists
  if [[ ! -f "$SETTINGS_FILE" ]]; then
    log_error "Settings file not found: $SETTINGS_FILE"
    return 1
  fi

  log_verbose "Settings file exists: $SETTINGS_FILE"

  # Validate JSON
  if ! validate_json "$SETTINGS_FILE"; then
    log_error "Settings file contains invalid JSON"
    return 1
  fi

  # Check if MCP is configured
  if ! jq -e ".mcpServers.\"$MCP_NAME\"" "$SETTINGS_FILE" >/dev/null 2>&1; then
    log_error "MCP server '$MCP_NAME' not found in configuration"
    return 1
  fi

  log_success "MCP configuration found in settings"

  # Check credentials
  local cred_path=$(jq -r ".mcpServers.\"$MCP_NAME\".env.GOOGLE_APPLICATION_CREDENTIALS" "$SETTINGS_FILE")
  if [[ ! -f "$cred_path" ]]; then
    log_error "Credentials file not found: $cred_path"
    return 1
  fi

  log_success "Credentials file exists: $cred_path"

  # Check permissions
  if ! check_file_permissions "$cred_path"; then
    log_warn "Consider setting safer permissions: chmod 600 $cred_path"
  fi

  # Check if pipx is available
  if ! command_exists pipx; then
    log_error "pipx not found"
    return 1
  fi

  log_success "All checks passed - MCP installation appears healthy"
  return 0
}

action_uninstall() {
  log_info "Uninstalling MCP configuration..."

  if [[ ! -f "$SETTINGS_FILE" ]]; then
    log_warn "Settings file not found: $SETTINGS_FILE"
    return 0
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log_dry_run "Would remove MCP server '$MCP_NAME' from $SETTINGS_FILE"
    return 0
  fi

  backup_file "$SETTINGS_FILE"

  local temp_file="${SETTINGS_FILE}.tmp"
  jq "del(.mcpServers.\"$MCP_NAME\")" "$SETTINGS_FILE" > "$temp_file"

  if ! validate_json "$temp_file"; then
    rm -f "$temp_file"
    fail "Failed to generate valid JSON during uninstall"
  fi

  mv "$temp_file" "$SETTINGS_FILE"
  log_success "MCP configuration removed from $SETTINGS_FILE"

  log_info "Note: Service account and credentials files were not deleted"
  log_info "To remove them manually, check: $KEY_DIR"
}

action_update() {
  log_info "Updating MCP package..."

  if ! command_exists pipx; then
    fail "pipx not found - cannot update MCP"
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log_dry_run "Would update MCP package via pipx"
    return 0
  fi

  # Note: Since we use --spec with git repo, there's no persistent install to update
  # We just need to verify the settings are correct
  log_info "MCP is configured to run via 'pipx run --spec', which always uses latest version"
  log_info "Running verification instead..."
  action_verify
}

action_install() {
  # Main installation logic (existing code will go here)
  install_main
}

# =============================================================
# Main Installation Logic
# =============================================================
install_main() {
  # Validate required parameters
  if [[ -z "$GOOGLE_PROJECT_ID" ]]; then
    fail "GOOGLE_PROJECT_ID is required. Use --help for usage information"
  fi

  log_info "Starting Google Analytics MCP setup"
  log_verbose "Mode: $MODE"
  log_verbose "Project ID: $GOOGLE_PROJECT_ID"
  log_verbose "Platform: $(detect_platform)"

  # =============================================================
  # Prerequisites
  # =============================================================
  log_info "Checking prerequisites..."

  validate_python_version

  if ! command_exists pipx; then
    log_info "Installing pipx..."
    if [[ "$DRY_RUN" == "1" ]]; then
      log_dry_run "Would install pipx via pip"
    else
      python3 -m pip install --user pipx || fail "Failed to install pipx"
      python3 -m pipx ensurepath
      export PATH="$HOME/.local/bin:$PATH"
      hash -r
      command_exists pipx || fail "pipx not found after installation"
      log_success "pipx installed"
    fi
  else
    log_verbose "pipx already installed"
  fi

  if ! command_exists jq; then
    if is_macos || is_linux; then
      install_with_package_manager jq || fail "Failed to install jq"
    else
      fail "jq not found. Install it and re-run (e.g., brew install jq / apt install jq)"
    fi
  else
    log_verbose "jq already installed"
  fi

  if ! command_exists git; then
    install_with_package_manager git || fail "Failed to install git"
  else
    log_verbose "git already installed"
  fi

  if ! command_exists gcloud; then
    log_warn "gcloud not found"
    if [[ "$AUTO_GCLOUD" == "1" ]]; then
      local platform=$(detect_platform)
      case "$platform" in
        Linux-x86_64)
          install_gcloud_linux
          ;;
        *)
          fail "Automatic gcloud installation only supported on Linux x86_64. Install manually: https://cloud.google.com/sdk/docs/install"
          ;;
      esac
    else
      fail "Install gcloud manually: https://cloud.google.com/sdk/docs/install (or use AUTO_GCLOUD=1)"
    fi
  else
    log_verbose "gcloud already installed"
  fi

  log_success "All prerequisites satisfied"

  # =============================================================
  # Validate gcloud authentication
  # =============================================================
  log_info "Validating gcloud authentication..."
  validate_gcloud_auth || fail "gcloud authentication validation failed"

  # =============================================================
  # Enable required APIs
  # =============================================================
  log_info "Enabling required Google APIs..."

  if [[ "$DRY_RUN" == "1" ]]; then
    log_dry_run "Would set project to $GOOGLE_PROJECT_ID"
    log_dry_run "Would enable analyticsadmin.googleapis.com and analyticsdata.googleapis.com"
  else
    log_verbose "Setting gcloud project to $GOOGLE_PROJECT_ID"
    gcloud config set project "$GOOGLE_PROJECT_ID" >/dev/null || fail "Failed to set gcloud project"

    log_verbose "Enabling Analytics Admin API and Analytics Data API"
    gcloud services enable analyticsadmin.googleapis.com analyticsdata.googleapis.com \
      || fail "Failed to enable required APIs"

    log_success "Required APIs enabled"
  fi

  # =============================================================
  # Credentials
  # =============================================================
  local CRED_PATH=""

  case "$MODE" in
    adc)
      log_info "Configuring Application Default Credentials (ADC)"

      if [[ "$DRY_RUN" == "1" ]]; then
        log_dry_run "Would run: gcloud auth application-default login"
        CRED_PATH="${HOME}/.config/gcloud/application_default_credentials.json"
      else
        gcloud auth application-default login --scopes="$REQUIRED_SCOPES" \
          || fail "ADC login failed"

        # Default ADC location fallback
        local DEFAULT_ADC="${HOME}/.config/gcloud/application_default_credentials.json"
        local ALT_ADC="${HOME}/Library/Application Support/gcloud/application_default_credentials.json"

        CRED_PATH="$(gcloud config config-helper --format 'value(credential.file)' 2>/dev/null || true)"

        # If gcloud doesn't report a path, fall back to default locations
        if [[ -z "$CRED_PATH" ]]; then
          if [[ -f "$DEFAULT_ADC" ]]; then
            CRED_PATH="$DEFAULT_ADC"
          elif [[ -f "$ALT_ADC" ]]; then
            CRED_PATH="$ALT_ADC"
          fi
        fi

        [[ -f "$CRED_PATH" ]] || fail "ADC credentials file not found at expected location"

        log_success "ADC configured: $CRED_PATH"
      fi
      ;;

    sa)
      log_info "Configuring Service Account authentication"
      local SA_EMAIL="${SA_NAME}@${GOOGLE_PROJECT_ID}.iam.gserviceaccount.com"

      log_verbose "Service account email: $SA_EMAIL"

      if [[ "$DRY_RUN" == "1" ]]; then
        log_dry_run "Would create or verify service account: $SA_EMAIL"
        log_dry_run "Would assign Analytics Viewer role"
        log_dry_run "Would create JSON key in $KEY_DIR"
        CRED_PATH="${KEY_DIR}/${SA_NAME}.json"
      else
        # Create service account if it doesn't exist
        if ! gcloud iam service-accounts describe "$SA_EMAIL" >/dev/null 2>&1; then
          log_info "Creating service account: $SA_EMAIL"
          gcloud iam service-accounts create "$SA_NAME" --display-name="MCP Analytics" \
            || fail "Failed to create service account"
          log_success "Service account created: $SA_EMAIL"
        else
          log_verbose "Service account already exists: $SA_EMAIL"
        fi

        # Assign IAM role if not already assigned
        if ! gcloud projects get-iam-policy "$GOOGLE_PROJECT_ID" \
            --flatten="bindings[].members" \
            --format="value(bindings.members)" \
            --filter="bindings.members:serviceAccount:${SA_EMAIL}" | grep -q .; then
          log_info "Assigning Analytics Viewer role to $SA_EMAIL"
          gcloud projects add-iam-policy-binding "$GOOGLE_PROJECT_ID" \
            --member="serviceAccount:${SA_EMAIL}" \
            --role="roles/analytics.viewer" >/dev/null \
            || fail "Failed to assign IAM role"
          log_success "IAM role assigned"
        else
          log_verbose "IAM role already assigned"
        fi

        # Create key directory and JSON key
        ensure_dir "$KEY_DIR"
        [[ -z "$KEY_PATH" ]] && KEY_PATH="${KEY_DIR}/${SA_NAME}.json"

        if [[ -f "$KEY_PATH" ]]; then
          log_warn "JSON key already exists: $KEY_PATH"
          log_info "Reusing existing key. For security, consider rotating keys regularly"
        else
          log_info "Creating service account key..."
          log_warn "Service account keys should be treated as sensitive credentials"
          log_warn "Store securely and rotate regularly"

          gcloud iam service-accounts keys create "$KEY_PATH" \
            --iam-account="$SA_EMAIL" \
            || fail "Failed to create service account key"

          # Set restrictive permissions
          chmod 600 "$KEY_PATH"
          log_success "Service account key created: $KEY_PATH"
        fi

        CRED_PATH="$KEY_PATH"

        # Activate service account
        gcloud auth activate-service-account --key-file="$CRED_PATH" \
          || fail "Failed to activate service account"

        log_warn "Manual step required:"
        log_warn "Add $SA_EMAIL to your GA4 property"
        log_warn "Go to Admin > Property Access Management and grant at least Viewer permissions"
      fi
      ;;

    *)
      fail "Invalid MODE: $MODE (must be 'adc' or 'sa')"
      ;;
  esac

  # =============================================================
  # Write Gemini MCP config
  # =============================================================
  log_info "Writing Gemini MCP configuration..."
  json_write_settings "$CRED_PATH" "$GOOGLE_PROJECT_ID"

  # =============================================================
  # Install / verify Gemini CLI
  # =============================================================
  log_info "Checking Gemini CLI..."

  if ! command_exists gemini; then
    log_warn "Gemini CLI not found"

    if [[ "$DRY_RUN" == "1" ]]; then
      log_dry_run "Would attempt to install Gemini CLI"
    else
      if command_exists npm; then
        log_info "Installing Gemini CLI via npm..."
        if npm install -g @google/gemini-cli; then
          log_success "Gemini CLI installed via npm"
        else
          log_warn "npm installation failed"
        fi
      elif command_exists brew; then
        log_info "Installing Gemini CLI via Homebrew..."
        if brew install gemini-cli; then
          log_success "Gemini CLI installed via Homebrew"
        else
          log_warn "Homebrew installation failed"
        fi
      elif command_exists npx; then
        log_info "npm/npx available - you can run: npx @google/gemini-cli"
      else
        log_warn "No package manager found for automatic installation"
        log_info "Install manually using one of:"
        log_info "  - npx @google/gemini-cli"
        log_info "  - npm install -g @google/gemini-cli"
        log_info "  - brew install gemini-cli"
        log_info "More info: https://github.com/google-gemini/gemini-cli"
      fi
    fi
  else
    log_success "Gemini CLI already installed"
  fi

  # =============================================================
  # Summary
  # =============================================================
  echo
  log_info "Configuration Summary:"
  echo "  Project ID:    $GOOGLE_PROJECT_ID"
  echo "  Credentials:   $CRED_PATH"
  echo "  Settings:      $SETTINGS_FILE"
  echo

  log_success "Setup complete!"
  echo
  log_info "Next steps:"
  log_info "  1. Start Gemini: gemini"
  log_info "  2. Inside Gemini, type: /mcp"
  log_info "  3. Verify that '$MCP_NAME' appears as an active server"

  if [[ "$MODE" == "sa" ]]; then
    echo
    log_warn "Don't forget to add the service account to your GA4 property!"
  fi
}

# =============================================================
# Main Entry Point
# =============================================================
main() {
  case "$ACTION" in
    install)
      action_install
      ;;
    uninstall)
      action_uninstall
      ;;
    update)
      action_update
      ;;
    verify)
      action_verify
      ;;
    *)
      fail "Invalid ACTION: $ACTION (must be install, uninstall, update, or verify)"
      ;;
  esac
}

# Run main
main
