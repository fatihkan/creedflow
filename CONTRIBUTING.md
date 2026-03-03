# Contributing to CreedFlow

Thanks for your interest in contributing!

## Quick Links

- **GitHub:** https://github.com/fatihkan/creedflow
- **Issues:** https://github.com/fatihkan/creedflow/issues

## Maintainer

- **Fatih Kan** — Creator & Maintainer
  - GitHub: [@fatihkan](https://github.com/fatihkan) · X: [@fatihkan](https://x.com/fatihkan)

## How to Contribute

1. **Bugs & small fixes** — Open a PR directly
2. **New features / architecture changes** — Open an [Issue](https://github.com/fatihkan/creedflow/issues) first to discuss the approach
3. **Questions** — Use [GitHub Discussions](https://github.com/fatihkan/creedflow/discussions) or open an issue

## Project Structure

CreedFlow has two platform targets:

| Platform | Directory | Stack |
|----------|-----------|-------|
| **macOS** | `CreedFlow/` | Swift 6.0 + SwiftUI |
| **Linux** | `creedflow-desktop/` | Rust (Tauri) + React + TypeScript |

## Development Setup

### macOS (Swift)

```bash
# Build
cd CreedFlow && swift build

# Run
.build/debug/CreedFlow

# Run tests
.build/debug/CreedFlowTests

# Package as .app / DMG
./Scripts/package-app.sh
./Scripts/package-app.sh --dmg
```

**Requirements:** macOS 14+, Swift 6.0, Xcode Command Line Tools

### Linux (Tauri)

```bash
cd creedflow-desktop
pnpm install
pnpm tauri dev        # Development
pnpm tauri build      # Production (.deb + .AppImage)
```

**Requirements:** Node.js 18+, pnpm, Rust toolchain, system dependencies for Tauri

## Before You PR

- **Test locally** — Build and run the app to verify your changes work
- **macOS:** `cd CreedFlow && swift build` (0 errors expected)
- **Linux:** `cd creedflow-desktop && pnpm tauri build`
- **Keep PRs focused** — One feature or fix per PR, don't mix unrelated changes
- **Describe what & why** — Explain the motivation and what your changes do
- **Follow existing patterns** — Match the code style and architecture conventions in the codebase

## Key Conventions

- Use `AgentTask` (not `Task`) to avoid collision with `Swift.Task`
- Models use `package` access level for cross-target visibility
- ViewModels use `@Observable` with GRDB `ValueObservation`
- Backend implementations conform to the `CLIBackend` protocol
- Agent implementations conform to `AgentProtocol`
- Database changes require a new migration in `AppDatabase.swift`

## AI-Assisted PRs Welcome

Built with Claude, Codex, Gemini, or other AI tools? Great — just be transparent:

- [ ] Note that the PR is AI-assisted in the title or description
- [ ] Confirm you understand what the code does
- [ ] Test the changes locally before submitting
- [ ] Note the degree of testing (untested / lightly tested / fully tested)

## Areas We'd Love Help With

- Bug fixes and stability improvements
- New AI backend integrations
- MCP server tool additions
- UI/UX improvements
- Documentation and examples
- Test coverage
- Linux (Tauri) feature parity with macOS

Check the [Issues](https://github.com/fatihkan/creedflow/issues) page for open tasks and "good first issue" labels.

## Report a Vulnerability

See [SECURITY.md](SECURITY.md) for details on reporting security issues.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
