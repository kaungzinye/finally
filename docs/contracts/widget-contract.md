# Contract: Widget Interface

Every widget reads the same Today definition as the Today tab. See `docs/model/Today.md`.

## Widget Families

| Family | Name | Content |
|--------|------|---------|
| `.systemMedium` | Focus widget | Headed "3 things to do" with the configured focus count. Lists the open Daily Focus picks with priority rings. A finished pick drops off. Tapping a ring completes the task. |
| `.systemSmall` | Now widget | The first open Daily Focus pick, large, with its deadline, "2 of 3", and a Done button. |
| `.systemLarge` | Today widget | All of Today, ordered like the Today tab. When room remains, the next seven days follow under "Coming up". When Today overflows, the list ends with "+N more". |
| `.accessoryCircular` | Lock screen ring | One ring split into one section per task in Today. Daily Focus sections draw in ink and the rest in a second color. A section fills when its task is done. The center shows done out of total. |
| `.accessoryRectangular` | Lock screen now | The first open Daily Focus pick and its deadline. |

## Interactive Elements

- **Complete**: A `Button(intent:)` runs an AppIntent in the widget process. It appends the task's provider workspace and external ID to a pending-completion list in app-group storage, updates the snapshot so the task shows done, and reloads timelines. On launch and on foreground the app applies pending completions as dirty edits, reschedules reminders, and clears the list.
- **Open task**: Tapping a row opens `finally://tasks/<id>?workspace=<provider workspace>`, so a pick from another provider opens in its own workspace.
- **Add**: `finally://tasks/new` opens capture.

## Data Source

- **Shared container**: App Group `group.com.kaungzinye.finally`
- **Storage**: a JSON presentation snapshot in app-group `UserDefaults`, written by the app after every local change and sync. It carries each open dated task's title, priority, status, scheduled day, deadline, and Daily Focus position for the selected workspace. It also carries every Daily Focus pick, whatever its provider, and each task finished on its scheduled or deadline day, so the lock screen ring can fill their sections.
- **Shared code**: the widget compiles `Finally/Shared`, which holds the Today query, the row date rule, the snapshot, and the widget selection. The widget and the Today tab read the same code.
- **Refresh**: the app calls `WidgetCenter.shared.reloadAllTimelines()` after writing the snapshot. The timeline adds an entry at the next midnight so Today rolls over.
