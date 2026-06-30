<#
.SYNOPSIS
    Re-applies the currently configured desktop wallpaper.
    Useful after Explorer has been restarted (e.g. by the context-menu
    tool) and the desktop is stuck showing a black/blank background.
#>

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@

$SPI_SETDESKWALLPAPER = 0x0014
$SPIF_UPDATEINIFILE = 0x01
$SPIF_SENDWININICHANGE = 0x02

$wallpaperPath = (Get-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name Wallpaper -ErrorAction SilentlyContinue).Wallpaper

if ([string]::IsNullOrWhiteSpace($wallpaperPath)) {
    Write-Host "No wallpaper path found in the registry. Trying a generic refresh instead..."
}
else {
    Write-Host "Re-applying wallpaper: $wallpaperPath"
    [Wallpaper]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $wallpaperPath, $SPIF_UPDATEINIFILE -bor $SPIF_SENDWININICHANGE) | Out-Null
}

# Also nudge Explorer to re-read all per-user system parameters
# (wallpaper, theme colors, etc.) in case the value above wasn't enough.
RUNDLL32.EXE user32.dll, UpdatePerUserSystemParameters

Write-Host "Done. If the desktop is still black, restart Explorer once more from Task Manager."
