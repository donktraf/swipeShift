# App Development Tracker — Feld-Level-Audit

Quelle: Notion-Datenbank "App Development Tracker" (https://app.notion.com/eff6b0b0e69082e8ba7f81add6a7b758?v=4d46b0b0e69082f1bfb1887808b1941d),
641 Zeilen, 3 Ebenen (Screen → Abschnitt → Feld).

**Methodik:** Für jeden Screen wird die Notion-Feldliste gegen den tatsächlichen Swift-/Backend-Code geprüft.
Nur Felder mit echtem UI-Gegenstück zählen als "vorhanden". Rein spekulative/zukünftige Felder (z.B. Platform-Fee-Konzepte ohne jegliche Backend-Grundlage) werden als "fehlt, vermutlich bewusst zurückgestellter Scope" markiert statt unkommentiert als Bug.

**Fortschritt wird nach jedem Screen hier aktualisiert** (damit bei Unterbrechung nichts verloren geht).

Status-Legende: ✅ geprüft | 🔄 in Arbeit | ⬜ noch nicht geprüft

---

## Übersicht

| # | Screen | Status | Konkrete Lücke gefunden? |
|---|---|---|---|
| 1 | Register Screen | ✅ | Nein — Register-/Onboarding-Felder vollständig |
| 2 | Login Screen | ✅ (Vorrunde) | Ja (bekannt, korrekt als "Problem" markiert) |
| 3 | Landing Page | ✅ | Nein |
| 4 | Applied Job Screen Overview (Employee) | ✅ | Nein (grobe Prüfung, Tabs/Withdraw-Flow passt) |
| 5 | Calendar Screen | ✅ | ~~Ja~~ → **umgesetzt 2026-11-16** (Worker-Seite) |
| 6 | Chat Screen | ✅ | ~~Ja~~ → **umgesetzt 2026-11-16** |
| 7 | Job Detail Screen | ✅ | ~~Ja (klein)~~ → **umgesetzt 2026-11-16** |
| 8 | Applicants Overview Screen (Company) | ✅ | Nein (Fund war falsch zugeordnet, siehe #14) |
| 9 | Add Job Screen (Company) | ✅ (Vorrunde) | **Ja** (groß, siehe oben) |
| 10 | Setting Screen | ✅ | **Ja** |
| 11 | Rating Screen | ✅ | ~~Ja~~ → **umgesetzt 2026-11-16** |
| 12 | Job List Screen | ✅ | Nein |
| 13 | Logout Screen | ✅ | Nein (Worker-Seite geprüft) |
| 14 | Detailed Company Profile Screen (Employee) | ✅ | ~~Ja~~ → **umgesetzt 2026-11-16** |
| 15 | Profile Screen | ✅ | Nein (grobe Prüfung) |
| 16 | Financial Overview | ✅ | ~~Ja~~ → **umgesetzt 2026-11-16** (beide Seiten) |
| 17 | Saved Screen | ✅ | Nein |
| 18 | Dashboard Screen - Worker | ✅ (Vorrunde) | Nein |

**Alle 18 Screens geprüft.** Methodik-Hinweis: Dies ist eine gezielte Code-Prüfung (grep + Lesen relevanter Abschnitte), keine erschöpfende Zeile-für-Zeile-Prüfung aller ~600 Notion-Feld-Zeilen — aber jeder unten gelistete Fund ist direkt im Code verifiziert, nicht geraten.

---

## 9. Add Job Screen (Company) — ✅ geprüft (Vorrunde)

Code: `swipeshift/Features/Employer/PostJobView.swift` (9 Abschnitte: Basic Info, Category, Tags, Shifts, Workers & Pay, Job Description, Tasks, Requirements, Payment & Contract).

**Fehlt konkret:** Job Urgency, Job Location Type (on-site/mehrere Standorte), Required Skills multi-select, Physical Requirements, Zertifikate/Bildungsniveau, Break Included/Duration, Same-Day Pay Available, Tips Included, Bonus Available/Description, Job Type multi-select (One-day/Weekend/Last-minute/Event-based), Instant Match Enabled, Repeat Work Opportunity, Cancellation Policy/Notes, Work Authorization Checkbox, explizite Platform-Terms-Checkbox. Platform Fee/Net Worker Pay: kein Backend-Konzept vorhanden.

Einschätzung: liest sich wie späterer, erweiterter Feature-Scope (Instant-Match, Plattform-Gebühren, Boni), nicht wie übersehene MVP-Arbeit — vor Umsetzung mit User klären.

---

## 18. Dashboard Screen - Worker — ✅ geprüft (Vorrunde)

3 Kinder ("View All Jobs Section", "Suggestions Section", "Category Section") waren alle schon "Erledigt" in Notion, keine eigenen Unterkinder. Keine Lücke gefunden.

---

## 1. Register Screen — ✅ keine Lücke

Code: `RegisterView.swift` + `WorkerOnboardingView.swift` + `EmployerOnboardingView.swift` + `RoleChoiceView.swift`. Alle Notion-Felder vorhanden: Worker (First/Last Name, Email, Password, DoB, Location, Job-Interests-Multiselect, Availability Days+Zeitblock, Terms-Checkbox, Profile Photo, Bio) und Employer (Company Name, Contact Person, Business Email, Password, Location, Industry, Company Size, Terms-Checkbox, Logo, Website/Instagram, Description) decken die Notion-Spec praktisch 1:1 ab.

## 3. Landing Page — ✅ keine Lücke

Code: `MainView.swift`. Login-Button, Register-Button, Google-/Apple-Sign-In-Buttons vorhanden (beide fullScreenCover, wie Architektur-Vorgabe verlangt).

## 4. Applied Job Screen Overview (Employee) — ✅ keine Lücke (grobe Prüfung)

Code: `JobApplicationsView.swift`. Confirmed/Applied/Completed/Cancelled-Tabs vorhanden, Withdraw-Application-Flow mit Bestätigungs-Alert vorhanden. Monatsgruppierung/Sortierung aus dem Notion-Kommentar nicht einzeln nachverifiziert (keine konkrete Lücke gefunden, aber auch nicht jedes Detail einzeln geprüft).

## 5. Calendar Screen — ⚠️ Lücke gefunden (Worker-Seite)

Code: `WorkerCalendarView.swift` (Month/Week-Toggle ✓, Status-Farbcodierung ✓) + `EmployerCalendarView.swift` (Month/Week-Toggle ✓, Filter All/Needs-Workers/Fully-Staffed ✓, Open-Spots/Assigned-Anzeige ✓ — Employer-Seite deckt ihre Notion-Spec gut ab).

**Fehlt auf Worker-Seite** (verifiziert: kein Treffer für `chat`/`Chat`, `Paid`/`pending`, `conflict`/`overlap` in der Datei):
- "Open Chat"-Button für bestätigte Jobs (explizit in CLAUDE.md-Wireframe gefordert)
- Payment-Status-Sichtbarkeit (Pending/Paid) auf Kalender-Einträgen
- Stornierungsgrund + visueller Indikator bei abgesagten Jobs
- Warnung bei überlappenden Schichten (Conflict-Indicator)

**✅ Umgesetzt (2026-11-16)** nach den Notion-Notizen zum "Calendar Screen": antippbare Einträge mit Detail-Sheet (Zeit, Ort, Arbeitgeber, Bezahlung) + "View Job Details" / "Open Chat" (nur angenommen), Zahlungsstatus bei abgeschlossenen Jobs, stornierte Jobs mit Symbol + Grund (Employer kann beim Stornieren optional einen Grund angeben), Overlap-Warnung, vergangene Jobs getrennt + ausgegraut, Leerzustand mit "Find jobs nearby", Wochen-Navigation. **Nebenbei behoben:** stornierte Jobs wurden angenommenen Workern weiter als "confirmed" angezeigt und als Verdienst gezählt.
**Bewusst offen:** "Daily view (default)" aus Notion (Wireframe verlangt Monat/Woche, so belassen), Zeitzonen-Label bei Jobs in anderem Bundesstaat, automatisches Aktualisieren ohne Neuöffnen (lädt bei jedem Öffnen neu).

## 6. Chat Screen — ⚠️ Lücke gefunden

Code: `ChatView.swift` + Prisma `Message`-Model (`id, conversationId, senderId, text, isSystem, isRead, createdAt`).

**Fehlt** (Backend-Modell hat schlicht keine Felder dafür):
- Typing-Indicator
- Online/Offline-Status der Gegenseite
- Read-Receipts über den einfachen `isRead`-Boolean hinaus (keine Pro-Teilnehmer-Quittung)

Das sind strukturelle Backend-Lücken, nicht nur UI — das Chat-System ist bewusst auf Polling (`?since=`) ausgelegt, nicht auf Echtzeit-Präsenz. Passt zur bekannten MVP-Vereinfachung.

**✅ Umgesetzt (2026-11-16), weiterhin Polling-basiert (kein WebSocket):**
- Backend: `User.lastSeenAt` (gedrosselt in `requireAuth`), `Conversation.{worker,employer}LastReadAt` + `{worker,employer}TypingAt` (Migration `20261116120000_add_chat_presence_read_receipts`), neuer Endpunkt `POST /messages/:id/typing`, `GET /messages/:id` liefert zusätzlich `presence`, Nachrichten tragen `isReadByOther`. Logik in `src/utils/chatPresence.js` (+ Tests).
- iOS: Header zeigt "typing…" / "Online" / "Last seen …", animierte Typing-Blase, Häkchen an eigenen Nachrichten (Uhr → ✓ → ✓✓), Polling im offenen Chat 10 s → 3 s, eingehende Nachrichten werden im offenen Chat sofort als gelesen gemeldet. Neue Datei `ChatBubbles.swift`.

## 7. Job Detail Screen — ⚠️ kleine Lücke

Code: `JobDetailView.swift`. Fast alle Notion-Felder vorhanden (Requirements, Pay Details, Company Section, What-Happens-Next, Bookmark). 

**Fehlt:** "Share Icon" (Job extern/intern teilen) — in Notion als eigenes Feld gelistet, im Code kein `Share`/`ShareLink`-Treffer in der Datei.

**✅ Umgesetzt (2026-11-16):** Share-Button im Header (iOS-Share-Sheet mit Kurztext + Deep Link `swipeshift://job/<id>`); Deep Link öffnet beim Worker das Job-Detail. TODO: Universal Link, sobald die Domain live ist.

## 8. Applicants Overview Screen (Company) — ⚠️ kleine Lücke

Code: `AllApplicantsView.swift`. Accept/Decline-Buttons rufen echte Backend-Endpunkte auf (`acceptApplicant`/`declineApplicant`), Tabs funktionieren.

~~**Fehlt:** "Employer response rate"~~ — **Korrektur 2026-11-16:** Das Feld gehört in Notion zum "Detailed Company Profile Screen (Employee)", nicht zur Bewerber-Übersicht. Umgesetzt dort (siehe #14).

## 10. Setting Screen — ⚠️ Lücke gefunden

Code: `AccountSettingsView.swift`. Navigation zu Account & Security, Notifications (inkl. Quiet Hours mit Toggle+DatePicker ✓), Payments & Payouts, Privacy & Data, App Preferences — Struktur stimmt mit CLAUDE.md überein.

**Fehlt konkret:**
- **2FA** — im Wireframe (CLAUDE.md: "Passwort aendern, 2FA, Active Sessions") explizit gefordert, kein `2FA`/`twoFactor`-Treffer im gesamten File.
- **Active Sessions ist komplett mock** — nicht nur das Einzelgerät-Abmelden (schon bekannt): die Geräte-*Liste selbst* ist hardcodiert (`private let sessions: [DeviceSession] = [...]`), kommt nicht vom Backend. Das ist eine größere Lücke als bisher dokumentiert.

**✅ Umgesetzt (2026-11-17):** Echte Sitzungen pro Gerät (Backend-Modell `UserSession`, jeder Token gehört zu einer Sitzung), Geräteliste mit "Active now"/zuletzt aktiv, einzelnes Gerät oder alle anderen abmelden, Logout beendet die Sitzung serverseitig, Passwortwechsel meldet andere Geräte ab. 2FA per 6-stelligem E-Mail-Code (an/aus mit Bestätigungscode, Abfrage bei jedem Login inkl. Google/Apple). Offen: Standort pro Gerät, Authenticator-App als Alternative.

## 11. Rating Screen — ⚠️ Lücke gefunden (Employer-Seite)

Code: `ReviewsView.swift` (Worker, zeigt bewertet-zu-werden) + `LeaveReviewsView.swift` (Employer, bewertet Worker). Worker-Seite: alle 4 Skills (Communication, Teamwork, Reliability, **Working under Pressure** — verifiziert vorhanden über `avgUnderPressure`) ✓. Employer-Seite: Pending/Drafts/Past-Tabs ✓, Sort (Most Recent/Highest/Lowest) ✓, Filter nach Rating + Would-Rehire ✓.

**Fehlt auf Employer-Seite:** Filter nach **Job Category** und **Date Range** — CLAUDE.md verlangt "Filter: Rating-Level, Job Category, Would Rehire, Date Range", Code hat nur `filterRating`/`filterWouldRehire`, keine Kategorie- oder Datums-Filter-States.

**✅ Umgesetzt (2026-11-16):** Neues Filter-Sheet (`ReviewFilterSheet.swift`) mit Job-Kategorie (nur vorkommende Kategorien) und Schicht-Datum (Last 7 Days / 30 Days / 3 Months / Custom); Kategorie + Datum filtern auch "Pending". Entwurfsmodus (wirkt erst bei Apply), "Keine Treffer"-Zustand. Rein clientseitig, Backend lieferte die Felder schon. **Neu aufgefallen:** der "Drafts"-Tab ist nur ein Platzhalter (Entwürfe werden nicht gespeichert).

## 12. Job List Screen — ✅ keine Lücke

Code: `JobListView.swift`. Sticky Header, Suchfeld, Sort-Sheet, Filter-Sheet, aktive-Filter-Zähler — alles vorhanden und deckt die Notion-/CLAUDE.md-Spec gut ab.

## 13. Logout Screen — ✅ keine Lücke (Worker-Seite geprüft)

Code: `WorkerProfileView.swift` — Bestätigungs-Alert ("Log Out?") vor echtem Logout vorhanden. Employer-Seite laut PRIORITIES.md #16 ebenfalls bereits umgesetzt (nicht erneut einzeln nachgelesen).

## 14. Detailed Company Profile Screen (Employee) — ⚠️ Lücke gefunden

Code: `CompanyProfileView.swift`. Rating + Sterne + Review-Breakdown ✓, Review-Karten (max 2 + "View all") ✓, Locations-Liste ✓, Website-Kontakt ✓.

**Fehlt:** Telefon und E-Mail in den Company-Contact-Details — CLAUDE.md verlangt explizit "Telefon, E-Mail, Website", Code hat nur `website`-Feld, kein `phone`/`email`-Treffer in der Datei.

**✅ Umgesetzt (2026-11-16): "Employer response rate" + "Typical response time"** (Notion-Felder dieses Screens): neues Feld `Apply.respondedAt` (erste Antwort), Berechnung in `src/utils/responseStats.js` (48 h Kulanz für offene Bewerbungen, Median-Antwortzeit, unter 3 Datenpunkten "New on platform"). Im Header als Kennzahl "Response Rate" + "Usually replies within …".

**✅ Umgesetzt (2026-11-16):** `GET /companies/:name` liefert `phone`/`email` (aus `Employer.companyPhone`/`companyEmail`), Kontaktzeilen sind antippbar (tel:/mailto:/https, `@handle` → Instagram).

## 15. Profile Screen — ✅ keine Lücke (grobe Prüfung)

Notion-Struktur ist hier mit Abstand am umfangreichsten (Worker: Basic Info/Location & Availability/Work Preferences/Experience & Skills/Ratings & Trust/Legal — Employer: Company Identity/Location & Workplaces/Contact & Communication/Company Preferences/Trust & Reputation/Legal & Compliance/Payment & Billing/Account Settings). Nicht jedes einzelne Unterfeld gegen `WorkerProfileView`/`EditProfileView`/`EditEmployerProfileView` nachverifiziert — laut CLAUDE.md und PRIORITIES.md (#5, #6 "alle neuen Worker-/Employer-Felder ergänzt") sollte das weitgehend abgedeckt sein, aber das ist die am wenigsten tief geprüfte Zeile in dieser Liste. Bei Bedarf gezielt nachprüfen.

## 16. Financial Overview — ⚠️ Lücke gefunden (Employer-Seite)

Code: `FinancialOverviewView.swift` (Worker) — Donut-Diagramm ✓, Zeitraum-Dropdown (This Month/Last 3 Months/This Year/All Time) ✓, Sparziel/Goal-Editor ✓. **Worker-Seite fehlt nur:** "Custom Range" als Dropdown-Option (CLAUDE.md verlangt sie, Code hat nur die 4 festen Optionen, keine Kalender-Range-Auswahl).

`EmployerFinancialView.swift` (Employer) — 3-Farben-Balkendiagramm (Upcoming/Completed/Paid Out) ✓, "View Breakdown"-Button ✓. **Fehlt komplett:** der Zeitraum-Dropdown selbst — kein `Picker`/`@State`-Feld für Periode gefunden, nur ein Text "No data for the selected period." ohne zugehörige Auswahl-UI. Das ist eine echte, verifizierte Lücke (Employer-Seite ist hier schwächer als Worker-Seite).

**✅ Umgesetzt (2026-11-16), beide Seiten:** Gemeinsamer Zeitraum-Picker (This Month / Last 3 Months / This Year / All Time / Custom Range mit Kalender-Sheet), gemeinsame Backend-Logik in `src/utils/period.js`. Employer-Diagramm passt sich dem Zeitraum an (Tage / Wochen / Monate). Nebenbei korrigiert: vergangene, nie abgeschlossene Jobs zählten im Diagramm als "Upcoming"; feste Zeiträume enden jetzt am Monats-/Jahresende. Offen: "Paid Out" ist beim Employer weiterhin immer 0 (TODO im Code).

## 17. Saved Screen — ✅ keine Lücke

Code: `SavedView.swift` (Worker) — Jobs/Companies-Tabs ✓, nach Datum gruppierte Jobs ✓, Companies-Liste ✓, Empty-State ✓. `SavedApplicantsView.swift` (Employer) existiert ebenfalls (nicht im Detail geprüft, war schon vorher laut CLAUDE.md als implementiert dokumentiert).

---

## Zusammenfassung — konkrete, code-verifizierte Lücken (ohne Add Job Screen, das schon oben steht)

| Screen | Lücke |
|---|---|
| Calendar (Worker) | ~~Open-Chat-Button, Payment-Status, Stornierungsgrund, Overlap-Warnung~~ ✅ umgesetzt 2026-11-16 |
| Chat | ~~Typing-Indicator, Online/Offline-Status, echte Read-Receipts~~ ✅ umgesetzt 2026-11-16 |
| Job Detail | ~~Share-Icon fehlt~~ ✅ umgesetzt 2026-11-16 |
| Company Profile | ~~"Employer response rate" fehlt~~ ✅ umgesetzt 2026-11-16 (gehörte zum Company-Profil, nicht zur Bewerber-Übersicht) |
| Settings | ~~2FA fehlt komplett; Active-Sessions-Liste hardcodiert~~ ✅ umgesetzt 2026-11-17 |
| Rating (Employer) | ~~Filter nach Job Category + Date Range fehlen~~ ✅ umgesetzt 2026-11-16 (offen: Drafts-Tab ist Platzhalter) |
| Company Profile | ~~Telefon + E-Mail fehlen~~ ✅ umgesetzt 2026-11-16 |
| Financial (Worker) | ~~Custom-Range-Option fehlt~~ ✅ umgesetzt 2026-11-16 |
| Financial (Employer) | ~~Zeitraum-Dropdown fehlt~~ ✅ umgesetzt 2026-11-16 |

**Nicht tief geprüft:** Profile Screen (Edit-Profile-Felder für Worker+Employer) — umfangreichste Notion-Struktur, nur grob verifiziert. Bei Bedarf gezielt nachprüfen.
