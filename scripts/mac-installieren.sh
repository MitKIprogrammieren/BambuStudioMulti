#!/bin/bash
# bambustudiomulti – baut „Bambu Studio Multi“ auf dem Mac und installiert sie nach ~/Applications
#
# Aufruf aus dem Repo-Ordner:
#   ./scripts/mac-installieren.sh             # holt den neuesten Stand, baut, installiert
#   ./scripts/mac-installieren.sh --abhaengigkeiten-neu   # Abhängigkeiten komplett neu bauen
#   ./scripts/mac-installieren.sh --ohne-update           # ohne git pull
#   ./scripts/mac-installieren.sh --sauber                # App-Build-Ordner vorher löschen
#
# Erster Lauf: ca. 1–2 Stunden (Abhängigkeiten). Danach: ca. 10–30 Minuten.

set -e
set -o pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="$(uname -m)"                       # arm64 auf Apple-Silicon
APP_NAME="Bambu Studio Multi.app"
ALTE_NAMEN=("BambuStudio Multi.app" "Bambu Lab Studio Multi.app" "Bambu Studio MultiBuildPlate.app")   # frühere Namen, werden entfernt
ZIEL="$HOME/Applications/$APP_NAME"
VENV="$REPO_DIR/.build-werkzeuge"
DEPS_FERTIG="$REPO_DIR/deps/build/$ARCH/BambuStudio_deps/usr/local"
LOG="$REPO_DIR/build-$(date +%Y%m%d-%H%M).log"
# Mindest-macOS 14.0: Das offizielle 10.15 lehnt die libc++ neuer SDKs ab,
# ab 15.0 fehlen Funktionen, die wxWidgets noch braucht (CGDisplayCreateImage).
MACOS_ZIEL="14.0"

DEPS_NEU=0; UPDATE=1; SAUBER=0
for arg in "$@"; do
  case "$arg" in
    --abhaengigkeiten-neu) DEPS_NEU=1 ;;
    --ohne-update)         UPDATE=0 ;;
    --sauber)              SAUBER=1 ;;
    -h|--hilfe)            sed -n 2,10p "$0"; exit 0 ;;
    *) echo "Unbekannte Option: $arg"; exit 1 ;;
  esac
done

schritt() { printf "\n\033[1;32m==> %s\033[0m\n" "$1"; }
fehler()  { printf "\n\033[1;31mFehler: %s\033[0m\n" "$1"; exit 1; }

exec > >(tee -a "$LOG") 2>&1
echo "Protokoll: $LOG"

# ---------------------------------------------------------------- Voraussetzungen
schritt "Prüfe Voraussetzungen"
[ "$(uname)" = "Darwin" ] || fehler "Dieses Skript läuft nur auf macOS."
xcode-select -p >/dev/null 2>&1 || {
  echo "Die Xcode-Kommandozeilenwerkzeuge fehlen. Das Installationsfenster öffnet sich jetzt."
  xcode-select --install || true
  fehler "Bitte nach der Installation das Skript erneut starten."
}
# Homebrew ist oft installiert, aber nicht im PATH (z. B. in einem neuen Terminal)
if ! command -v brew >/dev/null 2>&1; then
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$b" ] && eval "$("$b" shellenv)" && break
  done
fi
command -v brew >/dev/null 2>&1 || fehler "Homebrew fehlt. Installieren mit:
  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"
Danach:
  echo 'eval \"\$(/opt/homebrew/bin/brew shellenv)\"' >> ~/.zprofile
  eval \"\$(/opt/homebrew/bin/brew shellenv)\"
und dieses Skript erneut starten."

FREI_GB=$(df -g "$REPO_DIR" | awk 'NR==2 {print $4}')
[ "$FREI_GB" -ge 25 ] || fehler "Zu wenig Speicherplatz: ${FREI_GB} GB frei, nötig sind etwa 25 GB."

schritt "Installiere Werkzeuge über Homebrew (falls nötig)"
for pkg in git gettext automake autoconf libtool texinfo nasm yasm pkg-config; do
  brew list --formula "$pkg" >/dev/null 2>&1 || brew install "$pkg"
done

# Bambu Studio braucht CMake 3.31 (neuere Versionen brechen den Build ab).
# Statt die Homebrew-Version umzustellen, kommt CMake in einen eigenen Ordner im Repo.
schritt "Richte CMake 3.31 und Ninja im Repo ein"
if [ ! -x "$VENV/bin/cmake" ]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --upgrade pip
  "$VENV/bin/pip" install --quiet "cmake==3.31.6" ninja
fi
export PATH="$VENV/bin:$(brew --prefix gettext)/bin:$PATH"
cmake --version | head -1

# ---------------------------------------------------------------- Quellcode
if [ "$UPDATE" = "1" ]; then
  schritt "Hole den neuesten Stand von GitHub"
  # die vom Skript selbst erzeugte Übersetzung darf das Update nicht blockieren
  git -C "$REPO_DIR" checkout -- resources/i18n/de/BambuStudio.mo 2>/dev/null || true
  git -C "$REPO_DIR" pull --ff-only || echo "Hinweis: git pull nicht möglich, baue den vorhandenen Stand."
fi
echo "Stand: $(git -C "$REPO_DIR" log -1 --format='%h %s')"

# Deutsche Texte aus der .po-Datei neu übersetzen (der normale Build macht das nicht)
if command -v msgfmt >/dev/null 2>&1 && [ -f "$REPO_DIR/bbl/i18n/de/BambuStudio_de.po" ]; then
  msgfmt -o "$REPO_DIR/resources/i18n/de/BambuStudio.mo" "$REPO_DIR/bbl/i18n/de/BambuStudio_de.po" \
    && echo "Deutsche Übersetzung aktualisiert."
fi

# ---------------------------------------------------------------- Abhängigkeiten
cd "$REPO_DIR"
if [ "$DEPS_NEU" = "1" ]; then
  schritt "Lösche alte Abhängigkeiten"
  rm -rf "$REPO_DIR/deps/build/$ARCH"
fi

# Abhängigkeiten, die für ein anderes Mindest-macOS gebaut oder abgebrochen wurden, neu bauen
ZIEL_MARKER="$REPO_DIR/deps/build/$ARCH/.macos-ziel"
if [ -d "$REPO_DIR/deps/build/$ARCH" ] && [ "$(cat "$ZIEL_MARKER" 2>/dev/null)" != "$MACOS_ZIEL" ]; then
  schritt "Lösche Abhängigkeiten eines anderen oder abgebrochenen Builds"
  rm -rf "$REPO_DIR/deps/build/$ARCH"
fi

if [ ! -d "$DEPS_FERTIG" ]; then
  schritt "Baue Abhängigkeiten (einmalig, dauert lange)"
  # Eine installierte zstd-Bibliothek von Homebrew stört den Abhängigkeits-Build.
  ZSTD_WIEDER=0
  if brew list --formula zstd >/dev/null 2>&1; then
    brew unlink zstd >/dev/null && ZSTD_WIEDER=1
  fi
  trap '[ "$ZSTD_WIEDER" = "1" ] && brew link zstd >/dev/null' EXIT
  echo "Mindest-macOS: $MACOS_ZIEL"
  ./BuildMac.sh -d -x -a "$ARCH" -t "$MACOS_ZIEL"
  [ "$ZSTD_WIEDER" = "1" ] && brew link zstd >/dev/null; trap - EXIT
  # Zwischendateien entfernen, nur das Ergebnis behalten (spart viele GB)
  (cd "$REPO_DIR/deps/build/$ARCH" && find . -mindepth 1 -maxdepth 1 ! -name 'BambuStudio_deps' -exec rm -rf {} +)
  echo "$MACOS_ZIEL" > "$ZIEL_MARKER"
else
  schritt "Abhängigkeiten sind schon gebaut"
fi

# ---------------------------------------------------------------- App
if [ "$SAUBER" = "1" ]; then
  schritt "Lösche alten App-Build"
  rm -rf "$REPO_DIR/build/$ARCH"
fi

schritt "Baue Bambu Studio Multi"
./BuildMac.sh -s -x -a "$ARCH" -t "$MACOS_ZIEL"

GEBAUT="$REPO_DIR/build/$ARCH/BambuStudio/BambuStudio.app"
[ -d "$GEBAUT" ] || fehler "Die App wurde nicht gefunden: $GEBAUT"

# ---------------------------------------------------------------- Installieren
schritt "Installiere nach $ZIEL"
mkdir -p "$HOME/Applications"
if pgrep -f "$APP_NAME/Contents/MacOS" >/dev/null; then
  echo "Bambu Studio Multi läuft noch und wird beendet."
  pkill -f "$APP_NAME/Contents/MacOS" || true
  sleep 2
fi
rm -rf "$ZIEL"
for alt in "${ALTE_NAMEN[@]}"; do rm -rf "$HOME/Applications/$alt"; done
cp -R "$GEBAUT" "$ZIEL"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Bambu Studio Multi" "$ZIEL/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Bambu Studio Multi" "$ZIEL/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Bambu Studio Multi" "$ZIEL/Contents/Info.plist" 2>/dev/null || true
xattr -cr "$ZIEL"
codesign --force --deep --sign - "$ZIEL" >/dev/null 2>&1 || echo "Hinweis: Ad-hoc-Signatur fehlgeschlagen, die App startet trotzdem meist."

schritt "Fertig"
echo "App: $ZIEL"
echo "Starten mit: open \"$ZIEL\""
