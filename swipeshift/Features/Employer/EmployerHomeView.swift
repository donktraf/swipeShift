//
//  EmployerHomeView.swift
//  swipeShift
//
//  Created by DON on 15.12.25.
//

// EmployerHomeView.swift

import SwiftUI

struct EmployerHomeView: View {
    @EnvironmentObject var userStore: UserStore

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {

                Text("Welcome, \((userStore.currentUser?.firstName ?? "") + " " + (userStore.currentUser?.lastName ?? ""))")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Post jobs and find people ready to work.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button {
                    print("Create job tapped (MVP später)")
                } label: {
                    Text("Create a job post")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }

                Text("Your job posts will appear here in the next version.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)

                Spacer()
            }
            .padding()
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Log out") {
                        userStore.logout()
                    }
                }
            }
        }
    }
}

