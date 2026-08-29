# Security Policy

## Supported Versions

GuardianHer is a safety-critical application. Security updates are applied to the latest release branch.

| Version | Supported |
|---------|-----------|
| 1.0.x   | ✅ Yes    |

Only the latest stable release receives security patches. Older versions are not maintained.

---

## Reporting a Vulnerability

**Please do NOT publicly disclose exploitable vulnerabilities before remediation.**

If you discover a security vulnerability in GuardianHer, please report it responsibly:

1. **Email**: Send details to the project maintainers (contact information in the repository's `AUTHORS` or `CONTRIBUTORS` file, or via GitHub's private vulnerability reporting if enabled)
2. **Include**:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)
3. **Expect**:
   - Acknowledgment within 72 hours
   - Regular updates on remediation progress
   - Credit in the release notes (unless you prefer anonymity)

---

## Responsible Disclosure

We follow responsible disclosure practices:

- Vulnerabilities are fixed before public disclosure
- Users are informed via release notes and app updates
- No exploit details are published until a fix is widely deployed
- We appreciate researchers who help keep GuardianHer users safe

---

## Security Architecture Notes

GuardianHer's security model prioritizes:

- **Immediate emergency access** — No app lock/PIN/biometric on launch (by design)
- **Local-first data** — Sensitive data (contacts, history) in Keystore-backed `flutter_secure_storage`
- **No cloud sync by default** — Live location sharing is opt-in and requires explicit backend configuration
- **Honest communication** — Never claims delivery; only that composers were opened
- **Fail-closed** — Errors surface to user; no silent failures in safety paths
- **Minimal permissions** — No `ACCESS_BACKGROUND_LOCATION`, no `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, no exact alarms

---

## Known Security Considerations

| Area | Consideration |
|------|---------------|
| **Shake SOS cold launch** | Requires `SYSTEM_ALERT_WINDOW` on Android 14+ behind lock screen; without it, launch is silently refused |
| **Live location backend** | Optional; tokens are SHA-256 hashed server-side; public endpoints return identical responses for unknown/expired tokens |
| **SMS sending** | Emergency orchestrator uses `SEND_SMS` (runtime permission); user-confirmed composers used elsewhere |
| **Device administrator** | Opt-in; blocks uninstall/force-stop while active; declares NO policies (no lock/wipe) |
| **Safety Recorder** | Tamper-evident hash chain (not tamper-proof); no PII in events |

---

## Contact

For security inquiries, use the reporting channel above. Do not use public issue trackers for exploitable vulnerabilities.