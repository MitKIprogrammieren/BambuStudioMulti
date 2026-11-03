#!/bin/bash
# Doppelklick im Finder: holt den neuesten Stand von BambuStudioMulti, baut die App und installiert sie.
cd "$(dirname "$0")" || exit 1
./scripts/mac-installieren.sh "$@"
status=$?
echo
if [ $status -eq 0 ]; then
  echo "Fertig. Bambu Studio Multi wird gestartet."
  open "$HOME/Applications/BambuStudio Multi.app"
else
  echo "Das Update ist fehlgeschlagen (Code $status). Das Protokoll liegt als build-*.log im Ordner $(pwd)."
fi
echo
read -n 1 -s -r -p "Taste drücken zum Schließen …"
echo
