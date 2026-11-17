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
            .navigationTitle("Report \(conversation.company)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(submitted ? "Done" : "Cancel") { dismiss() }
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
    }

    private var form: some View {
        Form {
            Section("Reason") {
                ForEach(ReportReason.allCases) { item in
                    Button {
                        reason = item
                    } label: {
                        HStack {
                            Text(item.title).foregroundColor(.primary)
                            Spacer()
                            if item == reason {
                                Image(systemName: "checkmark").foregroundColor(SS.primary)
                            }
                        }
                    }
                }
            }
            Section("Details (optional)") {
                TextEditor(text: $details)
                    .frame(minHeight: 100)
                    .onChange(of: details) { _, newValue in
                        if newValue.count > maxDetails { details = String(newValue.prefix(maxDetails)) }
                    }
                Text("\(details.count)/\(maxDetails)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Spacer()
                        if isSending { ProgressView() } else { Text("Send report").fontWeight(.semibold) }
                        Spacer()
                    }
                }
                .disabled(isSending)
            }
        }
    }

    private var confirmation: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundColor(.green)
            Text("Thanks – our team will review this.")
                .font(.system(size: 17, weight: .semibold))
                .multilineTextAlignment(.center)
            Text("You can also block this user from the chat menu.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
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
            Color(uiColor: .secondarySystemGroupedBackground)
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
        Text(emoji).font(.system(size: size * 0.55))
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
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }
}

// MARK: - Quick job info (einklappbar)
struct ChatJobInfoCard: View {
    let conversation: Conversation
    let onViewJob: () -> Void
    var isLoadingJob = false

    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Label("Quick job info", systemImage: "briefcase")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    infoRow("calendar", conversation.shiftSummary)
                    if !conversation.location.isEmpty { infoRow("mappin.and.ellipse", conversation.location) }
                    if !conversation.payDisplay.isEmpty { infoRow("banknote", conversation.payDisplay) }
                    HStack(spacing: 8) {
                        Image(systemName: "flag").frame(width: 18).foregroundColor(.secondary)
                        StatusBadge(status: conversation.status)
                    }
                    Button(action: onViewJob) {
                        HStack {
                            if isLoadingJob { ProgressView().tint(.white) }
                            Text("View job details")
                        }
                    }
                    .buttonStyle(SSPrimaryButtonStyle())
                    .disabled(isLoadingJob)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    private func infoRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).frame(width: 18).foregroundColor(.secondary)
            Text(text).font(.system(size: 13)).foregroundColor(.primary)
            Spacer(minLength: 0)
        }
    }
}
