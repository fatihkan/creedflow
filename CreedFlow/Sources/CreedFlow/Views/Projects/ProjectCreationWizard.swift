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
    @State private var automationSteps: [AutomationStep] = []
    @State private var mcpCheckResults: [MCPCheckResult] = []
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showPromptPicker = false

    private let totalSteps = 4
    private let stepTitles = ["Project Type", "Details", "MCP Check", "Summary"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Project")
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
    }

    private func advanceStep() {
        withAnimation {
            if currentStep == 1 {
                // Trigger MCP check before showing step 2
                Task {
                    if let db = appDatabase {
                        mcpCheckResults = await MCPRequirementsChecker.check(for: projectType, in: db.dbQueue)
                    }
                }
            }
            currentStep += 1
        }
    }

    // MARK: - Step 0: Project Type

    private var projectTypeStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("What type of project are you creating?")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

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

    // MARK: - Step 1: Details

    private var detailsStep: some View {
        Form {
            Section("Project Info") {
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
            }

            if projectType == .software || projectType == .general {
                Section("Tech Stack") {
                    TextField("e.g., React, Node.js, PostgreSQL", text: $techStack)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if projectType == .automation {
                Section("Automation Steps") {
                    AutomationFlowEditor(steps: $automationSteps)
                        .frame(minHeight: 120)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Step 2: MCP Check

    private var mcpCheckStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("MCP Server Configuration")
                .font(.headline)
                .padding(.horizontal, 24)
                .padding(.top, 16)

            if mcpCheckResults.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.forgeSuccess)
                    Text("No additional MCP servers required")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let hasAnyConfigured = mcpCheckResults.contains { $0.isConfigured }
                let allConfigured = mcpCheckResults.allSatisfy { $0.isConfigured }
                let requiresAtLeastOne = MCPRequirementsChecker.requiresAtLeastOne(for: projectType)

                VStack(alignment: .leading, spacing: 8) {
                    if requiresAtLeastOne {
                        Text("At least one of these MCP servers should be configured:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                    } else {
                        Text("The following MCP servers are recommended:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                    }

                    ForEach(mcpCheckResults) { result in
                        HStack(spacing: 12) {
                            Image(systemName: result.isConfigured ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.isConfigured ? .forgeSuccess : .forgeDanger)
                                .font(.title3)
                            Text(result.displayName)
                                .font(.body)
                            Spacer()
                            Text(result.isConfigured ? "Configured" : "Missing")
                                .font(.footnote)
                                .foregroundStyle(result.isConfigured ? .forgeSuccess : .forgeDanger)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 4)
                    }

                    if !allConfigured && !(requiresAtLeastOne && hasAnyConfigured) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.forgeWarning)
                            Text("Some creative tasks may fail without these servers. You can configure them in Settings.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            }
        }
    }

    // MARK: - Step 3: Summary

    private var summaryStep: some View {
        Form {
            summaryInfoSection
            summaryDescriptionSection
            summaryAutomationSection
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

    @ViewBuilder
    private var summaryAutomationSection: some View {
        if projectType == .automation && !automationSteps.isEmpty {
            Section("Automation Flow (\(automationSteps.count) steps)") {
                ForEach(Array(automationSteps.enumerated()), id: \.element.id) { index, step in
                    HStack(spacing: 8) {
                        Text("\(index + 1).")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Image(systemName: step.agentType.icon)
                            .foregroundStyle(step.agentType.themeColor)
                        Text(step.title.isEmpty ? step.agentType.displayName : step.title)
                            .font(.footnote)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var summaryMCPSection: some View {
        let missing = mcpCheckResults.filter { !$0.isConfigured }
        if !missing.isEmpty {
            Section("MCP Warnings") {
                ForEach(missing) { result in
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.forgeWarning)
                            .font(.footnote)
                        Text("\(result.displayName) not configured")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
            let dirService = ProjectDirectoryService()
            let path = try await dirService.createProjectDirectory(name: name)

            // Capture state values before entering Sendable closure
            let capturedName = name
            let capturedDescription = description
            let capturedTechStack = techStack
            let capturedProjectType = projectType
            let capturedAutomationSteps = automationSteps
            let analyzerDescription = "[ProjectType: \(capturedProjectType.rawValue)] \(capturedDescription)"

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

                if capturedProjectType == .automation && !capturedAutomationSteps.isEmpty {
                    // Create tasks directly from automation steps (no Analyzer)
                    var createdTasks: [String: UUID] = [:]

                    for (index, step) in capturedAutomationSteps.enumerated() {
                        let task = AgentTask(
                            projectId: project.id,
                            agentType: step.agentType,
                            title: step.title.isEmpty ? "\(step.agentType.rawValue.capitalized) Step \(index + 1)" : step.title,
                            description: step.prompt.isEmpty ? step.title : step.prompt,
                            priority: max(1, 10 - index)
                        )
                        try task.insert(dbConn)
                        createdTasks["\(index)"] = task.id

                        // Create dependencies
                        for depIndex in step.dependsOnStepIndices {
                            if let depTaskId = createdTasks["\(depIndex)"] {
                                let dep = TaskDependency(
                                    taskId: task.id,
                                    dependsOnTaskId: depTaskId
                                )
                                try dep.insert(dbConn)
                            }
                        }
                    }
                } else {
                    // Standard flow: queue analyzer task
                    let analyzerTask = AgentTask(
                        projectId: project.id,
                        agentType: .analyzer,
                        title: "Analyze: \(capturedName)",
                        description: analyzerDescription,
                        priority: 10
                    )
                    try analyzerTask.insert(dbConn)
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
        case .automation: return "gearshape.2"
        case .general: return "square.grid.2x2"
        }
    }

    private var subtitle: String {
        switch type {
        case .software: return "Web apps, APIs, mobile apps"
        case .content: return "Blog posts, articles, docs"
        case .image: return "AI art, design, graphics"
        case .video: return "Video production, editing"
        case .automation: return "Custom agent workflows"
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
