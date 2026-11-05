# drag-lint Options

The plugin's settings dialog for drag-lint: lets you browse and toggle the
lint rule catalog. Reach for it to see which rules exist, which are on by
default, and which have an auto-fix, and to change what is enabled.

## Running it from the CLI
The dialog itself is in-process (no CLI shell-out), but it loads its rule
catalog by running:
```
drag-lint rules --json
```
The equivalent standalone command, with the same catalog:
```
drag-lint rules [--json] [--category <name>] [--rules-dir <dir>]
```
As loaded by this dialog, the catalog has 298 rules, 110 of them fixable,
251 on by default, across 18 categories.

## Reaching it in the IDE
drag-lint > drag-lint Options...

## What it needs
Not documented as needing an index -- the feature map marks this row's
Index column "n/a" and its Mechanism "in-process". It needs the rule
catalog files that `rules --json` reads; it does not need a project
database.

## Example
Illustrative only: opening drag-lint > drag-lint Options... shows the
full 298-rule catalog, grouped by its 18 categories, with a toggle per
rule and a marker for which of the 110 fixable rules have an auto-fix.

## Inline markers and severity icons (on by default)
The editor shows a coloured marker in the gutter for each finding, and a
severity icon on each row of the Diagnostics panel. All four severities are on
by default: errors, warnings, hints and info. Info is the most common severity
(about half of all findings on a typical project), so a file can look busy.
That is intended: the owner's ruling of 2026-11-05 is to fix false positives in
the rules rather than hide a whole severity.

To turn markers off, open the Tools menu, Options, Third Party, drag-lint, Linter page,
group "Inline Markers":

* untick "Show info inline" to hide only info markers;
* untick "Show hints inline" or "Show warnings inline" or "Show errors inline"
  to hide that severity;
* untick "Enable inline markers (gutter + underline)" to hide all of them.

To silence one noisy rule instead of a whole severity, switch it off in
drag-lint > drag-lint Options... (the rule catalog above) or review the line
with a `dl:ok` marker.

A value you saved earlier wins over the default. The default only applies to
an installation with no stored value, so if info markers are still missing on
a machine that ran an older plugin and ever pressed OK in the Options page,
tick "Show info inline" once. The stored value lives at
`HKCU\Software\drag-lint\DelphiPlugin\ShowInfoInline` (0 = off, 1 = on).
