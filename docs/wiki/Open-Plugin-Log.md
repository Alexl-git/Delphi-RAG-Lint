# Open Plugin Log

Opens the drag-lint plugin's own log file. Reach for it when diagnosing
the plugin's own behavior -- what it did, what it shelled out to, and any
errors it hit.

## Running it from the CLI
No CLI equivalent. The feature map lists this action's CliVerb as
"(none - in-process)" and its Mechanism as "in-process".

## Reaching it in the IDE
Open the About window (drag-lint > About) and click the Open Plugin Log button.

## What it needs
Not documented as needing an index -- the feature map marks this row's
Index column "n/a". It needs the plugin to have written a log file to
open.

## Example
Illustrative only: clicking Open Plugin Log in the About window opens the
plugin's log file in an editor or viewer, showing recent plugin activity.
