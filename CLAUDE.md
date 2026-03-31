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
./Features/Employer/EmployerHomeView.swift ← noch leer, jetzt implementieren
./Features/Worker/Dashboard/WorkerHomeView.swift ← Tab-Container mit AppTabBar
./Features/Worker/Dashboard/WorkerHomeTabView.swift ← Home-Tab Inhalt
./Features/Worker/Dashboard/CategoryScrollView.swift ← Horizontales Karussell
./Features/Worker/Dashboard/JobSectionView.swift ← Wiederverwendbare Sektion + DashboardJobCard
./Features/Worker/Jobs/JobListView.swift ← Alle Jobs, Sticky Header, Suche/Sort/Filter
./Features/Worker/Jobs/JobDetailView.swift ← Neu implementieren
./Features/Worker/Jobs/JobSwipeView.swift
./Features/Worker/Jobs/CategoryJobListView.swift
./Features/Worker/RadarView.swift ← MapKit implementieren
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
db.js ← routes.auth.js ← routes.jobs.js ← utils/haversine.js ← middlewares/requireVerifiedEmail.js
auth.js ← prisma/schema.prisma ← docker-compose.yml ← PostgreSQL + MailHog
In-Memory Store für MVP (users, jobs, applies, skips, saves)
Login, Register, Google/Apple OAuth, /me, Onboarding
GET /jobs, GET /jobs/nearby, POST apply/skip/save
Distanzberechnung zwischen zwei Koordinaten
JWT requireAuth Middleware
User-Model vorhanden, Job-Model noch NICHT erstellt
4. Aktueller Stand — Was funktioniert
Authentifizierung
• E-Mail/Passwort Register + Login vollständig
• Google Sign-In und Apple Sign-In funktionieren
• E-Mail-Verifikationsflow funktioniert
• isNewUser-Flag: GoogleLoginSuccessfulView erscheint nur bei neuen Social-Usern
• Auth-Screens nutzen fullScreenCover (nicht NavigationLink)
• ContentView-Routing: unverifiziert → Social Success → Onboarding → Home
Worker Dashboard
• WorkerHomeView: 5-Tab-Navigation mit eigenem AppTabBar (Home, Radar, Messages, Swipe, Profile)
• WorkerHomeTabView: Header mit Name/Location/Bell, View-All-Button, CategoryScrollView, 5 Job-Sektionen
als Placeholder
• CategoryScrollView: horizontales Scrollen, weiße Kreise mit Icons
• JobListView: Sticky Header, Suche, Sort-Sheet, Filter-Sheet, laedt alle Jobs via loadJobsAll()
• RadarView: Jobs in der Naehe via GET /jobs/nearby, Refresh-Button, Job-Liste
• Profile-Tab: Placeholder mit Logout-Button
Backend
• GET /jobs — alle Jobs ohne Location-Filter
• GET /jobs/nearby?lat&lng;&radius;=100 — Radius-Filter mit Haversine-Formel
• POST /jobs/:id/apply, /skip, /save
• Jobs in db.js haben lat/lng Koordinaten
5. Was noch NICHT implementiert ist
• Messages-Tab → nur PlaceholderTabView
• Swipe-Tab → JobSwipeView existiert, braucht Redesign laut Wireframe
• Profile-Tab → nur Logout, kein echtes Profil
• EmployerHomeView → leer
• JobDetailView → muss komplett neu implementiert werden
• RadarView → nur Liste, noch kein MapKit
• Job-Sektionen im Dashboard zeigen alle dieselben Jobs (TODO: echte Filter)
• Kein Prisma Job-Model (Jobs kommen aus db.js In-Memory)
• Kein Chat-System, keine Notifications, kein Calendar, keine Finanzen
6. Design System
Alle neuen Views muessen das bestehende Design-System verwenden:
• SS.primary → Markenfarbe (Lila/Blau)
• SS.background() → Hintergrundfarbe
• SSPrimaryButtonStyle → Standard-Button-Style
• DashboardJobCard → wiederverwendbare Job-Card (in JobSectionView definiert)
• Karten: weisser Hintergrund, RoundedRectangle(cornerRadius: 14), shadow(opacity: 0.04)
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
9. Backend-Erweiterungen
Prisma Job-Model (wenn erstellt)
model Job {
// fuer Sortierung
// Anzeige: "15 EUR / Stunde"
// fuer "Starting Soon" Logik
// Anzeige: "Today, 18:00-23:00"
// published, draft, inProgress, completed, cancelled
@default(now())
employerId String
id String @id @default(uuid())
title String
company String
location String
lat Float
lng Float
payAmount Float payText String startTime DateTime endTime DateTime
shiftText String shortInfo String
tags String[]
logoEmoji String
category String
status String openSpots Int
createdAt DateTime }
Neue Endpunkte
GET /jobs?type=quickMoney → Jobs die in <4h starten, hohe Bezahlung
GET /jobs?type=startingSoon → Jobs die heute oder morgen starten
GET /jobs?type=popular → Jobs mit 10+ Bewerbungen
GET /jobs?type=recommended → Basierend auf User-Skills/Kategorien (MVP: zufaellig)
GET /jobs?category=Hospitality → Kategorie-Filter
GET /jobs/nearby?lat&lng&radius → Radius-Filter (bereits implementiert)
POST /jobs/:id/apply → Bewerbung mit Schicht-Auswahl
GET /messages → Chat-Liste
POST /messages/:jobId → Nachricht senden
GET /companies/:id → Unternehmens-Profil
POST /jobs → Job erstellen (Arbeitgeber)
PATCH /jobs/:id → Job aktualisieren
DELETE /jobs/:id → Job stornieren
GET /employer/applicants → Alle Bewerber
POST /employer/applicants/:id/accept
POST /employer/applicants/:id/decline
10. Prioritaeten — In dieser Reihenfolge implementieren
Prioritaet 1: Radar View (MapKit)
• MapKit Map (45% Hoehe initial)
• Farbige Pins (blau/orange/gruen), Clustering
• Pin-Tippen → Job-Karte highlighten + scrollen
• Scroll-Verhalten: Map schrumpft auf 25% beim Scrollen
Prioritaet 2: Job Detail View
• Vollstaendige Implementierung laut Wireframe
• Apply-Button (sticky)
• Company-Section mit Weiterleitung
Prioritaet 3: Apply Flow
• 1 Schicht: Bestaeigungs-Sheet
• Mehrere Schichten: Schicht-Auswahl → Bestaetigung
• Alle Erfolgs-/Fehlerzustaende
Prioritaet 4: Messages Tab (Worker)
• Chat-Liste mit Status-Badges und Sortierung
• Leerzustand
• Inside Chat Screen
• Read-only nach Abschluss/Stornierung
Prioritaet 5: Employer Home View
• Dashboard mit Stats, Needs Attention, Quick Actions
• Navigation zu allen Arbeitgeber-Screens
Prioritaet 6: Post a New Job Screen
• Komplexes Formular laut Wireframe
• Save as Draft + Post Job
Prioritaet 7: Worker Profile Screen
• Navigations-Menue
• Alle Sub-Screens: Edit Profile, Job Applications, Calendar, Financial Overview, Settings, Reviews, Saved
11. Hinweise fuer Claude Code
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