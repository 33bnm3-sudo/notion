<#
.SYNOPSIS
    Minimal WinForms GUI to test the logo-to-svg logic: pick a
    transparent-background logo PNG, vectorize it to SVG, see the
    result. Shells out to logo-to-svg-cli.exe (compiled from the
    logo-to-svg Rust crate in this same repo, cross-compiled for
    Windows since the sandbox that built it can't run/verify a
    Windows binary directly).
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$CliPath = Join-Path $PSScriptRoot "logo-to-svg-cli.exe"

$ConfigDir = Join-Path $env:APPDATA "LogoToSvgTest"
$ConfigPath = Join-Path $ConfigDir "config.json"

function Load-Config {
    if (Test-Path $ConfigPath) {
        try { return Get-Content $ConfigPath -Raw | ConvertFrom-Json } catch { return $null }
    }
    return $null
}

function Save-Config($colorPrecision, $filterSpeckle, $cornerThreshold) {
    if (-not (Test-Path $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    }
    [PSCustomObject]@{
        colorPrecision  = $colorPrecision
        filterSpeckle   = $filterSpeckle
        cornerThreshold = $cornerThreshold
    } | ConvertTo-Json | Set-Content -Path $ConfigPath -Encoding UTF8
}

$saved = Load-Config

# ---- Form ----
$form = New-Object System.Windows.Forms.Form
$form.Text = "Logo to SVG Converter - Test"
$form.Size = New-Object System.Drawing.Size(560, 420)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$y = 15

if (-not (Test-Path $CliPath)) {
    $lblWarning = New-Object System.Windows.Forms.Label
    $lblWarning.Text = "logo-to-svg-cli.exe not found next to this script."
    $lblWarning.Location = New-Object System.Drawing.Point(15, $y)
    $lblWarning.Size = New-Object System.Drawing.Size(515, 24)
    $lblWarning.ForeColor = [System.Drawing.Color]::Firebrick
    $form.Controls.Add($lblWarning)
    $y += 30
}

$lblInput = New-Object System.Windows.Forms.Label
$lblInput.Text = "Input PNG (transparent background):"
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

function Set-InputImage($path) {
    $ext = [IO.Path]::GetExtension($path).ToLower()
    if ($ext -ne ".png") {
        [System.Windows.Forms.MessageBox]::Show("Only .png is supported (needs an alpha channel).", "Unsupported file") | Out-Null
        return
    }
    $txtInput.Text = $path
    $dir = Split-Path $path -Parent
    $name = [IO.Path]::GetFileNameWithoutExtension($path)
    $txtOutput.Text = Join-Path $dir ("$name.svg")
}

$btnBrowseInput = New-Object System.Windows.Forms.Button
$btnBrowseInput.Text = "Browse..."
$btnBrowseInput.Location = New-Object System.Drawing.Point(360, ($y - 1))
$btnBrowseInput.Size = New-Object System.Drawing.Size(80, 24)
$btnBrowseInput.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Choose a logo PNG"
    $dialog.Filter = "PNG images (*.png)|*.png"
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Set-InputImage $dialog.FileName
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
    if ($files -and $files.Count -gt 0) { Set-InputImage $files[0] }
})

$y += 35
$lblOutput = New-Object System.Windows.Forms.Label
$lblOutput.Text = "Output SVG:"
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
    $dialog.Filter = "SVG image (*.svg)|*.svg"
    if ($txtOutput.Text) { $dialog.FileName = $txtOutput.Text }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtOutput.Text = $dialog.FileName
    }
})
$form.Controls.Add($btnBrowseOutput)

$y += 35
$lblColorPrecision = New-Object System.Windows.Forms.Label
$lblColorPrecision.Text = "Color precision (1-8):"
$lblColorPrecision.Location = New-Object System.Drawing.Point(15, $y)
$lblColorPrecision.AutoSize = $true
$form.Controls.Add($lblColorPrecision)

$numColorPrecision = New-Object System.Windows.Forms.NumericUpDown
$numColorPrecision.Location = New-Object System.Drawing.Point(180, ($y - 3))
$numColorPrecision.Size = New-Object System.Drawing.Size(50, 24)
$numColorPrecision.Minimum = 1
$numColorPrecision.Maximum = 8
$numColorPrecision.Value = if ($saved -and $saved.colorPrecision) { [int]$saved.colorPrecision } else { 6 }
$form.Controls.Add($numColorPrecision)

$lblFilterSpeckle = New-Object System.Windows.Forms.Label
$lblFilterSpeckle.Text = "Filter speckle:"
$lblFilterSpeckle.Location = New-Object System.Drawing.Point(250, $y)
$lblFilterSpeckle.AutoSize = $true
$form.Controls.Add($lblFilterSpeckle)

$numFilterSpeckle = New-Object System.Windows.Forms.NumericUpDown
$numFilterSpeckle.Location = New-Object System.Drawing.Point(345, ($y - 3))
$numFilterSpeckle.Size = New-Object System.Drawing.Size(50, 24)
$numFilterSpeckle.Minimum = 0
$numFilterSpeckle.Maximum = 100
$numFilterSpeckle.Value = if ($saved -and $saved.filterSpeckle) { [int]$saved.filterSpeckle } else { 4 }
$form.Controls.Add($numFilterSpeckle)

$lblCornerThreshold = New-Object System.Windows.Forms.Label
$lblCornerThreshold.Text = "Corner angle:"
$lblCornerThreshold.Location = New-Object System.Drawing.Point(410, $y)
$lblCornerThreshold.AutoSize = $true
$form.Controls.Add($lblCornerThreshold)

$numCornerThreshold = New-Object System.Windows.Forms.NumericUpDown
$numCornerThreshold.Location = New-Object System.Drawing.Point(490, ($y - 3))
$numCornerThreshold.Size = New-Object System.Drawing.Size(50, 24)
$numCornerThreshold.Minimum = 0
$numCornerThreshold.Maximum = 180
$numCornerThreshold.Value = if ($saved -and $saved.cornerThreshold) { [int]$saved.cornerThreshold } else { 60 }
$form.Controls.Add($numCornerThreshold)

$y += 40
$btnConvert = New-Object System.Windows.Forms.Button
$btnConvert.Text = "Convert"
$btnConvert.Location = New-Object System.Drawing.Point(15, $y)
$btnConvert.Size = New-Object System.Drawing.Size(515, 32)
$btnConvert.Enabled = (Test-Path $CliPath)
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

$btnConvert.Add_Click({
    $input_ = $txtInput.Text.Trim()
    $output = $txtOutput.Text.Trim()
    $colorPrecision = [int]$numColorPrecision.Value
    $filterSpeckle = [int]$numFilterSpeckle.Value
    $cornerThreshold = [int]$numCornerThreshold.Value

    if ([string]::IsNullOrWhiteSpace($input_)) {
        [System.Windows.Forms.MessageBox]::Show("Choose an input PNG first.", "Missing input") | Out-Null
        return
    }
    if ([string]::IsNullOrWhiteSpace($output)) {
        [System.Windows.Forms.MessageBox]::Show("Choose an output path first.", "Missing output") | Out-Null
        return
    }

    Save-Config $colorPrecision $filterSpeckle $cornerThreshold

    $btnConvert.Enabled = $false
    $txtLog.Clear()
    Write-Log "Running logo-to-svg-cli..."

    try {
        $result = & $CliPath --input $input_ --output $output `
            --color-precision $colorPrecision `
            --filter-speckle $filterSpeckle `
            --corner-threshold $cornerThreshold 2>&1
        $result | ForEach-Object { Write-Log $_ }

        if ($LASTEXITCODE -ne 0) {
            throw "logo-to-svg-cli exited with code $LASTEXITCODE"
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
