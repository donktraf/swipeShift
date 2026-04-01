//
//  WorkerHomeView.swift
//  swipeShift
//

import SwiftUI

struct WorkerHomeView: View {
    @EnvironmentObject var userStore: UserStore
    @EnvironmentObject var jobStore: JobStore
    @EnvironmentObject var messageStore: MessageStore

    @State private var selectedTab: WorkerTab = .home

    // Für Navigation zu Kategorie-JobListe und allen Jobs
    @State private var selectedCategory: JobCategory? = nil
    @State private var navigateToCategoryList = false
    @State private var navigateToAllJobs = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {

                SS.background().ignoresSafeArea()

                // MARK: - Tab Content
                Group {
                    switch selectedTab {
                    case .home:
                        WorkerHomeTabView(
                            onCategorySelected: { category in
                                selectedCategory = category
                                navigateToCategoryList = true
                            },
                            onViewAllJobs: {
                                navigateToAllJobs = true
                            },
                            onGoToRadar: {
                                selectedTab = .radar
                            },
                            onGoToSwipe: {
                                selectedTab = .swipe
                            }
                        )

                    case .radar:
                        RadarView(
                            lat: userStore.currentUser?.lat ?? 48.7758,
                            lng: userStore.currentUser?.lng ?? 9.1829
                        )

                    case .messages:
                        MessagesView()
                            .environmentObject(messageStore)

                    case .swipe:
                        JobSwipeView()
                            .onAppear {
                                if jobStore.selectedLocation == nil,
                                   let location = userStore.currentUser?.location {
                                    jobStore.selectedLocation = location
                                }
                            }

                    case .profile:
                        WorkerProfileView()
                            .environmentObject(userStore)
                    }
                }
                // Genug Platz für TabBar lassen
                .padding(.bottom, 80)

                // MARK: - Tab Bar
                VStack(spacing: 0) {
                    Spacer()
                    AppTabBar(
                        selectedTab: $selectedTab,
                        unreadMessageCount: messageStore.unreadCount
                    )
                    .padding(.bottom, 8)
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationBarHidden(true)
            // Navigation zu Kategorie-Liste
            .navigationDestination(isPresented: $navigateToCategoryList) {
                if let category = selectedCategory {
                    CategoryJobListView(category: category)
                        .environmentObject(jobStore)
                }
            }
            .navigationDestination(isPresented: $navigateToAllJobs) {
                JobListView()
                    .environmentObject(jobStore)
                    .environmentObject(userStore)
            }
        }
    }
}

/// Placeholder für noch nicht implementierte Tabs
struct PlaceholderTabView: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.4))

            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.secondary.opacity(0.6))

            Text("Coming soon")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SS.background().ignoresSafeArea())
    }
}

struct ProfilePlaceholderView: View {
    @EnvironmentObject var userStore: UserStore

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.4))

            Text("Profile")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.secondary.opacity(0.6))

            Text("Coming soon")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.4))

            Spacer()

            // ✅ Logout Button
            Button {
                userStore.logout()
            } label: {
                Text("Log out")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SS.background().ignoresSafeArea())
    }
}

#Preview {
    WorkerHomeView()
        .environmentObject(UserStore())
        .environmentObject(JobStore())
        .environmentObject(MessageStore())
}
