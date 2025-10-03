@echo off
setlocal enabledelayedexpansion

REM =============================================================
REM Google Analytics MCP Setup - Batch Wrapper
REM This wrapper avoids PowerShell execution policy issues
REM =============================================================

REM Get the directory where this batch file is located
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%setup-analytics-mcp.ps1"

REM Check if PowerShell script exists
if not exist "%PS_SCRIPT%" (
    echo [ERROR] PowerShell script not found: %PS_SCRIPT%
    exit /b 1
)

REM Execute PowerShell script with bypassed execution policy
REM -ExecutionPolicy Bypass: Avoids signature requirement
REM -NoProfile: Speeds up execution
REM -File: Executes the script file
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%PS_SCRIPT%" %*

REM Pass through the exit code
exit /b %ERRORLEVEL%
