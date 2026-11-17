//
//  PostJobView.swift
//  swipeShift
//

import SwiftUI

// MARK: - Draft Shift Model
struct DraftShift: Identifiable {
    let id = UUID()
    var date: Date = Date()
    var startTime: Date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    var endTime: Date = Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: Date()) ?? Date()

    var durationText: String {
        let diff = endTime.timeIntervalSince(startTime)
        guard diff > 0 else { return "–" }
        let h = Int(diff / 3600)
        let m = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)
        return m == 0 ? "\(h)h" : "\(h)h \(m)min"
    }

    var dateLabel: String {
        let f = DateFormatter(); f.dateFormat = "EE, MMM dd"; f.locale = Locale(identifier: "en_US")
        return f.string(from: date)
    }

    var timeRangeLabel: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return "\(f.string(from: startTime))–\(f.string(from: endTime))"
    }

    func toRequest(payAmount: Double) -> PostJobShiftRequest {
        let hours = max(0, endTime.timeIntervalSince(startTime) / 3600)
        let total = String(format: "€%.0f total", hours * payAmount)

        // Combine date + start/end time into full DateTime for the backend
        let cal = Calendar.current
        let startComponents = cal.dateComponents([.hour, .minute], from: startTime)
        let endComponents   = cal.dateComponents([.hour, .minute], from: endTime)
        let startFull = cal.date(bySettingHour: startComponents.hour ?? 0,
                                 minute: startComponents.minute ?? 0,
                                 second: 0, of: date)
        let endFull = cal.date(bySettingHour: endComponents.hour ?? 0,
                               minute: endComponents.minute ?? 0,
                               second: 0, of: date)

        let iso = ISO8601DateFormatter()
        return PostJobShiftRequest(
            date: dateLabel,
            timeRange: timeRangeLabel,
            duration: durationText,
            totalPay: total,
            startTimeISO: startFull.map { iso.string(from: $0) },
            endTimeISO:   endFull.map   { iso.string(from: $0) }
        )
    }
}

// MARK: - Tag Groups
private let tagGroups: [(label: String, tags: [String])] = [
    ("Work Environment",       ["Indoor", "Outdoor", "Standing", "Sitting", "Fast-paced", "Quiet"]),
    ("Physical Requirements",  ["Light Lifting", "Heavy Lifting", "Lots of Walking", "Climbing"]),
    ("Social Interaction",     ["Customer Facing", "Teamwork", "Solo Work", "Phone Work"]),
    ("Special Features",       ["Uniform Provided", "Tips Possible", "Same-day Pay", "Flexible Hours"]),
]

private let dressCodeOptions   = ["No Dress Code", "Smart Casual", "Formal", "Work Clothing", "Uniform Provided"]
private let languageOptions    = ["German", "English", "Turkish", "Arabic", "Spanish", "French"]
private let expLevelOptions    = ["No Experience Required", "Up to 3 Months", "3–12 Months", "1+ Years"]
private let payFreqOptions     = ["After Shift", "Weekly", "Biweekly", "Monthly"]
private let contractTypeOptions = ["Freelance", "Mini-Job", "Temporary", "Insured Employment"]

// MARK: - PostJobView
struct PostJobView: View {
    @EnvironmentObject var userStore: UserStore
    @Environment(\.dismiss) private var dismiss

    /// Gesetzt = Bearbeiten-Modus fuer einen bestehenden Draft ("Edit Draft", PUT statt POST)
    let editingJobId: String?
    @State private var isLoadingDraft = false
    @State private var draftLoadError: String? = nil
    @State private var skipNextLocationReset = false

    init(editingJobId: String? = nil) {
        self.editingJobId = editingJobId
    }

    private var isEditing: Bool { editingJobId != nil }

    // Job Basics
    @State private var title = ""
    @State private var locationText = ""
    @State private var locationLat: Double? = nil
    @State private var locationLng: Double? = nil
    @StateObject private var locationGeocoder = LocationGeocoder()
    @State private var showLocationSuggestions = false
    @State private var locationSearchTask: Task<Void, Never>? = nil

    // Kategorie
    @State private var selectedCategory: String = ""

    // Tags
    @State private var selectedTags: Set<String> = []

    // Schichten
    @State private var shifts: [DraftShift] = [DraftShift()]

    // Workers & Lohn
    @State private var numberOfWorkers = 1
    @State private var hourlyRateText = ""

    // Beschreibung & Aufgaben
    @State private var jobDescription = ""
    @State private var tasks: [String] = [""]

    // Anforderungen
    @State private var selectedDressCode = ""
    @State private var selectedLanguages: Set<String> = []
    @State private var minAgeText = ""
    @State private var selectedExpLevel = ""

    // Zahlung
    @State private var selectedPayFreq = ""
    @State private var selectedContractType = ""

    // Sheets & Alerts
    @State private var showConfirmSheet = false
    @State private var pendingStatus: String = "published"
    @State private var isSubmitting = false
    @State private var showSuccessBanner = false
    @State private var errorMessage: String? = nil

    private var companyName: String { userStore.currentUser?.companyName ?? "My Company" }

    private var canPost: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !selectedCategory.isEmpty &&
        !shifts.isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                navBar
                Divider()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        basicInfoSection
                        categorySection
                        tagsSection
                        shiftsSection
                        workersAndPaySection
                        descriptionSection
                        tasksSection
                        requirementsSection
                        paymentSection
                        Spacer().frame(height: 110)
                    }
                }
            }

            footerBar
        }
        .navigationBarHidden(true)
        .overlay {
            // Laden fehlgeschlagen: kein (leeres) Formular, sonst koennte der Draft mit Defaults ueberschrieben werden
            if let draftLoadError {
                ZStack {
                    Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36))
                            .foregroundColor(.orange)
                        Text("Couldn't load this draft")
                            .font(.system(size: 17, weight: .semibold))
                        Text(draftLoadError)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await loadDraftIfNeeded() } }
                            .buttonStyle(SSPrimaryButtonStyle())
                        Button("Close") { dismiss() }
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 40)
                }
            } else if isLoadingDraft {
                ZStack {
                    Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                    ProgressView()
                }
            }
        }
        .task { await loadDraftIfNeeded() }
        .sheet(isPresented: $showConfirmSheet) {
            PostJobConfirmSheet(
                jobTitle: title,
                company: companyName,
                shiftsCount: shifts.count,
                isDraft: pendingStatus == "draft",
                onSaveAsDraft: {
                    showConfirmSheet = false
                    pendingStatus = "draft"
                    Task { await submit() }
                },
                onPost: {
                    showConfirmSheet = false
                    pendingStatus = "published"
                    Task { await submit() }
                },
                onCancel: { showConfirmSheet = false }
            )
        }
    }

    // MARK: - Nav Bar
    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(Circle())
            }

            Spacer()

            Text(isEditing ? "Edit Draft" : "Post a Job")
                .font(.system(size: 17, weight: .semibold))

            Spacer()

            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Grundinfos
    private var basicInfoSection: some View {
        FormSection(title: "Basic Info") {
            VStack(spacing: 0) {
                FormRow(label: "Job Title") {
                    TextField("e.g. Event Staff", text: $title)
                        .font(.system(size: 15))
                }
                Divider().padding(.leading, 16)
                FormRow(label: "Company") {
                    Text(companyName)
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                Divider().padding(.leading, 16)
                FormRow(label: "Location") {
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("City or address", text: $locationText)
                            .font(.system(size: 15))
                            .onChange(of: locationText) { _, newValue in
                                // Vorbefuellung im Bearbeiten-Modus: Koordinaten behalten, keine Vorschlaege oeffnen
                                if skipNextLocationReset { skipNextLocationReset = false; return }
                                locationLat = nil
                                locationLng = nil
                                showLocationSuggestions = true
                                locationSearchTask?.cancel()
                                locationSearchTask = Task {
                                    try? await Task.sleep(nanoseconds: 350_000_000)
                                    if Task.isCancelled { return }
                                    await MainActor.run { locationGeocoder.updateQuery(newValue) }
                                }
                            }

                        if showLocationSuggestions && !locationGeocoder.suggestions.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(locationGeocoder.suggestions) { s in
                                    Button {
                                        locationText = s.fullText
                                        locationLat  = s.lat
                                        locationLng  = s.lng
                                        showLocationSuggestions = false
                                        locationGeocoder.updateQuery("")
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(s.title)
                                                .font(.system(size: 14))
                                                .foregroundColor(.primary)
                                            if !s.subtitle.isEmpty {
                                                Text(s.subtitle)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    Divider()
                                }
                            }
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.top, 4)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Kategorie
    private var categorySection: some View {
        FormSection(title: "Category") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 100), spacing: 8)],
                spacing: 8
            ) {
                ForEach(JobCategory.all, id: \.name) { cat in
                    let isSelected = selectedCategory == cat.name
                    Button { selectedCategory = cat.name } label: {
                        HStack(spacing: 6) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 13))
                            Text(cat.name)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(isSelected ? .white : SS.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? SS.primary : SS.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.2), value: isSelected)
                }
            }
            .padding(14)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Tags
    private var tagsSection: some View {
        FormSection(title: "Job Tags") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(tagGroups, id: \.label) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        FlowChips(
                            items: group.tags,
                            selected: $selectedTags
                        )
                    }
                }
            }
            .padding(14)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Schichten
    private var shiftsSection: some View {
        FormSection(title: "Shifts") {
            VStack(spacing: 10) {
                ForEach($shifts) { $shift in
                    ShiftRow(shift: $shift, onRemove: shifts.count > 1 ? {
                        shifts.removeAll { $0.id == shift.id }
                    } : nil)
                }

                Button {
                    shifts.append(DraftShift())
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 15))
                        Text("Add Shift")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(SS.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(SS.primary.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Mitarbeiter & Lohn
    private var workersAndPaySection: some View {
        FormSection(title: "Workers & Pay") {
            VStack(spacing: 0) {
                FormRow(label: "Number of Workers") {
                    Stepper("\(numberOfWorkers)", value: $numberOfWorkers, in: 1...50)
                        .labelsHidden()
                    Text("\(numberOfWorkers)")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 30)
                }
                Divider().padding(.leading, 16)
                FormRow(label: "Hourly Rate (€)") {
                    TextField("e.g. 15.00", text: $hourlyRateText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 15))
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    // MARK: - Stellenbeschreibung
    private var descriptionSection: some View {
        FormSection(title: "Job Description") {
            TextEditor(text: $jobDescription)
                .font(.system(size: 15))
                .frame(minHeight: 100)
                .padding(10)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    Group {
                        if jobDescription.isEmpty {
                            Text("Describe the job, workflow, and work environment…")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary.opacity(0.6))
                                .padding(14)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )
        }
    }

    // MARK: - Aufgaben
    private var tasksSection: some View {
        FormSection(title: "Tasks") {
            VStack(spacing: 8) {
                ForEach(tasks.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 7))
                            .foregroundColor(SS.primary)
                            .padding(.leading, 4)

                        TextField("Describe task", text: $tasks[i])
                            .font(.system(size: 15))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        if tasks.count > 1 {
                            Button { tasks.remove(at: i) } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red.opacity(0.7))
                                    .font(.system(size: 20))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    tasks.append("")
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14))
                        Text("Add Task")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(SS.primary)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(14)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Anforderungen
    private var requirementsSection: some View {
        FormSection(title: "Requirements") {
            VStack(spacing: 0) {
                // Dress Code
                PickerRow(label: "Dress Code", options: dressCodeOptions, selection: $selectedDressCode)
                Divider().padding(.leading, 16)

                // Languages
                MultiPickerRow(label: "Languages", options: languageOptions, selected: $selectedLanguages)
                Divider().padding(.leading, 16)

                // Min Age
                FormRow(label: "Min. Age") {
                    TextField("e.g. 18", text: $minAgeText)
                        .keyboardType(.numberPad)
                        .font(.system(size: 15))
                        .multilineTextAlignment(.trailing)
                }
                Divider().padding(.leading, 16)

                // Experience Level (Radio Buttons)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Experience Level")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                    VStack(spacing: 0) {
                        ForEach(expLevelOptions, id: \.self) { option in
                            Button {
                                selectedExpLevel = option
                            } label: {
                                HStack {
                                    Text(option)
                                        .font(.system(size: 15))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: selectedExpLevel == option ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(selectedExpLevel == option ? SS.primary : .gray.opacity(0.4))
                                        .font(.system(size: 18))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            if option != expLevelOptions.last {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Zahlung
    private var paymentSection: some View {
        FormSection(title: "Payment & Contract") {
            VStack(spacing: 0) {
                PickerRow(label: "Payment Frequency", options: payFreqOptions, selection: $selectedPayFreq)
                Divider().padding(.leading, 16)
                PickerRow(label: "Contract Type", options: contractTypeOptions, selection: $selectedContractType)
            }
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - Footer
    private var footerBar: some View {
        VStack(spacing: 0) {
            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            Divider()
            HStack(spacing: 10) {
                Button {
                    pendingStatus = "draft"
                    showConfirmSheet = true
                } label: {
                    Text(isEditing ? "Save Draft" : "Save as Draft")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(SS.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SS.primary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)

                Button {
                    pendingStatus = "published"
                    showConfirmSheet = true
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Post Job")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canPost ? SS.primary : Color.gray.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(!canPost || isSubmitting)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .background(Color(uiColor: .systemBackground))
        }
    }

    // MARK: - Draft laden (Bearbeiten-Modus)
    @MainActor
    private func loadDraftIfNeeded() async {
        guard let editingJobId, !isLoadingDraft, title.isEmpty else { return }
        isLoadingDraft = true
        draftLoadError = nil
        defer { isLoadingDraft = false }
        do {
            let job = try await APIClient.shared.fetchJobForEditing(id: editingJobId)
            title = job.title
            if !job.location.isEmpty && job.location != locationText { skipNextLocationReset = true }
            locationText = job.location
            locationLat = job.lat
            locationLng = job.lng
            selectedCategory = job.category ?? ""
            selectedTags = Set(job.tags)
            let loaded = job.shifts.compactMap { $0.toDraftShift() }
            shifts = loaded.isEmpty ? [DraftShift()] : loaded
            numberOfWorkers = max(1, job.openSpots)
            if let pay = job.payAmount, pay > 0 {
                hourlyRateText = pay.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(pay)) : String(pay)
            }
            jobDescription = job.jobDescription ?? ""
            tasks = job.tasks.isEmpty ? [""] : job.tasks
            selectedDressCode = job.dressCode ?? ""
            selectedLanguages = Set(job.languages)
            minAgeText = job.minAge.map(String.init) ?? ""
            selectedExpLevel = job.experienceLevel ?? ""
            selectedPayFreq = job.paymentMethod ?? ""
            selectedContractType = job.contractType ?? ""
        } catch {
            draftLoadError = error.localizedDescription
        }
    }

    // MARK: - Submit
    @MainActor
    private func submit() async {
        isSubmitting = true
        errorMessage = nil

        let rate = Double(hourlyRateText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let shiftRequests = shifts.map { $0.toRequest(payAmount: rate) }
        let filteredTasks = tasks.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        let request = PostJobRequest(
            title: title.trimmingCharacters(in: .whitespaces),
            company: companyName,
            location: locationText.trimmingCharacters(in: .whitespaces),
            lat: locationLat,
            lng: locationLng,
            category: selectedCategory,
            tags: Array(selectedTags),
            shifts: shiftRequests,
            openSpots: numberOfWorkers,
            payAmount: rate,
            payText: rate > 0 ? "€\(String(format: "%.0f", rate)) / hr" : "On request",
            jobDescription: jobDescription,
            tasks: filteredTasks,
            dressCode: selectedDressCode.isEmpty ? nil : selectedDressCode,
            languages: Array(selectedLanguages),
            experienceLevel: selectedExpLevel.isEmpty ? nil : selectedExpLevel,
            minAge: Int(minAgeText),
            paymentMethod: selectedPayFreq.isEmpty ? nil : selectedPayFreq,
            contractType: selectedContractType.isEmpty ? nil : selectedContractType,
            status: pendingStatus
        )

        do {
            if let editingJobId {
                try await APIClient.shared.updateJob(id: editingJobId, request: request)
            } else {
                try await APIClient.shared.postJob(request)
            }
            isSubmitting = false
            dismiss()
        } catch {
            isSubmitting = false
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - PostJobConfirmSheet
struct PostJobConfirmSheet: View {
    let jobTitle: String
    let company: String
    let shiftsCount: Int
    let isDraft: Bool
    let onSaveAsDraft: () -> Void
    let onPost: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            VStack(spacing: 16) {
                Image(systemName: isDraft ? "doc.badge.clock" : "megaphone.fill")
                    .font(.system(size: 36))
                    .foregroundColor(isDraft ? .orange : SS.primary)
                    .padding(16)
                    .background((isDraft ? Color.orange : SS.primary).opacity(0.1))
                    .clipShape(Circle())

                VStack(spacing: 6) {
                    Text(isDraft ? "Save as draft?" : "Post job?")
                        .font(.system(size: 20, weight: .bold))

                    Text(isDraft
                        ? "The job will be saved but not yet published."
                        : "Once published, workers can apply for \"\(jobTitle)\".")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                HStack(spacing: 6) {
                    Image(systemName: "briefcase")
                        .font(.system(size: 12))
                    Text(jobTitle.isEmpty ? "No title" : jobTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Text("·")
                    Text("\(shiftsCount) shift\(shiftsCount == 1 ? "" : "s")")
                        .font(.system(size: 13))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(Capsule())
            }
            .padding(.bottom, 24)

            Divider()

            VStack(spacing: 10) {
                Button(isDraft ? "Save as Draft" : "Publish Now") {
                    isDraft ? onSaveAsDraft() : onPost()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(isDraft ? Color.orange : SS.primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                if !isDraft {
                    Button("Save as Draft") { onSaveAsDraft() }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }

                Button("Cancel") { onCancel() }
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - ShiftRow
private struct ShiftRow: View {
    @Binding var shift: DraftShift
    let onRemove: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(SS.primary)
                    .font(.system(size: 14))
                Text("Date")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Spacer()
                DatePicker("", selection: $shift.date, displayedComponents: .date)
                    .labelsHidden()
                    .tint(SS.primary)

                if let remove = onRemove {
                    Button(action: remove) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red.opacity(0.7))
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().padding(.leading, 14)

            HStack {
                Image(systemName: "clock")
                    .foregroundColor(SS.primary)
                    .font(.system(size: 14))
                Text("Start")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Spacer()
                DatePicker("", selection: $shift.startTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .tint(SS.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().padding(.leading, 14)

            HStack {
                Image(systemName: "clock.badge.checkmark")
                    .foregroundColor(SS.primary)
                    .font(.system(size: 14))
                Text("End")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Spacer()
                DatePicker("", selection: $shift.endTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .tint(SS.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().padding(.leading, 14)

            HStack {
                Image(systemName: "hourglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
                Text("Duration")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Spacer()
                Text(shift.durationText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(SS.primary)
                    .padding(.horizontal, 14)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - FlowChips (Multi-Select Tags)
private struct FlowChips: View {
    let items: [String]
    @Binding var selected: Set<String>

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 100, maximum: 180), spacing: 8)],
            spacing: 8
        ) {
            ForEach(items, id: \.self) { item in
                let isOn = selected.contains(item)
                Button { toggle(item) } label: {
                    Text(item)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isOn ? .white : SS.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(isOn ? SS.primary : SS.primary.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.2), value: isOn)
            }
        }
    }

    private func toggle(_ item: String) {
        if selected.contains(item) { selected.remove(item) }
        else { selected.insert(item) }
    }
}

// MARK: - FormSection
private struct FormSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
            content
                .padding(.horizontal, 16)
        }
        .padding(.top, 20)
    }
}

// MARK: - FormRow
private struct FormRow<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .padding(.leading, 16)
            Spacer()
            content
                .padding(.trailing, 16)
        }
        .padding(.vertical, 12)
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - PickerRow
private struct PickerRow: View {
    let label: String
    let options: [String]
    @Binding var selection: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .padding(.leading, 16)
            Spacer()
            Picker("", selection: $selection) {
                Text("Please select").tag("")
                ForEach(options, id: \.self) { opt in
                    Text(opt).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .tint(SS.primary)
            .padding(.trailing, 8)
        }
        .padding(.vertical, 6)
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - MultiPickerRow
private struct MultiPickerRow: View {
    let label: String
    let options: [String]
    @Binding var selected: Set<String>

    var displayText: String {
        selected.isEmpty ? "None selected" : selected.sorted().joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 90), spacing: 8)],
                spacing: 8
            ) {
                ForEach(options, id: \.self) { lang in
                    let on = selected.contains(lang)
                    Button {
                        if on { selected.remove(lang) } else { selected.insert(lang) }
                    } label: {
                        Text(lang)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(on ? .white : SS.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(on ? SS.primary : SS.primary.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.2), value: on)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - EditableJob (GET /jobs/:id → Bearbeiten-Modus)
struct EditableJob: Decodable {
    struct Shift: Decodable {
        let startTimeISO: String?
        let endTimeISO: String?

        func toDraftShift() -> DraftShift? {
            let iso = ISO8601DateFormatter()
            let isoFraction = ISO8601DateFormatter()
            isoFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            func parse(_ raw: String?) -> Date? {
                guard let raw else { return nil }
                return iso.date(from: raw) ?? isoFraction.date(from: raw)
            }
            guard let start = parse(startTimeISO), let end = parse(endTimeISO) else { return nil }
            return DraftShift(date: start, startTime: start, endTime: end)
        }
    }

    let title: String
    let location: String
    let lat: Double?
    let lng: Double?
    let category: String?
    let tags: [String]
    let shifts: [Shift]
    let openSpots: Int
    let payAmount: Double?
    let jobDescription: String?
    let tasks: [String]
    let dressCode: String?
    let languages: [String]
    let minAge: Int?
    let experienceLevel: String?
    let paymentMethod: String?
    let contractType: String?
}
