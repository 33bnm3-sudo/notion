<#
.SYNOPSIS
    Minimal WinForms GUI to test the reels-fhd-converter logic: pick a
    4K+ video, convert it to FHD (auto vertical/horizontal), see the
    result. Mirrors the ffmpeg command built by the Rust module in
    reels-fhd-converter/src/lib.rs in this same repo.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ConfigDir = Join-Path $env:APPDATA "ReelsFhdTest"
$ConfigPath = Join-Path $ConfigDir "config.json"

function Load-Config {
    if (Test-Path $ConfigPath) {
        try { return Get-Content $ConfigPath -Raw | ConvertFrom-Json } catch { return $null }
    }
    return $null
}

function Save-Config($crf, $preset) {
    if (-not (Test-Path $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    }
    [PSCustomObject]@{ crf = $crf; preset = $preset } | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
}

$saved = Load-Config

$HasFfmpeg = [bool](Get-Command ffmpeg -ErrorAction SilentlyContinue)
$HasFfprobe = [bool](Get-Command ffprobe -ErrorAction SilentlyContinue)

# ---- Form ----
$form = New-Object System.Windows.Forms.Form
$form.Text = "Reels FHD Converter - Test"
$form.Size = New-Object System.Drawing.Size(560, 420)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$y = 15

if (-not ($HasFfmpeg -and $HasFfprobe)) {
    $lblWarning = New-Object System.Windows.Forms.Label
    $lblWarning.Text = "ffmpeg/ffprobe not found on PATH. Install ffmpeg first (https://ffmpeg.org) - this tool shells out to it."
    $lblWarning.Location = New-Object System.Drawing.Point(15, $y)
    $lblWarning.Size = New-Object System.Drawing.Size(515, 40)
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
$txtInput.Size = New-Object System.Drawing.Size(340, 24)
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
    $dir = Split-Path $path -Parent
    $name = [IO.Path]::GetFileNameWithoutExtension($path)
    $txtOutput.Text = Join-Path $dir ("$name-fhd.mp4")
}

$btnBrowseInput = New-Object System.Windows.Forms.Button
$btnBrowseInput.Text = "Browse..."
$btnBrowseInput.Location = New-Object System.Drawing.Point(360, ($y - 1))
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
$btnClearInput.Location = New-Object System.Drawing.Point(445, ($y - 1))
$btnClearInput.Size = New-Object System.Drawing.Size(60, 24)
$btnClearInput.Add_Click({ $txtInput.Text = ""; $txtOutput.Text = "" })
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

$y += 35
$lblOutput = New-Object System.Windows.Forms.Label
$lblOutput.Text = "Output video:"
$lblOutput.Location = New-Object System.Drawing.Point(15, $y)
$lblOutput.AutoSize = $true
$form.Controls.Add($lblOutput)

$y += 20
$txtOutput = New-Object System.Windows.Forms.TextBox
$txtOutput.Location = New-Object System.Drawing.Point(15, $y)
$txtOutput.Size = New-Object System.Drawing.Size(420, 24)
$form.Controls.Add($txtOutput)

$btnBrowseOutput = New-Object System.Windows.Forms.Button
$btnBrowseOutput.Text = "Save As..."
$btnBrowseOutput.Location = New-Object System.Drawing.Point(440, ($y - 1))
$btnBrowseOutput.Size = New-Object System.Drawing.Size(90, 24)
$btnBrowseOutput.Add_Click({
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = "MP4 video (*.mp4)|*.mp4"
    if ($txtOutput.Text) { $dialog.FileName = $txtOutput.Text }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtOutput.Text = $dialog.FileName
    }
})
$form.Controls.Add($btnBrowseOutput)

$y += 35
$lblCrf = New-Object System.Windows.Forms.Label
$lblCrf.Text = "CRF (18-28, lower = better quality):"
$lblCrf.Location = New-Object System.Drawing.Point(15, $y)
$lblCrf.AutoSize = $true
$form.Controls.Add($lblCrf)

$numCrf = New-Object System.Windows.Forms.NumericUpDown
$numCrf.Location = New-Object System.Drawing.Point(260, ($y - 3))
$numCrf.Size = New-Object System.Drawing.Size(60, 24)
$numCrf.Minimum = 0
$numCrf.Maximum = 51
$numCrf.Value = if ($saved -and $saved.crf) { [int]$saved.crf } else { 26 }
$form.Controls.Add($numCrf)

$y += 35
$lblPreset = New-Object System.Windows.Forms.Label
$lblPreset.Text = "Preset (slower = smaller file):"
$lblPreset.Location = New-Object System.Drawing.Point(15, $y)
$lblPreset.AutoSize = $true
$form.Controls.Add($lblPreset)

$cmbPreset = New-Object System.Windows.Forms.ComboBox
$cmbPreset.Location = New-Object System.Drawing.Point(260, ($y - 3))
$cmbPreset.Size = New-Object System.Drawing.Size(120, 24)
$cmbPreset.DropDownStyle = "DropDownList"
@("ultrafast", "superfast", "veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow") |
    ForEach-Object { $cmbPreset.Items.Add($_) | Out-Null }
$cmbPreset.SelectedItem = if ($saved -and $saved.preset) { $saved.preset } else { "slow" }
$form.Controls.Add($cmbPreset)

$y += 40
$btnConvert = New-Object System.Windows.Forms.Button
$btnConvert.Text = "Convert"
$btnConvert.Location = New-Object System.Drawing.Point(15, $y)
$btnConvert.Size = New-Object System.Drawing.Size(515, 32)
$btnConvert.Enabled = ($HasFfmpeg -and $HasFfprobe)
$form.Controls.Add($btnConvert)

$y += 42
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(15, $y)
$txtLog.Size = New-Object System.Drawing.Size(515, 150)
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$form.Controls.Add($txtLog)

function Write-Log($text) {
    $txtLog.AppendText("$text`r`n")
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-VideoResolution($path) {
    $raw = & ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 -- $path
    if ($LASTEXITCODE -ne 0 -or -not $raw) {
        throw "ffprobe failed to read resolution for $path"
    }
    $parts = $raw.Trim() -split "x"
    return @{ width = [int]$parts[0]; height = [int]$parts[1] }
}

$btnConvert.Add_Click({
    $input_ = $txtInput.Text.Trim()
    $output = $txtOutput.Text.Trim()
    $crf = [int]$numCrf.Value
    $preset = $cmbPreset.SelectedItem

    if ([string]::IsNullOrWhiteSpace($input_)) {
        [System.Windows.Forms.MessageBox]::Show("Choose an input video first.", "Missing input") | Out-Null
        return
    }
    if ([string]::IsNullOrWhiteSpace($output)) {
        [System.Windows.Forms.MessageBox]::Show("Choose an output path first.", "Missing output") | Out-Null
        return
    }

    Save-Config $crf $preset

    $btnConvert.Enabled = $false
    $txtLog.Clear()

    try {
        Write-Log "Probing resolution..."
        $res = Get-VideoResolution $input_
        Write-Log "Source: $($res.width)x$($res.height)"

        if ($res.width -gt $res.height) {
            $targetW = 1920; $targetH = 1080
        } else {
            $targetW = 1080; $targetH = 1920
        }
        Write-Log "Target: ${targetW}x${targetH} (auto-detected orientation)"

        if ($res.width -lt $targetW -or $res.height -lt $targetH) {
            throw "Source resolution ($($res.width)x$($res.height)) is smaller than the target ($targetW`x$targetH) - upscaling isn't supported."
        }

        $vf = "hqdn3d=4:3:6:4.5,scale=${targetW}:${targetH}:flags=lanczos,unsharp=5:5:0.8:5:5:0.0"
        Write-Log "Running ffmpeg (this can take a while for slow presets)..."

        & ffmpeg -y -i $input_ -vf $vf -c:v libx265 -crf $crf -preset $preset -tag:v hvc1 -c:a copy -- $output 2>&1 |
            ForEach-Object { Write-Log $_ }

        if ($LASTEXITCODE -ne 0) {
            throw "ffmpeg exited with code $LASTEXITCODE"
        }

        Write-Log "Done: $output"
        Start-Process explorer.exe "/select,`"$output`""
    } catch {
        Write-Log "FAILED: $($_.Exception.Message)"
    } finally {
        $btnConvert.Enabled = $true
    }
})

[void]$form.ShowDialog()
