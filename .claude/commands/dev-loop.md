---
description: Führt den kompletten Loop automatisch aus - implementer baut/fixt, reviewer prüft, tester testet - iteriert bis alles grün ist, und protokolliert alles in reports/dev-loop-report.md
---

Führe für die folgende Aufgabe den vollständigen, automatisierten Entwicklungs-Loop aus,
OHNE mich zwischendurch um Bestätigung zu fragen. Nur bei echten Blockern (z. B. fehlende
Zugangsdaten, unklare fachliche Anforderung) unterbrichst du und fragst nach.

Aufgabe: $ARGUMENTS

Ablauf:
1. Lege (falls nicht vorhanden) `reports/` an und erstelle
   `reports/dev-loop-report.md` mit Zeitstempel-Überschrift für diesen Lauf.
2. Delegiere an den **implementer**-Agenten: Aufgabe umsetzen.
3. Delegiere an den **reviewer**-Agenten: Änderungen prüfen.
   - Ergebnis (Kritisch/Warnung/Vorschlag) an `reports/dev-loop-report.md` anhängen.
4. Wenn der Reviewer kritische Punkte findet: delegiere erneut an **implementer**,
   um genau diese zu beheben. Zurück zu Schritt 3. Maximal 3 Review-Runden,
   danach im Report vermerken, dass manuelle Prüfung nötig ist, und stoppen.
5. Delegiere an den **tester**-Agenten: Tests ausführen/ergänzen.
   - Testergebnis (bestanden/fehlgeschlagen, Anzahl, Details zu Fehlschlägen)
     an `reports/dev-loop-report.md` anhängen.
6. Wenn Tests fehlschlagen: delegiere erneut an **implementer** zur Behebung,
   danach zurück zu Schritt 5. Maximal 3 Testrunden, danach im Report vermerken
   und stoppen.
7. Abschluss: schreibe eine kurze Zusammenfassung ans Ende des Reports
   (Status: erfolgreich / manuelle Prüfung nötig, Anzahl Runden, offene Punkte).

Gib mir am Ende nur eine kompakte Zusammenfassung im Chat, die Details stehen im Report.
