# Google Analytics MCP Setup

Automated setup script to configure **Google Analytics MCP** for Gemini CLI.

##### Table of Contents
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Usage](#usage)
  - [1. Download the setup script](#1-download-the-setup-script)
  - [2. Run with Application Default Credentials (recommended)](#2-run-with-application-default-credentials-recommended)
  - [3. Run with Service Account JSON](#3-run-with-service-account-json)
  - [4. Optional advanced arguments](#4-optional-advanced-arguments)
  - [5. Verify Gemini MCP Setup](#5-verify-gemini-mcp-setup)
- [Windows Usage](#windows-usage)
  - [1. Download the setup script](#1-download-the-setup-script-1)
  - [2. Run with Application Default Credentials (recommended)](#2-run-with-application-default-credentials-recommended-1)
  - [3. Run with Service Account JSON](#3-run-with-service-account-json-1)
  - [4. Optional arguments](#4-optional-arguments)
  - [5. Verify Gemini MCP Setup](#5-verify-gemini-mcp-setup-1)
- [macOS Notes](#macos-notes)
- [Troubleshooting](#troubleshooting)
- [Security Notes](#security-notes)
- [License](#license)


---

## Features

- Installs and configures [google-analytics-mcp](https://github.com/googleanalytics/google-analytics-mcp)
- Supports **ADC** (Application Default Credentials) or **Service Account JSON**
- Ensures required Google APIs are enabled
- Generates the correct Gemini `settings.json`
- Installs Gemini CLI automatically if missing

---

## Prerequisites

- **Python 3.9+**
- A Google Cloud Porject → [Create a Google Cloud project](https://developers.google.com/workspace/guides/create-project)
- `pipx` (installed automatically if missing)
- `jq`
- `git`
- `gcloud` SDK → [Install Guide](https://cloud.google.com/sdk/docs/install)
- `npm` or `brew` (optional, for Gemini CLI)

---

## Usage

### **1. Download the setup script**

```bash
curl -O https://raw.githubusercontent.com/paolobtl/google-analytics-mcp-installer/refs/heads/main/setup-analytics-mcp.sh
chmod +x setup-analytics-mcp.sh
```

### **2. Run with Application Default Credentials (recommended)**

```bash
GOOGLE_PROJECT_ID="my-project" ./setup-analytics-mcp.sh
```

### **3. Run with Service Account JSON**

```bash
MODE=sa GOOGLE_PROJECT_ID="my-project" ./setup-analytics-mcp.sh
```

### **4. Optional arguments**

| Variable      | Description                                | Example |
|--------------|--------------------------------------------|----------------------------|
| `SA_NAME`    | Custom Service Account name                | `SA_NAME="custom-sa"` |
| `KEY_DIR`    | Directory where JSON key is stored         | `KEY_DIR="$HOME/secrets"` |
| `KEY_PATH`   | Full path for JSON key                     | `KEY_PATH="$HOME/keys/ga.json"` |
| `AUTO_GCLOUD`| Auto-install `gcloud` (Linux x86_64 only)  | `AUTO_GCLOUD=1` |

Example:
```bash
MODE=sa GOOGLE_PROJECT_ID="my-project" SA_NAME="custom-sa" KEY_DIR="$HOME/secrets" ./setup-analytics-mcp.sh
```

### **5. Verify Gemini MCP Setup**

```bash
gemini
```
Inside Gemini:
```bash
/mcp
```
You should see:
```
🟢 analytics-mcp - Ready
```
Here's the **Windows usage section** to add to the README:

---

## **Windows Usage**

### **1. Download the setup script**

```powershell
curl -O https://raw.githubusercontent.com/paolobtl/google-analytics-mcp-installer/refs/heads/main/setup-analytics-mcp.ps1
```

### **2. Run with Application Default Credentials (recommended)**

```powershell
$env:GOOGLE_PROJECT_ID="my-project"
.\setup-analytics-mcp.ps1
```

* Opens your browser for authentication.
* Stores credentials automatically.
* Configures Gemini MCP.

---

### **3. Run with Service Account JSON**

```powershell
$env:MODE="sa"
$env:GOOGLE_PROJECT_ID="my-project"
.\setup-analytics-mcp.ps1
```

* Creates a Service Account if missing.
* Assigns **Analytics Viewer** role.
* Generates and downloads a JSON key into `$HOME\keys`.
* Configures Gemini MCP.

---

### **4. Optional arguments**

| Environment Variable | Description                  | Example                                |
| -------------------- | ---------------------------- | -------------------------------------- |
| `SA_NAME`            | Custom Service Account name  | `$env:SA_NAME=\"custom-sa\"`           |
| `KEY_DIR`            | Directory to store JSON keys | `$env:KEY_DIR=\"$HOME\\secrets\"`      |
| `KEY_PATH`           | Full path to JSON key        | `$env:KEY_PATH=\"$HOME\\ga-key.json\"` |

Example:

```powershell
$env:MODE="sa"
$env:GOOGLE_PROJECT_ID="my-project"
$env:SA_NAME="custom-sa"
$env:KEY_DIR="$HOME\\secrets"
.\setup-analytics-mcp.ps1
```

---

### **5. Verify Gemini MCP Setup**

```powershell
gemini
```

Inside Gemini, run:

```bash
/mcp
```

You should see:

```
🟢 analytics-mcp - Ready
```

---

Do you also want me to prepare a **combined cross-platform README** where macOS, Linux, and Windows instructions are integrated cleanly? It could make everything much easier to maintain.

---

## macOS Notes

- ✅ **ADC & SA modes** work normally.
- ✅ Homebrew is used for installing `jq`, `git`, or `gemini-cli` when missing.
- ⚠️ **AUTO_GCLOUD=1** is **not supported** on macOS. Install gcloud manually:
  ```bash
  brew install --cask google-cloud-sdk
  ```
- ✅ The script automatically detects the macOS ADC path:
  ```
  ~/Library/Application Support/gcloud/application_default_credentials.json
  ```
- ⚠️ If you use `zsh`, run the script via:
  ```bash
  bash ./setup-analytics-mcp.sh
  ```

---

## Troubleshooting

### ❌ `ADC credentials not found`
Run:
```bash
gcloud auth application-default login --scopes="https://www.googleapis.com/auth/analytics.readonly,https://www.googleapis.com/auth/cloud-platform"
```
Then re-run the script.

---



## Security Notes

- By default, Service Accounts get **Analytics Viewer** only.
- JSON keys are stored in `$HOME/keys` by default.
- Consider rotating keys regularly.

---

## License

Apache 2.0
