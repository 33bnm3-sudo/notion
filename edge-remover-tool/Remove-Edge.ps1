<#
.SYNOPSIS
    Best-effort removal of Microsoft Edge (Chromium) on Windows 11.

.DESCRIPTION
    Microsoft does not officially support fully removing Edge - there is
    no guarantee this stays removed forever (a future Windows feature
    update can reinstall it). This script:
      1. Stops Edge and Edge Update processes/services
      2. Disables the Edge auto-update scheduled tasks and services so
         Windows is less likely to silently reinstall it
      3. Runs Edge's own uninstaller (setup.exe --uninstall) for the
         system-level install
      4. Removes leftover install folders and shortcuts
    It deliberately leaves the Microsoft Edge WebView2 Runtime alone,
    since many third-party apps (KakaoTalk, Discord, etc.) depend on it
    and removing it can break those apps.

    Must be run as Administrator.
#>

#Requires -RunAsAdministrator

Write-Host "=== Step 1: Stopping Edge and Edge Update processes ===" -ForegroundColor Cyan
Get-Process -Name "msedge", "MicrosoftEdgeUpdate", "MicrosoftEdge*" -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

Write-Host "=== Step 2: Disabling Edge auto-update services and tasks ===" -ForegroundColor Cyan
foreach ($svc in @("edgeupdate", "edgeupdatem")) {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Write-Host "Disabled service: $svc"
    }
}

foreach ($task in @(
    "MicrosoftEdgeUpdateTaskMachineCore",
    "MicrosoftEdgeUpdateTaskMachineUA",
    "MicrosoftEdgeUpdateBrowserReplacementTask"
)) {
    if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) {
        Disable-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue | Out-Null
        Write-Host "Disabled scheduled task: $task"
    }
}

Write-Host "=== Step 3: Blocking Edge reinstall via policy ===" -ForegroundColor Cyan
$edgeUpdatePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate"
if (-not (Test-Path $edgeUpdatePolicyPath)) {
    New-Item -Path $edgeUpdatePolicyPath -Force | Out-Null
}
# Stable channel GUID for Edge
New-ItemProperty -Path $edgeUpdatePolicyPath -Name "Update{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}" -Value 0 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $edgeUpdatePolicyPath -Name "InstallDefault" -Value 0 -PropertyType DWord -Force | Out-Null

Write-Host "=== Step 4: Running Edge's own uninstaller ===" -ForegroundColor Cyan
$setupCandidates = Get-ChildItem -Path "C:\Program Files (x86)\Microsoft\Edge\Application", "C:\Program Files\Microsoft\Edge\Application" `
    -Recurse -Filter "setup.exe" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match "\\Installer\\setup\.exe$" }

if ($setupCandidates) {
    foreach ($setup in $setupCandidates) {
        Write-Host "Found uninstaller: $($setup.FullName)"
        Start-Process -FilePath $setup.FullName `
            -ArgumentList "--uninstall --system-level --verbose-logging --force-uninstall" `
            -Wait -ErrorAction SilentlyContinue
    }
}
else {
    Write-Host "No Edge uninstaller found under Program Files. It may already be removed, or installed per-user." -ForegroundColor Yellow
}

Write-Host "=== Step 5: Cleaning up leftover folders and shortcuts ===" -ForegroundColor Cyan
$pathsToRemove = @(
    "C:\Program Files (x86)\Microsoft\Edge",
    "$env:PUBLIC\Desktop\Microsoft Edge.lnk",
    "$env:USERPROFILE\Desktop\Microsoft Edge.lnk",
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk",
    "$env:USERPROFILE\AppData\Local\Microsoft\Edge"
)
foreach ($p in $pathsToRemove) {
    if (Test-Path $p) {
        Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Removed: $p"
    }
}

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Green
Write-Host "Edge has been uninstalled where possible, and auto-reinstall has been blocked via policy."
Write-Host "Note: WebView2 Runtime was intentionally left in place since other apps depend on it."
Write-Host "A future major Windows feature update may still reinstall Edge - if that happens, just re-run this script."
