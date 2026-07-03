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

# Manually maintained from ai.google.dev/gemini-api/docs/pricing (checked 2026-07). Google
# does not expose pricing through the API, so this can drift - treat it as an estimate, not
# a bill. USD/KRW is a rough snapshot too, not a live rate.
$UsdToKrw = 1550
$PricingTable = @{
    "gemini-2.5-flash-image"          = @{ "default" = 0.039 }
    "gemini-3.1-flash-image"          = @{ "1K" = 0.067; "2K" = 0.101; "4K" = 0.151 }
    "gemini-3.1-flash-image-preview"  = @{ "1K" = 0.067; "2K" = 0.101; "4K" = 0.151 }
    "gemini-3.1-flash-lite-image"     = @{ "1K" = 0.034 }
    "gemini-3-pro-image"              = @{ "1K" = 0.134; "2K" = 0.134; "4K" = 0.24 }
    "gemini-3-pro-image-preview"      = @{ "1K" = 0.134; "2K" = 0.134; "4K" = 0.24 }
}

function Get-EstimatedPriceUsd($model, $size) {
    if (-not $PricingTable.ContainsKey($model)) {
        return @{ price = $null; exact = $false }
    }
    $sizes = $PricingTable[$model]
    if ($sizes.ContainsKey($size)) {
        return @{ price = $sizes[$size]; exact = $true }
    }
    if ($sizes.ContainsKey("default")) {
        return @{ price = $sizes["default"]; exact = $false }
    }
    $fallback = $sizes.GetEnumerator() | Select-Object -First 1
    return @{ price = $fallback.Value; exact = $false }
}

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

function Save-Config($apiKey, $aspectRatio, $imageSize, $model, $count, $outputFolder) {
    if (-not (Test-Path $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    }
    $config = [PSCustomObject]@{
        apiKey       = $apiKey
        aspectRatio  = $aspectRatio
        imageSize    = $imageSize
        model        = $model
        count        = $count
        outputFolder = $outputFolder
    }
    $config | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
}

$saved = Load-Config

# ---- Form ----
$form = New-Object System.Windows.Forms.Form
$form.Text = "Gemini Image Generator - Test"
$form.Size = New-Object System.Drawing.Size(560, 655)
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

$y += 22
$lnkGetKey = New-Object System.Windows.Forms.LinkLabel
$lnkGetKey.Text = "Get an API key (Google AI Studio)"
$lnkGetKey.Location = New-Object System.Drawing.Point(100, $y)
$lnkGetKey.AutoSize = $true
$lnkGetKey.Add_LinkClicked({ Start-Process "https://aistudio.google.com/app/apikey" })
$form.Controls.Add($lnkGetKey)

$y += 25
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
$lblFolder = New-Object System.Windows.Forms.Label
$lblFolder.Text = "Output folder:"
$lblFolder.Location = New-Object System.Drawing.Point(15, $y)
$lblFolder.AutoSize = $true
$form.Controls.Add($lblFolder)

$y += 20
$txtFolder = New-Object System.Windows.Forms.TextBox
$txtFolder.Location = New-Object System.Drawing.Point(15, $y)
$txtFolder.Size = New-Object System.Drawing.Size(420, 24)
$txtFolder.ReadOnly = $true
$txtFolder.Text = if ($saved -and $saved.outputFolder) { $saved.outputFolder } else { $OutputRoot }
$form.Controls.Add($txtFolder)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "Browse..."
$btnBrowse.Location = New-Object System.Drawing.Point(440, ($y - 1))
$btnBrowse.Size = New-Object System.Drawing.Size(90, 24)
$btnBrowse.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Choose where generated images will be saved"
    if (Test-Path $txtFolder.Text) { $dialog.SelectedPath = $txtFolder.Text }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtFolder.Text = $dialog.SelectedPath
    }
})
$form.Controls.Add($btnBrowse)

$y += 35
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

$DefaultModels = @("gemini-3.1-flash-image", "gemini-3.1-flash-lite-image")

$cmbModel = New-Object System.Windows.Forms.ComboBox
$cmbModel.Location = New-Object System.Drawing.Point(150, ($y - 3))
$cmbModel.Size = New-Object System.Drawing.Size(280, 24)
$cmbModel.DropDownStyle = "DropDownList"
$DefaultModels | ForEach-Object { $cmbModel.Items.Add($_) | Out-Null }
$cmbModel.SelectedItem = if ($saved -and $saved.model) { $saved.model } else { $DefaultModels[0] }
$form.Controls.Add($cmbModel)

$btnRefreshModels = New-Object System.Windows.Forms.Button
$btnRefreshModels.Text = "Refresh list"
$btnRefreshModels.Location = New-Object System.Drawing.Point(440, ($y - 4))
$btnRefreshModels.Size = New-Object System.Drawing.Size(90, 26)
$form.Controls.Add($btnRefreshModels)

$y += 24
$lblPrice = New-Object System.Windows.Forms.Label
$lblPrice.Text = "Estimated cost: -"
$lblPrice.Location = New-Object System.Drawing.Point(15, $y)
$lblPrice.AutoSize = $true
$lblPrice.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblPrice)

$y += 28
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

function Update-PriceEstimate {
    $model = $cmbModel.SelectedItem
    $size = $cmbSize.SelectedItem
    $count = [int]$numCount.Value

    if (-not $model -or -not $size) {
        $lblPrice.Text = "Estimated cost: -"
        return
    }

    $result = Get-EstimatedPriceUsd $model $size
    if ($null -eq $result.price) {
        $lblPrice.Text = "Estimated cost: unknown for this model (check the official pricing page)"
        return
    }

    $usd = $result.price
    $krw = [math]::Round($usd * $UsdToKrw)
    $totalUsd = [math]::Round($usd * $count, 3)
    $totalKrw = [math]::Round($usd * $count * $UsdToKrw)
    $note = if ($result.exact) { "" } else { " (approx, no exact price for this size)" }

    $lblPrice.Text = ("Estimated cost: ~`${0}/image (~{1} KRW){2}  |  total for {3}: ~`${4} (~{5} KRW)" `
        -f $usd, $krw, $note, $count, $totalUsd, $totalKrw)
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

# Asks Gemini's own ListModels endpoint what this API key can actually see, instead of
# keeping a hardcoded model list that goes stale whenever Google ships a new model or
# retires an old one. Filters to models that (a) support generateContent and (b) look like
# image-output models by name (Google's own image models all have "image" in the model id,
# e.g. gemini-3.1-flash-image; plain Imagen models use a separate :predict API, not
# generateContent, so they're naturally excluded by the generateContent check).
function Get-ImageModels($apiKey) {
    $names = @()
    $pageToken = $null
    do {
        $url = "https://generativelanguage.googleapis.com/v1beta/models?pageSize=100"
        if ($pageToken) { $url += "&pageToken=$pageToken" }
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers @{ "x-goog-api-key" = $apiKey }
        $imageModels = $response.models | Where-Object {
            $_.supportedGenerationMethods -contains "generateContent" -and $_.name -match "image"
        }
        $names += $imageModels | ForEach-Object { $_.name -replace "^models/", "" }
        $pageToken = $response.nextPageToken
    } while ($pageToken)

    return $names | Sort-Object -Unique
}

function Refresh-ModelList($apiKey) {
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        return
    }
    try {
        $models = Get-ImageModels $apiKey
        if ($models.Count -eq 0) {
            Write-Log "Model list refresh: no image-capable models found for this key, keeping defaults."
            return
        }
        $previous = $cmbModel.SelectedItem
        $cmbModel.Items.Clear()
        $models | ForEach-Object { $cmbModel.Items.Add($_) | Out-Null }
        if ($previous -and ($models -contains $previous)) {
            $cmbModel.SelectedItem = $previous
        } else {
            $cmbModel.SelectedIndex = 0
        }
        Write-Log "Model list refreshed: $($models -join ', ')"
    } catch {
        Write-Log "Model list refresh failed: $($_.Exception.Message)"
    }
}

$btnRefreshModels.Add_Click({
    Refresh-ModelList $txtKey.Text.Trim()
})

$form.Add_Shown({
    if ($saved -and $saved.apiKey) {
        Refresh-ModelList $saved.apiKey
    }
    Update-PriceEstimate
})

$cmbModel.Add_SelectedIndexChanged({ Update-PriceEstimate })
$cmbSize.Add_SelectedIndexChanged({ Update-PriceEstimate })
$numCount.Add_ValueChanged({ Update-PriceEstimate })

$btnGenerate.Add_Click({
    $apiKey = $txtKey.Text.Trim()
    $prompt = $txtPrompt.Text.Trim()
    $aspectRatio = $cmbRatio.SelectedItem
    $imageSize = $cmbSize.SelectedItem
    $model = $cmbModel.SelectedItem
    $count = [int]$numCount.Value
    $outputFolder = $txtFolder.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        [System.Windows.Forms.MessageBox]::Show("Enter an API key first.", "Missing API key") | Out-Null
        return
    }
    if ([string]::IsNullOrWhiteSpace($prompt)) {
        [System.Windows.Forms.MessageBox]::Show("Enter a prompt first.", "Missing prompt") | Out-Null
        return
    }
    if ([string]::IsNullOrWhiteSpace($outputFolder)) {
        [System.Windows.Forms.MessageBox]::Show("Choose an output folder first.", "Missing output folder") | Out-Null
        return
    }

    Save-Config $apiKey $aspectRatio $imageSize $model $count $outputFolder

    $btnGenerate.Enabled = $false
    $txtLog.Clear()

    if (-not (Test-Path $outputFolder)) {
        New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $batchDir = Join-Path $outputFolder $stamp
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
