<#
.SYNOPSIS
  Installs Docker Desktop (WSL2 backend) on native Windows if it is missing.
.DESCRIPTION
  Git, the AWS CLI and mise are deliberately not installed here. Run
  setup-dev-environment.sh inside WSL for those. Safe to re-run.
#>
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

function Write-Log($Message) { Write-Host "==> $Message" }

function Test-Command($Name) { [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Test-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent())
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    throw 'Run this script from an elevated (Run as administrator) PowerShell session.'
}

if (-not (Test-Command winget)) {
    throw 'winget not found. Install "App Installer" from the Microsoft Store, then re-run.'
}

# Docker Desktop uses the WSL2 backend, so make sure WSL itself is present.
$rebootNeeded = $false
wsl.exe --status *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Log 'Installing WSL (no distribution)'
    wsl.exe --install --no-distribution
    $rebootNeeded = $true
} else {
    Write-Log 'WSL already installed'
}

$dockerExe = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
if ((Test-Command docker) -or (Test-Path $dockerExe)) {
    Write-Log 'Docker Desktop already installed'
} else {
    Write-Log 'Installing Docker Desktop'
    winget install --id Docker.DockerDesktop --exact --silent `
        --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget failed with exit code $LASTEXITCODE" }
    $rebootNeeded = $true
}

Write-Log 'Next steps'
if ($rebootNeeded) { Write-Host '  1. Restart Windows' }
Write-Host '  - Start Docker Desktop once and accept the licence terms'
Write-Host '  - Settings > Resources > WSL integration: enable your WSL distro'
Write-Host '  - Inside WSL, run ./setup-dev-environment.sh for git, mise and the AWS CLI'
