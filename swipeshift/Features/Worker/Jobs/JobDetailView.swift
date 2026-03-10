//
//  JobDetailView.swift
//  swipeShift
//
//  Created by DON on 15.12.25.
//

// JobDetailView.swift

import SwiftUI

struct JobDetailView: View {
    let job: Job

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Logo + Titel + Firma
                HStack(alignment: .center, spacing: 12) {
                    Text(job.logoEmoji)
                        .font(.system(size: 40))
                        .frame(width: 64, height: 64)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.title)
                            .font(.title)
                            .fontWeight(.bold)

                        Text(job.company)
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                // Ort, Pay, Distance
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                        Text(job.location)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "eurosign.circle")
                        Text(job.payText)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "figure.walk")
                        Text(job.distanceText)
                    }
                }
                .font(.subheadline)
                .foregroundColor(.secondary)

                Divider()

                // Shift Time
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text(job.shiftText)
                }
                .font(.subheadline)

                // Beschreibung / Short Info
                Text("About this shift")
                    .font(.headline)
                    .padding(.top, 8)

                Text(job.shortInfo)
                    .font(.body)

                // Tags
                if !job.tags.isEmpty {
                    Text("Highlights")
                        .font(.headline)
                        .padding(.top, 8)

                    WrapTagsView(tags: job.tags)
                }

                Spacer().frame(height: 24)

                // Apply Button
                Button {
                    print("User applied to \(job.title)")
                    // später: API Call
                } label: {
                    Text("Apply now")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// Kleine helper-View für Tags
struct WrapTagsView: View {
    let tags: [String]

    var body: some View {
        // einfache Wrap-Implementierung über LazyVGrid
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.blue.opacity(0.08))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
            }
        }
    }
}

/*#Preview {
    NavigationStack {
        JobDetailView(
            job: Job(
                id: "preview-1",  // ✅ neu
                title: "Event Staff",
                company: "Berlin Events GmbH",
                location: "Berlin",
                payText: "€15 / hour",
                distanceText: "1.2 km away",
                shiftText: "Today, 18:00–23:00",
                shortInfo: "Help with setup...",
                tags: ["Flexible", "Same-day pay", "No experience"],
                logoEmoji: "🎪"
            )
        )
    }
}
*/
