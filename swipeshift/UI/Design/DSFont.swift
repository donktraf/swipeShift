//
//  DSFont.swift
//  swipeShift
//
//  Typografie: Plus Jakarta Sans (SIL OFL), statische Gewichte, Dynamic Type.
//

import SwiftUI
import UIKit

extension DS {
    enum Font {
        enum Weight {
            case regular, medium, semibold, bold, extrabold

            var postScriptName: String {
                switch self {
                case .regular: return "PlusJakartaSans-Regular"
                case .medium: return "PlusJakartaSans-Medium"
                case .semibold: return "PlusJakartaSans-SemiBold"
                case .bold: return "PlusJakartaSans-Bold"
                case .extrabold: return "PlusJakartaSans-ExtraBold"
                }
            }

            var system: SwiftUI.Font.Weight {
                switch self {
                case .regular: return .regular
                case .medium: return .medium
                case .semibold: return .semibold
                case .bold: return .bold
                case .extrabold: return .heavy
                }
            }
        }

        enum Style: CaseIterable {
            case display, title, headline, body, callout, caption, sectionLabel

            var size: CGFloat {
                switch self {
                case .display: return 28
                case .title: return 22
                case .headline: return 17
                case .body: return 15
                case .callout: return 14
                case .caption: return 12
                case .sectionLabel: return 12
                }
            }

            var weight: Weight {
                switch self {
                case .display: return .extrabold
                case .title: return .bold
                case .headline: return .semibold
                case .body: return .regular
                case .callout: return .medium
                case .caption: return .medium
                case .sectionLabel: return .bold
                }
            }

            var textStyle: SwiftUI.Font.TextStyle {
                switch self {
                case .display: return .title
                case .title: return .title2
                case .headline: return .headline
                case .body: return .body
                case .callout: return .callout
                case .caption, .sectionLabel: return .caption
                }
            }

            /// Laufweite in Punkt (display -0.5, Sektionslabel ~0.06em).
            var tracking: CGFloat {
                switch self {
                case .display: return -0.5
                case .sectionLabel: return 0.72
                default: return 0
                }
            }

            var isUppercase: Bool { self == .sectionLabel }
        }

        /// True, wenn die Markenschrift registriert ist (UIAppFonts).
        static var isBrandFontAvailable: Bool {
            UIFont(name: Weight.regular.postScriptName, size: 12) != nil
        }

        /// Freie Groesse/Gewicht, skaliert mit Dynamic Type relativ zu `relativeTo`
        /// (nil = feste Groesse). Faellt auf die Systemschrift zurueck.
        static func make(
            _ size: CGFloat,
            _ weight: Weight = .regular,
            relativeTo textStyle: SwiftUI.Font.TextStyle? = .body
        ) -> SwiftUI.Font {
            guard UIFont(name: weight.postScriptName, size: size) != nil else {
                return .system(size: size, weight: weight.system)
            }
            if let textStyle {
                return .custom(weight.postScriptName, size: size, relativeTo: textStyle)
            }
            return .custom(weight.postScriptName, fixedSize: size)
        }

        static func font(_ style: Style) -> SwiftUI.Font {
            make(style.size, style.weight, relativeTo: style.textStyle)
        }
    }
}

private struct DSFontModifier: ViewModifier {
    let style: DS.Font.Style

    func body(content: Content) -> some View {
        content
            .font(DS.Font.font(style))
            .tracking(style.tracking)
            .textCase(style.isUppercase ? .uppercase : nil)
    }
}

extension View {
    /// Typo-Skala: `.dsFont(.headline)`.
    func dsFont(_ style: DS.Font.Style) -> some View { modifier(DSFontModifier(style: style)) }
}

#Preview("Typo – Light") { DSTypePreview() }
#Preview("Typo – Dark") { DSTypePreview().preferredColorScheme(.dark) }

private struct DSTypePreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // Debug-Check: Schrift registriert?
            Text(DS.Font.isBrandFontAvailable ? "Plus Jakarta Sans geladen" : "FALLBACK: Systemschrift")
                .dsFont(.caption)
                .foregroundStyle(DS.Font.isBrandFontAvailable ? DS.Color.success : DS.Color.danger)
            Text("Find your shift").dsFont(.display)
            Text("Starting soon").dsFont(.title)
            Text("Barista – morning shift").dsFont(.headline)
            Text("Serve coffee and keep the bar tidy.").dsFont(.body).foregroundStyle(DS.Color.text2)
            Text("Quick facts").dsFont(.callout)
            Text("2.4 mi · Applied by 14 people").dsFont(.caption).foregroundStyle(DS.Color.muted)
            Text("Job basics").dsFont(.sectionLabel).foregroundStyle(DS.Color.muted)
        }
        .foregroundStyle(DS.Color.text)
        .padding(DS.Spacing.screenEdge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsBackground()
    }
}
