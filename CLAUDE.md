# Finally Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-03-13

## Active Technologies

- Swift 5.9+ / SwiftUI + SwiftData, WidgetKit, AppIntents, UserNotifications, BackgroundTasks, AuthenticationServices (ASWebAuthenticationSession), Security (Keychain) (001-notion-task-app)

## Build & Test

**IMPORTANT**: Always verify code compiles before committing. Use xcodebuild for compilation checks — never build to a device or simulator.

```bash
# Compile check (no device/simulator needed):
xcodebuild build -project Finally.xcodeproj -scheme Finally -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet

# If project.yml changes, regenerate first:
xcodegen generate

# Run tests (compile-only, no simulator):
xcodebuild build-for-testing -project Finally.xcodeproj -scheme FinallyTests -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO -quiet
```

## Project Structure

```text
Finally/        # Main iOS app target
FinallyWidget/  # Widget extension target
FinallyTests/   # Unit tests
vercel-notion-auth/            # Vercel serverless function for OAuth token exchange
specs/                         # Feature specifications (speckit)
project.yml                    # XcodeGen project definition
```

## UI Styling

- Use iOS 26 liquid glass styling (`glassBackgroundEffect`, `GlassEffectContainer`, etc.) for navigation bars, tab bars, sidebars, and buttons where available
- Always wrap iOS 26 styling with `if #available(iOS 26, *)` checks and provide an iOS 17-compatible fallback
- Follow Todoist UI patterns: inline task creation, chip-based fields, clean typography
- Priority colors: Urgent=red, High=orange, Medium=blue, Low=default

## Code Style

Swift 5.9+ / SwiftUI: Follow standard conventions

## Recent Changes

- 001-notion-task-app: Added Swift 5.9+ / SwiftUI + SwiftData, WidgetKit, AppIntents, UserNotifications, BackgroundTasks, AuthenticationServices (ASWebAuthenticationSession), Security (Keychain)

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
