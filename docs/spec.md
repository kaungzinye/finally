# Specification Package: Finally iOS and Task Providers

This package defines two separate contracts:

- [Product interface](product-interface.md) defines provider-independent iPhone behavior, interaction patterns, reminders, recurrence, widgets, and local persistence.
- [Notion provider](notion-provider.md) defines Notion authentication, schema mapping, synchronization, permission handling, and provider-specific deployment infrastructure.
- The Finally Server connection uses HTTP basic authentication over HTTPS to discover writable server projects. The selected project becomes an isolated task workspace with its own Keychain credential.

The product interface depends on a task-provider contract. The Notion provider and Finally Server adapter implement that contract. Daily Focus planning, the planning loop, and Google Calendar projection live in GitHub issue #5 and its child issues.

## Supporting artifacts

- [Data model](data-model.md) records the canonical SwiftData representation and provider-owned workspace metadata.
- [Quickstart](quickstart.md) covers Notion integration, database schema, and OAuth setup.
- [Notion API contract](contracts/notion-api.md) defines remote request and response shapes.
- [URL schemes](contracts/url-schemes.md) defines app deep links.
- [Widget contract](contracts/widget-contract.md) defines widget behavior.

Implementation work is tracked in GitHub Issues, not in this directory.

## Ownership rule

Provider-independent behavior belongs in `product-interface.md`. Notion-specific behavior belongs in `notion-provider.md`. New provider implementations conform to the product contract without adding their authentication, schema, or sync rules to the product interface specification.
