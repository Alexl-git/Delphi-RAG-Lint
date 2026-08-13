# Spec: doc-drift must not call a SHARED unit's facts block stale for facts a narrower project cannot see

Owner design, 2026-08-13. Supersedes the "union regeneration" sketch discussed
the same day, which was more expensive and less targeted.

## The problem

`YADF.Options.pas`, `YADF.Layout.pas` and `YADF.OptionsFrame.pas` are compiled by
THREE projects (`YADF.dproj`, `YADFOT.dproj`, `YADFSetup.dproj`), each with its
own index. A managed facts block contains two different kinds of fact:

| kind | examples | property |
|---|---|---|
| **intrinsic** | `Calls:`, `Reads:`, `Writes:`, `Returns:`, `Complexity:`, `Mutates:`, `<param>` types | computable from the unit alone -- ONE right answer |
| **inbound** | `Called from:`, `Used by:`, `Used in units:`, `<seealso>` | depends on WHO IS LOOKING -- a narrower project truthfully sees fewer |

`TDocDrift.Analyze` decides staleness with a whitespace-collapsed **byte
compare** of the stored block against a freshly rendered one
(`DRagLint.Doc.Drift.pas`, the `ddFactsBlockStale` branch):

```pascal
var Fresh: string := TDocRegions.RenderFactsBlock(Facts, '', IncludeRet);
if CollapseAllWhitespace(CurBlock) <> CollapseAllWhitespace(Fresh) then
  Findings.Add(MakeFinding(ddFactsBlockStale, 'managed facts block is out of date', True, DocLine));
```

So a block written while project A's index was open is reported stale by project
B, whose closure genuinely contains fewer callers. Documenting per project then
makes the three projects overwrite each other's inbound lists, turn by turn --
the oscillation observed as `(+8 more)` <-> `(+7 more)` churn on the same
declaration.

This is the fourth incident on the writer-vs-checker seam. The previous three:
the `<seealso>` flag mismatch (514 false findings), the `Covered by:` oscillation
(2026-08-11), and `document --project`'s batch planner reporting "nothing to
document" while the per-symbol repair path found 23 real edits (2026-08-13).

## The rule

Staleness becomes a STRUCTURED comparison rather than a byte compare.

1. Split both blocks into fact lines, and each inbound fact line into entries.
2. **Intrinsic facts: unchanged semantics.** Any difference is drift.
3. **Inbound facts:** compute the entries present in STORED but absent from
   FRESH. Such an entry is FORGIVEN -- it does not make the block stale --
   only when ALL of the following hold:
   - the declaring unit is **shared** (see below); AND
   - the entry names a unit that is **not in the current project's closure**; AND
   - the entry is **`certain`** -- rendered WITHOUT the trailing `' ?'`.
4. Entries present in FRESH but absent from STORED are always drift (the block
   is genuinely missing something the current project can see).

### The rendering already carries what step 3 needs -- do not change it

Every inbound entry already names its unit in parentheses, same-unit entries
included:

```
Called from: YADF.Groups.ParseGroups (YADF.Groups.pas), YadfMain.DebugTree (YadfMain.pas)
Used by:     declaration (YADF.Debug.pas), YADF.Guard.ExtractContent (YADF.Guard.pas)
```

So "is this entry from a unit outside my closure?" is answerable from the stored
text with no format change. Dropping the unit for same-unit entries was
considered and rejected: it buys nothing the checker needs, and re-rendering
every block to a new shape would report mass drift across all four projects for a
cosmetic change -- manufacturing the exact problem this spec removes.

### Why the `certain` condition is load-bearing

`DRagLint.Doc.Facts.pas` renders a trailing `' ?'` for any confidence other than
`certain`/`''` -- `ambiguous` (resolved but >1 candidate on the type chain) and
`unverified` (receiver untypable).

Every fabricated entry removed from YADF on 2026-08-13 carried `' ?'`:

```
Called from: YADF.Groups.ParseGroups (YADF.Groups.pas),
             Test1_InsertsPreserved (TestCachedUpdates.dpr) ?,     <-- an ORM3 test project
             Test2_MixedOpsPreserved (TestCachedUpdates.dpr) ?, ... (+7 more)
```

while the genuine cross-project entries are plain
(`uYADFSetupMain.TfrmMain.FormCreate (uYADFSetupMain.pas)`).

Those `?` entries are name-collision noise from a run that consulted too wide a
set with name-keyed matching. **A blanket "ignore entries naming other units"
rule would have forgiven them permanently** -- it would have preserved exactly
the garbage this change is meant to keep out. Restricting tolerance to `certain`
entries keeps the rule tolerant of real cross-project facts and intolerant of
guesses.

**Calibration, measured 2026-08-13 -- this condition is insurance, not the load
bearer.** Those references were never in YADF's database:

```
> drag-lint query --name Test1_InsertsPreserved --exact --db YADF.sqlite            -> 0 match(es)
> drag-lint query --name TdxRibbonMinimizeButtonPopupMenuController --exact --db ... -> 0 match(es)
grep -c 'TestCachedUpdates|dxRibbon|FMX.ListBox' YADF\*.pas                          -> 0
```

They existed only as stale TEXT in the `.pas` files, written by a run from the
union-DB era before the per-project split, and the 2026-08-13 `--fix --apply`
cycle removed the last of them. **The per-project database split already prevents
this class from being generated** -- a project index cannot contain another
project's symbols, so there is no cross-project name to collide with. Keep the
`certain` test anyway: it still discriminates `unverified` entries (untypable
receiver) arising WITHIN a project, and it costs one string test.

### Determining "shared" -- a UNIT-LEVEL MARKER, not derivation

An earlier draft of this spec said to derive it, on the theory that
`resolve-dbs --in <file>` already answers which DBs cover a file. **Measured, it
does not.** It resolves the OWNING database, one answer:

```
> drag-lint resolve-dbs --in C:\Projects\YADF\YADF.Options.pas
C:\Projects\YADF\_D-RAG\YADF.sqlite
```

-- even though `YADFOT.dproj` and `YADFSetup.dproj` both compile that unit.
Deriving the SET would mean opening every project index in the manifest and
asking each whether it contains the file: a new capability, N database opens per
run, for a fact that changes about once a year.

So the unit declares itself, with a marker in the same family as the `dl:ok`
review marker:

```pascal
unit YADF.Options;   // dl:shared YADF, YADFOT, YADFSetup
```

* Unit level, anywhere in the unit's header region. It must NOT be required on
  line 1 -- line 1 of a unit here is frequently the `{` of a block comment, which
  is the anchoring trap already recorded for `unit-too-large` and
  `compiler-magic-comments`.
* **The project list is part of the marker, not decoration.** It states the
  blast radius in the source, readable without running the tool -- which is the
  point of the feature (below) -- and it lets drag-lint VERIFY the claim rather
  than trust it.
* **Verification, following the `allow` round-trip precedent** (which refuses to
  write a marker that cannot be read back): warn when a listed project does not
  in fact compile the unit, and when an unlisted project does. A marker nobody
  checks decays into a lie, and this one is load-bearing for staleness.

## Why the inbound facts are the POINT, not an inconvenience

Owner framing, and it changes what this feature is for. A cross-project inbound
entry is the ONLY place the cross-project reach of a shared method is written
down -- by construction, since no single project's index can see it. It is what
tells a human, or an AI asked to change a shared method, that the blast radius
extends past this project.

The measured case: `SaveOptionsToIni` is reported `unused-public-symbol` by
`YADF.dproj` while having 15 call sites in `YADF.OptionsFrame.pas`, which only
YADFOT and YADFSetup compile. See
`INBOX-cross-project-symbol-use-defeats-single-project-rules.md`.

So the rule is not "tolerate a difference". It is **preserve the only record of
something true**, which is the same principle already established after the
`Covered by:` incident: a fact that cannot be computed from the configured index
must be preserved, not stripped, because deleting it destroys information nothing
else in the corpus holds.

## What this does NOT change

* The WRITER still renders from the current project's index only. No sibling DBs
  are opened, no facts are merged, no provenance markup is introduced. A
  narrower project still writes a narrower block -- it is simply no longer told
  that block is stale.
* Intrinsic facts keep byte-compare semantics.
* Non-shared units keep byte-compare semantics for inbound facts too.

## Acceptance

A fixture with one shared unit compiled by two project DBs, asserting:

1. **All projects agree.** After `document --apply` under project A, `lint-all`
   under project B reports NO `doc-drift` on the shared unit -- and vice versa.
   This is the assertion that would have caught all four incidents on this seam.
2. **A `?` entry is still drift.** A stored block carrying an out-of-closure
   entry rendered with `' ?'` IS reported stale, and the repair removes it.
3. **A real deletion is still drift.** Remove a caller that IS in the current
   closure; the block must be reported stale.
4. **Intrinsic drift is unaffected.** Change a parameter type; still stale.
5. **Non-shared units are unaffected.** A unit in exactly one project keeps
   today's behaviour exactly.
6. **Idempotence.** `document --apply` twice on the shared unit produces no
   second edit, under either project.

## Notes for the implementer

* Do the work in `TDocDrift.Analyze`'s `ddFactsBlockStale` branch. Both the
  checker (`RunDocDrift`) and the fix path (`FixEditsForDocDrift` ->
  `TDocumenter.BuildFor`) must agree, or this becomes incident five: the fix
  path must not "repair" a block the checker now considers current.
* `document --project`'s batch planner is separately buggy (it reported "nothing
  to document" on 23 decls the per-symbol path repaired). Do not build on its
  answer; fix or bypass it.
* The autofix guard reports `applied 11 fix(es) across 0 file(s), 22 skipped
  (stale index)` and the skip count never clears across reindexes -- two more
  defects on the same path, worth resolving before measuring this change.
