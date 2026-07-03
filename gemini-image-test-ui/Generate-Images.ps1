<#
.SYNOPSIS
    Minimal WinForms GUI to test the Gemini image generation API:
    enter an API key + prompt, generate a batch of images, see them
    land in a folder. Mirrors the request/response shape used by the
    gemini-image-generator Rust module in this same repo.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ConfigDir = Join-Path $env:APPDATA "GeminiImageTest"
$ConfigPath = Join-Path $ConfigDir "config.json"
$OutputRoot = Join-Path ([Environment]::GetFolderPath("MyPictures")) "GeminiImageTest"

function Load-Config {
    if (Test-Path $ConfigPath) {
        try {
            return Get-Content $ConfigPath -Raw | ConvertFrom-Json
        } catch {
            return $null
        }
    }
    return $null
}

function Save-Config($apiKey, $aspectRatio, $imageSize, $model, $count) {
    if (-not (Test-Path $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    }
    $config = [PSCustomObject]@{
        apiKey      = $apiKey
        aspectRatio = $aspectRatio
        imageSize   = $imageSize
        model       = $model
        count       = $count
    }
    $config | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
}

$saved = Load-Config

# ---- Form ----
$form = New-Object System.Windows.Forms.Form
$form.Text = "Gemini Image Generator - Test"
$form.Size = New-Object System.Drawing.Size(560, 560)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$y = 15

$lblKey = New-Object System.Windows.Forms.Label
$lblKey.Text = "API Key:"
$lblKey.Location = New-Object System.Drawing.Point(15, $y)
$lblKey.AutoSize = $true
$form.Controls.Add($lblKey)

$txtKey = New-Object System.Windows.Forms.TextBox
$txtKey.Location = New-Object System.Drawing.Point(100, ($y - 3))
$txtKey.Size = New-Object System.Drawing.Size(340, 24)
$txtKey.UseSystemPasswordChar = $true
if ($saved -and $saved.apiKey) { $txtKey.Text = $saved.apiKey }
$form.Controls.Add($txtKey)

$chkShowKey = New-Object System.Windows.Forms.CheckBox
$chkShowKey.Text = "Show"
$chkShowKey.Location = New-Object System.Drawing.Point(450, $y)
$chkShowKey.AutoSize = $true
$chkShowKey.Add_CheckedChanged({ $txtKey.UseSystemPasswordChar = -not $chkShowKey.Checked })
$form.Controls.Add($chkShowKey)

$y += 35
$lblPrompt = New-Object System.Windows.Forms.Label
$lblPrompt.Text = "Prompt:"
$lblPrompt.Location = New-Object System.Drawing.Point(15, $y)
$lblPrompt.AutoSize = $true
$form.Controls.Add($lblPrompt)

$y += 20
$txtPrompt = New-Object System.Windows.Forms.TextBox
$txtPrompt.Location = New-Object System.Drawing.Point(15, $y)
$txtPrompt.Size = New-Object System.Drawing.Size(515, 90)
$txtPrompt.Multiline = $true
$txtPrompt.ScrollBars = "Vertical"
$form.Controls.Add($txtPrompt)

$y += 105
$lblCount = New-Object System.Windows.Forms.Label
$lblCount.Text = "Number of images:"
$lblCount.Location = New-Object System.Drawing.Point(15, $y)
$lblCount.AutoSize = $true
$form.Controls.Add($lblCount)

$numCount = New-Object System.Windows.Forms.NumericUpDown
$numCount.Location = New-Object System.Drawing.Point(150, ($y - 3))
$numCount.Size = New-Object System.Drawing.Size(60, 24)
$numCount.Minimum = 1
$numCount.Maximum = 20
$numCount.Value = if ($saved -and $saved.count) { [int]$saved.count } else { 10 }
$form.Controls.Add($numCount)

$y += 35
$lblRatio = New-Object System.Windows.Forms.Label
$lblRatio.Text = "Aspect ratio:"
$lblRatio.Location = New-Object System.Drawing.Point(15, $y)
$lblRatio.AutoSize = $true
$form.Controls.Add($lblRatio)

$cmbRatio = New-Object System.Windows.Forms.ComboBox
$cmbRatio.Location = New-Object System.Drawing.Point(150, ($y - 3))
$cmbRatio.Size = New-Object System.Drawing.Size(100, 24)
$cmbRatio.DropDownStyle = "DropDownList"
@("1:1", "16:9", "9:16", "4:3", "3:4") | ForEach-Object { $cmbRatio.Items.Add($_) | Out-Null }
$cmbRatio.SelectedItem = if ($saved -and $saved.aspectRatio) { $saved.aspectRatio } else { "1:1" }
$form.Controls.Add($cmbRatio)

$lblSize = New-Object System.Windows.Forms.Label
$lblSize.Text = "Image size:"
$lblSize.Location = New-Object System.Drawing.Point(270, $y)
$lblSize.AutoSize = $true
$form.Controls.Add($lblSize)

$cmbSize = New-Object System.Windows.Forms.ComboBox
$cmbSize.Location = New-Object System.Drawing.Point(360, ($y - 3))
$cmbSize.Size = New-Object System.Drawing.Size(80, 24)
$cmbSize.DropDownStyle = "DropDownList"
@("1K", "2K", "4K") | ForEach-Object { $cmbSize.Items.Add($_) | Out-Null }
$cmbSize.SelectedItem = if ($saved -and $saved.imageSize) { $saved.imageSize } else { "2K" }
$form.Controls.Add($cmbSize)

$y += 35
$lblModel = New-Object System.Windows.Forms.Label
$lblModel.Text = "Model:"
$lblModel.Location = New-Object System.Drawing.Point(15, $y)
$lblModel.AutoSize = $true
$form.Controls.Add($lblModel)

$cmbModel = New-Object System.Windows.Forms.ComboBox
$cmbModel.Location = New-Object System.Drawing.Point(150, ($y - 3))
$cmbModel.Size = New-Object System.Drawing.Size(260, 24)
$cmbModel.DropDownStyle = "DropDownList"
@("gemini-3.1-flash-image", "gemini-3.1-flash-lite-image") | ForEach-Object { $cmbModel.Items.Add($_) | Out-Null }
$cmbModel.SelectedItem = if ($saved -and $saved.model) { $saved.model } else { "gemini-3.1-flash-image" }
$form.Controls.Add($cmbModel)

$y += 40
$btnGenerate = New-Object System.Windows.Forms.Button
$btnGenerate.Text = "Generate"
$btnGenerate.Location = New-Object System.Drawing.Point(15, $y)
$btnGenerate.Size = New-Object System.Drawing.Size(515, 32)
$form.Controls.Add($btnGenerate)

$y += 42
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(15, $y)
$txtLog.Size = New-Object System.Drawing.Size(515, 180)
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$form.Controls.Add($txtLog)

function Write-Log($text) {
    $txtLog.AppendText("$text`r`n")
    [System.Windows.Forms.Application]::DoEvents()
}

function Generate-One($apiKey, $prompt, $model, $aspectRatio, $imageSize, $outPath) {
    $url = "https://generativelanguage.googleapis.com/v1beta/models/$($model):generateContent"

    # NOTE: ConvertTo-Json silently collapses single-element arrays (e.g. "contents": [{...}]
    # becomes "contents": {...}), which would break this request shape. Building the JSON by
    # hand for the fixed structure and only running the user-supplied prompt through
    # ConvertTo-Json (as a scalar, which is unaffected) avoids that trap entirely.
    $escapedPrompt = $prompt | ConvertTo-Json
    $body = @"
{
  "contents": [{"parts": [{"text": $escapedPrompt}]}],
  "generationConfig": {
    "responseModalities": ["TEXT", "IMAGE"],
    "imageConfig": {"aspectRatio": "$aspectRatio", "imageSize": "$imageSize"}
  }
}
"@

    try {
        $response = Invoke-RestMethod -Uri $url -Method Post `
            -Headers @{ "x-goog-api-key" = $apiKey } `
            -ContentType "application/json; charset=utf-8" `
            -Body $body
    } catch {
        $errBody = $null
        if ($_.ErrorDetails.Message) { $errBody = $_.ErrorDetails.Message }
        throw "request failed: $($_.Exception.Message) $errBody"
    }

    if ($response.promptFeedback.blockReason) {
        throw "blocked by safety filter: $($response.promptFeedback.blockReason)"
    }

    $imagePart = $response.candidates[0].content.parts | Where-Object { $_.inlineData -ne $null } | Select-Object -First 1
    if (-not $imagePart) {
        $finishReason = $response.candidates[0].finishReason
        throw "no image in response (finishReason: $finishReason)"
    }

    $bytes = [Convert]::FromBase64String($imagePart.inlineData.data)
    [IO.File]::WriteAllBytes($outPath, $bytes)
}

$btnGenerate.Add_Click({
    $apiKey = $txtKey.Text.Trim()
    $prompt = $txtPrompt.Text.Trim()
    $aspectRatio = $cmbRatio.SelectedItem
    $imageSize = $cmbSize.SelectedItem
    $model = $cmbModel.SelectedItem
    $count = [int]$numCount.Value

    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        [System.Windows.Forms.MessageBox]::Show("Enter an API key first.", "Missing API key") | Out-Null
        return
    }
    if ([string]::IsNullOrWhiteSpace($prompt)) {
        [System.Windows.Forms.MessageBox]::Show("Enter a prompt first.", "Missing prompt") | Out-Null
        return
    }

    Save-Config $apiKey $aspectRatio $imageSize $model $count

    $btnGenerate.Enabled = $false
    $txtLog.Clear()

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $batchDir = Join-Path $OutputRoot $stamp
    New-Item -ItemType Directory -Path $batchDir -Force | Out-Null

    Write-Log "Output folder: $batchDir"
    Write-Log "Generating $count image(s)..."

    $successCount = 0
    for ($i = 1; $i -le $count; $i++) {
        Write-Log "[$i/$count] requesting..."
        $outPath = Join-Path $batchDir ("image-{0:D2}.png" -f $i)
        try {
            Generate-One $apiKey $prompt $model $aspectRatio $imageSize $outPath
            Write-Log "[$i/$count] saved: $(Split-Path $outPath -Leaf)"
            $successCount++
        } catch {
            Write-Log "[$i/$count] FAILED: $($_.Exception.Message)"
        }
    }

    Write-Log "Done. $successCount/$count succeeded."
    $btnGenerate.Enabled = $true

    if ($successCount -gt 0) {
        Start-Process explorer.exe $batchDir
    }
})

[void]$form.ShowDialog()
