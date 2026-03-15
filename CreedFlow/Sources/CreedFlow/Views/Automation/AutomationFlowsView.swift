import SwiftUI
import GRDB

struct AutomationFlowsView: View {
    let appDatabase: AppDatabase?

    @State private var flows: [AutomationFlow] = []
    @State private var editingFlow: AutomationFlow?
    @State private var showEditor = false
    @State private var filterTrigger: String = "all"
    @State private var confirmDeleteId: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automation Flows")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Define trigger \u{2192} action flows that execute automatically")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Filter picker
                Picker("Filter", selection: $filterTrigger) {
                    Text("All Triggers").tag("all")
                    ForEach(AutomationFlow.TriggerType.allCases, id: \.rawValue) { trigger in
                        Text(trigger.displayName).tag(trigger.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)

                Button {
                    editingFlow = nil
                    showEditor = true
                } label: {
                    Label("New Flow", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            // Error banner
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.system(size: 11))
                    Spacer()
                    Button { errorMessage = nil } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
            }

            // Flow list
            if filteredFlows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredFlows, id: \.id) { flow in
                            flowRow(flow)
                        }
                    }
                    .padding(20)
                }
            }

            // Footer
            Divider()
            HStack {
                Text("\(flows.count) flow\(flows.count == 1 ? "" : "s") total, \(flows.filter(\.isEnabled).count) enabled")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .sheet(isPresented: $showEditor) {
            AutomationFlowEditor(
                flow: editingFlow,
                onSave: { flow in
                    Task { await saveFlow(flow) }
                    showEditor = false
                },
                onCancel: { showEditor = false }
            )
        }
        .task { await observeFlows() }
    }

    // MARK: - Filtered

    private var filteredFlows: [AutomationFlow] {
        if filterTrigger == "all" {
            return flows
        }
        return flows.filter { $0.triggerType == filterTrigger }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bolt.circle")
                .font(.system(size: 36))
                .foregroundStyle(.quaternary)
            Text("No automation flows")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Create your first flow to automate workflows")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Spacer()
        }
    }

    // MARK: - Flow Row

    private func flowRow(_ flow: AutomationFlow) -> some View {
        HStack(spacing: 12) {
            // Toggle button
            Button {
                Task { await toggleFlow(flow) }
            } label: {
                Image(systemName: flow.isEnabled ? "bolt.circle.fill" : "bolt.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(flow.isEnabled ? .green : .secondary)
            }
            .buttonStyle(.plain)

            // Name + badges
            VStack(alignment: .leading, spacing: 4) {
                Text(flow.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .opacity(flow.isEnabled ? 1.0 : 0.5)

                HStack(spacing: 4) {
                    triggerBadge(flow.triggerType)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.quaternary)
                    actionBadge(flow.actionType)
                }
            }

            Spacer()

            // Last triggered
            if let lastTriggered = flow.lastTriggeredAt {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text(lastTriggered, style: .relative)
                        .font(.system(size: 10))
                }
                .foregroundStyle(.tertiary)
            }

            // Scope badge
            Text(flow.projectId != nil ? "Project" : "Global")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(flow.projectId != nil ? Color.secondary.opacity(0.15) : Color.forgeAmber.opacity(0.15))
                }

            // Edit
            Button {
                editingFlow = flow
                showEditor = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Edit flow")

            // Delete
            if confirmDeleteId == flow.id {
                HStack(spacing: 4) {
                    Button("Delete") {
                        Task { await deleteFlow(flow) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.mini)

                    Button("Cancel") {
                        confirmDeleteId = nil
                    }
                    .controlSize(.mini)
                }
            } else {
                Button {
                    confirmDeleteId = flow.id
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete flow")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(flow.isEnabled ? 0.04 : 0.02))
        }
    }

    // MARK: - Badges

    private func triggerBadge(_ type: String) -> some View {
        let triggerType = AutomationFlow.TriggerType(rawValue: type)
        let label = triggerType?.displayName ?? type
        let color: Color = {
            switch type {
            case "task_completed": return .green
            case "task_failed": return .red
            case "deploy_success": return .mint
            case "deploy_failed": return .orange
            case "review_passed": return .blue
            case "review_failed": return .yellow
            case "schedule": return .purple
            default: return .gray
            }
        }()

        return Text(label)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.15))
            }
            .foregroundStyle(color)
    }

    private func actionBadge(_ type: String) -> some View {
        let actionType = AutomationFlow.ActionType(rawValue: type)
        let label = actionType?.displayName ?? type
        let color: Color = {
            switch type {
            case "create_task": return .cyan
            case "send_notification": return .yellow
            case "run_command": return .pink
            case "deploy": return .indigo
            default: return .gray
            }
        }()

        return Text(label)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.15))
            }
            .foregroundStyle(color)
    }

    // MARK: - Data

    private func observeFlows() async {
        guard let db = appDatabase else { return }
        let observation = ValueObservation.tracking { db in
            try AutomationFlow.order(Column("name")).fetchAll(db)
        }
        do {
            for try await value in observation.values(in: db.dbQueue) {
                flows = value
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveFlow(_ flow: AutomationFlow) async {
        guard let db = appDatabase else { return }
        do {
            try await db.dbQueue.write { dbConn in
                var f = flow
                f.updatedAt = Date()
                if f.createdAt == Date.distantPast {
                    f.createdAt = Date()
                }
                try f.save(dbConn)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleFlow(_ flow: AutomationFlow) async {
        guard let db = appDatabase else { return }
        do {
            try await db.dbQueue.write { dbConn in
                var f = flow
                f.isEnabled.toggle()
                f.updatedAt = Date()
                try f.update(dbConn)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteFlow(_ flow: AutomationFlow) async {
        guard let db = appDatabase else { return }
        do {
            _ = try await db.dbQueue.write { dbConn in
                try AutomationFlow.deleteOne(dbConn, id: flow.id)
            }
            confirmDeleteId = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
