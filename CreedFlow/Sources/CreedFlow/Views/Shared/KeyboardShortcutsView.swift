import SwiftUI

struct KeyboardShortcutsView: View {
    @Binding var isPresented: Bool

    private let shortcutGroups: [(title: String, shortcuts: [(keys: String, description: String)])] = [
        (title: "Navigation", shortcuts: [
            ("\u{2318}1", "Projects"),
            ("\u{2318}2", "Tasks"),
            ("\u{2318}3", "Agents"),
            ("\u{2318}4", "Reviews"),
            ("\u{2318}5", "Deployments"),
            ("\u{2318}6", "Prompts"),
            ("\u{2318}7", "Assets"),
            ("\u{2318}8", "Git History"),
        ]),
        (title: "Actions", shortcuts: [
            ("Esc", "Close panel / chat"),
            ("\u{2318}?", "Show this overlay"),
        ]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Keyboard Shortcuts")
                    .font(.system(.headline, weight: .semibold))
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()

            Divider()

            // Shortcuts list
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(shortcutGroups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .tracking(1)

                            ForEach(group.shortcuts, id: \.description) { shortcut in
                                HStack {
                                    Text(shortcut.description)
                                        .font(.system(.subheadline))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(shortcut.keys)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(.quaternary)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 340, height: 380)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }
}
