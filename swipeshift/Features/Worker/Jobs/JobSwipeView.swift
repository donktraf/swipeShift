//
//  JobSwipeView.swift
//  swipeShift
//
//  Created by DON on 15.12.25.
//

import SwiftUI

struct JobSwipeView: View {
    @EnvironmentObject var jobStore: JobStore

    // Offset für das aktuell sichtbare Card-Dragging
    @State private var dragOffset: CGSize = .zero
    @State private var isApplying: Bool = false   // für kleine Farbeffekte, optional
    
    private let bottomSafeArea: CGFloat = 120   // 👈 Platz für spätere Funktionen

    // Der aktuell erste Job im Feed
    private var currentJob: Job? {
        jobStore.jobs.first
    }

    var body: some View {
        ZStack {
            if let job = currentJob {

                ZStack {
                    // Hauptinhalt
                    VStack(spacing: 16) {

                        // Filter-Leiste
                        HStack {
                            Button {
                                print("Filter tapped")
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "slider.horizontal.3")
                                    Text("Filter")
                                }
                            }

                            Spacer()

                            Button {
                                print("Expand search area tapped")
                            } label: {
                                Text("Expand area")
                            }
                        }
                        .padding(.horizontal)

                        // Job Card (größer)
                        jobCard(job)
                            .padding(.horizontal, 16)
                            .frame(maxHeight: .infinity)          // <-- macht die Karte "großer"
                            .offset(x: dragOffset.width, y: dragOffset.height)
                            .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        dragOffset = value.translation
                                    }
                                    .onEnded { value in
                                        handleDragEnd(value: value, job: job)
                                    }
                            )
                            .animation(.spring(), value: dragOffset)

                        // Buttons
                        actionButtons(for: job)

                        Spacer(minLength: bottomSafeArea)         // Platz für bottom bar
                    }

                    // Fixe Bottom-Bar
                    VStack {
                        Spacer()
                        bottomBar
                    }
                }

            } else {
                // Kein Job mehr im Feed
                VStack(spacing: 16) {
                    Text("No more jobs right now")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Try expanding your search area or updating your filters.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Button {
                        Task { await jobStore.loadJobs() }
                    } label: {
                        Text("Refresh")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                    }
                    .padding(.horizontal, 32)
                }
            }
        }
        .navigationTitle("Jobs for you")
        .navigationBarTitleDisplayMode(.inline)
        
        .onAppear {
            Task {
                print("Loading jobs for location:", jobStore.selectedLocation ?? "nil")
                await jobStore.loadJobs()
            }
        }
    }
    // MARK: - Job Card View

    private func jobCard(_ job: Job) -> some View {
        VStack(alignment: .leading, spacing: 12) {

            // Top: Logo + Titel + Company
            HStack(alignment: .center, spacing: 12) {
                Text(job.logoEmoji)
                    .font(.system(size: 32))
                    .frame(width: 56, height: 56)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 4) {
                    Text(job.title)
                        .font(.headline)

                    Text(job.company)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Pay & Distance
            HStack(spacing: 12) {
                labelCapsule(text: job.payText, systemImage: "eurosign.circle")

                labelCapsule(text: job.distanceText, systemImage: "mappin.and.ellipse")
            }

            // Shift time & info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text(job.shiftText)
                }
                .font(.subheadline)

                Text(job.shortInfo)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Tags
            if !job.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(job.tags, id: \.self) { tag in
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
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
        )
    }
    
    private var bottomBar: some View {
        HStack {
            Text("Actions coming soon")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: bottomSafeArea)
        .background(Color(.secondarySystemBackground))
    }

    // Kleine Helfer für Pills
    private func labelCapsule(text: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(text)
        }
        .font(.caption)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.gray.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Actions unter der Card

    private func actionButtons(for job: Job) -> some View {
        HStack(spacing: 16) {
            // Not interested (rechts-Swipe)
            Button {
                withAnimation {
                    dragOffset = .zero
                }
                Task {
                    await jobStore.skip(job)
                }
            } label: {
                VStack {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 32))
                    Text("Not interested")
                        .font(.caption)
                }
            }

            Spacer()

            // Save
            /*Button {
                jobStore.save(job) //-- Später schauen was damit ist
            } label: {
                VStack {
                    Image(systemName: "bookmark")
                        .font(.system(size: 24))
                    Text("Save")
                        .font(.caption)
                }
            }*/

            Spacer()

            // Share
            Button {
                print("Share job:", job.title)
                // Später: ShareSheet
            } label: {
                VStack {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 24))
                    Text("Share")
                        .font(.caption)
                }
            }

            Spacer()

            // Apply (links-Swipe)
            Button {
                withAnimation {
                    dragOffset = .zero
                }
                Task {
                    await jobStore.apply(to: job)
                }
            } label: {
                VStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                    Text("Apply")
                        .font(.caption)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 8)
        
        
    }

    // MARK: - Swipe-Logik

    private func handleDragEnd(value: DragGesture.Value, job: Job) {
        let threshold: CGFloat = 120  // wie weit man wischen muss

        if value.translation.width <= -threshold {
            // 👉 Links-Swipe = interessiert / apply
            withAnimation {
                dragOffset = .zero
            }
            Task {
                await jobStore.apply(to: job)
            }

        } else if value.translation.width >= threshold {
            // 👉 Rechts-Swipe = nicht interessiert / entfernen
            withAnimation {
                dragOffset = .zero
            }
            Task {
                await jobStore.skip(job)
            }

        } else {
            // Zu wenig gewischt → Karte zurückspringen
            withAnimation {
                dragOffset = .zero
            }
        }
    }
}

#Preview {
    NavigationStack {
        JobSwipeView()
            .environmentObject(JobStore())
    }
}
