//
//  DSPreviewSupport.swift
//  swipeShift
//
//  Hilfscontainer fuer #Preview (Hell/Dunkel).
//

import SwiftUI

/// Rahmen fuer Previews: DS-Hintergrund + Randabstand.
struct DSPreviewCanvas<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ScrollView {
            content
                .padding(DS.Spacing.screenEdge)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(DS.Color.text)
        .dsBackground()
    }
}
