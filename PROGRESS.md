# SwipeShift — iOS Frontend Progress

_Zuletzt aktualisiert: 2026-03-30 (Detailed Worker View + Leave Reviews Screen)_

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

### Priorität 7 — Worker Profile Screen
- Navigations-Menü (wie Wireframe)
- Edit Profile (Profilbild, Name, E-Mail, Telefon, Geburtsdatum, Location, Verfügbarkeit, Job Preferences, Skills, Legal)
- Job Applications (Tabs: Confirmed / Applied / Completed / Cancelled)
- Calendar (Monat/Woche Toggle)
- Financial Overview (Donut-Chart, Zeitraum-Dropdown)
- Settings & Support
- Reviews Screen
- Saved Screen

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
