<#
.SYNOPSIS
    Resume a paused Syncthing device/folders, wait until every folder reaches
    100% completion, and show a notification. Works two ways:

    1. GUI (default, no -Silent): enter API URL/key, see each folder's status,
       click "Sync Now".
    2. Silent/CLI, for chaining after another script/task finishes:
         powershell -File Sync-Trigger.ps1 -ApiKey xxx -Silent
       Runs headless, no window, prints progress to the console, shows a
       balloon notification at the end, and sets the exit code (0 = fully
       synced, 1 = timed out, 2 = error) so a calling script can check it.

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
            throw "API 키가 잘못됐거나 권한이 없습니다 (403)."
        }
        throw "Syncthing에 연결하지 못했습니다 ($Path): $($_.Exception.Message)"
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

function Show-Notification {
    param([string]$Title, [string]$Text, [System.Windows.Forms.NotifyIcon]$ExistingIcon)
    $notify = $ExistingIcon
    $ownIcon = $false
    if (-not $notify) {
        $notify = New-Object System.Windows.Forms.NotifyIcon
        $notify.Icon = [System.Drawing.SystemIcons]::Information
        $ownIcon = $true
    }
    $notify.Visible = $true
    $notify.BalloonTipTitle = $Title
    $notify.BalloonTipText = $Text
    $notify.ShowBalloonTip(8000)
    if ($ownIcon) {
        # No message loop is running in -Silent mode; pump a few events so
        # Windows actually draws the balloon before the script exits.
        for ($i = 0; $i -lt 20; $i++) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 250
        }
        $notify.Dispose()
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
            Show-Notification -Title "Syncthing" -Text "모든 폴더 동기화 완료"
            exit 0
        } else {
            Write-Host "Timed out waiting for sync."
            Show-Notification -Title "Syncthing" -Text "동기화가 시간 내에 끝나지 않았습니다"
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
$effectiveApiKey = if ($ApiKey) { $ApiKey } else { $saved.apiKey }

$form = New-Object System.Windows.Forms.Form
$form.Text = "Syncthing Sync Trigger"
$form.Size = New-Object System.Drawing.Size(520, 480)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
$form.Add_FormClosing({ $notifyIcon.Dispose() })

$y = 15

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
$txtKey.Size = New-Object System.Drawing.Size(340, 24)
$txtKey.Text = $effectiveApiKey
$txtKey.UseSystemPasswordChar = $true
$form.Controls.Add($txtKey)

$y += 36
$btnLoad = New-Object System.Windows.Forms.Button
$btnLoad.Text = "Load Folders"
$btnLoad.Location = New-Object System.Drawing.Point(15, $y)
$btnLoad.Size = New-Object System.Drawing.Size(150, 28)
$form.Controls.Add($btnLoad)

$btnSync = New-Object System.Windows.Forms.Button
$btnSync.Text = "Sync Now"
$btnSync.Location = New-Object System.Drawing.Point(175, $y)
$btnSync.Size = New-Object System.Drawing.Size(150, 28)
$btnSync.Enabled = $false
$form.Controls.Add($btnSync)

$lblOverall = New-Object System.Windows.Forms.Label
$lblOverall.Text = ""
$lblOverall.Location = New-Object System.Drawing.Point(335, ($y + 6))
$lblOverall.AutoSize = $true
$form.Controls.Add($lblOverall)

$y += 40
$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point(15, $y)
$listView.Size = New-Object System.Drawing.Size(475, 260)
$listView.View = "Details"
$listView.FullRowSelect = $true
$listView.Columns.Add("Folder", 300) | Out-Null
$listView.Columns.Add("Completion", 100) | Out-Null
$listView.Columns.Add("Status", 65) | Out-Null
$form.Controls.Add($listView)

$y += 270
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = ""
$lblStatus.Location = New-Object System.Drawing.Point(15, $y)
$lblStatus.Size = New-Object System.Drawing.Size(475, 40)
$lblStatus.ForeColor = [System.Drawing.Color]::Firebrick
$form.Controls.Add($lblStatus)

$script:myId = $null
$script:folders = @()

function Refresh-List($statuses) {
    $listView.Items.Clear()
    $allDone = $true
    foreach ($s in $statuses) {
        $item = New-Object System.Windows.Forms.ListViewItem($s.Label)
        [void]$item.SubItems.Add("$($s.Completion)%")
        $isDone = $s.Completion -ge 100
        [void]$item.SubItems.Add($(if ($isDone) { "Synced" } else { "Syncing" }))
        if (-not $isDone) { $allDone = $false }
        $listView.Items.Add($item) | Out-Null
    }
    $lblOverall.Text = if ($allDone) { "All synced" } else { "Syncing..." }
    return $allDone
}

$btnLoad.Add_Click({
    $lblStatus.Text = ""
    try {
        $apiUrl = $txtUrl.Text.Trim()
        $apiKey = $txtKey.Text.Trim()
        Save-Config $apiUrl $apiKey
        $script:myId = Get-MyDeviceId -ApiUrl $apiUrl -ApiKey $apiKey
        $script:folders = Get-SyncthingFolders -ApiUrl $apiUrl -ApiKey $apiKey
        $statuses = @(foreach ($f in $script:folders) { Get-FolderStatus -ApiUrl $apiUrl -ApiKey $apiKey -Folder $f -MyId $script:myId })
        Refresh-List $statuses | Out-Null
        $btnSync.Enabled = $true
    } catch {
        $lblStatus.Text = "FAILED: $($_.Exception.Message)"
    }
})

$syncTimer = New-Object System.Windows.Forms.Timer
$syncTimer.Interval = 3000
$script:syncDeadline = $null

$syncTimer.Add_Tick({
    try {
        $apiUrl = $txtUrl.Text.Trim()
        $apiKey = $txtKey.Text.Trim()
        $statuses = @(foreach ($f in $script:folders) { Get-FolderStatus -ApiUrl $apiUrl -ApiKey $apiKey -Folder $f -MyId $script:myId })
        $allDone = Refresh-List $statuses

        if ($allDone) {
            $syncTimer.Stop()
            $btnSync.Enabled = $true
            $btnLoad.Enabled = $true
            $notifyIcon.Visible = $true
            $notifyIcon.BalloonTipTitle = "Syncthing"
            $notifyIcon.BalloonTipText = "모든 폴더 동기화 완료"
            $notifyIcon.ShowBalloonTip(8000)
        } elseif ((Get-Date) -ge $script:syncDeadline) {
            $syncTimer.Stop()
            $btnSync.Enabled = $true
            $btnLoad.Enabled = $true
            $lblStatus.Text = "Timed out waiting for sync to finish."
            $notifyIcon.Visible = $true
            $notifyIcon.BalloonTipTitle = "Syncthing"
            $notifyIcon.BalloonTipText = "동기화가 시간 내에 끝나지 않았습니다"
            $notifyIcon.ShowBalloonTip(8000)
        }
    } catch {
        $syncTimer.Stop()
        $btnSync.Enabled = $true
        $btnLoad.Enabled = $true
        $lblStatus.Text = "FAILED: $($_.Exception.Message)"
    }
})

$btnSync.Add_Click({
    $lblStatus.Text = ""
    try {
        $apiUrl = $txtUrl.Text.Trim()
        $apiKey = $txtKey.Text.Trim()
        Resume-AllDevices -ApiUrl $apiUrl -ApiKey $apiKey
        $script:syncDeadline = (Get-Date).AddMinutes($TimeoutMinutes)
        $btnSync.Enabled = $false
        $btnLoad.Enabled = $false
        $syncTimer.Start()
    } catch {
        $lblStatus.Text = "FAILED: $($_.Exception.Message)"
    }
})

[void]$form.ShowDialog()
