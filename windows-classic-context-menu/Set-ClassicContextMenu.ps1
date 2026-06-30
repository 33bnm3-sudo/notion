<#
.SYNOPSIS
    Switches between the Windows 11 compact right-click menu and the classic
    Windows 10 full context menu.

.PARAMETER Mode
    "Classic" to restore the Windows 10 style menu, "Windows11" to revert
    back to the new compact menu.

.EXAMPLE
    .\Set-ClassicContextMenu.ps1 -Mode Classic
    .\Set-ClassicContextMenu.ps1 -Mode Windows11
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Classic", "Windows11")]
    [string]$Mode
)

$keyPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"

if ($Mode -eq "Classic") {
    if (-not (Test-Path $keyPath)) {
        New-Item -Path $keyPath -Force | Out-Null
    }
    Set-ItemProperty -Path $keyPath -Name "(default)" -Value ""
    Write-Host "Classic (Windows 10 style) context menu enabled."
}
else {
    $clsidPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
    if (Test-Path $clsidPath) {
        Remove-Item -Path $clsidPath -Recurse -Force
    }
    Write-Host "Windows 11 compact context menu restored."
}

Write-Host "Restarting Explorer to apply the change..."
Stop-Process -Name explorer -Force
Start-Sleep -Milliseconds 800
Start-Process explorer.exe

# Force-redraw the desktop wallpaper so it doesn't sit on a black
# screen while Explorer finishes reloading.
Start-Sleep -Milliseconds 1500
RUNDLL32.EXE user32.dll, UpdatePerUserSystemParameters
