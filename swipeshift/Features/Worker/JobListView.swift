//
//  JobListView.swift
//  swipeShift
//
//  Created by DON on 15.12.25.
//

// JobListView.swift

import SwiftUI

struct JobListView: View {
    @EnvironmentObject var jobStore: JobStore
    @State private var errorMessage: String?

    var body: some View {
        
        List(jobStore.jobs) { job in
            
            NavigationLink {
                JobDetailView(job: job)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.title)
                        .font(.headline)

                    Text(job.company)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Text(job.location)
                        Text("•")
                        Text(job.payText)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Text(job.shortInfo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Jobs (List)")
        .overlay(alignment: .top) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding()
                    }
                }
                    .task {
                        // Nur laden, wenn Token existiert
                        guard APIClient.shared.token != nil else {
                            errorMessage = "Not logged in / missing token"
                            return
                        }
                        await jobStore.loadJobs()
                    }
    }
}

#Preview {
    NavigationStack {
        JobListView()
            .environmentObject(JobStore())
    }
}
