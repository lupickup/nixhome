<#
.SYNOPSIS
    Bootstrap a Windows PC onto a nixhome-based dotfiles repo.

.DESCRIPTION
    Rerunnable. Each step is skipped when already satisfied.

      1. Ensure a Git Credential Manager exists on Windows (installs Git.Git if not).
         WSL borrows it so a *private* dotfiles repo can be cloned over HTTPS
         with a browser login - no SSH key needed on a fresh box.
      2. Ensure the WSL distro exists (wsl --install). First install needs you to
         create the Linux user (and maybe reboot) and then rerun this script.
      3. Inside WSL: clone (or fast-forward) the dotfiles repo with submodules,
         then run its ./install (Nix + Home Manager + the rest of setup-wsl.sh).
      4. Apply the repo's WinGet configuration (Windows packages), if present.
         Falls back to per-package `winget install` where `winget configure`
         is disabled.

.EXAMPLE
    # From any PowerShell window on a fresh PC:
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/lupickup/nixhome/main/scripts/bootstrap-windows.ps1))) `
        -DotfilesRepo https://github.com/<you>/Dotfiles.git

.EXAMPLE
    # Preview only, no changes:
    .\bootstrap-windows.ps1 -DotfilesRepo https://github.com/<you>/Dotfiles.git -DryRun
#>
[CmdletBinding()]
param(
    [string]$DotfilesRepo = $env:DOTFILES_REPO,
    [string]$Distro = 'Ubuntu-24.04',
    # Path inside WSL; ~/ or relative = under the Linux $HOME.
    [string]$DotfilesDir = '~/Dotfiles',
    # Passed to the repo's installer as HM_TARGET (empty = installer default).
    [string]$HmTarget = '',
    # Relative to the repo root.
    [string]$WingetConfig = 'windows/winget.dsc.yaml',
    [switch]$SkipWsl,
    [switch]$SkipWinget,
    [switch]$DryRun,
    # Extra args for the repo's ./install (e.g. '--config-only').
    [string[]]$InstallArgs = @()
)

$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'  # make wsl.exe print UTF-8 instead of UTF-16
# Never hand a bare '~' to a native command: pwsh 7 expands it to the *Windows*
# home. Pass a $HOME-relative path instead and let bash resolve it.
$DotfilesDirArg = $DotfilesDir -replace '^~/?', ''

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

function Invoke-Native([string]$Description, [string]$Exe, [string[]]$Arguments) {
    if ($DryRun) { Write-Host "[dry-run] $Description`n          $Exe $($Arguments -join ' ')" -ForegroundColor Yellow; return }
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Description failed (exit $LASTEXITCODE)" }
}

function Find-Gcm {
    $candidates = @(
        (Get-Command git-credential-manager.exe -ErrorAction SilentlyContinue).Source,
        "$env:ProgramFiles\Git\mingw64\bin\git-credential-manager.exe",
        "$env:LOCALAPPDATA\Programs\Git\mingw64\bin\git-credential-manager.exe"
    )
    $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}

function Get-WslDistros {
    $out = & wsl.exe -l -q 2>$null
    if ($LASTEXITCODE -ne 0) { return @() }
    @($out | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
}

# Applies a WinGet configuration file. Where `winget configure` is disabled
# (older/managed winget), falls back to `winget install` for each
# `settings: { id: <Package>, source: winget }` entry.
function Invoke-WingetConfig([string]$Path) {
    $ids = @([regex]::Matches((Get-Content $Path -Raw), 'id:\s*([^\s,}]+),\s*source:\s*winget') |
        ForEach-Object { $_.Groups[1].Value })
    if ($DryRun) { Write-Host "[dry-run] winget configure -f $Path`n          packages: $($ids -join ', ')" -ForegroundColor Yellow; return }
    $out = & winget.exe configure -f $Path --accept-configuration-agreements --disable-interactivity 2>&1
    $code = $LASTEXITCODE
    $out | ForEach-Object { Write-Host "    $_" }
    if ($code -eq 0) { return }
    if (($out -join "`n") -notmatch 'not enabled') { throw "winget configure failed (exit $code)" }
    Write-Host '    winget configure is disabled here; installing packages one by one instead.'
    foreach ($id in $ids) {
        & winget.exe list --id $id -e --accept-source-agreements *> $null
        if ($LASTEXITCODE -eq 0) { Write-Host "    $id already installed"; continue }
        & winget.exe install --id $id -e --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity
        if ($LASTEXITCODE -ne 0) { Write-Warning "$id install failed (exit $LASTEXITCODE)" }
    }
}

if (-not $DotfilesRepo) { throw 'Pass -DotfilesRepo <git url> (or set $env:DOTFILES_REPO).' }
if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    throw 'winget not found. Install "App Installer" from the Microsoft Store, then rerun.'
}

# --- 1. Git Credential Manager ---------------------------------------------
Write-Step 'Git Credential Manager'
$gcm = Find-Gcm
if (-not $gcm) {
    Invoke-Native 'Install Git for Windows (provides GCM)' 'winget.exe' @(
        'install', '--id', 'Git.Git', '-e', '--source', 'winget',
        '--accept-package-agreements', '--accept-source-agreements')
    $gcm = Find-Gcm
}
if ($gcm) { Write-Host "    $gcm" } elseif (-not $DryRun) { throw 'Git Credential Manager still not found.' }

if ($SkipWsl) { Write-Step 'Skipping WSL (-SkipWsl)' } else {
    # --- 2. WSL distro -------------------------------------------------------
    Write-Step "WSL distro $Distro"
    if ((Get-WslDistros) -notcontains $Distro) {
        Invoke-Native "Install WSL distro $Distro" 'wsl.exe' @('--install', '-d', $Distro)
        Write-Host @"

WSL/$Distro was just installed. Finish the Linux user setup in the window that
opened (reboot first if Windows asks), then rerun this same command.
"@ -ForegroundColor Green
        return
    }
    Write-Host '    present'

    # --- 3. Clone + install inside WSL --------------------------------------
    Write-Step "Dotfiles in WSL ($DotfilesDir)"
    $bash = @'
set -euo pipefail
repo="$1"; dir="$2"; gcm="$3"; hm_target="$4"; shift 4
[[ "$dir" == /* ]] || dir="$HOME/$dir"  # relative = under Linux $HOME
[[ "$gcm" == "-" ]] && gcm=""          # '-' = empty (PS 5.1 drops empty args)
[[ "$hm_target" == "-" ]] && hm_target=""

missing=()
for c in git curl; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
if ((${#missing[@]})); then
  sudo apt-get update -y && sudo apt-get install -y "${missing[@]}"
fi

# Borrow Windows GCM for HTTPS auth; rewrite SSH submodule URLs to HTTPS so a
# fresh box without SSH keys can still clone. Nothing is written to git config.
g=(git -c url.https://github.com/.insteadOf=git@github.com:)
if [[ -n "$gcm" ]]; then g+=(-c credential.helper= -c "credential.helper=${gcm// /\\ }"); fi

if [[ ! -d "$dir/.git" ]]; then
  "${g[@]}" clone --recurse-submodules "$repo" "$dir"
elif [[ -z "$(git -C "$dir" status --porcelain --ignore-submodules)" ]]; then
  "${g[@]}" -C "$dir" pull --ff-only
else
  echo "Local changes in $dir - skipping pull."
fi
"${g[@]}" -C "$dir" submodule update --init --recursive

cd "$dir"
[[ -x ./install ]] || { echo "No executable ./install in $dir - is this a dotfiles repo?" >&2; exit 1; }
if [[ -n "$hm_target" ]]; then export HM_TARGET="$hm_target"; fi
./install "$@"
'@
    # --exec skips the login shell, so arguments reach bash verbatim.
    $gcmWsl = '-'
    if ($gcm) { $gcmWsl = (& wsl.exe -d $Distro --exec wslpath -u "$gcm").Trim() }
    $hm = if ($HmTarget) { $HmTarget } else { '-' }
    $tmp = Join-Path $env:TEMP 'nixhome-bootstrap.sh'
    [IO.File]::WriteAllText($tmp, ($bash -replace "`r`n", "`n"))
    $tmpWsl = (& wsl.exe -d $Distro --exec wslpath -u "$tmp").Trim()
    Invoke-Native 'Clone dotfiles + run ./install in WSL' 'wsl.exe' (
        @('-d', $Distro, '--exec', 'bash', $tmpWsl, $DotfilesRepo, $DotfilesDirArg, $gcmWsl, $hm) + $InstallArgs)
}

# --- 4. WinGet configuration -------------------------------------------------
if ($SkipWinget -or $SkipWsl) { Write-Step 'Skipping WinGet configuration' } else {
    Write-Step "WinGet configuration ($WingetConfig)"
    $cfgWin = (& wsl.exe -d $Distro --exec bash -c 'd=$1; [[ $d == /* ]] || d=$HOME/$d; wslpath -w $d/$2' _ $DotfilesDirArg $WingetConfig).Trim()
    if (-not (Test-Path $cfgWin)) {
        Write-Host "    not found ($cfgWin) - skipping"
    } else {
        # winget can't always read \\wsl$ paths; stage a local copy.
        $cfgTmp = Join-Path $env:TEMP 'dotfiles-winget.dsc.yaml'
        Copy-Item $cfgWin $cfgTmp -Force
        Invoke-WingetConfig $cfgTmp
    }
}

Write-Step 'Done. Open a new terminal (and a new WSL shell) to pick up changes.'
