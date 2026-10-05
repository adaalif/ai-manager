# Installs or updates Ai-Manager from the latest GitHub release.
#
#   irm https://raw.githubusercontent.com/adaalif/ai-manager/main/scripts/install.ps1 | iex
#
# Settings in %APPDATA%\ai-manager are never touched; only the two executables are replaced.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # the progress bar makes Invoke-WebRequest many times slower

$download   = 'https://github.com/adaalif/ai-manager/releases/latest/download'
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\Ai-Manager'
$shortcut   = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Ai-Manager.lnk'

# A running copy holds the .exe open, and Windows refuses to overwrite it.
Get-Process ai-manager -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

New-Item -ItemType Directory -Force $installDir | Out-Null
# The hook has to sit beside the app: Install hooks looks for it there.
foreach ($exe in 'ai-manager.exe', 'ai-manager-hook.exe') {
    Write-Host "Downloading $exe"
    Invoke-WebRequest "$download/$exe" -OutFile (Join-Path $installDir $exe) -UseBasicParsing
}

$appExe = Join-Path $installDir 'ai-manager.exe'
$link = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut)
$link.TargetPath = $appExe
$link.WorkingDirectory = $installDir
$link.Save()

Start-Process $appExe
Write-Host "Ai-Manager installed to $installDir and started. It is in the Start menu as Ai-Manager."
