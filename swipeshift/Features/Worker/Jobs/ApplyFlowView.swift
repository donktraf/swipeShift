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

    init(job: Job, onSuccess: (() -> Void)? = nil, onExitToJobList: (() -> Void)? = nil) {
        self.job = job
        self.onSuccess = onSuccess
        self.onExitToJobList = onExitToJobList
        // Direkt zur Bestätigung wenn 0 oder 1 Schicht
        let hasMultipleShifts = (job.shifts?.count ?? 0) > 1
        self._step = State(initialValue: hasMultipleShifts ? .selectShifts : .confirm)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag Handle
            Capsule()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 4)

            switch step {
            case .selectShifts:
                ShiftSelectionView(
                    job: job,
                    selectedShiftIds: $selectedShiftIds,
                    onNext: {
                        withAnimation(.easeInOut(duration: 0.25)) { step = .confirm }
                    },
                    onDismiss: { dismiss() }
                )

            case .confirm:
                ConfirmationView(
                    job: job,
                    selectedShifts: selectedShiftsForConfirmation,
                    onConfirm: { Task { await submitApplication() } },
                    onBack: {
                        let hasMultipleShifts = (job.shifts?.count ?? 0) > 1
                        if hasMultipleShifts {
                            withAnimation(.easeInOut(duration: 0.25)) { step = .selectShifts }
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
        .background(Color(uiColor: .systemGroupedBackground))
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
        guard let shifts = job.shifts else { return [] }
        if selectedShiftIds.isEmpty { return shifts }
        return shifts.filter { selectedShiftIds.contains($0.id) }
    }

    @MainActor
    private func submitApplication() async {
        withAnimation { step = .loading }

        do {
            try await Task.sleep(nanoseconds: 900_000_000) // 0.9s UX-Feedback
            let autoAccepted = try await jobStore.apply(to: job)
            withAnimation { step = .result(autoAccepted ? .booked : .submitted) }
        } catch let applyError as ApplyError {
            switch applyError {
            case .shiftTaken:         withAnimation { step = .result(.shiftAlreadyTaken) }
            case .jobUnavailable:     withAnimation { step = .result(.shiftUnavailable) }
            case .schedulingConflict: withAnimation { step = .result(.schedulingConflict) }
            case .accountPaused:      withAnimation { step = .result(.accountPaused) }
            case .blocked:            withAnimation { step = .result(.blocked) }
            case .tryAgain:           withAnimation { step = .result(.connectionLost) }
            }
        } catch {
            withAnimation { step = .result(.connectionLost) }
        }
    }
}

// MARK: - Schritt 1: Schicht-Auswahl
private struct ShiftSelectionView: View {
    let job: Job
    @Binding var selectedShiftIds: Set<String>
    let onNext: () -> Void
    let onDismiss: () -> Void

    private var shifts: [JobShift] { job.shifts ?? [] }
    private var canProceed: Bool { !selectedShiftIds.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(Circle())
                }

                Spacer()

                Text("Select Shifts")
                    .font(.system(size: 17, weight: .semibold))

                Spacer()
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // Job-Kurzinfo
                    HStack(spacing: 12) {
                        Text(job.logoEmoji)
                            .font(.system(size: 24))
                            .frame(width: 44, height: 44)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.title)
                                .font(.system(size: 15, weight: .semibold))
                            Text(job.company)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(job.payText)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(SS.primary)
                    }
                    .padding(12)
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    Text("Select one or more shifts:")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)

                    // Schicht-Checkboxen
                    VStack(spacing: 10) {
                        ForEach(shifts) { shift in
                            ShiftCheckboxRow(
                                shift: shift,
                                isSelected: selectedShiftIds.contains(shift.id),
                                onToggle: {
                                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                        if selectedShiftIds.contains(shift.id) {
                                            selectedShiftIds.remove(shift.id)
                                        } else {
                                            selectedShiftIds.insert(shift.id)
                                        }
                                    }
                                }
                            )
                        }
                    }

                    // Ausgewählt-Zähler
                    if !selectedShiftIds.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(SS.primary)
                            Text("\(selectedShiftIds.count) shift\(selectedShiftIds.count == 1 ? "" : "s") selected")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(SS.primary)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(16)
            }

            // Footer
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
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 14) {
                // Checkbox
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? SS.primary : Color.gray.opacity(0.35), lineWidth: 2)
                        .frame(width: 22, height: 22)

                    if isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(SS.primary)
                            .frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(shift.date)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    HStack(spacing: 8) {
                        Label(shift.timeRange, systemImage: "clock")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(shift.duration)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Text(shift.totalPay)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isSelected ? SS.primary : .secondary)
            }
            .padding(14)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? SS.primary : Color.gray.opacity(0.15), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
    }
}

// MARK: - Schritt 2: Bestätigung
private struct ConfirmationView: View {
    let job: Job
    let selectedShifts: [JobShift]
    let onConfirm: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button { onBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(Circle())
                }

                Spacer()

                Text("Confirm Application")
                    .font(.system(size: 17, weight: .semibold))

                Spacer()
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {

                    // Job-Kurzinfo
                    HStack(spacing: 12) {
                        Text(job.logoEmoji)
                            .font(.system(size: 28))
                            .frame(width: 52, height: 52)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(job.title)
                                .font(.system(size: 16, weight: .bold))
                            Text(job.company)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Color(uiColor: .systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    // Schicht-Details
                    if !selectedShifts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Selected Shifts")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.leading, 2)

                            VStack(spacing: 0) {
                                ForEach(Array(selectedShifts.enumerated()), id: \.element.id) { idx, shift in
                                    ConfirmShiftRow(shift: shift)
                                    if idx < selectedShifts.count - 1 {
                                        Divider().padding(.leading, 16)
                                    }
                                }
                            }
                            .background(Color(uiColor: .systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    } else {
                        // Kein shifts-Array (Single-Shift via shiftText)
                        VStack(spacing: 0) {
                            ConfirmDetailRow(icon: "calendar", label: "Shift", value: job.shiftText)
                            Divider().padding(.leading, 44)
                            ConfirmDetailRow(icon: "mappin", label: "Location", value: job.location)
                            Divider().padding(.leading, 44)
                            ConfirmDetailRow(icon: "banknote", label: "Pay", value: job.payText)
                            if let method = job.paymentMethod {
                                Divider().padding(.leading, 44)
                                ConfirmDetailRow(icon: "creditcard", label: "Payment", value: method)
                            }
                        }
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // Instant Match: Hinweis auf sofortige Buchung
                    if job.instantMatch {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(SS.primary)
                                .font(.system(size: 15))
                                .padding(.top, 1)
                            Text("You'll be booked immediately — no waiting for approval.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        .padding(12)
                        .background(SS.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Rechtlicher Hinweis
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 15))
                            .padding(.top, 1)
                        Text(job.instantMatch
                             ? "Spots are limited. If all spots are filled by the time you apply, your application stays pending and the employer will review it."
                             : "Applying does not commit you to anything until confirmed. The employer will review your profile and get back to you via chat.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(16)
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

private struct ConfirmShiftRow: View {
    let shift: JobShift

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(shift.date)
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 6) {
                    Text(shift.timeRange)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(shift.duration)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Spacer()

            Text(shift.totalPay)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(SS.primary)
                .padding(.trailing, 14)
        }
    }
}

private struct ConfirmDetailRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(SS.primary)
                .frame(width: 20)
                .padding(.leading, 14)
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .padding(.trailing, 14)
        }
        .padding(.vertical, 11)
    }
}

// MARK: - Schritt 3a: Laden
private struct LoadingApplyView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.3)
            Text("Submitting application…")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .padding()
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

    private var config: ResultConfig { ResultConfig(result: result, job: job) }

    /// Primär-Button-Aktion: je nach Ergebniszustand navigiert/handelt der Button tatsächlich,
    /// statt immer nur das Sheet zu schließen (dismiss)
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

            VStack(spacing: 20) {
                // Icon
                ZStack {
                    Circle()
                        .fill(config.iconBackground)
                        .frame(width: 80, height: 80)
                    Image(systemName: config.iconName)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundColor(config.iconColor)
                }

                VStack(spacing: 8) {
                    Text(config.title)
                        .font(.system(size: 20, weight: .bold))
                        .multilineTextAlignment(.center)

                    Text(config.message)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 10) {
                // Primär-Aktion
                Button(config.primaryActionLabel) { primaryAction() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(config.primaryActionColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                // Sekundär-Aktion (nur bei Fehlern) — schließt immer nur das Apply-Sheet
                if let secondaryLabel = config.secondaryActionLabel {
                    Button(secondaryLabel) { onDone() }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .sheet(isPresented: $showCalendarSheet) {
            WorkerCalendarView()
        }
    }
}

// MARK: - Result Config
private struct ResultConfig {
    let iconName: String
    let iconColor: Color
    let iconBackground: Color
    let title: String
    let message: String
    let primaryActionLabel: String
    let primaryActionColor: Color
    let secondaryActionLabel: String?

    init(result: ApplyResult, job: Job) {
        switch result {
        case .submitted:
            iconName        = "checkmark.circle.fill"
            iconColor       = .white
            iconBackground  = SS.primary
            title           = "Application Submitted!"
            message         = "Your application to \(job.company) was successfully submitted. You'll receive a reply in chat."
            primaryActionLabel   = "Done"
            primaryActionColor   = SS.primary
            secondaryActionLabel = nil

        case .booked:
            iconName        = "bolt.circle.fill"
            iconColor       = .white
            iconBackground  = SS.primary
            title           = "You're booked!"
            message         = "\(job.company) uses Instant Match, so your spot is confirmed. Find the details in your chat and calendar."
            primaryActionLabel   = "Done"
            primaryActionColor   = SS.primary
            secondaryActionLabel = nil

        case .connectionLost:
            iconName        = "wifi.slash"
            iconColor       = .orange
            iconBackground  = Color.orange.opacity(0.1)
            title           = "Connection Lost"
            message         = "Your application could not be sent. Please check your internet connection and try again."
            primaryActionLabel   = "Try Again"
            primaryActionColor   = .orange
            secondaryActionLabel = "Cancel"

        case .shiftAlreadyTaken:
            iconName        = "person.fill.xmark"
            iconColor       = .red
            iconBackground  = Color.red.opacity(0.1)
            title           = "Shift Already Taken"
            message         = "Unfortunately this shift has already been taken by someone else."
            primaryActionLabel   = "View Other Shifts"
            primaryActionColor   = SS.primary
            secondaryActionLabel = "Back to Overview"

        case .shiftUnavailable:
            iconName        = "calendar.badge.minus"
            iconColor       = .red
            iconBackground  = Color.red.opacity(0.1)
            title           = "Shift Unavailable"
            message         = "This shift is no longer available. The employer may have removed it."
            primaryActionLabel   = "View Other Jobs"
            primaryActionColor   = SS.primary
            secondaryActionLabel = "Back"

        case .schedulingConflict:
            iconName        = "exclamationmark.triangle.fill"
            iconColor       = .orange
            iconBackground  = Color.orange.opacity(0.1)
            title           = "Scheduling Conflict Detected"
            message         = "You already have another job at this time. Check your calendar before applying."
            primaryActionLabel   = "View My Calendar"
            primaryActionColor   = .orange
            secondaryActionLabel = "Go Back Anyway"

        case .accountPaused:
            iconName        = "pause.circle.fill"
            iconColor       = .orange
            iconBackground  = Color.orange.opacity(0.1)
            title           = "Your Account Is Paused"
            message         = "You can't apply while your account is paused. Resume it under Account Settings → Privacy & Data."
            primaryActionLabel   = "OK"
            primaryActionColor   = SS.primary
            secondaryActionLabel = nil

        case .blocked:
            iconName        = "hand.raised.fill"
            iconColor       = .orange
            iconBackground  = Color.orange.opacity(0.1)
            title           = "Can't Apply"
            message         = "You can't apply to this employer."
            primaryActionLabel   = "OK"
            primaryActionColor   = SS.primary
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
        Divider()
        HStack(spacing: 12) {
            Button("Cancel") { onDismiss() }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 100)
                .padding(.vertical, 14)
                .background(Color.gray.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: 14))

            Button(action: action) {
                Text(buttonLabel)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .background(isEnabled ? SS.primary : Color.gray.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(!isEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
