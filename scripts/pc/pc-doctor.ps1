<#
.SYNOPSIS
  Checks the always-on Windows PC is ready as a Hylite test machine
  (docs/specifications/mac-mini-build-plan.md section 10.6). Read-only.
.DESCRIPTION
  Prints an OK / FIX / WARN list. Never reads secret files. Drive encryption
  can need an elevated prompt; the script says so when it does.
  Run:  powershell -ExecutionPolicy Bypass -File scripts\pc\pc-doctor.ps1
#>
$ErrorActionPreference = 'Continue'
$FlutterPin = '3.41.2'
$script:ok = 0; $script:fix = 0; $script:warn = 0
function Ok($m)   { $script:ok++;   Write-Host "OK    $m" }
function Fix($m)  { $script:fix++;  Write-Host "FIX   $m" }
function Warn($m) { $script:warn++; Write-Host "WARN  $m" }
function Have($n) { return [bool](Get-Command $n -ErrorAction SilentlyContinue) }
function FirstLine($cmd, $argList) {
  try { $o = & $cmd @argList 2>&1 | Select-Object -First 1; return "$o".Trim() } catch { return '' }
}

Write-Host 'Hylite PC doctor'
Write-Host ''
Ok ("Windows: " + [System.Environment]::OSVersion.VersionString)

# --- Tools
if (Have 'git')  { Ok (FirstLine 'git' @('--version')) } else { Fix 'Git missing: install Git for Windows.' }
if (Have 'node') { Ok ("Node " + (FirstLine 'node' @('--version'))) } else { Fix 'Node missing: install the LTS version.' }
if (Have 'pnpm') { Ok ("pnpm " + (FirstLine 'pnpm' @('--version'))) } else { Fix 'pnpm missing: npm install -g pnpm (or corepack enable).' }
if (Have 'java') { Ok ("Java: " + (FirstLine 'java' @('-version'))) } else { Fix 'Java missing (needed by the Firebase rules tests, npm run test:rules).' }
if (Have 'flutter') {
  $v = FirstLine 'flutter' @('--version')
  if ($v -match '^Flutter\s+([0-9][0-9.]*)') {
    if ($Matches[1] -eq $FlutterPin) { Ok "Flutter $($Matches[1])" }
    else { Fix "Flutter is $($Matches[1]); must be exactly $FlutterPin (do not upgrade)." }
  } else { Fix 'flutter did not report a version; run flutter doctor -v.' }
} else { Fix "flutter not on PATH (install $FlutterPin)." }

# --- Playwright browsers (default cache, or PLAYWRIGHT_BROWSERS_PATH)
$pw = $env:PLAYWRIGHT_BROWSERS_PATH
if (-not $pw) { $pw = Join-Path $env:LOCALAPPDATA 'ms-playwright' }
if (Test-Path $pw) {
  $b = @(Get-ChildItem -Path $pw -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(chromium|firefox|webkit)' })
  if ($b.Count -gt 0) { Ok ("Playwright browsers installed: " + (($b | ForEach-Object { $_.Name }) -join ', ')) }
  else { Fix 'Playwright folder has no browsers: run pnpm exec playwright install (in apps/web).' }
} else { Fix 'Playwright browsers not installed: run pnpm exec playwright install (in apps/web).' }

# --- Power plan: sleep and hibernate on AC must be never (0)
function AcIndex($sub, $setting) {
  try {
    $out = & powercfg /query SCHEME_CURRENT $sub $setting 2>&1 | Out-String
    $hex = [regex]::Matches($out, '0x[0-9a-fA-F]+')
    if ($hex.Count -ge 2) { return [Convert]::ToInt64($hex[$hex.Count - 2].Value, 16) }  # AC then DC are the last two
  } catch { }
  return $null
}
if (Have 'powercfg') {
  $sleepAc = AcIndex 'SUB_SLEEP' 'STANDBYIDLE'
  if ($null -eq $sleepAc) { Warn 'Could not read the sleep setting from powercfg.' }
  elseif ($sleepAc -eq 0) { Ok 'Sleep on AC power: never' }
  else { Fix "Sleep on AC is $([int]($sleepAc/60)) min: run powercfg /change standby-timeout-ac 0" }
  $hibAc = AcIndex 'SUB_SLEEP' 'HIBERNATEIDLE'
  if ($null -eq $hibAc) { Warn 'Could not read the hibernate setting.' }
  elseif ($hibAc -eq 0) { Ok 'Hibernate on AC power: never' }
  else { Fix 'Hibernate on AC is on: run powercfg /change hibernate-timeout-ac 0' }
} else { Fix 'powercfg not found.' }
try {
  $fs = Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction Stop
  if ($fs -eq 0) { Ok 'Fast Startup: off' } else { Warn 'Fast Startup is on (plan 10.4 says off): powercfg /h off, or Control Panel > Power Options.' }
} catch { Warn 'Could not read the Fast Startup setting.' }

# --- Drive encryption (read-only). manage-bde needs an elevated prompt.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$enc = $null
if ($isAdmin -and (Have 'manage-bde')) {
  $s = & manage-bde -status C: 2>&1 | Out-String
  if ($s -match 'Protection On') { $enc = $true } elseif ($s -match 'Protection Off') { $enc = $false }
}
if ($null -eq $enc) {
  # No admin: ask the shell (unverified mapping: 1 = protection on).
  try {
    $p = (New-Object -ComObject Shell.Application).NameSpace('C:').Self.ExtendedProperty('System.Volume.BitLockerProtection')
    if ($p -eq 1) { $enc = $true } elseif ($p -eq 0) { $enc = $false }
  } catch { }
}
if ($enc -eq $true) { Ok 'C: drive encryption (BitLocker / device encryption): on' }
elseif ($enc -eq $false) { Fix 'C: is not encrypted: turn on BitLocker or device encryption and save the recovery key.' }
else { Warn 'Could not read encryption status. Re-run this script from an elevated (Administrator) PowerShell so manage-bde -status C: works.' }

Write-Host ''
Write-Host "Result: $($script:ok) OK, $($script:warn) WARN, $($script:fix) FIX"
if ($script:fix -gt 0) { Write-Host 'Not ready: fix the FIX lines above.'; exit 1 }
Write-Host 'Ready for the first manual runs (plan 10.6 step 7).'
exit 0
