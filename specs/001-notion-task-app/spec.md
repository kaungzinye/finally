# Specification Package: Finally iOS and Task Providers

This package defines two separate contracts that the original combined specification treated as one feature:

- [Product interface](product-interface.md) defines provider-independent iPhone behavior, interaction patterns, reminders, recurrence, widgets, and local persistence.
- [Notion provider](notion-provider.md) defines Notion authentication, schema mapping, synchronization, permission handling, and provider-specific deployment infrastructure.
- The Finally Server connection uses HTTP basic authentication over HTTPS to discover writable server projects. The selected project becomes an isolated task workspace with its own Keychain credential.

The product interface depends on a task-provider contract. The Notion provider and Finally Server adapter implement that contract. Daily Focus planning, the Hermes planning loop, and Google Calendar projection belong to their own specifications.

## Supporting artifacts

- [Implementation plan](plan.md) records the current Swift implementation structure.
- [Data model](data-model.md) records the canonical SwiftData representation and provider-owned workspace metadata.
- [Research](research.md) records implementation research for persistence, notifications, widgets, and Notion synchronization.
- [Task checklist](tasks.md) tracks implementation work for this package.
- [Notion API contract](contracts/notion-api.md) defines remote request and response shapes.
- [URL schemes](contracts/url-schemes.md) defines app deep links.
- [Widget contract](contracts/widget-contract.md) defines widget behavior.

## Ownership rule

Provider-independent behavior belongs in `product-interface.md`. Notion-specific behavior belongs in `notion-provider.md`. New provider implementations conform to the product contract without adding their authentication, schema, or sync rules to the product interface specification.
