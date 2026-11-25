//
//  ApplyFlowView.swift
//  swipeShift
//
//  Apply Flow: Schicht-Auswahl → Bestätigung → Ergebnis

import SwiftUI

// MARK: - Flow-Schritte
private enum ApplyStep {
    case selectShifts
    case confirm
    case loading
    case result(ApplyResult)
}

enum ApplyResult {
    case submitted
    case booked          // Instant Match: sofort angenommen
    case connectionLost
    case shiftAlreadyTaken
    case shiftUnavailable
    case schedulingConflict
    case accountPaused
    case blocked
}

// MARK: - ApplyFlowView
struct ApplyFlowView: View {
    let job: Job

    @EnvironmentObject var jobStore: JobStore
    @Environment(\.dismiss) private var dismiss

    // Wird von außen gesetzt um nach Erfolg den Detail-Screen zu schließen
    var onSuccess: (() -> Void)? = nil
    // Wird von außen gesetzt um bei "Shift Already Taken"/"Shift Unavailable" komplett zurück
    // zur Job-Liste zu navigieren (schließt Apply-Sheet UND den darunterliegenden Detail-Screen,
    // ohne den Success-Seiteneffekt auszulösen)
    var onExitToJobList: (() -> Void)? = nil

    @State private var step: ApplyStep
    @State private var selectedShiftIds: Set<String> = []

    /// `initialResult`: Sheet startet direkt im Ergebnis-Zustand (z.B. nach Sofort-Apply-Fehler im Swipe)
    init(job: Job, initialResult: ApplyResult? = nil, onSuccess: (() -> Void)? = nil, onExitToJobList: (() -> Void)? = nil) {
        self.job = job
        self.onSuccess = onSuccess
        self.onExitToJobList = onExitToJobList
        // Direkt zur Bestätigung wenn 0 oder 1 Schicht
        if let initialResult {
            self._step = State(initialValue: .result(initialResult))
        } else if ApplyFlowView.hasNoBookableShift(job) {
            self._step = State(initialValue: .result(.shiftUnavailable))
        } else {
            self._step = State(initialValue: ApplyFlowView.needsShiftSelection(job) ? .selectShifts : .confirm)
        }
    }

    // MARK: - Schicht-Logik (geteilt mit JobSwipeView)

    /// Buchbare Schichten: noch nicht begonnen (Schichten ohne Startzeit gelten als buchbar).
    /// Ob eine Schicht voll ist, weiss nur das Backend (SHIFT_TAKEN beim Apply).
    static func bookableShifts(of job: Job, now: Date = Date()) -> [JobShift] {
        (job.shifts ?? []).filter { ($0.startDate ?? .distantFuture) > now }
    }

    /// Mehr als eine buchbare Schicht → Schicht-Auswahl noetig, sonst direkt bestaetigen/bewerben.
    static func needsShiftSelection(_ job: Job, now: Date = Date()) -> Bool {
        bookableShifts(of: job, now: now).count > 1
    }

    /// Schichtliste vorhanden, aber keine davon buchbar (alle gestartet) → "Shift Unavailable"
    static func hasNoBookableShift(_ job: Job, now: Date = Date()) -> Bool {
        !(job.shifts ?? []).isEmpty && bookableShifts(of: job, now: now).isEmpty
    }

    /// Sofort-Apply nur bei genau einer buchbaren Schicht oder Job ganz ohne Schichtliste
    static func canApplyImmediately(_ job: Job, now: Date = Date()) -> Bool {
        (job.shifts ?? []).isEmpty || singleShiftIds(for: job, now: now) != nil
    }

    /// Fehler des Apply-Calls → Ergebniszustand
    static func result(for error: Error) -> ApplyResult {
        guard let applyError = error as? ApplyError else { return .connectionLost }
        switch applyError {
        case .shiftTaken:         return .shiftAlreadyTaken
        case .jobUnavailable:     return .shiftUnavailable
        case .schedulingConflict: return .schedulingConflict
        case .shiftUnavailable:   return .shiftUnavailable
        case .accountPaused:      return .accountPaused
        case .blocked:            return .blocked
        case .tryAgain:           return .connectionLost
        }
    }

    /// shiftIds fuer einen Sofort-Apply (genau eine buchbare Schicht); nil bei Jobs ohne Schichtliste.
    static func singleShiftIds(for job: Job, now: Date = Date()) -> [String]? {
        let shifts = bookableShifts(of: job, now: now)
        return shifts.count == 1 ? [shifts[0].id] : nil
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stepAnimation: Animation? { reduceMotion ? nil : DS.Motion.standard.animation }

    /// Fortschritt nur im Mehrschicht-Flow (Schicht-Auswahl → Bestaetigung)
    private var progressIndex: Int? {
        guard ApplyFlowView.needsShiftSelection(job) else { return nil }
        switch step {
        case .selectShifts: return 0
        case .confirm: return 1
        default: return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag Handle
            Capsule()
                .fill(DS.Color.border)
                .frame(width: 36, height: 4)
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.xxs)

            if let progressIndex {
                DSProgressSteps(steps: ["Shifts", "Confirm"], current: progressIndex)
                    .padding(.horizontal, DS.Spacing.screenEdge)
                    .padding(.top, DS.Spacing.xs)
            }

            switch step {
            case .selectShifts:
                ShiftSelectionView(
                    job: job,
                    selectedShiftIds: $selectedShiftIds,
                    onNext: {
                        withAnimation(stepAnimation) { step = .confirm }
                    },
                    onDismiss: { dismiss() }
                )

            case .confirm:
                ConfirmationView(
                    job: job,
                    selectedShifts: selectedShiftsForConfirmation,
                    onConfirm: { Task { await submitApplication() } },
                    onBack: {
                        let hasMultipleShifts = ApplyFlowView.needsShiftSelection(job)
                        if hasMultipleShifts {
                            withAnimation(stepAnimation) { step = .selectShifts }
                        } else {
                            dismiss()
                        }
                    }
                )

            case .loading:
                LoadingApplyView()

            case .result(let result):
                ApplyResultView(
                    result: result,
                    job: job,
                    onDone: {
                        switch result {
                        case .submitted, .booked: onSuccess?()
                        default: break
                        }
                        dismiss()
                    },
                    onRetry: {
                        Task { await submitApplication() }
                    },
                    onExitToJobList: {
                        onExitToJobList?()
                        dismiss()
                    }
                )
            }
        }
        .dsBackground()
        .presentationDetents(presentationDetent)
        .presentationDragIndicator(.hidden)
    }

    // Dynamische Sheet-Höhe je nach Schritt
    private var presentationDetent: Set<PresentationDetent> {
        switch step {
        case .loading: return [.height(200)]
        case .result:  return [.medium]
        default:       return [.large]
        }
    }

    /// Schichten die bestätigt werden: entweder ausgewählte oder die einzige Schicht des Jobs
    private var selectedShiftsForConfirmation: [JobShift] {
        let shifts = ApplyFlowView.bookableShifts(of: job)
        if selectedShiftIds.isEmpty { return shifts }
        return shifts.filter { selectedShiftIds.contains($0.id) }
    }

    /// Schicht-IDs fuer den Backend-Call: die ausgewaehlten (in Job-Reihenfolge) bzw. alle Schichten bei Single-Shift-Jobs.
    /// nil bei Jobs ohne Schicht-Eintraege → Backend bucht dann "alle".
    private var shiftIdsToBook: [String]? {
        let shifts = ApplyFlowView.bookableShifts(of: job)
        if (job.shifts ?? []).isEmpty { return nil }   // Altbestand ohne Schichtliste → Backend bucht "alle"
        if shifts.isEmpty { return [] }                // nie "alle" buchen, wenn nichts buchbar ist
        if selectedShiftIds.isEmpty { return shifts.map(\.id) }
        return shifts.map(\.id).filter { selectedShiftIds.contains($0) }
    }

    @MainActor
    private func submitApplication() async {
        withAnimation(stepAnimation) { step = .loading }

        do {
            try await Task.sleep(nanoseconds: 900_000_000) // 0.9s UX-Feedback
            let autoAccepted = try await jobStore.apply(to: job, shiftIds: shiftIdsToBook)
            withAnimation(stepAnimation) { step = .result(autoAccepted ? .booked : .submitted) }
        } catch {
            withAnimation(stepAnimation) { step = .result(ApplyFlowView.result(for: error)) }
        }
    }
}

// MARK: - Gemeinsame Bausteine

/// Sheet-Kopf: runder Icon-Button links, Titel mittig
private struct ApplySheetHeader: View {
    let title: String
    let systemIcon: String
    let iconLabel: String
    let action: () -> Void

    var body: some View {
        HStack {
            DSIconButton(systemName: systemIcon, label: iconLabel, action: action)
            Spacer()
            Text(title)
                .dsFont(.headline)
                .foregroundStyle(DS.Color.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, DS.Spacing.screenEdge)
        .padding(.vertical, DS.Spacing.xs)
    }
}

/// Job-Kurzinfo (nicht antippbar)
private struct ApplyJobSummary: View {
    let job: Job
    var showsPay: Bool = false

    var body: some View {
        DSCard {
            HStack(spacing: DS.Spacing.sm) {
                DSAvatar(text: job.logoEmoji, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title).dsFont(.headline).foregroundStyle(DS.Color.text)
                    Text(job.company).dsFont(.caption).foregroundStyle(DS.Color.muted)
                }
                Spacer(minLength: DS.Spacing.xs)
                if showsPay {
                    Text(job.payText)
                        .font(DS.Font.make(15, .bold))
                        .foregroundStyle(DS.Color.primaryText)
                }
            }
        }
    }
}

/// Getoenter Hinweisblock mit Icon
private struct ApplyNotice: View {
    let systemIcon: String
    let tone: DS.Tone
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Image(systemName: systemIcon)
                .font(DS.Font.make(15, .semibold))
                .foregroundStyle(tone.foreground)
                .accessibilityHidden(true)
            Text(text)
                .dsFont(.caption)
                .foregroundStyle(DS.Color.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.soft, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

// MARK: - Schritt 1: Schicht-Auswahl
private struct ShiftSelectionView: View {
    let job: Job
    @Binding var selectedShiftIds: Set<String>
    let onNext: () -> Void
    let onDismiss: () -> Void

    private var shifts: [JobShift] { ApplyFlowView.bookableShifts(of: job) }
    private var canProceed: Bool { !selectedShiftIds.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            ApplySheetHeader(title: "Select Shifts", systemIcon: "xmark", iconLabel: "Close", action: onDismiss)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    ApplyJobSummary(job: job, showsPay: true)

                    // Schicht-Checkboxen
                    DSSection("Select one or more shifts") {
                        ForEach(Array(shifts.enumerated()), id: \.element.id) { idx, shift in
                            ShiftCheckboxRow(
                                shift: shift,
                                showsDivider: idx > 0,
                                isSelected: selectedShiftIds.contains(shift.id),
                                onToggle: {
                                    DS.Haptics.selection()
                                    if selectedShiftIds.contains(shift.id) {
                                        selectedShiftIds.remove(shift.id)
                                    } else {
                                        selectedShiftIds.insert(shift.id)
                                    }
                                }
                            )
                        }
                    }

                    // Ausgewaehlt-Zaehler
                    if !selectedShiftIds.isEmpty {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("\(selectedShiftIds.count) shift\(selectedShiftIds.count == 1 ? "" : "s") selected")
                        }
                        .dsFont(.callout)
                        .foregroundStyle(DS.Color.primaryText)
                        .transition(.opacity)
                    }
                }
                .padding(DS.Spacing.screenEdge)
                .dsAnimation(.snappy, value: selectedShiftIds)
            }

            applyFooter(
                buttonLabel: "Next",
                isEnabled: canProceed,
                action: onNext,
                onDismiss: onDismiss
            )
        }
    }
}

// MARK: - Schicht-Checkbox-Zeile
private struct ShiftCheckboxRow: View {
    let shift: JobShift
    let showsDivider: Bool
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        DSRow(
            shift.date,
            subtitle: "\(shift.timeRange) · \(shift.duration)",
            value: shift.totalPay,
            accentValue: isSelected,
            showsDivider: showsDivider,
            action: onToggle
        ) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(DS.Font.make(22, .regular, relativeTo: nil))
                .foregroundStyle(isSelected ? DS.Color.primary : DS.Color.border)
                .dsAnimation(.snappy, value: isSelected)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Schritt 2: Bestaetigung
private struct ConfirmationView: View {
    let job: Job
    let selectedShifts: [JobShift]
    let onConfirm: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ApplySheetHeader(title: "Confirm Application", systemIcon: "chevron.left", iconLabel: "Back", action: onBack)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    ApplyJobSummary(job: job)

                    // Schicht-Details
                    if !selectedShifts.isEmpty {
                        DSSection("Selected Shifts") {
                            ForEach(Array(selectedShifts.enumerated()), id: \.element.id) { idx, shift in
                                DSRow(
                                    shift.date,
                                    subtitle: "\(shift.timeRange) · \(shift.duration)",
                                    value: shift.totalPay,
                                    accentValue: true,
                                    showsDivider: idx > 0
                                )
                            }
                        }
                    } else {
                        // Kein shifts-Array (Single-Shift via shiftText)
                        DSSection("Details") {
                            DSRow("Shift", value: job.shiftText, systemIcon: "calendar", showsDivider: false)
                            DSRow("Location", value: job.location, systemIcon: "mappin")
                            DSRow("Pay", value: job.payText, systemIcon: "banknote")
                            if let method = job.paymentMethod {
                                DSRow("Payment", value: method, systemIcon: "creditcard")
                            }
                        }
                    }

                    // Instant Match: Hinweis auf sofortige Buchung
                    if job.instantMatch {
                        ApplyNotice(
                            systemIcon: "bolt.fill",
                            tone: .primary,
                            text: "You'll be booked immediately — no waiting for approval."
                        )
                    }

                    // Rechtlicher Hinweis
                    ApplyNotice(
                        systemIcon: "info.circle.fill",
                        tone: .warning,
                        text: job.instantMatch
                            ? "Spots are limited. If all spots are filled by the time you apply, your application stays pending and the employer will review it."
                            : "Applying does not commit you to anything until confirmed. The employer will review your profile and get back to you via chat."
                    )
                }
                .padding(DS.Spacing.screenEdge)
            }

            applyFooter(
                buttonLabel: "Submit Application",
                isEnabled: true,
                action: onConfirm,
                onDismiss: onBack
            )
        }
    }
}

// MARK: - Schritt 3a: Laden
private struct LoadingApplyView: View {
    var body: some View {
        VStack(spacing: DS.Spacing.md) {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(DS.Color.primary)
            Text("Submitting application…")
                .dsFont(.body)
                .foregroundStyle(DS.Color.text2)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .padding(DS.Spacing.md)
    }
}

// MARK: - Schritt 3b: Ergebnis
struct ApplyResultView: View {
    let result: ApplyResult
    let job: Job
    let onDone: () -> Void
    var onRetry: () -> Void = {}
    var onExitToJobList: () -> Void = {}

    @State private var showCalendarSheet = false
    @State private var iconVisible = false

    private var config: ResultConfig { ResultConfig(result: result, job: job) }

    /// Primaer-Button-Aktion: je nach Ergebniszustand navigiert/handelt der Button tatsaechlich,
    /// statt immer nur das Sheet zu schliessen (dismiss)
    private func primaryAction() {
        switch result {
        case .submitted, .booked:
            onDone()
        case .connectionLost:
            onRetry()
        case .shiftAlreadyTaken, .shiftUnavailable:
            onExitToJobList()
        case .accountPaused, .blocked:
            onDone()
        case .schedulingConflict:
            showCalendarSheet = true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: DS.Spacing.md) {
                // Icon im getoenten Kreis
                Image(systemName: config.iconName)
                    .font(DS.Font.make(34, .semibold, relativeTo: nil))
                    .foregroundStyle(config.tone.foreground)
                    .frame(width: 80, height: 80)
                    .background(config.tone.soft, in: Circle())
                    .scaleEffect(iconVisible ? 1 : 0.7)
                    .opacity(iconVisible ? 1 : 0)
                    .accessibilityHidden(true)

                VStack(spacing: DS.Spacing.xs) {
                    Text(config.title)
                        .dsFont(.title)
                        .foregroundStyle(DS.Color.text)
                        .multilineTextAlignment(.center)

                    Text(config.message)
                        .dsFont(.body)
                        .foregroundStyle(DS.Color.text2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, DS.Spacing.screenEdge)

            Spacer()

            VStack(spacing: DS.Spacing.xs) {
                // Primaer-Aktion
                Button(config.primaryActionLabel) { primaryAction() }
                    .buttonStyle(.ds(.primary))

                // Sekundaer-Aktion (nur bei Fehlern) — schliesst immer nur das Apply-Sheet
                if let secondaryLabel = config.secondaryActionLabel {
                    Button(secondaryLabel) { onDone() }
                        .buttonStyle(.ds(.secondary, size: .medium))
                }
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.bottom, DS.Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Spacing.sm)
        .onAppear {
            switch result {
            case .submitted, .booked: DS.Haptics.success()
            default: DS.Haptics.warning()
            }
            withAnimation(DS.Motion.standard.animation) { iconVisible = true }
        }
        .sheet(isPresented: $showCalendarSheet) {
            WorkerCalendarView()
        }
    }
}

// MARK: - Result Config
private struct ResultConfig {
    let iconName: String
    let tone: DS.Tone
    let title: String
    let message: String
    let primaryActionLabel: String
    let secondaryActionLabel: String?

    init(result: ApplyResult, job: Job) {
        switch result {
        case .submitted:
            iconName        = "checkmark.circle.fill"
            tone            = .success
            title           = "Application Submitted!"
            message         = "Your application to \(job.company) was successfully submitted. You'll receive a reply in chat."
            primaryActionLabel   = "Done"
            secondaryActionLabel = nil

        case .booked:
            iconName        = "bolt.circle.fill"
            tone            = .success
            title           = "You're booked!"
            message         = "\(job.company) uses Instant Match, so your spot is confirmed. Find the details in your chat and calendar."
            primaryActionLabel   = "Done"
            secondaryActionLabel = nil

        case .connectionLost:
            iconName        = "wifi.slash"
            tone            = .warning
            title           = "Connection Lost"
            message         = "Your application could not be sent. Please check your internet connection and try again."
            primaryActionLabel   = "Try Again"
            secondaryActionLabel = "Cancel"

        case .shiftAlreadyTaken:
            iconName        = "person.fill.xmark"
            tone            = .danger
            title           = "Shift Already Taken"
            message         = "Unfortunately this shift has already been taken by someone else."
            primaryActionLabel   = "View Other Shifts"
            secondaryActionLabel = "Back to Overview"

        case .shiftUnavailable:
            iconName        = "calendar.badge.minus"
            tone            = .danger
            title           = "Shift Unavailable"
            message         = "This shift is no longer available. The employer may have removed it."
            primaryActionLabel   = "View Other Jobs"
            secondaryActionLabel = "Back"

        case .schedulingConflict:
            iconName        = "exclamationmark.triangle.fill"
            tone            = .warning
            title           = "Scheduling Conflict Detected"
            message         = "You already have another job at this time. Check your calendar before applying."
            primaryActionLabel   = "View My Calendar"
            secondaryActionLabel = "Go Back Anyway"

        case .accountPaused:
            iconName        = "pause.circle.fill"
            tone            = .warning
            title           = "Your Account Is Paused"
            message         = "You can't apply while your account is paused. Resume it under Account Settings → Privacy & Data."
            primaryActionLabel   = "OK"
            secondaryActionLabel = nil

        case .blocked:
            iconName        = "hand.raised.fill"
            tone            = .warning
            title           = "Can't Apply"
            message         = "You can't apply to this employer."
            primaryActionLabel   = "OK"
            secondaryActionLabel = nil
        }
    }
}

// MARK: - Shared Footer
private func applyFooter(
    buttonLabel: String,
    isEnabled: Bool,
    action: @escaping () -> Void,
    onDismiss: @escaping () -> Void
) -> some View {
    VStack(spacing: 0) {
        DSDivider()
        HStack(spacing: DS.Spacing.sm) {
            Button("Cancel") { onDismiss() }
                .buttonStyle(.ds(.secondary, fullWidth: false))
                .frame(width: 100)

            Button(buttonLabel, action: action)
                .buttonStyle(.ds(.primary))
                .disabled(!isEnabled)
        }
        .padding(.horizontal, DS.Spacing.screenEdge)
        .padding(.vertical, DS.Spacing.sm)
    }
    .background(DS.Color.surface.ignoresSafeArea(edges: .bottom))
}
