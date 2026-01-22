## File: swipeShiftApp.swift

### Responsibility
`swipeShiftApp` is the entry point of the iOS app.

Responsibilities:
- creates global app state objects
- injects them into the SwiftUI environment
- defines the initial root view

### Key Concepts

**@main**
Marks the starting point of the app. iOS always launches the app here.

**Global State Objects**
- `UserStore`: holds authentication state (`currentUser`)
- `JobStore`: holds job data and filtering state

They are created using `@StateObject` to ensure they live for the entire app lifecycle.

**Environment Injection**
Both stores are injected via `.environmentObject`, allowing all child views to access them without manual passing.

---

## File: ContentView.swift

### Responsibility
`ContentView` is the central routing view of the app.

It decides:
- whether a user is logged in
- which main screen to show
- which role-based home view to display

### Routing Logic

- If `currentUser == nil` → show `MainView`
- If role is `worker` → show `WorkerHomeView`
- If role is `employer` → show `EmployerHomeView`

This routing is purely state-based and does not rely on navigation stacks or routers.

### Design Notes
- `Group {}` is used to satisfy SwiftUI’s requirement of returning a single view.
- Debug logs (`onAppear`, `onChange`) are temporary and help trace auth state changes.

## File: MainView.swift

### Responsibility
`MainView` is the public entry point for unauthenticated users.

It defines the initial navigation structure of the app before a user logs in and serves as the container for the authentication flow.

### Key Responsibilities
- creates the root `NavigationStack`
- displays the landing screen (`LandingView`)
- acts as the entry point for Login and Registration navigation

`MainView` itself does not contain business logic or state; it only manages navigation structure.

---

## File: LandingView (inside MainView.swift)

### Responsibility
`LandingView` is the first visible screen shown to users who are not logged in.

It allows the user to:
- navigate to the Login screen
- navigate to the Registration screen
- see basic branding and introductory copy

### Key Concepts

**Navigation**
- Uses `NavigationLink` to push `LoginView` and `RegisterView` onto the navigation stack.
- No authentication logic is handled here.

**Environment Usage**
- Reads `UserStore` only for optional debug/status display.
- Does not mutate user state.

### Design Notes
- Uses `Spacer()` to create vertical layout balance.
- Background gradient is purely visual and has no functional role.
- Footer text is informational only.

---

## File: LoginView.swift

### Responsibility
`LoginView` handles user authentication input and triggers the login process.

It is responsible for:
- collecting email and password
- triggering login via `UserStore`
- displaying login errors
- reacting to successful authentication indirectly via state changes

### State Management

**Local State**
- `email`, `password`: bound to input fields
- `errorMessage`: local UI error display

**Global State**
- accesses `UserStore` via `@EnvironmentObject`
- does not directly interact with `APIClient`

### Authentication Flow

1. User enters credentials
2. User taps "Login"
3. `handleLogin()` is called
4. `LoginView` calls `userStore.loginRemote(...)`
5. `UserStore` performs the network request
6. On success:
   - `currentUser` is set
   - `ContentView` reacts and switches the root view
7. On failure:
   - error message is shown inline

### Design Notes
- Button is disabled if inputs are empty
- Validation here is minimal; full validation happens server-side
- Navigation title is set to `.inline` to keep UI compact

File: RegisterView.swift

Purpose

RegisterView ist die komplette Registrierungs-UI für Worker und Employer.
Sie sammelt Eingaben, zeigt Inline-Fehler an und triggert anschließend UserStore.registerRemote(...).

Responsibilities
    •    UI für Rollenwahl (worker/employer)
    •    Formularfelder pro Rolle rendern
    •    lokale States halten (@State)
    •    Client-side validation via FormValidator
    •    Request-Body als RegisterRequestDTO bauen
    •    Profilfoto optional an UserStore.registerRemote(request:profileImage:) übergeben
    •    Backend-Errors (über userStore.errorMessage) anzeigen

Data Flow
    1.    User füllt Felder aus
    2.    Tap auf “Create Account” → handleRegister()
    3.    FormValidator.validateWorker/validateEmployer(...) liefert fieldErrors
    4.    Wenn fieldErrors leer: RegisterRequestDTO wird gebaut
    5.    UserStore.registerRemote(request: body, profileImage: profileUIImage) wird async gestartet
    6.    Bei Erfolg: userStore.currentUser wird gesetzt → ContentView routet automatisch weiter

Notes / TODO
    •    fieldErrors bei JobInterests ist aktuell im ForEach platziert → sollte unterhalb der ganzen Liste angezeigt werden (sonst wird es mehrfach gerendert).
    •    Button ist aktuell immer aktiv (disabled auskommentiert). Gute UX ist:
    •    Button immer aktiv, aber zeigt Fehler beim Klicken oder
    •    Button disabled, aber dann Fehler per “onChange/Focus” zeigen (sonst sieht man Fehler nie).
    •    profilePhotoUrl wird noch nicht gesetzt (kommt später vom Upload).

⸻

File: UserStore.swift

Purpose

UserStore ist der zentrale Auth-State der App (EnvironmentObject).
Views sprechen nur mit UserStore, nicht direkt mit APIClient.

Responsibilities
    •    hält currentUser (eingeloggt / registriert)
    •    hält errorMessage (für UI)
    •    führt loginRemote aus
    •    führt registerRemote aus inkl. optionalem Profilbild-Upload
    •    logout() setzt Token & User zurück

Data Flow

Login
    •    LoginView → userStore.loginRemote(email:password:)
    •    APIClient.login(...) → speichert Token → gibt UserDTO zurück
    •    UserStore.currentUser = user

Register
    •    RegisterView baut RegisterRequestDTO
    •    RegisterView → userStore.registerRemote(request:profileImage:)
    •    optional: APIClient.uploadProfilePhoto(image) → URL zurück
    •    Request wird mit profilePhotoUrl neu gebaut
    •    APIClient.register(requestBody:) → speichert Token → gibt UserDTO zurück
    •    UserStore.currentUser = user

Notes / TODO
    •    UIKit Import ist hier richtig, weil UIImage verwendet wird.
    •    Backend-Errors sollten idealerweise als strukturierte FieldErrors gemappt werden (später).

⸻

File: JobStore.swift

Purpose

JobStore hält den Job-State für die UI (EnvironmentObject).
Er lädt Jobs vom Backend und verarbeitet Swipe-Aktionen (apply/skip).

Responsibilities
    •    jobs: [Job] für UI
    •    selectedLocation als Filter (z. B. aus User-Location)
    •    loadJobs() lädt Jobs vom Backend (via APIClient)
    •    apply(to:) und skip(_:) informieren Backend und entfernen Job lokal

Data Flow
    1.    selectedLocation wird gesetzt (z. B. setInitialLocationIfNeeded(from:))
    2.    UI ruft await jobStore.loadJobs()
    3.    APIClient.fetchJobs(location:) → Backend → Jobs → jobs wird gesetzt
    4.    Swipe:
    •    apply oder skip → POST ans Backend
    •    Job wird lokal aus jobs entfernt → UI aktualisiert sich

Notes / TODO
    •    In skip/apply wird aktuell try? genutzt → Fehler verschwinden still.
Besser: do/catch und errorMessage setzen (du hast das in einer anderen Version schon sauber dokumentiert).
    •    selectedLocation ist Pflicht, sonst werden Jobs geleert → bewusstes Verhalten.

⸻

File: FormValidator.swift

Purpose

FormValidator ist die reine Client-side Validierung.
Er liefert pro Feld einen Fehlertext zurück: [FieldKey: String].

Responsibilities
    •    Worker: required fields + Email-Format + Passwortlänge + Confirm Match + 18+ + JobInterests min 1 + Availability min 1 day + Terms
    •    Employer: required fields + Email-Format + Passwortlänge + Confirm Match + CompanySize + Terms

Output Contract
    •    Gibt ein Dictionary zurück:
    •    Key = FieldKey (UI-Feld)
    •    Value = String (englischer Fehlertext)
    •    UI zeigt fieldErrors[.<field>] unter dem passenden Feld an.

Notes / TODO
    •    Email Regex ist MVP-tauglich (nicht RFC-perfect) — ok für MVP.
    •    Validation für Availability: korrekt (mindestens ein Tag available == true).
    
    
    
File: WorkerHomeView.swift

Purpose

WorkerHomeView ist die Startseite für eingeloggte Worker.
Sie dient als Einstiegspunkt nach Login/Registrierung und leitet zur Job-Suche weiter.

Responsibilities
    •    Begrüßung des eingeloggten Users
    •    Einstiegspunkt zur Job-Exploration
    •    Initiales Setzen der Job-Location aus dem User-Profil
    •    Logout-Funktion bereitstellen

Data Flow
    1.    ContentView routed hierher, wenn
userStore.currentUser != nil und role == worker
    2.    View liest currentUser aus UserStore
    3.    Beim Klick auf Explore jobs:
    •    Navigation zu JobSwipeView (oder JobListView)
    •    onAppear setzt einmalig:
    
    jobStore.selectedLocation = userStore.currentUser?.location
    
    4.    Ab hier ist JobStore bereit, Jobs zu laden

Architektur-Entscheidungen
    •    NavigationStack liegt in der HomeView, nicht global
    •    Vorteil: klare Navigations-Hierarchie pro Rolle
    •    Location-Logik liegt nicht im APIClient
    •    sondern in der View / im Store → UI-nahe Logik

Notes / TODO
    •    Location wird nur gesetzt, wenn selectedLocation == nil
→ überschreibt keine manuell gesetzten Filter
    •    Logout ruft userStore.logout() auf
→ ContentView reagiert automatisch und zeigt MainView

⸻

File: JobListView.swift

Purpose

JobListView zeigt Jobs klassisch als Liste an.
Sie ist eine alternative Darstellung zur Swipe-UI (JobSwipeView).

Responsibilities
    •    Darstellung der Job-Liste (jobStore.jobs)
    •    Navigation zu JobDetailView
    •    Initiales Laden der Jobs beim Erscheinen
    •    Anzeige von Fehlern (z. B. fehlender Token)

Data Flow
    1.    View erscheint
    2.    .task { ... } wird ausgeführt
    3.    Prüft:
    APIClient.shared.token != nil
    
    4.    Falls Token vorhanden:
    •    await jobStore.loadJobs()
    5.    JobStore lädt Jobs → jobs wird gesetzt
    6.    List rendert automatisch die Jobs

Architektur-Entscheidungen
    •    JobListView spricht nur mit JobStore
    •    Ausnahme: Token-Check via APIClient.shared.token
    •    MVP-Entscheidung (später über Store abstrahieren)
    •    Navigation zu JobDetailView erfolgt per NavigationLink

Notes / TODO
    •    Token-Check gehört langfristig in den JobStore
    •    Fehleranzeige ist lokal (@State errorMessage)
→ könnte vereinheitlicht werden (z. B. globales Error-Banner)
    •    Wird perspektivisch durch JobSwipeView ersetzt oder ergänzt
    
    
    File: swipeShiftApp (L1_DemoApp.swift)

Responsibility
    •    App-Entry-Point (@main): iOS startet hier.
    •    Erstellt globale App-States als @StateObject:
    •    UserStore (Auth/User State)
    •    JobStore (Job Feed State)
    •    Injiziert beide Stores via .environmentObject(...) in die View-Hierarchie, damit alle Screens Zugriff haben.

Key Concepts
    •    @StateObject ist wichtig, damit Store-Instanzen nur einmal erstellt werden (nicht bei jedem Re-Render).
    •    environmentObject macht die Stores global verfügbar:
    •    Views müssen nicht überall Props durchreichen (“prop drilling”).

App Flow
    •    Erste View ist ContentView.
    •    ContentView entscheidet anhand userStore.currentUser, ob:
    •    MainView (logged out)
    •    WorkerHomeView oder EmployerHomeView (logged in)

Notes / TODO
    •    Später: Token persistent speichern (Keychain) → dann beim App-Start currentUser ggf. wiederherstellen.

⸻

File: ContentView.swift

Responsibility
    •    “Router View” der App.
    •    Entscheidet, welche Haupt-UI angezeigt wird, basierend auf Login-State.

Logic
    •    userStore.currentUser == nil → MainView
    •    userStore.currentUser != nil → nach Rolle:
    •    .worker → WorkerHomeView
    •    .employer → EmployerHomeView

Debug
    •    onAppear + onChange sind aktuell nur Debug-Logs.
    •    Für Produktion: Debug-Logs entfernen oder über ein Debug-Flag steuern.

Why this is good
    •    Single Source of Truth: Login-State sitzt im UserStore.
    •    UI reagiert automatisch auf @Published currentUser:
    •    Login/Register setzt currentUser → ContentView rendert Home.
    •    Logout setzt currentUser = nil → ContentView rendert MainView.
