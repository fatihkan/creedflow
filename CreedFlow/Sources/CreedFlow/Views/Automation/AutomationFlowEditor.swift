import SwiftUI

/// A single step in an automation flow — maps to an AgentTask when the project is created.
struct AutomationStep: Identifiable {
    let id = UUID()
    var agentType: AgentTask.AgentType = .contentWriter
    var title: String = ""
    var prompt: String = ""
    var dependsOnStepIndices: Set<Int> = []
}

/// Inline editor for defining automation steps (embedded in ProjectCreationWizard).
struct AutomationFlowEditor: View {
    @Binding var steps: [AutomationStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if steps.isEmpty {
                VStack(spacing: 6) {
                    Text("No steps yet")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                    Text("Add steps to define your automation flow")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                AutomationStepRow(
                    index: index,
                    step: Binding(
                        get: { steps[index] },
                        set: { steps[index] = $0 }
                    ),
                    totalSteps: steps.count,
                    onDelete: {
                        // Clean up dependency references before deleting
                        let removedIndex = index
                        steps.remove(at: removedIndex)
                        for i in steps.indices {
                            steps[i].dependsOnStepIndices.remove(removedIndex)
                            // Shift indices down for steps after the removed one
                            let shifted = steps[i].dependsOnStepIndices.compactMap { dep in
                                dep > removedIndex ? dep - 1 : (dep == removedIndex ? nil : dep)
                            }
                            steps[i].dependsOnStepIndices = Set(shifted)
                        }
                    }
                )
            }
            .onMove { source, destination in
                steps.move(fromOffsets: source, toOffset: destination)
            }

            Button {
                steps.append(AutomationStep())
            } label: {
                Label("Add Step", systemImage: "plus.circle")
                    .font(.footnote.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.forgeAmber)
        }
    }
}

// MARK: - Step Row

private struct AutomationStepRow: View {
    let index: Int
    @Binding var step: AutomationStep
    let totalSteps: Int
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            stepHeader
            stepFields
            dependencyPicker
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.02))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                }
        }
    }

    @ViewBuilder
    private var stepHeader: some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.forgeAmber)
                .frame(width: 20, height: 20)
                .background(Color.forgeAmber.opacity(0.15))
                .clipShape(Circle())

            Picker("Agent", selection: $step.agentType) {
                ForEach(AgentTask.AgentType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .frame(maxWidth: 180)

            Spacer()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var stepFields: some View {
        TextField("Step title", text: $step.title)
            .textFieldStyle(.roundedBorder)
            .font(.footnote)

        ZStack(alignment: .topLeading) {
            if step.prompt.isEmpty {
                Text("Describe what this step should do...")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                    .padding(.top, 6)
                    .padding(.leading, 4)
            }
            TextEditor(text: $step.prompt)
                .font(.caption)
                .scrollContentBackground(.hidden)
        }
        .frame(minHeight: 40, maxHeight: 60)
        .padding(4)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var dependencyPicker: some View {
        if index > 0 {
            HStack(spacing: 4) {
                Text("Depends on:")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                ForEach(0..<index, id: \.self) { depIndex in
                    depButton(for: depIndex)
                }
            }
        }
    }

    private func depButton(for depIndex: Int) -> some View {
        let isSelected = step.dependsOnStepIndices.contains(depIndex)
        return Button {
            if isSelected {
                step.dependsOnStepIndices.remove(depIndex)
            } else {
                step.dependsOnStepIndices.insert(depIndex)
            }
        } label: {
            Text("Step \(depIndex + 1)")
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.forgeAmber : Color.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(isSelected ? Color.forgeAmber.opacity(0.15) : Color.primary.opacity(0.04))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
