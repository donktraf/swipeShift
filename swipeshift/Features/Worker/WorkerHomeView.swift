//
//  WorkerHomeView.swift
//  swipeShift
//
//  Created by DON on 15.12.25.
//

// WorkerHomeView.swift

import SwiftUI

struct WorkerHomeView: View {
    @EnvironmentObject var userStore: UserStore
    @EnvironmentObject var jobStore: JobStore

    var body: some View {
        // NavigationStack ist hier, weil von hier aus in die Jobliste navigiert wird
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {

                Text("Hi, \(userStore.currentUser?.firstName ?? "") \(userStore.currentUser?.lastName ?? "") there")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Find flexible jobs that match your availability.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // 👉 Sobald Worker hier drauf klickt → JobListView
                NavigationLink {
                    //JobListView()
                    JobSwipeView()
                        .onAppear {
                            guard let location = userStore.currentUser?.location else {
                                print("User has no location")
                                return
                            }

                            if jobStore.selectedLocation == nil {
                                jobStore.selectedLocation = location
                                print("selectedLocation set to:", location)
                            }
                        }
                } label: {
                    Text("Explore jobs")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
                .padding(.top, 8)

                Spacer()
            }
            .padding()
            .navigationTitle("Home")
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

#Preview {
    WorkerHomeView()
        .environmentObject(UserStore())
        .environmentObject(JobStore())
}
