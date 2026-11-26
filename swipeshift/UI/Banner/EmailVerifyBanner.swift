//
//  EmailVerifyBanner.swift
//  swipeShift
//
//  Created by DON on 03.01.26.
//

import SwiftUI

struct EmailVerifyBanner: View {
    @EnvironmentObject var userStore: UserStore

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "envelope.badge")
                .foregroundStyle(DS.Color.warning)
                .accessibilityHidden(true)
            Text("Please verify your email to unlock all features.")
                .dsFont(.callout)
                .foregroundStyle(DS.Color.text)
                .lineLimit(2)

            Spacer()

            ResendVerificationButton(title: "Resend")
        }
        .padding(.horizontal, DS.Spacing.sm)
        .background(DS.Color.warningSoft, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
        .padding(.horizontal, DS.Spacing.inset)
        .padding(.top, DS.Spacing.xs)
    }
}
