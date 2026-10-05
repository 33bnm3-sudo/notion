<#
.SYNOPSIS
    ThumbCrop.exe를 (필요하면) 빌드하고, "썸네일 크롭" 바로가기를 두 군데에 만듭니다.
      - 바탕화면: 이미지를 아이콘 위로 끌어다 놓으면 에디터가 열림
      - 보내기(SendTo) 메뉴: 탐색기에서 이미지 우클릭 → 보내기 → 썸네일 크롭
#>
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$exe = Join-Path $dir 'ThumbCrop.exe'
$src = Join-Path $dir 'ThumbCrop.cs'

if (-not (Test-Path $exe) -or (Get-Item $src).LastWriteTime -gt (Get-Item $exe).LastWriteTime) {
    & (Join-Path $dir 'build.bat') /quiet
    if ($LASTEXITCODE -ne 0) { Write-Host '빌드에 실패했습니다.' -ForegroundColor Red; exit 1 }
}

$shell = New-Object -ComObject WScript.Shell
$targets = @(
    @{ Folder = [Environment]::GetFolderPath('Desktop'); Label = '바탕화면' },
    @{ Folder = [Environment]::GetFolderPath('SendTo');  Label = '보내기 메뉴' }
)
foreach ($t in $targets) {
    $path = Join-Path $t.Folder '썸네일 크롭.lnk'
    $lnk = $shell.CreateShortcut($path)
    $lnk.TargetPath = $exe
    $lnk.WorkingDirectory = $dir
    $lnk.Description = '이미지를 끌어다 놓으면 크롭 에디터가 열립니다'
    $lnk.Save()
    Write-Host ("{0}에 바로가기를 만들었습니다: {1}" -f $t.Label, $path) -ForegroundColor Green
}
Write-Host ''
Write-Host '이제 바탕화면의 "썸네일 크롭" 아이콘 위로 이미지를 끌어다 놓으면 됩니다.'
