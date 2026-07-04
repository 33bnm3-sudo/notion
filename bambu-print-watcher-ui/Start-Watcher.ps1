<#
.SYNOPSIS
    Minimal WinForms GUI for bambu-print-watcher: enter the printer's
    IP/serial/access code and launch the watcher. Since the watcher is
    a long-running background process (not a one-shot conversion like
    the other test tools), this just launches it in its own visible
    console window rather than trying to stream its output into this
    GUI - simpler and avoids WinForms cross-thread pitfalls.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$WatcherDir = Join-Path (Split-Path $PSScriptRoot -Parent) "bambu-print-watcher"
$WatcherScript = Join-Path $WatcherDir "watch.py"
$DiscoverScript = Join-Path $WatcherDir "discover.py"

$ConfigDir = Join-Path $env:APPDATA "BambuPrintWatcher"
$ConfigPath = Join-Path $ConfigDir "config.json"

function Load-Config {
    if (Test-Path $ConfigPath) {
        try { return Get-Content $ConfigPath -Raw | ConvertFrom-Json } catch { return $null }
    }
    return $null
}

function Save-Config($ip, $serial, $accessCode) {
    if (-not (Test-Path $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    }
    [PSCustomObject]@{ ip = $ip; serial = $serial; accessCode = $accessCode } |
        ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
}

$saved = Load-Config
$HasPython = [bool](Get-Command python -ErrorAction SilentlyContinue)

# ---- Form ----
$form = New-Object System.Windows.Forms.Form
$form.Text = "Bambu Print Watcher"
$form.Size = New-Object System.Drawing.Size(480, 400)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$y = 15

if (-not $HasPython) {
    $lblWarning = New-Object System.Windows.Forms.Label
    $lblWarning.Text = "Python not found on PATH. Install Python first (https://python.org)."
    $lblWarning.Location = New-Object System.Drawing.Point(15, $y)
    $lblWarning.Size = New-Object System.Drawing.Size(440, 24)
    $lblWarning.ForeColor = [System.Drawing.Color]::Firebrick
    $form.Controls.Add($lblWarning)
    $y += 30
}
if (-not (Test-Path $WatcherScript)) {
    $lblWarning2 = New-Object System.Windows.Forms.Label
    $lblWarning2.Text = "watch.py not found - expected at: $WatcherScript"
    $lblWarning2.Location = New-Object System.Drawing.Point(15, $y)
    $lblWarning2.Size = New-Object System.Drawing.Size(440, 24)
    $lblWarning2.ForeColor = [System.Drawing.Color]::Firebrick
    $form.Controls.Add($lblWarning2)
    $y += 30
}

$lblDiscovered = New-Object System.Windows.Forms.Label
$lblDiscovered.Text = "Discovered printers:"
$lblDiscovered.Location = New-Object System.Drawing.Point(15, $y)
$lblDiscovered.AutoSize = $true
$form.Controls.Add($lblDiscovered)

$cmbDiscovered = New-Object System.Windows.Forms.ComboBox
$cmbDiscovered.Location = New-Object System.Drawing.Point(150, ($y - 3))
$cmbDiscovered.Size = New-Object System.Drawing.Size(200, 24)
$cmbDiscovered.DropDownStyle = "DropDownList"
$form.Controls.Add($cmbDiscovered)

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text = "Scan (5s)"
$btnScan.Location = New-Object System.Drawing.Point(360, ($y - 4))
$btnScan.Size = New-Object System.Drawing.Size(90, 26)
$btnScan.Enabled = $HasPython
$form.Controls.Add($btnScan)

$script:DiscoveredPrinters = @()

$btnScan.Add_Click({
    $btnScan.Enabled = $false
    $btnScan.Text = "Scanning..."
    $cmbDiscovered.Items.Clear()
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $json = & python $DiscoverScript --timeout 5 2>$null | Select-Object -Last 1
        $printers = $json | ConvertFrom-Json
    } catch {
        $printers = @()
    }

    $script:DiscoveredPrinters = @($printers)
    if ($script:DiscoveredPrinters.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No printers found in 5 seconds. Same WiFi/router required (won't cross VLANs or guest networks). You can still type IP/serial in manually below.",
            "No printers found"
        ) | Out-Null
    } else {
        foreach ($p in $script:DiscoveredPrinters) {
            $label = "$($p.name) ($($p.model)) - $($p.ip)"
            $cmbDiscovered.Items.Add($label) | Out-Null
        }
        $cmbDiscovered.SelectedIndex = 0
    }

    $btnScan.Text = "Scan (5s)"
    $btnScan.Enabled = $true
})

$cmbDiscovered.Add_SelectedIndexChanged({
    $i = $cmbDiscovered.SelectedIndex
    if ($i -ge 0 -and $i -lt $script:DiscoveredPrinters.Count) {
        $p = $script:DiscoveredPrinters[$i]
        $txtIp.Text = $p.ip
        $txtSerial.Text = $p.serial
    }
})

$y += 35
$lblIp = New-Object System.Windows.Forms.Label
$lblIp.Text = "Printer IP:"
$lblIp.Location = New-Object System.Drawing.Point(15, $y)
$lblIp.AutoSize = $true
$form.Controls.Add($lblIp)

$txtIp = New-Object System.Windows.Forms.TextBox
$txtIp.Location = New-Object System.Drawing.Point(150, ($y - 3))
$txtIp.Size = New-Object System.Drawing.Size(300, 24)
if ($saved -and $saved.ip) { $txtIp.Text = $saved.ip }
$form.Controls.Add($txtIp)

$y += 35
$lblSerial = New-Object System.Windows.Forms.Label
$lblSerial.Text = "Serial number:"
$lblSerial.Location = New-Object System.Drawing.Point(15, $y)
$lblSerial.AutoSize = $true
$form.Controls.Add($lblSerial)

$txtSerial = New-Object System.Windows.Forms.TextBox
$txtSerial.Location = New-Object System.Drawing.Point(150, ($y - 3))
$txtSerial.Size = New-Object System.Drawing.Size(300, 24)
if ($saved -and $saved.serial) { $txtSerial.Text = $saved.serial }
$form.Controls.Add($txtSerial)

$y += 35
$lblAccessCode = New-Object System.Windows.Forms.Label
$lblAccessCode.Text = "Access code:"
$lblAccessCode.Location = New-Object System.Drawing.Point(15, $y)
$lblAccessCode.AutoSize = $true
$form.Controls.Add($lblAccessCode)

$txtAccessCode = New-Object System.Windows.Forms.TextBox
$txtAccessCode.Location = New-Object System.Drawing.Point(150, ($y - 3))
$txtAccessCode.Size = New-Object System.Drawing.Size(220, 24)
$txtAccessCode.UseSystemPasswordChar = $true
if ($saved -and $saved.accessCode) { $txtAccessCode.Text = $saved.accessCode }
$form.Controls.Add($txtAccessCode)

$chkShowCode = New-Object System.Windows.Forms.CheckBox
$chkShowCode.Text = "Show"
$chkShowCode.Location = New-Object System.Drawing.Point(380, $y)
$chkShowCode.AutoSize = $true
$chkShowCode.Add_CheckedChanged({ $txtAccessCode.UseSystemPasswordChar = -not $chkShowCode.Checked })
$form.Controls.Add($chkShowCode)

$y += 45
$lblInfo = New-Object System.Windows.Forms.Label
$lblInfo.Text = "Starts the watcher in its own console window (live log there). Close that window, or Ctrl+C in it, to stop."
$lblInfo.Location = New-Object System.Drawing.Point(15, $y)
$lblInfo.Size = New-Object System.Drawing.Size(440, 40)
$lblInfo.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblInfo)

$y += 50
$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Start Watching"
$btnStart.Location = New-Object System.Drawing.Point(15, $y)
$btnStart.Size = New-Object System.Drawing.Size(440, 32)
$btnStart.Enabled = ($HasPython -and (Test-Path $WatcherScript))
$form.Controls.Add($btnStart)

$btnStart.Add_Click({
    $ip = $txtIp.Text.Trim()
    $serial = $txtSerial.Text.Trim()
    $accessCode = $txtAccessCode.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($ip) -or [string]::IsNullOrWhiteSpace($serial) -or [string]::IsNullOrWhiteSpace($accessCode)) {
        [System.Windows.Forms.MessageBox]::Show("Fill in printer IP, serial number, and access code first.", "Missing info") | Out-Null
        return
    }

    Save-Config $ip $serial $accessCode

    $arguments = "watch.py --host $ip --serial $serial --access-code $accessCode -v"
    Start-Process -FilePath "python" -ArgumentList $arguments -WorkingDirectory $WatcherDir
})

[void]$form.ShowDialog()
