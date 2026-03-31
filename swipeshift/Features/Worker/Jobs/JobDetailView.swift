//
//  JobDetailView.swift
//  swipeShift
//

import SwiftUI

struct JobDetailView: View {
    let job: Job

    @EnvironmentObject var jobStore: JobStore
    @Environment(\.dismiss) private var dismiss

    @State private var isBookmarked = false
    @State private var showApplySheet = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

            // MARK: - Scrollbarer Inhalt
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {

                    headerCard
                    quickInfoRow
                    categoryAndTagsSection
                    descriptionSection
                    tasksSection
                    requirementsSection
                    payDetailsSection
                    companySection
                    whatHappensNextSection

                    // Abstand für sticky Button
                    Spacer().frame(height: 100)
                }
            }

            // MARK: - Sticky Apply Button
            stickyApplyBar
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showApplySheet) {
            ApplyFlowView(job: job, onSuccess: {
                showApplySheet = false
                dismiss()
            })
            .environmentObject(jobStore)
        }
    }

    // MARK: - Header Card
    private var headerCard: some View {
        VStack(spacing: 0) {
            // Navigations-Leiste
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isBookmarked.toggle()
                    }
                } label: {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isBookmarked ? SS.primary : .primary)
                        .frame(width: 36, height: 36)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 56)
            .padding(.bottom, 16)

            // Logo + Titel
            HStack(alignment: .top, spacing: 14) {
                // Company Logo (Emoji Placeholder)
                Text(job.logoEmoji)
                    .font(.system(size: 36))
                    .frame(width: 64, height: 64)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray.opacity(0.12), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(job.title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)

                        if job.isVerified == true {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(SS.primary)
                                .font(.system(size: 14))
                        }
                    }

                    Text(job.company)
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)

                    if let rating = job.companyRating {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Quick-Info Zeile
    private var quickInfoRow: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                QuickInfoCell(icon: "mappin", value: job.location, label: "Location")
                Divider().frame(height: 36)
                QuickInfoCell(icon: "banknote", value: job.payText, label: "Hourly Rate")
                Divider().frame(height: 36)
                QuickInfoCell(icon: "clock", value: job.duration ?? "–", label: "Duration")
                Divider().frame(height: 36)
                QuickInfoCell(icon: "person.2", value: "\(job.openSpots ?? 1)", label: "Spots")
            }
            .padding(.vertical, 12)
            Divider()

            // Schicht-Zeit + Distanz
            HStack(spacing: 16) {
                Label(job.shiftText, systemImage: "calendar")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
                Label(job.distanceText, systemImage: "location")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
        }
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Kategorie + Tags
    private var categoryAndTagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let category = job.category {
                HStack {
                    Text(category)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(SS.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(SS.primary.opacity(0.1))
                        .clipShape(Capsule())
                    Spacer()
                }
            }

            if !job.tags.isEmpty {
                FlowTagsView(tags: job.tags)
            }
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground))
        .padding(.top, 8)
    }

    // MARK: - Beschreibung
    private var descriptionSection: some View {
        Group {
            if let desc = job.jobDescription, !desc.isEmpty {
                DetailSection(title: "Job Description") {
                    Text(desc)
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Aufgaben
    private var tasksSection: some View {
        Group {
            if let tasks = job.tasks, !tasks.isEmpty {
                DetailSection(title: "Tasks") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(tasks, id: \.self) { task in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(SS.primary)
                                    .padding(.top, 1)
                                Text(task)
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Anforderungen
    private var requirementsSection: some View {
        DetailSection(title: "Requirements") {
            VStack(spacing: 0) {
                if let dressCode = job.dressCode {
                    RequirementRow(label: "Dress Code", value: dressCode)
                    Divider().padding(.leading, 16)
                }
                if let langs = job.languages, !langs.isEmpty {
                    RequirementRow(label: "Languages", value: langs.joined(separator: ", "))
                    Divider().padding(.leading, 16)
                }
                if let exp = job.experienceLevel {
                    RequirementRow(label: "Experience", value: exp)
                    Divider().padding(.leading, 16)
                }
                if let age = job.minAge {
                    RequirementRow(label: "Min. Age", value: "\(age)+")
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Vergütung & Vertrag
    private var payDetailsSection: some View {
        DetailSection(title: "Pay & Contract") {
            VStack(spacing: 0) {
                RequirementRow(label: "Hourly Rate", value: job.payText)
                Divider().padding(.leading, 16)
                if let method = job.paymentMethod {
                    RequirementRow(label: "Payment Method", value: method)
                    Divider().padding(.leading, 16)
                }
                if let type_ = job.contractType {
                    RequirementRow(label: "Contract Type", value: type_)
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Unternehmen
    private var companySection: some View {
        DetailSection(title: "Company") {
            HStack(spacing: 14) {
                Text(job.logoEmoji)
                    .font(.system(size: 28))
                    .frame(width: 50, height: 50)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(job.company)
                            .font(.system(size: 15, weight: .semibold))
                        if job.isVerified == true {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundColor(SS.primary)
                        }
                    }

                    if let rating = job.companyRating {
                        HStack(spacing: 3) {
                            ForEach(0..<5) { i in
                                Image(systemName: Double(i) < rating ? "star.fill" : "star")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            }
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }

                    if let reply = job.replyTime {
                        Text(reply)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                // NavigationLink unsichtbar über die gesamte Karte
                NavigationLink {
                    CompanyProfileView(
                        company: .mock(name: job.company, logoEmoji: job.logoEmoji, rating: job.companyRating)
                    )
                } label: {
                    Color.clear
                }
            }
        }
    }

    // MARK: - Was passiert als Nächstes?
    private var whatHappensNextSection: some View {
        DetailSection(title: "What happens next?") {
            VStack(spacing: 12) {
                NextStepRow(number: "1", text: "The employer reviews your profile and availability.")
                NextStepRow(number: "2", text: "You receive a reply directly in the chat.")
                NextStepRow(number: "3", text: "No commitment until final confirmation.")
            }
            .padding(14)
            .background(SS.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SS.primary.opacity(0.15), lineWidth: 1)
            )
        }
    }

    // MARK: - Sticky Apply Bar
    private var stickyApplyBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(job.payText)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.primary)
                    if let spots = job.openSpots {
                        Text("\(spots) spot\(spots == 1 ? "" : "s") available")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }

                Button {
                    showApplySheet = true
                } label: {
                    Text("Jetzt bewerben")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SS.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .background(Color(uiColor: .systemBackground))
        }
    }
}

// MARK: - Hilfs-Views

private struct QuickInfoCell: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(SS.primary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RequirementRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.primary)
            content
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground))
        .padding(.top, 8)
    }
}

private struct NextStepRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(SS.primary)
                .clipShape(Circle())

            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }
}

/// Flow-Layout für Tags (umbrechend)
struct FlowTagsView: View {
    let tags: [String]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 90, maximum: 160), spacing: 8)],
            spacing: 8
        ) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SS.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(SS.primary.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
    }
}

