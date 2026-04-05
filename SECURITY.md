# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Security Design

Tickr is designed with security and privacy in mind:

- **Sandboxed** — The app runs in the macOS App Sandbox with only network client access
- **No Data Collection** — No analytics, telemetry, or personal data is collected
- **No Accounts** — No login, registration, or authentication required
- **Local Storage Only** — All settings are stored locally in UserDefaults (macOS sandbox container)
- **HTTPS Only** — All network requests use HTTPS; App Transport Security is enforced
- **No API Keys** — The app uses public financial data endpoints; no secrets are stored
- **Input Validation** — Ticker symbols are validated against a strict alphanumeric pattern before use
- **No Arbitrary Code Execution** — The app does not execute scripts, plugins, or downloaded code

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do NOT** open a public GitHub issue for security vulnerabilities
2. Email your report to the repository maintainers (see GitHub profile for contact)
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

We will acknowledge receipt within 48 hours and aim to provide a fix within 7 days for critical issues.

## Threat Model

### In Scope
- Data injection through malformed API responses
- Network security (MITM, certificate validation)
- Local data tampering
- Input validation bypass

### Out of Scope
- Physical access attacks (macOS handles this at the OS level)
- Denial of service against upstream data providers
- Social engineering
