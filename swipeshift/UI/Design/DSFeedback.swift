//
//  DSFeedback.swift
//  swipeShift
//
//  DSProgressSteps, Skeleton (shimmer), DSEmptyState.
//

import SwiftUI

// MARK: - Progress Steps

/// Segmentbalken + Schrittnamen. `current` ist 0-basiert.
struct DSProgressSteps: View {
    let steps: [String]
    let current: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index <= current ? DS.Color.primary : DS.Color.border)
                        .frame(height: 6)
                }
            }
            HStack(spacing: DS.Spacing.sm) {
                ForEach(steps.indices, id: \.self) { index in
                    Text(index < current ? "\(steps[index]) ✓" : steps[index])
                        .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                        .foregroundStyle(color(for: index))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .dsAnimation(.standard, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(min(current + 1, steps.count)) of \(steps.count)")
        .accessibilityValue(steps.indices.contains(current) ? steps[current] : "")
    }

    private func color(for index: Int) -> Color {
        if index < current { return DS.Color.success }
        return index == current ? DS.Color.text : DS.Color.muted
    }
}

// MARK: - Skeleton

private struct DSShimmerModifier: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if active && !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, DS.Color.surface.opacity(0.65), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: -geo.size.width * 0.6 + phase * geo.size.width * 1.6)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

private struct DSSkeletonModifier: ViewModifier {
    var isLoading: Bool

    func body(content: Content) -> some View {
        if isLoading {
            content
                .redacted(reason: .placeholder)
                .modifier(DSShimmerModifier(active: true))
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Loading")
        } else {
            content
        }
    }
}

extension View {
    /// Platzhalter beim Laden: Inhalt wird als Skeleton gezeigt (shimmer; statisch bei Reduce Motion).
    func dsSkeleton(_ isLoading: Bool) -> some View { modifier(DSSkeletonModifier(isLoading: isLoading)) }
}

/// Platzhalterform fuer eigene Skeleton-Layouts.
struct DSSkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 14
    var radius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(DS.Color.surface2)
            .frame(width: width, height: height)
            .modifier(DSShimmerModifier(active: true))
            .accessibilityHidden(true)
    }
}

// MARK: - Empty State

struct DSEmptyState: View {
    let systemIcon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: systemIcon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(DS.Color.primaryText)
                .frame(width: 64, height: 64)
                .background(DS.Color.primarySoft, in: Circle())
                .padding(.bottom, DS.Spacing.xxs)
                .accessibilityHidden(true)
            Text(title).dsFont(.title).foregroundStyle(DS.Color.text).multilineTextAlignment(.center)
            Text(message).dsFont(.body).foregroundStyle(DS.Color.text2).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.ds(.primary, size: .medium, fullWidth: false))
                    .padding(.top, DS.Spacing.xs)
            }
        }
        .padding(DS.Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

#Preview("Feedback – Light") { DSFeedbackPreview() }
#Preview("Feedback – Dark") { DSFeedbackPreview().preferredColorScheme(.dark) }

private struct DSFeedbackPreview: View {
    var body: some View {
        DSPreviewCanvas {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                DSProgressSteps(steps: ["Basics", "Shifts", "Pay", "Details", "Review"], current: 1)
                DSCard {
                    HStack(spacing: DS.Spacing.sm) {
                        DSAvatar(text: "BC")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Barista").dsFont(.headline)
                            Text("Blue Cup Coffee · 1.2 mi").dsFont(.caption)
                        }
                    }
                }
                .dsSkeleton(true)
                HStack {
                    DSSkeletonBlock(width: 120, height: 16)
                    DSSkeletonBlock(height: 16)
                }
                DSEmptyState(
                    systemIcon: "tray",
                    title: "No conversations yet",
                    message: "Once an employer accepts your application, your chat will appear here.",
                    actionTitle: "Browse jobs", action: {}
                )
            }
        }
    }
}
