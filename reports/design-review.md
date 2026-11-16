# SwipeShift — Design/UX Review

## Lauf: 2026-07-28 — Allgemeine Durchsicht (Worker + Employer Hauptflows)

**Scope:** Kein spezifischer Screen vom Nutzer vorgegeben → Hauptflows geprüft:
Worker Dashboard/Home, Category Discovery, Job List, Job Swipe, Job Detail, Apply Flow,
Radar (MapKit), Messages/Chat, Worker Profile + Sub-Screens, Employer Dashboard,
Employer Home/Profile-Tab, Post-a-Job (Auszug), All Posted Jobs (Auszug).

**Methodik:** Code gelesen (siehe Dateiliste je Finding), gegen bestehendes Theme
(`utils/Theme.swift`) und CLAUDE.md-Vorgaben abgeglichen, punktuell Best-Practice-
Recherche zu konkret aufgefallenen Problemen (iOS HIG Touch-Targets, SwiftUI
Nested-Tappable-Anti-Pattern, Swipe-Interface-Haptics). Kein Code geändert.

**Legende Kategorie:** 🟢 Quick Win · 🔵 Strukturell · 🟡 Diskussionswürdig

---

### Zusammenfassung nach Kategorie

- 🟢 Quick Win: 8
- 🔵 Strukturell: 4
- 🟡 Diskussionswürdig: 4

---

## 1. Irreführende "Apply"/"Bookmark"-Buttons auf `DashboardJobCard` (Bug-artiges UX-Problem)

**Datei/Screen:** `swipeshift/Features/Worker/Dashboard/JobSectionView.swift` (`DashboardJobCard`),
verwendet in `WorkerHomeTabView` (alle 4 Job-Sektionen) **und** in
`swipeshift/Features/Worker/Jobs/JobListView.swift` (komplette Job-Liste).

**Was stört:** `DashboardJobCard` zeigt einen Bookmark-`Image` und einen optisch wie
ein Button aussehenden "Apply"-Pill (`Text` mit farbigem Hintergrund). Beide sind aber
**keine eigenständigen `Button`-Views**, sondern nur gestylter Inhalt innerhalb des
Labels eines `NavigationLink` mit `.buttonStyle(.plain)`:

```swift
NavigationLink { JobDetailView(job: job) } label: { DashboardJobCard(job: job) }
    .buttonStyle(.plain)
```

Tippt ein Nutzer gezielt auf "Apply", passiert nichts anderes als beim Tippen auf die
restliche Karte — es öffnet sich nur der Detail-Screen, es wird **nicht** beworben,
und der Bookmark wird **nicht** gespeichert. Das ist die exakt gleiche Karte an zwei
zentralen Stellen (Dashboard-Sektionen + komplette Job-Liste), betrifft also einen
Großteil der Job-Discovery-Journey.

**Warum das ein Problem ist:** Klassischer "false affordance"-Fehler — ein Element
sieht interaktiv aus (Farbe, Padding, Pill-Form wie der echte "Apply Now"-Button in
`JobDetailView`), verhält sich aber nicht so. Das untergräbt Nutzervertrauen und kann
dazu führen, dass Nutzer denken, sie hätten sich beworben, obwohl das nicht der Fall
ist. In SwiftUI ist das ein bekanntes Anti-Pattern: verschachtelte "Buttons" innerhalb
eines größeren Tap-Targets (hier NavigationLink) werden vom äußeren Gesture-Handling
verschluckt.

**Recherche/Beleg:** SwiftUI-Community-Konsens (Hacking with Swift, Apple Developer
Forums) empfiehlt für sichere verschachtelte Interaktion entweder `.buttonStyle(.borderless)`
auf dem inneren Button + Entfernen des äußeren impliziten Tap-Verhaltens, oder — sauberer —
das Card-Tap-Ziel und die Mini-Actions strikt zu trennen (z. B. via `.contentShape` +
separatem `Button` statt Text/Image).

**Konkreter SwiftUI-Vorschlag:**
```swift
// Karte selbst bleibt NavigationLink (öffnet Detail)
// Bookmark und Apply werden zu ECHTEN Buttons mit .buttonStyle(.plain),
// die per .highPriorityGesture oder eigenem contentShape VOR dem NavigationLink greifen:

Button {
    Task { try? await APIClient.shared.saveJob(jobId: job.id) }
} label: {
    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
}
.buttonStyle(.plain)
.contentShape(Rectangle())
```
Am einfachsten: "Apply"-Pill ganz aus der Card entfernen (es gibt bereits einen
vollwertigen Apply-Flow in `JobDetailView`) und nur den Bookmark als echten Button
belassen — reduziert gleichzeitig visuelles Rauschen auf einer Übersichtskarte.

**Kategorie:** 🟢 Quick Win (Bookmark zu echtem Button machen) kombiniert mit
🔵 Strukturell falls direktes 1-Tap-Apply aus der Liste tatsächlich gewünscht ist
(bräuchte eigenen Apply-Flow-Trigger statt Navigation).

---

## 2. Swipe-Tab: gefilterte Karte stimmt nicht mit angezeigtem Zähler überein

**Datei/Screen:** `swipeshift/Features/Worker/Jobs/JobSwipeView.swift`

**Was stört:** Der Header zeigt `filteredSwipeJobs.count` ("X jobs available") und die
zwei Hintergrund-Karten nutzen `filteredSwipeJobs[1]`/`[2]`. Die **oberste, ziehbare**
Karte greift jedoch direkt auf `jobStore.swipeJobs.first` zu (nicht `filteredSwipeJobs.first`):

```swift
if let job = jobStore.swipeJobs.first {
    SwipeJobCard(job: job, ...)
```

Wenn ein Kategorie-Filter aktiv ist, kann die tatsächlich angezeigte/ziehbare Top-Karte
ein Job sein, der nicht zur Filterkategorie passt — während Zähler und die zwei Karten
darunter den gefilterten Stand zeigen. Für den Nutzer wirkt das wie ein Bug: Filter
"Hospitality" aktiv, aber die vorderste Karte zeigt einen Logistik-Job.

**Warum das wichtig ist:** Bei Swipe-Interfaces (Tinder/Bumble-Pattern) ist Vertrauen in
die Konsistenz des Stapels entscheidend — Nutzer verlassen sich darauf, dass jede
sichtbare Karte der aktuellen Filterlogik entspricht, sonst wird die Kernmechanik
(schnelle Entscheidung) unterlaufen.

**Konkreter Vorschlag:** `jobStore.swipeJobs.first` → `filteredSwipeJobs.first` (also
`topJob`) in der `cardArea`-Methode verwenden, konsistent mit `handleDragEnd`/`animateSwipe`,
die bereits `topJob` nutzen.

**Kategorie:** 🟢 Quick Win (einzeilige Änderung, aber hoher Vertrauens-Impact).

---

## 3. Apply-Flow: Fehler-Buttons ("View Other Shifts", "View My Calendar") navigieren nirgendwohin

**Datei/Screen:** `swipeshift/Features/Worker/Jobs/ApplyFlowView.swift` (`ApplyResultView`)

**Was stört:** Für jeden Fehlerzustand gibt es laut CLAUDE.md-Wireframe einen eigenen
Action-Button (z. B. "View Other Shifts", "View My Calendar", "View Other Jobs"). Im
Code rufen **Primär- und Sekundär-Button identisch** nur `onDone()` auf:

```swift
Button(config.primaryActionLabel) { onDone() }   // z.B. "View My Calendar"
...
Button(secondaryLabel) { onDone() }              // z.B. "Go Back Anyway"
```

`onDone()` schließt lediglich das Sheet (`dismiss()`), unabhängig vom Label. Ein Nutzer,
der bei "Scheduling Conflict Detected" auf "View My Calendar" tippt, erwartet den
Kalender-Screen zu sehen — bekommt aber nur die Job-Detail-Ansicht zurück, die er vorher
schon hatte.

**Warum das ein Problem ist:** Das ist eine Diskrepanz zwischen Beschriftung und
tatsächlichem Verhalten (Nielsen-Heuristik "Match between system and the real world" /
Konsistenz der Handlungsversprechen). Gerade in Fehlerzuständen ist es wichtig, dass
der Ausweg, den die App anbietet, auch wirklich funktioniert — sonst wirkt die App
kaputt, obwohl "nur" die Navigation fehlt.

**Konkreter Vorschlag:** `ApplyResultView` um Callback-Parameter erweitern (z. B.
`onPrimaryAction: () -> Void` statt generischem `onDone`), der je nach `result`
tatsächlich navigiert:
```swift
case .schedulingConflict:
    primaryAction = { /* Navigation zu WorkerCalendarView */ }
case .shiftAlreadyTaken, .shiftUnavailable:
    primaryAction = { dismiss(); /* zurück zu JobListView/JobSwipeView */ }
case .submitted:
    primaryAction = onSuccess
```
Falls die Navigation kurzfristig zu aufwändig ist: Labels anpassen an das, was der
Button tatsächlich tut (z. B. "OK" / "Close"), um keine falschen Erwartungen zu wecken.

**Kategorie:** 🔵 Strukturell (braucht echtes Routing zu Calendar/JobList aus einem
modalen Sheet heraus).

---

## 4. Hardcodierte Badge-Zahlen in Navigationslisten (Worker + Employer)

**Dateien/Screens:**
- `swipeshift/Features/Worker/Profile/WorkerProfileView.swift` — `ProfileNavItem(..., label: "Job Applications", badge: "3")` und `badge: "5"` bei "Saved"
- `swipeshift/Features/Employer/EmployerDashboardView.swift` — `NavRow(..., label: "Assign Workers", badge: "2")` und `label: "Leave Reviews", badge: "3")`

**Was stört:** Diese Badges sind **statische String-Literale**, nicht an echte Daten
gebunden — im Gegensatz zu den direkt daneben liegenden Badges, die bereits korrekt aus
Store/DTO gespeist werden (`activeJobs > 0 ? "\(activeJobs)" : nil`,
`newApplicants > 0 ? ...`). Nach dem im PROGRESS.md dokumentierten Umbau "Mock-Daten
entfernt — echte DB-Anbindung" wirken diese verbliebenen Fake-Zahlen wie ein Rückstand.

**Warum das wichtig ist:** Zeigt die App "3 neue Bewerbungen", obwohl es z. B. 0 oder 7
sind, verliert der Nutzer Vertrauen in alle Zähler der App — auch in die korrekten. Bei
einem Job-Marktplatz mit Zeitdruck (befristete Schichten) sind falsche Zahlen besonders
schädlich, da sie Handlungsdringlichkeit vortäuschen oder verschleiern.

**Konkreter Vorschlag:** Entweder an bestehende Endpunkte anbinden (z. B. `AssignWorkers`-
Badge aus `fetchAssignedWorkers()`-Count, "Leave Reviews" aus Pending-Reviews-Count,
sofern Backend das liefert) oder — falls kurzfristig nicht möglich — `badge: nil` setzen,
bis echte Daten verfügbar sind. Lieber kein Badge als ein falsches.

**Kategorie:** 🟢 Quick Win.

---

## 5. "Click to view all jobs" (3 Punkte + Text) vs. Ellipsis-Icon im Header — zwei
unterschiedliche "View All"-Affordanzen im selben Screen

**Datei/Screen:** `swipeshift/Features/Worker/Dashboard/JobSectionView.swift`,
sichtbar in `WorkerHomeTabView`

**Was stört:** Jede Job-Sektion hat **zwei** Wege zu "alle Jobs anzeigen": den
`ellipsis`-Icon-Button oben rechts im Section-Header und den Text-Link "Click to view
all jobs" mit drei kleinen State-Dots darunter. Beide lösen denselben `onViewAll`-Callback
aus. Das Ellipsis-Icon (•••) signalisiert in iOS konventionell ein Kontextmenü ("mehr
Optionen"), nicht "zur Liste springen" — das kann kurz irritieren, bevor der Nutzer
merkt, dass es einfach navigiert.

**Warum das auffällt:** Vergleichbare Job-/Feed-Apps (Apple Music "See All", Indeed,
LinkedIn Jobs) nutzen für "alle anzeigen" konsistent ein Text-Label ("See All") oder
einen Chevron, nicht ein Ellipsis-Symbol — weil Ellipsis in iOS für Menüs reserviert ist
(z. B. `.contextMenu`-Trigger, Share-Sheets).

**Konkreter Vorschlag:** Ellipsis-Button im Section-Header entfernen, stattdessen ein
kompaktes "See All"-Textlabel mit Chevron rechts im Header platzieren (wie in vielen
iOS-Feeds üblich), das untere "Click to view all jobs" (mit den 3 Punkten, laut
Wireframe explizit gefordert) als alleinigen Call-to-Action beibehalten:
```swift
Button(action: onViewAll) {
    HStack(spacing: 2) {
        Text("See All").font(.system(size: 13, weight: .semibold))
        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
    }
    .foregroundColor(SS.primary)
}
```

**Kategorie:** 🟡 Diskussionswürdig (Wireframe verlangt explizit "Click to view all
jobs" — Frage ist nur, ob der zusätzliche Ellipsis-Button im Header sinnvoll/nötig ist
oder ersetzt werden soll).

---

## 6. Fehlende Haptics bei Swipe-Threshold und Apply/Skip-Buttons

**Datei/Screen:** `swipeshift/Features/Worker/Jobs/JobSwipeView.swift`

**Was stört:** Weder beim Überschreiten des Swipe-Threshold (110pt, `handleDragEnd`)
noch beim Tippen der Action-Buttons (X / Bookmark / ✓) gibt es haptisches Feedback
(`UIImpactFeedbackGenerator` bzw. iOS 17 `.sensoryFeedback`-Modifier).

**Warum das auffällt:** Swipe-basierte Interfaces (Tinder, Bumble) gelten als UX-
Referenz genau wegen der taktilen Befriedigung der Entscheidung — Haptik am
Decision-Point verstärkt das Gefühl "meine Aktion wurde registriert" und ist 2025/2026
Standard-Praxis für Mikrointeraktionen in Swipe-/Match-Interfaces.

**Konkreter Vorschlag (iOS 17, kein UIKit nötig):**
```swift
.sensoryFeedback(.impact(weight: .medium), trigger: dragFraction > 0.6)
// oder gezielt in animateSwipe():
UIImpactFeedbackGenerator(style: .medium).impactOccurred()
```
Leichtes `.light`-Feedback bei Threshold-Überschreitung während des Drags, `.medium`
beim endgültigen Apply/Skip.

**Kategorie:** 🟢 Quick Win.

---

## 7. Job-Detail: Bookmark-Status ist rein lokal, geht beim Verlassen verloren

**Datei/Screen:** `swipeshift/Features/Worker/Jobs/JobDetailView.swift`

**Was stört:** `@State private var isBookmarked = false` wird nie aus dem Backend
geladen (anders als z. B. in `CompanyProfileView`, wo `isSaved` explizit via
`.task` geladen wird — siehe PROGRESS.md "Saved Companies"-Eintrag). Tippt ein Nutzer
den Bookmark, ändert sich nur lokaler State — es wird auch kein `saveJob()`-Call
ausgelöst (anders als im Swipe-Tab, wo der Bookmark-Button `APIClient.shared.saveJob`
aufruft). Verlässt der Nutzer den Screen und kehrt zurück, ist der Bookmark wieder leer,
selbst wenn der Job tatsächlich gespeichert wurde/ist.

**Warum das wichtig ist:** Inkonsistenz zum eigenen Pattern — an anderer Stelle in der
App (Swipe-Tab, Company-Profil) ist Save bereits korrekt ans Backend angebunden. Aus
Nutzersicht ist das ein "kaputter" Speichern-Button auf dem wichtigsten Conversion-Screen
der App (Job Detail → Apply).

**Konkreter Vorschlag:**
```swift
.task {
    isBookmarked = (try? await APIClient.shared.isJobSaved(jobId: job.id)) ?? false
}
Button {
    Task { try? await APIClient.shared.saveJob(jobId: job.id) } // bzw. unsave-Endpoint
    withAnimation { isBookmarked.toggle() }
}
```
(Falls kein `GET`-Endpoint für Einzelstatus existiert: zumindest den `POST /jobs/:id/save`-
Call ergänzen, analog zum Swipe-Tab — aktuell fehlt er in JobDetailView komplett.)

**Kategorie:** 🟢 Quick Win (Backend-Endpoint existiert laut PROGRESS.md bereits).

---

## 8. Card-Radius-Inkonsistenz: `Theme.swift` definiert 34pt, tatsächlich verwendete
Job-/List-Karten nutzen überall 12–16pt

**Datei/Screen:** `swipeshift/utils/Theme.swift` (`SS.cardRadius = 34`) vs. praktisch
jede Job-Karte in `JobSectionView.swift`, `JobListView.swift`, `RadarView.swift`,
`JobDetailView.swift` (durchgängig `cornerRadius: 12`–`16`, `DashboardJobCard`
z. B. 14).

**Was stört:** CLAUDE.md schreibt als Kartenkonvention "RoundedRectangle(cornerRadius: 14)"
fest — das wird in der Praxis fast überall korrekt eingehalten. `SS.cardRadius` (34pt)
wird aber nur von `SSCard` (Auth-Screens) verwendet und weicht stark davon ab. Das ist
kein Bug, aber ein Zeichen, dass die Theme-Konstante `cardRadius` nicht (mehr) den
"Wahrheitswert" für Karten-Radius im Rest der App repräsentiert — neue Entwickler
(auch Claude Code) könnten `SS.cardRadius` fälschlich für Job-/Listenkarten verwenden
und damit optische Brüche einführen.

**Warum das wichtig ist:** Konsistente Wiederverwendung von Design-Tokens ist die
Grundlage jedes Design-Systems (siehe auch iOS HIG "Consistency"-Prinzip). Eine Theme-
Konstante, die vom faktischen Pattern abweicht, untergräbt genau diesen Zweck.

**Konkreter Vorschlag:** Zwei Radius-Tokens klar benennen und dokumentieren:
```swift
static let cardRadius: CGFloat = 14        // Standard-Job-/Listenkarten (matches CLAUDE.md)
static let authCardRadius: CGFloat = 34    // Große Auth-/Onboarding-Karten (SSCard)
```
Alle bestehenden Hardcodes (14, 16, 12) könnten schrittweise durch `SS.cardRadius`
ersetzt werden, um zukünftige Drifts zu verhindern.

**Kategorie:** 🟢 Quick Win (Theme-Datei) + optional 🔵 Strukturell falls flächendeckend
auf das Token umgestellt werden soll.

---

## 9. Sticky Apply Bar: kein Safe-Area-/Keyboard-Test für kleinere Geräte, Text
"X spots available" kann bei fehlenden Daten leer wirken

**Datei/Screen:** `swipeshift/Features/Worker/Jobs/JobDetailView.swift` (`stickyApplyBar`)

**Was stört:** `job.openSpots` ist optional; wenn `nil`, wird die komplette Zeile
("X spot available") ausgeblendet, aber der `payText` bleibt stehen — die Bar wirkt
dann einzeilig und die zweite Spalte im `quickInfoRow` ("Spots", oben im Screen) zeigt
parallel `"\(job.openSpots ?? 1)"`, also fälschlich **"1"** statt eines Platzhalters wie
"–". Das ist eine kleine Dateninkonsistenz zwischen zwei Stellen desselben Screens
(oben: Fallback "1", unten: Zeile komplett ausgeblendet).

**Konkreter Vorschlag:** Einheitlichen Fallback wählen, z. B. immer `"–"` statt `1`,
und die gleiche Optional-Handling-Logik oben (QuickInfoCell) und unten (stickyApplyBar)
verwenden.

**Kategorie:** 🟢 Quick Win.

---

## 10. RadarView: Radius-Filter-Button und Legende konkurrieren um denselben
Bildschirmbereich bei kleinen Displays (iPhone SE/mini)

**Datei/Screen:** `swipeshift/Features/Worker/Jobs/RadarView.swift`

**Was stört:** Die Farblegende (`LegendDot`s) liegt als `.overlay(alignment: .bottomLeading)`
direkt auf der Karte, unmittelbar über der Zähler-/Radius-Filter-Zeile. Bei
`mapHeightFraction = 0.25` (nach dem Scrollen) und kleineren Displays kann die
Legende visuell mit der darunterliegenden "Showing X jobs"-Zeile kollidieren bzw. wirkt
auf 25%-Kartenhöhe (deutlich weniger als 45%) proportional größer/aufdringlicher, da sie
nicht mitschrumpft.

**Warum das relevant ist:** MapKit-Overlays sollten bei dynamisch schrumpfenden Karten
(hier bewusst als Feature implementiert: 45%→25%) mitskalieren oder ab einer Schwelle
ausgeblendet werden, sonst wirkt die Karte im eingeklappten Zustand überladen — ähnlich
wie bei Uber, wo Kartenoverlays beim Verkleinern reduziert/versteckt werden.

**Konkreter Vorschlag:**
```swift
.overlay(alignment: .bottomLeading) {
    if mapHeightFraction > 0.35 {   // nur bei ausgeklappter Karte zeigen
        legendView
    }
}
```

**Kategorie:** 🟡 Diskussionswürdig (abhängig von Zielgeräten/Design-Intent — auf
großen Displays evtl. kein Problem).

---

## 11. Chat-Header: Titel-Text ist bei Employer-Mode redundant ("company" zweimal)

**Datei/Screen:** `swipeshift/Features/Worker/Messages/ChatView.swift` (`chatHeader`)

**Was stört:**
```swift
Text(isEmployerMode ? conversation.company : conversation.company)
```
Beide Zweige der Ternary geben `conversation.company` zurück — im Employer-Modus sollte
hier laut Kommentar direkt darüber ("Employer: worker name; Worker: company name")
eigentlich der **Name des Workers** stehen, nicht der Firmenname (der Worker hat ja
keine "company"). Vermutlich fehlt im `Conversation`-Modell aktuell ein `workerName`-Feld,
und der Code wurde als Platzhalter belassen.

**Warum das wichtig ist:** Im Employer-Chat sieht der Arbeitgeber vermutlich einen für
ihn bedeutungslosen oder falschen Namen im Chat-Header (z. B. den eigenen Firmennamen
oder eine irreführende Bezeichnung) statt zu wissen, mit welchem Worker er gerade
schreibt — kritisch für einen Chat-Screen.

**Konkreter Vorschlag:** `Conversation`-Modell um `workerName: String` erweitern (Backend
liefert das bereits für `AllApplicantsView`/`DetailedWorkerView` — sollte auch in
Conversation/Messages-Response verfügbar gemacht werden), dann:
```swift
Text(isEmployerMode ? conversation.workerName : conversation.company)
```

**Kategorie:** 🔵 Strukturell (braucht Backend-Feld + DTO-Anpassung), aber hoher
Impact, da es den Employer-Messages-Screen (Prio-Flow) betrifft.

---

## 12. `ConversationRow`: identisches visuelles Gewicht für "Today"/"Upcoming" (farbig)
vs. Read/Unread — zwei Signale konkurrieren um Aufmerksamkeit

**Datei/Screen:** `swipeshift/Features/Worker/Messages/MessagesView.swift`

**Was stört:** Jede Zeile zeigt gleichzeitig: (a) einen farbigen Status-Pill (Today=blau,
Upcoming=grün, Completed=grau, Cancelled=rot), (b) einen ungelesen-Punkt am Avatar,
(c) fett vs. normal Text je nach `isRead`. Das sind drei unterschiedliche visuelle
Kodierungen für "Wichtigkeit"/"Status" nebeneinander, die um Aufmerksamkeit konkurrieren,
besonders bei mehreren gleichzeitig aktiven Signalen (z. B. "Today" + ungelesen +
fett) — laut Wireframe zwar so vorgegeben (Sortierung + Badges + Ungelesen-Punkt),
aber in der visuellen Ausführung könnte der ungelesen-Punkt am Avatar (12x12pt, blauer
Kreis mit weißem Rand) mit der "Today"-Badge-Farbe (auch blau) verschmelzen und dadurch
weniger auffallen als gewünscht.

**Konkreter Vorschlag:** Ungelesen-Indikator bewusst in einer Farbe halten, die sich von
allen Status-Badge-Farben unterscheidet (z. B. reines `SS.primary`-Orange oder ein
Rot/Akzent, das nicht mit Today=Blau kollidiert), damit "ungelesen" immer eindeutig
erkennbar bleibt, unabhängig vom Job-Status.

**Kategorie:** 🟡 Diskussionswürdig (Wireframe-treu umgesetzt, reine Farbfeinjustierung).

---

## 13. Touch-Target-Prüfung: Kleinste interaktive Elemente durchgehend ≥44pt? — punktuelle Ausnahme

**Datei/Screen:** `swipeshift/Features/Worker/Jobs/JobDetailView.swift` (Header-Buttons:
X-Button und Bookmark-Button, `frame(width: 36, height: 36)`)

**Was stört:** X (Close) und Bookmark im Header sind mit `36x36pt` unter dem von Apple
empfohlenen Minimum von 44x44pt für zuverlässige Tap-Erkennung. Die meisten anderen
Buttons in der App (Circle-Buttons im Swipe-Tab: 58pt/44pt, Tab-Bar-Items) liegen im
grünen Bereich — dieser Screen ist eine der wenigen Ausnahmen.

**Recherche/Beleg:** Apple HIG: "maintain a minimum tappable area of 44×44 points for
all controls" — kleinere Ziele erhöhen Fehltipp-Rate, besonders bei Zeigefinger-Bedienung
mit einer Hand (typisch beim Scrollen durch Job-Listen).

**Konkreter Vorschlag:**
```swift
.frame(width: 44, height: 44)   // statt 36x36
```
Optisches Icon kann bei 16pt bleiben, nur der Tap-Bereich wird vergrößert (padding
erhöhen statt Icon zu vergrößern), um das kompakte Erscheinungsbild zu erhalten.

**Kategorie:** 🟢 Quick Win.

---

## 14. Employer-Dashboard "Avg. Worker Rating"-Kachel zeigt dauerhaft "—" / "no data yet"

**Datei/Screen:** `swipeshift/Features/Employer/EmployerDashboardView.swift` (`trends`)

**Was stört:**
```swift
TrendItem(value: "—", label: "Avg. Worker Rating", delta: "no data yet", ...)
```
Dieser Wert ist hart codiert auf "—"/"no data yet", während die drei anderen
Trend-Kacheln bereits aus `EmployerStatsDTO` gespeist werden. Für den Arbeitgeber sieht
das dauerhaft nach einer kaputten/nicht implementierten Funktion aus, nicht nach "noch
keine Bewertungen vorhanden" (was ja plausibel früh im Lifecycle sein könnte).

**Konkreter Vorschlag:** Falls Backend die Aggregation noch nicht liefert: Kachel mit
klarem Hinweis versehen ("Available after your first completed job") statt generischem
Em-Dash, oder Kachel temporär ausblenden bis Daten verfügbar sind (Prinzip: lieber
weniger Kacheln als eine, die permanent leer wirkt).

**Kategorie:** 🟢 Quick Win.

---

## 15. Fehlende Pull-to-Refresh auf Listen-lastigen Screens

**Dateien/Screens:** `JobListView.swift`, `MessagesView.swift`, `AllPostedJobsView.swift`,
`AllApplicantsView.swift`, `RadarView.swift` (Job-Liste unterhalb der Karte)

**Was stört:** Keiner der geprüften Listen-Screens implementiert `.refreshable {}`
(natives Pull-to-Refresh von SwiftUI/iOS 15+). Aktualisierung erfolgt nur über
`.task` beim ersten Erscheinen bzw. explizite Refresh-Buttons (Radar, Swipe-Empty-State).
Für einen zeitkritischen Marktplatz (neue Bewerber, neue Jobs, neue Nachrichten
innerhalb von Minuten relevant) ist das ein spürbares Bedienungsdefizit — Nutzer
erwarten von praktisch jeder Liste in modernen iOS-Apps (Mail, App Store, Instagram,
auch Indeed/LinkedIn Jobs) Pull-to-Refresh als Standard-Geste.

**Konkreter Vorschlag:**
```swift
ScrollView { ... }
    .refreshable {
        await jobStore.loadJobsAll()   // bzw. jeweiliger Store-Reload
    }
```
Kostengünstig nachzurüsten, da die Lade-Funktionen bereits existieren (`async`).

**Kategorie:** 🟢 Quick Win — hoher wahrgenommener Qualitätsgewinn für geringen Aufwand,
in mehreren Screens gleichzeitig anwendbar.

---

## 16. Konsistenz Worker- vs. Employer-Profil-Tab: unterschiedliche Detailtiefe für
strukturell gleiche Screens

**Dateien/Screens:** `WorkerProfileView.swift` (Worker-Profil-Tab) vs.
`EmployerHomeView.swift → EmployerProfileTab` (Employer-Profil-Tab)

**Was stört:** Der Worker-Profil-Tab hat u. a. Live-Rating (`fetchWorkerReviews()`),
"Verified Worker"-Badge, differenzierten Logout-Alert (`.alert` mit Confirm/Cancel).
Der Employer-Profil-Tab hat einen rein statischen Verified-Badge (kein Live-Rating-Check),
und **Logout ohne Bestätigungsdialog** (`Button { userStore.logout() }` direkt, kein
`.alert`) — obwohl CLAUDE.md für beide Rollen "Logout triggert Bestätigungs-Popup"
vorschreibt bzw. es für Worker bereits so umgesetzt ist.

**Warum das auffällt:** Zwei strukturell identische Screens (Profil-Tab je Rolle)
sollten das gleiche Sicherheits-/Bestätigungsniveau haben. Ein Arbeitgeber, der aus
Versehen den Logout-Button trifft (z. B. beim schnellen Scrollen), wird ohne Rückfrage
ausgeloggt — inkonsistent zur Worker-Seite und potenziell frustrierend, da Employer
mitten in Bewerbungsmanagement/Zahlungsabwicklung sein könnte.

**Konkreter Vorschlag:** Gleiches `.alert("Log Out?", ...)`-Pattern aus
`WorkerProfileView` 1:1 in `EmployerProfileTab` übernehmen (identischer Code, nur
`@State private var showLogoutAlert` + `.alert` Modifier ergänzen).

**Kategorie:** 🟢 Quick Win.

---

## 17. Post-a-Job-Formular: sehr hohe Informationsdichte in einem einzigen langen Scroll
ohne Fortschrittsanzeige

**Datei/Screen:** `swipeshift/Features/Employer/PostJobView.swift`

**Was stört:** Das Formular hat 9 aneinandergereihte Sektionen (Basisinfo, Kategorie,
Tags, Schichten, Workers & Lohn, Beschreibung, Aufgaben, Anforderungen, Zahlung) in
einem durchgehenden `ScrollView`, ohne Fortschrittsindikator, Sprungnavigation oder
Sektions-Anker. Bei komplexen mehrstufigen Formularen (vergleichbar mit
Instawork/Wonolo Job-Posting-Flows) wird üblicherweise entweder in Schritte/Screens
unterteilt oder zumindest ein Fortschrittsbalken/Sticky-Sektion-Menü angeboten, damit
Arbeitgeber (oft am Handy, unterwegs) den Überblick behalten und nicht das Gefühl haben,
"endlos" zu scrollen.

**Warum das relevant ist:** Lange Formulare ohne Fortschrittsanzeige erhöhen
Abbruchraten (etablierter Formular-UX-Befund, u. a. NN/g "Chunking long forms"). Gerade
bei einem Marktplatz, der auf schnelles Job-Posting durch KMU-Arbeitgeber abzielt
(oft spontan, kurzfristige Schichten), ist Formular-Länge ein Conversion-Risiko.

**Konkreter Vorschlag:** Nicht zwingend in mehrere Screens aufteilen (Datenverlust-Risiko
bei Navigation), aber mindestens: dünne, sticky Fortschritts-/Sektionsleiste oben
("1/5 Basics · 2/5 Schedule · ...") mit `ScrollViewReader`-Sprungnavigation, analog zum
bereits vorhandenen "Sticky Footer" (Save Draft / Post Job).

**Kategorie:** 🔵 Strukturell (neue Komponente, betrifft Formular-Layout-Architektur).

---

## 18. Farbcodierung "Draft" (grau) im Employer-Job-Status vs. "Completed" (grün) — mögliche Verwechslungsgefahr mit "Cancelled"/"Inactive"-Konventionen

**Datei/Screen:** `swipeshift/Features/Employer/AllPostedJobsView.swift` (`EmployerJob.JobStatus.color`)

**Was stört:**
```swift
case .active:     return SS.primary   // blau
case .inProgress: return .orange
case .draft:      return .gray
case .completed:  return .green
case .cancelled:  return .red
```
Fünf Status, fünf Farben — grundsätzlich sauber getrennt. Aber: Grau wird in sehr vielen
iOS-Apps sowohl für "Draft/Entwurf" als auch für "Inaktiv/Deaktiviert" verwendet; hier
gibt es keine visuelle Unterscheidung zwischen "Draft" (bewusst noch nicht
veröffentlicht, positiv/neutral) und einem deaktivierten Zustand. Das ist kein Fehler,
aber im direkten Vergleich zur Konkurrenz (Indeed Employer Dashboard, LinkedIn Jobs
Recruiter) wird "Draft" dort meist mit einem neutralen aber klar erkennbaren
Badge-Icon (Stift-Symbol) zusätzlich zur Farbe gekennzeichnet, um Farbfehlsichtigkeit
(Rot/Grün-Schwäche, ca. 8% der Männer) abzufedern — hier hängt die Unterscheidung
zwischen "Cancelled" (rot) und den übrigen Status ausschließlich an der Farbe.

**Recherche/Beleg:** WCAG/iOS-Accessibility-Empfehlung: Farbe sollte nie das einzige
Unterscheidungsmerkmal für Status sein ("Don't rely on color alone").

**Konkreter Vorschlag:** Jedes Status-Badge zusätzlich zur Farbe mit einem kleinen
SF-Symbol versehen (z. B. `pencil` für Draft, `xmark.circle` für Cancelled,
`checkmark.circle` für Completed) — kostengünstige Ergänzung zur bestehenden
`PostedJobCard`-Badge-Komponente.

**Kategorie:** 🟡 Diskussionswürdig (Accessibility-Verbesserung, kein hartes Usability-Problem
für die Mehrheit der Nutzer, aber leicht nachrüstbar).

---

## Umsetzungs-Status (Lauf: 2026-07-28, /design-apply "Quick-wins 1-5")

### Finding #1 — Fake Apply/Bookmark auf `DashboardJobCard`: ✅ Umgesetzt (nach 1 Korrekturrunde)

- Apply-Pill entfernt, Bookmark ist echter `Button` (`jobStore.toggleSaveJob`), neuer zentraler State
  `JobStore.savedJobIds` + `loadSavedJobIds()`.
- **Korrekturrunde 1 (kritisch, behoben):** Reviewer fand, dass `JobSwipeView` einen komplett separaten,
  nicht synchronisierten `@State savedJobIds` nutzte → Speichern im Swipe-Tab hätte die Dashboard-Karte nicht
  aktualisiert. Gefixt: `JobSwipeView` nutzt jetzt denselben `jobStore.savedJobIds`/`toggleSaveJob`.
- **Warnung (behoben):** `CategoryJobListView` lud `loadSavedJobIds()` nicht selbst — ergänzt für Robustheit
  bei künftigen Einstiegspunkten.
- **Zweiter kritischer Punkt des Reviewers (`JobDetailView.isBookmarked` ist reiner UI-Fake, keine API-Anbindung)
  wurde NICHT hier behoben** — das ist exakt Finding #7 (Quick Win #5 dieser Auswahl) und wird dort adressiert,
  um Doppelarbeit zu vermeiden.
- Dateien: `swipeshift/Stores/JobStore.swift`, `Features/Worker/Dashboard/JobSectionView.swift`,
  `Features/Worker/Dashboard/WorkerHomeTabView.swift`, `Features/Worker/Jobs/JobListView.swift`,
  `Features/Worker/Jobs/JobSwipeView.swift`, `Features/Worker/Jobs/CategoryJobListView.swift`.

### Finding #2 — Swipe-Tab: Top-Karte inkonsistent mit Filter: ✅ Umgesetzt

Einzeilige Änderung in `JobSwipeView.swift:121`: `jobStore.swipeJobs.first` → `topJob` (bereits vorhandene
computed property = `filteredSwipeJobs.first`). Top-Karte ist jetzt konsistent mit Header-Zähler,
Hintergrundkarten und Action-Buttons (alle nutzen bereits `filteredSwipeJobs`/`topJob`).

Hinweis: Der `reviewer` markierte diesen Fix zunächst fälschlich als "kritisch — angeblich kein Ein-Zeilen-Fix",
weil `git diff` gegen den letzten Commit auch viel nicht mit dieser Aufgabe zusammenhängenden, bereits vorher
unstaged im Working Tree liegenden Code zeigt (FilterSheet, Ratings-Block — Altlast aus vorherigem
Arbeitsstand). Per direktem Vorher/Nachher-Vergleich der betroffenen Zeilen verifiziert: Es wurde tatsächlich
nur die eine Zeile geändert. Kein Korrektur-Durchlauf nötig.

### Finding #4 — Hardcodierte Fake-Badges: ✅ Umgesetzt (keine Korrektur nötig)

Alle 4 Badges an echte Backend-Daten angebunden (kein `nil`-Fallback nötig, da für jeden Fall bereits ein
passender Endpunkt existierte): "Job Applications" (Worker) über `fetchWorkerApplications()` gefiltert auf
`displayStatus == "applied"`; "Saved" (Worker) über `fetchWorkerSaved()` + `fetchSavedCompanies()`;
"Assign Workers" (Employer) über `fetchAssignedWorkers()` gefiltert auf `!isFullyStaffed`; "Leave Reviews"
(Employer) über `fetchPendingReviews().count`. Reviewer bestätigte Filterlogik, Fehlerbehandlung (`try?`,
kein Crash-Risiko) und Konsistenz mit bereits bestehenden Nachbar-Badges — keine kritischen Punkte.

Vorschlag (optional, kein Blocker): In `WorkerProfileView` wird der "Saved"-Count aus zwei unabhängigen
`try?`-Calls addiert — schlägt einer fehl, wird nur die Hälfte gezählt statt komplett `nil`. Nicht umgesetzt,
da unkritisch für ein reines Badge.

Dateien: `Features/Worker/Profile/WorkerProfileView.swift`, `Features/Employer/EmployerDashboardView.swift`.

### Finding #6 — Fehlende Haptics im Swipe-Interface: ✅ Umgesetzt (keine Korrektur nötig)

3 native iOS-17 `.sensoryFeedback`-Modifier in `JobSwipeView.swift` ergänzt (kein UIKit): `.light` beim
einmaligen Überschreiten des Swipe-Threshold während des Drags, `.medium` beim tatsächlichen Apply/Skip
(Drag-Release oder Button-Tap), `.light` beim Bookmark-Toggle. Reviewer bestätigte korrekte Trigger-Logik
(garantierter Wertwechsel durch `.toggle()`, korrektes Reset pro Geste) — keine kritischen Punkte.

Dateien: `Features/Worker/Jobs/JobSwipeView.swift`.

### Finding #7 — Job-Detail-Bookmark ist rein lokal: ✅ Umgesetzt (nach 1 Korrekturrunde)

`JobDetailView.swift`: lokaler `@State isBookmarked` entfernt, ersetzt durch computed property
`jobStore.savedJobIds.contains(job.id)`; Bookmark-Button ruft jetzt `jobStore.toggleSaveJob(job.id)` auf;
`.task { await jobStore.loadSavedJobIds() }` ergänzt für Deep-Link-Robustheit.

**Korrekturrunde 1 (Warnung, behoben):** Reviewer fand einen wirkungslosen `withAnimation`-Wrapper um den
`Task {...}`-Block — `withAnimation` animiert nur synchrone State-Changes, der eigentliche State-Change in
`toggleSaveJob` passiert aber asynchron außerhalb dieser Transaktion, der Wrapper war toter Code. Entfernt,
jetzt konsistent mit dem bereits etablierten Pattern in `JobSectionView.swift`/`JobSwipeView.swift` (kein
expliziter Animation-Wrapper nötig).

Dateien: `Features/Worker/Jobs/JobDetailView.swift`.

---

**Alle 5 Quick Wins dieser Auswahl (Findings #1, #2, #4, #6, #7) sind umgesetzt.** Zusammen bilden sie jetzt
ein durchgängig konsistentes Bookmark-System über `JobStore.savedJobIds`/`toggleSaveJob(_:)`/`loadSavedJobIds()`,
das an allen 5 Stellen (Dashboard-Karten, Job-Liste, Kategorie-Liste, Swipe-Tab, Job-Detail) denselben,
echten Backend-Zustand zeigt.

### Finding #8 — Theme-Radius-Inkonsistenz: ✅ Umgesetzt (Quick-Win-Teil, keine Korrektur nötig)

`swipeshift/utils/Theme.swift`: `SS.cardRadius` bedeutet jetzt 14pt (korrekt benannter Standard für
Job-/Listenkarten), neue Konstante `SS.authCardRadius` = 34pt (alte Bedeutung, jetzt korrekt benannt, von
`SSCard` referenziert). Reviewer bestätigte: `SSCard` war die einzige bisherige Verwendungsstelle der alten
34pt-Konstante — keine stillschweigenden Layout-Änderungen an anderer Stelle, Auth-Screens visuell unverändert.

**Bewusst NICHT umgesetzt (optionaler struktureller Teil):** Flächendeckende Umstellung der Hardcodes
(12/14/16pt) in `JobSectionView.swift`/`JobListView.swift`/`RadarView.swift`/`JobDetailView.swift` auf die
neue Konstante — das war explizit als optionaler 🔵-Anteil ausgeklammert. `SS.cardRadius` (14pt) ist aktuell
ungenutzt ("totes" Token), bis dieser strukturelle Nachfolge-Schritt bei Bedarf separat angegangen wird.

Dateien: `swipeshift/utils/Theme.swift`.

### Finding #9 — Open-Spots-Fallback-Inkonsistenz: ✅ Umgesetzt (keine Korrektur nötig)

`JobDetailView.swift`: Beide Stellen (`QuickInfoCell` Zeile 151, Sticky Apply Bar Zeile 370) nutzen jetzt
`job.openSpots.map { ... } ?? "–"` — konsistenter `"–"`-Fallback bei `nil` statt der vorher irreführenden
`"1"`, echte Zahl (inkl. `0`) wird weiterhin korrekt angezeigt. Reviewer bestätigte korrekte Optional-Logik
und Pluralisierung.

Dateien: `Features/Worker/Jobs/JobDetailView.swift`.

### Finding #13 — Touch-Targets zu klein: ✅ Umgesetzt (keine Korrektur nötig)

`JobDetailView.swift`: X-Button und Bookmark im Header behalten ihre sichtbare 36x36pt-Kreisgröße
(Icon/Hintergrund/Schatten unverändert), bekommen aber einen zusätzlichen äußeren `.frame(44, 44)` für den
Tap-Bereich. Reviewer bestätigte, dass SwiftUI den kleineren Kreis korrekt zentriert (kein Stretching/Clipping)
und schlug vor, `.contentShape(Circle())` zu `.contentShape(Rectangle())` zu ändern, damit die vollen 44x44pt
tappbar sind statt nur der einbeschriebene Kreis (Ecken sonst ~21% ungetappt) — direkt übernommen.

Dateien: `Features/Worker/Jobs/JobDetailView.swift`.

### Finding #14 — Leere "Avg. Worker Rating"-Kachel: ✅ Umgesetzt (echte Anbindung, nach kleiner Korrektur)

`EmployerDashboardView.swift`: Fachlich geklärt, dass "Avg. Worker Rating" die Bewertungen meint, die der
Employer seinen Workern nach Schichtabschluss gibt (`Review`-Modell) — Endpunkt `fetchPastReviews()` existierte
bereits (genutzt in `LeaveReviewsView`). Kachel zeigt jetzt den echten Durchschnitt (`PastReviewItem.avgRating`
gemittelt, `%.1f`-Formatierung) mit "based on N reviews"; ist die Liste leer, zeigt sie `"—"` mit der
transparenteren Copy `"Available after your first completed job"` statt des generischen "no data yet".
Reviewer bestätigte korrekte Division-durch-Null-Absicherung (leer-Check vor der Division), korrekte
Formatierung und `try?`-Fehlerbehandlung.

**Kleine Korrektur (Performance-Warnung, direkt behoben):** `fetchEmployerStats()` lief sequenziell vor den
drei anderen `async let`-Calls in `loadStats()`. Umgestellt, sodass alle 4 Calls parallel laufen.

Dateien: `Features/Employer/EmployerDashboardView.swift`.

### Finding #15 — Fehlendes Pull-to-Refresh: ✅ Umgesetzt (alle 5 Screens, keine Korrektur nötig)

`.refreshable {}` ergänzt in `JobListView.swift` (ruft `loadJobsAll()`+`loadSavedJobIds()`),
`MessagesView.swift` (`loadConversations()`), `AllPostedJobsView.swift` und `AllApplicantsView.swift` (jeweils
`load()`, angewendet auf `SubScreenShell(...)` — propagiert korrekt an die intern gerenderte `ScrollView`),
`RadarView.swift` (`loadJobs()`, bestehender manueller Refresh-Button bewusst nicht entfernt). Reviewer
bestätigte: alle aufgerufenen Funktionen existieren bereits, keine neu erfundene Logik, kein Regressionsrisiko.
Kleine, bereits vorbestehende UX-Lücke (kein Auth-Guard-Feedback in `JobListView`) repliziert, aber nicht neu
eingeführt — außerhalb des Scopes.

Dateien: `Features/Worker/Jobs/JobListView.swift`, `Features/Worker/Messages/MessagesView.swift`,
`Features/Employer/AllPostedJobsView.swift`, `Features/Employer/AllApplicantsView.swift`,
`Features/Worker/Jobs/RadarView.swift`.

### Finding #16 — Fehlender Employer-Logout-Bestätigungsdialog: ✅ Umgesetzt (keine Korrektur nötig)

`EmployerHomeView.swift` (`EmployerProfileTab`): Logout-Button setzt jetzt `showLogoutAlert = true` statt
direkt `userStore.logout()` aufzurufen; neuer `.alert("Log Out?", ...)` mit "Log Out"/destructive und
"Cancel"-Buttons, 1:1 identisch zum bereits bestehenden Worker-Pattern (`WorkerProfileView.swift`). Reviewer
bestätigte korrekte Platzierung, kein doppelter/toter Logout-Pfad.

Dateien: `Features/Employer/EmployerHomeView.swift`.

---

**Damit sind alle 11 als 🟢 Quick Win markierten Findings dieses Reports umgesetzt** (#1, #2, #4, #6, #7, #8,
#9, #13, #14, #15, #16) — 5 aus der vorherigen `/design-apply`-Runde, 6 aus dieser Runde. Offen bleiben nur
noch die 4 🔵 Strukturell-Findings (#3, #11, #17, sowie der optionale Teil von #8) und die 4 🟡
Diskussionswürdig-Findings (#5, #10, #12, #18) — Letztere erfordern laut Vorgabe explizit eine Rückfrage vor
Umsetzung.

## Anhang: Nicht vertiefte, aber notierte Beobachtungen (für spätere Läufe)

- `EmployerJobsTab`/`EmployerPlaceholderTab` in `EmployerHomeView.swift` sind
  ungenutzte `private struct`s (toter Code) — kein Design-, aber ein Wartbarkeitsthema.
- `ChatView`: Polling alle 10s per `Task.sleep` ist funktional, aber kein
  Battery-/Netzwerk-schonendes Pattern für Dauerbetrieb; für ein späteres Review evtl.
  WebSocket/Push statt Poll evaluieren (kein reines Design-Thema, daher hier nur notiert).
- `RadarView`: Radius-Optionen (5/10/25/50/100 km) vs. `JobListView`-Distanzfilter
  (5/10/15/20/25 km) nutzen unterschiedliche Werte-Sets für konzeptionell denselben
  Filter — evtl. für einen späteren Konsistenz-Review vereinheitlichen.

## Tester: Build-/Regressionscheck (design-apply Lauf)

**Zeitstempel:** 2026-07-28

**iOS-Build:** Kein vollständiges Xcode installiert — `xcode-select -p` zeigt
`/Library/Developer/CommandLineTools`, `xcodebuild -version`/`-list` schlägt mit
`"tool 'xcodebuild' requires Xcode"` fehl. Ein echter `xcodebuild build`-Lauf war in dieser
Umgebung daher nicht möglich (ehrlich vermerkt, nicht vorgetäuscht).

**Ersatz-Check — `swiftc -parse` auf den 9 geänderten Kern-Dateien:** Alle 9 Dateien wurden
einzeln mit `swiftc -parse <datei>` geprüft (reine Syntaxprüfung, keine Modul-/Import-Auflösung
nötig). Ergebnis: **alle 9 exit 0, keine Fehlermeldungen.**

- `swipeshift/Stores/JobStore.swift`
- `swipeshift/Features/Worker/Dashboard/JobSectionView.swift`
- `swipeshift/Features/Worker/Dashboard/WorkerHomeTabView.swift`
- `swipeshift/Features/Worker/Jobs/JobListView.swift`
- `swipeshift/Features/Worker/Jobs/CategoryJobListView.swift`
- `swipeshift/Features/Worker/Jobs/JobSwipeView.swift`
- `swipeshift/Features/Worker/Profile/WorkerProfileView.swift`
- `swipeshift/Features/Employer/EmployerDashboardView.swift`
- `swipeshift/Features/Worker/Jobs/JobDetailView.swift`

Hinweis: `-parse` prüft nur Grammatik/Syntax, keine Typen, keine Cross-File-Referenzen
(z.B. ob `jobStore.savedJobIds` tatsächlich existiert) — das ersetzt keinen echten Build,
ist aber ein ehrlicher Teil-Check ohne Xcode.

**Backend-Regressionscheck:** `cd swipeshift-backend && npm test` → alle 4 bestehenden Tests
weiterhin grün (`haversineDistance`-Tests + multer/static-Pfad-Test), 0 Fails. Kein inhaltlicher
Bezug zu den iOS-Änderungen, reiner Vollständigkeits-Check.

**Fazit:** Kein Build-Fehler feststellbar im Rahmen der verfügbaren Checks. Volle Gewissheit über
Kompilierbarkeit (Typen, Signaturen, `@MainActor`/`async`-Korrektheit) erfordert einen echten
`xcodebuild`-Lauf mit vollem Xcode, der in dieser Umgebung nicht verfügbar ist.

## Tester: Finaler Build-/Regressionscheck (design-apply Runde 2)

**Zeitstempel:** 2026-07-28

**Umgebung unverändert:** `xcodebuild -version` scheitert weiterhin mit
`"tool 'xcodebuild' requires Xcode"` (nur Command Line Tools aktiv), `xcrun --sdk iphonesimulator
--show-sdk-path` findet keine SDK. Kein voller Build möglich, wie im vorherigen Tester-Lauf bestätigt.

**Ersatz-Check — `swiftc -parse` auf den 9 in dieser Runde geänderten Dateien:** Jede Datei einzeln
mit `swiftc -parse <datei>` geprüft (Swift 6.3.1 / swift-driver 1.148.6). Ergebnis: **alle 9 exit 0,
keine Fehlermeldungen/Warnungen im Output.**

- `swipeshift/utils/Theme.swift`
- `swipeshift/Features/Worker/Jobs/JobDetailView.swift`
- `swipeshift/Features/Employer/EmployerDashboardView.swift`
- `swipeshift/Features/Worker/Jobs/JobListView.swift`
- `swipeshift/Features/Worker/Messages/MessagesView.swift`
- `swipeshift/Features/Employer/AllPostedJobsView.swift`
- `swipeshift/Features/Employer/AllApplicantsView.swift`
- `swipeshift/Features/Worker/Jobs/RadarView.swift`
- `swipeshift/Features/Employer/EmployerHomeView.swift`

Hinweis unverändert: `-parse` prüft nur Grammatik/Syntax, keine Typen, keine Cross-File-Referenzen
(z. B. ob `SS.cardRadius`/`SS.authCardRadius` überall korrekt referenziert werden oder ob
`.refreshable {}` auf einen tatsächlich existierenden async Store-Call zeigt) — ersetzt keinen
echten Build.

**Backend-Regressionscheck:** `cd swipeshift-backend && npm test` → weiterhin alle 4 bestehenden
Tests grün (0 fail): `haversineDistance` (3 Tests: identische Koordinaten, Stuttgart→Hamburg-Distanz,
Symmetrie A→B/B→A) sowie der multer-diskStorage/express.static-Pfadauflösungstest. Kein inhaltlicher
Bezug zu den iOS-Design-Fixes dieser Runde, reiner Vollständigkeits-Check.

**Fazit:** Kein Syntaxfehler in den 9 geänderten Swift-Dateien feststellbar, Backend-Tests
unverändert grün. Wie zuvor: keine Aussage über Typkorrektheit/Cross-File-Referenzen ohne echten
Xcode-Build möglich.

---

## `/design-apply`-Lauf: Strukturelle Findings #3, #11, #8 (optional)

**Zeitstempel:** 2026-08-03. Auswahl laut Nutzer: "strukturelle finding #3 und #11 und #8".

### Finding #3 — Apply-Flow: Fehler-Buttons navigieren nirgendwohin: ✅ Umgesetzt

`ApplyResultView` (`ApplyFlowView.swift`) hat jetzt pro Ergebniszustand eine tatsächliche Aktion statt
generischem `onDone()`: `.connectionLost` → "Try Again" ruft `submitApplication()` erneut auf;
`.shiftAlreadyTaken`/`.shiftUnavailable` → Primär-Button schließt über neuen `onExitToJobList`-Callback
das gesamte Apply-Sheet + JobDetailView (zurück zur Job-Liste); `.schedulingConflict` → "View My Calendar"
präsentiert `WorkerCalendarView()` als verschachteltes Sheet. Einziger Call-Site (`JobDetailView.swift`)
angepasst. Reviewer bestätigte: korrekt, vollständig, kein Regressionsrisiko, `swiftc -parse` sauber.

Dateien: `Features/Worker/Jobs/ApplyFlowView.swift`, `Features/Worker/Jobs/JobDetailView.swift`.

### Finding #11 — Chat-Header zeigt Firmenname statt Worker-Name: ✅ Umgesetzt (Befund korrigiert)

**Wichtige Abweichung vom ursprünglichen Finding:** Die Prämisse des Reports ("braucht neues
Backend-Feld + DTO-Anpassung") war veraltet/falsch. Gegenprüfung von `routes.messages.js`
(`formatConversation`) zeigte, dass das Feld `company` bereits serverseitig rollenabhängig korrekt
befüllt wird (Worker-Sicht: Firmenname, Employer-Sicht: Worker-Name) — kein Laufzeit-Bug. Der einzige
tatsächliche Fehler war eine tote/verwirrende Ternary in `ChatView.swift` (`chatHeader`), bei der beide
Zweige identisch `conversation.company` zurückgaben. Umgesetzt wurde eine reine Code-Klarheits-Korrektur
(Ternary entfernt, Kommentar korrigiert) statt der ursprünglich angenommenen Backend-/DTO-Änderung.
Reviewer bestätigte die Gegenprüfung unabhängig und die Korrektheit der minimalen Änderung.

Dateien: `Features/Worker/Messages/ChatView.swift`.

### Finding #8 (optionaler Teil) — Card-Radius-Token vereinheitlichen: ✅ Umgesetzt

Hardcodierte `cornerRadius`-Werte an den äußeren Karten-Containern durch `SS.cardRadius` ersetzt:
`DashboardJobCard` (`JobSectionView.swift`, 14→Token), `RadarJobCard` (`RadarView.swift`, 14→Token),
sowie vier Sektionen in `JobDetailView.swift` (`requirementsSection`, `payDetailsSection`,
`companySection`, `whatHappensNextSection`, 12→Token). `JobListView.swift` brauchte keine Änderung
(nutzt bereits `DashboardJobCard`). Dekorative Icon-/Logo-Container, Buttons, Suchfeld und Sheets
bewusst nicht angefasst (außerhalb des Finding-Scopes).

**Hinweis (vom Reviewer korrigiert):** In `JobSectionView.swift`/`RadarView.swift` war der Hardcode
bereits 14 (= `SS.cardRadius`), daher optisch neutral. In `JobDetailView.swift` war der Hardcode zuvor
**12**, nicht 14 — die vier betroffenen Karten werden dort minimal runder (12→14pt), ein kleiner,
aber echter optischer Effekt, keine reine Wert-Migration ohne visuelle Änderung.

Dateien: `Features/Worker/Dashboard/JobSectionView.swift`, `Features/Worker/Jobs/RadarView.swift`,
`Features/Worker/Jobs/JobDetailView.swift`.

### Tester: Gesamt-Check dieser 3 Findings

`swiftc -parse` auf allen 5 geänderten Dateien: exit 0, keine Fehler. `git diff --stat` zeigt keine
unbeabsichtigten Zusatzänderungen. Backend-Tests (`npm test`): weiterhin 4/4 grün (kein inhaltlicher
Bezug, reiner Vollständigkeits-Check). Kein echter Xcode-Build/Simulator-Lauf möglich (bekannte
Umgebungseinschränkung, siehe oben).

**Offen bleiben:** Finding #17 (🔵 Strukturell, Post-a-Job-Formular) sowie die 4 🟡
Diskussionswürdig-Findings (#5, #10, #12, #18) — Letztere weiterhin nur nach Rückfrage/Richtungsentscheidung.
