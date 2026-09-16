# URGENT TODO — drag-lint has no authoritative record of which framework a unit uses

Raised 2026-07-29, from the proptree ancestor-scope work (branch `feat/proptree-ancestor-scope`).
Filed at the user's explicit instruction: *"The project or maybe even single forms have a statement
(or record or selection) somewhere what framework is used. First investigate where to get this
information. If you won't succeed put it on urgent TODO and infer from the ancestry."*

The investigation was done. **No authoritative source is reachable from where `proptree` runs.**
The ancestry fallback was implemented as ruled. This TODO records the proper fix.

## Why it matters

When a type name is ambiguous across frameworks — `TFont` exists as both `Vcl.Graphics.TFont` and
`FMX.Graphics.TFont`, likewise `TPopupMenu`, `TCustomImageList` — the resolver must pick one. With
no framework record it can only infer. Today it declines on legacy pre-namespace units, which costs
the conversion editor real mappable surface: on `Abcbtn.TabcToggleBtn`, `PopupMenu` (757 leaves),
`Images` (214) and `Font` (14) degrade from class-typed to scalar.

## What exists, and why none of it is reachable

### 1. `.dproj` `<FrameworkType>` — real, authoritative, unparsed

Confirmed in every real project on this machine, e.g.
`C:\Projects\DB\ORM3\CLIENT\Micronite2027.dproj:5` → `VCL`. Observed values: `VCL`, `None`.

drag-lint does not read it. `src/project/DRagLint.Project.Resolver.pas:316-345`
(`TProjectResolver.ReadDProj`) regexes only four unrelated `DCC_*` path tags out of a `.dproj`.

Even if parsed, it is **project-scoped**, and the library index has no project concept: no
`projects` table, no per-file project-association column — schema verified identical in
`library-Win64.sqlite` and the project index `ORM3\drag-lint.sqlite`. The index manifest
(`third_party/dll-win64/drag-lint.json`) carries nothing framework-shaped either.

`Abcbtn.pas` is third-party *library* source shared by whichever project happens to use it. It has
no `.dproj` of its own, so a project-level value would not intrinsically describe it.

### 2. `.dfm` vs `.fmx` sibling file — real, but one-sided and form-only

VCL forms pair with `.dfm`, FMX forms with `.fmx`. drag-lint already does this style of
sibling-file probe by naming convention for `symbol_facts.dfm_event`
(`docs/INDEX-SCHEMA.md:427-442`); there is no `paired_dfm_id` column.

Live counts: `library-Win64.sqlite` has **743 `.dfm` and 0 `.fmx`**; `ORM3\drag-lint.sqlite` has
69 `.dfm`. So in this corpus the signal can only ever say "VCL" or "no signal" — it can never
positively identify FMX — and it applies only to *form* units. `Abcbtn.pas` is a
component-registration unit with no paired form file.

### 3. Open Tools API — correct, but IDE-only

`IOTAProject.GetProjectProperty('FrameworkType')`, and per-module `.dfm`/`.fmx` inspection via
`IOTAModuleInfo.GetFileName`, both give the answer directly. They require a live RAD Studio
process. `proptree` runs headless as a CLI against a SQLite index, so OTA is unavailable at query
time — though it IS available to the design-time plugin BPL and could be used there.

### 4. `unit_uses.unit_name` vocabulary — an inference, not a declaration

Reachable from the library index with zero project context. `Abcbtn.pas`'s uses are 100 % bare
pre-namespace VCL names (`Controls`, `Forms`, `Graphics`, `Menus`, `ImgList`) with zero `FMX.*`.
Suggestive, but corpus convention rather than a statement of intent.

## Proposed fix

1. **Parse `<FrameworkType>` in the `.dproj` reader** (`src/project/DRagLint.Project.Resolver.pas`) and carry
   it into the index. Cheapest real win: it makes project-scoped queries authoritative.
2. **Add a per-file framework column** (or a `symbol_facts` fact) so the value survives into the
   index and is readable at query time without the `.dproj` at hand. Note this is a schema change
   and therefore out of scope for the branch that raised it, which is bound to "no schema change".
3. **Record the paired form file's extension per unit** while indexing — `.dfm` → VCL, `.fmx` →
   FMX. This is the per-form signal the user suspected exists, and it needs no `.dproj`.
4. Keep the ancestry inference as the fallback for library units that have neither.

## What was shipped instead, meanwhile

Framework inference from the type's own ancestor chain: climb to the nearest hop whose unit carries
a dotted `Vcl.`/`FMX.` prefix and anchor the scope rule on that segment, instead of declining at an
undotted legacy unit. See the proptree ancestor-scope spec and
`src/report/DRagLint.Convert.PropTree.pas`.
