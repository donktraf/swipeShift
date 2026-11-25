//
//  DSButtons.swift
//  swipeShift
//
//  Button-Styles (primary/secondary/soft/destructiveSoft) + DSIconButton.
//

import SwiftUI

enum DSButtonVariant { case primary, secondary, soft, destructiveSoft }
enum DSButtonSize { case large, medium }

struct DSButtonStyle: ButtonStyle {
    var variant: DSButtonVariant = .primary
    var size: DSButtonSize = .large
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        DSButtonBody(configuration: configuration, variant: variant, size: size, fullWidth: fullWidth)
    }
}

private struct DSButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let variant: DSButtonVariant
    let size: DSButtonSize
    let fullWidth: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var height: CGFloat { size == .large ? 52 : 44 }
    private var radius: CGFloat { size == .large ? DS.Radius.button : DS.Radius.control }
    private var font: Font { size == .large ? DS.Font.make(16, .semibold) : DS.Font.make(15, .semibold) }

    private var background: Color {
        switch variant {
        case .primary: return DS.Color.primary
        case .secondary: return DS.Color.surface
        case .soft: return DS.Color.primarySoft
        case .destructiveSoft: return DS.Color.dangerSoft
        }
    }

    private var foreground: Color {
        switch variant {
        case .primary: return DS.Color.onPrimary
        case .secondary: return DS.Color.text
        case .soft: return DS.Color.primaryText
        case .destructiveSoft: return DS.Color.danger
        }
    }

    var body: some View {
        configuration.label
            .font(font)
            .foregroundStyle(foreground)
            .padding(.horizontal, DS.Spacing.md)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .background(background, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if variant == .secondary {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(DS.Color.border, lineWidth: 1)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : DS.Motion.snappy.animation, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { DS.Haptics.light() }
            }
    }
}

/// Leichter Press-Effekt fuer antippbare Container (Karten, Chips, Zeilen).
struct DSPressableStyle: ButtonStyle {
    var scale: CGFloat = 0.98
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .animation(reduceMotion ? nil : DS.Motion.snappy.animation, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == DSButtonStyle {
    /// `.buttonStyle(.ds(.primary))`, `.buttonStyle(.ds(.soft, size: .medium, fullWidth: false))`
    static func ds(_ variant: DSButtonVariant = .primary, size: DSButtonSize = .large, fullWidth: Bool = true) -> DSButtonStyle {
        DSButtonStyle(variant: variant, size: size, fullWidth: fullWidth)
    }
}

extension ButtonStyle where Self == DSPressableStyle {
    static var dsPressable: DSPressableStyle { DSPressableStyle() }
}

/// 44x44 Icon-Button mit Rand. `label` ist Pflicht (VoiceOver).
struct DSIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button {
            DS.Haptics.light()
            action()
        } label: {
            Image(systemName: systemName)
                .font(DS.Font.make(17, .semibold))
                .foregroundStyle(DS.Color.text)
                .frame(width: 44, height: 44)
                .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .strokeBorder(DS.Color.border, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        }
        .buttonStyle(.dsPressable)
        .accessibilityLabel(label)
    }
}

#Preview("Buttons – Light") { DSButtonsPreview() }
#Preview("Buttons – Dark") { DSButtonsPreview().preferredColorScheme(.dark) }

private struct DSButtonsPreview: View {
    var body: some View {
        DSPreviewCanvas {
            VStack(spacing: DS.Spacing.sm) {
                Button("Apply now") {}.buttonStyle(.ds(.primary))
                Button("Save for later") {}.buttonStyle(.ds(.secondary))
                Button("Disabled") {}.buttonStyle(.ds(.primary)).disabled(true)
                HStack(spacing: DS.Spacing.sm) {
                    Button("Open chat") {}.buttonStyle(.ds(.soft, size: .medium))
                    Button("Cancel shift") {}.buttonStyle(.ds(.destructiveSoft, size: .medium))
                }
                HStack {
                    DSIconButton(systemName: "xmark", label: "Close") {}
                    DSIconButton(systemName: "bookmark", label: "Save") {}
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
