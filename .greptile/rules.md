# Finally review rules

Finally is an unreleased iOS app with no deployed users, released data contracts, or user vaults. Its canonical SwiftData schema changes in place. Schema review evaluates fresh stores and current readers. Migrations, dual read paths, and compatibility shims violate this project's requirements.

Provider workspaces own their tasks and Daily Focus records independently. Daily Focus picks can reference tasks across providers while each record retains its storage workspace identity. Planned days express intentions, deadlines express stated obligations, and suggested subtask dates derive from a parent's planning window.

Review data isolation, dirty-edit durability during asynchronous reads and writes, bounded picks, explicit replanning, and provider onboarding. The phone implementation uses the Daily Focus API contract in docs/contracts/daily-focus-loop.md; server deployment and live personal-agent verification are separate integration dependencies.
