//
//  DSFields.swift
//  swipeShift
//
//  DSTextField, DSTextEditor, DSStepper.
//

import SwiftUI

/// Gemeinsamer Feldrahmen: Label oben, Feld (16 Innenabstand), Fehlertext unten.
private struct DSFieldFrame<Field: View>: View {
    let label: String
    var error: String?
    var isFocused: Bool
    var minHeight: CGFloat
    var onTap: () -> Void
    let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(DS.Font.make(13, .semibold, relativeTo: .footnote))
                .foregroundStyle(DS.Color.text2)

            field
                .font(DS.Font.make(15, .medium))
                .foregroundStyle(DS.Color.text)
                .tint(DS.Color.primary)
                .padding(.horizontal, DS.Spacing.inset)
                .padding(.vertical, 12)
                .frame(minHeight: minHeight, alignment: .topLeading)
                .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: isFocused || error != nil ? 1.5 : 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
                .onTapGesture(perform: onTap)

            if let error {
                Text(error)
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.danger)
                    .accessibilityLabel("Error: \(error)")
            }
        }
    }

    private var borderColor: Color {
        if error != nil { return DS.Color.danger }
        return isFocused ? DS.Color.primary : DS.Color.border
    }
}

/// Einzeiliges Textfeld. Platzhalter ist der native Prompt und sitzt damit exakt auf der Cursor-Linie.
struct DSTextField: View {
    let label: String
    var placeholder: String = ""
    @Binding var text: String
    var error: String?
    var isSecure: Bool = false

    @FocusState private var focused: Bool

    init(_ label: String, placeholder: String = "", text: Binding<String>, error: String? = nil, isSecure: Bool = false) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.error = error
        self.isSecure = isSecure
    }

    var body: some View {
        DSFieldFrame(
            label: label, error: error, isFocused: focused, minHeight: 50,
            onTap: { focused = true },
            field: Group {
                if isSecure {
                    SecureField(label, text: $text, prompt: prompt)
                } else {
                    TextField(label, text: $text, prompt: prompt)
                }
            }
            .focused($focused)
        )
    }

    private var prompt: Text {
        Text(placeholder).foregroundStyle(DS.Color.muted)
    }
}

/// Mehrzeiliges Feld. Nutzt TextField(axis: .vertical), damit der Platzhalter exakt auf der
/// Cursor-Linie liegt (kein Overlay-Hack). Optional mit Zeichenlimit + Zaehler.
struct DSTextEditor: View {
    let label: String
    var placeholder: String = ""
    @Binding var text: String
    var error: String?
    var minLines: Int = 3
    var maxLines: Int = 8
    var maxLength: Int?

    @FocusState private var focused: Bool

    init(
        _ label: String, placeholder: String = "", text: Binding<String>, error: String? = nil,
        minLines: Int = 3, maxLines: Int = 8, maxLength: Int? = nil
    ) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.error = error
        self.minLines = minLines
        self.maxLines = maxLines
        self.maxLength = maxLength
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            DSFieldFrame(
                label: label, error: error, isFocused: focused, minHeight: 50,
                onTap: { focused = true },
                field: TextField(label, text: $text, prompt: Text(placeholder).foregroundStyle(DS.Color.muted), axis: .vertical)
                    .lineLimit(minLines...max(minLines, maxLines))
                    .focused($focused)
            )
            if let maxLength {
                Text("\(text.count)/\(maxLength)")
                    .dsFont(.caption)
                    .foregroundStyle(text.count >= maxLength ? DS.Color.danger : DS.Color.muted)
            }
        }
        .onChange(of: text) { _, newValue in
            if let maxLength, newValue.count > maxLength {
                text = String(newValue.prefix(maxLength))
            }
        }
    }
}

/// Minus/Plus-Stepper in getoentem Container.
struct DSStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...99
    var step: Int = 1
    var accessibilityName: String = "Value"

    var body: some View {
        HStack(spacing: DS.Spacing.xxs) {
            stepButton("minus", label: "Decrease", enabled: value - step >= range.lowerBound) {
                value = max(range.lowerBound, value - step)
            }
            Text("\(value)")
                .font(DS.Font.make(15, .extrabold))
                .foregroundStyle(DS.Color.text)
                .frame(minWidth: 32)
                .monospacedDigit()
            stepButton("plus", label: "Increase", enabled: value + step <= range.upperBound) {
                value = min(range.upperBound, value + step)
            }
        }
        .padding(DS.Spacing.xxs)
        .background(DS.Color.surface2, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }

    private func stepButton(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            DS.Haptics.selection()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DS.Color.text)
                .frame(width: 36, height: 36)
                .background(DS.Color.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .opacity(enabled ? 1 : 0.4)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.dsPressable)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

#Preview("Fields – Light") { DSFieldsPreview() }
#Preview("Fields – Dark") { DSFieldsPreview().preferredColorScheme(.dark) }

private struct DSFieldsPreview: View {
    @State private var title = "Event staff"
    @State private var empty = ""
    @State private var desc = ""
    @State private var workers = 6

    var body: some View {
        DSPreviewCanvas {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                DSTextField("Job title", placeholder: "e.g. Barista", text: $title)
                DSTextField("Location", placeholder: "City or address", text: $empty, error: "Location is required")
                DSTextEditor("Description", placeholder: "Describe the job", text: $desc, maxLength: 300)
                DSSection("Workers", ruled: true) {
                    HStack {
                        Text("Workers needed").dsFont(.body)
                        Spacer()
                        DSStepper(value: $workers, range: 1...50, accessibilityName: "Workers needed")
                    }
                    .padding(.vertical, DS.Spacing.xs)
                }
            }
        }
    }
}
