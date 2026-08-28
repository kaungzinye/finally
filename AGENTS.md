# Project Agent Instructions

## What Finally is

Finally is a native iOS task manager built around protecting attention. It presents one task experience over separate task providers, currently Notion and Finally Server, and never copies tasks between them. Each provider owns its own workspace and stays authoritative for it.

One Swift target ships the app. `FinallyWidget/` is the WidgetKit extension, `FinallyTests/` holds unit tests, and `vercel-notion-auth/` is a Vercel serverless function that brokers the Notion OAuth token exchange. `docs/` holds the specifications and setup guide. `project.yml` is the XcodeGen definition, so regenerate after changing it.

Active technologies: Swift 5.9+, SwiftUI, SwiftData, WidgetKit, AppIntents, UserNotifications, BackgroundTasks, AuthenticationServices, and Security for Keychain.

## Language and decisions

- **Read `CONTEXT.md` first. It is the glossary of this project.** Use its names in UI, docs, comments, tests, and APIs. Task, task provider, planned day, deadline, work session, and Daily Focus all mean something specific here.
- `docs/agents/domain.md` and `docs/agents/issue-tracker.md` describe how to use the domain model and the tracker.
- `docs/` holds the specifications. `spec.md` is the index, `product-interface.md` and `notion-provider.md` are the two contracts, and `docs/contracts/` pins request shapes, deep links, and widget behavior.
- The Finally Server and Daily Focus work has no spec file. Issue #5 is its PRD, and the child issues carry the detail.

## Repositories and issues

- Issues and PRDs live in GitHub Issues for `kaungzinye/finally`. Use `gh`.
- The server lives in a separate repo, `kaungzinye/finally-server`, a fork of `go-vikunja/vikunja`. It has no issues of its own, so a server PR cannot auto-close an issue. Close them by hand.
- Finally's server endpoints are v2-only, under `pkg/routes/api/v2/finally_*.go`. Both v1 and v2 route trees come from upstream Vikunja. Keep rebasing on upstream rather than deleting v1.
- Both repos reject squash merges. Use `gh pr merge --merge`.

## Build and test

**Always verify the app builds before committing.** Headless `xcodebuild` is the compile gate. Simulator builds, launches, UI inspection, log capture, and test runs are allowed for behavioural verification. Do not build to a physical device unless the user explicitly asks.

```bash
# Compile check, no simulator needed:
xcodebuild build -project Finally.xcodeproj -scheme Finally -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet

# If project.yml changed, regenerate first:
xcodegen generate

# Compile the test target without launching a simulator:
xcodebuild build-for-testing -project Finally.xcodeproj -scheme Finally -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet
```

The project defines two schemes, `Finally` and `FinallyWidgetExtension`. `FinallyTests` is a target, not a scheme, so `-scheme FinallyTests` fails. The `Finally` scheme already builds and tests `FinallyTests`.

For runtime verification, run the app on a booted simulator and inspect the launched UI and logs, then run the relevant tests on that simulator.

Maestro drives UI flows on the booted simulator for behavioural verification. Flows live in `maestro/`. Build and install the app on the simulator first, then:

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home
maestro test maestro/<flow>.yaml
```

The `-deadline-demo` launch argument (DEBUG builds) opens a populated task detail screen with no OAuth, giving flows deterministic UI.

## No compatibility burden

The app has not shipped. There are no released data contracts and no user vaults to preserve.

- Do not write migrations, legacy fallbacks, dual read paths, or backwards-compatibility shims.
- Change the canonical schema in place and update every reader.
- This is the opposite of a shipped product's rules. Do not import that instinct from another repo.

## UI

- Use iOS 26 liquid glass styling (`glassBackgroundEffect`, `GlassEffectContainer`) for navigation bars, tab bars, sidebars, and buttons where available.
- Always wrap iOS 26 styling in `if #available(iOS 26, *)` with an iOS 17 fallback.
- Follow Todoist patterns: inline task creation, chip-based fields, clean typography.
- Priority colors: Urgent is red, High is orange, Medium is blue, Low is default.

## Architecture planning in Enso

Invoke the `enso` skill whenever architecture planning needs a picture. The point is dogfooding Enso, so reach for it instead of describing structure in prose.

Triggers:

- Presenting architecture change options for comparison
- Scoping a large body of work that touches more than one subsystem
- Any explain, show, map, or illustrate request about system structure

Steps:

1. Confirm the running Enso app was built in Xcode from `main` in `~/Documents/SWE/enso`. Rebuild from `main` if the running app came from another branch or a stale build.
2. Ask the user whether they are on mobile. Ask every time, do not guess and do not carry the answer over from an earlier task.
3. Build the Canvas through the skill's normal Canvas pass.
4. Capture vision with `enso context --canvas current --vision --pretty` and read the image at `data.vision.image.path`.
5. If the user is on mobile, crop the image down to the Canvas content, cutting empty margins and app chrome so the diagram is legible on a phone, then send it with `SendUserFile`. If the user is not on mobile, name the Canvas and stop. They will open the app themselves.

Read the skill's `references/diagram-design.md` before choosing geometry, and `references/codebase-maps.md` when the Canvas maps a repository.

## Working agreements

- Do not push to remote unless the user explicitly asks.
- Do not add `Co-authored-by:` lines to commit messages or AI attribution footers to PR bodies. Commits are attributed to the human author only.
- `git push --force-with-lease` is blocked by the auto-mode classifier. Push review fixes as a follow-up commit rather than amending.
- Keep command output compact. Print failures and the final summary, not raw `xcodebuild` streams.
- Exclude build products, caches, and session histories from repository searches.

## How to weigh these

These are good defaults, not hard rules. The user's stated preference overrides anything here. When two rules collide, say which one you followed and why.

Prefer the smallest change that makes the correct behaviour unsurprising. Do not preserve complexity because it already exists, and do not add machinery because it looks rigorous.

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
