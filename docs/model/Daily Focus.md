# Daily Focus

The few tasks the user picks out of Today to actually do. The interface calls it "3 things to do", using the focus limit as the number. It exists to cut analysis paralysis.

Daily Focus picks from [[Today]] first, then from everything else.

Daily Focus never grows past its [[Focus limit]].

## Fields

- Day
- Picks, ordered, each naming a task in a provider workspace
- Confirmed or proposed

## Rules

- Picking a task sets its scheduled day to today, so every pick is part of Today.
- A list the user picks by hand is confirmed by picking. No Confirm button.
- A list the personal agent proposes shows a Confirm button until the user accepts it.
- Today numbers the picks in pick order. The number of the first open pick is orange, marking where to start. A done pick keeps its place and collapses to one short struck-through line, and its ring reopens it.
- A long press and drag reorders the picks, done ones included, and saves the new pick order.
- A pick whose task was deleted shows as "Deleted" in muted text.
- One counter only: "1 of 3 done". With nothing picked it reads "Pick from Today".
- Remove takes a pick out of the day and leaves the task open with its dates. Picking into a full day swaps out the pick the user chooses.
