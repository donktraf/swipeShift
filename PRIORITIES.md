---
name: next-priority-steps
description: "Prioritätenliste (Stand 2026-06-01): Prios 4-7 erledigt, neue aus TODO-Audit"
metadata: 
  node_type: memory
  type: project
  originSessionId: 0116dd4a-a743-4c21-a3e6-235032ea274c
---

## Abgeschlossen

1. ✅ **Employer Calendar echte Daten** — `GET /employer/calendar`, EmployerCalendarJobDTO, Mock entfernt
2. ✅ **AssignWorkers Mitarbeiter hinzufügen** — `AddWorkerSheet` mit pending Bewerbern, Assign-Button → acceptApplicant, optimistischer UI-Update
3. ✅ **Worker bewertet Employer** — `POST /worker/reviews`, `WorkerReview`-Model, `EmployerRatingSheet`, Company Profile zeigt Breakdown + Review-Karten
4. ✅ **ChatView Worker + Employer: "Rate"-Button verdrahten** — applyId zu Conversation + ConversationDTO; Rate/ReviewFormSheet; reviewSubmitted State
5. ✅ **Edit Profile Worker speichern → PATCH /auth/me** — 10 neue Worker-Felder in Prisma + Migration; upsert-fähig; Swift UpdateProfileRequest + prefillFromUser + save
6. ✅ **Edit Profile Employer speichern → PATCH /employer/profile** — 8 neue Employer-Felder; neuer PATCH-Endpoint; CompanyInfoTab + PersonalProfileTab vollständig verdrahtet
7. ✅ **SwipeJobCard: Employer-Rating-Breakdown anzeigen** — enrichJobsWithRatings(); reviewBreakdown + matchReasons; ratingsBlock() + matchReasonsBlock()

---

## Offene Prios — aus TODO-Audit (2026-06-01)

8. ✅ **JobSwipeView: Bookmark + Filter verdrahten**
   - Bookmark → `POST /jobs/:id/save`; Filter → FilterSheet mit Kategorie-Chips

9. ✅ **ChatView: Info-Button → JobDetailView**
   - `GET /jobs/:id` hinzugefügt; Info-Button fetcht Job + zeigt Sheet mit JobDetailView

10. ✅ **EmployerDashboardView: Bell → NotificationsView**
    - Bell-Button öffnet `NotificationsView` als Sheet

11. ✅ **AccountSettings: Backend-Endpunkte verdrahten**
    - Change Password → `POST /auth/change-password` ✅
    - Change Email → `PATCH /auth/me/email` + Re-Verifikation ✅
    - Change Phone → `PATCH /auth/me` ✅
    - Delete Account → `DELETE /auth/me` + local logout ✅
    - Pause Account → UserDefaults ✅
    - Payout Settings → UserDefaults ✅
    - Privacy Policy / Terms → `openURL` ✅
    - Revoke all sessions → local logout ✅

12. ✅ **WorkerProfileView: echte Daten laden**
    - Rating + Review-Count aus `GET /worker/reviews` (`overallRating` + `totalJobs`)

**Why:** TODO-Audit am 2026-06-01; alle CLAUDE.md-Screens sind implementiert, nur diese Verdrahtungs-Lücken offen.
**How to apply:** Eine Prio pro Turn. Warten auf User-"go" vor Start.
