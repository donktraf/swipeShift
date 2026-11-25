//
//  JobSwipeView.swift
//  swipeShift
//

import SwiftUI

struct JobSwipeView: View {
    @EnvironmentObject var jobStore: JobStore
    @EnvironmentObject var userStore: UserStore

    @State private var dragOffset: CGSize = .zero
    @State private var isAnimatingOut = false
    @State private var showFilterSheet = false
    @State private var filterOptions: JobFilterOptions = JobFilterOptions()

    // Schicht-Auswahl-Sheet bei Mehrschicht-Jobs (Swipe-Rechts / Apply-Button)
    @State private var applySheetJob: ApplySheetRequest?
    // Fly-out/Sofort-Apply läuft: weitere Taps und Drags ignorieren
    @State private var isSwiping = false

    private struct ApplySheetRequest: Identifiable {
        let job: Job
        var initialResult: ApplyResult? = nil
        var id: String { job.id }
    }

    // Haptics: kippt einmalig pro Drag-Geste beim Ueberschreiten des Swipe-Thresholds
    @State private var hasCrossedSwipeThreshold = false
    // Haptics: toggelt bei jedem tatsaechlichen Apply/Skip-Auslösen
    @State private var swipeHapticTrigger = false
    // Haptics: toggelt bei jedem Bookmark-Toggle
    @State private var bookmarkHapticTrigger = false

    // Wie weit gezogen wurde (0…1)
    private var dragFraction: CGFloat { min(abs(dragOffset.width) / 130, 1.0) }
    private var isDraggingRight: Bool { dragOffset.width > 20 }
    private var isDraggingLeft:  Bool { dragOffset.width < -20 }
    private var rotation: Double { Double(dragOffset.width / 22) }

    private var filteredSwipeJobs: [Job] {
        guard let cat = filterOptions.category else { return jobStore.swipeJobs }
        return jobStore.swipeJobs.filter {
            $0.category?.lowercased() == cat.lowercased()
            || $0.tags.contains(where: { $0.lowercased() == cat.lowercased() })
        }
    }

    private var topJob:  Job? { filteredSwipeJobs.first }
    private var nextJob: Job? { filteredSwipeJobs.dropFirst().first }

    // Skeleton waehrend des ersten Ladens
    @State private var isLoadingInitial = false

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                header
                categoryChips
                cardArea(geo: geo)
                actionBar
                    .padding(.bottom, DS.Spacing.xl)
            }
            .dsBackground()
        }
        .sheet(isPresented: $showFilterSheet) {
            FilterSheet(filterOptions: $filterOptions)
                .presentationDetents([.medium])
        }
        // Erfolg: jobStore.apply entfernt den Job bereits aus swipeJobs; Abbruch/Fehler: Karte bleibt
        .sheet(item: $applySheetJob) { request in
            ApplyFlowView(job: request.job, initialResult: request.initialResult)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hasCrossedSwipeThreshold)
        .sensoryFeedback(.impact(weight: .medium), trigger: swipeHapticTrigger)
        .sensoryFeedback(.impact(weight: .light), trigger: bookmarkHapticTrigger)
        .task {
            if jobStore.swipeJobs.isEmpty {
                isLoadingInitial = true
                await jobStore.loadSwipeJobs()
                isLoadingInitial = false
            }
            await jobStore.loadSavedJobIds()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Swipe")
                    .dsFont(.display)
                    .foregroundStyle(DS.Color.text)
                Text("\(filteredSwipeJobs.count) jobs left")
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.muted)
            }
            Spacer()
            ZStack(alignment: .topTrailing) {
                DSIconButton(systemName: "slider.horizontal.3", label: "Filter") { showFilterSheet = true }
                if filterOptions.category != nil {
                    Circle()
                        .fill(DS.Color.warning)
                        .frame(width: 10, height: 10)
                        .offset(x: 3, y: -3)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.screenEdge)
        .padding(.top, DS.Spacing.xs)
        .padding(.bottom, DS.Spacing.sm)
    }

    // MARK: - Kategorie-Chips

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xs) {
                DSChip("All", isSelected: filterOptions.category == nil) {
                    filterOptions.category = nil
                }
                ForEach(JobCategory.all) { category in
                    DSChip(category.name, isSelected: filterOptions.category == category.name) {
                        filterOptions.category = category.name
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
        }
        .padding(.bottom, DS.Spacing.xs)
    }

    // MARK: - Card Area

    private func cardArea(geo: GeometryProxy) -> some View {
        let cardH = geo.size.height * 0.62

        return ZStack {
            if isLoadingInitial && filteredSwipeJobs.isEmpty {
                SwipeCardSkeleton()
                    .frame(height: cardH)
            } else if filteredSwipeJobs.isEmpty {
                emptyState
            } else {
                // Karte 3 (ganz hinten, kaum sichtbar)
                if filteredSwipeJobs.count >= 3 {
                    SwipeJobCard(job: filteredSwipeJobs[2])
                        .frame(height: cardH)
                        .scaleEffect(0.91)
                        .offset(y: -10)
                        .zIndex(1)
                }
                // Karte 2 (mittig)
                if filteredSwipeJobs.count >= 2 {
                    SwipeJobCard(job: filteredSwipeJobs[1])
                        .frame(height: cardH)
                        .scaleEffect(0.96)
                        .offset(y: -5)
                        .zIndex(2)
                }
                // Top-Karte (ziehbar)
                if let job = topJob {
                    SwipeJobCard(
                        job: job,
                        dragFraction: dragFraction,
                        isDraggingRight: isDraggingRight,
                        isDraggingLeft: isDraggingLeft
                    )
                    .frame(height: cardH)
                    .offset(x: dragOffset.width, y: dragOffset.height * 0.25)
                    .rotationEffect(.degrees(rotation))
                    .zIndex(3)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard !isSwiping else { return }
                                dragOffset = value.translation
                                let fraction = min(abs(value.translation.width) / 130, 1.0)
                                if fraction > 0.6 && !hasCrossedSwipeThreshold {
                                    hasCrossedSwipeThreshold = true
                                }
                            }
                            .onEnded   { if !isSwiping { handleDragEnd($0, job: job) } }
                    )
                    .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.72), value: dragOffset)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.screenEdge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: DS.Spacing.xl) {
            // Skip (links)
            circleButton(icon: "xmark", label: "Skip", style: .skip, size: 64) {
                if let job = topJob { animateSwipe(direction: -1, job: job) }
            }

            // Bookmark (speichern)
            let isSaved = jobStore.savedJobIds.contains(topJob?.id ?? "")
            circleButton(
                icon: isSaved ? "bookmark.fill" : "bookmark",
                label: isSaved ? "Remove from saved" : "Save job",
                style: .save, size: 52
            ) {
                guard let job = topJob else { return }
                bookmarkHapticTrigger.toggle()
                Task { await jobStore.toggleSaveJob(job.id) }
            }

            // Apply (rechts)
            circleButton(icon: "checkmark", label: "Apply", style: .apply, size: 64) {
                if let job = topJob { animateSwipe(direction: 1, job: job) }
            }
        }
        .padding(.top, DS.Spacing.md)
        .opacity(filteredSwipeJobs.isEmpty ? 0.45 : 1)
        .disabled(filteredSwipeJobs.isEmpty)
    }

    private enum CircleStyle { case skip, save, apply }

    private func circleButton(icon: String, label: String, style: CircleStyle, size: CGFloat, action: @escaping () -> Void) -> some View {
        let foreground: Color = {
            switch style {
            case .skip: return DS.Color.danger
            case .save: return DS.Color.primaryText
            case .apply: return DS.Color.onPrimary
            }
        }()
        let background: Color = style == .apply ? DS.Color.success : DS.Color.surface
        return Button(action: action) {
            Image(systemName: icon)
                .font(DS.Font.make(size * 0.36, .bold, relativeTo: nil))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(background, in: Circle())
                .overlay(Circle().strokeBorder(style == .apply ? Color.clear : DS.Color.border, lineWidth: 1))
                .dsCardShadow()
                .contentShape(Circle())
        }
        .buttonStyle(DSPressableStyle(scale: 0.92))
        .accessibilityLabel(label)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        DSEmptyState(
            systemIcon: "sparkles",
            title: "No more jobs",
            message: "Expand your search or check back later.",
            actionTitle: "Refresh",
            action: { Task { await jobStore.loadJobsAll() } }
        )
    }

    // MARK: - Swipe-Logik

    private func handleDragEnd(_ value: DragGesture.Value, job: Job) {
        let threshold: CGFloat = 110
        // Threshold-Flag fuer die naechste Drag-Geste zuruecksetzen
        hasCrossedSwipeThreshold = false
        if value.translation.width >= threshold {
            animateSwipe(direction: 1, job: job)   // rechts = apply
        } else if value.translation.width <= -threshold {
            animateSwipe(direction: -1, job: job)  // links = skip
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                dragOffset = .zero
            }
        }
    }

    private func animateSwipe(direction: CGFloat, job: Job) {
        guard !isSwiping, applySheetJob == nil else { return }

        // Mehrschicht-Job (oder Schichten ohne eindeutig buchbare Schicht): Karte bleibt, Sheet öffnet
        if direction > 0 && !ApplyFlowView.canApplyImmediately(job) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                dragOffset = .zero
            }
            applySheetJob = ApplySheetRequest(job: job)
            return
        }

        isSwiping = true
        swipeHapticTrigger.toggle()
        withAnimation(.easeIn(duration: 0.28)) {
            dragOffset = CGSize(width: direction * 700, height: 0)
        }
        Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            var failure: ApplyResult?
            if direction > 0 {
                do {
                    try await jobStore.apply(to: job, shiftIds: ApplyFlowView.singleShiftIds(for: job))
                    DS.Haptics.success()
                } catch { failure = ApplyFlowView.result(for: error) }
            } else {
                await jobStore.skip(job)
            }
            // Karte erst nach dem Call zurücksetzen (kein Zurückspringen während des Requests)
            var tx = Transaction(); tx.disablesAnimations = failure == nil
            withTransaction(tx) { dragOffset = .zero }
            if let failure {
                applySheetJob = ApplySheetRequest(job: job, initialResult: failure)
            }
            isSwiping = false
        }
    }
}

// MARK: - SwipeJobCard

private struct SwipeJobCard: View {
    let job: Job
    var dragFraction: CGFloat = 0
    var isDraggingRight: Bool = false
    var isDraggingLeft:  Bool = false

    private let cardShape = RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous)

    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                cardHeader
                // Inhalt wird nie abgeschnitten: ViewThatFits waehlt die ausfuehrlichste Variante, die passt
                ViewThatFits(in: .vertical) {
                    cardContent(showRatings: true, showReasons: true, showTags: true)
                    cardContent(showRatings: false, showReasons: true, showTags: true)
                    cardContent(showRatings: false, showReasons: false, showTags: true)
                    cardContent(showRatings: false, showReasons: false, showTags: false)
                }
                .frame(maxHeight: .infinity, alignment: .top)
                cardFooter
            }
            .background(DS.Color.surface, in: cardShape)
            .clipShape(cardShape)
            .overlay(cardShape.strokeBorder(DS.Color.border, lineWidth: 1))
            .dsCardShadow()

            // Stempel: APPLY (rechts oben) / SKIP (links oben)
            if isDraggingRight && dragFraction > 0.08 {
                stamp(text: "APPLY", tone: .success, rotation: 12)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .opacity(Double(dragFraction))
            }
            if isDraggingLeft && dragFraction > 0.08 {
                stamp(text: "SKIP", tone: .danger, rotation: -12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(Double(dragFraction))
            }
        }
    }

    // MARK: Card sections

    private func cardContent(showRatings: Bool, showReasons: Bool, showTags: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            titleBlock
            chipsRow
            descriptionBlock
            if showTags { tagsBlock }
            if showRatings, let bd = job.reviewBreakdown {
                ratingsBlock(bd)
            }
            if showReasons && !job.matchReasons.isEmpty {
                matchReasonsBlock
            }
        }
        .padding(DS.Spacing.screenEdge)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Getoenter Kopfbereich mit grossem Avatar
    private var cardHeader: some View {
        ZStack {
            DS.Color.primarySoft
            DSAvatar(text: job.logoEmoji, size: 84, shape: .roundedSquare, tone: .neutral)
                .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: 84 * 0.3, style: .continuous))
        }
        .frame(height: 140)
        .accessibilityHidden(true)
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.xxs) {
                    Text(job.title)
                        .dsFont(.title)
                        .foregroundStyle(DS.Color.text)
                        .lineLimit(2)
                    if job.isVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(DS.Font.make(14, .semibold))
                            .foregroundStyle(DS.Color.primaryText)
                            .accessibilityLabel("Verified")
                    }
                }
                Text(job.distanceText.isEmpty ? job.company : "\(job.company) · \(job.distanceText)")
                    .dsFont(.callout)
                    .foregroundStyle(DS.Color.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Spacing.xs)
            Text(job.payText)
                .font(DS.Font.make(18, .extrabold, relativeTo: .headline))
                .foregroundStyle(DS.Color.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xs) {
                SwipePill(icon: "mappin", text: job.location)
                if let dur = job.duration {
                    SwipePill(icon: "clock", text: dur)
                }
                if let cat = job.category {
                    SwipePill(icon: nil, text: cat)
                }
            }
        }
    }

    private var descriptionBlock: some View {
        Text(job.shortInfo)
            .dsFont(.callout)
            .foregroundStyle(DS.Color.text2)
            .lineLimit(3)
    }

    @ViewBuilder
    private var tagsBlock: some View {
        if !job.tags.isEmpty {
            FlowTagsView(tags: Array(job.tags.prefix(4)))
        }
    }

    // MARK: Ratings & Reviews block

    private func ratingsBlock(_ bd: JobReviewSummary) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            DSDivider()
            Text("RATINGS & REVIEWS")
                .dsFont(.sectionLabel)
                .foregroundStyle(DS.Color.muted)
                .padding(.top, DS.Spacing.xxs)

            HStack(spacing: DS.Spacing.sm) {
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", bd.avgRating))
                        .font(DS.Font.make(28, .extrabold, relativeTo: .title))
                        .foregroundStyle(DS.Color.text)
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: Double(i) <= bd.avgRating ? "star.fill" : (Double(i) - 0.5 <= bd.avgRating ? "star.leadinghalf.filled" : "star"))
                                .font(DS.Font.make(9, .semibold, relativeTo: .caption2))
                                .foregroundStyle(DS.Color.warning)
                        }
                    }
                    Text("\(bd.totalReviews) review\(bd.totalReviews == 1 ? "" : "s")")
                        .font(DS.Font.make(10, .medium, relativeTo: .caption2))
                        .foregroundStyle(DS.Color.muted)
                }
                .fixedSize()

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    ratingBar("Communication",   value: bd.communication)
                    ratingBar("Payment",         value: bd.paymentFairness)
                    ratingBar("Work Environment", value: bd.workEnvironment)
                    ratingBar("Job Description", value: bd.jobDescriptionAccuracy)
                    ratingBar("Overall",         value: bd.overallExperience)
                }
            }

            if !bd.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.xs) {
                        ForEach(bd.tags, id: \.self) { tag in
                            DSBadge(tag, .tone(.success))
                        }
                    }
                }
            }
        }
    }

    private func ratingBar(_ label: String, value: Double) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Text(label)
                .font(DS.Font.make(10, .medium, relativeTo: .caption2))
                .foregroundStyle(DS.Color.muted)
                .lineLimit(1)
                .frame(width: 84, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Color.surface2)
                    Capsule().fill(DS.Color.primary)
                        .frame(width: geo.size.width * CGFloat(min(max(value / 5.0, 0), 1)))
                }
            }
            .frame(height: 6)
            Text(String(format: "%.1f", value))
                .font(DS.Font.make(10, .semibold, relativeTo: .caption2))
                .foregroundStyle(DS.Color.text2)
                .frame(width: 24, alignment: .trailing)
        }
    }

    // MARK: Why you see this Job block

    private var matchReasonsBlock: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            DSDivider()
            Text("WHY YOU SEE THIS JOB")
                .dsFont(.sectionLabel)
                .foregroundStyle(DS.Color.muted)
                .padding(.top, DS.Spacing.xxs)
            ForEach(job.matchReasons.prefix(2), id: \.self) { reason in
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(DS.Font.make(13, .semibold, relativeTo: .caption))
                        .foregroundStyle(DS.Color.primary)
                    Text(reason)
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.text)
                        .lineLimit(1)
                }
            }
        }
    }

    private var cardFooter: some View {
        HStack {
            Label(job.shiftText, systemImage: "calendar")
                .dsFont(.caption)
                .foregroundStyle(DS.Color.muted)
                .lineLimit(1)
            Spacer()
            if let spots = job.openSpots {
                Label("\(spots) open", systemImage: "person.2")
                    .font(DS.Font.make(12, .bold, relativeTo: .caption))
                    .foregroundStyle(DS.Color.success)
            }
        }
        .padding(.horizontal, DS.Spacing.screenEdge)
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(DS.Color.surface2)
    }

    // MARK: Stempel

    private func stamp(text: String, tone: DS.Tone, rotation: Double) -> some View {
        Text(text)
            .font(DS.Font.make(15, .extrabold, relativeTo: nil))
            .tracking(1)
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, DS.Spacing.xs)
            .background(tone.soft.opacity(0.9), in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    .strokeBorder(tone.foreground, lineWidth: 2.5)
            )
            .rotationEffect(.degrees(rotation))
            .padding(DS.Spacing.md)
            .accessibilityHidden(true)
    }
}

// MARK: - Skeleton

private struct SwipeCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DS.Color.surface2.frame(height: 140)
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                DSSkeletonBlock(width: 200, height: 22)
                DSSkeletonBlock(width: 140, height: 14)
                DSSkeletonBlock(height: 14)
                DSSkeletonBlock(height: 14)
                Spacer()
            }
            .padding(DS.Spacing.screenEdge)
        }
        .frame(maxWidth: .infinity)
        .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sheet, style: .continuous)
                .strokeBorder(DS.Color.border, lineWidth: 1)
        )
        .accessibilityLabel("Loading jobs")
    }
}

// MARK: - SwipePill

private struct SwipePill: View {
    let icon: String?
    let text: String

    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            if let icon {
                Image(systemName: icon)
                    .font(DS.Font.make(11, .semibold, relativeTo: .caption))
            }
            Text(text)
                .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                .lineLimit(1)
        }
        .foregroundStyle(DS.Color.text2)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(DS.Color.surface2, in: Capsule())
    }
}

#Preview {
    JobSwipeView()
        .environmentObject(JobStore())
        .environmentObject(UserStore())
}
