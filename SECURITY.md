# Security Policy

If you believe you've found a security issue in CreedFlow, please report it responsibly.

## Supported Versions

| Version | Supported |
|---------|-----------|
| v1.3.0 (latest) | Yes |
| < v1.3.0 | Best effort |

## Reporting a Vulnerability

**Do not open a public issue for security vulnerabilities.**

Instead, report them privately:

1. **GitHub Security Advisories** (preferred) — Use [GitHub's private vulnerability reporting](https://github.com/fatihkan/creedflow/security/advisories/new)
2. **Email** — Contact the maintainer directly via GitHub

### What to Include

1. **Description** — What the vulnerability is
2. **Severity** — Your assessment (Critical / High / Medium / Low)
3. **Affected Component** — Which part of CreedFlow is affected (macOS app, Tauri app, backend, etc.)
4. **Reproduction Steps** — Step-by-step instructions to reproduce the issue
5. **Impact** — What an attacker could achieve
6. **Environment** — OS version, CreedFlow version, relevant configuration
7. **Suggested Fix** — If you have one

### Response Timeline

- **Acknowledgment:** Within 48 hours
- **Assessment:** Within 1 week
- **Fix (critical):** As soon as possible
- **Fix (non-critical):** Included in next release

## Security Architecture

### AI Agent Trust Model

CreedFlow orchestrates AI agents that generate and execute code. Important trust boundaries:

- **AI-generated code is untrusted** — All agent output should be reviewed before deployment
- **Agents run with user-level permissions** — No elevated privileges, but full access to the user's filesystem
- **CLI backends inherit the user's environment** — API keys and PATH are passed to spawned processes
- **The app sandbox is disabled** — Required for spawning CLI processes (Claude, Codex, Gemini, etc.)

### Credential Storage

CreedFlow stores credentials locally on your machine:

| Platform | Storage | Location |
|----------|---------|----------|
| macOS | UserDefaults | `~/Library/Preferences/com.creedflow.app.plist` |
| Linux | settings.json | `{app_data_dir}/settings.json` |
| Both | SQLite | Publishing channel credentials in `credentialsJSON` column |

**Note:** Credentials are stored in plaintext. They are never transmitted to third parties beyond the configured AI backends. We recommend:

- Using environment variables for API keys when possible
- Keeping your machine's user account secured
- Not sharing your CreedFlow data directory

### Process Management

- `ProcessTracker` singleton tracks all child CLI processes by PID
- All child processes receive SIGTERM on app termination — no orphaned processes
- CLI processes are spawned via `Process()` (Swift) or `tokio::process::Command` (Rust), not through a shell unless required (deployment)

## Known Security Considerations

These are by-design tradeoffs, not vulnerabilities:

| Item | Reason |
|------|--------|
| App sandbox disabled | Required to spawn AI CLI processes |
| UserDefaults for tokens | Simple local storage; Keychain migration planned |
| Shell execution in deploy | `LocalDeploymentService` uses `/bin/sh -c` for Docker/process deployment |
| curl-pipe-bash for Homebrew | Standard Homebrew install pattern in `DependencyInstaller` |
| Tauri CSP set to null | Development convenience; should be tightened for production |

## Out of Scope

The following are not considered security vulnerabilities:

- AI-generated code containing bugs or vulnerabilities (this is expected; users must review output)
- Prompt injection attacks against AI backends (this is an AI backend concern, not CreedFlow's)
- Local file access by the app (the app requires filesystem access by design)
- Credential storage in UserDefaults/settings.json (documented behavior; local-only)
- Issues requiring physical access to the user's machine

## Best Practices for Users

- **Review all AI-generated code** before committing or deploying
- **Never commit secrets** to your repository — use environment variables
- **Keep `.gitignore` updated** — Ensure `.env`, `*.pem`, `*.key` are excluded
- **Use Docker for deployments** — Isolate AI-generated code from your host
- **Keep AI CLIs updated** — Install the latest versions of Claude, Codex, Gemini, etc.
- **Monitor agent output** — Review logs before approving tasks

## Bug Bounties

CreedFlow is an open-source project maintained by an individual developer. There is no bug bounty program. Please still report vulnerabilities responsibly so they can be fixed promptly.

The best way to help is by sending PRs that fix security issues.
