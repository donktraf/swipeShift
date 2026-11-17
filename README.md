# SwipeShift

Ein flexibler Job-Marktplatz für kurzfristige Schichten: Arbeitnehmer durchsuchen, swipen oder
filtern Jobs; Arbeitgeber schreiben Jobs aus, verwalten Bewerber und wickeln Zahlungen ab.

- **iOS App:** SwiftUI, iOS 17+
- **Backend:** Node.js, Express, Prisma ORM, PostgreSQL

## Projektstruktur

```
swipeshift/            iOS-App (SwiftUI)
├── Features/           Screens nach Worker/Employer/Auth/Onboarding gegliedert
├── Stores/              @MainActor ObservableObjects (UserStore, JobStore, MessageStore)
├── DTOs/                Codable-Modelle für die Backend-Kommunikation
├── Networking/          APIClient (singleton), Multipart-Upload
├── Models/              Domain-Modelle
└── utils/               Theme, FormValidator

swipeshift-backend/    Node.js/Express-Backend
├── src/routes.*.js     Auth, Jobs, Employer, Messages, Companies, Worker, Notifications
├── src/middlewares/     JWT-Auth, Email-Verifikation
├── prisma/schema.prisma Datenmodell
└── docker-compose.yml  PostgreSQL + MailHog
```

Details zu Architektur-Entscheidungen und aktuellem Implementierungsstand: siehe
[`CLAUDE.md`](CLAUDE.md) und [`PROGRESS.md`](PROGRESS.md).

## Voraussetzungen

- Xcode 15+ (iOS 17 SDK)
- Node.js 20+
- Docker (für PostgreSQL + MailHog)

## Backend starten

```bash
cd swipeshift-backend
npm install

# PostgreSQL + MailHog starten
docker compose up -d

# .env anlegen (siehe Variablen unten), dann Migrationen anwenden
npx prisma migrate deploy
npx prisma db seed   # optional: Demo-Daten

npm run dev           # nodemon, http://localhost:3000
```

### Benötigte Umgebungsvariablen (`swipeshift-backend/.env`)

| Variable | Beschreibung |
|---|---|
| `DATABASE_URL` | Postgres-Connection-String (z.B. `postgresql://swipeshift:swipeshift_pw@localhost:5432/swipeshift_dev`) |
| `JWT_SECRET` | Secret zum Signieren der Auth-Tokens |
| `PORT` | Server-Port (Standard: `3000`) |
| `NODE_ENV` | `development` / `test` / `production`. Ohne `development`/`test` bricht der Start ohne `TOTP_ENCRYPTION_KEY` und `BACKUP_CODE_PEPPER` ab. `npm run dev`/`npm test` setzen es per Shell-Syntax (macOS/Linux vorausgesetzt) |
| `TOTP_ENCRYPTION_KEY` | 32 Byte (`openssl rand -hex 32`) zum Verschlüsseln der Authenticator-Secrets; Rotation siehe `scripts/rotate-totp-key.js` (`TOTP_ENCRYPTION_KEY_PREVIOUS`) |
| `BACKUP_CODE_PEPPER` | 32 Byte, stabil (nicht rotieren) für Backup-Codes |
| `TRUST_PROXY` | Nur hinter Proxy: Hop-Anzahl (z.B. `1`) oder Proxy-IPs/CIDRs, nie `true` |
| `SUPPORT_EMAIL` | Empfänger für Safety-Meldungen (Standard `support@swipeshift.app`) |
| `GOOGLE_CLIENT_ID` | Google Sign-In |
| `APPLE_CLIENT_ID` | Apple Sign-In |
| `APP_SCHEME` | Custom URL Scheme für OAuth-Redirects in der iOS-App |
| `SMTP_HOST`, `SMTP_PORT` | MailHog lokal: `localhost`, `1025` |
| `MAIL_FROM` | Absenderadresse für Verifikations-/Reset-Mails |
| `PUBLIC_API_BASE_URL` | Öffentlich erreichbare Backend-URL (für Links in E-Mails) |
| `PUBLIC_RESET_FALLBACK_URL` | Fallback-Link für Passwort-Reset außerhalb der App |

MailHog-Weboberfläche (lokale Test-Mails): http://localhost:8025

Vorlage: `swipeshift-backend/.env.example`.

### Backend-Tests

```bash
cd swipeshift-backend
npm test
```

## iOS-App starten

1. `swipeShift.xcodeproj` in Xcode öffnen
2. Simulator/Gerät auswählen und Build starten (⌘R)
3. Die App verbindet sich im `DEBUG`-Build standardmäßig mit `http://localhost:3000`
   (siehe `swipeshift/App/AppConfig.swift`) — Backend muss also laufen

Es existiert aktuell kein XCTest-Target im Xcode-Projekt; Details dazu und wie eines ergänzt
werden kann stehen in `CLAUDE.md` (Abschnitt 11/12).

## Design System

Alle Views nutzen ein gemeinsames Design-System (`SS.primary`, `SS.background()`,
`SSPrimaryButtonStyle`, `DashboardJobCard`, ein eigener `AppTabBar` statt SwiftUI `TabView`).
Details siehe `CLAUDE.md`.
