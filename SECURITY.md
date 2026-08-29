# Security policy

## Supported code

Security fixes target the current `main` branch and the latest published release. Older builds may require an upgrade before a fix can be applied.

## Report a vulnerability privately

Use [GitHub private vulnerability reporting](https://github.com/kaungzinye/finally/security/advisories/new). Do not open a public issue for a suspected vulnerability.

If GitHub private reporting is unavailable, email `kaungzinye11@gmail.com` with the subject `Finally security report`.

Include:

- the affected commit, release, or deployed component;
- steps to reproduce with sensitive values removed;
- the impact and data at risk;
- any known workaround or suggested fix;
- a safe way to contact you.

You should receive an acknowledgement within 72 hours. Triage and remediation timing depends on severity and reproducibility. The project will coordinate disclosure with the reporter when practical.

## Scope

Reports are in scope when they affect:

- OAuth callback or token exchange handling;
- Keychain credential storage;
- task or project authorization and provider isolation;
- the widget or app-group data boundary;
- notification data exposure;
- Finally Server authentication used by the iOS client;
- code in this repository that exposes private task or calendar data.

Report vulnerabilities in Notion, Apple, Vercel, Google, or another independent service to that provider unless Finally's code causes the exposure.

## Research guidelines

Use accounts, devices, workspaces, and servers you own or have permission to test. Avoid privacy violations, service disruption, social engineering, and access to other people's data. Stop testing and report the issue if you encounter private data.

The maintainer will not pursue action against good-faith research that follows these guidelines and gives the project a reasonable opportunity to address the report. This statement does not authorize testing against third-party services.
