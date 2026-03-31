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

    // Wie weit gezogen wurde (0…1)
    private var dragFraction: CGFloat { min(abs(dragOffset.width) / 130, 1.0) }
    private var isDraggingRight: Bool { dragOffset.width > 20 }
    private var isDraggingLeft:  Bool { dragOffset.width < -20 }
    private var rotation: Double { Double(dragOffset.width / 22) }

    // swipeJobs als Quelle — unabhängig von jobs/nearbyJobs
    private var topJob:  Job? { jobStore.swipeJobs.first }
    private var nextJob: Job? { jobStore.swipeJobs.dropFirst().first }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                SS.background().ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    cardArea(geo: geo)
                    actionBar
                        .padding(.bottom, 24)
                }
            }
        }
        .task {
            if jobStore.swipeJobs.isEmpty {
                await jobStore.loadSwipeJobs()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Swipe")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                Text("\(jobStore.swipeJobs.count) jobs available")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            Button { /* TODO: Filter */ } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(SS.primary)
                    .padding(10)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    // MARK: - Card Area

    private func cardArea(geo: GeometryProxy) -> some View {
        let cardH = geo.size.height * 0.63

        return ZStack {
            if jobStore.swipeJobs.isEmpty {
                emptyState
            } else {
                // Karte 3 (ganz hinten, kaum sichtbar)
                if jobStore.swipeJobs.count >= 3 {
                    SwipeJobCard(job: jobStore.swipeJobs[2])
                        .frame(height: cardH)
                        .scaleEffect(0.91)
                        .offset(y: -10)
                        .zIndex(1)
                }
                // Karte 2 (mittig)
                if jobStore.swipeJobs.count >= 2 {
                    SwipeJobCard(job: jobStore.swipeJobs[1])
                        .frame(height: cardH)
                        .scaleEffect(0.96)
                        .offset(y: -5)
                        .zIndex(2)
                }
                // Top-Karte (ziehbar)
                if let job = jobStore.swipeJobs.first {
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
                            .onChanged { dragOffset = $0.translation }
                            .onEnded   { handleDragEnd($0, job: job) }
                    )
                    .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.72), value: dragOffset)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 36) {
            // Skip (links)
            circleButton(icon: "xmark", color: .red, size: 58) {
                if let job = jobStore.swipeJobs.first { animateSwipe(direction: -1, job: job) }
            }

            // Bookmark (speichern)
            circleButton(icon: "bookmark", color: SS.primary, size: 44) {
                // TODO: POST /jobs/:id/save
            }

            // Apply (rechts)
            circleButton(icon: "checkmark", color: .green, size: 58) {
                if let job = jobStore.swipeJobs.first { animateSwipe(direction: 1, job: job) }
            }
        }
        .padding(.top, 22)
    }

    private func circleButton(icon: String, color: Color, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundColor(color)
                .frame(width: size, height: size)
                .background(Color.white)
                .clipShape(Circle())
                .shadow(color: color.opacity(0.22), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 52))
                .foregroundColor(.white.opacity(0.35))
            Text("Keine Jobs mehr")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
            Text("Expand your search or\ncheck back later.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            Button {
                Task { await jobStore.loadJobsAll() }
            } label: {
                Text("Refresh")
            }
            .buttonStyle(SSPrimaryButtonStyle())
            .padding(.horizontal, 60)
        }
    }

    // MARK: - Swipe-Logik

    private func handleDragEnd(_ value: DragGesture.Value, job: Job) {
        let threshold: CGFloat = 110
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
        withAnimation(.easeIn(duration: 0.28)) {
            dragOffset = CGSize(width: direction * 700, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            dragOffset = .zero
            Task {
                if direction > 0 { await jobStore.apply(to: job) }
                else             { await jobStore.skip(job) }
            }
        }
    }
}

// MARK: - SwipeJobCard

private struct SwipeJobCard: View {
    let job: Job
    var dragFraction: CGFloat = 0
    var isDraggingRight: Bool = false
    var isDraggingLeft:  Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                cardHeader
                Divider().padding(.horizontal, 16)
                quickInfoRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Divider().padding(.horizontal, 16)
                descriptionBlock
                tagsBlock
                Spacer(minLength: 0)
                cardFooter
            }
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.13), radius: 20, x: 0, y: 8)

            // APPLY Badge
            if isDraggingRight && dragFraction > 0.08 {
                badgeView(text: "APPLY ✓", color: .green, rotation: -14)
                    .opacity(Double(dragFraction))
            }

            // SKIP Badge
            if isDraggingLeft && dragFraction > 0.08 {
                badgeView(text: "SKIP ✗", color: .red, rotation: 14)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 16)
                    .opacity(Double(dragFraction))
            }
        }
    }

    // MARK: Card sections

    private var cardHeader: some View {
        HStack(spacing: 14) {
            Text(job.logoEmoji)
                .font(.system(size: 36))
                .frame(width: 64, height: 64)
                .background(Color.gray.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(job.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if job.isVerified == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13))
                            .foregroundColor(SS.primary)
                    }
                }
                Text(job.company)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                if let cat = job.category {
                    Text(cat)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(SS.primary)
                        .clipShape(Capsule())
                }
            }
            Spacer()
        }
        .padding(16)
    }

    private var quickInfoRow: some View {
        HStack(spacing: 10) {
            SwipePill(icon: "mappin",    text: job.location)
            SwipePill(icon: "banknote",  text: job.payText)
            if let dur = job.duration {
                SwipePill(icon: "clock", text: dur)
            }
        }
    }

    private var descriptionBlock: some View {
        Text(job.shortInfo)
            .font(.system(size: 13))
            .foregroundColor(.secondary)
            .lineLimit(3)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private var tagsBlock: some View {
        Group {
            if !job.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(job.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(SS.primary)
                                .padding(.vertical, 5)
                                .padding(.horizontal, 10)
                                .background(SS.primary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var cardFooter: some View {
        HStack {
            Label(job.shiftText, systemImage: "calendar")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()
            if let spots = job.openSpots {
                Label("\(spots) offen", systemImage: "person.2")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.gray.opacity(0.04))
        .clipShape(
            .rect(
                bottomLeadingRadius: 28,
                bottomTrailingRadius: 28,
                style: .continuous
            )
        )
    }

    // MARK: Badge

    private func badgeView(text: String, color: Color, rotation: Double) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .black))
            .foregroundColor(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color, lineWidth: 2.5)
            )
            .rotationEffect(.degrees(rotation))
            .padding(.horizontal, 16)
            .padding(.top, 20)
    }
}

// MARK: - SwipePill

private struct SwipePill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 12))
                .lineLimit(1)
        }
        .foregroundColor(.secondary)
        .padding(.vertical, 5)
        .padding(.horizontal, 9)
        .background(Color.gray.opacity(0.08))
        .clipShape(Capsule())
    }
}

#Preview {
    JobSwipeView()
        .environmentObject(JobStore())
        .environmentObject(UserStore())
}
