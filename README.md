# Google Analytics MCP Installer

Automated setup scripts to configure **Google Analytics MCP** for Gemini CLI on Linux, macOS, and Windows.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
  - [Linux/macOS](#linuxmacos)
  - [Windows](#windows)
- [Installation Methods](#installation-methods)
  - [Application Default Credentials (ADC)](#application-default-credentials-adc)
  - [Service Account](#service-account)
- [Configuration Options](#configuration-options)
- [Advanced Usage](#advanced-usage)
  - [Dry Run Mode](#dry-run-mode)
  - [Verbose Logging](#verbose-logging)
  - [Uninstall](#uninstall)
  - [Verify Installation](#verify-installation)
  - [Update MCP](#update-mcp)
- [Troubleshooting](#troubleshooting)
- [Security Best Practices](#security-best-practices)
- [Platform-Specific Notes](#platform-specific-notes)
- [License](#license)

---

## Overview

This installer automates the setup of [Google Analytics MCP](https://github.com/googleanalytics/google-analytics-mcp) for use with Gemini CLI. It handles:

- Google Cloud authentication (ADC or Service Account)
- Required API enablement
- Gemini CLI installation
- MCP server configuration

## Features

- **Cross-platform**: Linux, macOS, and Windows support
- **Multiple authentication modes**: ADC or Service Account
- **Automatic dependency installation**: pipx, gcloud, git, jq (Linux/macOS only)
- **Professional logging**: Color-coded output with verbose and quiet modes
- **Safety features**: Dry-run mode, automatic backup/rollback, JSON validation
- **Multiple actions**: Install, uninstall, update, verify
- **No signature issues on Windows**: Uses batch wrapper to bypass PowerShell execution policy

---

## Prerequisites

### All Platforms

- **Python 3.9 or higher** - [Download Python](https://www.python.org/downloads/)
- **Google Cloud Project** - [Create a project](https://developers.google.com/workspace/guides/create-project)
- **Google Cloud SDK (gcloud)** - [Installation guide](https://cloud.google.com/sdk/docs/install)
  - Can be auto-installed with `AUTO_GCLOUD=1` (Linux x86_64 or Windows with package manager)

### Linux/macOS

- `git` (auto-installed if missing)
- `jq` (auto-installed if missing on macOS with Homebrew)
- Package manager: `apt`, `dnf`, `yum`, or `brew` (macOS)

### Windows

- **PowerShell 5.1 or higher** (included in Windows 10/11)
- Optional package manager: `winget` (Windows 11), `chocolatey`, or `scoop`

---

## Quick Start

### Linux/macOS

```bash
# Download the installer
curl -O https://raw.githubusercontent.com/paolobtl/google-analytics-mcp-installer/main/setup-analytics-mcp.sh
chmod +x setup-analytics-mcp.sh

# Run with your Google Cloud project ID
GOOGLE_PROJECT_ID="your-project-id" ./setup-analytics-mcp.sh
```

### Windows

```powershell
# Download the installer (both files required)
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/paolobtl/google-analytics-mcp-installer/main/setup-analytics-mcp.bat" -OutFile "setup-analytics-mcp.bat"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/paolobtl/google-analytics-mcp-installer/main/setup-analytics-mcp.ps1" -OutFile "setup-analytics-mcp.ps1"

# Run with your Google Cloud project ID
$env:GOOGLE_PROJECT_ID="your-project-id"
.\setup-analytics-mcp.bat
```

---

## Installation Methods

### Application Default Credentials (ADC)

**Recommended for individual developers**

ADC uses your personal Google Cloud credentials. This method is simpler and doesn't require managing service account keys.

#### Linux/macOS

```bash
GOOGLE_PROJECT_ID="your-project-id" ./setup-analytics-mcp.sh
```

#### Windows

```powershell
$env:GOOGLE_PROJECT_ID="your-project-id"
.\setup-analytics-mcp.bat
```

**What happens:**
1. Opens browser for Google authentication
2. Saves credentials locally
3. Configures Gemini to use your credentials

**Credentials location:**
- Linux/macOS: `~/.config/gcloud/application_default_credentials.json` (or `~/Library/Application Support/gcloud/` on macOS)
- Windows: `%APPDATA%\gcloud\application_default_credentials.json`

---

### Service Account

**Recommended for production, shared environments, or CI/CD**

Service accounts provide more control and don't require user interaction after setup.

#### Linux/macOS

```bash
MODE=sa GOOGLE_PROJECT_ID="your-project-id" ./setup-analytics-mcp.sh
```

#### Windows

```powershell
$env:MODE="sa"
$env:GOOGLE_PROJECT_ID="your-project-id"
.\setup-analytics-mcp.bat
```

**What happens:**
1. Creates a service account in your GCP project
2. Assigns Analytics Viewer role
3. Generates and saves a JSON key file
4. Configures Gemini to use the service account

**Important:** After setup, you must manually add the service account email to your GA4 property:
1. Go to Google Analytics → Admin → Property Access Management
2. Add the service account email (shown in output)
3. Grant at least "Viewer" permissions

**Key location:**
- Linux/macOS: `~/keys/mcp-analytics.json`
- Windows: `%USERPROFILE%\keys\mcp-analytics.json`

---

## Configuration Options

### Common Options

| Option | Description | Default | Example |
|--------|-------------|---------|---------|
| `GOOGLE_PROJECT_ID` | **Required.** Your GCP project ID | - | `my-project-123` |
| `MODE` | Authentication mode: `adc` or `sa` | `adc` | `MODE=sa` |
| `ACTION` | Action to perform: `install`, `uninstall`, `update`, `verify` | `install` | `ACTION=verify` |
| `DRY_RUN` | Preview changes without executing | `0` | `DRY_RUN=1` |
| `VERBOSE` | Enable detailed logging | `0` | `VERBOSE=1` |
| `QUIET` | Suppress non-error output | `0` | `QUIET=1` |
| `NO_COLOR` | Disable colored output | `0` | `NO_COLOR=1` |

### Service Account Options (MODE=sa only)

| Option | Description | Default | Example |
|--------|-------------|---------|---------|
| `SA_NAME` | Service account name | `mcp-analytics` | `SA_NAME=my-sa` |
| `KEY_DIR` | Directory for JSON key | `~/keys` (Linux/macOS)<br>`%USERPROFILE%\keys` (Windows) | `KEY_DIR=~/secrets` |
| `KEY_PATH` | Full path to JSON key (overrides KEY_DIR) | - | `KEY_PATH=~/custom/path.json` |

### Installation Options

| Option | Description | Platform | Example |
|--------|-------------|----------|---------|
| `AUTO_GCLOUD` | Auto-install Google Cloud SDK | Linux x86_64, Windows | `AUTO_GCLOUD=1` |

---

## Advanced Usage

### Dry Run Mode

Preview all changes without executing them:

#### Linux/macOS
```bash
DRY_RUN=1 GOOGLE_PROJECT_ID="your-project-id" ./setup-analytics-mcp.sh
```

#### Windows
```powershell
$env:DRY_RUN="1"
$env:GOOGLE_PROJECT_ID="your-project-id"
.\setup-analytics-mcp.bat
```

**Output example:**
```
[DRY-RUN] Would set project to your-project-id
[DRY-RUN] Would enable analyticsadmin.googleapis.com and analyticsdata.googleapis.com
[DRY-RUN] Would run: gcloud auth application-default login
[DRY-RUN] Would update /home/user/.gemini/settings.json with MCP configuration
```

---

### Verbose Logging

Enable detailed debug output:

#### Linux/macOS
```bash
VERBOSE=1 GOOGLE_PROJECT_ID="your-project-id" ./setup-analytics-mcp.sh
```

#### Windows
```powershell
$env:VERBOSE="1"
$env:GOOGLE_PROJECT_ID="your-project-id"
.\setup-analytics-mcp.bat
```

**Output includes:**
- Python version detection
- File paths and locations
- API enablement details
- All configuration steps

---

### Uninstall

Remove MCP configuration from Gemini settings:

#### Linux/macOS
```bash
ACTION=uninstall ./setup-analytics-mcp.sh
```

#### Windows
```powershell
$env:ACTION="uninstall"
.\setup-analytics-mcp.bat
```

**What it does:**
- Removes MCP server configuration from `~/.gemini/settings.json`
- Creates backup before modification
- Does **not** delete service account or credential files

**To completely remove:**
- Manually delete credential files from `~/keys/` or `%USERPROFILE%\keys\`
- Delete service account from Google Cloud Console (if using SA mode)

---

### Verify Installation

Check if MCP is properly configured:

#### Linux/macOS
```bash
ACTION=verify ./setup-analytics-mcp.sh
```

#### Windows
```powershell
$env:ACTION="verify"
.\setup-analytics-mcp.bat
```

**Checks performed:**
1. Settings file exists and contains valid JSON
2. MCP server configuration is present
3. Credential file exists and is readable
4. File permissions are secure (600 recommended)
5. Required tools (pipx) are installed

**Output example:**
```
[INFO] Verifying MCP installation...
[OK] MCP configuration found in settings
[OK] Credentials file exists: /home/user/.config/gcloud/application_default_credentials.json
[OK] All checks passed - MCP installation appears healthy
```

---

### Update MCP

Update to the latest MCP version:

#### Linux/macOS
```bash
ACTION=update ./setup-analytics-mcp.sh
```

#### Windows
```powershell
$env:ACTION="update"
.\setup-analytics-mcp.bat
```

**Note:** The MCP is configured to run via `pipx run --spec`, which always fetches the latest version. This command verifies your installation is working correctly.

---

### Custom Service Account Configuration

Use custom names and locations for service account keys:

#### Linux/macOS
```bash
MODE=sa \
GOOGLE_PROJECT_ID="your-project-id" \
SA_NAME="custom-analytics-sa" \
KEY_DIR="$HOME/secure-keys" \
./setup-analytics-mcp.sh
```

#### Windows
```powershell
$env:MODE="sa"
$env:GOOGLE_PROJECT_ID="your-project-id"
$env:SA_NAME="custom-analytics-sa"
$env:KEY_DIR="$env:USERPROFILE\secure-keys"
.\setup-analytics-mcp.bat
```

**Creates:**
- Service account: `custom-analytics-sa@your-project-id.iam.gserviceaccount.com`
- Key file: `~/secure-keys/custom-analytics-sa.json` (or `%USERPROFILE%\secure-keys\`)

---

### Help and Version

#### Linux/macOS
```bash
./setup-analytics-mcp.sh --help
./setup-analytics-mcp.sh --version
```

#### Windows
```powershell
.\setup-analytics-mcp.bat --help
.\setup-analytics-mcp.bat --version
```

---

## Troubleshooting

### "GOOGLE_PROJECT_ID is required"

**Solution:** Set the environment variable before running:

```bash
# Linux/macOS
export GOOGLE_PROJECT_ID="your-project-id"
./setup-analytics-mcp.sh

# Windows
$env:GOOGLE_PROJECT_ID="your-project-id"
.\setup-analytics-mcp.bat
```

---

### "ADC credentials file not found"

**Cause:** You haven't authenticated with Google Cloud.

**Solution:** Run the authentication command manually:

```bash
gcloud auth application-default login --scopes="https://www.googleapis.com/auth/analytics.readonly,https://www.googleapis.com/auth/cloud-platform"
```

Then re-run the installer.

---

### "Python 3.9 or higher required"

**Solution:** Install or update Python:

- **Linux:** `sudo apt install python3` or `sudo dnf install python3`
- **macOS:** `brew install python@3.9` or download from [python.org](https://www.python.org/downloads/)
- **Windows:** Download from [python.org](https://www.python.org/downloads/)

---

### "Currently authenticated with service account from different project"

**Cause:** You're authenticated with gcloud using a service account from another (possibly deleted) project.

**What the installer does:**
- Detects if you're using a service account from a different project
- Warns you about potential permission issues
- Offers to continue or abort

**Solution:** Switch to your personal account:

```bash
# See all authenticated accounts
gcloud auth list

# Revoke the old service account
gcloud auth revoke OLD_SERVICE_ACCOUNT@project.iam.gserviceaccount.com

# Login with your personal account
gcloud auth login

# Set the correct project
gcloud config set project your-project-id

# Re-run the installer
GOOGLE_PROJECT_ID="your-project-id" ./setup-analytics-mcp.sh
```

---

### "Cannot access project"

**Cause:** The gcloud account doesn't have access to the specified project.

**The installer automatically checks:**
1. If the project exists
2. If you have permission to access it
3. If you're authenticated with the correct account

**Solution:** Verify your authentication:

```bash
# Check active account
gcloud auth list

# Verify project access
gcloud projects describe YOUR_PROJECT_ID

# If needed, switch accounts
gcloud config set account YOUR_EMAIL@gmail.com
```

---

### "gcloud not found"

**Solution Option 1:** Install manually from [Google Cloud SDK](https://cloud.google.com/sdk/docs/install)

**Solution Option 2:** Use auto-install:

```bash
# Linux x86_64
AUTO_GCLOUD=1 GOOGLE_PROJECT_ID="your-project-id" ./setup-analytics-mcp.sh

# macOS - install via Homebrew first
brew install --cask google-cloud-sdk

# Windows
$env:AUTO_GCLOUD="1"
$env:GOOGLE_PROJECT_ID="your-project-id"
.\setup-analytics-mcp.bat
```

---

### "MCP server not appearing in Gemini"

**Check 1:** Verify installation

```bash
# Linux/macOS
ACTION=verify ./setup-analytics-mcp.sh

# Windows
$env:ACTION="verify"; .\setup-analytics-mcp.bat
```

**Check 2:** Examine settings file

```bash
# Linux/macOS
cat ~/.gemini/settings.json

# Windows
Get-Content $env:USERPROFILE\.gemini\settings.json
```

Should contain:
```json
{
  "mcpServers": {
    "analytics-mcp": {
      "command": "pipx",
      "args": ["run", "--spec", "git+https://github.com/googleanalytics/google-analytics-mcp.git", "google-analytics-mcp"],
      "env": {
        "GOOGLE_APPLICATION_CREDENTIALS": "/path/to/credentials.json",
        "GOOGLE_PROJECT_ID": "your-project-id"
      }
    }
  }
}
```

**Check 3:** Verify pipx is installed

```bash
# All platforms
pipx --version
```

**Check 4:** Test MCP manually

```bash
pipx run --spec git+https://github.com/googleanalytics/google-analytics-mcp.git google-analytics-mcp
```

---

### Windows: "Cannot be loaded because running scripts is disabled"

**This should not happen** with the batch wrapper, but if you run the `.ps1` directly:

**Solution:** Use the batch wrapper instead:
```powershell
.\setup-analytics-mcp.bat
```

Or bypass manually:
```powershell
powershell.exe -ExecutionPolicy Bypass -File .\setup-analytics-mcp.ps1
```

---

### Service Account not working with GA4

**Cause:** Service account not added to GA4 property.

**Solution:**
1. Copy the service account email from installer output (e.g., `mcp-analytics@your-project-id.iam.gserviceaccount.com`)
2. Go to Google Analytics → Admin → Property Access Management
3. Click "+" → Add users
4. Paste the service account email
5. Assign "Viewer" role minimum
6. Click "Add"

---

### Permission denied errors on Linux/macOS

**Cause:** Script not executable.

**Solution:**
```bash
chmod +x setup-analytics-mcp.sh
./setup-analytics-mcp.sh
```

---

### JSON parsing errors

**Cause:** Corrupted settings file.

**Solution:** The installer creates backups automatically. If you see errors:

```bash
# Linux/macOS
mv ~/.gemini/settings.json.backup ~/.gemini/settings.json

# Windows
Move-Item $env:USERPROFILE\.gemini\settings.json.backup $env:USERPROFILE\.gemini\settings.json -Force
```

Then re-run the installer.

---

## Security Best Practices

### Service Account Keys

1. **Store securely**: Keep JSON keys in a secure directory with restricted permissions
   ```bash
   # Linux/macOS
   chmod 600 ~/keys/mcp-analytics.json

   # Windows (PowerShell)
   icacls "$env:USERPROFILE\keys\mcp-analytics.json" /inheritance:r /grant:r "$env:USERNAME:F"
   ```

2. **Rotate regularly**: Create new keys and delete old ones every 90 days
   ```bash
   # Create new key
   gcloud iam service-accounts keys create new-key.json --iam-account=mcp-analytics@your-project-id.iam.gserviceaccount.com

   # List keys to find old key ID
   gcloud iam service-accounts keys list --iam-account=mcp-analytics@your-project-id.iam.gserviceaccount.com

   # Delete old key
   gcloud iam service-accounts keys delete KEY_ID --iam-account=mcp-analytics@your-project-id.iam.gserviceaccount.com
   ```

3. **Never commit to version control**: Add to `.gitignore`:
   ```
   *.json
   keys/
   secrets/
   ```

4. **Use minimal permissions**: The installer grants only "Analytics Viewer" role

### ADC Credentials

1. **Personal use only**: Don't share ADC credentials between users
2. **Revoke when done**:
   ```bash
   gcloud auth application-default revoke
   ```

3. **Monitor access**: Check Cloud Console → IAM → Activity logs

---

## Platform-Specific Notes

### Linux

- ✅ Supports `apt`, `dnf`, and `yum` package managers
- ✅ Auto-installs missing dependencies
- ✅ `AUTO_GCLOUD=1` works on x86_64 architecture
- ⚠️ Requires `sudo` for system package installations

### macOS

- ✅ Full ADC and SA mode support
- ✅ Automatically uses Homebrew for dependencies
- ✅ Detects macOS-specific ADC path: `~/Library/Application Support/gcloud/`
- ⚠️ `AUTO_GCLOUD=1` not supported - install manually:
  ```bash
  brew install --cask google-cloud-sdk
  ```
- ⚠️ If using `zsh`, run as: `bash ./setup-analytics-mcp.sh`

### Windows

- ✅ **No PowerShell signature required** - batch wrapper bypasses execution policy
- ✅ Full ADC and SA mode support
- ✅ Supports `winget`, `chocolatey`, and `scoop` package managers
- ✅ `AUTO_GCLOUD=1` works with any supported package manager
- ✅ Native JSON handling (no `jq` dependency)
- ✅ ADC path: `%APPDATA%\gcloud\application_default_credentials.json`
- ⚠️ Run from **PowerShell** (not Command Prompt)
- ⚠️ Admin rights may be required for package installations
- ⚠️ Both `.bat` and `.ps1` files must be in the same directory

---

## Configuration File Location

The installer modifies the Gemini settings file:

- **Linux/macOS:** `~/.gemini/settings.json`
- **Windows:** `%USERPROFILE%\.gemini\settings.json`

**Backup location:** A `.backup` file is created before any modifications.

---

## Complete Examples

### Example 1: Basic ADC Installation (Linux/macOS)

```bash
# Download
curl -O https://raw.githubusercontent.com/paolobtl/google-analytics-mcp-installer/main/setup-analytics-mcp.sh
chmod +x setup-analytics-mcp.sh

# Install
GOOGLE_PROJECT_ID="my-analytics-project" ./setup-analytics-mcp.sh

# Verify
ACTION=verify ./setup-analytics-mcp.sh

# Start Gemini
gemini
# Then type: /mcp
```

### Example 2: Service Account with Custom Settings (Windows)

```powershell
# Download
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/paolobtl/google-analytics-mcp-installer/main/setup-analytics-mcp.bat" -OutFile "setup-analytics-mcp.bat"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/paolobtl/google-analytics-mcp-installer/main/setup-analytics-mcp.ps1" -OutFile "setup-analytics-mcp.ps1"

# Install with custom settings
$env:MODE="sa"
$env:GOOGLE_PROJECT_ID="production-analytics"
$env:SA_NAME="prod-analytics-reader"
$env:KEY_DIR="C:\secure\keys"
$env:VERBOSE="1"
.\setup-analytics-mcp.bat

# Verify
$env:ACTION="verify"
.\setup-analytics-mcp.bat
```

### Example 3: Dry Run Before Installation (Any Platform)

```bash
# Linux/macOS
DRY_RUN=1 VERBOSE=1 GOOGLE_PROJECT_ID="test-project" ./setup-analytics-mcp.sh

# Windows
$env:DRY_RUN="1"; $env:VERBOSE="1"; $env:GOOGLE_PROJECT_ID="test-project"; .\setup-analytics-mcp.bat
```

### Example 4: Complete Uninstall (Any Platform)

```bash
# Linux/macOS
ACTION=uninstall ./setup-analytics-mcp.sh
rm -rf ~/.gemini/settings.json.backup
rm -rf ~/keys/mcp-analytics.json
gcloud iam service-accounts delete mcp-analytics@PROJECT_ID.iam.gserviceaccount.com

# Windows
$env:ACTION="uninstall"; .\setup-analytics-mcp.bat
Remove-Item $env:USERPROFILE\.gemini\settings.json.backup -Force
Remove-Item $env:USERPROFILE\keys\mcp-analytics.json -Force
gcloud iam service-accounts delete mcp-analytics@PROJECT_ID.iam.gserviceaccount.com
```

---

## Contributing

Contributions welcome! Please submit issues or pull requests at:
https://github.com/paolobtl/google-analytics-mcp-installer

---

## License

[Apache 2.0](https://github.com/paolobtl/google-analytics-mcp-installer/blob/main/LICENSE)

---

## Support

- **Issues:** https://github.com/paolobtl/google-analytics-mcp-installer/issues
- **Google Analytics MCP:** https://github.com/googleanalytics/google-analytics-mcp
- **Gemini CLI:** https://github.com/google-gemini/gemini-cli
- **Google Cloud SDK:** https://cloud.google.com/sdk/docs
