# SwipeShift — Backend Progress

_Zuletzt aktualisiert: 2026-03-28_

---

## ✅ Abgeschlossen

### db.js — Mock-Daten erweitert
- `payAmount` (Number), `startTime` (ISO8601-String), `category` (String) zu allen 5 Mock-Jobs ergänzt
- `shifts` (Array) pro Job: `{ id, date, timeRange, duration, totalPay }`
- Detail-Felder für alle Jobs: `jobDescription`, `tasks`, `openSpots`, `duration`, `dressCode`, `languages`, `experienceLevel`, `minAge`, `paymentMethod`, `contractType`, `companyRating`, `replyTime`, `isVerified`

### routes.jobs.js — POST /jobs Endpoint
- `POST /jobs` erstellt neuen Job mit UUID, legt ihn in `db.jobs` ab
- Gibt `{ job }` mit Status 201 zurück
- Validierung: `title` und `category` erforderlich (400 falls nicht)

### routes.jobs.js — GET /jobs mit type- und category-Filter
- `?type=quickMoney` → startTime ≤ 4h + payAmount ≥ 15
- `?type=startingSoon` → startTime ≤ 48h, sortiert nach Datum
- `?type=popular` → sortiert nach openSpots absteigend (MVP)
- `?type=recommended` → sortiert nach payAmount absteigend (MVP)
- `?category=Events` → Kategorie-Filter (case-insensitive)
- Alle Filter kombinierbar

---

## 🔜 Offen

- Prisma-Schema: `Job`-Modell noch nicht migriert (alles noch in-memory via `db.js`)
- `GET /companies/:id` — Company Profile Endpunkt (Frontend nutzt Mock-Daten)
- `GET /users/:id/applications` — Job Applications für Worker Profile
- `PUT /users/:id` — Profil-Update für EditProfileView
- Upload-Endpoint für Company-Logos / Profilbilder (Multer konfiguriert, kein dedizierter Handler)
- Notifications Endpunkte (GET /notifications)
