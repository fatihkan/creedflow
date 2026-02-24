import SwiftUI

struct TemplateVariableInputView: View {
    let template: String
    let builtInValues: [String: String]
    let onApply: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var variableValues: [String: String] = [:]

    private var variables: [String] {
        TemplateVariableResolver.extractVariables(from: template)
    }

    private var resolvedContent: String {
        var merged = builtInValues
        for (key, value) in variableValues where !value.isEmpty {
            merged[key] = value
        }
        return TemplateVariableResolver.resolve(template: template, values: merged)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Template Variables")
                        .font(.title3.bold())
                    Text("Fill in the variables to customize this prompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)

            Divider()

            Form {
                Section("Variables") {
                    ForEach(variables, id: \.self) { variable in
                        HStack {
                            Text(variable)
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 140, alignment: .leading)
                            if TemplateVariableResolver.builtInVariables.contains(variable),
                               let autoValue = builtInValues[variable], !autoValue.isEmpty {
                                TextField("Auto-filled", text: binding(for: variable))
                                    .textFieldStyle(.roundedBorder)
                                Text("auto")
                                    .font(.caption2)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.green.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.green)
                            } else {
                                TextField("Enter value...", text: binding(for: variable))
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                }

                Section("Preview") {
                    Text(resolvedContent)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply") {
                    onApply(resolvedContent)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 560, height: 480)
        .onAppear {
            // Pre-fill built-in values
            for variable in variables {
                if let autoValue = builtInValues[variable] {
                    variableValues[variable] = autoValue
                }
            }
        }
    }

    private func binding(for variable: String) -> Binding<String> {
        Binding(
            get: { variableValues[variable] ?? builtInValues[variable] ?? "" },
            set: { variableValues[variable] = $0 }
        )
    }
}
