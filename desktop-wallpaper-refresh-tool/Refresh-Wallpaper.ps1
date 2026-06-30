<#
.SYNOPSIS
    Re-applies the currently configured desktop background (picture or
    solid color). Useful after Explorer has been restarted (e.g. by the
    context-menu tool) and the desktop is stuck showing a black/blank
    background.
#>

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);

    [DllImport("user32.dll")]
    public static extern bool SetSysColors(int cElements, int[] lpaElements, int[] lpaRgbValues);
}
"@

$SPI_SETDESKWALLPAPER = 0x0014
$SPIF_UPDATEINIFILE = 0x01
$SPIF_SENDWININICHANGE = 0x02
$COLOR_DESKTOP = 1

$wallpaperPath = (Get-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name Wallpaper -ErrorAction SilentlyContinue).Wallpaper

if (-not [string]::IsNullOrWhiteSpace($wallpaperPath)) {
    Write-Host "Re-applying wallpaper image: $wallpaperPath"
    [Wallpaper]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $wallpaperPath, $SPIF_UPDATEINIFILE -bor $SPIF_SENDWININICHANGE) | Out-Null
}
else {
    Write-Host "No wallpaper image set - looks like a solid color background. Re-applying the color instead..."

    $bgColor = (Get-ItemProperty -Path "HKCU:\Control Panel\Colors" -Name Background -ErrorAction SilentlyContinue).Background

    if ($bgColor) {
        $rgb = $bgColor -split " " | ForEach-Object { [int]$_ }
        $colorRef = $rgb[0] -bor ($rgb[1] -shl 8) -bor ($rgb[2] -shl 16)
        [Wallpaper]::SetSysColors(1, @($COLOR_DESKTOP), @($colorRef)) | Out-Null
        Write-Host "Re-applied solid background color: RGB($($rgb[0]), $($rgb[1]), $($rgb[2]))"
    }
    else {
        Write-Host "Could not find a saved background color either. Try restarting Explorer instead."
    }
}

# Also nudge Explorer to re-read all per-user system parameters
# (wallpaper, theme colors, etc.) in case the value above wasn't enough.
RUNDLL32.EXE user32.dll, UpdatePerUserSystemParameters

Write-Host "Done. If the desktop is still black, restart Explorer once more from Task Manager."
