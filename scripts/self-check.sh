#!/bin/bash
# self-check.sh
# Wird nach jedem Edit/Write vom implementer-Agent automatisch ausgeführt.
# Exit-Code 2 => Claude Code gibt die Fehlermeldung an den Agent zurück,
# der Agent muss sich selbst korrigieren, bevor er weitermacht.
#
# Passe die Befehle unten an dein Projekt an (npm test, pytest, go test, ...).
# Da euer Stack gemischt ist, versucht das Skript gängige Runner automatisch zu erkennen.

set -uo pipefail
INPUT=$(cat)

mkdir -p reports
LOG="reports/self-check.log"
echo "[$(date -Iseconds)] self-check gestartet" >> "$LOG"

run_and_check() {
  local label="$1"
  shift
  echo "--- $label ---"
  if ! "$@" 2>&1 | tee -a "$LOG"; then
    echo "FEHLER in: $label" | tee -a "$LOG" >&2
    exit 2
  fi
}

# Node/JS-Projekt
if [ -f "package.json" ]; then
  if grep -q '"lint"' package.json; then run_and_check "npm lint" npm run lint --silent; fi
  if grep -q '"test"' package.json; then run_and_check "npm test" npm test --silent; fi
fi

# Python-Projekt
if [ -f "pyproject.toml" ] || [ -f "requirements.txt" ]; then
  if command -v ruff >/dev/null; then run_and_check "ruff" ruff check .; fi
  if command -v pytest >/dev/null; then run_and_check "pytest" pytest -q; fi
fi

# Go-Projekt
if [ -f "go.mod" ]; then
  run_and_check "go vet" go vet ./...
  run_and_check "go test" go test ./...
fi

exit 0
