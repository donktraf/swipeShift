//
//  Theme.swift
//  swipeShift
//
//  Created by DON on 05.03.26.
//

import SwiftUI

enum SS {
    // Primary from Hex: #2563EB — Electric Blue
    static let primary = Color(red: 37/255, green: 99/255, blue: 235/255)
    static let bgTop    = Color(red: 29/255, green: 78/255, blue: 216/255).opacity(0.97)
    static let bgBottom = Color(red: 30/255, green: 58/255, blue: 138/255).opacity(0.97)

    /// Standard-Radius fuer Job-/Listenkarten (JobSectionView, JobListView, RadarView, JobDetailView).
    /// Aktuell nutzen diese Views noch hardcodierte Werte (12-16pt) statt dieser Konstante —
    /// siehe design-review.md Finding #8 fuer die optionale strukturelle Umstellung.
    static let cardRadius: CGFloat = 14
    /// Groesserer Radius, urspruenglich als "cardRadius" bezeichnet, wird ausschliesslich
    /// von SSCard (Auth-Screens) verwendet.
    static let authCardRadius: CGFloat = 34
    static let controlRadius: CGFloat = 16

    static let shadow = Color.black.opacity(0.10)

    static func background() -> LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct SSCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(24)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: SS.authCardRadius, style: .continuous))
            .shadow(color: SS.shadow, radius: 18, x: 0, y: 10)
            .padding(.horizontal, 18)
    }
}

struct SSPrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isEnabled ? SS.primary : Color.gray.opacity(0.35))
            .foregroundColor(.white)
            .font(.system(size: 18, weight: .semibold))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: SS.shadow, radius: configuration.isPressed ? 6 : 14, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
    }
}

struct SSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.55))
            .foregroundColor(.primary)
            .font(.system(size: 17, weight: .semibold))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
    }
}

struct SSTextFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: SS.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SS.controlRadius, style: .continuous)
                    .stroke(Color.gray.opacity(0.18), lineWidth: 1)
            )
    }
}


struct SSOAuthPillButton: View {
    let title: String
    let icon: Image?
    let background: Color
    let foreground: Color
    let border: Color?

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            } else {
                // Platzhalter damit Text wirklich mittig bleibt
                Color.clear.frame(width: 18, height: 18)
            }

            Spacer()

            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(foreground)

            Spacer()

            // rechts gleicher Platzhalter für perfekte Zentrierung
            Color.clear.frame(width: 18, height: 18)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(border ?? .clear, lineWidth: border == nil ? 0 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension View {
    func ssTextField() -> some View { modifier(SSTextFieldStyle()) }
}
