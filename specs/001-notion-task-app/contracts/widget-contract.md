# Contract: Widget Interface

**Date**: 2026-03-13

## Widget Families

| Family | Layout | Content |
|--------|--------|---------|
| `.systemSmall` | Compact list | 3-4 nearest tasks with checkboxes. "+" button bottom-right. Single tap area for whole widget opens app. |
| `.systemMedium` | Wide list | 4-6 tasks with checkbox, task name, due date. "+" button bottom-right via `Link`. |
| `.systemLarge` | Extended list | 8-10 tasks with checkbox, task name, due date, priority color indicator. "+" button bottom-right via `Link`. |

## Interactive Elements

### Task Checkbox (Toggle)

- **Mechanism**: `Toggle(isOn:intent:)` with `ToggleTaskCompleteIntent` (AppIntent)
- **Behavior**: Optimistic UI flip → `perform()` updates shared SwiftData store → timeline auto-reloads
- **For recurring tasks**: Advances due date instead of marking done

### "+" Add Button

- **Mechanism**: `Link(destination: URL(string: "finally://tasks/new")!)`
- **Position**: Bottom-right corner of all widget sizes
- **Behavior**: Opens main app → task creation flow

## Data Source

- **Shared container**: App Group `group.com.kaungzinye.finally`
- **Storage**: SwiftData `ModelContainer` at shared container path
- **Widget reads only**: Writes via AppIntents (run in main app process)
- **Refresh trigger**: `WidgetCenter.shared.reloadTimelines(ofKind: "TaskListWidget")` on every data change
- **Timeline policy**: `.atEnd` with entries at each upcoming task due time
