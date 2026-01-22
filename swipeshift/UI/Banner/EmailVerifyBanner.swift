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
        HStack(spacing: 12) {
            Image(systemName: "envelope.badge")
            Text("Please verify your email to unlock all features.")
                .font(.footnote)
                .lineLimit(2)

            Spacer()

            Button("Resend") {
                Task { await userStore.resendVerification() }
            }
            .font(.footnote)
            .fontWeight(.semibold)
        }
        .padding(12)
        .background(Color.yellow.opacity(0.18))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.yellow.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}
