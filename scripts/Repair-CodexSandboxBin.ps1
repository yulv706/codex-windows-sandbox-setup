# Diagnose or repair the Codex elevated-sandbox lockout on .sandbox-bin.
# Diagnose is read-only. -Repair changes only the directory owner, and only when elevated.
[CmdletBinding()]
param(
    [switch]$Repair,
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" })
)

$ErrorActionPreference = "Stop"
$AdministratorsSid = "S-1-5-32-544"
$WriteDac = 0x40000

$bin = Join-Path $CodexHome ".sandbox-bin"
$sandbox = Join-Path $CodexHome ".sandbox"
$markerPath = Join-Path $sandbox "setup_marker.json"
$errorPath = Join-Path $sandbox "setup_error.json"

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-OwnerSid {
    param($Acl)
    return $Acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
}

if (-not (Test-Path -LiteralPath $bin)) {
    Write-Host "diagnosis: missing-sandbox-bin"
    Write-Host "path: $bin"
    Write-Host "Do not create or rename this directory. Open Codex and rerun the diagnose."
    exit 1
}

$acl = Get-Acl -LiteralPath $bin
$ownerSid = Get-OwnerSid $acl
$systemMask = 0
foreach ($ace in $acl.Access) {
    $sid = $null
    if ($ace.IdentityReference -is [System.Security.Principal.SecurityIdentifier]) {
        $sid = $ace.IdentityReference.Value
    }
    else {
        try {
            $sid = $ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
        }
        catch {
            continue
        }
    }
    if ($sid -eq "S-1-5-18" -and $ace.AccessControlType -eq "Allow") {
        $systemMask = $systemMask -bor [int]$ace.FileSystemRights
    }
}

$systemHasWriteDac = ($systemMask -band $WriteDac) -ne 0
$ownerIsAdministrators = $ownerSid -eq $AdministratorsSid
$markerBytes = if (Test-Path -LiteralPath $markerPath) { (Get-Item -LiteralPath $markerPath).Length } else { -1 }
$errorCode = ""
if (Test-Path -LiteralPath $errorPath) {
    try {
        $errorCode = [string](Get-Content -LiteralPath $errorPath -Raw | ConvertFrom-Json).code
    }
    catch {
        $errorCode = "unreadable"
    }
}

Write-Host "sandbox-bin: $bin"
Write-Host "owner-sid: $ownerSid"
Write-Host "protected: $($acl.AreAccessRulesProtected)"
Write-Host "system-write-dac: $systemHasWriteDac"
Write-Host "marker-bytes: $markerBytes"
Write-Host "setup-error: $(if ($errorCode) { $errorCode } else { '(none)' })"

$serviceLockedOut = $acl.AreAccessRulesProtected -and -not $systemHasWriteDac -and -not $ownerIsAdministrators
if ($serviceLockedOut) {
    Write-Host "diagnosis: service-lockout"
    if (-not $Repair) {
        Write-Host "fix: takeown /F `"$bin`" /A"
        Write-Host "Re-run elevated with -Repair. Do not delete or rename .sandbox-bin."
        exit 2
    }
    if (-not (Test-IsAdmin)) {
        Write-Host "Repair requires an elevated PowerShell. Approve UAC, then rerun -Repair."
        exit 2
    }
    & takeown.exe /F $bin /A
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $ownerAfter = Get-OwnerSid (Get-Acl -LiteralPath $bin)
    Write-Host "owner-after: $ownerAfter"
    if ($ownerAfter -ne $AdministratorsSid) {
        Write-Host "diagnosis: repair-failed"
        exit 1
    }
    Write-Host "repaired. Click Continue in Codex so it rewrites setup_marker.json."
    exit 0
}

if ($ownerIsAdministrators -or $systemHasWriteDac) {
    $markerStale = $markerBytes -eq 0 -or $errorCode -eq "helper_sandbox_lock_failed"
    if ($markerStale) {
        Write-Host "diagnosis: ownership-ok-marker-stale"
        Write-Host "Click Continue once in Codex. Do not edit setup_marker.json by hand."
        exit 3
    }
    Write-Host "diagnosis: ok"
    exit 0
}

Write-Host "diagnosis: inconclusive"
Write-Host "Read references/mechanism.md before changing permissions."
exit 4
