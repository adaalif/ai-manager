# Installs or updates Ai-Manager from the private GitHub repo.
#
#   gh api repos/adaalif/ai-manager/contents/scripts/install.ps1 -H "Accept: application/vnd.github.raw" | Out-String | iex
#
# Needs git, the GitHub CLI signed in to an account with access to the repo, and Rust
# (MSVC toolchain). Builds from source, so the first run takes several minutes.
# Settings in %APPDATA%\ai-manager are never touched; only the two executables are replaced.

$ErrorActionPreference = 'Stop'

$repo       = 'adaalif/ai-manager'
$sourceDir  = Join-Path $env:LOCALAPPDATA 'Ai-Manager\src'
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\Ai-Manager'
$shortcut   = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Ai-Manager.lnk'

foreach ($tool in 'git', 'gh', 'cargo') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool is not installed. Install git, the GitHub CLI (winget install GitHub.cli) and Rust (https://rustup.rs), then run this again."
    }
}
# Through cmd: Windows PowerShell turns a redirected native stderr line into a terminating
# error under 'Stop', and gh prints its status to stderr.
cmd /c "gh auth status >nul 2>&1"
if ($LASTEXITCODE -ne 0) { throw "The GitHub CLI is not signed in. Run 'gh auth login' first." }

if (Test-Path (Join-Path $sourceDir '.git')) {
    Write-Host "Updating source in $sourceDir"
    git -C $sourceDir pull --ff-only
} else {
    Write-Host "Downloading source to $sourceDir"
    gh repo clone $repo $sourceDir
}
if ($LASTEXITCODE -ne 0) { throw "Could not download $repo." }

Write-Host 'Building (the first build takes several minutes)'
cargo build --release --locked --manifest-path (Join-Path $sourceDir 'Cargo.toml')
if ($LASTEXITCODE -ne 0) { throw 'Build failed; see the cargo output above.' }

# A running copy holds the .exe open, and Windows refuses to overwrite it.
Get-Process ai-manager -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

New-Item -ItemType Directory -Force $installDir | Out-Null
# The hook has to sit beside the app: Install hooks looks for it there.
foreach ($exe in 'ai-manager.exe', 'ai-manager-hook.exe') {
    Copy-Item (Join-Path $sourceDir "target\release\$exe") $installDir -Force
}

$appExe = Join-Path $installDir 'ai-manager.exe'
$link = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut)
$link.TargetPath = $appExe
$link.WorkingDirectory = $installDir
$link.Save()

Start-Process $appExe
Write-Host "Ai-Manager installed to $installDir and started. It is in the Start menu as Ai-Manager."
