# Contract: Widget Interface

Every widget reads the same Today definition as the Today tab. See `docs/model/Today.md`.

## Widgets

Each widget is its own kind with its own gallery name, so the gallery lists four widgets. They share one timeline provider.

| Gallery name | Kind | Families |
|--------------|------|----------|
| 3 things to do | `FinallyFocusWidget` | `.systemMedium` |
| Next up | `FinallyNowWidget` | `.systemSmall` |
| Today | `FinallyTodayWidget` | `.systemLarge` |
| Today ring | `FinallyTodayRingWidget` | `.accessoryCircular`, `.accessoryRectangular` |

## Widget Families

| Family | Name | Content |
|--------|------|---------|
| `.systemMedium` | Focus widget | Headed "3 things to do" with the configured focus count. Lists the open Daily Focus picks with priority rings. A finished pick drops off. Tapping a ring completes the task. While the personal agent's proposed Daily Focus waits for confirmation, it reads "3 things to confirm" over the proposed titles with no rings, and a tap opens Today. |
| `.systemSmall` | Now widget | The first open Daily Focus pick, large, with its deadline, "2 of 3", and a Done button. While the Daily Focus waits for confirmation, it reads "3 things to confirm" and "Open to confirm" with no Done button, and a tap opens Today. |
| `.systemLarge` | Today widget | All of Today, ordered like the Today tab. When room remains, the next seven days follow under "Coming up". When Today overflows, the list ends with "+N more". Unconfirmed picks list as ordinary Today tasks. |
| `.accessoryCircular` | Lock screen ring | One ring split into one section per task in Today. Daily Focus sections draw in ink and the rest in a second color. A section fills when its task is done. The center shows done out of total. Unconfirmed picks draw in the second color. |
| `.accessoryRectangular` | Lock screen now | The first open Daily Focus pick and its deadline, or "3 things to confirm" while the Daily Focus waits for confirmation. |

## Interactive Elements

- **Complete**: A `Button(intent:)` runs an AppIntent in the widget process. It appends the task's provider workspace and external ID to a pending-completion list in app-group storage, updates the snapshot so the task and its open steps show done, and reloads timelines. On launch and on foreground the app applies pending completions as dirty edits, reschedules reminders, and clears the list.
- **Open task**: Tapping a row opens `finally://tasks/<id>?workspace=<provider workspace>`, so a pick from another provider opens in its own workspace.
- **Add**: `finally://tasks/new` opens capture.

## Data Source

- **Shared container**: App Group `group.com.kaungzinye.finally`
- **Storage**: a JSON presentation snapshot in app-group `UserDefaults`, written by the app after every local change and sync. It carries each open dated task's title, priority, status, scheduled day, and deadline for the selected workspace. It also carries every Daily Focus pick, whatever its provider, as its own place holding the picked task and its open steps in order, and each task finished today that was in Today when it finished, with its completion time, so the lock screen ring can fill their sections. A step carries its parent's ID, so finishing a parent's last open step from a widget returns the parent to Today. It records whether the user confirmed the Daily Focus. The widgets draw the snapshot with every pending completion shown on top, so a completion stays done when a racing tap overwrites the snapshot.
- **Shared code**: the widget compiles `Finally/Shared`, which holds the Today query, the row date rule, the snapshot, and the widget selection. The widget and the Today tab read the same code.
- **Refresh**: the app calls `WidgetCenter.shared.reloadAllTimelines()` after writing the snapshot, which reloads every kind. The timeline adds an entry at the next midnight so Today rolls over.
