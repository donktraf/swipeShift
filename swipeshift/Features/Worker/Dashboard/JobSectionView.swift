//
//  JobSectionView.swift
//  swipeShift
//

import SwiftUI

/// Wiederverwendbare Job-Sektion für das Dashboard.
/// Jede Sektion hat einen Titel, bis zu 2 Jobs und rechts im Kopf "See all".
struct JobSectionView: View {
    let title: String
    let jobs: [Job]
    var isLoading: Bool = false
    let onViewAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {

            // Header: Titel links, "See all" rechts
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(DS.Font.make(17, .bold, relativeTo: .headline))
                    .foregroundStyle(DS.Color.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: DS.Spacing.sm)
                Button {
                    DS.Haptics.light()
                    onViewAll()
                } label: {
                    Text("See all")
                        .font(DS.Font.make(14, .semibold, relativeTo: .callout))
                        .foregroundStyle(DS.Color.primaryText)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.dsPressable)
                .accessibilityLabel("See all \(title)")
            }
            .padding(.horizontal, DS.Spacing.screenEdge)

            if isLoading && jobs.isEmpty {
                VStack(spacing: DS.Spacing.sm) {
                    DashboardJobCardSkeleton()
                    DashboardJobCardSkeleton()
                }
                .padding(.horizontal, DS.Spacing.screenEdge)
            } else if jobs.isEmpty {
                Text("No jobs available right now.")
                    .dsFont(.callout)
                    .foregroundStyle(DS.Color.muted)
                    .padding(.horizontal, DS.Spacing.screenEdge)
                    .padding(.vertical, DS.Spacing.xs)
            } else {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(jobs.prefix(2)) { job in
                        NavigationLink {
                            JobDetailView(job: job)
                        } label: {
                            DashboardJobCard(job: job)
                        }
                        .buttonStyle(.dsPressable)
                    }
                }
                .padding(.horizontal, DS.Spacing.screenEdge)
            }
        }
    }
}

// MARK: - Job-Karte

/// Job-Karte (Dashboard, Job-Liste, Kategorie-Liste): Avatar, Titel, Firma · Distanz, Lohn rechts, Chips.
struct DashboardJobCard: View {
    let job: Job

    // Saved-Status kommt zentral aus dem JobStore (gilt an allen Verwendungsstellen).
    @EnvironmentObject var jobStore: JobStore

    private var isSaved: Bool { jobStore.savedJobIds.contains(job.id) }

    /// Stabile Tönung pro Firma (gleiche Firma = gleiche Farbe).
    private var avatarTone: DS.Tone {
        let tones: [DS.Tone] = [.primary, .success, .warning, .neutral]
        let sum = job.company.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return tones[sum % tones.count]
    }

    private var companyLine: String {
        let distance = job.distanceText.replacingOccurrences(of: " away", with: "")
        return distance.isEmpty ? job.company : "\(job.company) · \(distance)"
    }

    /// "$22 / hr" -> ("$22", "/hr"); sonstige Texte ("On request") ohne Suffix.
    private var payParts: (amount: String, suffix: String?) {
        let parts = job.payText.components(separatedBy: " / ")
        guard parts.count == 2 else { return (job.payText, nil) }
        return (parts[0], "/" + parts[1])
    }

    /// "Starts in 3 h" nur wenn der Start in der Zukunft und innerhalb von 5 Stunden liegt.
    private var startsSoonText: String? {
        guard let start = job.startTime else { return nil }
        let seconds = start.timeIntervalSinceNow
        guard seconds > 0, seconds <= 5 * 3600 else { return nil }
        let hours = max(1, Int((seconds / 3600).rounded(.up)))
        return "Starts in \(hours) h"
    }

    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(alignment: .center, spacing: DS.Spacing.sm) {
                    // Firmen-Emoji bleibt, aber im getönten Rundquadrat
                    DSAvatar(text: job.logoEmoji, size: 44, shape: .roundedSquare, tone: avatarTone)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.title)
                            .font(DS.Font.make(15, .bold, relativeTo: .body))
                            .foregroundStyle(DS.Color.text)
                            .lineLimit(2)
                        Text(companyLine)
                            .dsFont(.caption)
                            .foregroundStyle(DS.Color.muted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: DS.Spacing.xs)

                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(payParts.amount)
                            .font(DS.Font.make(17, .extrabold, relativeTo: .headline))
                            .foregroundStyle(DS.Color.text)
                        if let suffix = payParts.suffix {
                            Text(suffix)
                                .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                                .foregroundStyle(DS.Color.muted)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                    bookmarkButton
                }

                // Chips: Zeit, Dauer, Dringlichkeit, Tags
                DSFlowLayout(spacing: DS.Spacing.xs) {
                    infoChip(job.shiftText)
                    if let duration = job.duration, !duration.isEmpty {
                        infoChip(duration)
                    }
                    if let soon = startsSoonText {
                        DSBadge(soon, .tone(.warning))
                    }
                    if job.isUrgent {
                        DSBadge("Urgent", .tone(.danger))
                    }
                    ForEach(job.tags.prefix(2), id: \.self) { tag in
                        DSBadge(tag, .tone(.primary))
                    }
                }
            }
        }
    }

    private func infoChip(_ text: String) -> some View {
        DSBadge(text, .completed)
    }

    // Echter Bookmark-Button (der vollwertige Apply-Flow lebt in JobDetailView).
    private var bookmarkButton: some View {
        Button {
            DS.Haptics.light()
            Task { await jobStore.toggleSaveJob(job.id) }
        } label: {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(DS.Font.make(16, .semibold, relativeTo: nil))
                .foregroundStyle(isSaved ? DS.Color.primaryText : DS.Color.muted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dsPressable)
        // Tippfläche 44pt, optisch näher an den Kartenrand/Lohn rücken
        .padding(.trailing, -DS.Spacing.xs)
        .padding(.vertical, -DS.Spacing.xs)
        .accessibilityLabel(isSaved ? "Remove bookmark" : "Save job")
    }
}

/// Platzhalter-Karte für das erste Laden.
struct DashboardJobCardSkeleton: View {
    var body: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    DSSkeletonBlock(width: 44, height: 44, radius: 13)
                    VStack(alignment: .leading, spacing: 6) {
                        DSSkeletonBlock(width: 140, height: 14)
                        DSSkeletonBlock(width: 100, height: 12)
                    }
                    Spacer()
                    DSSkeletonBlock(width: 48, height: 18)
                }
                HStack(spacing: DS.Spacing.xs) {
                    DSSkeletonBlock(width: 90, height: 24, radius: 12)
                    DSSkeletonBlock(width: 50, height: 24, radius: 12)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

// MARK: - Flow-Layout (umbrechende Chip-Reihe, Element mit Trailing-Key rutscht ans Zeilenende der letzten Zeile)

struct DSFlowTrailingKey: LayoutValueKey {
    static let defaultValue = false
}

/// Einfaches umbrechendes Layout. Subviews mit `DSFlowTrailingKey == true` werden rechtsbündig in die letzte Zeile gesetzt.
struct DSFlowLayout: Layout {
    var spacing: CGFloat = 8

    private struct Placement { var origin: CGPoint; var size: CGSize }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (placements: [Placement], height: CGFloat) {
        var placements: [Placement] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var trailing: [Int] = []

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if subview[DSFlowTrailingKey.self] {
                trailing.append(index)
                placements.append(Placement(origin: .zero, size: size))
                continue
            }
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            placements.append(Placement(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        // Trailing-Elemente: rechts in der letzten Zeile, falls Platz, sonst neue Zeile
        for index in trailing {
            let size = placements[index].size
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            let tx = max(x, width - size.width)
            placements[index].origin = CGPoint(x: tx, y: y + (max(rowHeight, size.height) - size.height) / 2)
            rowHeight = max(rowHeight, size.height)
        }
        return (placements, y + rowHeight)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let result = arrange(subviews, width: width)
        return CGSize(width: proposal.width ?? 0, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews, width: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let p = result.placements[index]
            subview.place(
                at: CGPoint(x: bounds.minX + p.origin.x, y: bounds.minY + p.origin.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(p.size)
            )
        }
    }
}
