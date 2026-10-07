# DL's doc-facts cycle -- the `cycles` question, proven on a real SCC

Generated 2026-10-06 from the frozen DL clone (`charts\scratch\db\DL-drag-lint.sqlite`,
this repo's own CLI project), engine `drag-lint 1.22.0-alpha`. Nothing in the
bundle was written by hand; rerun it, never edit output. The bundle folder
`cycles-project\` is gitignored; this README is the committed part.

## What the cycle is

The largest real multi-unit cycle in the clones: one strongly-connected
component of 5 units (CLIENT's two groups have 3 and 2). It is NOT a ring --
three loops share `DRagLint.Doc.Regions`:

* Facts -> Harvest -> Regions -> Facts
* Regions -> SharedFacts -> Regions
* Regions -> SharedFacts -> ProjectTags -> Regions

## Every edge, verified against the source

Checked by hand in `C:\Projects\Delphi-RAG-lint\src\doc\`, each file's sha256
equal to the clone's `files.sha256` (so the source read IS the source indexed).

| from | to | section | file:line |
|---|---|---|---|
| DRagLint.Doc.Facts | DRagLint.Doc.Harvest | implementation | DRagLint.Doc.Facts.pas:977 |
| DRagLint.Doc.Harvest | DRagLint.Doc.Regions | implementation | DRagLint.Doc.Harvest.pas:206 |
| DRagLint.Doc.ProjectTags | DRagLint.Doc.Regions | implementation | DRagLint.Doc.ProjectTags.pas:304 |
| DRagLint.Doc.Regions | DRagLint.Doc.Facts | **interface** | DRagLint.Doc.Regions.pas:42 |
| DRagLint.Doc.Regions | DRagLint.Doc.SharedFacts | implementation | DRagLint.Doc.Regions.pas:933 |
| DRagLint.Doc.SharedFacts | DRagLint.Doc.Regions | implementation | DRagLint.Doc.SharedFacts.pas:446 |
| DRagLint.Doc.SharedFacts | DRagLint.Doc.ProjectTags | implementation | DRagLint.Doc.SharedFacts.pas:447 |

No intra-group `uses` entry exists in the source that the chart does not draw.
The set is pinned in `src\Test-Emitters.ps1` (`A-CY2-EDGESET`).

## What the chart claims, and why

* **"interface coupling: 1 of 7 uses interface-section; every loop crosses an
  implementation use".** The verb flags the group `interface_cycle:true`, which
  means only that ONE intra-group edge is interface-section. A loop made only of
  interface uses is what the compiler refuses (F2047); this group has none, and
  the project builds. Before R3 the chart said "interface cycle" here.
* **The one red arrow is Regions -> Facts (:42);** the six amber ones are
  implementation uses. Before R3 every arrow in the group was red.
* **Each row anchors to that unit's FIRST intra-group uses entry** -- SharedFacts
  at :446, not :447 (before R3 it followed the verb's member order).
* The chart makes no "break here" suggestion of its own; `-Playbook` would add
  the engine's `cycles --plan` status line.

## Regenerate

```
cd <repo>\charts
.\src\New-DiagramArtifact.ps1 -Question cycles -Target project -DbPath <abs>\scratch\db\DL-drag-lint.sqlite -OutRoot <abs>\docs\examples\cycles
```
