<#!
.SYNOPSIS
  Setup script for Google Analytics MCP on Windows.

.DESCRIPTION
  Automates configuration of Google Analytics MCP for Gemini CLI:
    - Supports ADC or Service Account credentials
    - Enables required Google APIs
    - Configures Gemini MCP `settings.json`
    - Installs Gemini CLI if missing

.PARAMETERS
  MODE              adc | sa (default: adc)
  GOOGLE_PROJECT_ID GCP Project ID (mandatory)
  SA_NAME           Service Account name (default: mcp-analytics)
  KEY_DIR           Directory to store JSON keys (default: $HOME\keys)
  KEY_PATH          Full path for JSON key (optional)
#>

param(
  [string]$MODE = $env:MODE  | ForEach-Object { if ($_ -eq $null) { 'adc' } else { $_ } },
  [string]$GOOGLE_PROJECT_ID = $env:GOOGLE_PROJECT_ID,
  [string]$SA_NAME = $env:SA_NAME | ForEach-Object { if ($_ -eq $null) { 'mcp-analytics' } else { $_ } },
  [string]$KEY_DIR = $env:KEY_DIR | ForEach-Object { if ($_ -eq $null) { "$HOME\keys" } else { $_ } },
  [string]$KEY_PATH = $env:KEY_PATH
)

$MCP_REPO = "git+https://github.com/googleanalytics/google-analytics-mcp.git"
$MCP_NAME = "analytics-mcp"
$SETTINGS_DIR = Join-Path $HOME ".gemini"
$SETTINGS_FILE = Join-Path $SETTINGS_DIR "settings.json"
$REQUIRED_SCOPES = "https://www.googleapis.com/auth/analytics.readonly,https://www.googleapis.com/auth/cloud-platform"

# =============================================================
# Helper Functions
# =============================================================
function Fail($msg) {
  Write-Host "❌ $msg" -ForegroundColor Red
  Exit 1
}

function Ensure-Dir($path) {
  if (!(Test-Path $path)) {
    New-Item -ItemType Directory -Force -Path $path | Out-Null
  }
}

function Command-Exists($cmd) {
  $null -ne (Get-Command $cmd -ErrorAction SilentlyContinue)
}

function Write-SettingsJson($CredPath, $ProjectId) {
  Ensure-Dir $SETTINGS_DIR

  $existing = if (Test-Path $SETTINGS_FILE) {
    Get-Content $SETTINGS_FILE | ConvertFrom-Json
  } else {
    @{}
  }

  if (-not $existing.mcpServers) {
    $existing | Add-Member -MemberType NoteProperty -Name "mcpServers" -Value @{}
  }

  $existing.mcpServers[$MCP_NAME] = @{
    command = "pipx"
    args = @("run", "--spec", "$MCP_REPO", "google-analytics-mcp")
    env = @{
      GOOGLE_APPLICATION_CREDENTIALS = $CredPath
      GOOGLE_PROJECT_ID = $ProjectId
    }
  }

  $existing | ConvertTo-Json -Depth 6 | Set-Content -Path $SETTINGS_FILE -Encoding UTF8
  Write-Host "✓ Updated $SETTINGS_FILE" -ForegroundColor Green
}

# =============================================================
# Prerequisites
# =============================================================
Write-Host "==> Checking prerequisites..." -ForegroundColor Cyan

if (-not $GOOGLE_PROJECT_ID) {
  Fail "Set GOOGLE_PROJECT_ID, e.g.: `$env:GOOGLE_PROJECT_ID='my-project' .\setup-analytics-mcp.ps1"
}

if (-not (Command-Exists python)) {
  Fail "Python3 not found. Install it and re-run."
}

if (-not (Command-Exists pipx)) {
  Write-Host "→ Installing pipx..." -ForegroundColor Yellow
  python -m pip install --user pipx
  python -m pipx ensurepath
  $env:PATH += ";$HOME\.local\bin"
  if (-not (Command-Exists pipx)) {
    Fail "pipx not found after installation. Restart PowerShell and retry."
  }
}

if (-not (Command-Exists jq)) {
  Fail "jq not found. Please install it: https://stedolan.github.io/jq/download/"
}

if (-not (Command-Exists gcloud)) {
  Fail "Google Cloud SDK (gcloud) not found. Install it: https://cloud.google.com/sdk/docs/install"
}

# =============================================================
# Enable Required APIs
# =============================================================
Write-Host "==> Enabling APIs..." -ForegroundColor Cyan
gcloud config set project $GOOGLE_PROJECT_ID | Out-Null
gcloud services enable analyticsadmin.googleapis.com analyticsdata.googleapis.com
if ($LASTEXITCODE -ne 0) { Fail "Failed to enable required APIs" }

# =============================================================
# Credentials
# =============================================================
$CredPath = ""
switch ($MODE) {
  "adc" {
    Write-Host "==> Using ADC mode (no manual JSON needed)" -ForegroundColor Cyan
    gcloud auth application-default login --scopes=$REQUIRED_SCOPES

    $DefaultADC = Join-Path $HOME ".config\\gcloud\\application_default_credentials.json"
    $AltADC = Join-Path $HOME "AppData\\Roaming\\gcloud\\application_default_credentials.json"

    if (Test-Path $DefaultADC) { $CredPath = $DefaultADC }
    elseif (Test-Path $AltADC) { $CredPath = $AltADC }
    else { Fail "ADC credentials not found. Try re-running gcloud auth application-default login" }

    Write-Host "✓ ADC ready: $CredPath" -ForegroundColor Green
  }

  "sa" {
    Write-Host "==> Using Service Account + JSON mode" -ForegroundColor Cyan
    $SA_EMAIL = "$SA_NAME@$GOOGLE_PROJECT_ID.iam.gserviceaccount.com"

    if (-not (gcloud iam service-accounts describe $SA_EMAIL 2>$null)) {
      gcloud iam service-accounts create $SA_NAME --display-name="MCP Analytics"
      Write-Host "✓ Created Service Account: $SA_EMAIL" -ForegroundColor Green
    } else {
      Write-Host "↺ Service Account already exists: $SA_EMAIL"
    }

    if (-not (gcloud projects get-iam-policy $GOOGLE_PROJECT_ID --flatten="bindings[].members" --format="value(bindings.members)" --filter="bindings.members:serviceAccount:$SA_EMAIL" | Select-String .)) {
      gcloud projects add-iam-policy-binding $GOOGLE_PROJECT_ID --member="serviceAccount:$SA_EMAIL" --role="roles/analytics.viewer" | Out-Null
      Write-Host "✓ Added Analytics Viewer role for $SA_EMAIL" -ForegroundColor Green
    } else {
      Write-Host "↺ Role already assigned: $SA_EMAIL"
    }

    Ensure-Dir $KEY_DIR
    if (-not $KEY_PATH) { $KEY_PATH = Join-Path $KEY_DIR "$SA_NAME.json" }

    if (-not (Test-Path $KEY_PATH)) {
      gcloud iam service-accounts keys create $KEY_PATH --iam-account=$SA_EMAIL
      Write-Host "✓ JSON key saved: $KEY_PATH" -ForegroundColor Green
    } else {
      Write-Host "↺ JSON key already exists: $KEY_PATH"
    }

    $CredPath = $KEY_PATH
    gcloud auth activate-service-account --key-file=$CredPath

    Write-Host "⚠️  Manual step required: Add $SA_EMAIL as Viewer in GA4 Property Access Management" -ForegroundColor Yellow
  }

  default { Fail "Invalid MODE. Use adc or sa." }
}

# =============================================================
# Configure Gemini MCP
# =============================================================
Write-Host "==> Writing Gemini MCP configuration..." -ForegroundColor Cyan
Write-SettingsJson -CredPath $CredPath -ProjectId $GOOGLE_PROJECT_ID

# =============================================================
# Gemini CLI Installation
# =============================================================
Write-Host "==> Checking Gemini CLI..." -ForegroundColor Cyan
if (-not (Command-Exists gemini)) {
  if (Command-Exists npm) {
    Write-Host "→ Installing Gemini CLI via npm..."
    npm install -g @google/gemini-cli
  } else {
    Write-Host "⚠️ Gemini CLI not found. Install manually via npm or npx."
  }
} else {
  Write-Host "✓ Gemini CLI already installed."
}

# =============================================================
# Summary
# =============================================================
Write-Host "\n• Project ID:      $GOOGLE_PROJECT_ID"
Write-Host "• Credentials:     $CredPath"
Write-Host "\n🥳 Setup complete!"
Write-Host "\nStart Gemini with: gemini"
Write-Host "Inside Gemini, run: /mcp to verify $MCP_NAME is active."
