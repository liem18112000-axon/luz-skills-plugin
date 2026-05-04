# ensure-bash.ps1 — Windows bash bootstrap helper.
# Run once: powershell -ExecutionPolicy Bypass -File ensure-bash.ps1
# Verifies a working `bash` is reachable. If missing or broken (e.g. Windows'
# WSL bash stub with no distro installed), tries common Git Bash install paths,
# then winget-installs Git for Windows. Idempotent — safe to re-run.

$ErrorActionPreference = 'Stop'

function Test-Bash([string]$exe) {
    if ([string]::IsNullOrWhiteSpace($exe)) { return $false }
    if (-not (Test-Path $exe)) { return $false }
    try {
        $out = & $exe -c "echo ok" 2>$null
        return ($LASTEXITCODE -eq 0 -and $out -eq "ok")
    } catch {
        return $false
    }
}

function Find-Bash {
    $cmd = Get-Command bash -ErrorAction SilentlyContinue
    if ($cmd -and (Test-Bash $cmd.Source)) { return $cmd.Source }
    $candidates = @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "$env:ProgramFiles\Git\usr\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Bash $p) { return $p }
    }
    return $null
}

$bash = Find-Bash
if ($bash) {
    $v = (& $bash --version | Select-Object -First 1)
    Write-Host "Working bash found: $bash"
    Write-Host "  $v"
    exit 0
}

Write-Host "No working bash found (Windows WSL stub without a distro counts as broken)."
Write-Host "Attempting to install Git for Windows (provides Git Bash) ..."

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error "winget is not available. Install Git for Windows manually from https://git-scm.com/download/win then re-open the shell."
    exit 1
}

winget install --id Git.Git -e --source winget --accept-source-agreements --accept-package-agreements
if ($LASTEXITCODE -ne 0) {
    Write-Error "winget install failed (exit $LASTEXITCODE). Install Git for Windows manually from https://git-scm.com/download/win"
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Git for Windows installed. Open a NEW PowerShell / cmd window so PATH picks up bash, then re-run your skill."
Write-Host "If the WSL bash stub still wins on PATH, invoke Git Bash directly: `"$env:ProgramFiles\Git\bin\bash.exe`" <script.sh>"
