# Google Analytics MCP Setup

Automated setup script to configure **Google Analytics MCP** for Gemini CLI.

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
- `pipx` (installed automatically if missing)
- `jq`
- `git`
- `gcloud` SDK → [Install Guide](https://cloud.google.com/sdk/docs/install)
- `npm` or `brew` (optional, for Gemini CLI)

---


## Usage


### 1. Download the setup script


```bash
curl -O https://raw.githubusercontent.com/paolobtl/google-analytics-mcp-installer/setup-analytics-mcp.sh
chmod +x setup-analytics-mcp.sh
```


### 2. Run with Application Default Credentials (**recommended**)


```bash
GOOGLE_PROJECT_ID="my-project" ./setup-analytics-mcp.sh
```


This will:
- Prompt you to log in via browser.
- Save your credentials automatically.
- Configure Gemini MCP.


---


### 3. Run with Service Account JSON


```bash
MODE=sa GOOGLE_PROJECT_ID="my-project" ./setup-analytics-mcp.sh
```


This will:
- Create a Service Account (if missing).
- Assign **Analytics Viewer** role.
- Generate and download a JSON key.
- Configure Gemini MCP.

---


### 4. Verify Gemini MCP Setup


Start Gemini:


```bash
gemini
```


Inside Gemini, type:


```bash
/mcp
```


You should see:


```
analytics-mcp ✅ active
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

* By default, Service Accounts get **Analytics Viewer** only.
* JSON keys are stored in `$HOME/keys` by default.
* Consider rotating keys regularly.

---
### **Usage Examples**

#### **1. Default mode (ADC — recommended)**

```bash
GOOGLE_PROJECT_ID="my-project" ./setup-analytics-mcp.sh
```

* Uses **Application Default Credentials**.
* Prompts browser login.
* Stores credentials automatically.

---

#### **2. Service Account mode**

```bash
MODE=sa GOOGLE_PROJECT_ID="my-project" ./setup-analytics-mcp.sh
```

* Creates a Service Account named `mcp-analytics` (default).
* Generates a JSON key in `~/keys/mcp-analytics.json`.
* Assigns **Analytics Viewer** role automatically.

---

#### **3. Custom Service Account name**

```bash
MODE=sa GOOGLE_PROJECT_ID="my-project" SA_NAME="my-custom-sa" ./setup-analytics-mcp.sh
```

* Uses `my-custom-sa` instead of the default `mcp-analytics`.

---

#### **4. Custom key directory**

```bash
MODE=sa GOOGLE_PROJECT_ID="my-project" KEY_DIR="$HOME/secrets" ./setup-analytics-mcp.sh
```

* Stores JSON key in `~/secrets/mcp-analytics.json`.

---

#### **5. Predefined custom key path**

```bash
MODE=sa GOOGLE_PROJECT_ID="my-project" KEY_PATH="$HOME/secrets/ga-key.json" ./setup-analytics-mcp.sh
```

* Uses exactly the file path you specify for the JSON key.

---

#### **6. Automatic gcloud installation (Linux x86\_64 only)**

```bash
AUTO_GCLOUD=1 GOOGLE_PROJECT_ID="my-project" ./setup-analytics-mcp.sh
```

* If `gcloud` is missing, installs the Google Cloud SDK automatically.

---


## License

Apache 2.0


