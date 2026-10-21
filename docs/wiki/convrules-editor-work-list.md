# Work list

After a Convert run, ConvRulesEditor lists every place in the converted units'
code that still uses a member of a converted component and needs a person to
look at it: a property the new class does not have, a member the book maps to a
dotted path the engine could not rewrite, a cast the engine refused to make, a
global (a type or an enum value) whose unit the book removed. Use it as the
to-do list for the manual part of a conversion.

## Where it shows
View > Work list opens the Work list tab, beside the Convert tab. It is filled
when a Convert run finishes and replaced by the next run -- it never mixes two
runs.

Each row is one member (or global) in one unit. The columns are Unit,
Instance (`(global)` for a global), From -> To (`--` for a global), Member,
Kind, Status, Lines and Declared in. The status line above the grid sums it up, for example:

```
2 to work on (2 unmapped, 0 global, 0 cast-refused, 0 not-rewritten), 1 mapped / same-name; 2 shown
```

## Filtering
A check list of statuses (the four work statuses are checked by default;
`mapped` and `same-name` are not; `(other)` stands for any status this editor
version does not know, and is checked so nothing new is hidden), a unit box and
a member / instance text filter. Rows sort by status, then unit, then instance
(globals last), then member.

## Going to the code
Double-click a row: the full path and line, `<path>(<line>)`, are copied to the
clipboard and the status bar says `Copied <file>(<line>) to the clipboard -- line <N>`. The IDE's Go to line dialog takes only the line number. A file that is
gone, or a line past its end, is reported on the status bar instead.

## What it needs
An engine that reports `pas_uses` in `info --json` (drag-lint 1.27.0 and
later). With an older engine the tab says `no work list (engine has no pas_uses)`. A run in which no unit converted says `no work list (no unit converted)`; before any run it says `no work list yet -- run Convert first`.

## A refused Convert keeps the list
When Convert is refused before it runs (the pre-flight, no project file, or the
inherited-instance question answered No) the list keeps the previous run's rows and the
summary says so: ` -- from the previous run (<unit>, <time>); the last Convert was
refused`. Before any run there is nothing to keep and the summary does not change.
The next finished run replaces the list as before.

## Limits
The list is what the engine reported for the units that CONVERTED; a failed,
refused or rolled-back unit contributes nothing. "Declared in" names a unit only
when the engine resolved the class in the unit's scope. With drag-lint 1.28.2 and
later (`pas_uses_resolution`) an unresolved row says so instead of guessing:
`ambiguous: FMX.StdCtrls, Vcl.StdCtrls` (the units that could declare it),
`(class not found)`, `(member not found)` or `(kind unknown)`, and its Kind reads
`(unknown)` when the engine could not tell. An older engine's text is shown as it
came.
