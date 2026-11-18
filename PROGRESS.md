# SwipeShift — iOS Frontend Progress

_Zuletzt aktualisiert: 2026-11-17 (Active Sessions + 2FA per E-Mail-Code)_

---

## ✅ Abgeschlossen

### Priorität 1 — RadarView (MapKit)
- `Models/Job.swift` — `lat`, `lng`, `payAmount`, `startTime`, `category` ergänzt
- `DTOs/JobDTO.swift` — selbe Felder + ISO8601 → Date Konvertierung
- `Features/Worker/Jobs/RadarView.swift` — vollständig neu mit MapKit:
  - Map (45% → 25% beim Scrollen, spring-Animation)
  - Farbige Pins: blau (default), orange (startet ≤5h), grün (payAmount ≥18)
  - Pin-Tap → hebt Job-Karte hervor + scrollt automatisch hin
  - `UserAnnotation`, Legende, "Zeige X Jobs"-Zähler, Filter-Button (TODO Radius)
  - Eigene `RadarJobCard` mit Highlight-Rahmen
- `Info.plist` — `NSLocationWhenInUseUsageDescription` ergänzt

### Priorität 2 — JobDetailView
- `Models/Job.swift` — 13 neue Detailfelder: `jobDescription`, `tasks`, `openSpots`, `duration`, `dressCode`, `languages`, `experienceLevel`, `minAge`, `paymentMethod`, `contractType`, `companyRating`, `replyTime`, `isVerified`
- `DTOs/JobDTO.swift` — selbe Felder + toDomain() aktualisiert
- `Features/Worker/Jobs/JobDetailView.swift` — vollständig neu:
  - Header (X, Bookmark, Logo, Verified Badge, Rating)
  - Quick-Info-Zeile (4 Spalten: Standort / Lohn / Dauer / Plätze)
  - Kategorie-Badge + Tags (FlowTagsView)
  - Stellenbeschreibung, Aufgaben (Checkliste), Anforderungen, Vergütung & Vertrag
  - Unternehmens-Sektion (Sterne, Reply-Zeit)
  - "Was passiert als Nächstes?" (3 Schritte)
  - Sticky Apply Bar (Preis + offene Plätze + Button)

### Priorität 3 — Apply Flow
- `Models/Job.swift` — `JobShift`-Modell + `shifts: [JobShift]?`
- `DTOs/JobDTO.swift` — `ShiftDTO` + `shifts` ergänzt
- `Features/Worker/Jobs/ApplyFlowView.swift` — neu erstellt:
  - Step 1: Schicht-Auswahl (Checkboxen, nur bei 2+ Schichten)
  - Step 2: Bestätigung (Job-Info, Schicht-Details, rechtlicher Hinweis)
  - Step 3: Ergebnis (5 Zustände: submitted / connectionLost / shiftAlreadyTaken / shiftUnavailable / schedulingConflict)
  - `PostJobConfirmSheet` → jetzt `ApplyConfirmationSheet` entfernt
- `Features/Worker/Jobs/JobDetailView.swift` — verknüpft mit `ApplyFlowView`

### Priorität 4 — Messages Tab (Worker)
- `Models/Conversation.swift` — `Conversation`, `ChatMessage`, `ConversationStatus`
- `Stores/MessageStore.swift` — `@MainActor ObservableObject`, Mock-Daten (today/upcoming/completed/cancelled), `markAsRead()`, `sendMessage()`, `unreadCount`
- `Features/Worker/Messages/MessagesView.swift` — Chat-Liste mit Sortierung, `ConversationRow`, `StatusBadge`, Leerzustand
- `Features/Worker/Messages/ChatView.swift` — Chat-Screen: System-Nachrichten, User/Employer-Blasen, Auto-Scroll, Read-only-Bar, Input-Feld
- `App/swipeShiftApp.swift` — `MessageStore` als `@StateObject` registriert
- `Features/Worker/Dashboard/WorkerHomeView.swift` — Messages-Placeholder ersetzt, Badge-Count an TabBar
- `UI/AppTabBar.swift` — unread-Badge beim Messages-Tab

### Priorität 5 — Employer Home View
- `UI/AppTabBar.swift` — `EmployerTab` enum + `EmployerTabBar` (5 Tabs)
- `Features/Employer/EmployerDashboardView.swift` — neu erstellt:
  - Header (Unternehmensname, Standort, Glocke)
  - Stats-Reihe (Active Jobs, Neue Bewerber, Monatl. Ausgaben)
  - Needs Attention (3 Alert-Cards mit Action-Buttons)
  - Quick Actions (Job ausschreiben, Alle Jobs)
  - Navigation (Job Management + Worker Management mit Badges)
  - Trends (4 Kacheln mit Delta-Indikatoren)
- `Features/Employer/EmployerHomeView.swift` — vollständig neu:
  - Tab-Container mit `EmployerTabBar`
  - Dashboard, Jobs, Applicants (Placeholder), Messages, Profile-Tab
  - Profile-Tab: Company-Logo, Verified Badge, Navigationsliste, Logout
- `App/ContentView.swift` — `messageStore` an `WorkerHomeView` + `EmployerHomeView` weitergegeben

### Priorität 6 — Post a New Job Screen
- `DTOs/PostJobDTO.swift` — `PostJobRequest` + `PostJobShiftRequest`
- `Networking/APIClient.swift` — `postJob()` ergänzt
- `Features/Employer/PostJobView.swift` — vollständiges Formular:
  - Grundinfos (Titel, Unternehmen vor-ausgefüllt, Standort)
  - Kategorie (Grid-Chips, Einfachauswahl)
  - Tags (4 Gruppen × Multi-Select-Chips)
  - Schichten (Datum + Start/End-DatePicker, Dauer auto-berechnet, + Schicht / × entfernen)
  - Mitarbeiter & Lohn (Stepper + Decimal-Eingabe)
  - Stellenbeschreibung (TextEditor)
  - Aufgaben (dynamische Liste)
  - Anforderungen (Dresscode, Sprachen, Mindestalter, Erfahrungslevel Radio)
  - Zahlung & Vertrag (Picker)
  - Sticky Footer: "Als Entwurf" + "Job veröffentlichen" (Validation)
  - `PostJobConfirmSheet` mit Bestätigung
- `Features/Employer/EmployerDashboardView.swift` — Quick Action verdrahtet
- `Features/Employer/EmployerHomeView.swift` — `showPostJob`-Sheet + `EmployerJobsTab`

---

## 🔜 Offen

### Nächste Schritte (Reihenfolge festgelegt 2026-04-03)

| # | Was | Status |
|---|-----|--------|
| 1 | Fix `POST /jobs/:id/apply` → 500 | ✅ Erledigt |
| 2 | AssignWorkers echte Daten (Shift-Model, Endpoint, iOS) | ✅ Erledigt |
| 3 | LeaveReviews echte Daten (Review-Model, Endpoint, iOS) | ✅ Erledigt |
| 4 | JobPayment echte Daten (Payment-Model, Endpoint, iOS) | ✅ Erledigt |
| 5 | Worker Calendar / Financials / Saved / Reviews (Backend + iOS) | ✅ Erledigt |
| 6 | Edit Profile speichern (`PATCH /auth/me` + iOS) | ✅ Erledigt |

---

### Priorität 7 — Worker Profile Screen
- `Features/Worker/Profile/WorkerProfileView.swift` — neu erstellt:
  - Profilbild (AsyncImage + Placeholder), Name, Verified Worker Badge, Sterne-Rating
  - Edit Profile Button → `EditProfileView`
  - Navigationsliste: Job Applications, Calendar, Financial Overview, Saved, Your Ratings, Settings, Account Settings, Help & Support
  - Logout mit `.alert`-Bestätigungs-Dialog
  - `SubScreenShell` — geteiltes Layout für alle Unter-Screens (Custom Back Button, SS.background)
  - `SettingsSupportView`, `AccountSettingsPlaceholderView`, `HelpSupportPlaceholderView` inline
- `Features/Worker/Profile/EditProfileView.swift` — neu erstellt:
  - Profilfoto-Bereich (TODO: ImagePicker)
  - Persönliche Daten (Vor-/Nachname, E-Mail, Telefon, Geburtsdatum)
  - Standort & Mobilität (Location, Relocation-Toggle, Max-Distanz, Transportmittel)
  - Verfügbarkeit (Wochentag-Toggles als Kreise, Same-day-Toggle)
  - Job Präferenzen (Kategorien als 2-Spalten-Grid)
  - Skills (Sterne-Rating: Communication, Teamwork, Reliability, Under Pressure)
  - Rechtliches (Checkbox-Toggles: Alter, Arbeitserlaubnis, AGB)
  - Bio (TextEditor, max 300 Zeichen)
  - Speichern-Button → TODO PUT /users/:id
- `Features/Worker/Profile/JobApplicationsView.swift` — neu erstellt:
  - Custom Tab-Selector: Confirmed / Applied / Completed / Cancelled (Capsule-Design)
  - `ApplicationCard` mit Status-Badge, Job-Infos, Withdraw-Button (Applied), Rate-Button (Completed)
  - Leerzustand wenn kein Job in der Kategorie
- `Features/Worker/Profile/WorkerCalendarView.swift` — neu erstellt:
  - Monat/Woche Toggle
  - Monatsansicht: Kalender-Grid mit Wochentag-Header, Tages-Zellen, Job-Dots (grün/grau), Navigation (</>)
  - Bevorstehende Jobs-Liste unterhalb des Grids
  - Wochenansicht: Horizontale Tages-Spalten (mit Job-Karten, Heute hervorgehoben)
- `Features/Worker/Profile/FinancialOverviewView.swift` — neu erstellt:
  - Zeitraum-Picker (Menu: This Month / Last 3 Months / This Year / All Time)
  - 3 Stats-Karten (Upcoming / Completed / Paid Out)
  - Donut-Chart via SwiftUI Canvas (ohne externen Framework)
  - Legende + Earning-Rows-Liste + "View Breakdown"-Button (TODO)
- `Features/Worker/Profile/ReviewsView.swift` — neu erstellt:
  - Gesamtbewertung + Sterne-Verteilungs-Balken
  - Skills Performance: Balken-Anzeige für 4 Skills
  - Review-Karten (max 3 initial, "Alle anzeigen" Toggle), inkl. Mini-Skill-Ratings
- `Features/Worker/Profile/SavedView.swift` — neu erstellt:
  - Tabs: Jobs / Companies
  - `SavedJobCard` (mit appliedStatus-Badge, Bookmark-Toggle)
  - Gruppierung nach savedAt-Datum
  - `SavedCompanyCard` (Verified Badge, Rating, offene Jobs, "Offene Jobs ansehen"-Button)
  - Leerzustand mit "Jobs durchsuchen"-Button
- `Features/Worker/Dashboard/WorkerHomeView.swift` — `ProfilePlaceholderView` → `WorkerProfileView()`

### RadarView Clustering
- `Features/Worker/Jobs/ClusterMapView.swift` — neu erstellt (UIViewRepresentable):
  - `JobAnnotation: MKAnnotation` — trägt Job + UIColor
  - `JobAnnotationView` — farbiger Kreis, `clusteringIdentifier = "job"` → MapKit clustert automatisch
  - `SelectedJobAnnotationView` — größerer Pin mit Pulsring, kein Clustering
  - `JobClusterAnnotationView` — Cluster-Kreis mit Anzahl + dominanter Farbe
  - `ClusterMapView.Coordinator: MKMapViewDelegate` — Pin-Tap → Callback, Cluster-Tap → Zoom rein, User-Interaktion schützt Kamera-Binding vor Überschreiben
- `Features/Worker/Jobs/RadarView.swift` — SwiftUI `Map` → `ClusterMapView`, `MapCameraPosition` → `MKCoordinateRegion`, `RadarPinView` entfernt

### Dashboard Backend-Filter
- `Networking/APIClient.swift` — `fetchJobs(location:type:category:)` — neue Parameter `type` und `category` als URLQueryItems
- `Stores/JobStore.swift` — 4 neue `@Published`: `recommendedJobs`, `quickMoneyJobs`, `startingSoonJobs`, `popularJobs`; `loadDashboardSections()` lädt alle 4 parallel mit `async let`
- `Features/Worker/Dashboard/WorkerHomeTabView.swift` — Sektionen nutzen echte Store-Arrays; `.task` ruft `loadJobs()` + `loadDashboardSections()` parallel
- `swipeshift-backend/src/routes.jobs.js` — `GET /jobs` unterstützt `?type=quickMoney|startingSoon|popular|recommended` und `?category=`:
  - `quickMoney`: startTime ≤ 4h + payAmount ≥ 15
  - `startingSoon`: startTime ≤ 48h, sortiert nach Datum
  - `popular`: sortiert nach openSpots absteigend (MVP)
  - `recommended`: sortiert nach payAmount absteigend (MVP)

### Swipe-Tab Redesign
- `Features/Worker/Jobs/JobSwipeView.swift` — vollständig neu:
  - Header: Titel + Job-Anzahl + Filter-Button (TODO)
  - Card-Stack: 3 Karten sichtbar (scale 0.91 / 0.96 / 1.0), Stacked-Effekt
  - Top-Karte: Drag mit Rotation, `interactiveSpring`-Animation
  - APPLY-Badge (grün, links, rotiert) bei Rechtswipe
  - SKIP-Badge (rot, rechts, rotiert) bei Linkswipe — Opacity proportional zur Drag-Distanz
  - SwipeJobCard: Header (Logo, Titel, Verified, Kategorie-Badge), Quick-Info-Pills (Ort/Lohn/Dauer), Beschreibung, Tags, Footer (Schichtzeit + offene Plätze)
  - Action-Bar: X (skip), Bookmark (save TODO), ✓ (apply) als Kreis-Buttons mit farbigem Shadow
  - Rechts-Swipe = apply, Links-Swipe = skip (Threshold 110pt)
  - `animateSwipe()`: Karte fliegt aus dem Bild (0.28s), dann wird Job aus Store entfernt
  - Leerzustand mit Sparkles-Icon + Aktualisieren-Button

### Company Profile Screen
- `Features/Worker/Company/CompanyProfileView.swift` — neu erstellt:
  - `CompanyProfile` Struct mit allen Feldern + `mock(name:logoEmoji:rating:)` Factory (TODO: GET /companies/:id)
  - Header: Logo mit Verified-Badge, Name, Location, Stats-Row (abg. Jobs / Rating / Bereiche)
  - Rating Tags: horizontale Chip-Leiste (Friendly Team, Fair Pay usw.)
  - About-Sektion: Fließtext + Business Areas als farbige Capsules
  - Ratings & Reviews Aufschlüsselung: 5 Kategorien als Balken (Communication, Payment Fairness, Work Environment, Job Description Accuracy, Overall Experience)
  - Review-Karten (max 2 initial, "Alle X Reviews" Toggle)
  - Standorte-Liste (HQ-Badge)
  - Kontakt (Telefon, E-Mail, Website)
  - "Offene Jobs ansehen" Button (NavigationLink → TODO: JobListView mit Company-Filter)
- `Features/Worker/Jobs/JobDetailView.swift` — companySection: Chevron-TODO → `NavigationLink` zu `CompanyProfileView` (unsichtbarer Overlay über die gesamte Karte)

### Bug Fix — Swipe-Tab Datenisolation
- `Stores/JobStore.swift` — `@Published var swipeJobs: [Job] = []` als eigener Array nur für Swipe-Tab; `loadSwipeJobs()` lädt in diesen Array; `apply(to:)` und `skip(_:)` entfernen **nur** aus `swipeJobs` (nicht `jobs`, `nearbyJobs` oder Dashboard-Sektionen)
- `Features/Worker/Jobs/JobSwipeView.swift` — alle Referenzen auf `jobStore.jobs` → `jobStore.swipeJobs`
- `Features/Worker/Jobs/RadarView.swift` — `.task` lädt nur wenn `nearbyJobs.isEmpty`, so bleiben Pins nach JobDetailView-Dismiss erhalten; Refresh-Button lädt immer neu

### Notifications Screen
- `Features/Worker/Notifications/NotificationsView.swift` — neu erstellt:
  - `NotificationCategory` enum (jobActivity / payments / messages / system) mit Icon + Farbe
  - `AppNotification` Struct mit `isRead: Bool`, `category`, `title`, `body`, `timestamp`
  - Filter-Bar: horizontale Chips (Alle + je Kategorie), `FilterChip` mit selected/unselected-State
  - "Alle als gelesen markieren"-Button (nur sichtbar wenn unread > 0)
  - `NotificationRow`: farbiger Kategorie-Icon-Kreis, Titel (fett wenn ungelesen), Body (2 Zeilen), relativer Zeitstempel, linke farbige Leiste für ungelesene, Ungelesen-Punkt oben rechts
  - 8 Mock-Benachrichtigungen über alle Kategorien verteilt
  - `Date.relativeLabel` Extension: relative Zeitanzeige (Gerade eben / vor X Min. / Std. / Tag(en))
  - Leerzustand: bell.slash Icon + Erklärungstext
- `Features/Worker/Dashboard/WorkerHomeTabView.swift` — Bell-Button → `NavigationLink` zu `NotificationsView`

### Account Settings Screen
- `Features/Worker/Profile/AccountSettingsView.swift` — neu erstellt:
  - **AccountSettingsView** — Hauptmenü mit 5 NavigationLinks (Account & Security, Notifications, Payments & Payouts, Privacy & Data, App Preferences)
  - **AccountSecurityView** — E-Mail/Telefon/Passwort ändern (je als Sheet), 2FA-Toggle, NavigationLink zu ActiveSessionsView
  - **ActiveSessionsView** — Liste der eingeloggten Geräte (Gerätename, Standort, letzte Aktivität, "Dieses Gerät"-Badge), Einzeln-Abmelden + "Von allen Geräten abmelden"-Button mit Bestätigung
  - **NotificationSettingsView** — Push + E-Mail Toggle pro Kategorie (Job Activity, Payments, Messages, Account), Ruhige-Stunden-Toggle mit DatePicker (von/bis)
  - **PaymentsPayoutsView** — Segment-Toggle Bankkonto/PayPal, IBAN oder PayPal-E-Mail Eingabe, Auszahlungsrhythmus (Sofort/Wöchentlich/Monatlich) als Radio-Buttons, Speichern-Button
  - **PrivacyDataView** — Datenschutz/AGB (TODO: URL öffnen), Konto-pausieren-Toggle mit Bestätigungs-Alert, "Konto löschen"-Button mit Bestätigungs-Alert
  - **AppPreferencesView** — Erscheinungsbild (System/Hell/Dunkel) mit Checkmarks, Sprache (Deutsch/English)
  - **ChangeEmailSheet**, **ChangePhoneSheet**, **ChangePasswordSheet** — native Form-Sheets mit Validierung
- `Features/Worker/Profile/WorkerProfileView.swift` — `AccountSettingsPlaceholderView` → `AccountSettingsView`

### Prisma Job-Model (Backend)
- `prisma/schema.prisma` — `Job`, `Apply`, `Skip`, `Save` Models ergänzt:
  - `Job`: alle App-Felder (title, company, location, lat/lng, payAmount, payText, startTime/endTime, shiftText, duration, shortInfo, jobDescription, tasks, openSpots, dressCode, languages, experienceLevel, minAge, paymentMethod, contractType, companyRating, replyTime, isVerified, tags, logoEmoji, category, status, employerId)
  - `shifts` als `Json` (Array von Schicht-Objekten)
  - `Apply`, `Skip`, `Save` mit `@@unique([userId, jobId])` → keine Duplikate
  - Relations: `Job` → `Apply[]`, `Skip[]`, `Save[]`
- Migration: `20260329231940_add_job_apply_skip_save` — angewendet auf PostgreSQL
- `prisma/seed.js` — 8 Job-Datensätze (alle bisherigen db.js-Jobs + Security Guard + Cleaning Staff + Customer Service Agent)
- `src/routes.jobs.js` — vollständig auf Prisma umgestellt:
  - `getSeenJobIds()` liest jetzt aus `Apply`/`Skip`-Tabellen (statt in-memory Arrays)
  - `GET /jobs` — `prisma.job.findMany()` mit `id: { notIn: seenIds }`, type-Filter als Prisma-Where-Clauses
  - `GET /jobs/nearby` — Prisma-Query + Haversine-Filterung clientseitig (lat/lng nicht in DB-Filter möglich)
  - `POST /jobs` — `prisma.job.create()`
  - `POST /jobs/:id/apply|skip|save` — `prisma.apply/skip/save.upsert()` mit `@@unique`-Key → idempotent

### Geocoding für POST /jobs (Backend)
- `src/utils/geocode.js` — neu erstellt: `geocodeLocation(location)` ruft OpenStreetMap Nominatim auf (kostenlos, kein API-Key), gibt `{ lat, lng }` oder `null` zurück
- `src/routes.jobs.js` — `POST /jobs` ruft `geocodeLocation(location)` auf bevor der Job gespeichert wird; `lat`/`lng` werden automatisch befüllt → Job erscheint im Radar

### All Posted Jobs Screen (Employer)
- `src/routes.jobs.js` — 3 neue Endpunkte:
  - `GET /jobs/mine` — alle Jobs des eingeloggten Arbeitgebers, inkl. `applicantCount`
  - `PATCH /jobs/:id/status` — Status ändern (published / draft / cancelled / completed / inProgress), nur eigene Jobs
  - `GET /jobs/:id/applicants` — Bewerber-Liste mit User-Daten für einen Job
- `Networking/APIClient.swift` — `fetchMyJobs()` und `updateJobStatus(jobId:status:)` ergänzt
- `Models/EmployerJob.swift` → `Features/Employer/AllPostedJobsView.swift` — neu erstellt:
  - `EmployerJob` Decodable-Struct mit `statusEnum` computed property
  - Tabs: Active / Draft / Completed / Past mit Zähler-Badges
  - `PostedJobCard`: Logo, Titel, Status-Badge, Standort, Schichtzeit, Stats-Zeile (Bewerber / Plätze / Lohn), Action-Buttons (Veröffentlichen / Stornieren) mit Bestätigungs-Alerts
  - Laden via `GET /jobs/mine`, Fehler- und Leerzustand
- `Features/Employer/EmployerHomeView.swift` — `EmployerJobsTab` Placeholder → `AllPostedJobsView`

### All Applicants Screen (Employer)
- `src/routes.employer.js` — neu erstellt mit 3 Endpunkten:
  - `GET /employer/applicants` — alle Bewerber über alle Jobs des Arbeitgebers, inkl. User-Daten + Worker-Foto + Job-Info
  - `POST /employer/applicants/:applyId/accept` — Bewerbung annehmen (MVP: Response-Flag, kein DB-Status-Feld)
  - `POST /employer/applicants/:applyId/decline` — Bewerbung ablehnen (löscht Apply-Eintrag aus DB)
- `src/index.js` — `/employer`-Router registriert
- `Networking/APIClient.swift` — `fetchApplicants()`, `acceptApplicant()`, `declineApplicant()` ergänzt
- `Features/Employer/AllApplicantsView.swift` — neu erstellt:
  - `Applicant`, `ApplicantUser`, `ApplicantJob` Decodable-Structs
  - Filter-Bar: Alle / Ausstehend / Angenommen / Abgelehnt mit Zähler
  - `ApplicantCard`: Avatar, Name, Standort, Status-Badge, Job-Info-Zeile, Accept/Decline-Buttons
  - Nach Aktion: Karte wird ausgegraut + Badge wechselt (lokaler State im MVP)
  - Leerzustand, Fehler-Retry
- `Features/Employer/EmployerHomeView.swift` — Applicants-Placeholder → `AllApplicantsView`

### Design — Primärfarbe Electric Blue
- `utils/Theme.swift` — `SS.primary` von Lila (#5B5CE6) zu Electric Blue (#2563EB) geändert; `bgTop`/`bgBottom` entsprechend angepasst

### Detailed Worker Screen (Employer)
- `Features/Employer/DetailedWorkerView.swift` — neu erstellt (vollständiges Worker-Profil für Arbeitgeber):
  - Header: Avatar (AsyncImage), Name, Verified Badge, Sterne-Rating (Mock 4.6 / 18 Jobs), Standort
  - Job-Sektion: "Bewirbt sich für" — Logo, Titel, Schicht, Lohn
  - Ratings & Reviews: 4 Skills als GeometryReader-Fortschrittsbalken (Communication, Teamwork, Reliability, Under Pressure)
  - Verfügbarkeit & Standort: Tage, Max-Distanz, Same-day
  - Work Experience: Kategorie + Erfahrungslevel mit Emoji-Icons
  - Job Preferences: bevorzugte Rollen, Schichten, Min-Stundenlohn
  - Legal & Compliance: Arbeitserlaubnis, Mindestalter, AGB — grüne Checkmarks
  - Sticky Footer: Ablehnen (rot, outline) + Annehmen (SS.primary) mit Bestätigungs-Alerts
  - Privater `sectionCard()` Helper, card-weißer Hintergrund auf SS.background-Gradient
- `Features/Employer/AllApplicantsView.swift` — `NavigationLink` um `ApplicantCard` ergänzt → öffnet `DetailedWorkerView`

### Leave Reviews Screen (Arbeitgeber)
- `Features/Employer/LeaveReviewsView.swift` — neu erstellt:
  - **3 Tabs**: Pending (ausstehend) / Drafts / Past Reviews mit Zähler-Badges
  - **Sort Sheet**: Most Recent / Highest Rating / Lowest Rating (Radio, schließt automatisch)
  - **Filter Sheet**: Mindestbewertung (1–5 Sterne Chips) + Would Rehire (Ja/Nein) mit Apply/Cancel Footer
  - Aktiver Sort/Filter: Punkt-Indikator + "Zurücksetzen"-Button
  - **PendingReviewCard**: Worker-Info (Name, Emoji, Job, Datum) + "Bewertung abgeben"-Button
  - **PastReviewCard**: Header + mini 5-Sterne-Reihen für alle 4 Skills + Kommentar + Would-Rehire Indikator
  - **ReviewFormSheet** (native Sheet):
    - Worker-Info Header
    - 4 Skill-Bewertungen via tippbare Sterne (Communication, Teamwork, Reliability, Under Pressure)
    - "Würde wieder einstellen?" Toggle
    - Kommentar TextEditor (max 600 Zeichen mit Zähler)
    - Speichern-Button (disabled bis alle 4 Skills bewertet)
  - `ReviewDraft.avgRating` computed (Ø aller 4 Skills)
  - Mock-Daten (3 ausstehende Bewertungen)
- `Features/Employer/EmployerDashboardView.swift` — "Bewertungen abgeben" NavRow → `navigationDestination` zu `LeaveReviewsView`

### Assign Workers Screen (Arbeitgeber)
- `Features/Employer/AssignWorkersView.swift` — neu erstellt:
  - **Filter-Chips**: Alle / Offen / Besetzt
  - **JobAssignCard** — ausklappbar pro Job:
    - Header: Logo-Emoji, Titel, Standort, Staffing-Badge (Anzahl offen / vollständig besetzt)
    - Expandiert: Liste aller Schichten
  - **Schicht-Reihe** — ausklappbar pro Schicht:
    - Datum (Heute/Morgen/Wochentag), Startzeit–Endzeit
    - Staffing-Pillen: grüne/graue Mini-Rechtecke pro Slot + "X offen" / "Vollständig" Label
    - Expandiert: Liste der zugewiesenen Mitarbeiter
  - **Worker-Reihe**: Avatar-Emoji, Name, Sterne-Rating, ×-Button zum Entfernen (mit Animation)
  - "Mitarbeiter hinzufügen"-Button (TODO: Bewerber-Liste für Schicht öffnen)
  - Mock-Daten: 3 Jobs mit mehreren Schichten und teils zugewiesenen Mitarbeitern
- `Features/Employer/EmployerDashboardView.swift` — "Mitarbeiter zuweisen" NavRow → `navigationDestination` zu `AssignWorkersView`

### Financial Overview Screen (Arbeitgeber)
- `Features/Employer/EmployerFinancialView.swift` — neu erstellt:
  - **Period Picker**: Menu (This Month / Last 3 Months / This Year / All Time)
  - **Summary Grid** (2×2): Total Spending, Upcoming Payments, Completed Jobs, Paid Out
  - **Stacked Bar Chart** (Canvas-frei, SwiftUI): 7 Tages-Balken, je 3 Segmente (Upcoming=orange / Completed=blue / Paid Out=teal), Legende oben
  - **Payment List**: Worker-Name, Job, Stunden × Stundenlohn, Paid/Ausstehend-Badge
  - **View Breakdown Sheet** (modal): Segment-Toggle (Nach Status / Nach Kategorie), Balken-Zeilen mit Fortschrittsbalken + €-Betrag
- Eingehängt: Dashboard-StatCard "Monatl. Ausgaben" → `EmployerFinancialView`; Profile-Tab "Financial Overview" → `EmployerFinancialView`

### AssignWorkers — echte Daten

- `prisma/schema.prisma` — `Apply.status String @default("pending")` + `Apply → User`-Relation ergänzt; Migration `add_apply_user_relation` angewendet
- `src/routes.employer.js`:
  - `POST /employer/applicants/:id/accept` → setzt `status = "accepted"` (statt No-Op)
  - `POST /employer/applicants/:id/decline` → setzt `status = "declined"` (statt Delete)
  - `POST /employer/applicants/:id/unassign` → setzt `status = "pending"` (neu)
  - `GET /employer/assigned-workers` → gibt Jobs mit `openSpots`, `shifts` (JSON) und `assignedWorkers` (accepted applies) zurück (neu)
  - `GET /employer/applicants` → gibt echten `status` zurück (statt hardcoded "pending")
- `Networking/APIClient.swift` — `fetchAssignedWorkers()` + `unassignWorker(applyId:)` ergänzt
- `Features/Employer/AssignWorkersView.swift` — komplett neu:
  - DTOs: `AssignableJobDTO`, `ShiftSlotDTO`, `AssignedWorkerDTO`
  - Lädt via `APIClient.shared.fetchAssignedWorkers()` in `.task`
  - Filter-Chips: All / Open / Staffed
  - `JobAssignCard`: ausklappbar, zeigt Schichten (read-only aus JSON) + zugewiesene Worker
  - Unassign-Button → `APIClient.shared.unassignWorker()` + optimistischer UI-Update
  - Lade- und Fehlerzustand

### DB-User bereinigt — Emails & Passwörter

- Alle Passwörter (außer Google-Account `kevinowusu14@gmail.com`) auf `Passwort1` gesetzt
- Emails nach Rolle strukturiert:
  - Workers: `worker1@example.de`, `worker2@example.de`, `worker3@example.de`
  - Employers: `emp1@example.de` bis `emp6@example.de`
  - Google-Account bleibt unverändert: `kevinowusu14@gmail.com`
- Seed-Script (`prisma/seed.js`) ebenfalls auf `Passwort1` und `@swipeshift.test`-Schema aktualisiert

### Seed-Daten erweitert — echte Firmen & Employer-User

- `prisma/seed.js` — komplett neu:
  - **5 Employer-User** (mit Employer-Profil via Relation): EventPro GmbH, LogiSpeed GmbH, RetailGroup AG, Brew & Co., CleanPro Services
  - **2 Worker-User** zum Testen (Stuttgart + Hamburg)
  - **16 Jobs** mit echtem `employerId` — alle Kategorien abgedeckt: Events, Hospitality, Logistics, Retail, Customer Service, Office, Cleaning
  - Jobs haben je **2–6 echte Schichten** (JSON) → Apply-Flow mit Schicht-Auswahl testbar
  - Pay-Spanne €12–€24/h → quickMoney- und High-Pay-Filter greifen
  - Start-Zeiten: heute +2h, heute +4h, morgen, +2 Tage, +3 Tage → startingSoon-Filter greift
  - Passwort für alle Test-User: `Test1234!`
  - Seed löscht nur `@swipeshift.test`-User → bestehende Produktiv-Accounts bleiben erhalten

### Fix — POST /jobs/:id/apply → 500

- `prisma/schema.prisma` — `Conversation.employerId` von `String` auf `String?` (nullable) geändert
- Migration `make_conversation_employer_id_nullable` angewendet
- `src/routes.jobs.js` — `job.employerId ?? "unknown"` → `job.employerId ?? null`
- **Ursache**: Seed-Jobs haben `employerId: null`; non-nullable Feld + `"unknown"` String führte zum Crash im `$transaction`
- **Verhalten**: Worker sehen ihre Conversations (`workerId`-Filter); Employer sehen nur Conversations zu ihren eigenen Jobs (`employerId`-Filter) — Seed-Jobs ohne Employer tauchen dort nicht auf (korrekt)

### Mock-Daten entfernt — echte DB-Anbindung

- **Google Sign-In Fix** — `GIDSignIn.sharedInstance.handle(url)` in `swipeShiftApp.swift` ergänzt; war die Ursache für stillen Sign-In-Fehler
- **Set Password für Social-User** — `POST /auth/set-password` Endpoint + `SetPasswordSheet` in `AccountSettingsView`; Social-User (Google/Apple) können erstmals ein Passwort setzen
- **`hasSocialLogin`-Flag** — Login, Google-Auth, Apple-Auth und `/me` geben `hasSocialLogin: true/false` zurück; iOS zeigt "Passwort setzen" statt "Passwort ändern"
- **`lat`/`lng` in Login-Response** — Prisma-Select in Login-Route hatte `lat`/`lng` nicht, Radar zeigte deshalb keine Jobs → behoben
- **Messaging-Backend komplett neu** — `Conversation`- und `Message`-Modell in Prisma (Migration `20260402114545`); `POST /jobs/:id/apply` legt automatisch eine Conversation + System-Nachricht an; `routes.messages.js` mit `GET /messages`, `POST /messages/:id`, `PATCH /messages/:id/read`
- **`MessageStore`** — alle Mock-Daten entfernt; lädt via `APIClient.shared.fetchConversations()`; optimistisches Senden mit Server-ID-Ersatz
- **Company Profile** — Mock-Factory `CompanyProfile.mock()` entfernt; `routes.companies.js` (`GET /companies/:name`) aggregiert echte Job- und Employer-Daten aus DB; `CompanyProfileView` lädt live
- **Employer Financial Overview** — alle hardcodierten Stats/Chart/Payment-Daten entfernt; `GET /employer/financials` liefert echte Prisma-Aggregationen; `EmployerFinancialView` vollständig neu an DB angebunden
- **`AssignWorkersView`** — Mock-Jobs-Array entfernt, zeigt leeren Zustand (TODO: `GET /employer/jobs/:id/shifts`)
- **`LeaveReviewsView`** — Mock-Reviews-Array entfernt, zeigt leeren Zustand (TODO: `GET /employer/reviews/pending`)
- **`JobPaymentView`** — Mock-Factory entfernt, `workers: []` bis Backend-Endpoint existiert

### Calendar Screen (Arbeitgeber)
- `Features/Employer/EmployerCalendarView.swift` — neu erstellt:
  - **Controls**: Monat/Woche Toggle-Pill + Filter-Menu (All Jobs / Needs Workers / Fully Staffed)
  - **Monatsansicht**:
    - Navigierbar (</>), Wochentag-Header (Mo–So)
    - Tages-Zellen: Heute hervorgehoben, ausgewählt Tag mit weißem Kreis, orange Punkt bei Jobs
    - Jobs-Liste für ausgewählten Tag unterhalb des Grids
  - **Wochenansicht**:
    - Horizontale Tages-Spalten mit Heute-Kreis
    - Zeitstrahl 06:00–02:00 (56pt pro Stunde)
    - Farbige Job-Blöcke per `offset(y:)` korrekt platziert (orange=Needs Workers, blau=Partial, grün=Fully Staffed)
  - **ShiftStatus** enum mit Farbe + Label (needsWorkers/partiallyStaffed/fullyStaffed)
  - **EmployerCalJobCard**: Status-Stripe, Logo, Titel, Zeit, Standort, "X/Y"-Staffing-Anzeige
  - Mock-Daten: 8 Jobs über 2 Wochen verteilt
- Eingehängt: Profile-Tab "Kalender" → `EmployerCalendarView`; Dashboard `navigationDestination` registriert

### Employer Calendar — echte Daten (2026-06-01)
- `src/routes.employer.js` — `GET /employer/calendar` neu:
  - Gibt Jobs des Arbeitgebers zurück (status: published/inProgress/completed, startTime not null)
  - Pro Job: id, title, location, logoEmoji, startTime, endTime, openSpots, assignedCount (accepted applies)
- `Networking/APIClient.swift` — `fetchEmployerCalendar() -> [EmployerCalendarJobDTO]` ergänzt
- `Features/Employer/EmployerCalendarView.swift` — vollständig auf echte Daten umgestellt:
  - `EmployerCalendarJobDTO: Identifiable, Decodable` als neues Struct (oben in der Datei)
  - `EmployerCalJob.init(dto:)` — leitet `date`, `startHour`, `durationHours`, `openSpots`, `totalSpots` aus DTO ab
  - Mock-Jobs-Array entfernt; lädt via `APIClient.shared.fetchEmployerCalendar()` in `.task`
  - `isLoading`-State + ProgressView während Laden

### Mockup-Review — Neue Prioritätenliste (2026-05-29)

Alle Mockup-Images analysiert (15 Dateien), neue Lücken identifiziert und implementiert:

| # | Was | Status |
|---|-----|--------|
| 1 | Worker Calendar — echte Daten (mock → API) | ✅ Erledigt |
| 2 | Notifications — echte Daten (Worker + Employer) | ✅ Erledigt |
| 3 | Employer Saved Applicants (Save/Unsave, Liste) | ✅ Erledigt |
| 4 | Worker Financial "Step to Target" (Einkommensziel) | ✅ Erledigt |

### Worker Calendar — echte Daten
- `Features/Worker/Profile/WorkerCalendarView.swift` — Mock-Jobs entfernt:
  - Lädt via `APIClient.shared.fetchWorkerApplications()` in `.task`
  - Filtert `cancelled` + `completed` heraus
  - Konvertiert `WorkerApplicationItem` → `CalendarJob` (mit `ApplicationStatus` Mapping)
  - Weekday-Header auf Englisch übersetzt (Mo/Di/Mi → Mo/Tu/We)
  - "Bevorstehende Jobs" → "Upcoming Jobs"

### Notifications — echte Daten
- `src/routes.notifications.js` — neu erstellt (dynamische Notifications, kein DB-Model):
  - **Worker**: accepted applies + reviews received + paid applies
  - **Employer**: pending applicants + reviews to leave (completed jobs ohne Review)
  - Sortiert nach timestamp absteigend
- `src/index.js` — `/notifications`-Router registriert
- `DTOs/NotificationDTO.swift` — neu: `NotificationDTO` mit id, category, title, body, timestamp
- `Networking/APIClient.swift` — `fetchNotifications()` ergänzt
- `Features/Worker/Notifications/NotificationsView.swift` — vollständig auf echte Daten umgestellt:
  - `AppNotification` — `id` von `UUID` auf `String` geändert; `init(dto:)` hinzugefügt
  - `NotificationCategory` — `.reviews` Case + `from(_ raw:)` Factory ergänzt
  - Mock-Daten entfernt; lädt via `fetchNotifications()` in `.task`
  - "Alle als gelesen markieren" + relative Zeitangaben auf Englisch

### Employer Saved Applicants
- `prisma/schema.prisma` — `SavedApplicant`-Model + `Apply.savedApplicant`-Relation; Migration `20260529154913_add_saved_applicant`
- `src/routes.employer.js` — 3 neue Endpunkte:
  - `POST /employer/applicants/:applyId/save` — Bewerber speichern (upsert)
  - `DELETE /employer/applicants/:applyId/save` — Bewerber entfernen
  - `GET /employer/saved-applicants` — alle gespeicherten Bewerber mit Worker+Job-Info
- `Networking/APIClient.swift` — `saveApplicant()`, `unsaveApplicant()`, `fetchSavedApplicants()` ergänzt
- `Features/Employer/SavedApplicantsView.swift` — neu erstellt:
  - `SavedApplicantItem` Decodable-Struct
  - Liste + Leerzustand + Unsave-Button per Karte
- `Features/Employer/AllApplicantsView.swift` — Bookmark-Icon an ApplicantCard ergänzt
- `Features/Employer/EmployerHomeView.swift` — "Saved Applicants" NavRow + `navigationDestination`

### Chat Auto-Refresh (Polling) — B1 aus TODO-Audit (2026-07-24)
- `swipeshift-backend/src/routes.messages.js` — `GET /messages/:conversationId` neu: gibt Nachrichten einer Conversation zurück; `?since=<ISO8601>` filtert auf neuere Nachrichten; Teilnehmer-Check (403 wenn nicht workerId/employerId)
- `Networking/APIClient.swift` — `fetchMessages(conversationId:since:)` ergänzt (ISO8601-Encoding des since-Parameters)
- `Stores/MessageStore.swift` — `refreshMessages(conversationId:isEmployerMode:)`:
  - Letzten echten Timestamp ermitteln (optimistic-Prefix ausschließen)
  - Nur neue Nachrichten per `since`-Filter holen
  - Bereits bekannte IDs herausfiltern → nur wirklich neue Nachrichten appenden
  - `appendMessages()` privater Helper aktualisiert zusätzlich `lastMessage`/`lastMessageTime`
- `Features/Worker/Messages/ChatView.swift` — `.task(id: conversation.id)`:
  - Startet nicht bei read-only (completed/cancelled)
  - 10-Sekunden-Intervall via `Task.sleep(for: .seconds(10))`
  - Task wird automatisch gecancelt wenn View verschwindet (SwiftUI structured concurrency)
  - Neue Nachrichten erscheinen sofort durch `@Published`-Update im Store

### Saved Companies (Worker) — A4 aus TODO-Audit (2026-07-24)
- `prisma/schema.prisma` — `SavedCompany`-Model ergänzt (userId, companyName, savedAt, @@unique, Cascade-Delete); `User.savedCompanies`-Relation; Migration `20260724095918_add_saved_company` angewendet
- `src/routes.worker.js` — 3 neue Endpoints:
  - `GET /worker/saved-companies` — Liste mit Anreicherung (logoEmoji, rating, openJobs) via Promise.all
  - `POST /worker/saved-companies` — upsert (idempotent)
  - `DELETE /worker/saved-companies/:name` — URL-kodierter Name
- `DTOs/MessageDTO.swift` — `SavedCompanyItem` Struct (id, companyName, logoEmoji, isVerified, openJobs, rating, savedAt)
- `Networking/APIClient.swift` — `fetchSavedCompanies()`, `saveCompany(name:)`, `unsaveCompany(name:)`
- `Features/Worker/Profile/WorkerProfileView.swift` — `SubScreenShell` um zweiten Init erweitert (`trailing: () -> T` via `AnyView`-Slot), alle bestehenden Aufrufe unverändert
- `Features/Worker/Company/CompanyProfileView.swift` — `isSaved`/`isSaveLoading`-State; `bookmarkButton` computed prop; `load()` lädt isSaved parallel; `toggleSave()` optimistisch
- `Features/Worker/Profile/SavedView.swift` — `savedCompanies: [SavedCompanyItem]`-State; `onChange(selectedTab)` lädt jeweils; `savedCompaniesList` + `SavedCompanyCard` (Logo, Verified, Rating, Open Jobs, Unsave-Button)

### CategoryJobListView: Backend-Filter — A2 aus TODO-Audit (2026-07-24)
- `Features/Worker/Jobs/CategoryJobListView.swift` — komplett umgeschrieben:
  - `@EnvironmentObject var jobStore` + client-seitiger Filter entfernt
  - Eigener `@State jobs: [Job]`, `isLoading`, `errorMessage`
  - `.task { await load() }` ruft `APIClient.shared.fetchJobs(category: category.name)` auf → `GET /jobs?category=Hospitality`
  - Lade- und Fehlerzustand ergänzt; Retry-Button bei Fehler
  - `@EnvironmentObject` nicht mehr nötig (kein `jobStore`-Inject mehr erforderlich)

### Profilfoto-Upload Worker — A1 aus TODO-Audit (2026-07-24)
- `DTOs/AuthDTO.swift` — `UpdateProfileRequest` um `profilePhotoUrl: String?` ergänzt (Feld + init-Parameter)
- `Features/Worker/Profile/EditProfileView.swift` — `save()`: wenn `selectedImage != nil`, wird erst `APIClient.shared.uploadProfilePhoto(img)` aufgerufen; zurückgegebene URL wird als `profilePhotoUrl` an `updateProfile()` übergeben
- `swipeshift-backend/src/routes.me.js` — `PATCH /auth/me`: `profilePhotoUrl` in Destructuring + Worker-Update ergänzt; wird jetzt in `Worker`-Tabelle persistiert

### Worker Financial — Step to Target
- `Features/Worker/Profile/FinancialOverviewView.swift`:
  - `@State incomeGoal: Double` — persistiert in `UserDefaults` (Key: `incomeGoal`, Default: 2000)
  - `stepToTargetSection` — neuer Abschnitt zwischen Donut und Earnings:
    - Fortschrittsbalken (blau = in progress, grün = Ziel erreicht)
    - "€X earned" + "€X to go" / "Goal reached!" Label
    - Bearbeitungs-Button → `GoalEditorSheet`
  - `GoalEditorSheet` — native Form-Sheet mit DecimalPad-Eingabe + Save/Cancel

### Worker bewertet Employer (2026-06-01)
- `prisma/schema.prisma` — `WorkerReview`-Model + `Apply.workerReview`-Relation; Migration `20260601084140_add_worker_review`
- `src/routes.worker.js` — `POST /worker/reviews`: Worker bewertet Arbeitgeber (5 Kategorien + Kommentar); upsert → idempotent
- `src/routes.companies.js` — `GET /companies/:name` erweitert:
  - `workerReviews` (Promise.all parallel query, max 10) inkl. Worker-Name aus User-Relation
  - `reviewBreakdown` (Ø der 5 Kategorien + totalReviews)
  - `rating` nutzt jetzt `overallExperience`-Ø aus WorkerReviews (Fallback: job.companyRating)
- `DTOs/MessageDTO.swift` — `ReviewBreakdownDTO` + `WorkerReviewDTO` (mit Date); `CompanyProfileDTO` erweitert um `reviewBreakdown` + `workerReviews`
- `Networking/APIClient.swift` — `EmployerReviewRequest` Encodable-Struct + `submitEmployerReview()` ergänzt; `fetchCompany()` nutzt ISO8601-Decoder
- `Features/Worker/Company/EmployerRatingSheet.swift` — neu erstellt:
  - 5 Stern-Kategorien: Communication, Payment Fairness, Work Environment, Job Description Accuracy, Overall Experience
  - Interaktive Sterne-Buttons (1–5) mit Label (Poor/Fair/Good/Great/Excellent)
  - Optionaler Kommentar (max 400 Zeichen, Zähler)
  - Submit-Button disabled bis alle 5 Kategorien bewertet; Lade-State; Fehler-Anzeige
  - Nach Erfolg: Callback + dismiss()
- `Features/Worker/Profile/JobApplicationsView.swift` — "Leave a Review"-Button verdrahtet:
  - `@State showRatingSheet` + `hasReviewed` pro Karte
  - Nach Submit: Button wechselt zu "Review Submitted" (grau, disabled)
- `Features/Worker/Company/CompanyProfileView.swift` — `ratingsSection()` komplett ersetzt:
  - Gesamtbewertung + 5 Kategorie-Fortschrittsbalken (GeometryReader) wenn `reviewBreakdown` vorhanden
  - Leerzustand "No reviews yet" wenn kein Rating
  - Einzelne Review-Karten mit Avatar (Initialbuchstabe), Name, Sterne, Datum, Kommentar
  - "View all X reviews" Toggle (max 2 initial, ausklappbar)

### WorkerProfileView: echte Daten (2026-06-01)
- `Features/Worker/Profile/WorkerProfileView.swift`:
  - `@State rating` + `reviewCount` statt statischer Konstanten
  - `.task` lädt `fetchWorkerReviews()` → `overallRating` + `totalJobs`
  - Leerzustand "No reviews yet" wenn `reviewCount == 0`

### AccountSettings: Backend-Endpunkte verdrahtet (2026-06-01)
- `src/routes.auth.js` — 3 neue Endpoints:
  - `POST /auth/change-password` — verifiziert altes Passwort, setzt neues
  - `PATCH /auth/me/email` — verifiziert Passwort, prüft Duplikat, updated Email + schickt Verifikations-Mail
  - `DELETE /auth/me` — löscht Account mit Cascade
- `Networking/APIClient.swift` — `changePassword()`, `changeEmail()`, `deleteAccount()` ergänzt
- `Features/Worker/Profile/AccountSettingsView.swift`:
  - `ChangeEmailSheet` — loading + error state + success Alert, ruft `changeEmail()` auf
  - `ChangePhoneSheet` — ruft `updateProfile(phone:)` auf
  - `ChangePasswordSheet` — loading + error state + success Alert, ruft `changePassword()` auf
  - `ActiveSessionsView` — "Sign out of all devices" löscht Token + `userStore.logout()`
  - `PaymentsPayoutsView` — Save speichert in UserDefaults
  - `PrivacyDataView` — Privacy Policy + Terms via `openURL`; Delete Account ruft `deleteAccount()` + logout; Pause Account via UserDefaults

### EmployerDashboardView: Bell → NotificationsView (2026-06-01)
- `Features/Employer/EmployerDashboardView.swift` — `@State showNotifications` + Bell-Button verdrahtet
- `.sheet(isPresented: $showNotifications)` → `NavigationStack { NotificationsView() }`

### JobSwipeView: Bookmark + Filter verdrahtet (2026-06-01)
- `Networking/APIClient.swift` — `saveJob(jobId:)` ergänzt (`POST /jobs/:id/save`)
- `Features/Worker/Jobs/JobSwipeView.swift`:
  - Filter-Button öffnet `FilterSheet` (Kategorie-Chips); oranger Dot-Indikator bei aktivem Filter
  - `filteredSwipeJobs` — lokaler Kategorie-Filter über `jobStore.swipeJobs`
  - Bookmark-Button ruft `saveJob(jobId:)` auf; Icon wechselt optimistisch zu `bookmark.fill`
  - Skip/Apply-Buttons nutzen `topJob` (filterbewusst)

### ChatView: Info-Button → JobDetailView verdrahtet (2026-06-01)
- `prisma/schema.prisma` / Backend: kein Schema-Change nötig (jobId war bereits in Apply/Conversation)
- `src/routes.jobs.js` — `GET /jobs/:id` hinzugefügt (nach `/mine`, vor `/:id/applicants`)
- `Models/Conversation.swift` — `jobId: String` hinzugefügt
- `DTOs/MessageDTO.swift` — `jobId` in `toDomain()` weitergegeben
- `Networking/APIClient.swift` — `fetchJob(jobId:)` ergänzt
- `Features/Worker/Messages/ChatView.swift`:
  - `@State jobDetailJob: Job?` + `loadingJobDetail: Bool`
  - Info-Button: fetcht `GET /jobs/:id`, zeigt `ProgressView` während Laden
  - `.sheet(item: $jobDetailJob)` → `NavigationStack { JobDetailView(job:) }`

### AssignWorkers — Mitarbeiter hinzufügen (2026-06-01)
- `src/routes.jobs.js` — `GET /jobs/:id/applicants` erweitert:
  - `?status=` Query-Parameter-Filter (z.B. `?status=pending`)
  - Gibt `status`, `workerName`, `profilePhotoUrl`, `rating` (aus Reviews aggregiert), `location` zurück
- `Features/Employer/AssignWorkersView.swift` — `AddWorkerSheet` hinzugefügt:
  - `JobApplicantDTO` + `JobApplicantsResponse` DTOs
  - "Add Worker"-Button öffnet `AddWorkerSheet` via `.sheet`
  - `AddWorkerSheet`: lädt pending Bewerber via `fetchPendingApplicantsForJob(jobId:)`, zeigt Avatar, Name, Rating, Standort
  - "Assign"-Button ruft `acceptApplicant(applyId:)` auf, fügt Worker optimistisch zur Liste hinzu, entfernt Bewerber aus Sheet
  - Schließt automatisch wenn alle Bewerber zugewiesen
- `Networking/APIClient.swift` — `fetchPendingApplicantsForJob(jobId:)` ergänzt

### C-Prios: Popular / Recommended / Apply Error Codes (2026-07-24)

**C1 — "Popular This Week": Sort by Apply Count**
- `swipeshift-backend/src/routes.jobs.js` — `popular`-Branch: `orderBy: { openSpots: "desc" }` → `orderBy: { applies: { _count: "desc" } }` (Prisma relation count sort)

**C2 — "Recommended for You": Category Matching**
- `swipeshift-backend/src/routes.jobs.js` — `recommended`-Branch:
  - Lädt `Worker.preferredCategories` für den aktuellen User
  - Alle Jobs nach `payAmount DESC` holen
  - Partitioniert: matching Jobs zuerst, dann der Rest (beide Gruppen payAmount-sortiert)
  - Kein Einfluss auf andere Typen

**C3 — Apply Flow: Strukturierte Error Codes**
- `swipeshift-backend/src/routes.jobs.js` — `POST /jobs/:id/apply`:
  - `job.status !== "published"` → HTTP 400 `{ error: "JOB_UNAVAILABLE" }`
  - `job.openSpots <= 0` → HTTP 409 `{ error: "SHIFT_TAKEN" }`
  - Scheduling-Konflikt (accepted Apply für überlappende Zeit) → HTTP 409 `{ error: "SCHEDULING_CONFLICT" }`
- `Networking/APIClient.swift` — `ApplyError` enum (shiftTaken / jobUnavailable / schedulingConflict) + `apply(jobId:)` parst HTTP-Fehlerantwort und wirft typisierten Fehler
- `Stores/JobStore.swift` — `apply(to:)` jetzt `throws` (rethrowt `ApplyError`)
- `Features/Worker/Jobs/ApplyFlowView.swift` — `submitApplication()`: fängt `ApplyError` und mappt auf korrekte `ApplyResult`-States (shiftAlreadyTaken / shiftUnavailable / schedulingConflict); generische Netzwerkfehler → connectionLost
- `Features/Worker/Jobs/JobSwipeView.swift` — Swipe-Tap nutzt `try? await` (stille Fehler bei Swipe gewollt)

### Employer Profilfoto-Upload — B4 aus TODO-Audit (2026-07-24)
- `DTOs/AuthDTO.swift` — `UpdateEmployerProfileRequest` um `profilePhotoUrl: String?` ergänzt
- `swipeshift-backend/src/routes.employer.js` — `PATCH /employer/profile`: `profilePhotoUrl` in Destructuring + `employerUpdate.companyLogoUrl = profilePhotoUrl` ergänzt (Feld existiert bereits in Prisma-Schema als `Employer.companyLogoUrl`)
- `Features/Employer/EditEmployerProfileView.swift` — `CompanyInfoTab.save()`:
  - Wenn `selectedLogo != nil`: `APIClient.shared.uploadProfilePhoto(img)` aufgerufen, URL zurückgegeben
  - URL als `profilePhotoUrl` an `UpdateEmployerProfileRequest` übergeben
  - `PersonalProfileTab.save()` übergibt `profilePhotoUrl: nil` (kein Foto-Tab dort)
- `/me`-Response gibt `companyLogoUrl` bereits zurück → Logo erscheint nach `refreshMe()` sofort

### Help & Support Buttons — B3 aus TODO-Audit (2026-07-24)
- `Features/Worker/Profile/WorkerProfileView.swift` — `HelpSupportPlaceholderView`:
  - `@Environment(\.openURL)` ergänzt
  - Guide → `openURL("https://swipeshift.app/guide")`
  - Live Chat → `openURL("mailto:support@swipeshift.app")`
  - Terms & Conditions → `openURL("https://swipeshift.app/terms")` (konsistent mit `PrivacyDataView`)
  - Privacy Policy → `openURL("https://swipeshift.app/privacy")` (konsistent mit `PrivacyDataView`)

### JobListView: Distance Filter — B2 aus TODO-Audit (2026-07-24)
- `Features/Worker/Jobs/JobListView.swift`:
  - `haversineKm(lat1:lng1:lat2:lng2:)` free function — client-seitige Erdradius-Berechnung (6371 km)
  - `JobFilterOptions.maxDistance: Double?` — TODO-Kommentar entfernt, vollständig aktiviert
  - `hasActiveFilter` — schließt `maxDistance != nil` ein (Filter-Button leuchtet bei aktivem Distanz-Filter)
  - `userLat` / `userLng` — computed props aus `userStore.currentUser`
  - `distanceKm(to:)` — gibt nil wenn Koordinaten fehlen (graceful fallback)
  - `displayedJobs` Schritt 3 — wendet `maxDistance`-Filter an; Jobs ohne Koordinaten werden eingeschlossen
  - `displayedJobs` Schritt 5 — `.distance`-Sortierung nutzt `distanceKm(to:)` mit `.greatestFiniteMagnitude` als Fallback
  - `FilterSheet` — Distanz-Sektion mit "Any"-Chip + 5/10/15/20/25 km Chips oberhalb der Kategorie-Chips

### Chat Presence — Typing, Online-Status, Lesebestätigungen (2026-11-16)
Lücke aus dem Field-Audit (`reports/app-tracker-field-audit.md`, Chat Screen). Weiterhin Polling-basiert, kein WebSocket.
- Backend:
  - Prisma: `User.lastSeenAt`, `Conversation.{worker,employer}LastReadAt`, `Conversation.{worker,employer}TypingAt` (Migration `20261116120000_add_chat_presence_read_receipts`)
  - `src/utils/chatPresence.js` (+ Tests) — Typing-Fenster 6 s, Online-Fenster 2 min, `lastSeenAt`-Drosselung 30 s
  - `src/auth.js` — `requireAuth` aktualisiert `lastSeenAt` gedrosselt (fire-and-forget)
  - `src/routes.messages.js` — neuer Endpunkt `POST /messages/:id/typing`; `GET /messages` + `GET /messages/:id` liefern `presence`; Nachrichten tragen `isReadByOther`; `PATCH /read` setzt den Lesezeitpunkt. Typing/Lesen per Raw-SQL, damit `updatedAt` (Listen-Sortierung) unverändert bleibt
- iOS:
  - `Models/Conversation.swift` — `ChatPresence`, `ChatMessage.isReadByOther`
  - `DTOs/MessageDTO.swift` — `ChatPresenceDTO`, `ChatMessagesResponseDTO`
  - `Stores/MessageStore.swift` — Presence übernehmen, Lesebestätigungen nachziehen, eingehende Nachrichten im offenen Chat sofort als gelesen melden, gedrosselte Typing-Pings (`userIsTyping` / `userStoppedTyping`)
  - `Features/Worker/Messages/ChatView.swift` — Polling 10 s → 3 s, Header-Status, Typing-Blase
  - `Features/Worker/Messages/ChatBubbles.swift` (neu) — Nachrichten-Blasen (aus ChatView verschoben), `ReadReceiptIcon` (Uhr → ✓ → ✓✓), `PresenceLine`, `TypingBubble`

### Fix: Employer-Chatliste hat das Backend abstürzen lassen (2026-11-16)
- `src/routes.messages.js` — `GET /messages` enthielt für Employer `include: { worker }`, Conversation hat diese Relation nicht → `PrismaClientValidationError`, unbehandelt in Express 4 → Node-Prozess beendet. Include entfernt (Name wird ohnehin separat geladen), `handle()`-Wrapper für GET-Liste/POST/PATCH ergänzt (500 statt Absturz)
- `src/routes.messages.test.js` — Regressionstest ohne echte DB

### Job Detail: Share-Button (2026-11-16)
- `Features/Worker/Jobs/JobDetailView.swift` — `ShareLink` im Header neben dem Bookmark; `JobShareContent` baut Kurztext (Titel, Firma, Lohn, Schicht, Ort) + Deep Link `swipeshift://job/<id>` (TODO: Universal Link sobald Domain live)
- `App/swipeShiftApp.swift` — `handleDeepLink` erkennt `swipeshift://job/<id>` → `JobStore.pendingDeepLinkJobId`
- `Features/Worker/Dashboard/WorkerHomeView.swift` — lädt den Job per `fetchJob` und zeigt `JobDetailView` als Sheet (auch bei Kaltstart über den Link)

### Company Profile: Telefon + E-Mail (2026-11-16)
- `src/routes.companies.js` — `GET /companies/:name` liefert `phone` / `email` aus `Employer.companyPhone` / `companyEmail`
- `DTOs/MessageDTO.swift` — `CompanyProfileDTO.phone` / `email`
- `Features/Worker/Company/CompanyProfileView.swift` — Contact-Sektion mit Telefon, E-Mail, Website; antippbar über `ContactLink` (tel:/mailto:/https, `@handle` → instagram.com)

### Financial Overview: Zeitraum-Filter für beide Seiten (2026-11-16)
Lücken aus dem Field-Audit: Employer hatte gar keinen Zeitraum-Filter, Worker keine "Custom Range".
- Backend:
  - `src/utils/period.js` (+ Tests) — `resolvePeriod` (thisMonth / last3Months / thisYear / allTime / custom mit `from`/`to` = YYYY-MM-DD, inklusive), `buildBuckets` (Tage ≤ 31 Tage, Wochen ≤ 16 Wochen, sonst Monate). Feste Zeiträume enden am Monats- bzw. Jahresende
  - `src/routes.employer.js` — `GET /employer/financials` filtert nach Zeitraum; Diagramm folgt dem Zeitraum statt fest 7 Tage; "Monthly Spend" bleibt laufender Monat; "Upcoming" überall = veröffentlicht + in der Zukunft (vorher zählte das Diagramm auch vergangene Jobs); 400 bei ungültigem Zeitraum
  - `src/routes.worker.js` — `GET /worker/financials` nutzt denselben Helper (damit auch `custom`)
- iOS:
  - `UI/Components/FinancialPeriodPicker.swift` (neu) — `FinancialPeriod`, Capsule-Dropdown, Custom-Range-Sheet mit Kalender (Start/End)
  - `Networking/APIClient.swift` — beide Finanz-Calls nehmen `FinancialPeriod`, Query sauber kodiert
  - `Features/Employer/EmployerFinancialView.swift` — Picker, Fehlerzustand mit Retry, Diagramm für viele Balken (enger, nur jedes n-te Label)
  - `Features/Worker/Profile/FinancialOverviewView.swift` — eigenes `TimePeriod` durch gemeinsamen Picker ersetzt
  - Beide Views: `.task(id: period)`, abgebrochene Requests überschreiben keinen Zustand
- Offen: "Paid Out" beim Employer weiterhin 0, obwohl `Apply.isPaid` existiert (TODO im Code)

### Fix: Employer "Paid Out" + einheitliche Kostenformel (2026-11-16)
- `src/utils/jobCost.js` (+ Tests) — Stundenlohn × Schichtstunden (0,1 h gerundet, Fallback 8 h) × Worker. Abgeschlossen = angenommene Worker, kommend = geplante Plätze, Paid Out = als bezahlt markierte Worker
- Vorher rechneten Finanz-Übersicht und Dashboard `payAmount × openSpots` (ohne Stunden, obwohl `payAmount` der Stundenlohn ist) → Beträge viel zu niedrig, passten nie zum Job-Payment-Screen; "Paid Out" war fest 0
- `GET /employer/financials` — echtes `paidOut`, gestapeltes Diagramm ohne Doppelzählung, Liste markiert komplett bezahlte Jobs als `paid`
- `GET /employer/stats` (Dashboard "Monthly Spend"), `GET /employer/jobs/:id/payments` und `GET /worker/financials` nutzen dieselbe Formel
- iOS `EmployerFinancialView` — Kachel "Paid Out" (laut Wireframe) statt "Monthly Spend", Breakdown "Completed (unpaid)", "Paid"-Badge

### Leave Reviews: Filter nach Job-Kategorie + Schicht-Datum (2026-11-16)
- `Features/Employer/ReviewFilterSheet.swift` (neu) — `ReviewFilters` (Rating, Would Rehire, Kategorie, Datum mit Presets + Custom), Filter-Sheet mit Entwurfsmodus, umbrechende Chips
- `Features/Employer/LeaveReviewsView.swift` — nutzt das neue Sheet; Kategorie + Datum filtern auch "Pending"; "No reviews match your filters"-Zustand
- Offen: "Drafts"-Tab ist weiterhin ein Platzhalter

### Company Profile: Response Rate + typische Antwortzeit (2026-11-16)
Notion-Felder "Employer response rate" / "Typical response time" (Detailed Company Profile Screen). Im Field-Audit zunächst fälschlich der Bewerber-Übersicht zugeordnet.
- Prisma: `Apply.respondedAt` (Migration `20261116180000_add_apply_responded_at`), gesetzt bei der ERSTEN Antwort in `POST /employer/applicants/:id/accept|decline`; Unassign behält es
- `src/utils/responseStats.js` (+ Tests) — Quote = beantwortet / (beantwortet + offen > 48 h); Antwortzeit = Median; unter 3 Datenpunkten `null`. Altdaten (accepted/declined ohne Zeitstempel) zählen für die Quote, nicht für die Zeit
- `src/routes.companies.js` — `responseRate`, `typicalResponseHours` (nur aggregierte Zahlen)
- iOS `CompanyProfileView` — Kennzahl "Response Rate" im Header, "Usually replies within …" aus echten Daten (Fallback: statischer `replyTime`), "New on platform" bei zu wenig Daten
- Hinweis: Seed-Daten haben deutschen `replyTime`-Fallbacktext in englischer UI

### Worker-Kalender nach Notion-Vorgabe + Fix: stornierte Jobs (2026-11-16)
- **Fix:** `GET /worker/applications` sah nur den Bewerbungsstatus → stornierte Jobs blieben für angenommene Worker "confirmed" (Kalender + Job Applications); `GET /worker/financials` zählte sie als Verdienst
- Backend:
  - `src/utils/applicationStatus.js` (+ Tests) — Anzeige-Status inkl. storniertem Job, vom Employer abgeschlossenem Job, Zahlungsstatus, Stornierungsart + -grund
  - `GET /worker/applications` — neu: `cancellationKind`, `cancellationReason`, `paymentStatus`, `earnings`, `conversationId`
  - Prisma `Job.cancellationReason` (Migration `20261116200000_add_job_cancellation_reason`); `PATCH /jobs/:id/status` nimmt optional `reason` beim Stornieren (max. 300 Zeichen)
- iOS:
  - `WorkerCalendarView.swift` (neu aufgebaut), `WorkerCalendarComponents.swift` (Modell, Overlap-Erkennung, Grid, Zeilen, Wochenleiste), `WorkerCalendarDetailSheet.swift` (Detail-Sheet mit View Job / Open Chat)
  - Zahlungsstatus, Stornierungsgrund, Overlap-Warnung, vergangene Jobs getrennt, Leerzustand mit "Find jobs nearby", Wochen-Navigation, Legende
  - `JobApplicationsView` — Grund auf stornierten Karten; `AllPostedJobsView` — optionales Grund-Feld beim Stornieren
- Bewusst offen: Daily View (Wireframe: Monat/Woche), Zeitzonen-Label, Live-Aktualisierung ohne Neuöffnen


### Settings: echte Active Sessions + 2FA per E-Mail-Code (2026-11-17)
Vorher: Geräteliste hartcodiert, "Sign out of all other devices" hat nur lokal ausgeloggt, 2FA-Schalter ohne Funktion.
- Backend:
  - Prisma `UserSession` (eine pro Login/Gerät), `TwoFactorCode`, `User.twoFactorEnabled` (Migration `20261117100000_add_sessions_two_factor`)
  - Jeder JWT trägt jetzt `sid`; `requireAuth` prüft die Session in der DB (widerrufen/abgelaufen → `401 { code: "SESSION_REVOKED" }`) und aktualisiert `lastActiveAt` gedrosselt. **Alte Tokens ohne `sid` sind ungültig → alle Nutzer müssen sich einmal neu einloggen.**
  - `src/sessions.js` — gemeinsamer Login-Abschluss für E-Mail, Google, Apple, Register (`completeLogin`); bei aktivierter 2FA kommt statt Token `{ twoFactorRequired, challengeId, emailHint }`
  - `src/routes.security.js` — `GET /auth/sessions`, `POST /auth/sessions/:id/revoke`, `POST /auth/sessions/revoke-others`, `POST /auth/logout`, `GET /auth/2fa`, `POST /auth/2fa/request|confirm|verify-login|resend`
  - Codes: 6-stellig, HMAC-gehasht, 10 Min gültig, max. 5 Fehlversuche, einmal nutzbar, rate-limited; Mail via MailHog
  - Passwort ändern → alle anderen Geräte abgemeldet; Passwort-Reset → alle Geräte abgemeldet
  - `src/utils/twoFactor.js`, `src/utils/deviceInfo.js` (+ Tests); `GET /auth/me` liefert `twoFactorEnabled`
- iOS:
  - `DTOs/SecurityDTO.swift` (neu) — Login-Ergebnis, Challenge, Session-DTOs, Geräte-Header (`X-Device-Name/-Model`, `X-OS-Version`)
  - `Features/Auth/TwoFactorCodeView.swift` (neu) — Code-Eingabe (Login + An/Aus), "Send a new code"
  - `UserStore` — alle Login-Wege gehen über `applyLoginOutcome`; `pendingTwoFactor`; Logout beendet die Session auch serverseitig; bei `SESSION_REVOKED` automatisch ausloggen + Hinweis auf dem Startscreen
  - `AccountSettingsView` — 2FA-Schalter echt (Code per Mail bestätigen, Abschalten mit Rückfrage); Active Sessions mit echten Geräten, einzeln oder alle anderen abmelden
  - `validate()` reicht strukturierte Backend-Fehler (`{ error, code }`) als lesbare Meldung durch
  - Employer: Profil-Zeile "Settings" öffnet jetzt die Account Settings (war leer)
- End-to-End gegen lokale DB + MailHog getestet (28 Checks: Geräte, Abmelden, Logout, 2FA an/aus, Login mit Code, Resend, Brute-Force-Sperre, Passwortwechsel, alte Tokens)
- Bewusst offen: Standort pro Gerät (bräuchte IP-Geolocation), Authenticator-App (TOTP) als Alternative zur E-Mail, eigenes Employer-"Payments & Billing"

### Worker-Detailprofil (Arbeitgeber-Sicht) mit echten Daten (2026-11-17)
Vorher waren Bewertung (4.6 / „18 Jobs“), Kategorie-Bewertungen, Verfügbarkeit, Erfahrung, Präferenzen und Legal fest eingetragen — für jeden Bewerber gleich.
- Backend: `GET /employer/workers/:userId` in `routes.employer.js` — nur wenn sich der Worker auf einen Job dieses Arbeitgebers beworben hat (sonst 404). Liefert Profil (ohne Telefon/E-Mail/Geburtsdatum, nur Alter), Bewertungs-Durchschnitte + Rehire-Quote aus `Review`, abgeschlossene Jobs gesamt/pro Kategorie, bis zu 3 Kommentare
- `src/utils/workerProfile.js` (+ Tests) — Alter, verfügbare Tage, Review-Zusammenfassung, abgeschlossene Jobs (gleiche Logik wie Worker-Kalender), Bereinigung freier JSON-Felder
- iOS: `DTOs/WorkerProfileDTO.swift` (neu), `DetailedWorkerView.swift` neu aufgebaut (Lade-/Fehlerzustand, „New on SwipeShift“ ohne Bewertungen, Selbsteinschätzung klar gekennzeichnet, „Verified email“ statt „Verified Worker“)
- Offen: Erfahrungslevel pro Kategorie (nicht im Datenmodell), Sprachen, Zuverlässigkeit/No-Show-Quote

### Einstellungen werden wirklich gespeichert (2026-11-17)
Vorher: Benachrichtigungen, Quiet Hours, Dark Mode, Sprache nur lokaler `@State`; Auszahlung + „Konto pausieren“ nur in `UserDefaults`, ohne Wirkung.
- Backend: `User.settings` (JSON) + `User.pausedAt` (Migration `20261117140000_add_user_settings_paused`); `src/routes.settings.js` — `GET/PATCH /auth/me/settings`, `POST /auth/me/pause`; `GET /auth/me` liefert `isPaused`
- `src/utils/settings.js` (+ Tests) — Standardwerte, Validierung (HH:MM, IBAN mit Mod-97-Prüfung, PayPal-Mail), Teil-Updates, IBAN wird nie komplett zurückgegeben
- Pause wirkt: pausierter Worker → `POST /jobs/:id/apply` = `403 ACCOUNT_PAUSED` (eigener Ergebnis-Screen im Apply-Flow); Jobs pausierter Arbeitgeber fehlen in `GET /jobs` + `/jobs/nearby` und sind nicht bewerbbar
- iOS: `DTOs/SettingsDTO.swift` (neu); Notifications speichern jede Änderung sofort (bei Fehler zurück auf alten Stand); Payments lädt/speichert, gespeicherte IBAN nur maskiert; Pause über API mit rollenabhängigem Text; Dark Mode via `@AppStorage`, angewendet in `swipeShiftApp`; Sprachauswahl durch Hinweis „English, more coming soon“ ersetzt
- End-to-End gegen lokale DB getestet (13 Checks)
- Offen: Push-/Mail-Versand gemäß Einstellungen (keine Push-Infrastruktur), echte Auszahlungen, Lokalisierung, Zeitzone; offene-Jobs-Zähler im Company-Profil zählt Jobs pausierter Arbeitgeber noch mit

### Zustimmungen speichern, 18+ prüfen, Entfernungen in Meilen (2026-11-17)
Gefunden beim Profile-Screen-Abgleich: Legal-Schalter (Worker + Arbeitgeber) und „I am at least 18“ waren nur lokaler `@State`; km und Meilen gemischt.
- Backend: `User.legalConsents` (JSON, Key → Zeitstempel; Migration `20261117180000_add_legal_consents`); `src/utils/consents.js` (Whitelist pro Rolle, Terms nicht widerrufbar) + `src/utils/age.js` (`isAtLeast18`) mit Tests
- Onboarding verlangt `acceptedTerms` und speichert Terms; Registrierung speichert Terms, wenn mitgeschickt; 18+ wird in Onboarding, Registrierung und `PATCH /auth/me` geprüft
- `GET /auth/me` liefert `legalConsents` (Bool-Map) und `dateOfBirth` als `yyyy-MM-dd`; `PATCH /auth/me` + `PATCH /employer/profile` nehmen `legalConsents` an
- `/jobs/nearby?unit=mi` (ohne `unit` weiter km), `distanceText` in Meilen, Radius validiert; `kmToMiles`/`milesToKm` in `haversine.js`
- iOS: `utils/DateOnly.swift`, `utils/Distance.swift` (neu); Edit Profile (Worker) mit Rating-System-Zustimmung, 18+-Zeile aus dem Geburtsdatum, Geburtsdatum wird nicht mehr still überschrieben, Fehler-Alert; Arbeitgeber-Profil speichert alle fünf Zustimmungen; Jobliste-Filter + Radar in Meilen
- `validate()` reicht jede Backend-Meldung `{ error }` lesbar durch (vorher nur mit `code`)
- Vor Start: `npx prisma migrate deploy`

### Arbeitgeber-Entwürfe bearbeiten und löschen (2026-11-17)
- Backend: `Job.updatedAt` (Migration `20261117200000_add_job_updated_at`, Altjobs übernehmen `createdAt`); `src/utils/jobData.js` — `buildJobData` (gemeinsames Mapping POST/PUT), `validateJobBody` (400 statt 500 bei kaputten Zahlen/Arrays), `checkDraftAccess` (+ Tests)
- `PUT /jobs/:id` (nur eigener Entwurf, optional direkt veröffentlichen, `company` bleibt wenn nicht gesendet) und `DELETE /jobs/:id` (nur eigener Entwurf) — beide atomar (`updateMany`/`deleteMany` mit `status: "draft"`), damit ein inzwischen veröffentlichter Job nie überschrieben/gelöscht wird; Fehler 404/403/409 `NOT_DRAFT`
- iOS: `PostJobView(editingJobId:)` lädt und befüllt den Entwurf („Edit Draft“, Save Draft / Post Job, Fehlerzustand mit Retry/Close); Entwurfskarten mit Edit / Publish / Delete (Bestätigung) und „Last saved …“, Entwürfe nach letzter Änderung sortiert; „View Applicants“ auf veröffentlichten Jobs mit Bewerbern (`AllApplicantsView(jobId:jobTitle:)`); Fehler als Alert statt ganzer Fehleransicht
- Offen: Klick-Test; beim Veröffentlichen bleibt das Erstelldatum das des Entwurfs

### Bewertungen: Entwürfe, Work quality, Top Worker, Would work again (2026-11-17)
- Backend: Modell `ReviewDraft`, `Review.workQuality` (nullable für Bestand) + `Review.topWorker`, `WorkerReview.wouldWorkAgain` (Migration `20261117220000_review_drafts_and_fields`); `src/utils/reviewLogic.js` (+ Tests) — Durchschnitte nur über vorhandene Werte, Draft-/Review-Validierung, Would-work-again-Quote (ab 3 Antworten)
- `GET/PUT/DELETE /employer/reviews/drafts`; `POST /employer/reviews` verlangt 5 Kategorien, löscht den Entwurf in derselben Transaktion; Pending blendet Einträge mit Entwurf aus
- `POST /worker/reviews` verlangt `wouldWorkAgain` + `publishConsent`, nur Werte 1–5 und nur für eigene, abgeschlossene Jobs; doppelte Bewertung → 409 statt 500
- Firmenprofil: `wouldWorkAgainPercent`; Worker-Bewertungsliste zeigt den richtigen Firmennamen (vorher fast immer „Unknown Company“)
- iOS: Bewertungsformular (Arbeitgeber) mit Work quality, „Highlight as Top Worker“, „Save as Draft“ + Toast; Drafts-Tab mit echten Entwürfen (öffnen, löschen); Chat-Formular lädt vorhandenen Entwurf; Firmen-Bewertung mit „Would you work here again?“ + Pflicht-Zustimmung; Worker-Bewertungen/Detailprofil zeigen Work quality und „Top Worker ×N“; Firmenprofil zeigt „X% would work here again“
- Bewusst offen: Schalter „zählt zur Firmenbewertung“, Inhaltsmoderation

### Währung € → US-Dollar (2026-11-17)
- iOS: `utils/Money.swift` — einheitliche Formatierung (en_US, USD): ganze Beträge ohne Cent, sonst 2 Nachkommastellen („$18“, „$15.50“, „$1,250.75“); alle Beträge, Labels („Hourly Rate ($)“) und Euro-Symbole umgestellt
- Backend: `formatAmount`/`formatPayText` in `src/utils/jobData.js` („$X / hr“, gleiche Regel wie iOS); Seeds auf $ und englische Texte
- Migration `20261117230000_currency_usd` ersetzt das Symbol in bestehenden Lohn-/Schichttexten (keine Umrechnung)
- Offen: Auszahlung per IBAN ist EU-spezifisch — für US Bankverbindung (Routing/Account Number) nötig

### Chat: Melden, Blockieren, Fotos, Job-Kontext (2026-11-18)
- Backend: `UserBlock`, `UserReport` (bewusst ohne Fremdschlüssel, Meldungen überleben Kontolöschung; Migration `20261118090000_chat_safety`); `src/routes.safety.js` — `POST /safety/reports` (Mail an `SUPPORT_EMAIL`, 10/h, nur bei bestehender Verbindung), `POST/DELETE/GET /safety/blocks`; `src/utils/safety.js` (+ Tests)
- Block wirkt in beide Richtungen: Senden 403 `BLOCKED`, Bewerben 403 `BLOCKED`, Jobs im Feed ausgeblendet
- Conversation-Payload: Gegenüber-ID + Foto, Ort, Lohn, Schicht, Zahlungsstatus, Block- und Merk-Status
- iOS: `ChatSafety.swift`, `ChatView+Header.swift` — Menü (Report, Block/Unblock, Contact support per Mail, Job details, View worker profile), Sicherheitshinweis, Profilfotos in Liste und Header, Datums-Trenner, Datum/Schicht im Header, einklappbare Job-Infokarte, nach Jobende Zahlungsstatus + Firma/Worker merken; fehlgeschlagene Nachrichten landen wieder in der Eingabe
- Offen: „Erneut buchen“, Liste blockierter Nutzer in den Einstellungen, Admin-Oberfläche für Meldungen

### Restliche Profilfelder (2026-11-18)
- Worker: `availableTimes` (morning/afternoon/evening/night), `shiftTypes` (oneDay/weekend/eventBased — Last-minute bleibt der Same-day-Schalter), `experience` (pro Kategorie < 3 Monate / 3–12 Monate / 1+ Jahre); im Edit Profile bearbeitbar, im Worker-Detailprofil für Arbeitgeber sichtbar
- Arbeitgeber: `yearFounded`, `tagline`, `socialLinks` (nur echte Instagram/LinkedIn/Facebook/TikTok-Links), `streetAddress`, `zipCode` (US), `addressLat/Lng` (Adresssuche), `publicContactName/Role`, `postsInMultipleStates`, `remoteFriendly`; Firmenprofil zeigt Slogan, „Founded“, Adresse + Karte („Open in Maps“), Ansprechpartner, Social-Icons
- Backend: `src/utils/profileFields.js` (+ Tests), Migration `20261118110000_profile_fields`
- Offen: Sub-Typen pro Kategorie, Zuverlässigkeits-Score, Auswertung von „mehrere Bundesstaaten“/„Remote“

### Kleinere Lücken Worker-Seite (2026-11-18)
- Jobdetail: Abschnitt „Location“ mit Adresse + Karte („Open in Maps“, `UI/Components/LocationMapPreview.swift`), Firmenblock mit Branche und Anzahl abgeschlossener Schichten
- Kalender-Detail: Kategorie + Entfernung; Bewerbungen nach Monat gruppiert mit Summen, „Applied …“, Kategorie, Zahlungsstatus, „View job“/„Chat“ (`ApplicationCard`, `ApplicationMonthGroups`, gemeinsame `ApplicationNavigation`)
- Gespeichert: Firmenkarten mit Standort/Branche/Kurztext + „View open jobs“/„View profile“; Jobkarten mit Tags, Entfernung, „Company“, „Apply“ (nur bei freien Plätzen und zukünftigem Start)
- Finanzen (Worker): Verdienstliste mit Stundenlohn × Stunden und Status, nach Monat gruppiert, bis 100 Einträge; Kennzahl „This week“
- Firmenprofil: Rating-Tags („Fair Pay“, „Friendly Team“ …) ab 3 Bewertungen und Ø ≥ 4.5 über alle Bewertungen
- Login: zuletzt genutzte Methode wird angezeigt (`Security/LastLoginMethod.swift`)
- Behoben: ein gemeinsamer Datums-Decoder (mit/ohne Millisekunden) für alle API-Aufrufe; Konto löschen loggt bei Fehler nicht mehr aus
- Backend-utils: `companyStats.js`, `ratingTags.js`, `distanceMilesBetween`, `currentWeekRange` (+ Tests)

### Kleinere Lücken Arbeitgeber-Seite (2026-11-18)
- Backend: `src/utils/applicantSummary.js` (+ Tests) und `src/applicantSummaries.js` — eine Zusammenfassung pro Worker (Ø-Bewertung, Jobs, Tags, 18+-Badge ohne Alter, Verfügbarkeit), gebündelt geladen; genutzt von `GET /employer/applicants`, `/employer/saved-applicants`, `/employer/calendar`
- Bewerberkarte: Bewertung („New“ ohne), Jobs, Erfahrungs-/Skill-Tags, 18+, „Applied 2h ago“, Verfügbarkeit, „Chat“ nach Annahme; Status Angenommen/Abgelehnt kommt jetzt vom Server
- Gemerkte Bewerber: Foto, Stadt, Bewertung, Jobs, stärkste Erfahrung, Kurz-Bio, „View profile“
- Arbeitgeber-Kalender: Kategorie, Schichtkosten, bestätigte Worker (antippbar) mit Team-Ø
- Worker-Detailprofil: „Chat“-Button nach Annahme; Bewerbungsliste (Worker) zeigt die Anzahl Jobs pro Monat

### Active Sessions: Stadt pro Gerät + Authenticator-App (2026-11-18)
- Stadt: App schickt den groben Ort aus dem Profil (`X-Device-City`, „City, ST“), gespeichert in `UserSession.city`, angezeigt als „Austin, TX (approx.)“ — keine Koordinaten, keine IP-Ortung, kein Drittanbieter; Cache wird bei Logout/Nutzerwechsel gelöscht
- TOTP (RFC 6238, eigene Implementierung `src/utils/totp.js`): Einrichtung erst nach Mailcode, QR-Code + Secret + „Open in authenticator app“, 8 Backup-Codes (einmalig, Info-Mail bei Verbrauch, „N of 8 left“, neu erzeugen mit aktuellem Code); Login akzeptiert TOTP- oder Backup-Code
- Sicherheit: Secret AES-256-GCM mit Key-ID + AAD (Rotation über `TOTP_ENCRYPTION_KEY_PREVIOUS` + `scripts/rotate-totp-key.js`), eigener `BACKUP_CODE_PEPPER`, Replay-Schutz, Challenge-Art an aktuelle Methode gebunden, Fehlversuchssperre pro Nutzer+IP (IPv6 /64) plus nutzerweite Obergrenze, Warn-Mail; `TRUST_PROXY` nur Hop-Zahl/IP-Liste
- Konfiguration: `swipeshift-backend/.env.example`; außerhalb von development/test startet das Backend nur mit `TOTP_ENCRYPTION_KEY` und `BACKUP_CODE_PEPPER` (`npm run dev` setzt NODE_ENV=development)
- Migration `20261118140000_session_city_totp`
- Manuell zu prüfen: Einrichtung (falscher/abgelaufener Mailcode, Pending > 15 min), Login mit TOTP/Backup-Code, Sperre (10 Fehlversuche je IP, 50/h gesamt), Downgrade mit altem Mailcode, Abschalten, Backup-Codes neu erzeugen, Schlüsselrotation, Startprüfungen
- Offen: direkter Wechsel E-Mail → Authenticator in der App (aktuell erst ausschalten)

### Add Job: Zusatzfelder + Instant Match (2026-11-18)
- Neue Job-Felder: Required Skills, Physical Requirements, Certifications, Education Level, Work Authorization required, Urgency (normal/urgent), Location Type (single/multiple), Break (+ Minuten), Same-Day Pay, Tips, Bonus (+ Text), Repeat Work, Cancellation Policy (+ Notes), Job Notes — im Post-Job-Formular, Draft-Round-Trip, Anzeige in der Jobdetailansicht (nur gesetzte Werte); „Urgent“-Pille auf Jobkarten, dringende Jobs zuerst in „Starting Soon“
- Terms-Checkbox: Veröffentlichen erfordert `termsAccepted` (POST, PUT, PATCH /status in jedem Wechsel nach published) → sonst 400 `TERMS_REQUIRED`; `Job.termsAcceptedAt`; POST nur draft/published, Draft nur → published/cancelled (409 `INVALID_TRANSITION`)
- Instant Match: Bewerbung wird automatisch angenommen, solange Plätze frei sind und Mindestalter/Arbeitserlaubnis erfüllt sind (`shouldAutoAccept`), sonst normal pending; Serializable-Transaktion mit Retry, final 409 `TRY_AGAIN`; `Apply.autoAccepted` (bei manueller Aktion zurückgesetzt); Worker sieht „You're booked!“
- Statistik: auto-angenommene Bewerbungen zählen nicht als „New Applicants“/„needs response“, nicht in Antwortquote/-zeit; eigene Kennzahl „Instant Matches“ (Dashboard) und „Instant“ (Job-Karte); „Auto-accepted“-Pille bei Bewerbern/zugewiesenen Workern. Gebuchte Plätze, Finanzen, Reviews zählen sie als normale Worker
- Backend-utils: `jobData.js` (Validierung, `evaluateStatusChange`, `shouldAutoAccept`), `applyCounts.js` (+ Tests); Migrationen `20261118160000_job_extra_fields`, `20261118170000_job_extra_fields_backfill` (lokal angewendet)
- Bewusst nicht umgesetzt: Job-Type-Mehrfachauswahl, Plattformgebühr/Netto-Lohn (kein Gebührenmodell)
- Offen: Zertifikate bei Instant Match nicht prüfbar (kein Worker-Feld)

### Job-Status-Regeln, Vollständigkeit beim Veröffentlichen, Bewerberzahl (2026-11-18)
- Statuswechsel nur noch: draft → published/cancelled; published → inProgress/completed/cancelled, → draft nur ohne Bewerbungen (409 `HAS_APPLICANTS`); inProgress → completed/cancelled; completed/cancelled final (409 `INVALID_TRANSITION`, neu ausschreiben statt wiedereröffnen); gleicher Status = No-op. Race-sicher über bedingtes Update (Status + updatedAt)
- Veröffentlichen (POST, PUT, PATCH) prüft nach den Terms die Vollständigkeit: Titel, Kategorie, Ort, jede Schicht mit Start < Ende, Stundenlohn > 0, ≥ 1 Platz → sonst 400 `INCOMPLETE_JOB` mit `missing`; App zeigt fehlende Angaben + „Edit draft“; Post-Job-Formular verlangt jetzt auch Ort + Stundenlohn
- `GET /jobs/mine`: `applicantCount` = nur unbeantwortete manuelle Bewerbungen (Wireframe), dazu `instantMatchCount`, `totalApplicationCount`; Jobkarte zeigt „N new“ nur bei veröffentlichten Jobs
- Helper: `STATUS_TRANSITIONS`/`evaluateStatusChange`, `missingPublishFields`/`publishGate` (jobData.js), `summarizeJobApplies` (applyCounts.js) + Tests

### Kleine Reste aus dem App Development Tracker (2026-11-18)
- Kalender (beide Seiten): Job-Hinweise des Arbeitgebers sichtbar (Worker nur bei offener/angenommener Bewerbung)
- Gemerkte Firmen: „Last worked: …“ (letzter eigener Job dort), sonst „Last posted: …“
- Gemerkte Jobs: „Not interested“ — entfernt aus Gemerkt und blendet den Job überall aus (`Skip.notInterested`), Rückgängig-Banner (6 s); ein früherer Swipe-Skip bleibt dabei erhalten
- Arbeitgeber-Jobkarte: bis zu 2 offene Bewerber mit Accept/Decline, „Message“ nach Annahme, Pille „N new matches“ (`Job.applicantsSeenAt`, gesetzt über `POST /jobs/:id/applicants/seen`, ohne `updatedAt` zu ändern)
- Bewerberkarte: „Available for this shift“ / „Outside stated availability“ (App, Gerätezeitzone, nur Schichtbeginn) / „Has another job at this time“ (Server, nur offene Bewerbungen)
- Worker-Detailprofil: vergangene Jobs (max. 10, Firma/Job/Datum/Bewertung, keine Kommentare), Konto (E-Mail bestätigt, Mitglied seit — Pausiert wird bewusst nicht gezeigt), Match-Hinweis im Kontext eines eigenen Jobs (Kategorie, Skills ≥ 4, Arbeitserlaubnis, Mindestalter)
- Behoben: Bewerberliste des Arbeitgebers lieferte Serverfehler, sobald Bewerber da waren (Profilfoto aus falschem Modell abgefragt, seit März)
- Backend-utils: `scheduleConflict.js`, `employerJobCard.js`, `workerDetail.js`, `savedCompanyDates.js`, `jobNotes.js` (+ Tests); Migration `20261118180000_applicants_seen_and_not_interested` (lokal angewendet)
- Verfügbarkeits-Hinweis auch bei den Bewerbern direkt auf der Jobkarte (kompakt, gleicher Wortlaut)

### Liste blockierter Nutzer (2026-11-18)
- Einstellungen → Privacy & Data → „Blocked users“ (Worker und Arbeitgeber): Foto/Initiale, Name (Arbeitgeber = Firmenname), Rolle, „Blocked on …“, „Unblock“ mit Bestätigung; Lade-, Fehler- und Leerzustand, Erklärung was Blockieren bewirkt
- Backend: `GET /safety/blocks` liefert zusätzlich Rolle und Foto (gebündelt, `src/utils/blockedUsers.js` + Tests)

### Benachrichtigungen per Push + E-Mail (2026-11-18)
- Versand nach den Einstellungen pro Kategorie (Job Activity, Messages, Payments, Account) und Kanal; Ruhezeiten dämpfen nur Push (Zeitzone vom Gerät, `X-Time-Zone` → `User.timeZone`); Sicherheits-Mails (Passwort, 2FA, neues Gerät) unverändert immer
- Ereignisse: Bewerbung angenommen/abgelehnt, Job storniert, Schicht-Erinnerung (einmal, ≤ 24 h vorher), neue Bewerbung, Instant Match; Chat-Nachricht (Push sofort mit Vorschau, E-Mail nur wenn nach 15 min ungelesen, max. 1/Chat/Stunde, ohne Nachrichtentext); als bezahlt markiert, Zahlung offen nach Jobende; neue Bewertung, Konto pausiert/fortgesetzt. Keine Benachrichtigungen zwischen blockierten Nutzern; pausierte Konten nur Pause/Fortsetzen; Stornogrund nur im Push, nicht in Mails
- Push: komplett vorbereitet (APNs über HTTP/2, `src/push.js`, Geräte `PushDevice`, `/auth/me/push-devices`), aber inaktiv bis `APNS_*` gesetzt sind (siehe `.env.example`); Geräte werden bei Logout/Sitzungs-Widerruf/Passwortwechsel entfernt, Offline-Logout wird nachgeholt, Token wechselt beim Login den Besitzer, Push-Taps nur im richtigen Konto
- Hintergrundjobs: `src/scheduler.js` (alle 5 min, idempotent auch bei mehreren Servern)
- iOS: Berechtigung einmal nach dem Onboarding, Hinweis + „Open Settings“ in den Benachrichtigungs-Einstellungen, Tap öffnet Chat/Job (Arbeitgeber: nur Tab)
- Migration `20261118190000_push_notifications` (lokal angewendet)
- Offen: Push-Capability/`aps-environment` in Xcode + APNs-Schlüssel (braucht bezahltes Apple Developer Program); Arbeitgeber-Deep-Links aus Push

### US-Bankdaten für Auszahlungen statt IBAN (2026-11-18)
- Auszahlung per Bankkonto: Kontoinhaber, Routing Number (9 Ziffern, ABA-Prüfsumme, nicht nur Nullen), Kontonummer (4–17 Ziffern, mit Bestätigungsfeld), Checking/Savings; PayPal bleibt
- Kontonummer AES-256-GCM verschlüsselt (gemeinsamer Helper `src/utils/secretBox.js`, gleicher Schlüssel wie TOTP, eigene AAD `bank:<userId>`), nach außen nur „•••• 1234“; Routing Number im Klartext
- Sicherheits-Mail bei jeder echten Änderung von Bankdaten, PayPal oder Auszahlungsmethode (was geändert wurde, Zeitpunkt UTC, Support-Hinweis; nie volle Kontonummer/Routing Number)
- Schlüsselrotation (`scripts/rotate-totp-key.js`) erfasst jetzt auch die Bankdaten — live getestet inkl. TOTP
- IBAN komplett entfernt; Migration `20261118200000_remove_stored_iban` löscht gespeicherte IBANs (nur Daten, lokal angewendet)
- Offen: erneute Anmeldung (Passwort/2FA) vor Änderung der Auszahlungsdaten; echte Auszahlungen (Zahlungsanbieter)

### Erneute Anmeldung vor Änderung der Auszahlungsdaten (2026-11-18)
- Änderungen an Bankdaten, PayPal oder Auszahlungsmethode brauchen eine Bestätigung auf dem aktuellen Gerät (10 Minuten gültig, `UserSession.reauthAt`), sonst 403 `REAUTH_REQUIRED` und nichts wird gespeichert; Frequenz und Benachrichtigungen ohne Bestätigung
- Methoden: Authenticator-/Backup-Code (falls 2FA per App), Passwort (falls vorhanden), E-Mail-Code nur für Konten ohne beides (Google/Apple); serverseitig erzwungen
- Eigene Fehlversuchssperre (getrennt vom 2FA-Login), E-Mail-Code mit eigenem Zweck, einmalig, max. 5 Versuche (`CODE_ATTEMPTS_EXCEEDED`); Bestätigung verfällt bei Passwort-/2FA-/Backup-Code-Änderung
- App: „Confirm it's you“-Sheet beim Speichern, danach automatisch erneut gespeichert
- Backend: `src/utils/reauth.js` (+ Tests), Endpunkte `/auth/me/reauth*`; Migration `20261118210000_session_reauth` (lokal angewendet)

### 2FA-Methode direkt wechseln (2026-11-18)
- E-Mail-Code → Authenticator-App: über den bestehenden Einrichtungsweg (erst E-Mail-Code, dann QR + Bestätigung), 2FA bleibt durchgehend an; neue Sicherheits-Mail „Two-factor method changed to authenticator app“
- Authenticator-App → E-Mail-Code: `POST /auth/2fa/switch-to-email/start` (TOTP- oder Backup-Code, Replay-Schutz, Sperre) → Mail-Code mit eigenem Zweck `switch_email`, an die Sitzung gebunden → `/confirm` stellt atomar um, löscht TOTP-Secret + Backup-Codes, beendet laufende Bestätigungen (`reauthAt`), Sicherheits-Mail
- App: „Switch to authenticator app“ / „Switch to email codes“ in Account & Security (`SwitchToEmailView`)
- Migration `20261118220000_switch_email_2fa` (Enum-Wert + `TwoFactorCode.sessionId`, lokal angewendet)
