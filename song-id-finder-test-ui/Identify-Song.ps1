<#
.SYNOPSIS
    Minimal WinForms GUI to test the song-id-finder logic: pick a video,
    extract its audio, run it through whichever recognition services have
    an API key filled in (AudD / ACRCloud / AcoustID), and show a YouTube
    link for each match found. Mirrors the HTTP calls built by the Rust
    module in song-id-finder/src/lib.rs in this same repo.

    This tool does NOT download any video or audio from YouTube - it only
    builds a link. What you do with that link (use the platform's native
    "use this sound" feature, buy the track, etc.) is up to you.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http

$ConfigDir = Join-Path $env:APPDATA "SongIdFinderTest"
$ConfigPath = Join-Path $ConfigDir "config.json"
$ExtractSeconds = 20

function Load-Config {
    if (Test-Path $ConfigPath) {
        try { return Get-Content $ConfigPath -Raw | ConvertFrom-Json } catch { return $null }
    }
    return $null
}

function Save-Config($auddToken, $acrHost, $acrKey, $acrSecret, $acoustidKey, $ytKey) {
    if (-not (Test-Path $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    }
    [PSCustomObject]@{
        auddToken   = $auddToken
        acrHost     = $acrHost
        acrKey      = $acrKey
        acrSecret   = $acrSecret
        acoustidKey = $acoustidKey
        ytKey       = $ytKey
    } | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
}

$saved = Load-Config
$HasFfmpeg = [bool](Get-Command ffmpeg -ErrorAction SilentlyContinue)
$HasFpcalc = [bool](Get-Command fpcalc -ErrorAction SilentlyContinue)

# ---- HTTP helpers (mirror song-id-finder/src/lib.rs) ----

# Indexing [0] straight into a $null (e.g. a JSON key the API omitted on an
# error/no-match response) throws in PowerShell, unlike plain property access
# which just returns $null. Every array-first-element read below goes through
# this so an unexpected/error-shaped API response can't crash the run.
function Get-SafeFirst($obj) {
    if ($obj -and $obj.Count -gt 0) { return $obj[0] }
    return $null
}

function Invoke-MultipartUpload {
    param([string]$Url, [hashtable]$Fields, [string]$FileFieldName, [string]$FilePath)
    $client = New-Object System.Net.Http.HttpClient
    try {
        $content = New-Object System.Net.Http.MultipartFormDataContent
        foreach ($key in $Fields.Keys) {
            $content.Add((New-Object System.Net.Http.StringContent([string]$Fields[$key])), $key)
        }
        $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
        $byteContent = New-Object System.Net.Http.ByteArrayContent(@(,$fileBytes))
        $content.Add($byteContent, $FileFieldName, [System.IO.Path]::GetFileName($FilePath))

        $response = $client.PostAsync($Url, $content).GetAwaiter().GetResult()
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        return $body | ConvertFrom-Json
    } finally {
        $client.Dispose()
    }
}

# https://docs.audd.io/ - free tier available, good coverage of trending commercial tracks
function Get-AuddMatch {
    param([string]$AudioPath, [string]$Token)
    if ([string]::IsNullOrWhiteSpace($Token)) { return $null }
    try {
        $json = Invoke-MultipartUpload -Url "https://api.audd.io/" `
            -Fields @{ api_token = $Token; return = "spotify,apple_music" } `
            -FileFieldName "file" -FilePath $AudioPath
        if ($null -eq $json.result) {
            return [PSCustomObject]@{ Provider = "AudD"; Title = $null; Artist = $null; Error = $null }
        }
        return [PSCustomObject]@{ Provider = "AudD"; Title = $json.result.title; Artist = $json.result.artist; Error = $null }
    } catch {
        return [PSCustomObject]@{ Provider = "AudD"; Title = $null; Artist = $null; Error = $_.Exception.Message }
    }
}

# https://docs.acrcloud.com/reference/identification-api - needs an HMAC-SHA1 signature per request
function Get-AcrCloudMatch {
    param([string]$AudioPath, [string]$HostName, [string]$AccessKey, [string]$AccessSecret)
    if ([string]::IsNullOrWhiteSpace($HostName) -or [string]::IsNullOrWhiteSpace($AccessKey) -or [string]::IsNullOrWhiteSpace($AccessSecret)) {
        return $null
    }
    try {
        $timestamp = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        $stringToSign = "POST`n/v1/identify`n$AccessKey`naudio`n1`n$timestamp"
        $hmac = New-Object System.Security.Cryptography.HMACSHA1
        $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($AccessSecret)
        $signature = [Convert]::ToBase64String($hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($stringToSign)))
        $sampleBytes = (Get-Item $AudioPath).Length

        $fields = @{
            access_key        = $AccessKey
            data_type         = "audio"
            signature_version = "1"
            signature         = $signature
            sample_bytes      = "$sampleBytes"
            timestamp         = "$timestamp"
        }
        $json = Invoke-MultipartUpload -Url "https://$HostName/v1/identify" -Fields $fields -FileFieldName "sample" -FilePath $AudioPath
        $music = Get-SafeFirst $json.metadata.music
        if ($null -eq $music) {
            return [PSCustomObject]@{ Provider = "ACRCloud"; Title = $null; Artist = $null; Error = $null }
        }
        return [PSCustomObject]@{ Provider = "ACRCloud"; Title = $music.title; Artist = $music.artists[0].name; Error = $null }
    } catch {
        return [PSCustomObject]@{ Provider = "ACRCloud"; Title = $null; Artist = $null; Error = $_.Exception.Message }
    }
}

# https://acoustid.org/webservice - fully free, needs Chromaprint's fpcalc on PATH.
# Database is release-catalog based, so remixed/sped-up trend sounds common on
# Shorts/Reels may not be found here - that's what AudD/ACRCloud are for.
function Get-AcoustIdMatch {
    param([string]$AudioPath, [string]$ApiKey)
    if ([string]::IsNullOrWhiteSpace($ApiKey)) { return $null }
    if (-not $HasFpcalc) {
        return [PSCustomObject]@{ Provider = "AcoustID"; Title = $null; Artist = $null; Error = "fpcalc (Chromaprint) not found on PATH" }
    }
    try {
        $fp = & fpcalc -json $AudioPath | ConvertFrom-Json
        $url = "https://api.acoustid.org/v2/lookup?client=$([uri]::EscapeDataString($ApiKey))&meta=recordings&duration=$([int]$fp.duration)&fingerprint=$([uri]::EscapeDataString($fp.fingerprint))"
        $json = Invoke-RestMethod -Uri $url -Method Get
        $firstResult = Get-SafeFirst $json.results
        $recording = if ($firstResult) { Get-SafeFirst $firstResult.recordings } else { $null }
        if ($null -eq $recording) {
            return [PSCustomObject]@{ Provider = "AcoustID"; Title = $null; Artist = $null; Error = $null }
        }
        return [PSCustomObject]@{ Provider = "AcoustID"; Title = $recording.title; Artist = $recording.artists[0].name; Error = $null }
    } catch {
        return [PSCustomObject]@{ Provider = "AcoustID"; Title = $null; Artist = $null; Error = $_.Exception.Message }
    }
}

function Get-YoutubeLink {
    param([string]$Title, [string]$Artist, [string]$YtApiKey)
    $query = "$Artist $Title"
    if (-not [string]::IsNullOrWhiteSpace($YtApiKey)) {
        try {
            $url = "https://www.googleapis.com/youtube/v3/search?part=id&type=video&maxResults=1&q=$([uri]::EscapeDataString($query))&key=$([uri]::EscapeDataString($YtApiKey))"
            $json = Invoke-RestMethod -Uri $url -Method Get
            $firstItem = Get-SafeFirst $json.items
            $videoId = if ($firstItem) { $firstItem.id.videoId } else { $null }
            if ($videoId) { return "https://www.youtube.com/watch?v=$videoId" }
        } catch {
            # fall through to plain search link
        }
    }
    return "https://www.youtube.com/results?search_query=$([uri]::EscapeDataString($query))"
}

# ---- Form ----
$form = New-Object System.Windows.Forms.Form
$form.Text = "Song ID Finder - Test"
$form.Size = New-Object System.Drawing.Size(600, 620)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$y = 15

if (-not $HasFfmpeg) {
    $lblWarning = New-Object System.Windows.Forms.Label
    $lblWarning.Text = "ffmpeg not found on PATH. Install ffmpeg first (https://ffmpeg.org) - this tool shells out to it to extract audio."
    $lblWarning.Location = New-Object System.Drawing.Point(15, $y)
    $lblWarning.Size = New-Object System.Drawing.Size(555, 40)
    $lblWarning.ForeColor = [System.Drawing.Color]::Firebrick
    $form.Controls.Add($lblWarning)
    $y += 45
}

$lblInput = New-Object System.Windows.Forms.Label
$lblInput.Text = "Input video:"
$lblInput.Location = New-Object System.Drawing.Point(15, $y)
$lblInput.AutoSize = $true
$form.Controls.Add($lblInput)

$y += 20
$txtInput = New-Object System.Windows.Forms.TextBox
$txtInput.Location = New-Object System.Drawing.Point(15, $y)
$txtInput.Size = New-Object System.Drawing.Size(380, 24)
$txtInput.ReadOnly = $true
$txtInput.AllowDrop = $true
$form.Controls.Add($txtInput)

function Set-InputVideo($path) {
    $ext = [IO.Path]::GetExtension($path).ToLower()
    if ($ext -notin @(".mp4", ".mov", ".mkv", ".avi", ".webm", ".m4v")) {
        [System.Windows.Forms.MessageBox]::Show("Unsupported file type: $path", "Unsupported video") | Out-Null
        return
    }
    $txtInput.Text = $path
}

$btnBrowseInput = New-Object System.Windows.Forms.Button
$btnBrowseInput.Text = "Browse..."
$btnBrowseInput.Location = New-Object System.Drawing.Point(400, ($y - 1))
$btnBrowseInput.Size = New-Object System.Drawing.Size(80, 24)
$btnBrowseInput.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Choose a video"
    $dialog.Filter = "Videos (*.mp4;*.mov;*.mkv;*.avi;*.webm;*.m4v)|*.mp4;*.mov;*.mkv;*.avi;*.webm;*.m4v"
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Set-InputVideo $dialog.FileName
    }
})
$form.Controls.Add($btnBrowseInput)

$btnClearInput = New-Object System.Windows.Forms.Button
$btnClearInput.Text = "Clear"
$btnClearInput.Location = New-Object System.Drawing.Point(485, ($y - 1))
$btnClearInput.Size = New-Object System.Drawing.Size(60, 24)
$btnClearInput.Add_Click({ $txtInput.Text = "" })
$form.Controls.Add($btnClearInput)

$txtInput.Add_DragEnter({
    param($sender, $e)
    if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
        $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy
    }
})
$txtInput.Add_DragDrop({
    param($sender, $e)
    $files = $e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
    if ($files -and $files.Count -gt 0) { Set-InputVideo $files[0] }
})

function Add-KeyField($label, $y, $default) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $label
    $lbl.Location = New-Object System.Drawing.Point(15, $y)
    $lbl.AutoSize = $true
    $form.Controls.Add($lbl)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(230, ($y - 3))
    $txt.Size = New-Object System.Drawing.Size(340, 24)
    $txt.Text = $default
    $form.Controls.Add($txt)
    return $txt
}

$y += 40
$lblSection1 = New-Object System.Windows.Forms.Label
$lblSection1.Text = "API keys (only services with a key filled in are run):"
$lblSection1.Location = New-Object System.Drawing.Point(15, $y)
$lblSection1.AutoSize = $true
$lblSection1.Font = New-Object System.Drawing.Font($lblSection1.Font, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblSection1)

$y += 28
$txtAuddToken = Add-KeyField "AudD API token:" $y ($saved.auddToken)
$y += 32
$txtAcrHost = Add-KeyField "ACRCloud host:" $y ($saved.acrHost)
$y += 32
$txtAcrKey = Add-KeyField "ACRCloud access key:" $y ($saved.acrKey)
$y += 32
$txtAcrSecret = Add-KeyField "ACRCloud access secret:" $y ($saved.acrSecret)
$y += 32
$txtAcoustidKey = Add-KeyField "AcoustID API key:" $y ($saved.acoustidKey)
$y += 32
$txtYtKey = Add-KeyField "YouTube Data API key (optional):" $y ($saved.ytKey)

if (-not $HasFpcalc) {
    $y += 26
    $lblFpcalc = New-Object System.Windows.Forms.Label
    $lblFpcalc.Text = "fpcalc (Chromaprint) not found on PATH - AcoustID will be skipped even if a key is set."
    $lblFpcalc.Location = New-Object System.Drawing.Point(15, $y)
    $lblFpcalc.Size = New-Object System.Drawing.Size(555, 20)
    $lblFpcalc.ForeColor = [System.Drawing.Color]::DarkOrange
    $form.Controls.Add($lblFpcalc)
}

$y += 40
$btnIdentify = New-Object System.Windows.Forms.Button
$btnIdentify.Text = "Identify Song"
$btnIdentify.Location = New-Object System.Drawing.Point(15, $y)
$btnIdentify.Size = New-Object System.Drawing.Size(555, 32)
$btnIdentify.Enabled = $HasFfmpeg
$form.Controls.Add($btnIdentify)

$y += 42
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(15, $y)
$txtLog.Size = New-Object System.Drawing.Size(555, 110)
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$form.Controls.Add($txtLog)

function Write-Log($text) {
    $txtLog.AppendText("$text`r`n")
    [System.Windows.Forms.Application]::DoEvents()
}

$y += 120
$lblLinks = New-Object System.Windows.Forms.Label
$lblLinks.Text = "YouTube links:"
$lblLinks.Location = New-Object System.Drawing.Point(15, $y)
$lblLinks.AutoSize = $true
$form.Controls.Add($lblLinks)

$y += 20
$linkPanel = New-Object System.Windows.Forms.Panel
$linkPanel.Location = New-Object System.Drawing.Point(15, $y)
$linkPanel.Size = New-Object System.Drawing.Size(555, 90)
$linkPanel.AutoScroll = $true
$form.Controls.Add($linkPanel)

function Add-ResultLink($text, $url) {
    $link = New-Object System.Windows.Forms.LinkLabel
    $link.Text = $text
    $link.Location = New-Object System.Drawing.Point(5, ($linkPanel.Controls.Count * 22))
    $link.AutoSize = $true
    $link.Tag = $url
    $link.Add_LinkClicked({ Start-Process $this.Tag })
    $linkPanel.Controls.Add($link)
}

$btnIdentify.Add_Click({
    $inputPath = $txtInput.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($inputPath)) {
        [System.Windows.Forms.MessageBox]::Show("Choose an input video first.", "Missing input") | Out-Null
        return
    }

    Save-Config $txtAuddToken.Text $txtAcrHost.Text $txtAcrKey.Text $txtAcrSecret.Text $txtAcoustidKey.Text $txtYtKey.Text

    $btnIdentify.Enabled = $false
    $txtLog.Clear()
    $linkPanel.Controls.Clear()

    try {
        $audioPath = Join-Path $env:TEMP "song-id-finder-sample.mp3"
        Write-Log "Extracting first $ExtractSeconds seconds of audio..."
        & ffmpeg -y -i $inputPath -t $ExtractSeconds -vn -acodec libmp3lame -ar 44100 -ac 2 -- $audioPath 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $audioPath)) {
            throw "ffmpeg failed to extract audio"
        }

        $anyKeySet = -not [string]::IsNullOrWhiteSpace($txtAuddToken.Text) -or
                     (-not [string]::IsNullOrWhiteSpace($txtAcrHost.Text) -and -not [string]::IsNullOrWhiteSpace($txtAcrKey.Text)) -or
                     -not [string]::IsNullOrWhiteSpace($txtAcoustidKey.Text)
        if (-not $anyKeySet) {
            Write-Log "No API keys set - nothing to run. Fill in at least one service's key above."
            return
        }

        $results = @(
            (Get-AuddMatch -AudioPath $audioPath -Token $txtAuddToken.Text),
            (Get-AcrCloudMatch -AudioPath $audioPath -HostName $txtAcrHost.Text -AccessKey $txtAcrKey.Text -AccessSecret $txtAcrSecret.Text),
            (Get-AcoustIdMatch -AudioPath $audioPath -ApiKey $txtAcoustidKey.Text)
        ) | Where-Object { $_ -ne $null }

        foreach ($r in $results) {
            if ($r.Error) {
                Write-Log "[$($r.Provider)] ERROR: $($r.Error)"
            } elseif (-not $r.Title) {
                Write-Log "[$($r.Provider)] no match"
            } else {
                Write-Log "[$($r.Provider)] $($r.Title) - $($r.Artist)"
                $url = Get-YoutubeLink -Title $r.Title -Artist $r.Artist -YtApiKey $txtYtKey.Text
                Add-ResultLink "$($r.Provider): $($r.Title) - $($r.Artist)" $url
            }
        }

        if ($linkPanel.Controls.Count -eq 0) {
            Write-Log "No song matched by any configured service."
        }
    } catch {
        Write-Log "FAILED: $($_.Exception.Message)"
    } finally {
        Remove-Item $audioPath -ErrorAction SilentlyContinue
        $btnIdentify.Enabled = $true
    }
})

[void]$form.ShowDialog()
