# Specification Package: Finally iOS and the Notion Provider

This package defines two separate contracts that the original combined specification treated as one feature:

- [Product interface](product-interface.md) defines provider-independent iPhone behavior, interaction patterns, reminders, recurrence, widgets, and local persistence.
- [Notion provider](notion-provider.md) defines Notion authentication, schema mapping, synchronization, permission handling, and provider-specific deployment infrastructure.

The product interface depends on a task-provider contract. The Notion provider implements that contract. Neither contract defines the future Finally Server, Daily Focus planning service, Hermes planning loop, or Google Calendar projection; those capabilities belong to their own specification.

## Supporting artifacts

- [Implementation plan](plan.md) records the current Swift implementation structure.
- [Data model](data-model.md) records the current Notion-backed SwiftData representation that the provider-neutral model replaces before release.
- [Research](research.md) records implementation research for persistence, notifications, widgets, and Notion synchronization.
- [Task checklist](tasks.md) tracks implementation work for this package.
- [Notion API contract](contracts/notion-api.md) defines remote request and response shapes.
- [URL schemes](contracts/url-schemes.md) defines app deep links.
- [Widget contract](contracts/widget-contract.md) defines widget behavior.

## Ownership rule

Provider-independent behavior belongs in `product-interface.md`. Notion-specific behavior belongs in `notion-provider.md`. New provider implementations conform to the product contract without adding their authentication, schema, or sync rules to the product interface specification.
