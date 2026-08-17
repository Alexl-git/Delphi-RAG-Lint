# Open Plugin Log

Opens the drag-lint plugin's own log file. Reach for it when diagnosing
the plugin's own behavior -- what it did, what it shelled out to, and any
errors it hit.

## Running it from the CLI
No CLI equivalent. The feature map lists this action's CliVerb as
"(none - in-process)" and its Mechanism as "in-process".

## Reaching it in the IDE
drag-lint > Open Plugin Log

## What it needs
Not documented as needing an index -- the feature map marks this row's
Index column "n/a". It needs the plugin to have written a log file to
open.

## Example
Illustrative only: choosing drag-lint > Open Plugin Log opens the
plugin's log file in an editor or viewer, showing recent plugin activity.
