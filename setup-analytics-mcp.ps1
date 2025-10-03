#Requires -Version 5.1

# =============================================================
# Script Metadata
# =============================================================
$SCRIPT_VERSION = "2.0.0"
$SCRIPT_NAME = $MyInvocation.MyCommand.Name

# =============================================================
# Configuration
# =============================================================
$MCP_REPO = "git+https://github.com/googleanalytics/google-analytics-mcp.git"
$MCP_NAME = "analytics-mcp"
$SETTINGS_DIR = Join-Path $env:USERPROFILE ".gemini"
$SETTINGS_FILE = Join-Path $SETTINGS_DIR "settings.json"
$REQUIRED_SCOPES = "https://www.googleapis.com/auth/analytics.readonly,https://www.googleapis.com/auth/cloud-platform"
$MIN_PYTHON_VERSION = [Version]"3.9.0"

# Environment variables with defaults
$MODE = if ($env:MODE) { $env:MODE } else { "adc" }
$GOOGLE_PROJECT_ID = $env:GOOGLE_PROJECT_ID
$SA_NAME = if ($env:SA_NAME) { $env:SA_NAME } else { "mcp-analytics" }
$KEY_DIR = if ($env:KEY_DIR) { $env:KEY_DIR } else { Join-Path $env:USERPROFILE "keys" }
$KEY_PATH = $env:KEY_PATH
$AUTO_GCLOUD = if ($env:AUTO_GCLOUD -eq "1") { $true } else { $false }

# Runtime flags
$DRY_RUN = if ($env:DRY_RUN -eq "1") { $true } else { $false }
$VERBOSE_MODE = if ($env:VERBOSE -eq "1") { $true } else { $false }
$QUIET_MODE = if ($env:QUIET -eq "1") { $true } else { $false }
$ACTION = if ($env:ACTION) { $env:ACTION } else { "install" }

# Color support
$NO_COLOR = $env:NO_COLOR -eq "1"

# =============================================================
# Logging Functions
# =============================================================
function Write-ColorLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [ConsoleColor]$Color = [ConsoleColor]::White
    )

    if ($NO_COLOR) {
        Write-Host "[$Level] $Message"
    } else {
        Write-Host "[$Level] " -ForegroundColor $Color -NoNewline
        Write-Host $Message
    }
}

function Log-Error {
    param([string]$Message)
    Write-ColorLog -Message $Message -Level "ERROR" -Color Red
}

function Log-Warn {
    param([string]$Message)
    if (-not $QUIET_MODE) {
        Write-ColorLog -Message $Message -Level "WARN" -Color Yellow
    }
}

function Log-Info {
    param([string]$Message)
    if (-not $QUIET_MODE) {
        Write-ColorLog -Message $Message -Level "INFO" -Color Blue
    }
}

function Log-Success {
    param([string]$Message)
    if (-not $QUIET_MODE) {
        Write-ColorLog -Message $Message -Level "OK" -Color Green
    }
}

function Log-Verbose {
    param([string]$Message)
    if ($VERBOSE_MODE) {
        Write-ColorLog -Message $Message -Level "DEBUG" -Color Gray
    }
}

function Log-DryRun {
    param([string]$Message)
    if ($DRY_RUN) {
        Write-ColorLog -Message $Message -Level "DRY-RUN" -Color Yellow
    }
}

# =============================================================
# Error Handling
# =============================================================
$ErrorActionPreference = "Stop"

function Invoke-WithBackup {
    param(
        [string]$FilePath,
        [scriptblock]$ScriptBlock
    )

    $backupPath = "$FilePath.backup"

    try {
        if (Test-Path $FilePath) {
            Copy-Item $FilePath $backupPath -Force
            Log-Verbose "Backed up $FilePath to $backupPath"
        }

        & $ScriptBlock

        # Remove backup on success
        if (Test-Path $backupPath) {
            Remove-Item $backupPath -Force
        }
    }
    catch {
        # Restore backup on error
        if (Test-Path $backupPath) {
            Log-Warn "Restoring backup..."
            Move-Item $backupPath $FilePath -Force
        }
        throw
    }
}

# =============================================================
# Helper Functions
# =============================================================
function Test-Command {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Test-PythonVersion {
    if (-not (Test-Command "python")) {
        throw "Python is required but not found. Install from https://www.python.org/downloads/"
    }

    $pythonVersion = python --version 2>&1
    if ($pythonVersion -match "Python (\d+\.\d+\.\d+)") {
        $version = [Version]$matches[1]
        Log-Verbose "Found Python version: $version"

        if ($version -lt $MIN_PYTHON_VERSION) {
            throw "Python $MIN_PYTHON_VERSION or higher required (found $version)"
        }

        Log-Verbose "Python version check passed"
    } else {
        throw "Could not determine Python version"
    }
}

function Get-PackageManager {
    if (Test-Command "winget") {
        return "winget"
    } elseif (Test-Command "choco") {
        return "choco"
    } elseif (Test-Command "scoop") {
        return "scoop"
    }
    return $null
}

function Install-Package {
    param([string]$Package)

    Log-Info "Installing $Package..."

    if ($DRY_RUN) {
        Log-DryRun "Would install $Package"
        return
    }

    $pkgMgr = Get-PackageManager

    if (-not $pkgMgr) {
        throw "No package manager found. Install winget, chocolatey, or scoop"
    }

    Log-Verbose "Using package manager: $pkgMgr"

    switch ($pkgMgr) {
        "winget" {
            winget install $Package --silent
        }
        "choco" {
            choco install $Package -y
        }
        "scoop" {
            scoop install $Package
        }
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install $Package"
    }

    Log-Success "$Package installed"
}

function Test-ValidJson {
    param([string]$FilePath)

    try {
        $null = Get-Content $FilePath -Raw | ConvertFrom-Json
        return $true
    }
    catch {
        Log-Error "Invalid JSON in $FilePath"
        return $false
    }
}

# =============================================================
# Help & Usage
# =============================================================
function Show-Help {
    Write-Host @"
Google Analytics MCP Setup Script for Windows

USAGE:
  `$env:GOOGLE_PROJECT_ID="my-project"; .\setup-analytics-mcp.bat

REQUIRED:
  GOOGLE_PROJECT_ID    Your Google Cloud project ID

AUTHENTICATION MODES:
  MODE=adc            Use Application Default Credentials (default)
  MODE=sa             Use Service Account with JSON key

SERVICE ACCOUNT OPTIONS (MODE=sa only):
  SA_NAME=<name>      Service account name (default: mcp-analytics)
  KEY_DIR=<path>      Directory for JSON key (default: %USERPROFILE%\keys)
  KEY_PATH=<path>     Full path for JSON key (overrides KEY_DIR)

OTHER OPTIONS:
  AUTO_GCLOUD=1       Auto-install gcloud via package manager
  DRY_RUN=1          Show what would be done without executing
  VERBOSE=1          Enable verbose logging
  QUIET=1            Suppress non-error output
  NO_COLOR=1         Disable colored output

ACTIONS:
  ACTION=install      Install and configure MCP (default)
  ACTION=uninstall    Remove MCP configuration
  ACTION=update       Update MCP package
  ACTION=verify       Verify existing installation

EXAMPLES:
  # Install with ADC
  `$env:GOOGLE_PROJECT_ID="my-project"; .\setup-analytics-mcp.bat

  # Install with Service Account
  `$env:MODE="sa"; `$env:GOOGLE_PROJECT_ID="my-project"; .\setup-analytics-mcp.bat

  # Dry run to preview changes
  `$env:DRY_RUN="1"; `$env:GOOGLE_PROJECT_ID="my-project"; .\setup-analytics-mcp.bat

  # Uninstall
  `$env:ACTION="uninstall"; .\setup-analytics-mcp.bat

  # Verify installation
  `$env:ACTION="verify"; .\setup-analytics-mcp.bat

MORE INFO:
  https://github.com/paolobtl/google-analytics-mcp-installer

"@
    exit 0
}

function Show-Version {
    Write-Host "$SCRIPT_NAME version $SCRIPT_VERSION"
    exit 0
}

# Parse command line arguments
if ($args -contains "--help" -or $args -contains "-h") {
    Show-Help
}

if ($args -contains "--version" -or $args -contains "-v") {
    Show-Version
}

# =============================================================
# MCP Configuration Functions
# =============================================================
function Write-MCPSettings {
    param(
        [string]$CredPath,
        [string]$ProjectId
    )

    if ($DRY_RUN) {
        Log-DryRun "Would update $SETTINGS_FILE with MCP configuration"
        return
    }

    if (-not (Test-Path $SETTINGS_DIR)) {
        New-Item -ItemType Directory -Path $SETTINGS_DIR -Force | Out-Null
    }

    $settings = @{}
    if (Test-Path $SETTINGS_FILE) {
        $settings = Get-Content $SETTINGS_FILE -Raw | ConvertFrom-Json -AsHashtable
    }

    if (-not $settings.ContainsKey("mcpServers")) {
        $settings["mcpServers"] = @{}
    }

    $settings["mcpServers"][$MCP_NAME] = @{
        command = "pipx"
        args = @("run", "--spec", $MCP_REPO, "google-analytics-mcp")
        env = @{
            GOOGLE_APPLICATION_CREDENTIALS = $CredPath
            GOOGLE_PROJECT_ID = $ProjectId
        }
    }

    $settings | ConvertTo-Json -Depth 10 | Set-Content $SETTINGS_FILE

    if (-not (Test-ValidJson $SETTINGS_FILE)) {
        throw "Generated invalid JSON configuration"
    }

    Log-Success "Updated $SETTINGS_FILE"
}

# =============================================================
# Action Handlers
# =============================================================
function Invoke-Verify {
    Log-Info "Verifying MCP installation..."

    if (-not (Test-Path $SETTINGS_FILE)) {
        Log-Error "Settings file not found: $SETTINGS_FILE"
        return $false
    }

    Log-Verbose "Settings file exists: $SETTINGS_FILE"

    if (-not (Test-ValidJson $SETTINGS_FILE)) {
        Log-Error "Settings file contains invalid JSON"
        return $false
    }

    $settings = Get-Content $SETTINGS_FILE -Raw | ConvertFrom-Json

    if (-not $settings.mcpServers.$MCP_NAME) {
        Log-Error "MCP server '$MCP_NAME' not found in configuration"
        return $false
    }

    Log-Success "MCP configuration found in settings"

    $credPath = $settings.mcpServers.$MCP_NAME.env.GOOGLE_APPLICATION_CREDENTIALS
    if (-not (Test-Path $credPath)) {
        Log-Error "Credentials file not found: $credPath"
        return $false
    }

    Log-Success "Credentials file exists: $credPath"

    if (-not (Test-Command "pipx")) {
        Log-Error "pipx not found"
        return $false
    }

    Log-Success "All checks passed - MCP installation appears healthy"
    return $true
}

function Invoke-Uninstall {
    Log-Info "Uninstalling MCP configuration..."

    if (-not (Test-Path $SETTINGS_FILE)) {
        Log-Warn "Settings file not found: $SETTINGS_FILE"
        return
    }

    if ($DRY_RUN) {
        Log-DryRun "Would remove MCP server '$MCP_NAME' from $SETTINGS_FILE"
        return
    }

    Invoke-WithBackup -FilePath $SETTINGS_FILE -ScriptBlock {
        $settings = Get-Content $SETTINGS_FILE -Raw | ConvertFrom-Json -AsHashtable
        $settings["mcpServers"].Remove($MCP_NAME)
        $settings | ConvertTo-Json -Depth 10 | Set-Content $SETTINGS_FILE
    }

    if (-not (Test-ValidJson $SETTINGS_FILE)) {
        throw "Failed to generate valid JSON during uninstall"
    }

    Log-Success "MCP configuration removed from $SETTINGS_FILE"
    Log-Info "Note: Service account and credentials files were not deleted"
    Log-Info "To remove them manually, check: $KEY_DIR"
}

function Invoke-Update {
    Log-Info "Updating MCP package..."

    if (-not (Test-Command "pipx")) {
        throw "pipx not found - cannot update MCP"
    }

    if ($DRY_RUN) {
        Log-DryRun "Would update MCP package via pipx"
        return
    }

    Log-Info "MCP is configured to run via 'pipx run --spec', which always uses latest version"
    Log-Info "Running verification instead..."
    Invoke-Verify
}

function Invoke-Install {
    # Validate required parameters
    if (-not $GOOGLE_PROJECT_ID) {
        throw "GOOGLE_PROJECT_ID is required. Use --help for usage information"
    }

    Log-Info "Starting Google Analytics MCP setup for Windows"
    Log-Verbose "Mode: $MODE"
    Log-Verbose "Project ID: $GOOGLE_PROJECT_ID"
    Log-Verbose "Platform: Windows"

    # =============================================================
    # Prerequisites
    # =============================================================
    Log-Info "Checking prerequisites..."

    Test-PythonVersion

    # Install pipx
    if (-not (Test-Command "pipx")) {
        Log-Info "Installing pipx..."
        if ($DRY_RUN) {
            Log-DryRun "Would install pipx via pip"
        } else {
            python -m pip install --user pipx
            python -m pipx ensurepath
            $env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"

            if (-not (Test-Command "pipx")) {
                throw "pipx not found after installation"
            }
            Log-Success "pipx installed"
        }
    } else {
        Log-Verbose "pipx already installed"
    }

    # Install git
    if (-not (Test-Command "git")) {
        Install-Package "git"
    } else {
        Log-Verbose "git already installed"
    }

    # Install gcloud
    if (-not (Test-Command "gcloud")) {
        Log-Warn "gcloud not found"
        if ($AUTO_GCLOUD) {
            Log-Info "Installing Google Cloud SDK..."
            if ($DRY_RUN) {
                Log-DryRun "Would install gcloud via package manager"
            } else {
                $pkgMgr = Get-PackageManager
                switch ($pkgMgr) {
                    "winget" { winget install Google.CloudSDK --silent }
                    "choco" { choco install gcloudsdk -y }
                    "scoop" { scoop bucket add extras; scoop install gcloud }
                    default { throw "No package manager found for gcloud installation" }
                }

                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to install gcloud"
                }

                # Refresh environment
                $env:PATH = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

                Log-Success "Google Cloud SDK installed"
            }
        } else {
            throw "Install gcloud manually from https://cloud.google.com/sdk/docs/install (or use AUTO_GCLOUD=1)"
        }
    } else {
        Log-Verbose "gcloud already installed"
    }

    Log-Success "All prerequisites satisfied"

    # =============================================================
    # Enable required APIs
    # =============================================================
    Log-Info "Enabling required Google APIs..."

    if ($DRY_RUN) {
        Log-DryRun "Would set project to $GOOGLE_PROJECT_ID"
        Log-DryRun "Would enable analyticsadmin.googleapis.com and analyticsdata.googleapis.com"
    } else {
        Log-Verbose "Setting gcloud project to $GOOGLE_PROJECT_ID"
        gcloud config set project $GOOGLE_PROJECT_ID --quiet

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to set gcloud project"
        }

        Log-Verbose "Enabling Analytics Admin API and Analytics Data API"
        gcloud services enable analyticsadmin.googleapis.com analyticsdata.googleapis.com

        if ($LASTEXITCODE -ne 0) {
            throw "Failed to enable required APIs"
        }

        Log-Success "Required APIs enabled"
    }

    # =============================================================
    # Credentials
    # =============================================================
    $credPath = ""

    switch ($MODE) {
        "adc" {
            Log-Info "Configuring Application Default Credentials (ADC)"

            if ($DRY_RUN) {
                Log-DryRun "Would run: gcloud auth application-default login"
                $credPath = Join-Path $env:APPDATA "gcloud\application_default_credentials.json"
            } else {
                gcloud auth application-default login --scopes=$REQUIRED_SCOPES

                if ($LASTEXITCODE -ne 0) {
                    throw "ADC login failed"
                }

                $credPath = Join-Path $env:APPDATA "gcloud\application_default_credentials.json"

                if (-not (Test-Path $credPath)) {
                    throw "ADC credentials file not found at expected location: $credPath"
                }

                Log-Success "ADC configured: $credPath"
            }
        }

        "sa" {
            Log-Info "Configuring Service Account authentication"
            $saEmail = "$SA_NAME@$GOOGLE_PROJECT_ID.iam.gserviceaccount.com"

            Log-Verbose "Service account email: $saEmail"

            if ($DRY_RUN) {
                Log-DryRun "Would create or verify service account: $saEmail"
                Log-DryRun "Would assign Analytics Viewer role"
                Log-DryRun "Would create JSON key in $KEY_DIR"
                $credPath = Join-Path $KEY_DIR "$SA_NAME.json"
            } else {
                # Create service account if it doesn't exist
                gcloud iam service-accounts describe $saEmail --quiet 2>$null

                if ($LASTEXITCODE -ne 0) {
                    Log-Info "Creating service account: $saEmail"
                    gcloud iam service-accounts create $SA_NAME --display-name="MCP Analytics"

                    if ($LASTEXITCODE -ne 0) {
                        throw "Failed to create service account"
                    }

                    Log-Success "Service account created: $saEmail"
                } else {
                    Log-Verbose "Service account already exists: $saEmail"
                }

                # Assign IAM role
                $hasRole = gcloud projects get-iam-policy $GOOGLE_PROJECT_ID --flatten="bindings[].members" --format="value(bindings.members)" --filter="bindings.members:serviceAccount:$saEmail" 2>$null

                if (-not $hasRole) {
                    Log-Info "Assigning Analytics Viewer role to $saEmail"
                    gcloud projects add-iam-policy-binding $GOOGLE_PROJECT_ID --member="serviceAccount:$saEmail" --role="roles/analytics.viewer" --quiet

                    if ($LASTEXITCODE -ne 0) {
                        throw "Failed to assign IAM role"
                    }

                    Log-Success "IAM role assigned"
                } else {
                    Log-Verbose "IAM role already assigned"
                }

                # Create key directory and JSON key
                if (-not (Test-Path $KEY_DIR)) {
                    New-Item -ItemType Directory -Path $KEY_DIR -Force | Out-Null
                }

                if (-not $KEY_PATH) {
                    $KEY_PATH = Join-Path $KEY_DIR "$SA_NAME.json"
                }

                if (Test-Path $KEY_PATH) {
                    Log-Warn "JSON key already exists: $KEY_PATH"
                    Log-Info "Reusing existing key. For security, consider rotating keys regularly"
                } else {
                    Log-Info "Creating service account key..."
                    Log-Warn "Service account keys should be treated as sensitive credentials"
                    Log-Warn "Store securely and rotate regularly"

                    gcloud iam service-accounts keys create $KEY_PATH --iam-account=$saEmail

                    if ($LASTEXITCODE -ne 0) {
                        throw "Failed to create service account key"
                    }

                    Log-Success "Service account key created: $KEY_PATH"
                }

                $credPath = $KEY_PATH

                # Activate service account
                gcloud auth activate-service-account --key-file=$credPath

                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to activate service account"
                }

                Log-Warn "Manual step required:"
                Log-Warn "Add $saEmail to your GA4 property"
                Log-Warn "Go to Admin > Property Access Management and grant at least Viewer permissions"
            }
        }

        default {
            throw "Invalid MODE: $MODE (must be 'adc' or 'sa')"
        }
    }

    # =============================================================
    # Write Gemini MCP config
    # =============================================================
    Log-Info "Writing Gemini MCP configuration..."
    Write-MCPSettings -CredPath $credPath -ProjectId $GOOGLE_PROJECT_ID

    # =============================================================
    # Install / verify Gemini CLI
    # =============================================================
    Log-Info "Checking Gemini CLI..."

    if (-not (Test-Command "gemini")) {
        Log-Warn "Gemini CLI not found"

        if ($DRY_RUN) {
            Log-DryRun "Would attempt to install Gemini CLI"
        } else {
            if (Test-Command "npm") {
                Log-Info "Installing Gemini CLI via npm..."
                npm install -g @google/gemini-cli

                if ($LASTEXITCODE -eq 0) {
                    Log-Success "Gemini CLI installed via npm"
                } else {
                    Log-Warn "npm installation failed"
                }
            } elseif (Test-Command "npx") {
                Log-Info "npm/npx available - you can run: npx @google/gemini-cli"
            } else {
                Log-Warn "No package manager found for automatic installation"
                Log-Info "Install manually using one of:"
                Log-Info "  - npx @google/gemini-cli"
                Log-Info "  - npm install -g @google/gemini-cli"
                Log-Info "More info: https://github.com/google-gemini/gemini-cli"
            }
        }
    } else {
        Log-Success "Gemini CLI already installed"
    }

    # =============================================================
    # Summary
    # =============================================================
    Write-Host ""
    Log-Info "Configuration Summary:"
    Write-Host "  Project ID:    $GOOGLE_PROJECT_ID"
    Write-Host "  Credentials:   $credPath"
    Write-Host "  Settings:      $SETTINGS_FILE"
    Write-Host ""

    Log-Success "Setup complete!"
    Write-Host ""
    Log-Info "Next steps:"
    Log-Info "  1. Start Gemini: gemini"
    Log-Info "  2. Inside Gemini, type: /mcp"
    Log-Info "  3. Verify that '$MCP_NAME' appears as an active server"

    if ($MODE -eq "sa") {
        Write-Host ""
        Log-Warn "Don't forget to add the service account to your GA4 property!"
    }
}

# =============================================================
# Main Entry Point
# =============================================================
try {
    switch ($ACTION) {
        "install" { Invoke-Install }
        "uninstall" { Invoke-Uninstall }
        "update" { Invoke-Update }
        "verify" { Invoke-Verify }
        default { throw "Invalid ACTION: $ACTION (must be install, uninstall, update, or verify)" }
    }

    exit 0
}
catch {
    Log-Error $_.Exception.Message
    exit 1
}
