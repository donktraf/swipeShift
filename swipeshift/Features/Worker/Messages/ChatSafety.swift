//
//  ChatSafety.swift
//  swipeShift
//
//  Melden / Blockieren / Support im Chat (App-Store Guideline 1.2).
//

import SwiftUI
import UIKit

enum ChatSafety {
    static let supportEmail = "support@swipeshift.app"
    static let safetyNotice = "Messages are job-related and may be reviewed for safety."

    /// mailto-Link mit Betreff inkl. Job-Titel + Conversation-ID
    static func supportURL(for conversation: Conversation) -> URL? {
        let subject = "SwipeShift support: \(conversation.jobTitle) [\(conversation.id)]"
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = supportEmail
        // percentEncodedQuery: URLQueryItem laesst "+", "&", "=" unkodiert → Betreff wuerde zerlegt
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=#?")
        let encoded = subject.addingPercentEncoding(withAllowedCharacters: allowed) ?? subject
        comps.percentEncodedQuery = "subject=\(encoded)"
        return comps.url
    }
}

/// Gruende laut Backend-Whitelist (utils/safety.js)
enum ReportReason: String, CaseIterable, Identifiable {
    case harassment, spam, inappropriate, safety, payment, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .harassment:    return "Harassment or abuse"
        case .spam:          return "Spam or scam"
        case .inappropriate: return "Inappropriate content"
        case .safety:        return "Safety concern"
        case .payment:       return "Payment issue"
        case .other:         return "Something else"
        }
    }
}

// MARK: - Report-Sheet
struct ReportUserSheet: View {
    let conversation: Conversation
    let userId: String

    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason = .harassment
    @State private var details = ""
    @State private var isSending = false
    @State private var submitted = false
    @State private var errorMessage: String?

    private let maxDetails = 1000

    var body: some View {
        NavigationStack {
            Group {
                if submitted { confirmation } else { form }
            }
            .dsBackground()
            .navigationTitle("Report \(conversation.company)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(submitted ? "Done" : "Cancel") { dismiss() }
                        .tint(DS.Color.primaryText)
                }
            }
            .alert("Could not send report", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(DS.Radius.sheet)
        .presentationBackground(DS.Color.bg)
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                DSSection("Reason") {
                    VStack(spacing: 0) {
                        ForEach(ReportReason.allCases) { item in
                            Button {
                                DS.Haptics.selection()
                                reason = item
                            } label: {
                                HStack {
                                    Text(item.title)
                                        .dsFont(.body)
                                        .foregroundStyle(DS.Color.text)
                                    Spacer()
                                    if item == reason {
                                        Image(systemName: "checkmark")
                                            .font(DS.Font.make(15, .bold))
                                            .foregroundStyle(DS.Color.primary)
                                    }
                                }
                                .frame(minHeight: 48)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.dsPressable)
                            .accessibilityAddTraits(item == reason ? .isSelected : [])
                            if item != ReportReason.allCases.last { DSDivider() }
                        }
                    }
                }

                DSTextEditor("Details (optional)", text: $details, maxLength: maxDetails)

                Button {
                    Task { await submit() }
                } label: {
                    if isSending { ProgressView().tint(DS.Color.onPrimary) } else { Text("Send report") }
                }
                .buttonStyle(.ds(.primary, size: .large))
                .disabled(isSending)
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.vertical, DS.Spacing.lg)
        }
    }

    private var confirmation: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(DS.Color.success)
                .accessibilityHidden(true)
            Text("Thanks – our team will review this.")
                .dsFont(.headline)
                .foregroundStyle(DS.Color.text)
                .multilineTextAlignment(.center)
            Text("You can also block this user from the chat menu.")
                .dsFont(.callout)
                .foregroundStyle(DS.Color.text2)
                .multilineTextAlignment(.center)
        }
        .padding(DS.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func submit() async {
        isSending = true
        defer { isSending = false }
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await APIClient.shared.reportUser(
                userId: userId,
                conversationId: conversation.id,
                reason: reason.rawValue,
                details: trimmed.isEmpty ? nil : trimmed
            )
            DS.Haptics.success()
            submitted = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Avatar (Foto oder Emoji-Platzhalter)
struct ChatAvatar: View {
    let photoUrl: String?
    let emoji: String
    var size: CGFloat = 40

    /// Absolute URLs (Upload-Endpunkte liefern `http(s)://host/uploads/..`) unveraendert;
    /// relative Pfade werden gegen AppConfig.baseURL aufgeloest.
    private var resolvedURL: URL? {
        guard let photoUrl, !photoUrl.isEmpty else { return nil }
        if photoUrl.hasPrefix("/") { return URL(string: photoUrl, relativeTo: AppConfig.baseURL)?.absoluteURL }
        return URL(string: photoUrl)
    }

    var body: some View {
        ZStack {
            DS.Color.surface2
            if let url = resolvedURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        DSAvatar(text: emoji, size: size, shape: .circle)
    }
}

// MARK: - Datums-Trenner
struct DateSeparator: View {
    let date: Date

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    static func label(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        return formatter.string(from: date)
    }

    var body: some View {
        Text(Self.label(for: date))
            .dsFont(.caption)
            .foregroundStyle(DS.Color.text2)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xxs)
            .background(DS.Color.surface2, in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.xs)
    }
}

// MARK: - Quick job info (einklappbar)
struct ChatJobInfoCard: View {
    let conversation: Conversation
    let onViewJob: () -> Void
    var isLoadingJob = false

    @State private var expanded = false

    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Button {
                    DS.Haptics.selection()
                    expanded.toggle()
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "briefcase")
                            .foregroundStyle(DS.Color.primaryText)
                        Text("Quick job info")
                            .dsFont(.callout)
                            .foregroundStyle(DS.Color.text)
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(DS.Font.make(12, .bold))
                            .foregroundStyle(DS.Color.muted)
                    }
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.dsPressable)
                .accessibilityLabel("Quick job info, \(expanded ? "expanded" : "collapsed")")

                if expanded {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        infoRow("calendar", conversation.shiftSummary)
                        if !conversation.location.isEmpty { infoRow("mappin.and.ellipse", conversation.location) }
                        if !conversation.payDisplay.isEmpty { infoRow("banknote", conversation.payDisplay) }
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "flag").frame(width: 18).foregroundStyle(DS.Color.muted)
                            StatusBadge(status: conversation.status)
                        }
                        Button(action: onViewJob) {
                            HStack(spacing: DS.Spacing.xs) {
                                if isLoadingJob { ProgressView().tint(DS.Color.onPrimary) }
                                Text("View job details")
                            }
                        }
                        .buttonStyle(.ds(.primary, size: .medium))
                        .disabled(isLoadingJob)
                        .padding(.top, DS.Spacing.xxs)
                    }
                    .transition(.opacity)
                }
            }
            .dsAnimation(.snappy, value: expanded)
        }
    }

    private func infoRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.xs) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(DS.Color.muted)
            Text(text).dsFont(.callout).foregroundStyle(DS.Color.text)
            Spacer(minLength: 0)
        }
    }
}
