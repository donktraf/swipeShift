# Setup

1. Kompletten Ordner-Inhalt (`.claude/`, `scripts/`) in dein bestehendes Projekt kopieren —
   also dort, wo du `claude` in dem Projekt startest (Projekt-Root).
2. `chmod +x scripts/self-check.sh` (falls die Ausführbarkeit beim Kopieren verloren geht).
3. In `scripts/self-check.sh` prüfen/anpassen, ob dein Lint-/Test-Befehl erkannt wird
   (Node/Python/Go werden automatisch erkannt — bei anderem Stack Zeilen ergänzen).
4. Claude Code im Projekt starten.

## Automatisierten Loop starten

Statt Agents manuell zu verketten, einfach:

```
/dev-loop Baue Feature X: ...
```

oder für ein bestehendes Projekt / einen bekannten Bug:

```
/dev-loop Refactoriere Modul Y, sodass ...
```

Das läuft dann **vollautomatisch** ab, ohne dass du zwischendurch bestätigen musst:

```
implementer baut/fixt
   → reviewer prüft (read-only)
      → bei kritischen Punkten: zurück zu implementer (max. 3 Runden)
   → tester testet / ergänzt Tests
      → bei Fehlschlägen: zurück zu implementer (max. 3 Runden)
   → Zusammenfassung
```

Nach jedem Edit/Write des implementer-Agents läuft zusätzlich automatisch der
`self-check.sh`-Hook (Lint/Tests) — Fehler gehen sofort zurück an den Agent,
noch bevor Reviewer/Tester überhaupt dran sind. Das ist der eigentliche
Selbstkorrektur-Loop "im Kleinen"; `/dev-loop` ist der Loop "im Großen"
(ganze Pipeline inkl. Review).

## Wo die Ergebnisse landen

Alles wird in Dateien protokolliert, nichts geht nur durch den Chat verloren:

- **`reports/dev-loop-report.md`** — ein Eintrag pro `/dev-loop`-Lauf mit
  Zeitstempel: Review-Ergebnis (Kritisch/Warnung/Vorschlag), Test-Ergebnis
  (bestanden/fehlgeschlagen, Details) und Abschluss-Status.
- **`reports/self-check.log`** — Rohes Lint-/Test-Output aus jedem automatischen
  Zwischencheck nach Edit/Write.

So kannst du über mehrere Apps/Projekte hinweg `/dev-loop` laufen lassen und
hinterher einfach die Report-Dateien durchgehen, statt den Chatverlauf zu wälzen.

## Agents im Überblick

- **implementer** — baut Features, passt Code an, behebt Findings aus
  Review/Tests (kein separater "Fixer"-Agent nötig, siehe Begründung unten).
- **reviewer** — read-only, unabhängige Prüfung, damit er nicht dieselben
  blinden Flecken hat wie der Autor des Codes.
- **tester** — führt/schreibt Tests, ändert selbst keinen Produktionscode.
- **debugger** *(optional, außerhalb des `/dev-loop`)* — für isolierte
  Fehlerfälle ohne bestehenden Implementierungskontext, z. B. gemeldete
  Produktionsbugs. Direkt aufrufen mit: `Nutze den debugger-Agent für: ...`

## Auf mehreren Projekten nutzen

Da alles projektlokal in `.claude/` liegt, reicht es, den Ordner in jedes
Projekt zu kopieren, das du automatisiert durchlaufen lassen willst. Willst
du das Setup projektübergreifend verfügbar haben, verschiebe die Agent-Dateien
stattdessen nach `~/.claude/agents/` — dann brauchst du nur noch
`scripts/self-check.sh` und `.claude/commands/dev-loop.md` pro Projekt.
