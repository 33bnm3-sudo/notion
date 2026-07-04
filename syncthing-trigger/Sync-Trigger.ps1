<#
.SYNOPSIS
    Resume a paused Syncthing device/folders and wait until every folder
    reaches 100% completion. Works two ways:

    1. GUI (default, no -Silent): enter API URL/key, see each folder's
       completion % update live, click a folder's own Sync button.
    2. Silent/CLI, for chaining after another script/task finishes:
         powershell -File Sync-Trigger.ps1 -ApiKey xxx -Silent
       Runs headless, no window, prints progress to the console, and sets
       the exit code (0 = fully synced, 1 = timed out, 2 = error) so a
       calling script can check it.

    Verified against a real local Syncthing pair (two instances on the same
    host, paired as devices, one folder shared) - not against an actual
    phone, so double check once against your real setup before relying on it.
#>

param(
    [string]$ApiUrl,
    [string]$ApiKey,
    [switch]$Silent,
    [int]$TimeoutMinutes = 30
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ConfigDir = Join-Path $env:APPDATA "SyncthingTrigger"
$ConfigPath = Join-Path $ConfigDir "config.json"

function Load-Config {
    if (Test-Path $ConfigPath) {
        try { return Get-Content $ConfigPath -Raw | ConvertFrom-Json } catch { return $null }
    }
    return $null
}

function Save-Config($apiUrl, $apiKey) {
    if (-not (Test-Path $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    }
    [PSCustomObject]@{ apiUrl = $apiUrl; apiKey = $apiKey } | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
}

# Syncthing keeps its API key in its own config.xml, at a well-known default
# location - read it from there instead of making the user copy it out of the
# Syncthing web GUI by hand. Only ever reads the LOCAL machine's own
# Syncthing instance (one API key per instance, covers every folder/device
# it manages) - there's no way to reach into a phone's separate config.xml
# from here, nor any need to: this tool only ever talks to the local instance.
function Find-LocalApiKey {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Syncthing\config.xml"),
        (Join-Path $env:APPDATA "Syncthing\config.xml")
    )
    foreach ($path in $candidates) {
        if (Test-Path $path) {
            try {
                [xml]$xml = Get-Content $path -Raw
                $key = $xml.configuration.gui.apikey
                if ($key) { return $key }
            } catch {
                continue
            }
        }
    }
    return $null
}

# Checks a few well-known spots instead of just PATH, since Syncthing is
# often installed without ever being added to it: the per-user install dir
# the official Windows installer/MSI defaults to, the Program Files
# locations some package managers use, and finally the presence of its
# config.xml (a machine that's run Syncthing before will have one even if
# the exe itself got moved or uninstalled oddly).
function Test-SyncthingInstalled {
    if (Get-Command syncthing -ErrorAction SilentlyContinue) { return $true }

    # Join-Path throws outright on a $null base, so only build a candidate
    # from an env var that's actually set (ProgramFiles(x86) in particular
    # doesn't exist on 32-bit Windows).
    $candidates = @()
    if ($env:LOCALAPPDATA) {
        $candidates += Join-Path $env:LOCALAPPDATA "Programs\syncthing\syncthing.exe"
        $candidates += Join-Path $env:LOCALAPPDATA "Syncthing\config.xml"
    }
    if ($env:ProgramFiles) {
        $candidates += Join-Path $env:ProgramFiles "Syncthing\syncthing.exe"
    }
    $programFilesX86 = ${env:ProgramFiles(x86)}
    if ($programFilesX86) {
        $candidates += Join-Path $programFilesX86 "Syncthing\syncthing.exe"
    }

    foreach ($path in $candidates) {
        if (Test-Path $path) { return $true }
    }
    return $false
}

# ---- Syncthing REST API helpers ----
# Verified against a real Syncthing instance: GET /rest/system/status (myID),
# GET /rest/config (folders[].id/label/devices[].deviceID), POST
# /rest/system/resume (all devices), GET /rest/db/completion?folder=&device=
# (completion/needBytes). A bad API key returns HTTP 403, not 401.

function Invoke-SyncthingApi {
    param([string]$Method = "GET", [string]$Path, [string]$ApiUrl, [string]$ApiKey)
    $headers = @{ "X-API-Key" = $ApiKey }
    try {
        return Invoke-RestMethod -Uri "$ApiUrl$Path" -Method $Method -Headers $headers
    } catch {
        $status = $_.Exception.Response.StatusCode.value__
        if ($status -eq 403) {
            throw "Invalid or unauthorized API key (403)."
        }
        throw "Could not reach Syncthing ($Path): $($_.Exception.Message)"
    }
}

function Get-MyDeviceId {
    param([string]$ApiUrl, [string]$ApiKey)
    (Invoke-SyncthingApi -Path "/rest/system/status" -ApiUrl $ApiUrl -ApiKey $ApiKey).myID
}

function Get-SyncthingFolders {
    param([string]$ApiUrl, [string]$ApiKey)
    (Invoke-SyncthingApi -Path "/rest/config" -ApiUrl $ApiUrl -ApiKey $ApiKey).folders
}

function Resume-AllDevices {
    param([string]$ApiUrl, [string]$ApiKey)
    Invoke-SyncthingApi -Method POST -Path "/rest/system/resume" -ApiUrl $ApiUrl -ApiKey $ApiKey | Out-Null
}

function Resume-Device {
    param([string]$ApiUrl, [string]$ApiKey, [string]$DeviceId)
    Invoke-SyncthingApi -Method POST -Path "/rest/system/resume?device=$DeviceId" -ApiUrl $ApiUrl -ApiKey $ApiKey | Out-Null
}

# Resumes only the devices that share this specific folder, instead of every
# device Syncthing knows about - so triggering one folder's sync doesn't wake
# up an unrelated phone that happens to be paused for a different folder.
function Resume-FolderDevices {
    param([string]$ApiUrl, [string]$ApiKey, $Folder, [string]$MyId)
    $remotes = @($Folder.devices | Where-Object { $_.deviceID -ne $MyId })
    foreach ($d in $remotes) {
        Resume-Device -ApiUrl $ApiUrl -ApiKey $ApiKey -DeviceId $d.deviceID
    }
}

# A folder can be shared with several devices (several phones). It only
# counts as "done" once every one of them has fully caught up, so we take the
# minimum completion across all remote devices sharing that folder.
function Get-FolderStatus {
    param([string]$ApiUrl, [string]$ApiKey, $Folder, [string]$MyId)
    $remotes = @($Folder.devices | Where-Object { $_.deviceID -ne $MyId })
    if ($remotes.Count -eq 0) {
        return [PSCustomObject]@{ Id = $Folder.id; Label = $Folder.label; Completion = 100 }
    }
    $values = foreach ($d in $remotes) {
        try {
            (Invoke-SyncthingApi -Path "/rest/db/completion?folder=$($Folder.id)&device=$($d.deviceID)" -ApiUrl $ApiUrl -ApiKey $ApiKey).completion
        } catch {
            0
        }
    }
    $min = ($values | Measure-Object -Minimum).Minimum
    [PSCustomObject]@{ Id = $Folder.id; Label = $Folder.label; Completion = [math]::Round($min, 1) }
}

# Core routine shared by both Silent and GUI mode: resume everything, then
# poll every folder until each is at 100% or the timeout hits. -OnProgress
# (if given) is called with the current status array on every poll so the
# GUI can update its list live without this function knowing about WinForms.
function Invoke-SyncAndWait {
    param([string]$ApiUrl, [string]$ApiKey, [int]$TimeoutMinutes, [scriptblock]$OnProgress)

    $myId = Get-MyDeviceId -ApiUrl $ApiUrl -ApiKey $ApiKey
    Resume-AllDevices -ApiUrl $ApiUrl -ApiKey $ApiKey
    $folders = Get-SyncthingFolders -ApiUrl $ApiUrl -ApiKey $ApiKey
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)

    while ($true) {
        $statuses = @(foreach ($f in $folders) { Get-FolderStatus -ApiUrl $ApiUrl -ApiKey $ApiKey -Folder $f -MyId $myId })
        if ($OnProgress) { & $OnProgress $statuses }

        if (-not ($statuses | Where-Object { $_.Completion -lt 100 })) {
            return [PSCustomObject]@{ Success = $true; Folders = $statuses }
        }
        if ((Get-Date) -ge $deadline) {
            return [PSCustomObject]@{ Success = $false; Folders = $statuses }
        }
        Start-Sleep -Seconds 3
    }
}

# ---- Silent / CLI mode ----
if ($Silent) {
    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        Write-Host "ERROR: -ApiKey is required in -Silent mode."
        exit 2
    }
    $effectiveUrl = if ($ApiUrl) { $ApiUrl } else { "http://127.0.0.1:8384" }
    try {
        Write-Host "Resuming devices and waiting for sync (timeout ${TimeoutMinutes}m)..."
        $result = Invoke-SyncAndWait -ApiUrl $effectiveUrl -ApiKey $ApiKey -TimeoutMinutes $TimeoutMinutes -OnProgress {
            param($statuses)
            foreach ($s in $statuses) { Write-Host ("  {0}: {1}%" -f $s.Label, $s.Completion) }
        }
        if ($result.Success) {
            Write-Host "All folders synced."
            exit 0
        } else {
            Write-Host "Timed out waiting for sync."
            exit 1
        }
    } catch {
        Write-Host "ERROR: $($_.Exception.Message)"
        exit 2
    }
}

# ---- GUI mode ----
$saved = Load-Config
$effectiveApiUrl = if ($ApiUrl) { $ApiUrl } elseif ($saved.apiUrl) { $saved.apiUrl } else { "http://127.0.0.1:8384" }
$effectiveApiKey = if ($ApiKey) { $ApiKey } elseif ($saved.apiKey) { $saved.apiKey } else { Find-LocalApiKey }

$form = New-Object System.Windows.Forms.Form
$form.Text = "Syncthing Sync Trigger"
$form.Size = New-Object System.Drawing.Size(520, 480)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$y = 15
$syncthingInstalled = Test-SyncthingInstalled

if (-not $syncthingInstalled) {
    $lblInstallWarning = New-Object System.Windows.Forms.Label
    $lblInstallWarning.Text = "Syncthing was not found on this computer. Install it, then click Recheck."
    $lblInstallWarning.Location = New-Object System.Drawing.Point(15, $y)
    $lblInstallWarning.Size = New-Object System.Drawing.Size(495, 40)
    $lblInstallWarning.ForeColor = [System.Drawing.Color]::Firebrick
    $form.Controls.Add($lblInstallWarning)
    $y += 45

    $btnInstall = New-Object System.Windows.Forms.Button
    $btnInstall.Text = "Install Syncthing"
    $btnInstall.Location = New-Object System.Drawing.Point(15, $y)
    $btnInstall.Size = New-Object System.Drawing.Size(150, 28)
    $btnInstall.Add_Click({ Start-Process "https://syncthing.net/downloads/" })
    $form.Controls.Add($btnInstall)

    $btnRecheck = New-Object System.Windows.Forms.Button
    $btnRecheck.Text = "Recheck"
    $btnRecheck.Location = New-Object System.Drawing.Point(175, $y)
    $btnRecheck.Size = New-Object System.Drawing.Size(100, 28)
    $btnRecheck.Add_Click({
        if (Test-SyncthingInstalled) {
            $lblInstallWarning.Text = "Syncthing found."
            $lblInstallWarning.ForeColor = [System.Drawing.Color]::SeaGreen
            $btnInstall.Enabled = $false
            $btnRecheck.Enabled = $false
            $txtUrl.Enabled = $true
            $txtKey.Enabled = $true
            $btnAutoKey.Enabled = $true
            $btnLoad.Enabled = $true
            if (-not $txtKey.Text) {
                $autoKey = Find-LocalApiKey
                if ($autoKey) { $txtKey.Text = $autoKey }
            }
        } else {
            $lblInstallWarning.Text = "Still not found. Make sure the installer finished, then try Recheck again."
        }
    })
    $form.Controls.Add($btnRecheck)

    $y += 40
    $form.Height += 85
}

$lblUrl = New-Object System.Windows.Forms.Label
$lblUrl.Text = "Syncthing URL:"
$lblUrl.Location = New-Object System.Drawing.Point(15, $y)
$lblUrl.AutoSize = $true
$form.Controls.Add($lblUrl)

$txtUrl = New-Object System.Windows.Forms.TextBox
$txtUrl.Location = New-Object System.Drawing.Point(150, ($y - 3))
$txtUrl.Size = New-Object System.Drawing.Size(340, 24)
$txtUrl.Text = $effectiveApiUrl
$form.Controls.Add($txtUrl)

$y += 32
$lblKey = New-Object System.Windows.Forms.Label
$lblKey.Text = "API key:"
$lblKey.Location = New-Object System.Drawing.Point(15, $y)
$lblKey.AutoSize = $true
$form.Controls.Add($lblKey)

$txtKey = New-Object System.Windows.Forms.TextBox
$txtKey.Location = New-Object System.Drawing.Point(150, ($y - 3))
$txtKey.Size = New-Object System.Drawing.Size(260, 24)
$txtKey.Text = $effectiveApiKey
$txtKey.UseSystemPasswordChar = $true
$form.Controls.Add($txtKey)

$btnAutoKey = New-Object System.Windows.Forms.Button
$btnAutoKey.Text = "Auto-detect"
$btnAutoKey.Location = New-Object System.Drawing.Point(415, ($y - 4))
$btnAutoKey.Size = New-Object System.Drawing.Size(80, 26)
$btnAutoKey.Add_Click({
    $key = Find-LocalApiKey
    if ($key) {
        $txtKey.Text = $key
        $lblStatus.Text = "Found API key in the local Syncthing config."
    } else {
        $lblStatus.Text = "Could not find a local Syncthing config.xml - enter the API key manually (Syncthing GUI -> Settings -> General)."
    }
})
$form.Controls.Add($btnAutoKey)

$y += 36
$btnLoad = New-Object System.Windows.Forms.Button
$btnLoad.Text = "Load Folders"
$btnLoad.Location = New-Object System.Drawing.Point(15, $y)
$btnLoad.Size = New-Object System.Drawing.Size(150, 28)
$form.Controls.Add($btnLoad)

# Nothing here is useful until Syncthing itself exists, so everything stays
# disabled until Test-SyncthingInstalled passes (either now, or later via the
# Recheck button above).
$txtUrl.Enabled = $syncthingInstalled
$txtKey.Enabled = $syncthingInstalled
$btnAutoKey.Enabled = $syncthingInstalled
$btnLoad.Enabled = $syncthingInstalled

$y += 40
$folderPanel = New-Object System.Windows.Forms.Panel
$folderPanel.Location = New-Object System.Drawing.Point(15, $y)
$folderPanel.Size = New-Object System.Drawing.Size(475, 300)
$folderPanel.AutoScroll = $true
$folderPanel.BorderStyle = "FixedSingle"
$form.Controls.Add($folderPanel)

$y += 310
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = ""
$lblStatus.Location = New-Object System.Drawing.Point(15, $y)
$lblStatus.Size = New-Object System.Drawing.Size(475, 40)
$lblStatus.ForeColor = [System.Drawing.Color]::Firebrick
$form.Controls.Add($lblStatus)

# folder.id -> @{ Deadline; PercentLabel; SyncButton; Folder }, filled in when
# that folder's Sync button is clicked, drained by $syncTimer as each one
# finishes (or times out) so several folders can be syncing at once.
$script:activeSyncs = @{}
$script:myId = $null
$script:apiUrl = ""
$script:apiKey = ""

function Update-FolderRow($lblPercent, $btnSync, $completion) {
    $lblPercent.Text = "$completion%"
    $isDone = $completion -ge 100
    $btnSync.Enabled = $isDone
    $btnSync.Text = if ($isDone) { "Synced" } else { "Syncing..." }
}

$syncTimer = New-Object System.Windows.Forms.Timer
$syncTimer.Interval = 3000
$syncTimer.Add_Tick({
    foreach ($folderId in @($script:activeSyncs.Keys)) {
        $entry = $script:activeSyncs[$folderId]
        try {
            $status = Get-FolderStatus -ApiUrl $script:apiUrl -ApiKey $script:apiKey -Folder $entry.Folder -MyId $script:myId
        } catch {
            $lblStatus.Text = "FAILED ($($entry.Folder.label)): $($_.Exception.Message)"
            $entry.SyncButton.Enabled = $true
            $entry.SyncButton.Text = "Sync"
            $script:activeSyncs.Remove($folderId)
            continue
        }

        if ($status.Completion -ge 100) {
            Update-FolderRow $entry.PercentLabel $entry.SyncButton 100
            $entry.SyncButton.Text = "Sync"
            $script:activeSyncs.Remove($folderId)
        } elseif ((Get-Date) -ge $entry.Deadline) {
            $entry.PercentLabel.Text = "$($status.Completion)% (timeout)"
            $entry.SyncButton.Enabled = $true
            $entry.SyncButton.Text = "Sync"
            $script:activeSyncs.Remove($folderId)
        } else {
            Update-FolderRow $entry.PercentLabel $entry.SyncButton $status.Completion
        }
    }
    if ($script:activeSyncs.Count -eq 0) { $syncTimer.Stop() }
})

function Start-FolderSync($folder, $lblPercent, $btnSync) {
    try {
        Resume-FolderDevices -ApiUrl $script:apiUrl -ApiKey $script:apiKey -Folder $folder -MyId $script:myId
        $btnSync.Enabled = $false
        $btnSync.Text = "Syncing..."
        $script:activeSyncs[$folder.id] = @{
            Deadline    = (Get-Date).AddMinutes($TimeoutMinutes)
            PercentLabel = $lblPercent
            SyncButton  = $btnSync
            Folder      = $folder
        }
        if (-not $syncTimer.Enabled) { $syncTimer.Start() }
    } catch {
        $lblStatus.Text = "FAILED ($($folder.label)): $($_.Exception.Message)"
    }
}

function Build-FolderRows($folders) {
    $folderPanel.Controls.Clear()
    $rowY = 5
    foreach ($folder in $folders) {
        $lblName = New-Object System.Windows.Forms.Label
        $lblName.Text = $folder.label
        $lblName.Location = New-Object System.Drawing.Point(5, ($rowY + 5))
        $lblName.Size = New-Object System.Drawing.Size(230, 20)
        $lblName.AutoEllipsis = $true
        $folderPanel.Controls.Add($lblName)

        $lblPercent = New-Object System.Windows.Forms.Label
        $lblPercent.Text = "..."
        $lblPercent.Location = New-Object System.Drawing.Point(240, ($rowY + 5))
        $lblPercent.Size = New-Object System.Drawing.Size(70, 20)
        $folderPanel.Controls.Add($lblPercent)

        $btnFolderSync = New-Object System.Windows.Forms.Button
        $btnFolderSync.Text = "Sync"
        $btnFolderSync.Location = New-Object System.Drawing.Point(315, $rowY)
        $btnFolderSync.Size = New-Object System.Drawing.Size(90, 26)
        $folderPanel.Controls.Add($btnFolderSync)

        # Bind the specific folder/label/button for this row via .Tag instead
        # of capturing $folder from the loop directly - a script block would
        # otherwise see whatever $folder happens to be by the time it fires,
        # which by then is always the last folder in the list.
        $btnFolderSync.Tag = @{ Folder = $folder; PercentLabel = $lblPercent; Button = $btnFolderSync }
        $btnFolderSync.Add_Click({
            $data = $this.Tag
            Start-FolderSync $data.Folder $data.PercentLabel $data.Button
        })

        try {
            $status = Get-FolderStatus -ApiUrl $script:apiUrl -ApiKey $script:apiKey -Folder $folder -MyId $script:myId
            $lblPercent.Text = "$($status.Completion)%"
        } catch {
            $lblPercent.Text = "?"
        }

        $rowY += 34
    }
}

$btnLoad.Add_Click({
    $lblStatus.Text = ""
    try {
        $script:apiUrl = $txtUrl.Text.Trim()
        $script:apiKey = $txtKey.Text.Trim()
        Save-Config $script:apiUrl $script:apiKey
        $script:myId = Get-MyDeviceId -ApiUrl $script:apiUrl -ApiKey $script:apiKey
        $folders = Get-SyncthingFolders -ApiUrl $script:apiUrl -ApiKey $script:apiKey
        Build-FolderRows $folders
    } catch {
        $lblStatus.Text = "FAILED: $($_.Exception.Message)"
    }
})

[void]$form.ShowDialog()
