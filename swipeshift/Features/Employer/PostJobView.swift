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

    /// Schichtdauer in Stunden (0 bei ungueltiger Zeitspanne)
    var hours: Double { max(0, endTime.timeIntervalSince(startTime) / 3600) }

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
        let total = "\(Money.format(hours * payAmount)) total"

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
    @ObservedObject private var feeConfig = FeeConfig.shared
    /// Eingefrorener Satz eines geladenen Jobs; nil bei neuen Jobs/Entwuerfen (dann aktueller Satz)
    @State private var frozenFeePercent: Double? = nil
    private var effectiveFeePercent: Double { frozenFeePercent ?? feeConfig.platformFeePercent }

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

    // Optionale Zusatzfelder
    @State private var requiredSkills: Set<String> = []
    @State private var physicalRequirements: Set<String> = []
    @State private var certifications: Set<String> = []
    @State private var educationLevel = ""
    @State private var workAuthorizationRequired = false
    @State private var isUrgent = false
    @State private var multipleLocations = false
    @State private var breakIncluded = false
    @State private var breakMinutes = 30
    @State private var sameDayPay = false
    @State private var tipsIncluded = false
    @State private var repeatWork = false
    @State private var bonusAvailable = false
    @State private var bonusDescription = ""
    @State private var cancellationPolicy = ""      // JobCancellationPolicy.rawValue oder ""
    @State private var cancellationNotes = ""
    @State private var jobNotes = ""
    @State private var instantMatch = false

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
        !locationText.trimmingCharacters(in: .whitespaces).isEmpty &&
        !shifts.isEmpty &&
        (Double(hourlyRateText.replacingOccurrences(of: ",", with: ".")) ?? 0) > 0   // Backend verlangt Lohn > 0 zum Veroeffentlichen
    }

    // MARK: - Fortschritt (Schritte = Abschnittsgruppen, Stand aus den ausgefuellten Pflichtfeldern)

    private static let stepTitles = ["Basics", "Shifts", "Pay", "Details", "Review"]

    private var basicsDone: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !locationText.trimmingCharacters(in: .whitespaces).isEmpty &&
        !selectedCategory.isEmpty
    }
    private var shiftsDone: Bool { !shifts.isEmpty && shifts.contains { $0.hours > 0 } }
    private var payDone: Bool { parsedRate > 0 }
    private var detailsDone: Bool { !jobDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Erster noch nicht erledigter Schritt; alle erledigt → "Review"
    private var currentStep: Int {
        if !basicsDone { return 0 }
        if !shiftsDone { return 1 }
        if !payDone { return 2 }
        if !detailsDone { return 3 }
        return 4
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar

            DSProgressSteps(steps: Self.stepTitles, current: currentStep)
                .padding(.horizontal, DS.Spacing.screenEdge)
                .padding(.bottom, DS.Spacing.sm)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    basicInfoSection
                    categorySection
                    tagsSection
                    shiftsSection
                    workersAndPaySection
                    costSummarySection
                    descriptionSection
                    tasksSection
                    requirementsSection
                    paymentSection
                    applicationsSection
                    cancellationSection
                }
                .padding(.horizontal, DS.Spacing.screenEdge)
                .padding(.top, DS.Spacing.xs)
                .padding(.bottom, DS.Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)

            footerBar
        }
        .dsBackground()
        .navigationBarHidden(true)
        .overlay {
            // Laden fehlgeschlagen: kein (leeres) Formular, sonst koennte der Draft mit Defaults ueberschrieben werden
            if let draftLoadError {
                VStack(spacing: DS.Spacing.sm) {
                    DSEmptyState(
                        systemIcon: "exclamationmark.triangle",
                        title: "Couldn't load this draft",
                        message: draftLoadError,
                        actionTitle: "Retry",
                        action: { Task { await loadDraftIfNeeded() } }
                    )
                    Button("Close") { dismiss() }
                        .buttonStyle(.ds(.secondary, size: .medium, fullWidth: false))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.Color.bg.ignoresSafeArea())
            } else if isLoadingDraft {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    DSSkeletonBlock(width: 120, height: 14)
                    DSSkeletonBlock(height: 50, radius: DS.Radius.control)
                    DSSkeletonBlock(height: 50, radius: DS.Radius.control)
                    DSSkeletonBlock(height: 50, radius: DS.Radius.control)
                    DSSkeletonBlock(width: 160, height: 14)
                    DSSkeletonBlock(height: 120, radius: DS.Radius.control)
                    Spacer()
                }
                .padding(DS.Spacing.screenEdge)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.Color.bg.ignoresSafeArea())
            }
        }
        .task {
            await feeConfig.refresh()
            await loadDraftIfNeeded()
        }
        .sheet(isPresented: $showConfirmSheet) {
            PostJobConfirmSheet(
                jobTitle: title,
                company: companyName,
                shiftsCount: shifts.count,
                shiftHours: shifts.map(\.hours),
                hourlyRate: parsedRate,
                workers: numberOfWorkers,
                feePercent: effectiveFeePercent,
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
        HStack(spacing: DS.Spacing.sm) {
            DSIconButton(systemName: "xmark", label: "Close") { dismiss() }

            Spacer(minLength: 0)

            Text(isEditing ? "Edit draft" : "Post a job")
                .dsFont(.headline)
                .foregroundStyle(DS.Color.text)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, DS.Spacing.screenEdge)
        .padding(.vertical, DS.Spacing.xs)
    }

    // MARK: - Grundinfos
    private var basicInfoSection: some View {
        DSSection("Basic info", ruled: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                DSTextField("Job title", placeholder: "e.g. Event staff", text: $title)

                DSRow("Company", value: companyName, showsDivider: false)

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    DSTextField("Location", placeholder: "City or address", text: $locationText)
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
                                    DS.Haptics.selection()
                                    locationText = s.fullText
                                    locationLat  = s.lat
                                    locationLng  = s.lng
                                    showLocationSuggestions = false
                                    locationGeocoder.updateQuery("")
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.title)
                                            .dsFont(.body)
                                            .foregroundStyle(DS.Color.text)
                                        if !s.subtitle.isEmpty {
                                            Text(s.subtitle)
                                                .dsFont(.caption)
                                                .foregroundStyle(DS.Color.muted)
                                        }
                                    }
                                    .padding(.vertical, DS.Spacing.xs)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                DSDivider()
                            }
                        }
                    }
                }
            }
            .padding(.top, DS.Spacing.xxs)
        }
    }

    // MARK: - Kategorie
    private var categorySection: some View {
        DSSection("Category", ruled: false) {
            DSFlowLayout(spacing: DS.Spacing.xs) {
                ForEach(JobCategory.all, id: \.name) { cat in
                    DSChip(cat.name, isSelected: selectedCategory == cat.name) {
                        selectedCategory = cat.name
                    }
                }
            }
            .padding(.top, DS.Spacing.xxs)
        }
    }

    // MARK: - Tags
    private var tagsSection: some View {
        DSSection("Job tags", ruled: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                ForEach(tagGroups, id: \.label) { group in
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        Text(group.label)
                            .dsFont(.caption)
                            .foregroundStyle(DS.Color.text2)

                        FlowChips(items: group.tags, selected: $selectedTags)
                    }
                }
            }
            .padding(.top, DS.Spacing.xxs)
        }
    }

    // MARK: - Schichten
    private var shiftsSection: some View {
        DSSection("Shifts", trailing: "Duration is calculated", ruled: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                ForEach(Array($shifts.enumerated()), id: \.element.id) { index, $shift in
                    ShiftRow(index: index, shift: $shift, onRemove: shifts.count > 1 ? {
                        shifts.removeAll { $0.id == shift.id }
                    } : nil)
                }

                Button {
                    DS.Haptics.light()
                    shifts.append(DraftShift())
                } label: {
                    Label("Add shift", systemImage: "plus")
                }
                .buttonStyle(.ds(.soft, size: .medium))

                shiftOptions
            }
        }
    }

    // Dringlichkeit, Standorttyp, Pause (alles optional)
    private var shiftOptions: some View {
        VStack(spacing: 0) {
            DSToggleRow("Urgent (needs workers fast)", isOn: $isUrgent)
            DSToggleRow("Work at multiple locations", isOn: $multipleLocations)
            DSToggleRow("Break included", isOn: $breakIncluded)
            if breakIncluded {
                DSRow("Break length") {
                    Picker("Break length", selection: $breakMinutes) {
                        ForEach(JobOptions.breakMinutes, id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(DS.Color.primaryText)
                }
            }
        }
        .overlay(alignment: .bottom) { DSDivider() }
    }

    // MARK: - Mitarbeiter & Lohn
    private var workersAndPaySection: some View {
        DSSection("Workers & pay", ruled: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                DSRow("Number of workers", showsDivider: false) {
                    DSStepper(value: $numberOfWorkers, range: 1...50, accessibilityName: "Number of workers")
                }
                DSTextField("Hourly rate ($)", placeholder: "e.g. 15.00", text: $hourlyRateText)
                    .keyboardType(.decimalPad)
            }
        }
    }

    private var parsedRate: Double {
        Double(hourlyRateText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    // MARK: - Kostenuebersicht (Plattform-Gebuehr obendrauf, Worker erhaelt den vollen Lohn)
    @ViewBuilder
    private var costSummarySection: some View {
        if parsedRate > 0, shifts.contains(where: { $0.hours > 0 }) {
            DSSection("Cost summary", ruled: false) {
                FeeSummaryView(shiftHours: shifts.map(\.hours), hourlyRate: parsedRate,
                               workers: numberOfWorkers, percent: effectiveFeePercent)
                    .padding(.top, DS.Spacing.xxs)
            }
        }
    }

    // MARK: - Stellenbeschreibung
    private var descriptionSection: some View {
        DSSection("Job description", ruled: false) {
            DSTextEditor("Description", placeholder: "Describe the job, workflow, and work environment…",
                         text: $jobDescription, minLines: 4, maxLines: 10)
                .padding(.top, DS.Spacing.xxs)
        }
    }

    // MARK: - Aufgaben
    private var tasksSection: some View {
        DSSection("Tasks", ruled: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                ForEach(tasks.indices, id: \.self) { i in
                    HStack(alignment: .bottom, spacing: DS.Spacing.xs) {
                        DSTextField("Task \(i + 1)", placeholder: "Describe task", text: $tasks[i])

                        if tasks.count > 1 {
                            Button {
                                DS.Haptics.light()
                                tasks.remove(at: i)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(DS.Color.danger)
                                    .frame(width: 44, height: 50)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.dsPressable)
                            .accessibilityLabel("Remove task \(i + 1)")
                        }
                    }
                }

                Button {
                    DS.Haptics.light()
                    tasks.append("")
                } label: {
                    Label("Add task", systemImage: "plus")
                }
                .buttonStyle(.ds(.soft, size: .medium, fullWidth: false))
            }
            .padding(.top, DS.Spacing.xxs)
        }
    }

    // MARK: - Anforderungen
    private var requirementsSection: some View {
        DSSection("Requirements") {
            PickerRow(label: "Dress code", options: dressCodeOptions, selection: $selectedDressCode)
            MultiPickerRow(label: "Languages", options: languageOptions, selected: $selectedLanguages)

            DSRow("Min. age") {
                TextField("Min. age", text: $minAgeText, prompt: Text("e.g. 18").foregroundStyle(DS.Color.muted))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(DS.Font.make(15, .semibold))
                    .foregroundStyle(DS.Color.text)
                    .tint(DS.Color.primary)
                    .frame(maxWidth: 140)
            }

            // Optionale Anforderungen
            MultiPickerRow(label: "Required skills", options: JobOptions.skills, selected: $requiredSkills)
            MultiPickerRow(label: "Physical requirements", options: JobOptions.physical, selected: $physicalRequirements)
            MultiPickerRow(label: "Certifications", options: JobOptions.certifications, selected: $certifications)
            PickerRow(label: "Education", options: JobOptions.education, selection: $educationLevel)
            DSToggleRow("Work authorization required", isOn: $workAuthorizationRequired)

            // Experience Level (Radio Buttons)
            VStack(alignment: .leading, spacing: 0) {
                Text("Experience level")
                    .dsFont(.callout)
                    .foregroundStyle(DS.Color.text2)
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.xxs)
                ForEach(expLevelOptions, id: \.self) { option in
                    let isOn = selectedExpLevel == option
                    DSRow(option, showsDivider: option != expLevelOptions.first, action: {
                        DS.Haptics.selection()
                        selectedExpLevel = option
                    }) {
                        Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(isOn ? DS.Color.primary : DS.Color.border)
                            .accessibilityHidden(true)
                    }
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .overlay(alignment: .top) { DSDivider() }
        }
    }

    // MARK: - Zahlung
    private var paymentSection: some View {
        DSSection("Payment & contract") {
            PickerRow(label: "Payment frequency", options: payFreqOptions, selection: $selectedPayFreq)
            PickerRow(label: "Contract type", options: contractTypeOptions, selection: $selectedContractType)
            DSToggleRow("Same-day pay", isOn: $sameDayPay)
            DSToggleRow("Tips included", isOn: $tipsIncluded)
            DSToggleRow("Bonus available", isOn: $bonusAvailable)
            if bonusAvailable {
                DSTextEditor("Bonus", placeholder: "Describe the bonus (optional)", text: $bonusDescription,
                             minLines: 1, maxLines: 3, maxLength: 200)
                    .padding(.vertical, DS.Spacing.xs)
            }
            DSToggleRow("Repeat work possible", isOn: $repeatWork)
        }
    }

    // MARK: - Instant Match
    private var applicationsSection: some View {
        DSSection("Applications") {
            DSToggleRow("Instant match", subtitle: "Qualified applicants are accepted automatically until all spots are filled.", showsDivider: false, isOn: $instantMatch)
        }
    }

    // MARK: - Cancellation & Notes
    private var cancellationSection: some View {
        DSSection("Cancellation & notes", ruled: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                DSRow("Cancellation policy", showsDivider: false) {
                    Picker("Cancellation policy", selection: $cancellationPolicy) {
                        Text("Please select").tag("")
                        ForEach(JobCancellationPolicy.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.menu)
                    .tint(DS.Color.primaryText)
                }
                DSTextEditor("Cancellation notes", placeholder: "Cancellation notes (optional)", text: $cancellationNotes,
                             minLines: 2, maxLines: 5, maxLength: 300)
                DSTextEditor("Notes for workers", placeholder: "e.g. meeting point or parking (optional)", text: $jobNotes,
                             minLines: 2, maxLines: 6, maxLength: 500)
            }
        }
    }

    // MARK: - Footer
    private var footerBar: some View {
        VStack(spacing: DS.Spacing.xs) {
            if let err = errorMessage {
                Text(err)
                    .dsFont(.caption)
                    .foregroundStyle(DS.Color.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: DS.Spacing.sm) {
                Button {
                    pendingStatus = "draft"
                    showConfirmSheet = true
                } label: {
                    Text("Save draft")
                }
                .buttonStyle(.ds(.secondary))
                .disabled(isSubmitting)

                Button {
                    pendingStatus = "published"
                    showConfirmSheet = true
                } label: {
                    if isSubmitting {
                        ProgressView().tint(DS.Color.onPrimary)
                    } else {
                        Text("Post job")
                    }
                }
                .buttonStyle(.ds(.primary))
                .disabled(!canPost || isSubmitting)
            }
        }
        .padding(.horizontal, DS.Spacing.screenEdge)
        .padding(.top, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.sm)
        .background(DS.Color.surface)
        .overlay(alignment: .top) { DSDivider() }
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
            frozenFeePercent = job.platformFeePercent
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
            requiredSkills = Set(job.requiredSkills ?? [])
            physicalRequirements = Set(job.physicalRequirements ?? [])
            certifications = Set(job.certifications ?? [])
            educationLevel = job.educationLevel ?? ""
            workAuthorizationRequired = job.workAuthorizationRequired ?? false
            isUrgent = job.urgency == "urgent"
            multipleLocations = job.locationType == "multiple"
            breakIncluded = job.breakIncluded ?? false
            breakMinutes = job.breakMinutes ?? 30
            sameDayPay = job.sameDayPay ?? false
            tipsIncluded = job.tipsIncluded ?? false
            repeatWork = job.repeatWork ?? false
            bonusAvailable = job.bonusAvailable ?? false
            bonusDescription = job.bonusDescription ?? ""
            cancellationPolicy = job.cancellationPolicy ?? ""
            cancellationNotes = job.cancellationNotes ?? ""
            jobNotes = job.jobNotes ?? ""
            instantMatch = job.instantMatch ?? false
        } catch {
            draftLoadError = error.localizedDescription
        }
    }

    private func trimmedOrNil(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
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
            payText: rate > 0 ? "\(Money.format(rate)) / hr" : "On request",
            jobDescription: jobDescription,
            tasks: filteredTasks,
            dressCode: selectedDressCode.isEmpty ? nil : selectedDressCode,
            languages: Array(selectedLanguages),
            experienceLevel: selectedExpLevel.isEmpty ? nil : selectedExpLevel,
            minAge: Int(minAgeText),
            paymentMethod: selectedPayFreq.isEmpty ? nil : selectedPayFreq,
            contractType: selectedContractType.isEmpty ? nil : selectedContractType,
            status: pendingStatus,
            requiredSkills: Array(requiredSkills),
            physicalRequirements: Array(physicalRequirements),
            certifications: Array(certifications),
            educationLevel: educationLevel.isEmpty ? nil : educationLevel,
            workAuthorizationRequired: workAuthorizationRequired,
            urgency: isUrgent ? "urgent" : "normal",
            locationType: multipleLocations ? "multiple" : "single",
            breakIncluded: breakIncluded,
            breakMinutes: breakIncluded ? breakMinutes : nil,
            sameDayPay: sameDayPay,
            tipsIncluded: tipsIncluded,
            repeatWork: repeatWork,
            bonusAvailable: bonusAvailable,
            bonusDescription: bonusAvailable ? trimmedOrNil(bonusDescription) : nil,
            cancellationPolicy: cancellationPolicy.isEmpty ? nil : cancellationPolicy,
            cancellationNotes: trimmedOrNil(cancellationNotes),
            jobNotes: trimmedOrNil(jobNotes),
            instantMatch: instantMatch,
            termsAccepted: pendingStatus == "published"   // Checkbox im Confirm-Sheet ist Pflicht fuer "Post Job"
        )

        do {
            if let editingJobId {
                try await APIClient.shared.updateJob(id: editingJobId, request: request)
            } else {
                try await APIClient.shared.postJob(request)
            }
            isSubmitting = false
            DS.Haptics.success()
            dismiss()
        } catch {
            isSubmitting = false
            DS.Haptics.warning()
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - PostJobConfirmSheet
struct PostJobConfirmSheet: View {
    let jobTitle: String
    let company: String
    let shiftsCount: Int
    var shiftHours: [Double] = []
    var hourlyRate: Double = 0
    var workers: Int = 1
    var feePercent: Double = PlatformFees.defaultPlatformPercent
    let isDraft: Bool
    let onSaveAsDraft: () -> Void
    let onPost: () -> Void
    let onCancel: () -> Void

    // Pflicht-Zustimmung beim Veroeffentlichen (Drafts brauchen sie nicht)
    @State private var termsAccepted = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.md) {
                VStack(spacing: DS.Spacing.xs) {
                    Image(systemName: isDraft ? "doc.badge.clock" : "megaphone.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(isDraft ? DS.Tone.warning.foreground : DS.Tone.primary.foreground)
                        .frame(width: 64, height: 64)
                        .background(isDraft ? DS.Tone.warning.soft : DS.Tone.primary.soft, in: Circle())
                        .accessibilityHidden(true)

                    Text(isDraft ? "Save as draft?" : "Post job?")
                        .dsFont(.title)
                        .foregroundStyle(DS.Color.text)

                    Text(isDraft
                        ? "The job will be saved but not yet published."
                        : "Once published, workers can apply for \"\(jobTitle)\".")
                        .dsFont(.body)
                        .foregroundStyle(DS.Color.text2)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 6) {
                    Image(systemName: "briefcase")
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(jobTitle.isEmpty ? "No title" : jobTitle)
                        .font(DS.Font.make(13, .semibold, relativeTo: .footnote))
                        .lineLimit(1)
                    Text("·")
                    Text("\(shiftsCount) shift\(shiftsCount == 1 ? "" : "s")")
                        .dsFont(.caption)
                }
                .foregroundStyle(DS.Color.text2)
                .padding(.horizontal, DS.Spacing.inset)
                .padding(.vertical, DS.Spacing.xs)
                .background(DS.Color.surface2, in: Capsule())

                if !isDraft && hourlyRate > 0 && shiftHours.contains(where: { $0 > 0 }) {
                    FeeSummaryView(shiftHours: shiftHours, hourlyRate: hourlyRate, workers: workers, percent: feePercent)
                }

                if !isDraft {
                    TermsConsentRow(isAccepted: $termsAccepted)
                }

                VStack(spacing: DS.Spacing.xs) {
                    let publishBlocked = !isDraft && !termsAccepted
                    Button(isDraft ? "Save as draft" : "Publish now") {
                        isDraft ? onSaveAsDraft() : onPost()
                    }
                    .buttonStyle(.ds(.primary))
                    .disabled(publishBlocked)

                    if !isDraft {
                        Button("Save as draft") { onSaveAsDraft() }
                            .buttonStyle(.ds(.soft))
                    }

                    Button("Cancel") { onCancel() }
                        .buttonStyle(.ds(.secondary))
                }
            }
            .padding(.horizontal, DS.Spacing.screenEdge)
            .padding(.top, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.lg)
        }
        .dsBackground()
        .presentationDetents(isDraft ? [.medium, .large] : [.fraction(0.8), .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - FeeSummaryView (Kostenaufstellung fuer den Employer)
/// Pro Worker und Schicht: Lohn (Stunden × Stundenlohn), Plattform-Gebuehr, Gesamt; dazu Summe fuer alle Worker/Schichten.
/// Die Gebuehr wird nach der Schicht obendrauf berechnet; der Worker erhaelt den vollen Lohn.
struct FeeSummaryView: View {
    let shiftHours: [Double]
    let hourlyRate: Double
    let workers: Int
    let percent: Double

    private var activeHours: [Double] { shiftHours.filter { $0 > 0 } }

    private func hoursText(_ h: Double) -> String {
        h.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(h))h" : String(format: "%.1fh", h)
    }

    /// Summe ueber alle Schichten fuer `count` Worker
    private func total(workers count: Int) -> PlatformFees.Breakdown {
        let parts = activeHours.map { PlatformFees.breakdown(hours: $0, hourlyRate: hourlyRate, workers: count, percent: percent) }
        return PlatformFees.Breakdown(wages: PlatformFees.roundMoney(parts.reduce(0) { $0 + $1.wages }),
                                      fees:  PlatformFees.roundMoney(parts.reduce(0) { $0 + $1.fees }))
    }

    var body: some View {
        let perWorker = total(workers: 1)
        let all = total(workers: workers)
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            heading("Per worker, per shift")
            ForEach(Array(activeHours.enumerated()), id: \.offset) { i, h in
                let b = PlatformFees.breakdown(hours: h, hourlyRate: hourlyRate, workers: 1, percent: percent)
                if activeHours.count > 1 {
                    Text("Shift \(i + 1)")
                        .font(DS.Font.make(12, .semibold, relativeTo: .caption))
                        .foregroundStyle(DS.Color.text)
                }
                row("Wage (\(hoursText(h)) × \(Money.format(hourlyRate, fractionDigits: 2)))", b.wages)
                row("Platform fee (\(PlatformFees.percentLabel(percent)))", b.fees)
                row("Total per worker", b.total, bold: true)
            }
            DSDivider().padding(.vertical, DS.Spacing.xxs)
            heading("All \(workers) worker\(workers == 1 ? "" : "s") × \(activeHours.count) shift\(activeHours.count == 1 ? "" : "s")")
            row("Wages", all.wages)
            row("Platform fee (\(PlatformFees.percentLabel(percent)))", all.fees)
            row("You pay in total", all.total, bold: true)
            row("Worker receives (each, full wage)", perWorker.wages, accent: true)
            Text("The platform fee is added on top and billed after the shift. No-shows are not billed.")
                .dsFont(.caption)
                .foregroundStyle(DS.Color.muted)
        }
        .padding(DS.Spacing.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.surface2, in: RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(DS.Font.make(12, .bold, relativeTo: .caption))
            .foregroundStyle(DS.Color.text2)
    }

    private func row(_ label: String, _ amount: Double, bold: Bool = false, accent: Bool = false) -> some View {
        HStack {
            Text(label).font(DS.Font.make(14, bold ? .bold : .medium, relativeTo: .callout))
            Spacer(minLength: DS.Spacing.xs)
            Text(Money.format(amount, fractionDigits: 2))
                .font(DS.Font.make(14, bold ? .extrabold : .semibold, relativeTo: .callout))
        }
        .foregroundStyle(accent ? DS.Color.success : DS.Color.text)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - TermsConsentRow (Pflicht-Checkbox beim Veroeffentlichen, auch in AllPostedJobsView)
struct TermsConsentRow: View {
    @Binding var isAccepted: Bool

    var body: some View {
        DSCard(action: {
            DS.Haptics.selection()
            isAccepted.toggle()
        }) {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                Image(systemName: isAccepted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(isAccepted ? DS.Color.primary : DS.Color.muted)
                    .accessibilityHidden(true)
                Text("I agree to the SwipeShift Terms for Employers and confirm this job information is accurate.")
                    .dsFont(.callout)
                    .foregroundStyle(DS.Color.text)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityAddTraits(isAccepted ? .isSelected : [])
    }
}

// MARK: - ShiftRow (flach: Datum / Start / Ende / Dauer)
private struct ShiftRow: View {
    let index: Int
    @Binding var shift: DraftShift
    let onRemove: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Shift \(index + 1)")
                    .font(DS.Font.make(13, .bold, relativeTo: .footnote))
                    .foregroundStyle(DS.Color.text2)
                Spacer()
                if let remove = onRemove {
                    Button {
                        DS.Haptics.light()
                        remove()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(DS.Color.danger)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.dsPressable)
                    .accessibilityLabel("Remove shift \(index + 1)")
                }
            }
            .frame(minHeight: 44)

            DSRow("Date", systemIcon: "calendar") {
                DatePicker("Date", selection: $shift.date, displayedComponents: .date)
                    .labelsHidden()
                    .tint(DS.Color.primary)
            }
            DSRow("Start", systemIcon: "clock") {
                DatePicker("Start", selection: $shift.startTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .tint(DS.Color.primary)
            }
            DSRow("End", systemIcon: "clock.badge.checkmark") {
                DatePicker("End", selection: $shift.endTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .tint(DS.Color.primary)
            }
            DSRow("Duration", value: shift.durationText, accentValue: true, systemIcon: "hourglass", iconTone: .neutral)
        }
        .overlay(alignment: .bottom) { DSDivider() }
    }
}

// MARK: - FlowChips (Multi-Select Tags)
private struct FlowChips: View {
    let items: [String]
    @Binding var selected: Set<String>

    var body: some View {
        DSFlowLayout(spacing: DS.Spacing.xs) {
            ForEach(items, id: \.self) { item in
                DSChip(item, isSelected: selected.contains(item)) { toggle(item) }
            }
        }
    }

    private func toggle(_ item: String) {
        if selected.contains(item) { selected.remove(item) }
        else { selected.insert(item) }
    }
}

// MARK: - PickerRow (Menue-Auswahl, flache Zeile)
private struct PickerRow: View {
    let label: String
    let options: [String]
    @Binding var selection: String

    var body: some View {
        DSRow(label) {
            Picker(label, selection: $selection) {
                Text("Please select").tag("")
                ForEach(options, id: \.self) { opt in
                    Text(opt).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .tint(DS.Color.primaryText)
        }
    }
}

// MARK: - MultiPickerRow (Chips)
private struct MultiPickerRow: View {
    let label: String
    let options: [String]
    @Binding var selected: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(label)
                .dsFont(.callout)
                .foregroundStyle(DS.Color.text2)

            DSFlowLayout(spacing: DS.Spacing.xs) {
                ForEach(options, id: \.self) { option in
                    DSChip(option, isSelected: selected.contains(option)) {
                        if selected.contains(option) { selected.remove(option) } else { selected.insert(option) }
                    }
                }
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { DSDivider() }
    }
}

// MARK: - EditableJob (GET /jobs/:id → Bearbeiten-Modus)
struct EditableJob: Decodable {
    /// Eingefrorener Gebuehren-Satz (nur fuer veroeffentlichte Jobs; Entwuerfe: nil → aktueller Satz)
    var platformFeePercent: Double? = nil
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
    // Optionale Zusatzfelder (fehlende Keys → nil)
    let requiredSkills: [String]?
    let physicalRequirements: [String]?
    let certifications: [String]?
    let educationLevel: String?
    let workAuthorizationRequired: Bool?
    let urgency: String?
    let locationType: String?
    let breakIncluded: Bool?
    let breakMinutes: Int?
    let sameDayPay: Bool?
    let tipsIncluded: Bool?
    let repeatWork: Bool?
    let bonusAvailable: Bool?
    let bonusDescription: String?
    let cancellationPolicy: String?
    let cancellationNotes: String?
    let jobNotes: String?
    let instantMatch: Bool?
}
