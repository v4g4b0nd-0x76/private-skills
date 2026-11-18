# Rules of engagement

Load when filling or validating `.product-security/<run>/roe.md`.

## Required frontmatter keys

```yaml
---
authorized: false          # must be true before black/gray/white
valid_from: YYYY-MM-DD
valid_until: YYYY-MM-DD
stop_contact: name + channel
credentials.ref: ""        # path to secrets file outside the workspace (gray)
code-root: ""              # absolute or project-relative path to owned source (white)
approval_reference: ""     # ticket / email / change id
---
```

## Body sections the agent must complete

1. **Scope** — exact domains, IPs, ports, and URL prefixes under test.
2. **Out of scope** — third-party CDNs, payment providers, shared infra, DoS, social engineering.
3. **Allowed actions** — Bright non-destructive by default; destructive only when armed.
4. **Stop conditions** — error-rate spike, customer impact, auth lockouts → stop and page `stop_contact`.
5. **Data handling** — no customer PII in findings; redact tokens.

## Machine rules (enforced by scripts)

- `authorized` must equal `true` (case-sensitive YAML boolean).
- Every scan target must appear in `targets.json`.
- `credentials.ref` must be non-empty before `--phase gray`.
- `code-root` must exist as a directory before `--phase white`.
- Secrets never copied into `.product-security/`.
