//
//  RegisterView.swift
//  L1 Demo
//

import SwiftUI

enum RegistrationRole {
    case worker
    case employer
}

enum CompanySize: String, CaseIterable, Identifiable {
    case none
    case size1to10
    case size11to50
    case size50plus

    var id: String { rawValue }

    // ✅ Was der User in der UI sieht
    var label: String {
        switch self {
        case .none: return "none"
        case .size1to10: return "1–10"     // UI darf en-dash
        case .size11to50: return "11–50"
        case .size50plus: return "50+"
        }
    }

    // ✅ Was ans Backend geht (muss GENAU zu Zod passen)
    var apiValue: String? {
        switch self {
        case .none: return nil
        case .size1to10: return "1-10"
        case .size11to50: return "11-50"
        case .size50plus: return "50+"
        }
    }
}

struct DayAvailability {
    let name: String
    var available: Bool = false
}

enum FieldKey {
    //Worker
    case firstName
    case lastName
    case email
    case dateOfBirth
    case password
    case jobInterests
    case availability
    case confirmPassword
    case locationText
    case terms
    
    // Employer
    case companyName
    case employerEmail
    case employerPassword
    case employerConfirmPassword
    case employerLocation
    case employerIndustry
    case companySize
    case employerTerms
}


struct RegisterView: View {
    // MARK: - Variablen
    // Zugriff auf das Fake-Backend
    @EnvironmentObject var userStore: UserStore
    
    @StateObject private var locationGeocoder = LocationGeocoder()

    // Rolle (Worker vs. Employer)
    @State private var selectedRole: RegistrationRole = .worker
    
    @State private var lat: Double? = nil
    @State private var lng: Double? = nil
    
    // Employer-Felder
    @State private var companyName: String = ""
    @State private var employerEmail: String = ""
    @State private var employerPassword: String = ""
    @State private var employerConfirmPassword: String = ""
    @State private var employerLocationText: String = ""
    @State private var companySize: CompanySize = .size1to10
    @State private var companyLogoImage: UIImage? = nil
    @State private var showCompanyLogoPicker = false
    @State private var websiteOrInstagram: String = ""
    @State private var companyDescription: String = ""
    private let companyDescriptionLimit = 300
    
    @State private var employerLat: Double? = nil
    @State private var employerLng: Double? = nil
    @State private var showEmployerLocationSuggestions: Bool = false
    @State private var employerLocationSearchTask: Task<Void, Never>? = nil

    // Employer Terms (separat, best practice)
    @State private var employerAcceptedTerms: Bool = false


    // Worker-Felder
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @State private var locationText: String = "" // City / ZIP
    @State private var workerLat: Double? = nil
    @State private var workerLng: Double? = nil
    @State private var showWorkerLocationSuggestions: Bool = false
    @State private var workerLocationSearchTask: Task<Void, Never>? = nil
    
    //Profile Photo
    @State private var showImagePicker = false
    @State private var profileUIImage: UIImage? = nil
    
    // Job Interests
    private let jobInterestOptions: [String] = [
        "Hospitality", "Events", "Retail", "Office", "Logistics", "Warehouse", "Customer Service"
    ]
    
    // Industry/Category: gleiche Optionen wie Worker-JobInterests
    @State private var employerIndustry: String = "Hospitality"

    @State private var selectedJobInterests: Set<String> = []

    // Availability (einfaches Modell mit Morning / Afternoon / Evening)
    @State private var availability: [DayAvailability] = [
        DayAvailability(name: "Mon"),
        DayAvailability(name: "Tue"),
        DayAvailability(name: "Wed"),
        DayAvailability(name: "Thu"),
        DayAvailability(name: "Fri"),
        DayAvailability(name: "Sat"),
        DayAvailability(name: "Sun")
    ]
    
    //Short Bio
    @State private var shortBio: String = ""
    private let bioLimit = 200
   
    @State private var acceptedTerms: Bool = false

    // Fehlermeldung bei Fehlern (z.B. Email existiert schon)
    @State private var errorMessage: String?
    

    // MARK: - Validierungen
    
    //Enthält Fehlertexte Pro Feld
    @State private var fieldErrors: [FieldKey: String] = [:]


    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                // MARK: - Header
                VStack(spacing: 8) {
                    Text("Create Account")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Choose how you want to use the app.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 24)

                // MARK: - Role Selection Cards
                roleSelectionSection

                // MARK: - Formular je nach Rolle
                switch selectedRole {
                case .worker:
                    workerFormSection
                case .employer:
                    employerFormSection
                }

                // Fehlermeldung vom Backend
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
               // @State private var isRegistering = false

                // MARK: - Registrieren Button
                Button(action: handleRegister) {
                    Text(selectedRole == .worker ? "Create Worker Account" : "Create Employer Account")
                        .frame(maxWidth: .infinity)
                        .padding()
                        //.background(isFormValid ? Color.blue : Color.gray.opacity(0.5))
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 24)
                //.disabled(!isFormValid)

                // Optional: Anzeige, wenn Registrierung gleichzeitig einloggt
                if let current = userStore.currentUser {
                    Text("Registered & logged in as \(current.email)")
                        .font(.footnote)
                        .foregroundColor(.green)
                        .padding(.top, 8)
                }

                Spacer(minLength: 40)
            }
        }
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Subviews

    private var roleSelectionSection: some View {
        HStack(spacing: 16) {
            // Worker Card
            VStack(alignment: .leading, spacing: 8) {
                Text("I'm looking for work")
                    .font(.headline)
                Text("Create a worker profile to find jobs that match you.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectedRole == .worker ? Color.blue.opacity(0.15) : Color.gray.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selectedRole == .worker ? Color.blue : Color.clear, lineWidth: 2)
            )
            .cornerRadius(16)
            .onTapGesture {
                selectedRole = .worker
            }

            // Employer Card
            VStack(alignment: .leading, spacing: 8) {
                Text("I'm hiring for jobs")
                    .font(.headline)
                Text("Post jobs and find talent. (Coming soon)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectedRole == .employer ? Color.blue.opacity(0.15) : Color.gray.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selectedRole == .employer ? Color.blue : Color.clear, lineWidth: 2)
            )
            .cornerRadius(16)
            .onTapGesture {
                selectedRole = .employer
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: Worker Form Section
    private var workerFormSection: some View {
        
        VStack(spacing: 24) {

            // MARK: - Basic Info
            VStack(alignment: .leading, spacing: 16) {
                
                    // Profile Photo (optional) – aligned like the other section headers
                   Text("Profile photo (optional)")
                       .font(.headline)

                   HStack(spacing: 12) {
                       // Preview Avatar
                       Group {
                           if let image = profileUIImage {
                               Image(uiImage: image)
                                   .resizable()
                                   .scaledToFill()
                           } else {
                               Image(systemName: "person.crop.circle.fill")
                                   .resizable()
                                   .scaledToFit()
                                   .foregroundColor(.secondary)
                                   .padding(10)
                           }
                       }
                       .frame(width: 56, height: 56)
                       .background(Color.gray.opacity(0.08))
                       .clipShape(Circle())

                       VStack(alignment: .leading, spacing: 4) {
                           Text(profileUIImage == nil ? "No photo selected" : "Photo selected")
                               .font(.subheadline)
                               .foregroundColor(.secondary)

                           Button {
                               showImagePicker = true
                           } label: {
                               Text(profileUIImage == nil ? "Choose photo" : "Change photo")
                                   .font(.subheadline)
                                   .fontWeight(.semibold)
                           }
                       }

                       Spacer()

                       if profileUIImage != nil {
                           Button(role: .destructive) {
                               profileUIImage = nil
                           } label: {
                               Image(systemName: "trash")
                           }
                       }
                   }
                   .padding()
                   .background(Color.gray.opacity(0.1))
                   .cornerRadius(12)
                   .sheet(isPresented: $showImagePicker) {
                       ImagePicker(image: $profileUIImage)
                   }

                
                Text("Basic information")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        TextField("First name", text: $firstName)
                            .textInputAutocapitalization(.words)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        
                        TextField("Last name", text: $lastName)
                            .textInputAutocapitalization(.words)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        
                        if let error = fieldErrors[.firstName] {
                            Text("First name: \(error)").font(.caption).foregroundColor(.red)
                        }
                        
                        if let error = fieldErrors[.lastName] {
                            Text("Last name: \(error)").font(.caption).foregroundColor(.red)
                        }
                    }
                }
                
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                
                if let error = fieldErrors[.email] {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                SecureField("Password", text: $password)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .textContentType(.oneTimeCode)
                
                
                if let msg = fieldErrors[.password] {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                SecureField("Confirm password", text: $confirmPassword)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .textContentType(.oneTimeCode)

                if let msg = fieldErrors[.confirmPassword] {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 24)

            // MARK: - Date of birth
            VStack(alignment: .leading, spacing: 8) {
                Text("Date of birth")
                    .font(.headline)

                DatePicker(
                    "",
                    selection: $dateOfBirth,
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                
                if let msg = fieldErrors[.dateOfBirth] {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 24)

            
            // MARK: - Location
            VStack(alignment: .leading, spacing: 8) {
                Text("Location")
                    .font(.headline)

                Text("Start typing a city or ZIP. Pick a suggestion so we can save coordinates.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("City / ZIP code", text: $locationText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .textContentType(.addressCity) // ✅ iOS Hint, aber nicht “echte” Autocomplete
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .onChange(of: locationText) { _, newValue in
                        
                        // Koordinaten resetten wenn User wieder tippt
                        workerLat = nil
                        workerLng = nil
                        showWorkerLocationSuggestions = true

                        workerLocationSearchTask?.cancel()
                        workerLocationSearchTask = Task {
                            try? await Task.sleep(nanoseconds: 350_000_000) // 350ms debounce
                            if Task.isCancelled { return }
                            await MainActor.run {
                                locationGeocoder.updateQuery(newValue)
                            }
                        }
                    }

                // Vorschläge
                if showWorkerLocationSuggestions && !locationGeocoder.suggestions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(locationGeocoder.suggestions) { s in
                            Button {
                                locationText = s.fullText
                                workerLat = s.lat
                                workerLng = s.lng
                                showWorkerLocationSuggestions = false
                                hideKeyboard()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.title)
                                        .foregroundColor(.primary)
                                    if !s.subtitle.isEmpty {
                                        Text(s.subtitle)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            Divider()
                        }
                    }
                    .background(Color.gray.opacity(0.06))
                    .cornerRadius(12)
                }

                // Debug / Feedback (optional)
                if let lat = workerLat, let lng = workerLng {
                    Text("Saved coordinates: \(lat), \(lng)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if let msg = fieldErrors[.locationText] {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 24)

            // MARK: - Job Interests (Toggle-Liste)
            VStack(alignment: .leading, spacing: 8) {
                Text("Job interests")
                    .font(.headline)

                Text("Select one or more categories.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Wir nutzen eine VStack-Liste statt Chips.
                // Jede Zeile ist ein Toggle, der in selectedJobInterests schreibt.
                VStack(spacing: 10) {
                    ForEach(jobInterestOptions, id: \.self) { option in
                        Toggle(isOn: Binding(
                            get: { selectedJobInterests.contains(option) },
                            set: { isOn in
                                if isOn {
                                    selectedJobInterests.insert(option)
                                } else {
                                    selectedJobInterests.remove(option)
                                }
                            }
                        )) {
                            Text(option)
                                .font(.subheadline)
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                        .padding()
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(12)
                        
                        if let error = fieldErrors[.jobInterests] {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)


            // MARK: - Availability
            VStack(alignment: .leading, spacing: 8) {
                Text("Availability")
                    .font(.headline)

                Text("Select the days when you are usually available.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(spacing: 12) {
                    ForEach(availability.indices, id: \.self) { index in
                        HStack {
                            Text(availability[index].name)
                                .frame(width: 36, alignment: .leading)

                            Spacer()

                            Toggle("", isOn: $availability[index].available)
                                .labelsHidden()
                        }
                        .font(.caption)
                    }
                }
                
                if let msg = fieldErrors[.availability] {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 24)
            
            // MARK: - Short Bio Text
            VStack(alignment: .leading, spacing: 8) {
                Text("Short bio (optional)")
                    .font(.headline)

                Text("Tell employers a bit about yourself.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextEditor(text: $shortBio)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .onChange(of: shortBio) { oldValue, newValue in
                        if newValue.count > bioLimit {
                            shortBio = String(newValue.prefix(bioLimit))
                        }
                    }

                HStack {
                    Spacer()
                    Text("\(shortBio.count)/\(bioLimit)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 24)


            // MARK: - Terms & Privacy
            Toggle(isOn: $acceptedTerms) {
                Text("I accept the Terms & Conditions and Privacy Policy.")
                    .font(.footnote)
            }
            .toggleStyle(SwitchToggleStyle(tint: .blue))
            .padding(.horizontal, 24)
            
            if let msg = fieldErrors[.terms] {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: EmployerFormSecion
    private var employerFormSection: some View {
        VStack(spacing: 24) {

            // MARK: - Company Info
            VStack(alignment: .leading, spacing: 16) {
                Text("Company information")
                    .font(.headline)

                TextField("Company name", text: $companyName)
                    .textInputAutocapitalization(.words)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                
                if let msg = fieldErrors[.companyName] {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                VStack(alignment: .leading, spacing: 8) {
                       Text("Contact person")
                           .font(.subheadline)
                           .fontWeight(.medium)

                       HStack(spacing: 12) {
                           TextField("First name", text: $firstName)
                               .textInputAutocapitalization(.words)
                               .padding()
                               .background(Color.gray.opacity(0.1))
                               .cornerRadius(12)
                           
                           if let msg = fieldErrors[.firstName] {
                               Text(msg)
                                   .font(.caption)
                                   .foregroundColor(.red)
                           }

                           TextField("Last name", text: $lastName)
                               .textInputAutocapitalization(.words)
                               .padding()
                               .background(Color.gray.opacity(0.1))
                               .cornerRadius(12)
                           
                           if let msg = fieldErrors[.lastName] {
                               Text(msg)
                                   .font(.caption)
                                   .foregroundColor(.red)
                           }
                       }
                   }
            }
            .padding(.horizontal, 24)

            // MARK: - Login Info
            VStack(alignment: .leading, spacing: 16) {
                Text("Account details")
                    .font(.headline)

                TextField("Work email", text: $employerEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                
                if let msg = fieldErrors[.employerEmail] {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                SecureField("Password", text: $employerPassword)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                
                if let msg = fieldErrors[.employerPassword] {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                SecureField("Confirm password", text: $employerConfirmPassword)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                
                if let msg = fieldErrors[.employerConfirmPassword] {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
            }
            .padding(.horizontal, 24)

            // MARK: - Location
            // MARK: - Location
            VStack(alignment: .leading, spacing: 8) {
                Text("Location")
                    .font(.headline)

                Text("Start typing a city or ZIP. Pick a suggestion so we can save coordinates.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("City / ZIP code", text: $employerLocationText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .textContentType(.addressCity)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .onChange(of: employerLocationText) { _, newValue in
                        employerLat = nil
                        employerLng = nil
                        showEmployerLocationSuggestions = true

                        employerLocationSearchTask?.cancel()
                        employerLocationSearchTask = Task {
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            if Task.isCancelled { return }
                            await MainActor.run {
                                locationGeocoder.updateQuery(newValue)
                            }
                        }
                    }

                if showEmployerLocationSuggestions && !locationGeocoder.suggestions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(locationGeocoder.suggestions) { s in
                            Button {
                                employerLocationText = s.fullText
                                employerLat = s.lat
                                employerLng = s.lng
                                showEmployerLocationSuggestions = false
                                hideKeyboard()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.title)
                                        .foregroundColor(.primary)
                                    if !s.subtitle.isEmpty {
                                        Text(s.subtitle)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            Divider()
                        }
                    }
                    .background(Color.gray.opacity(0.06))
                    .cornerRadius(12)
                }

                if let lat = employerLat, let lng = employerLng {
                    Text("Saved coordinates: \(lat), \(lng)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if let msg = fieldErrors[.employerLocation] {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 24)
            
            
            // MARK: - Industry / Category
            VStack(alignment: .leading, spacing: 8) {
                Text("Industry / Category")
                    .font(.headline)

                HStack {
                    Picker("Industry", selection: $employerIndustry) {
                        ForEach(jobInterestOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            
            if let msg = fieldErrors[.employerIndustry] {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            // MARK: - Company Size
            VStack(alignment: .leading, spacing: 8) {
                Text("Company size")
                    .font(.headline)

                Picker("Company size", selection: $companySize) {
                    ForEach(CompanySize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                
                if let msg = fieldErrors[.companySize] {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 24)

            VStack(spacing: 24) {

                // MARK: - Company Logo (optional)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Company logo (optional)")
                        .font(.headline)

                    HStack(spacing: 12) {
                        Group {
                            if let image = companyLogoImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: "building.2.crop.circle")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundColor(.secondary)
                                    .padding(10)
                            }
                        }
                        .frame(width: 56, height: 56)
                        .background(Color.gray.opacity(0.08))
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(companyLogoImage == nil ? "No logo selected" : "Logo selected")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Button {
                                showCompanyLogoPicker = true
                            } label: {
                                Text(companyLogoImage == nil ? "Choose logo" : "Change logo")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                        }

                        Spacer()

                        if companyLogoImage != nil {
                            Button(role: .destructive) {
                                companyLogoImage = nil
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 24)
                .sheet(isPresented: $showCompanyLogoPicker) {
                    ImagePicker(image: $companyLogoImage)
                }

                // MARK: - Website / Instagram (optional)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Website or Instagram (optional)")
                        .font(.headline)

                    TextField("https:// or @instagram", text: $websiteOrInstagram)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                }
                .padding(.horizontal, 24)

                // MARK: - Short Company Description (optional)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Short company description (optional)")
                        .font(.headline)

                    TextEditor(text: $companyDescription)
                        .frame(minHeight: 100)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                        .onChange(of: companyDescription) { _, newValue in
                            if newValue.count > companyDescriptionLimit {
                                companyDescription = String(newValue.prefix(companyDescriptionLimit))
                            }
                        }

                    HStack {
                        Spacer()
                        Text("\(companyDescription.count)/\(companyDescriptionLimit)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 24)

            }
            
            
            // MARK: - Terms & Privacy (Employer)
            Toggle(isOn: $employerAcceptedTerms) {
                Text("I accept the Terms & Conditions and Privacy Policy.")
                    .font(.footnote)
            }
            .toggleStyle(SwitchToggleStyle(tint: .blue))
            .padding(.horizontal, 24)
            
            if let msg = fieldErrors[.employerTerms] {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
            }

        }
    }


    // MARK: - Aktionen

    /*private func toggleJobInterest(_ option: String) {
        if selectedJobInterests.contains(option) {
            selectedJobInterests.remove(option)
        } else {
            selectedJobInterests.insert(option)
        }
    }*/
    
    private func isoDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    private func handleRegister() {
        
        
        errorMessage = nil

        switch selectedRole {
            
        case .worker:
            
            // 1) Client-side Validierung
            fieldErrors = FormValidator.validateWorker(
                firstName: firstName,
                lastName: lastName,
                email: email,
                dateOfBirth: dateOfBirth,
                password: password,
                confirmPassword: confirmPassword,
                locationText: locationText,
                jobInterests: selectedJobInterests,
                availability: availability,
                acceptedTerms: acceptedTerms
            )

            // 2) Wenn Fehler da sind: KEIN Request ans Backend
            guard fieldErrors.isEmpty else { return }
            
            guard let wLat = workerLat, let wLng = workerLng else {
                fieldErrors[.locationText] = "Please select a location from the suggestions."
                return
            }
            

            let body = RegisterRequestDTO(
                   firstName: firstName,
                   lastName: lastName,
                   email: email,
                   password: password,
                   role: "worker",
                   location: locationText,
                   lat: wLat,
                   lng: wLng,

                   dateOfBirth: isoDate(dateOfBirth),
                   jobInterests: Array(selectedJobInterests),
                   availability: availability.map { AvailabilityDTO(name: $0.name, available: $0.available) },
                   bio: shortBio.isEmpty ? nil : shortBio,
                   profilePhotoUrl: nil,

                   companyName: nil,
                   companySize: nil,
                   industry: nil,
                   companyLogoUrl: nil,
                   websiteOrInstagram: nil,
                   companyDescription: nil
               )
                Task {
                
                    await userStore.registerRemote(request: body, pickedImage: profileUIImage)
                    
                    
                    if let msg = userStore.errorMessage {
                        print("Register failed:", msg)
                    } else {
                        print("Register success (worker): \(userStore.currentUser?.email ?? "")")
                        print("Location:", locationText)
                        print("Availability:", availability)
                        print("Job interests:", selectedJobInterests)
                    }
                }

  

        case .employer:
            
            //Wenn die Validierung fehlschlägt → Funktion sofort beenden
            fieldErrors = FormValidator.validateEmployer(
                       companyName: companyName,
                       contactFirstName: firstName,
                       contactLastName: lastName,
                       email: employerEmail,
                       employerPassword: employerPassword,
                       confirmPassword: employerConfirmPassword,
                       location: employerLocationText,
                       industry: employerIndustry,
                       companySizeRaw: companySize,
                       acceptedTerms: employerAcceptedTerms
                   )

           guard fieldErrors.isEmpty else { return }
            
            guard let eLat = employerLat, let eLng = employerLng else {
                fieldErrors[.employerLocation] = "Please select a location from the suggestions."
                return
            }
            
            let body = RegisterRequestDTO(
                   firstName: firstName,
                   lastName: lastName,
                   email: employerEmail,
                   password: employerPassword,
                   role: "employer",
                   location: employerLocationText,
                   
                   lat: eLat,
                   lng: eLng,

                   dateOfBirth: nil,
                   jobInterests: nil,
                   availability: nil,
                   bio: nil,
                   profilePhotoUrl: nil,

                   companyName: companyName,
                   companySize: companySize.apiValue,
                   industry: employerIndustry,
                   companyLogoUrl: nil,
                   websiteOrInstagram: websiteOrInstagram.isEmpty ? nil : websiteOrInstagram,
                   companyDescription: companyDescription.isEmpty ? nil : companyDescription
               )

                Task {
                    await userStore.registerRemote(request: body, pickedImage: companyLogoImage)
                    
                    if let msg = userStore.errorMessage {
                        print("Register failed:", msg)
                    } else {
                        print("Register success (employer): \(userStore.currentUser?.email ?? "")")
                        print("Location:", employerLocationText)
                        print("lat: ", employerLat)
                        print("lng: ", employerLng)
                        print("Availability:", availability)
                        print("Job interests:", selectedJobInterests)
                    }
                    
                    
                }




        }

    }

}



struct WrapLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let items: Data
    let spacing: CGFloat
    let content: (Data.Element) -> Content

    init(items: Data, spacing: CGFloat = 8, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.items = items
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        var width = CGFloat.zero
        var height = CGFloat.zero

        return GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(Array(items), id: \.self) { item in
                    content(item)
                        .padding(.trailing, spacing)
                        .padding(.bottom, spacing)
                        .alignmentGuide(.leading) { d in
                            if (abs(width - d.width) > geometry.size.width) {
                                width = 0
                                height -= d.height + spacing
                            }
                            let result = width
                            width -= d.width + spacing
                            return result
                        }
                        .alignmentGuide(.top) { _ in
                            let result = height
                            return result
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 0)
    }
}

private func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                    to: nil, from: nil, for: nil)
}


#Preview {
    NavigationStack {
        RegisterView()
            .environmentObject(UserStore())
    }
}
