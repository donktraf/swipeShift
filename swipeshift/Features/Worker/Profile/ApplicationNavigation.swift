//
//  ApplicationNavigation.swift
//  swipeShift
//
//  Gemeinsame Navigation "View job" / "Open Chat" fuer Worker-Kalender und Job Applications:
//  Job per ID laden und als Sheet zeigen, Conversation per ID suchen und den Chat pushen.
//  Fehler werden in einem Alert angezeigt.
//

import SwiftUI
import Combine

@MainActor
final class ApplicationNavigation: ObservableObject {
    @Published var jobDetail: Job?
    @Published var chatConversation: Conversation?
    @Published var actionError: String?

    func openJob(jobId: String) {
        Task {
            do {
                jobDetail = try await APIClient.shared.fetchJob(jobId: jobId)
            } catch {
                actionError = "The job details could not be loaded."
            }
        }
    }

    func openChat(conversationId: String?, messageStore: MessageStore) {
        guard let conversationId else { return }
        Task {
            if messageStore.conversations.first(where: { $0.id == conversationId }) == nil {
                await messageStore.loadConversations()
            }
            if let conversation = messageStore.conversations.first(where: { $0.id == conversationId }) {
                chatConversation = conversation
            } else {
                actionError = "The chat for this job could not be found."
            }
        }
    }
}

private struct ApplicationNavigationModifier: ViewModifier {
    @ObservedObject var navigation: ApplicationNavigation

    func body(content: Content) -> some View {
        content
            .sheet(item: $navigation.jobDetail) { job in
                NavigationStack { JobDetailView(job: job) }
            }
            .navigationDestination(isPresented: Binding(
                get: { navigation.chatConversation != nil },
                set: { if !$0 { navigation.chatConversation = nil } }
            )) {
                if let conversation = navigation.chatConversation {
                    ChatView(conversation: conversation)
                }
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { navigation.actionError != nil },
                set: { if !$0 { navigation.actionError = nil } }
            )) {
                Button("OK", role: .cancel) { navigation.actionError = nil }
            } message: {
                Text(navigation.actionError ?? "")
            }
    }
}

extension View {
    /// Haengt Job-Sheet, Chat-Ziel und Fehler-Alert fuer `ApplicationNavigation` an.
    func applicationNavigation(_ navigation: ApplicationNavigation) -> some View {
        modifier(ApplicationNavigationModifier(navigation: navigation))
    }
}
