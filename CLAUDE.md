SwipeShift
Claude Code Prompt — Vollständige Projektübergabe
1. Über dieses Dokument
Dieser Prompt beschreibt das SwipeShift-Projekt vollständig für Claude Code. Claude Code soll damit ohne weiteren
Kontext direkt weiterarbeiten können. Alle Beschreibungen sind auf Deutsch. Alle Code-Bezeichner, Variablennamen,
Funktionsnamen und Dateinamen bleiben auf Englisch.
2. Projektübersicht
SwipeShift ist eine iOS-App (SwiftUI, iOS 17+) mit einem Node.js/Express-Backend. Es handelt sich um einen
flexiblen Job-Marktplatz, der Arbeitnehmer mit Arbeitgebern für kurzfristige Schichten verbindet. Arbeitnehmer können
Jobs durchsuchen, per Swipe bewerben oder über eine Listansicht filtern. Arbeitgeber können Jobs ausschreiben,
Bewerber verwalten und Zahlungen abwickeln.
Tech-Stack
• iOS: SwiftUI, iOS 17+, kein UIKit außer absolut notwendig
• Backend: Node.js, Express, Prisma ORM, PostgreSQL
• Authentifizierung: JWT (Bearer Token im Keychain), Google Sign-In, Apple Sign-In
• E-Mail: MailHog (lokal via Docker) für Verifikations- und Passwort-Reset-Mails
• Infrastruktur: Docker Compose (PostgreSQL auf Port 5432, MailHog auf 8025/1025)
• Kein TypeScript im Backend — reines JavaScript
3. Dateistruktur
iOS App
./App/swipeShiftApp.swift
./App/ContentView.swift ← Routing-Logik (unverified → onboarding → home)
./App/AppConfig.swift
./Security/TokenStore.swift ./Networking/APIClient.swift ← JWT im Keychain speichern/lesen
← Alle HTTP-Calls (singleton: APIClient.shared)
./Networking/MultipartFormDataBuilder.swift
./Networking/UploadTarget.swift
./Features/Auth/MainView.swift ← LandingView mit fullScreenCover-Buttons
./Features/Auth/LoginView.swift
./Features/Auth/RegisterView.swift
./Features/Auth/GoogleLoginSuccessfulView.swift
./Features/Auth/VerifyEmailView.swift
./Features/Auth/ForgotPasswordView.swift
./Features/Auth/ResetPasswordView.swift
./Features/Auth/RoleChoiceView.swift
./Features/Employer/EmployerHomeView.swift ← Tab-Container mit EmployerTabBar (vollstaendig implementiert)
./Features/Employer/EmployerDashboardView.swift, PostJobView.swift, AllPostedJobsView.swift, AllApplicantsView.swift,
  DetailedWorkerView.swift, AssignWorkersView.swift, LeaveReviewsView.swift, JobPaymentView.swift,
  EmployerFinancialView.swift, EmployerCalendarView.swift, EditEmployerProfileView.swift, SavedApplicantsView.swift
  ← alle implementiert, an echte Backend-Daten angebunden
./Features/Worker/Dashboard/WorkerHomeView.swift ← Tab-Container mit AppTabBar
./Features/Worker/Dashboard/WorkerHomeTabView.swift ← Home-Tab Inhalt
./Features/Worker/Dashboard/CategoryScrollView.swift ← Horizontales Karussell
./Features/Worker/Dashboard/JobSectionView.swift ← Wiederverwendbare Sektion + DashboardJobCard
./Features/Worker/Jobs/JobListView.swift ← Alle Jobs, Sticky Header, Suche/Sort/Filter
./Features/Worker/Jobs/JobDetailView.swift ← vollstaendig implementiert
./Features/Worker/Jobs/ApplyFlowView.swift ← Apply Flow (Schicht-Auswahl, Bestaetigung, Fehlerzustaende)
./Features/Worker/Jobs/JobSwipeView.swift ← Redesign nach Wireframe implementiert
./Features/Worker/Jobs/CategoryJobListView.swift
./Features/Worker/Jobs/RadarView.swift ← MapKit implementiert (Clustering via ClusterMapView)
./Features/Worker/Jobs/ClusterMapView.swift ← MKAnnotation-Clustering (UIViewRepresentable)
./Features/Worker/Messages/MessagesView.swift, ChatView.swift ← Chat-System implementiert
./Features/Worker/Notifications/NotificationsView.swift ← implementiert
./Features/Worker/Company/CompanyProfileView.swift, EmployerRatingSheet.swift ← implementiert
./Features/Worker/Profile/WorkerProfileView.swift ← implementiert, plus alle Sub-Screens
  (EditProfileView, JobApplicationsView, WorkerCalendarView, FinancialOverviewView, ReviewsView,
  SavedView, AccountSettingsView)
./Features/Onboarding/OnboardingRootView.swift
./Features/Onboarding/WorkerOnboardingView.swift
./Features/Onboarding/EmployerOnboardingView.swift
./Stores/UserStore.swift
./Stores/JobStore.swift
./Models/UserRole.swift
./Models/Job.swift
./DTOs/JobDTO.swift
./DTOs/AuthDTO.swift
./Services/LocationGeocoder.swift
./UI/TabBar/AppTabBar.swift
./UI/Components/ImagePicker.swift
./UI/Components/EmailVerifyBanner.swift
./utils/FormValidator.swift
./utils/Theme.swift ← SS.primary, SS.background(), SSPrimaryButtonStyle
Backend
src/
index.js ← Express-App-Setup, Router-Registrierung
prisma.js ← Prisma-Client-Singleton
routes.auth.js ← Login, Register, Google/Apple OAuth, /me, Passwort aendern/setzen, Account loeschen
routes.onboarding.js ← Onboarding-Endpunkte
routes.jobs.js ← GET /jobs (inkl. type-/category-Filter), /jobs/nearby, /jobs/mine, /jobs/:id,
  /jobs/:id/apply|skip|save, /jobs/:id/applicants, PATCH /jobs/:id/status
routes.employer.js ← Applicants (accept/decline/save/unsave), Assigned Workers, Employer-Profil,
  Employer-Kalender, Employer-Finanzen
routes.messages.js ← Chat-System (Conversations + Messages, Polling via ?since=)
routes.companies.js ← Company-Profil-Aggregation aus Job-/Employer-/Review-Daten
routes.worker.js ← Saved Companies, Worker-Reviews (Employer bewerten)
routes.notifications.js ← dynamische Benachrichtigungen (kein eigenes DB-Model)
routes.upload.js ← Profilfoto-Upload
routes.me.js ← PATCH /auth/me (Profil-Update)
utils/haversine.js ← Distanzberechnung zwischen zwei Koordinaten
utils/geocode.js ← Nominatim-Geocoding fuer POST /jobs
middlewares/requireVerifiedEmail.js
auth.js ← JWT requireAuth Middleware
prisma/schema.prisma ← vollstaendiges Datenmodell (siehe unten)
docker-compose.yml ← PostgreSQL + MailHog
Alle Routen sind vollstaendig auf Prisma/PostgreSQL umgestellt, kein In-Memory-Store mehr aktiv.
db.js (In-Memory-Store) wurde entfernt, da nirgends mehr aktiv referenziert.
4. Aktueller Stand — Was funktioniert
Hinweis: Der Grossteil der in Abschnitt 8 beschriebenen Wireframe-Screens ist mittlerweile vollstaendig
implementiert und an echte Backend-/DB-Daten angebunden (siehe PROGRESS.md fuer die vollstaendige,
chronologische Aenderungshistorie). Es gibt praktisch keine Mock-/Platzhalterdaten mehr in den
Kern-Flows.

Authentifizierung
• E-Mail/Passwort Register + Login vollständig
• Google Sign-In und Apple Sign-In funktionieren (inkl. Fix fuer GIDSignIn-URL-Handling)
• E-Mail-Verifikationsflow funktioniert
• isNewUser-Flag: GoogleLoginSuccessfulView erscheint nur bei neuen Social-Usern
• Auth-Screens nutzen fullScreenCover (nicht NavigationLink)
• ContentView-Routing: unverifiziert → Social Success → Onboarding → Home
• Passwort setzen fuer Social-User, Passwort/E-Mail aendern, Account loeschen — alles ueber echte Endpunkte

Worker — Dashboard, Jobs, Radar, Swipe
• WorkerHomeView: 5-Tab-Navigation mit eigenem AppTabBar (Home, Radar, Messages, Swipe, Profile),
  Messages-Tab zeigt Unread-Badge
• WorkerHomeTabView: Header, View-All-Button, CategoryScrollView, 5 echte Job-Sektionen (Recommended,
  Quick Money, Starting Soon, Popular, "Might Like") ueber Backend-Filter (?type=..., ?category=...)
• JobListView: Sticky Header, Suche, Sort-Sheet, Filter-Sheet inkl. echtem Distanz-Filter
• JobDetailView: vollstaendig laut Wireframe (Header, Quick-Info, Tags, Beschreibung, Aufgaben,
  Requirements, Pay/Contract, Company-Section, "Was passiert als Naechstes")
• ApplyFlowView: Schicht-Auswahl, Bestaetigung, alle Erfolgs-/Fehlerzustaende inkl. strukturierter
  Backend-Fehlercodes (JOB_UNAVAILABLE, SHIFT_TAKEN, SCHEDULING_CONFLICT)
• RadarView: MapKit mit Clustering (ClusterMapView), farbige Pins, Map-Shrink beim Scrollen,
  Radius-Filter-Sheet, echte /jobs/nearby-Daten
• JobSwipeView: Redesign laut Wireframe, Card-Stack mit Drag/Apply/Skip, Bookmark, Kategorie-Filter
• CategoryJobListView: laedt direkt per Backend-Kategorie-Filter (kein Client-Filter mehr)
• CompanyProfileView: echte Daten von GET /companies/:name inkl. Review-Breakdown, Save/Unsave

Worker — Messages, Profil, Konto
• Chat-System vollstaendig: Conversation-/Message-Modell in Prisma, MessagesView + ChatView,
  Auto-Refresh via Polling, Read-only nach Completed/Cancelled, System-Nachrichten
• NotificationsView: echte, dynamisch generierte Benachrichtigungen (kein eigenes DB-Model noetig)
• WorkerProfileView + alle Sub-Screens implementiert: EditProfileView (inkl. Fotoupload),
  JobApplicationsView, WorkerCalendarView, FinancialOverviewView (inkl. Sparziel), ReviewsView,
  SavedView (Jobs + Companies), AccountSettingsView (Security, Notifications, Payments, Privacy, App Prefs)
• Worker kann Employer nach Jobabschluss bewerten (EmployerRatingSheet)

Employer
• EmployerHomeView: 5-Tab-Container mit EmployerTabBar
• EmployerDashboardView: echte Stats, Needs-Attention-Alerts, Quick Actions, Trends
• PostJobView: vollstaendiges Formular (Schichten, Tags, Requirements, Payment/Contract), Draft/Publish
• AllPostedJobsView, AllApplicantsView, DetailedWorkerView, AssignWorkersView (inkl. "Add Worker"-Sheet),
  LeaveReviewsView, JobPaymentView, SavedApplicantsView, EmployerCalendarView, EmployerFinancialView,
  EditEmployerProfileView — alle implementiert und an echte Backend-Endpunkte angebunden

Backend
• Vollstaendig auf Prisma/PostgreSQL umgestellt — kein In-Memory-Store mehr aktiv
• Prisma-Modelle: User, Worker, Employer, Job, Apply, Skip, Save, Review, WorkerReview,
  Conversation, Message, SavedCompany, SavedApplicant (siehe schema.prisma fuer Details)
• GET /jobs — inkl. ?type=quickMoney|startingSoon|popular|recommended und ?category=
• GET /jobs/nearby, /jobs/mine, /jobs/:id, /jobs/:id/applicants — implementiert
• POST /jobs/:id/apply (mit Schicht-Auswahl + strukturierten Fehlercodes), /skip, /save
• POST /jobs, PATCH /jobs/:id/status — Job erstellen/aktualisieren (Arbeitgeber)
• routes.employer.js — Applicants (accept/decline/save/unsave), Assigned Workers, Kalender, Finanzen
• routes.messages.js — Chat (GET /messages, GET /messages/:conversationId?since=, POST/PATCH)
• routes.companies.js, routes.worker.js, routes.notifications.js — implementiert
• Minimales Test-Setup vorhanden (node --test, siehe Abschnitt 12)

5. Was noch NICHT implementiert ist
Der ueberwiegende Teil der Wireframe-Anforderungen ist implementiert. Bekannte offene Detail-Punkte
(siehe PROGRESS.md, TODO-Kommentare im Code):
• Active Sessions + 2FA sind umgesetzt (E-Mail-Code 2026-11-17, Authenticator-App/TOTP + ungefaehre
  Stadt pro Geraet 2026-11-18, siehe PROGRESS.md). Backend braucht ausserhalb von development/test
  TOTP_ENCRYPTION_KEY + BACKUP_CODE_PEPPER (siehe swipeshift-backend/.env.example). Offen: eigenes
  Employer-"Payments & Billing" (Employer nutzt aktuell die Worker-Account-Settings)
• DetailedWorkerView: seit 2026-11-17 echte Daten (GET /employer/workers/:userId). Offen: Erfahrungslevel
  pro Kategorie (nicht im Worker-Modell), Sprachen, Zuverlaessigkeit/No-Show-Quote
• AccountSettingsView: seit 2026-11-17 gespeichert (GET/PATCH /auth/me/settings, POST /auth/me/pause;
  Dark Mode pro Geraet via @AppStorage). Offen: Push-/Mail-Versand nach diesen Einstellungen, echte
  Auszahlungen, Lokalisierung (Sprachauswahl bis dahin entfernt), Zeitzone
• Kein XCTest-Target im Xcode-Projekt vorhanden — iOS-Unit-/UI-Tests muessen ueber Xcode
  (File > New > Target > Unit Testing Bundle) manuell angelegt werden, siehe Abschnitt 12
• Backend-Testabdeckung ist bewusst minimal (Smoke-Tests fuer reine Utility-Funktionen), keine
  vollstaendige Route-/Integrationstest-Suite
• Website + Universal Links fehlen (Notion Aufgaben-Tracker: "Website & Universal Links"):
  Job-Share (JobDetailView, `JobShareContent`) nutzt aktuell den Custom-Scheme-Link
  `swipeshift://job/<id>` (ausgewertet in swipeShiftApp.handleDeepLink → WorkerHomeView). Der
  funktioniert nur mit installierter App und ist in manchen Messengern nicht antippbar. Ziel:
  https://swipeshift.app/jobs/<id> als Universal Link → braucht Domain, Web-Fallback-Seite pro
  Job (mit App-Store-Button), apple-app-site-association-Datei, Associated-Domains-Entitlement
  (bezahlter Apple-Developer-Account). Ausserdem verweisen Privacy/Terms/Guide-Links
  (AccountSettingsView, WorkerProfileView) und support@swipeshift.app bereits auf die Domain,
  die Seiten existieren aber noch nicht — fuer die App-Store-Einreichung Pflicht.
  Stand 2026-11-25: Teilen nutzt jetzt den Web-Link https://swipeshift.app/jobs/<id>, die App
  verarbeitet Universal Links (swipeShiftApp.jobId(from:), .onOpenURL + .onContinueUserActivity;
  swipeshift://job/<id> bleibt Rueckfall) und die Release-Backend-URL ist api.swipeshift.app.
  Verbleibender Schritt: in Xcode Signing & Capabilities → Associated Domains →
  `applinks:swipeshift.app` eintragen (nach Apple-Developer-Mitgliedschaft).
• Einige Bereiche nutzen weiterhin vereinfachte MVP-Logik statt echter Business-Regeln (z.B.
  "recommended"-Sortierung basiert auf Worker.preferredCategories + payAmount, kein echtes Scoring;
  Apply-Status-Feld bei manchen Flows minimal gehalten) — kein Blocker, aber erweiterbar
6. Design System
NEU (seit Redesign Etappe 1): Alle neuen/umgebauten Views nutzen das Design-System unter
swipeShift/UI/Design/ (Details: UI/Design/README.md):
• Tokens: DS.Color.* (dynamisch hell/dunkel, Markenfarbe nur in `Brand` aendern), `.dsFont(.headline)`
  (Plus Jakarta Sans, Dynamic Type), DS.Spacing (4er-Raster, Rand 20, Innenabstand 16), DS.Radius,
  .dsCardShadow(), DS.Motion, DS.Haptics
• Komponenten: DSSection/DSRow/DSToggleRow (flach), DSCard (nur Antippbares), DSTile (Kennzahlen),
  DSBadge, DSChip, DSAvatar, .buttonStyle(.ds(...)), DSIconButton, DSTextField/DSTextEditor, DSStepper,
  DSProgressSteps, .dsSkeleton(), DSEmptyState
• Regeln: flach fuer Formulare/Einstellungen, Karte nur fuer Antippbares, Kachel fuer Zahlen; keine
  hartcodierten Farben/Groessen in neuen Views; Reduce Motion beachten
• Hintergrund neuer Screens: .dsBackground() (statt SS.background())
ALT (wird abgeloest, Screens werden in spaeteren Etappen umgestellt): SS-Theme (utils/Theme.swift)
• SS.primary → Markenfarbe (zeigt intern auf Brand.primaryLight)
• SS.background() → Hintergrund-Gradient
• SSPrimaryButtonStyle → alter Button-Style
• DashboardJobCard → wiederverwendbare Job-Card (in JobSectionView definiert)
• Karten (alt): weisser Hintergrund, RoundedRectangle(cornerRadius: 14), shadow(opacity: 0.04)
Unveraendert gueltig:
• TabBar: eigener AppTabBar (kein SwiftUI TabView), floating Pill-Design
• NavigationStack lebt in WorkerHomeView und umschliesst alle Tabs
• @MainActor fuer alle Store-Funktionen die @Published Properties aendern
• async/await fuer alle Netzwerk-Calls
7. Architektur-Entscheidungen (nicht aendern)
• Auth-Screens: immer fullScreenCover, nie NavigationLink
• NavigationStack: liegt in WorkerHomeView, umschliesst alle Tabs
• AppTabBar: State via @State private var selectedTab: WorkerTab
• JobStore.jobs = alle Jobs, JobStore.nearbyJobs = Radius-gefiltert
• UserStore.currentUser: UserDTO enthaelt lat, lng, location, firstName, lastName, role, onboarding
• Fuer jede neue Datei: Terminal-Befehl mit korrektem Zielordner angeben
• Git-Commits fuer logische Aenderungsgruppen angeben
8. Wireframe-Anforderungen (aus den PDFs)
Zwei vollstaendige Wireframe-PDFs wurden bereitgestellt: employee-screen.pdf und employer-screen.pdf. Alle Screens
muessen exakt nach diesen Wireframes implementiert werden.
Worker (Arbeitnehmer) Screens
Home Screen
• Header: 'Your Personal Job Dashboard', Glocken-Icon, Name + Location
• 'View All Available Jobs' Button
• Category Discovery: horizontales Icon-Karussell (Hospitality, Events, Logistics, Retail, Customer Service,
Warehouse, Office, Cleaning)
• Tippen auf Kategorie oeffnet Job-Liste gefiltert nach dieser Kategorie
• 5 Job-Sektionen (je 2 Karten + 'Click to view all jobs'):
- 'Here are jobs you might like today': starke Uebereinstimmung mit Skills, Kategorien, vergangenen Bewerbungen
- 'Quick Money Jobs': unter 4 Stunden entfernt, starten bald, gute Bezahlung
- 'Recommended for You': basierend auf Skills, vergangenen Bewerbungen, Verfuegbarkeit
- 'Starting Soon': starten heute oder morgen, Dringlichkeit erzeugen
- 'Popular This Week': 10+ Bewerbungen, zeigt 'Applied by XX People'
• Bottom CTAs: 'Looking for nearby jobs? → Go to Radar' und 'Want to decide fast? → Try Swipe'
All Available Jobs Screen
• Sticky Header: 'All Available Jobs' Titel + Suchfeld + Sort + Filter Buttons
• Suchfeld matched: Job Title, Company Name, Job Category, Keywords/Tags, Location (Stadt, PLZ)
• Sort (Bottom Sheet, Radio Buttons, schliesst automatisch nach Auswahl): Starting soon, Highest Pay, Nearest
Distance, Most Recent
• Aktiver Sort zeigt Punkt neben Sort-Button
• Filter (Bottom Sheet mit Apply/Cancel Footer): Location/Distance (5/10/15/20/25 Miles), Date/Time
(Today/Tomorrow/This Week/Custom), Pay/Hourly Rate (Minimum), Job Type (One-time/Multi-shift/Recurring),
Job Category (alle Kategorien), Duration (Min 1h / Max 12h), Start Time (Morning/Afternoon/Evening/Night),
Experience Required, Payment Type, Job Tags
• Aktive Filter: Punkt + Anzahl neben Filter-Button, 'Clear All Filters' Button (nur sichtbar bei aktivem Filter)
• Tippen auf Job-Karte oeffnet Job Detail Screen
Job Detail Screen
• Header: Job Title, Company Logo (tippbar → Company Profile), Verified Badge, Bookmark Icon, X-Button
• Location (Stadt + Bereich), Distanz, Stundenlohn, Datum & Uhrzeit, Dauer
• Job Category Badge, Job Tags
• Apply Button (sticky am unteren Rand)
• Job Description Abschnitt
• Open Spots Anzahl
• Tasks Liste
• Requirements: Dress Code, Language Skills, Experience Level, Certifications, Min Age
• Pay Details: hourly/per shift, Payment Method (Same-day/Weekly/In-app Wallet)
• Contract Type: Freelance/Temporary/Mini-Job/Insurance Info
• Company Section: Name, Rating, 'Usually replies within XX hours'
• 'What happens next?' Section: Arbeitgeber prueft Profil → Antwort im Chat → keine Verpflichtung bis
Bestaetigung
Apply Flow
• Apply-Button auf Job-Card oder Detail-Screen oeffnet Bestaeigungs-Popup
• Option 1 (1 Schicht): 'Confirm Application' Sheet mit Job-Details, Schicht-Details, Verguetung, rechtlichem
Hinweis
• Option 2 (mehrere Schichten): Zuerst 'Select Shift(s)' Sheet mit Checkboxen → dann Bestaetigung
• 'Next'-Button nur aktiv wenn mindestens eine Schicht ausgewaehlt
• Nach Bestaetigung → Erfolgs-/Fehlerzustaende: Application Submitted, Connection Lost, Shift Already Taken,
Shift Unavailable, Scheduling Conflict Detected
• Jeder Fehlerzustand hat eigenen Action-Button (z.B. 'View Other Shifts', 'View My Calendar')
Radar Screen
• MapKit Map: nimmt initial 45% der Bildschirmhoehe ein
• 3 Farben fuer Job-Pins: Blau (Standard), Orange (Starting Soon = innerhalb 5 Stunden), Gruen (High Pay)
• Clustering: mehrere Jobs am selben Ort werden zu einem Cluster zusammengefasst
• Tippen auf Pin: hebt entsprechende Job-Karte hervor und scrollt automatisch dazu
• Job-Liste darunter: sortiert nach Distanz + Starting Soon
• Beim Scrollen der Liste: Map schrumpft auf 25% Hoehe
• Beim Zurueckscrollen nach oben: Map expandiert zurueck auf 45%
• Nach Schliessen des Job-Detail-Screens: gehighlighteter Pin in der Mitte der Map
• Filter-Button (Radius-Filter fuer spaeter)
• 'Showing X jobs near you' Zaehler
Messages Screen (Worker)
• Chat-Liste, sortiert: 1) Jobs naechste 24h, 2) Upcoming Jobs nach Datum, 3) Ungelesene Nachrichten, 4)
Completed, 5) Cancelled
• Job Status Badges: Today (blaue Pill), Upcoming (gruene Pill), Completed (weisse Pill), Cancelled (rote Pill)
• Ungelesener-Punkt nur sichtbar wenn Nachricht ungelesen
• Leerzustand: 'No conversations yet. Once an employer accepts your application, your chat with them will appear
here.' + 'Browse Jobs' Button
• Chat nur verfuegbar wenn Arbeitgeber Bewerbung angenommen hat
• Im Chat: angenommene-Nachricht oben, Chat-Blasen, System-Nachrichten fuer
Job-Updates/Stornierung/Abschluss
• Read-only Text-Box wenn Completed/Cancelled mit entsprechender Nachricht
• Link zu Rating-Screen wenn Job abgeschlossen
• Tippen auf Company-Logo → Company Profile Screen
• Info-Button → Job-Detail-Screen
Profile Screen (Worker)
• Profilbild, Name, 'Verified Worker' Badge, Bewertung
• 'Edit Profile' Button
• Navigations-Liste: Job Applications, Calendar, Financial Overview, Settings and Support, Account Settings, Help
& Support, Logout, Your Ratings, Saved
• Logout triggert Bestaeigungs-Popup
Edit Profile Screen (Worker)
• Profilbild editierbar
• Name (First/Last), E-Mail, Telefon, Geburtsdatum
• Location & Mobility: aktuelle Stadt/Bundesland, bereit in anderer Stadt zu arbeiten (Ja/Nein), maximale
Reisedistanz (5/10/15/20 Miles), Transportmittel
• Verfuegbarkeit: verfuegbare Tage (Mon-Sun Toggle), Zeitraum (Zeitstrahl), Same-day jobs verfuegbar
• Job Preferences: bevorzugte Kategorien (mit Sub-Typen und Erfahrungslevel), bevorzugter Stundelohn-Bereich
• Experience: pro Kategorie Sub-Typen auswaehlen, Erfahrungslevel (<3 Monate, 3-12 Monate, 1+ Jahre)
• Skills: Communication, Teamwork, Reliability, Working under Pressure
• Legal & Compliance: Altersbestaetigung, Arbeitserlaubnis, AGB, Rating-System Zustimmung
• Bio (Optional, max 300 Zeichen)
Job Applications Screen
• Tabs: Confirmed / Applied / Completed / Cancelled
• Confirmed: alle zukuenftigen Jobs wo Arbeitgeber bestaetigt hat
• Applied: alle zukuenftigen Jobs ohne Antwort des Arbeitgebers
• Completed: alle vergangenen abgeschlossenen Jobs
• Cancelled: alle vergangenen abgelehnten/zurueckgezogenen Jobs
• 'Withdraw Application' Button → Bestaeigungs-Popup → Bestaetigung-Popup
Calendar Screen
• Monat/Woche Toggle
• Monatsansicht: Kalender-Grid + Liste der Upcoming Jobs darunter
• Wochenansicht: horizontale Tages-Spalten + Zeitstrahl 12AM-12PM
• Job-Status-Badges: Confirmed (gruen), Applied (grau)
• 'Open Chat' Button fuer bestaetigte Jobs
Financial Overview Screen (Worker)
• Donut-Diagramm: 3 Farben (Upcoming Earnings, Completed Earnings, Paid Out)
• Zeitraum-Dropdown: This Month / Last 3 Months / This Year / All Time / Custom Range
• Custom Range: Kalender-Ansicht zur Zeitraum-Auswahl
• Upcoming Jobs Liste (Status: Confirmed)
• Completed Jobs Liste
• 'View Breakdown' Button → Aufschluesselung nach Job Status oder Kategorie
Saved Screen
• Tabs: Jobs / Companies
• Gespeicherte Jobs: mit Datum gruppiert, Status-Badge wenn beworben/bestaetigt
• Gespeicherte Unternehmen: Logo, Verified Badge, Anzahl offener Jobs, Bewertung, 'View Open Jobs' Button
• Leerzustand: 'You have not saved anything yet. Start exploring jobs and companies and save the ones you like.'
Company Profile Screen
• Logo, Name, Verified Badge, Anzahl abgeschlossener Jobs
• Business Areas (Kategorien), Standort, Bewertung (Sterne + Anzahl Reviews)
• 'About Company' Abschnitt
• Ratings & Reviews: Aufschluesselung nach Communication, Payment Fairness, Work Environment, Accuracy of
Job Description, Overall Experience
• Review-Karten (max 2 sichtbar, 'View All Reviews' Button)
• Locations (HQ + weitere)
• Company Contact Details: Telefon, E-Mail, Website
• Rating Tags (z.B. Friendly Team, Fair Pay, Good Communication)
• 'View Open Jobs' Button → gefilterte Job-Liste dieses Unternehmens
Notifications Screen
• Liste aller Benachrichtigungen mit Icon, Titel, Beschreibung, Zeitstempel
• Kategorien: Job-Aktivitaet, Zahlungen, Nachrichten, System
Account Settings Screen
• Navigation zu: Account & Security, Notifications, Payments & Payouts, Privacy & Data, App Preferences
• Account & Security: E-Mail aendern (mit Verifikation), Telefon aendern, Passwort aendern, 2FA, Active Sessions
/ eingeloggte Geraete
• Notifications: Push + E-Mail pro Kategorie (Job Activity, Payments, Messages, Account), Quiet Hours
• Payments & Payouts: Bankverbindung oder PayPal, Auszahlungseinstellungen
• Privacy & Data: Privacy Policy, Terms, Konto pausieren, Konto loeschen (mit Bestaetigung)
• App Preferences: Dark Mode Toggle, Sprache
Reviews Screen (Worker)
• Gesamt-Bewertung (z.B. 4.6/5), basiert auf X Jobs
• Skills Performance: Communication, Teamwork, Reliability, Working under Pressure
• Bewertungen nach Job (max 5 sichtbar, 'View All Ratings' Button)
• Jede Bewertung: Unternehmensname, Job-Typ, Datum, Sterne, Unternehmens-Feedback
Employer (Arbeitgeber) Screens
Employer Dashboard
• Header: Unternehmensname, Location-Dropdown (wenn mehrere Standorte)
• Stats-Reihe: Active Jobs (Anzahl + View all), New Applicants (Anzahl + View all), Monthly Spend ($)
• 'Needs Attention' Alerts: ausstehende Bewerbungen, Schichten ohne Mitarbeiter, ausstehende Zahlungen, Profil
unvollstaendig
• Quick Actions: Post a New Job, View All Posted Jobs
• Navigation: Job Management (Posted Jobs), Worker Management (Applicants, Assign Workers, Leave Reviews)
• Trends: Jobs Filled, New Applications, Avg Worker Rating, Top Job Categories
Post a New Job Screen
• Job Basics: Titel, Unternehmensname (vor-ausgefuellt), Standort mit Suche
• Job Category: Einfachauswahl
• Job Tags: Vorgeschlagene Tags gruppiert nach Kategorie (Work Environment, Physical Requirements, Social
Interactions, Special Context), mehrfach auswahlbar als Chips
• Shift Details: Datumsauswahl (Kalender), pro Schicht: Datum, Startzeit, Endzeit (Dauer auto-berechnet), '+ Add
Shift' Button
• Number of Workers
• Stundenlohn
• Position Info: Job Description, Tasks (+ Add Task), Requirements (Dress Code Dropdown, Language Skills
Multi-Select, Min Age, Zertifikate, Erfahrung, Physical Requirements, Bildungsniveau, Experience Level Radio
Buttons)
• Zahlung: Payment Frequency Dropdown (After Shift/Weekly/Biweekly/Monthly), Contract Type Dropdown
(Freelance/Temporary/Mini-Job/Insurance)
• Footer: 'Save as Draft' + 'Post Job' Buttons
• Post Job Bestaeigungs-Popup: 'Sind Sie sicher? Sobald veroeffentlicht koennen Arbeitnehmer sich bewerben' +
Save as Draft / Post Job
All Posted Jobs Screen
• Tabs: Active / Draft / Completed / Past Jobs
• Job-Karten mit Status-Badges (Published, In Progress, Draft)
• Cancel Job Flow mit Bestaeigungs-Popup
• Entwurf veroeffentlichen mit Bestaeigungs-Popup
• Anzahl Bewerbungen zeigt nur unbeantwortete
Job Detail Screen (Arbeitgeber)
• Vollstaendige Job-Infos
• Bewerber-Karten mit Accept/Decline Buttons (Status: Published)
• Zugewiesene Mitarbeiter-Liste (Status: In Progress)
All Applicants Screen
• Alle Bewerber ueber alle Jobs
• Bewerber-Karte: Name, Bewertung, Erfahrung, Standort, Job-Titel, Datum/Schicht, Stundenlohn, Accept/Decline
• Tippen → Detailliertes Worker-Profil
Detailed Worker Screen
• Vollstaendiges Arbeitnehmer-Profil: Name, Verified Badge, Bewertung, Standort, Mobilitaet
• Ratings & Reviews Aufschluesselung
• Availability & Location: verfuegbare Tage, Max Reisedistanz, On-Call
• Work Experience: nach Kategorie und Erfahrungslevel
• Job Preferences: bevorzugte Rollen und Schichten
• Legal & Compliance: Arbeitserlaubnis
• Accept / Decline Buttons
• Bestaeigungs-Popup fuer Accept und Decline
Leave Reviews Screen (Arbeitgeber)
• Tabs: Pending Reviews / Drafts / Past Reviews
• Pending: Arbeitnehmer die bewertet werden muessen nach Schichtabschluss
• Bewertungsformular: Kommunikation, Teamwork, Reliability, Working under Pressure (je 1-5 Sterne), optionaler
Kommentar (max 600 Zeichen), 'Would rehire?' Toggle
• Sort: Most Recent, Highest/Lowest Rating
• Filter: Rating-Level, Job Category, Would Rehire, Date Range
Assign Workers Screen
• Job-Liste mit offenen Stellen
• Pro Job: Schichten mit (X Open Spots / Y Workers assigned)
Financial Overview Screen (Arbeitgeber)
• Total Spending, Upcoming Payments, Completed Jobs, Paid Out
• Balkendiagramm: 3 Farben pro Tag (Upcoming/Completed/Paid Out)
• Zeitraum-Dropdown: This Month / Last 3 Months / This Year / All Time / Custom Range
• View Breakdown: Aufschluesselung nach Job Status oder Job Kategorie
Job Payment Screen (Arbeitgeber)
• Pro Job: alle Mitarbeiter mit geleisteten Stunden x Stundenlohn = Gesamtbetrag
• Bereits bezahlte Mitarbeiter zeigen 'Paid' Badge
• 'Pay All Workers' oder 'Pay Worker' oder 'Pay Remaining Worker' Button
• Bestaeigungs-Popup vor Zahlungsfreigabe
Messages Screen (Arbeitgeber)
• Chat-Liste mit Mitarbeiter-Infos
• Job Status Badges: Today (blau), Upcoming (gruen), Completed (weiss), Cancelled (rot)
• Sortierung: 1) Jobs naechste 24h, 2) Upcoming nach Datum, 3) Completed, 4) Cancelled
• Chat wird read-only nach Abschluss/Stornierung
Employer Profile/Settings Screen
• Unternehmensname, Standort-Dropdown, Job Manager Rolle
• 'Edit Profile' Button, Verified Badge
• Navigation: Job Management, Financial Overview, Calendar, Settings, Account Settings, Help & Support, Logout
Edit Profile Screen (Arbeitgeber) — 2 Tabs
• Company Information Tab: Unternehmensname, Business Areas, E-Mail, Telefon, Standorte (+ Neuen
hinzufuegen), Primary Hiring Location, Company Size, Company Bio, Website
• Your Profile Tab: Vorname, Nachname, Work-E-Mail, Standorte die man verwaltet, Jobtitel, Rolle (Admin/Hiring
Manager)
• Team Members: Liste, Einladen (E-Mail + Rolle), Entfernen (mit Bestaetigung)
• Legal Agreements: AGB, Rating-System, Payment Responsibility, Accurate Job Information, Legal Hiring
Calendar Screen (Arbeitgeber)
• Monat/Woche Toggle
• Standort-Dropdown (wenn mehrere)
• Filter: All Jobs / Needs Workers / Fully Staffed
• Wochenansicht: Zeitstrahl 12AM-12PM
• Job-Karten: zeigen Schicht-Status (Open Spots, Workers Assigned, Fully Staffed)
Account Settings (Arbeitgeber)
• Account & Security, Notifications (wie Worker)
• Payments & Billing: Zahlungsmethode (Bank/PayPal), automatische vs. manuelle Zahlung, naechstes
Zahlungsdatum
• Privacy & Data, App Preferences (wie Worker)
9. Backend-Erweiterungen (Status: erledigt)
Das Prisma Job-Model ist erstellt und um zahlreiche Detailfelder erweitert worden (siehe
prisma/schema.prisma fuer die vollstaendige, aktuelle Definition — inkl. Apply, Skip, Save, Review,
WorkerReview, Conversation, Message, SavedCompany, SavedApplicant). Alle unten aufgefuehrten,
urspruenglich geplanten Endpunkte sind implementiert (teils mit erweitertem Funktionsumfang):
• GET /jobs?type=quickMoney|startingSoon|popular|recommended — implementiert (routes.jobs.js)
• GET /jobs?category=Hospitality — Kategorie-Filter implementiert
• GET /jobs/nearby?lat&lng&radius — Radius-Filter implementiert
• POST /jobs/:id/apply — Bewerbung mit Schicht-Auswahl + strukturierten Fehlercodes implementiert
• GET /messages, GET /messages/:conversationId?since=, POST/PATCH /messages — Chat implementiert
• GET /companies/:name — Unternehmens-Profil implementiert (inkl. Review-Aggregation)
• POST /jobs, PATCH /jobs/:id/status — Job erstellen/Status aendern implementiert
• GET /employer/applicants, POST /employer/applicants/:id/accept|decline|save|unsave — implementiert
Damit gilt Abschnitt 9 als abgeschlossen; neue Erweiterungswuensche sollten als eigene TODOs erfasst
werden statt hier nachgetragen zu werden.

10. Prioritaeten (historisch — alle abgeschlossen)
Alle urspruenglich hier definierten Prioritaeten 1-7 (Radar View/MapKit, Job Detail View, Apply Flow,
Messages Tab, Employer Home View, Post a New Job Screen, Worker Profile Screen) sind vollstaendig
umgesetzt. Fuer die detaillierte Chronologie aller nachfolgenden Erweiterungen (Assign Workers,
Financial Overview, Notifications, Saved Companies, etc.) siehe PROGRESS.md. Neue Prioritaeten sollten
bei Bedarf hier durch das Team neu definiert werden.

11. Testinfrastruktur
Backend (swipeshift-backend/):
• `npm test` fuehrt echte Tests aus via Node's eingebautem Test-Runner (`node --test`), keine
  zusaetzliche Dependency noetig
• Tests liegen unter src/**/*.test.js (aktuell: utils/haversine.test.js) — bewusst auf reine,
  DB-freie Utility-Funktionen beschraenkt, keine vollstaendige Route-/Integrationstest-Suite
Website (website/, lokal statt Cloudflare):
• `node scripts/serve-website.js` → http://localhost:8788 (ENV PORT, WEBSITE_DIR; emuliert _redirects,
  _headers, saubere URLs, 404.html). Tests: `node --test scripts/serve-website.test.js`
• Debug-Build der App oeffnet Website-Links (Privacy/Terms/Guide, Job-Share) ueber `AppConfig.websiteURL`
  dort, Release nutzt https://swipeshift.app

iOS (swipeShift.xcodeproj):
• Es existiert noch KEIN XCTest-Target im Xcode-Projekt. Das Anlegen eines Test-Targets per
  Texteditor im project.pbxproj ist fehleranfaellig und kann die Projektdatei korrumpieren — dies
  muss manuell in Xcode erfolgen: File > New > Target > Unit Testing Bundle (bzw. UI Testing Bundle
  fuer UI-Tests). Danach koennen XCTest-Cases fuer Stores (UserStore, JobStore, MessageStore) und
  DTOs ergaenzt werden.

12. Hinweise fuer Claude Code
• Zuerst alle bestehenden Dateien lesen um den aktuellen Stand zu verstehen
• Bei unklarem Wireframe-Verhalten nachfragen bevor implementiert wird
• Fuer jede neue Datei den Terminal-Befehl mit korrektem Zielordner angeben
• Git-Commits fuer logische Aenderungsgruppen mit aussagekraeftigen Nachrichten
• TODO-Kommentare hinterlassen wo Backend-Datenmodell noch nicht unterstuetzt wird
• Alle neuen Views muessen .environmentObject(userStore) und .environmentObject(jobStore) erhalten wo
benoetigt
• Englische Variablen-/Funktions-/Dateinamen — Deutsche Kommentare erlaubt
• SwiftUI only (iOS 17+), kein UIKit ausser absolut notwendig
• Backend: Plain JavaScript, kein TypeScript
SwipeShift — Claude Code Prompt | Generiert fuer Projektuebergabe