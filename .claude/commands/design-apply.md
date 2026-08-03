---
description: Setzt Vorschläge aus reports/design-review.md um - über implementer/reviewer/tester. Nutzung z.B. "/design-apply JobDetailView" oder "/design-apply alle Quick Wins"
---

Setze Design-Vorschläge aus `reports/design-review.md` um, ohne mich zwischendurch
um Bestätigung zu fragen - außer bei Vorschlägen der Kategorie "Diskussionswürdig",
die IMMER erst zur Wahl gestellt werden müssen, nie automatisch umgesetzt werden.

Auswahl: $ARGUMENTS

(Falls leer: alle "Quick Win"-Vorschläge aus dem letzten Report-Lauf umsetzen,
"Strukturell" nur nach Rückfrage, "Diskussionswürdig" nie automatisch.)

Ablauf:
1. Lies `reports/design-review.md`. Falls die Datei nicht existiert: sag das
   direkt und schlage vor, zuerst den design-reviewer-Agenten laufen zu lassen.
2. Filtere die Vorschläge anhand von "Auswahl" (Screen-Name, Kategorie, oder "alle").
   "Diskussionswürdig"-Punkte werden dabei immer herausgefiltert und stattdessen
   im Chat als Frage an mich aufgelistet, statt umgesetzt zu werden.
3. Für jeden verbleibenden Vorschlag, EINZELN nacheinander:
   a. Delegiere an **implementer**: genau diesen einen Design-Vorschlag umsetzen,
      unter Beibehaltung des bestehenden Theme-Systems (Farb-/Spacing-Konstanten
      wiederverwenden statt neue Hardcoded-Werte einzuführen, außer der Vorschlag
      betrifft explizit eine Theme-Konstante selbst).
   b. Delegiere an **reviewer**: prüfen, inkl. ob die Umsetzung optisch/strukturell
      dem Vorschlag entspricht und keine anderen Screens durch geteilte Komponenten
      unbeabsichtigt verändert.
   c. Bei kritischem Feedback: zurück zu implementer, max. 2 Korrekturrunden,
      danach überspringen und im Report vermerken.
4. Nach allen Umsetzungen: delegiere an **tester** für einen Gesamt-Testlauf
   der geänderten Screens (falls UI-Tests existieren; sonst Build-Check ausreichend).
5. Ergänze `reports/design-review.md` am Ende um einen Status pro umgesetztem
   Vorschlag (umgesetzt / übersprungen + Grund).

Gib mir am Ende eine kompakte Zusammenfassung: was umgesetzt wurde, was zur
Diskussion offen ist (mit kurzer Nennung der Optionen), was übersprungen wurde.
