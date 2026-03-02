import SwiftUI
import GRDB

struct ProjectCreationWizard: View {
    let appDatabase: AppDatabase?
    var initialProjectType: Project.ProjectType?

    @Environment(\.dismiss) private var dismiss

    @State private var currentStep = 0
    @State private var projectType: Project.ProjectType = .software
    @State private var name = ""
    @State private var description = ""
    @State private var techStack = ""
    // @State private var automationSteps: [AutomationStep] = []
    @State private var mcpStore = MCPServerConfigStore()
    @State private var mcpSetupTemplate: MCPServerTemplate?
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showPromptPicker = false
    @State private var useNotebookLMResearch: Bool?  // nil = not decided yet
    @State private var isImporting = false
    @State private var importedPath: String?
    @State private var importValidation: ProjectDirectoryService.ImportValidation?

    private let totalSteps = 4
    private let stepTitles = ["Project Type", "Details", "MCP Check", "Summary"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isImporting ? "Import Project" : "New Project")
                        .font(.title3.bold())
                    Text("Step \(currentStep + 1) of \(totalSteps): \(stepTitles[currentStep])")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            // Progress bar
            HStack(spacing: 4) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(step <= currentStep ? Color.forgeAmber : Color.forgeNeutral.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()

            // Step content
            Group {
                switch currentStep {
                case 0:
                    projectTypeStep
                case 1:
                    detailsStep
                case 2:
                    mcpCheckStep
                case 3:
                    summaryStep
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let error = errorMessage {
                ForgeErrorBanner(message: error, onDismiss: { errorMessage = nil })
                    .padding(.horizontal, 16)
            }

            Divider()

            // Navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .keyboardShortcut(.cancelAction)
                } else {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }

                Spacer()

                if currentStep == 2 {
                    Button("Skip") {
                        withAnimation { currentStep += 1 }
                    }
                    .foregroundStyle(.secondary)
                }

                if currentStep < totalSteps - 1 {
                    Button("Next") {
                        advanceStep()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.forgeAmber)
                    .disabled(currentStep == 0 ? false : (currentStep == 1 && (name.isEmpty || description.isEmpty)))
                } else {
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.7)
                            .padding(.trailing, 8)
                    }
                    Button("Create Project") {
                        Task { await createProject() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.forgeAmber)
                    .disabled(name.isEmpty || description.isEmpty || isCreating)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 600, height: 580)
        .onAppear {
            if let initial = initialProjectType {
                projectType = initial
                currentStep = 1
            }
            if let db = appDatabase {
                mcpStore.observe(in: db.dbQueue)
            }
        }
        .sheet(isPresented: $showPromptPicker) {
            PromptPickerSheet(
                appDatabase: appDatabase,
                projectName: name,
                techStack: techStack,
                projectType: projectType.rawValue
            ) { content, category in
                description = content
                if let category {
                    projectType = NewProjectSheet.detectProjectType(from: category)
                }
            }
        }
        .sheet(item: $mcpSetupTemplate) { template in
            MCPInlineSetupSheet(appDatabase: appDatabase, template: template)
        }
    }

    private func advanceStep() {
        withAnimation {
            currentStep += 1
        }
    }

    // MARK: - Step 0: Project Type

    private var projectTypeStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Import existing project button
                Button {
                    importExistingProject()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 20))
                            .foregroundStyle(.forgeAmber)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Import Existing Project")
                                .font(.system(.subheadline, weight: .semibold))
                            Text("Select a project folder from your machine")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.forgeAmber.opacity(0.06))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.forgeAmber.opacity(0.2), lineWidth: 0.5)
                            }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Divider
                HStack {
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
                    Text("or create new")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
                }
                .padding(.horizontal, 24)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ], spacing: 12) {
                    ForEach(Project.ProjectType.allCases, id: \.self) { type in
                        ProjectTypeCard(
                            type: type,
                            isSelected: projectType == type
                        )
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.15)) {
                                projectType = type
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }

    private func importExistingProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a project folder to import"
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path = url.path
        let dirService = ProjectDirectoryService()

        Task {
            do {
                let validation = try await dirService.validateImportPath(path)
                importedPath = path
                importValidation = validation
                isImporting = true
                name = url.lastPathComponent
                if let stack = validation.detectedTechStack {
                    techStack = stack
                }
                withAnimation { currentStep = 1 }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Step 1: Details

    private var detailsStep: some View {
        Form {
            Section("Project Info") {
                if let path = importedPath {
                    LabeledContent("Imported from") {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                TextField("Project Name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            Section {
                HStack {
                    Text("Description")
                    Spacer()
                    Button {
                        showPromptPicker = true
                    } label: {
                        Label("Use Prompt", systemImage: "text.book.closed")
                            .font(.footnote)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                TextEditor(text: $description)
                    .frame(minHeight: 80)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.quaternary.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                descriptionHint
            }

            if projectType == .software || projectType == .general {
                Section("Tech Stack") {
                    TextField("e.g., React, Node.js, PostgreSQL", text: $techStack)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // if projectType == .automation {
            //     Section("Automation Steps") {
            //         AutomationFlowEditor(steps: $automationSteps)
            //             .frame(minHeight: 120)
            //     }
            // }

            notebookLMSection
        }
        .formStyle(.grouped)
    }

    /// Whether NotebookLM is configured in DB
    private var isNotebookLMConfigured: Bool {
        mcpStore.configs.contains { $0.name == "notebooklm" }
    }

    @ViewBuilder
    private var notebookLMSection: some View {
        let isContentOrImage = projectType == .content || projectType == .image
        Section {
            if isNotebookLMConfigured {
                Toggle(isOn: Binding(
                    get: { useNotebookLMResearch ?? isContentOrImage },
                    set: { useNotebookLMResearch = $0 }
                )) {
                    notebookLMLabel(
                        subtitle: isContentOrImage
                            ? "Research, infographics, and slide decks for your content"
                            : "Use NotebookLM for project research before task planning"
                    )
                }
                .tint(.forgeAmber)
            } else {
                HStack(spacing: 12) {
                    notebookLMLabel(
                        subtitle: "Research, infographics, slide decks, and podcasts"
                    )
                    Spacer()
                    Button {
                        mcpSetupTemplate = MCPServerTemplate.notebooklm
                    } label: {
                        Text("Setup")
                            .font(.footnote.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.forgeAmber)
                    .controlSize(.small)
                }
            }
        } header: {
            Text("NotebookLM")
        }
    }

    private func notebookLMLabel(subtitle: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 18))
                .foregroundStyle(.forgeAmber)
            VStack(alignment: .leading, spacing: 2) {
                Text("NotebookLM")
                    .font(.system(.body, weight: .medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var descriptionHint: some View {
        let hint: String? = {
            switch projectType {
            case .content:
                return "Tip: Mention the media types your content needs (e.g. image, video, voiceover, illustration) so CreedFlow can set up the right AI services automatically."
            case .image:
                return "Tip: Describe the visual style, format, and purpose of the images you need. CreedFlow will configure the best image generation services."
            case .video:
                return "Tip: Specify if your video needs voiceover, sound effects, or AI avatars so the right services can be configured."
            case .general:
                return "Tip: If your project involves images, video, audio, or design work, mention it here so CreedFlow can detect the required AI services."
            default:
                return nil
            }
        }()
        if let hint {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.forgeAmber)
                    .padding(.top, 1)
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Step 2: MCP Check (Description-Aware)

    /// Capabilities detected from project type + description, respecting user's NotebookLM toggle
    private var detectedCapabilities: [DetectedCapability] {
        let all = MCPRequirementsChecker.analyzeRequirements(type: projectType, description: description)
        let isContentOrImage = projectType == .content || projectType == .image
        let nlmEnabled = useNotebookLMResearch ?? isContentOrImage
        if nlmEnabled { return all }
        return all.filter { $0.id != "notebookLM" }
    }

    /// All unique MCP server IDs from detected capabilities (excluding "creedflow" — always present)
    private var relevantTemplates: [MCPServerTemplate] {
        let serverIds = MCPRequirementsChecker.allRequiredServers(from: detectedCapabilities)
            .filter { $0 != "creedflow" }
        return serverIds.compactMap { serverId in
            MCPServerTemplate.all.first { $0.id == serverId }
        }
    }

    private func isServerConfigured(_ serverId: String) -> Bool {
        mcpStore.configs.contains { $0.name == serverId }
    }

    private var mcpCheckStep: some View {
        VStack(spacing: 0) {
            mcpCheckHeader
            Divider().padding(.horizontal, 16)
            mcpCheckBody
        }
    }

    @ViewBuilder
    private var mcpCheckHeader: some View {
        let caps = detectedCapabilities.filter { $0.id != "orchestration" }
        VStack(alignment: .leading, spacing: 4) {
            Text("AI Services & MCP Configuration")
                .font(.headline)
            if caps.isEmpty {
                Text("No additional AI services detected for this project.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Based on your project description, these capabilities were detected:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    @ViewBuilder
    private var mcpCheckBody: some View {
        let caps = detectedCapabilities.filter { $0.id != "orchestration" }
        if caps.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.forgeSuccess)
                Text("No additional MCP servers required")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Your project doesn't need any external AI services.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(caps) { cap in
                        capabilitySection(cap)
                    }
                }
                .padding(16)
            }
        }
    }

    private func capabilitySection(_ cap: DetectedCapability) -> some View {
        let servers = cap.mcpServers.compactMap { serverId in
            MCPServerTemplate.all.first { $0.id == serverId }
        }
        let anyConfigured = cap.mcpServers.contains { isServerConfigured($0) }
        return VStack(alignment: .leading, spacing: 8) {
            // Capability header
            capabilitySectionHeader(cap: cap, anyConfigured: anyConfigured)

            // MCP server rows for this capability
            ForEach(servers) { template in
                capabilityServerRow(template)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(anyConfigured ? Color.forgeSuccess.opacity(0.03) : Color.forgeAmber.opacity(0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            anyConfigured ? Color.forgeSuccess.opacity(0.15) : Color.forgeAmber.opacity(0.15),
                            lineWidth: 0.5
                        )
                }
        }
    }

    private func capabilitySectionHeader(cap: DetectedCapability, anyConfigured: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: cap.icon)
                .font(.system(size: 16))
                .foregroundStyle(anyConfigured ? .forgeSuccess : .forgeAmber)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(cap.name)
                        .font(.system(.subheadline, weight: .semibold))
                    if cap.isOptional {
                        Text("Optional")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                }
                Text(cap.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Text(cap.agentDisplayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }

    private func capabilityServerRow(_ template: MCPServerTemplate) -> some View {
        let configured = isServerConfigured(template.id)
        return HStack(spacing: 10) {
            Image(systemName: configured ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(configured ? Color.forgeSuccess : Color.secondary.opacity(0.4))

            VStack(alignment: .leading, spacing: 1) {
                Text(template.displayName)
                    .font(.system(.footnote, weight: .medium))
                Text(template.description)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            if configured {
                Text("Ready")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.forgeSuccess)
            } else {
                Button {
                    if template.requiredInputs.isEmpty {
                        installMCPDirectly(template)
                    } else {
                        mcpSetupTemplate = template
                    }
                } label: {
                    Text("Configure")
                        .font(.caption2.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.forgeAmber)
                .controlSize(.mini)
            }
        }
        .padding(.leading, 32)
    }

    private func installMCPDirectly(_ template: MCPServerTemplate) {
        guard let db = appDatabase else { return }
        var config = template.buildConfig(inputs: [:])
        try? db.dbQueue.write { dbConn in
            try config.insert(dbConn)
        }
    }

    // MARK: - Step 3: Summary

    private var summaryStep: some View {
        Form {
            summaryInfoSection
            summaryDescriptionSection
            // summaryAutomationSection
            summaryMCPSection
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var summaryInfoSection: some View {
        Section("Project Summary") {
            LabeledContent("Type", value: projectType.displayName)
            LabeledContent("Name", value: name)
            if !techStack.isEmpty {
                LabeledContent("Tech Stack", value: techStack)
            }
            if let path = importedPath {
                LabeledContent("Source") {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if isImporting {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.forgeAmber)
                        .font(.footnote)
                    Text("Analyzer will not run automatically. You can trigger it manually after import.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var summaryDescriptionSection: some View {
        Section("Description") {
            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(6)
        }
    }

    // MARK: - Automation (disabled — not in Rust/Tauri)
    // @ViewBuilder
    // private var summaryAutomationSection: some View {
    //     if projectType == .automation && !automationSteps.isEmpty {
    //         Section("Automation Flow (\(automationSteps.count) steps)") { ... }
    //     }
    // }

    @ViewBuilder
    private var summaryMCPSection: some View {
        let caps = detectedCapabilities.filter { $0.id != "orchestration" }
        if !caps.isEmpty {
            Section("Detected Capabilities") {
                ForEach(caps) { cap in
                    let anyReady = cap.mcpServers.contains { isServerConfigured($0) }
                    HStack(spacing: 6) {
                        Image(systemName: cap.icon)
                            .foregroundStyle(anyReady ? .forgeSuccess : .forgeWarning)
                            .font(.footnote)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(cap.name)
                                .font(.footnote.weight(.medium))
                            Text(cap.agentDisplayName)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if cap.isOptional {
                            Text("Optional")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(anyReady ? "Ready" : "Missing")
                            .font(.caption)
                            .foregroundStyle(anyReady ? .forgeSuccess : .forgeDanger)
                    }
                }
            }
        }
    }

    // MARK: - Create Project

    private func createProject() async {
        isCreating = true
        defer { isCreating = false }

        guard let db = appDatabase else {
            errorMessage = "Database not available"
            return
        }

        do {
            let path: String
            if let importPath = importedPath {
                // Import mode: use existing directory, optionally init git
                path = importPath
                if let validation = importValidation, !validation.hasGitRepo {
                    let git = GitService()
                    try await git.initRepo(at: path)
                }
            } else {
                // New project: create directory with git branches
                let dirService = ProjectDirectoryService()
                path = try await dirService.createProjectDirectory(name: name)
            }

            // Capture state values before entering Sendable closure
            let capturedName = name
            let capturedDescription = description
            let capturedTechStack = techStack
            let capturedProjectType = projectType
            // let capturedAutomationSteps = automationSteps
            let capturedIsImporting = isImporting

            try await db.dbQueue.write { dbConn in
                let project = Project(
                    name: capturedName,
                    description: capturedDescription,
                    techStack: capturedTechStack,
                    directoryPath: path,
                    projectType: capturedProjectType
                )
                try project.insert(dbConn)

                // Backfill recent prompt usage records
                let fiveMinAgo = Date().addingTimeInterval(-300)
                try PromptUsage
                    .filter(Column("projectId") == nil)
                    .filter(Column("usedAt") >= fiveMinAgo)
                    .updateAll(dbConn, Column("projectId").set(to: project.id))

                if capturedIsImporting {
                    // Import mode: no analyzer task — user triggers manually
                } else {
                    // No auto-analyzer — user will discuss in chat first
                }
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Project Type Card

private struct ProjectTypeCard: View {
    let type: Project.ProjectType
    let isSelected: Bool

    private var icon: String {
        switch type {
        case .software: return "chevron.left.forwardslash.chevron.right"
        case .content: return "doc.text"
        case .image: return "photo"
        case .video: return "film"
        // case .automation: return "gearshape.2"
        case .general: return "square.grid.2x2"
        }
    }

    private var subtitle: String {
        switch type {
        case .software: return "Web apps, APIs, mobile apps"
        case .content: return "Blog posts, articles, docs"
        case .image: return "AI art, design, graphics"
        case .video: return "Video production, editing"
        // case .automation: return "Custom agent workflows"
        case .general: return "Mixed or other projects"
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(isSelected ? .forgeAmber : .secondary)

            Text(type.displayName)
                .font(.system(.subheadline, weight: .semibold))

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.forgeAmber.opacity(0.1) : Color.primary.opacity(0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Color.forgeAmber : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 0.5)
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - MCP Inline Setup Sheet

private struct MCPInlineSetupSheet: View {
    let appDatabase: AppDatabase?
    let template: MCPServerTemplate
    @Environment(\.dismiss) private var dismiss
    @State private var inputValues: [String: String] = [:]

    private var allInputsFilled: Bool {
        template.requiredInputs.allSatisfy { input in
            guard let value = inputValues[input.id] else { return false }
            return !value.isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            mcpSetupHeader
            mcpSetupForm
            Divider()
            mcpSetupActions
        }
        .frame(width: 420, height: 320)
    }

    private var mcpSetupHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: template.icon)
                .font(.largeTitle)
                .foregroundStyle(Color.forgeAmber)
            Text("Setup \(template.displayName)")
                .font(.headline)
            Text(template.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var mcpSetupForm: some View {
        Form {
            ForEach(template.requiredInputs) { input in
                Section(input.label) {
                    switch input.type {
                    case .path:
                        HStack {
                            TextField(input.placeholder, text: binding(for: input.id))
                                .textFieldStyle(.roundedBorder)
                            Button("Browse") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = true
                                panel.allowsMultipleSelection = false
                                if panel.runModal() == .OK, let url = panel.url {
                                    inputValues[input.id] = url.path
                                }
                            }
                        }
                    case .secret:
                        SecureField(input.placeholder, text: binding(for: input.id))
                            .textFieldStyle(.roundedBorder)
                    case .text:
                        TextField(input.placeholder, text: binding(for: input.id))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var mcpSetupActions: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Save") { install() }
                .buttonStyle(.borderedProminent)
                .tint(.forgeAmber)
                .keyboardShortcut(.defaultAction)
                .disabled(!allInputsFilled)
        }
        .padding()
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { inputValues[key, default: ""] },
            set: { inputValues[key] = $0 }
        )
    }

    private func install() {
        guard let db = appDatabase else { return }
        var config = template.buildConfig(inputs: inputValues)
        try? db.dbQueue.write { dbConn in
            try config.insert(dbConn)
        }
        dismiss()
    }
}
