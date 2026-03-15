import SwiftUI

struct AutomationFlowEditor: View {
    let flow: AutomationFlow?
    let onSave: (AutomationFlow) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var triggerType: AutomationFlow.TriggerType = .taskCompleted
    @State private var triggerConfig: String = "{}"
    @State private var actionType: AutomationFlow.ActionType = .createTask
    @State private var actionConfig: String = "{}"
    @State private var isEnabled: Bool = true
    @State private var projectId: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(flow == nil ? "New Automation Flow" : "Edit Flow")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { onCancel() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Name
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("e.g. Auto-review on coder completion", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }

                    // Trigger + Action pickers side by side
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Trigger")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Picker("Trigger", selection: $triggerType) {
                                ForEach(AutomationFlow.TriggerType.allCases, id: \.self) { t in
                                    Text(t.displayName).tag(t)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Action")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Picker("Action", selection: $actionType) {
                                ForEach(AutomationFlow.ActionType.allCases, id: \.self) { a in
                                    Text(a.displayName).tag(a)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }
                    }

                    // Trigger config
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trigger Config (JSON)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $triggerConfig)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 60)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.primary.opacity(0.04))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(Color.primary.opacity(0.1))
                                    }
                            }
                        triggerConfigHint
                    }

                    // Action config
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Action Config (JSON)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $actionConfig)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 60)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.primary.opacity(0.04))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(Color.primary.opacity(0.1))
                                    }
                            }
                        actionConfigHint
                    }

                    // Enabled toggle
                    Toggle("Enabled", isOn: $isEnabled)
                        .font(.system(size: 12))
                }
                .padding(16)
            }

            Divider()

            // Actions
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)

                Button(flow == nil ? "Create" : "Save") {
                    let result = AutomationFlow(
                        id: flow?.id ?? UUID().uuidString,
                        projectId: projectId,
                        name: name,
                        triggerType: triggerType.rawValue,
                        triggerConfig: triggerConfig,
                        actionType: actionType.rawValue,
                        actionConfig: actionConfig,
                        isEnabled: isEnabled,
                        lastTriggeredAt: flow?.lastTriggeredAt,
                        createdAt: flow?.createdAt ?? Date(),
                        updatedAt: Date()
                    )
                    onSave(result)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 500, height: 520)
        .onAppear {
            if let flow {
                name = flow.name
                triggerType = AutomationFlow.TriggerType(rawValue: flow.triggerType) ?? .taskCompleted
                triggerConfig = flow.triggerConfig
                actionType = AutomationFlow.ActionType(rawValue: flow.actionType) ?? .createTask
                actionConfig = flow.actionConfig
                isEnabled = flow.isEnabled
                projectId = flow.projectId
            }
        }
    }

    // MARK: - Config Hints

    @ViewBuilder
    private var triggerConfigHint: some View {
        switch triggerType {
        case .taskCompleted, .taskFailed:
            Text("Example: {\"agentType\": \"coder\"}")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        case .deploySuccess, .deployFailed:
            Text("Example: {\"environment\": \"staging\"}")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        case .reviewPassed, .reviewFailed:
            Text("Example: {\"minScore\": 7.0}")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        case .schedule:
            Text("Example: {\"cron\": \"0 9 * * *\"}")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var actionConfigHint: some View {
        switch actionType {
        case .createTask:
            Text("Example: {\"agentType\": \"reviewer\", \"title\": \"Auto-review\"}")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        case .sendNotification:
            Text("Example: {\"message\": \"Task completed!\"}")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        case .runCommand:
            Text("Example: {\"command\": \"make test\"}")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        case .deploy:
            Text("Example: {\"environment\": \"staging\"}")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}
