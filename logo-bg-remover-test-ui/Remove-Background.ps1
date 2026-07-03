<#
.SYNOPSIS
    Minimal WinForms GUI to test the logo-bg-remover logic: pick an
    image, remove the background, see the result. Shells out to
    logo-bg-remover-cli.exe, which you build once on your own machine
    (see README.md in this folder for why it isn't bundled here).
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$CliPath = Join-Path $PSScriptRoot "logo-bg-remover-cli.exe"

$ConfigDir = Join-Path $env:APPDATA "LogoBgRemoverTest"
$ConfigPath = Join-Path $ConfigDir "config.json"

# ---- Form ----
$form = New-Object System.Windows.Forms.Form
$form.Text = "Logo Background Remover - Test"
$form.Size = New-Object System.Drawing.Size(560, 380)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$y = 15

if (-not (Test-Path $CliPath)) {
    $lblWarning = New-Object System.Windows.Forms.Label
    $lblWarning.Text = "logo-bg-remover-cli.exe not found. Build it once first - see README.md in this folder."
    $lblWarning.Location = New-Object System.Drawing.Point(15, $y)
    $lblWarning.Size = New-Object System.Drawing.Size(515, 40)
    $lblWarning.ForeColor = [System.Drawing.Color]::Firebrick
    $form.Controls.Add($lblWarning)
    $y += 45
}

$lblInput = New-Object System.Windows.Forms.Label
$lblInput.Text = "Input image:"
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
    if ($ext -notin @(".png", ".jpg", ".jpeg")) {
        [System.Windows.Forms.MessageBox]::Show("Unsupported file type: $path", "Unsupported image") | Out-Null
        return
    }
    $txtInput.Text = $path
    $dir = Split-Path $path -Parent
    $name = [IO.Path]::GetFileNameWithoutExtension($path)
    $txtOutput.Text = Join-Path $dir ("$name-nobg.png")
}

$btnBrowseInput = New-Object System.Windows.Forms.Button
$btnBrowseInput.Text = "Browse..."
$btnBrowseInput.Location = New-Object System.Drawing.Point(360, ($y - 1))
$btnBrowseInput.Size = New-Object System.Drawing.Size(80, 24)
$btnBrowseInput.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Choose an image"
    $dialog.Filter = "Images (*.png;*.jpg;*.jpeg)|*.png;*.jpg;*.jpeg"
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
$lblOutput.Text = "Output PNG (transparent):"
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
    $dialog.Filter = "PNG image (*.png)|*.png"
    if ($txtOutput.Text) { $dialog.FileName = $txtOutput.Text }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtOutput.Text = $dialog.FileName
    }
})
$form.Controls.Add($btnBrowseOutput)

$y += 45
$btnRemove = New-Object System.Windows.Forms.Button
$btnRemove.Text = "Remove Background"
$btnRemove.Location = New-Object System.Drawing.Point(15, $y)
$btnRemove.Size = New-Object System.Drawing.Size(515, 32)
$btnRemove.Enabled = (Test-Path $CliPath)
$form.Controls.Add($btnRemove)

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

$btnRemove.Add_Click({
    $input_ = $txtInput.Text.Trim()
    $output = $txtOutput.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($input_)) {
        [System.Windows.Forms.MessageBox]::Show("Choose an input image first.", "Missing input") | Out-Null
        return
    }
    if ([string]::IsNullOrWhiteSpace($output)) {
        [System.Windows.Forms.MessageBox]::Show("Choose an output path first.", "Missing output") | Out-Null
        return
    }

    $btnRemove.Enabled = $false
    $txtLog.Clear()
    Write-Log "Running logo-bg-remover-cli (first run downloads a ~176MB model, can take a while)..."

    try {
        $result = & $CliPath --input $input_ --output $output 2>&1
        $result | ForEach-Object { Write-Log $_ }

        if ($LASTEXITCODE -ne 0) {
            throw "logo-bg-remover-cli exited with code $LASTEXITCODE"
        }

        Write-Log "Done: $output"
        Start-Process explorer.exe "/select,`"$output`""
    } catch {
        Write-Log "FAILED: $($_.Exception.Message)"
    } finally {
        $btnRemove.Enabled = $true
    }
})

[void]$form.ShowDialog()
