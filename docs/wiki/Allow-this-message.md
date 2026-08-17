# Allow this message

Records a `dl:ok` review of one finding, so it stops being reported without
being fixed. Reach for it when a finding is a deliberate, reviewed
exception rather than something to change.

## Reaching it in the IDE

This is a RIGHT-CLICK action, not a main-menu item. Menu path: "Structure
form (right-click a tree node)".

**The Structure form's right-click menu is the only place "Allow this
message" is reachable in the IDE** -- there is no main drag-lint menu item
for it.

To reach it: open the Structure form first (drag-lint > Show Structure),
then right-click the tree node for a finding and choose "Allow this
message".

## Running it from the CLI

The feature map lists the underlying verb as `allow`. From the usage
banner:

```
drag-lint allow <file> --fix-line <L> --fix-rule <id> [--apply]
```

Records a `dl:ok` review of one finding; dry-run without `--apply`.

## What it needs

No index required -- `allow` records the review directly against the given
file, without going through a project index database.

## Example

Illustrative:

```
drag-lint allow C:\Projects\MyApp\Unit1.pas --fix-line 42 --fix-rule unused-private-member --apply
```

This would record `Unit1.pas` line 42's `unused-private-member` finding as
reviewed, so it no longer appears in future lint runs.
