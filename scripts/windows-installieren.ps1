# Bambu Studio Multi – baut die App unter Windows und installiert sie
#
# Start per Doppelklick auf "Bambu Studio Multi aktualisieren (Windows).bat" im Repo-Ordner
# oder in PowerShell:
#   powershell -ExecutionPolicy Bypass -File scripts\windows-installieren.ps1 [-OhneUpdate] [-Sauber] [-AbhaengigkeitenNeu]
#
# Erster Lauf: ca. 1–2 Stunden (Abhängigkeiten). Danach: ca. 10–30 Minuten.
# Wichtig: Repo in einen KURZEN Pfad klonen, z. B. C:\BSM (Windows hat Probleme mit langen Pfaden).

param(
    [switch]$OhneUpdate,
    [switch]$Sauber,
    [switch]$AbhaengigkeitenNeu
)

$ErrorActionPreference = "Stop"
$RepoDir   = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$AppName   = "Bambu Studio Multi"
$Ziel      = Join-Path $env:LOCALAPPDATA "Programs\$AppName"
$Werkzeuge = Join-Path $RepoDir ".build-werkzeuge"
$DepsDir   = Join-Path $RepoDir "deps\build"
$DepsOut   = Join-Path $DepsDir "BambuStudio_dep"
$DepsFertig= Join-Path $DepsOut "usr\local"
$BuildDir  = Join-Path $RepoDir "build"
$InstallDir= Join-Path $RepoDir "install-dir"
$Log       = Join-Path $RepoDir ("build-" + (Get-Date -Format "yyyyMMdd-HHmm") + ".log")

function Schritt($text) { Write-Host ""; Write-Host "==> $text" -ForegroundColor Green }
function Fehler($text)  { Write-Host ""; Write-Host "Fehler: $text" -ForegroundColor Red; Stop-Transcript | Out-Null; exit 1 }
function Ausfuehren($exe, [string[]]$argumente) {
    & $exe @argumente
    if ($LASTEXITCODE -ne 0) { Fehler "$exe ist mit Code $LASTEXITCODE abgebrochen. Protokoll: $Log" }
}

Start-Transcript -Path $Log | Out-Null
Write-Host "Protokoll: $Log"

if ($RepoDir.Length -gt 40) {
    Write-Host "Hinweis: Der Repo-Pfad ist lang ($($RepoDir.Length) Zeichen). Falls der Build mit Pfadfehlern abbricht, klone das Repo nach z. B. C:\BSM." -ForegroundColor Yellow
}

# ---------------------------------------------------------------- Voraussetzungen
Schritt "Prüfe Voraussetzungen"
$frei = [math]::Floor((Get-PSDrive ((Split-Path $RepoDir -Qualifier).TrimEnd(':'))).Free / 1GB)
if ($frei -lt 30) { Fehler "Zu wenig Speicherplatz: $frei GB frei, nötig sind etwa 30 GB." }

$winget = Get-Command winget -ErrorAction SilentlyContinue
function Installiere($id, $name, [string]$extra = "") {
    if (-not $winget) { Fehler "$name fehlt und winget ist nicht verfügbar. Bitte $name von Hand installieren." }
    Write-Host "Installiere $name ..."
    $a = @("install", "--id", $id, "-e", "--accept-package-agreements", "--accept-source-agreements")
    if ($extra) { $a += @("--override", $extra) }
    & winget @a
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Installiere "Git.Git" "Git"
    $env:Path += ";$env:ProgramFiles\Git\cmd"
}
git config --global core.longpaths true | Out-Null

# Visual Studio (2022 oder 2026) mit C++-Werkzeugen
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
function Finde-VS {
    if (-not (Test-Path $vswhere)) { return $null }
    $v = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property catalog_productLineVersion
    return $v
}
$vsJahr = Finde-VS
if (-not $vsJahr) {
    Installiere "Microsoft.VisualStudio.2022.BuildTools" "Visual Studio Build Tools 2022 (C++)" `
        "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.Windows11SDK.22621 --includeRecommended"
    $vsJahr = Finde-VS
    if (-not $vsJahr) { Fehler "Visual Studio mit C++-Werkzeugen wurde nicht gefunden. Bitte Windows neu starten und das Skript erneut ausführen." }
}
switch ($vsJahr) {
    "2026"  { $Generator = "Visual Studio 18 2026" }
    "2022"  { $Generator = "Visual Studio 17 2022" }
    "2019"  { $Generator = "Visual Studio 16 2019" }
    default { $Generator = "Visual Studio 17 2022" }
}
Write-Host "Compiler: $Generator"

# Perl (für OpenSSL) und pkg-config
if (-not (Get-Command perl -ErrorAction SilentlyContinue)) {
    Installiere "StrawberryPerl.StrawberryPerl" "Strawberry Perl"
    $env:Path += ";C:\Strawberry\perl\bin;C:\Strawberry\c\bin"
}
if (-not (Get-Command pkg-config -ErrorAction SilentlyContinue)) {
    Installiere "bloodrock.pkg-config-lite" "pkg-config"
}

# CMake 3.31 im Repo (neuere Versionen brechen den Build ab), unabhängig von einer installierten Version
$cmakeExe = Join-Path $Werkzeuge "cmake-3.31.6-windows-x86_64\bin\cmake.exe"
if (-not (Test-Path $cmakeExe)) {
    Schritt "Lade CMake 3.31.6"
    New-Item -ItemType Directory -Force -Path $Werkzeuge | Out-Null
    $zip = Join-Path $Werkzeuge "cmake.zip"
    Invoke-WebRequest "https://github.com/Kitware/CMake/releases/download/v3.31.6/cmake-3.31.6-windows-x86_64.zip" -OutFile $zip
    Expand-Archive $zip -DestinationPath $Werkzeuge -Force
    Remove-Item $zip
}
$env:Path = (Split-Path $cmakeExe) + ";" + $env:Path
& $cmakeExe --version | Select-Object -First 1

# neuestes Windows-SDK
$sdkRoot = "${env:ProgramFiles(x86)}\Windows Kits\10\Include"
$sdk = Get-ChildItem $sdkRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^10\.' } | Sort-Object Name -Descending | Select-Object -First 1
if (-not $sdk) { Fehler "Kein Windows-SDK gefunden. Installiere im Visual Studio Installer das Windows 11 SDK." }
$sdkPath = $sdk.FullName.Replace('\', '/')
Write-Host "Windows-SDK: $($sdk.Name)"

# ---------------------------------------------------------------- Quellcode
if (-not $OhneUpdate) {
    Schritt "Hole den neuesten Stand von GitHub"
    git -C $RepoDir checkout -- resources/i18n/de/BambuStudio.mo 2>$null
    git -C $RepoDir pull --ff-only
    if ($LASTEXITCODE -ne 0) { Write-Host "Hinweis: git pull nicht möglich, baue den vorhandenen Stand." -ForegroundColor Yellow }
}
Write-Host ("Stand: " + (git -C $RepoDir log -1 --format="%h %s"))

# ---------------------------------------------------------------- Abhängigkeiten
if ($AbhaengigkeitenNeu -and (Test-Path $DepsDir)) {
    Schritt "Lösche alte Abhängigkeiten"
    Remove-Item -Recurse -Force $DepsDir
}
$marker = Join-Path $DepsDir ".compiler"
if ((Test-Path $DepsDir) -and ((Get-Content $marker -ErrorAction SilentlyContinue) -ne $Generator)) {
    Schritt "Lösche Abhängigkeiten eines anderen oder abgebrochenen Builds"
    Remove-Item -Recurse -Force $DepsDir
}

if (-not (Test-Path $DepsFertig)) {
    Schritt "Baue Abhängigkeiten (einmalig, dauert lange)"
    New-Item -ItemType Directory -Force -Path $DepsOut | Out-Null
    Push-Location $DepsDir
    Ausfuehren $cmakeExe @("..", "-G", $Generator, "-A", "x64", "-DDESTDIR=$($DepsOut.Replace('\','/'))", "-DCMAKE_BUILD_TYPE=Release", "-DDEP_DEBUG=OFF")
    Ausfuehren $cmakeExe @("--build", ".", "--config", "Release", "--target", "ALL_BUILD", "--", "/m")
    Pop-Location
    # Zwischendateien entfernen, nur das Ergebnis behalten
    Get-ChildItem $DepsDir -Force | Where-Object { $_.Name -ne "BambuStudio_dep" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Set-Content -Path $marker -Value $Generator
} else {
    Schritt "Abhängigkeiten sind schon gebaut"
}

# ---------------------------------------------------------------- App
if ($Sauber -and (Test-Path $BuildDir)) {
    Schritt "Lösche alten App-Build"
    Remove-Item -Recurse -Force $BuildDir
}
Schritt "Baue $AppName"
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
Push-Location $BuildDir
Ausfuehren $cmakeExe @("..", "-G", $Generator, "-A", "x64", "-DBBL_RELEASE_TO_PUBLIC=1", "-DBBL_INTERNAL_TESTING=0",
    "-DCMAKE_PREFIX_PATH=$($DepsFertig.Replace('\','/'))", "-DCMAKE_INSTALL_PREFIX=$($InstallDir.Replace('\','/'))",
    "-DCMAKE_BUILD_TYPE=Release", "-DWIN10SDK_PATH=$sdkPath")
Ausfuehren $cmakeExe @("--build", ".", "--target", "install", "--config", "Release", "--", "/m")
Pop-Location

$exe = Get-ChildItem $InstallDir -Filter "bambu-studio.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $exe) { Fehler "bambu-studio.exe wurde nicht gefunden in $InstallDir" }

# ---------------------------------------------------------------- Installieren
Schritt "Installiere nach $Ziel"
Get-Process -Name "bambu-studio" -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$Ziel*" } | Stop-Process -Force
if (Test-Path $Ziel) { Remove-Item -Recurse -Force $Ziel }
New-Item -ItemType Directory -Force -Path $Ziel | Out-Null
Copy-Item -Path (Join-Path $InstallDir "*") -Destination $Ziel -Recurse -Force
$zielExe = Join-Path $Ziel ($exe.FullName.Substring($InstallDir.Length).TrimStart('\'))

# Startmenü- und Desktop-Verknüpfung
$shell = New-Object -ComObject WScript.Shell
foreach ($ordner in @([Environment]::GetFolderPath("Programs"), [Environment]::GetFolderPath("Desktop"))) {
    $lnk = $shell.CreateShortcut((Join-Path $ordner "$AppName.lnk"))
    $lnk.TargetPath       = $zielExe
    $lnk.WorkingDirectory = Split-Path $zielExe
    $lnk.Save()
}

Schritt "Fertig"
Write-Host "App: $zielExe"
Write-Host "Verknüpfungen: Startmenü und Desktop („$AppName“)"
Stop-Transcript | Out-Null
