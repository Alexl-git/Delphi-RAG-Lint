> **RETIRED to INBOX-Done/ on 2026-08-15.** ADOPTED, not merely fixed: this became the standing owner ruling now recorded in C:\Projects\CLAUDE.md (AUTHORITATIVE SET = platform library + project DB, authority is per-QUESTION not per-database, a stale DB is not authoritative).
>
> Original note follows unchanged.

# Owner ruling 2026-08-13: DB authority is Project DB + Platform Library, nothing else

> **Status:** RULED, NOT YET IMPLEMENTED. There is a real interaction with
> `8abcc3e` that must be settled first -- see "The trap" below. Do not implement
> the ruling without reading it.

## The ruling, in the owner's terms

> "The real situation that holds reliable and workable information is Platform
> Library + Project DB. The rest provides noise and misleading information. We
> need to treat these 2 DB as the authoritative, provided the project DB is
> fresh. Any other DB should be treated with suspicion and maybe even for now
> not allowed."

So the authoritative set for any consumer query is exactly:

1. **the project's own DB** -- `<project folder>\_D-RAG\<project>.sqlite`, and
2. **the platform library DB** -- `C:\Projects\.drag-lint\library-<Platform>.sqlite`

Every OTHER database -- principally another project's DB -- is noise. For now,
disallow rather than merely deprioritise.

## Why this came up

`document --project YADFOT.dproj` wrote this into shared source:

```
Used in units: dxXMLWriter, FireDAC.Comp.QBE, Spring.Data.ExpressionParser,
               System.Bindings.Evaluator, System.JSON, XPTestedUnitParser, ...
```

where the project renders four real units. `OpenExtraStores` called
`ResolveConsumerDbs`, which AUTO-RESOLVES THE WHOLE MANIFEST when no `--db` is
given, so a run scoped to one project searched every index on the machine.

## THE TRAP -- read before implementing

**Every one of those junk names came from the PLATFORM LIBRARY DB** -- the very
database this ruling calls authoritative. The library index is not itself wrong;
it correctly indexes the RTL/VCL/DevExpress/Spring surface. What was wrong is the
QUERY: the `Used in units:` bucket (`Doc.Facts.pas:1947`) does a bare
`FindCallersByName(LastSeg(QualifiedName))` against every extra store **with no
ambiguity gate at all**, unlike its `Called from:` sibling at `:1669`, which
requires `NameUnambiguous and LeafNameNotAmbiguous` and marks every hit
`unverified`.

So "authoritative" has to be read per-QUESTION, not per-database:

| Question | Project DB | Platform Library |
|---|---|---|
| Which unit declares symbol X (`find-unit`, type resolution) | yes | **yes -- this is what the library DB is FOR** |
| What are this symbol's callers / used-in-units (doc facts) | yes | **NO -- a name match against the RTL is not a caller** |

`8abcc3e` currently fixes this by making the fan-out explicit-`--db` only, which
happens to exclude the library DB too. That is why the three YADF projects now
converge. **Adding the library DB back as an extra store re-introduces the junk
unless the ungated bucket is gated first.**

## Implementation order that does not regress

1. **Gate `Used in units:`** at `Doc.Facts.pas:1947` the way `Called from:` is
   gated at `:1669`, or exclude extra stores from that bucket outright. Prove it
   by re-running the YADF/YADFOT/YADFSetup cycle and showing the fixed point
   holds (currently YADF 12 / YADFOT 35 / YADFSetup 24, doc-drift 4/2/0).
2. **Then** implement the ruling in DB resolution: restrict the resolved set to
   {project DB, platform library DB}; reject anything else with a named error
   rather than silently dropping it, so a user who passes another project's
   `--db` learns why.
3. **Freshness gate.** The ruling says "provided the project DB is fresh". There
   is no freshness check on the consumer path today. Decide what stale means
   (mtime vs source? schema version? a recorded index run?) and what happens when
   it fails -- refuse, warn, or auto-reindex. Not designed yet.

## Open question the ruling does not settle

Explicit multi-`--db` is the deliberate CROSS-PROJECT case: an ORM3 `COMMON`
reference surfaces only because a second project's DB was passed
(`Doc.Facts.pas:1661-1705` documents this as its whole reason for existing). The
ruling says other DBs are "maybe even for now not allowed". If that includes
explicit `--db`, the cross-project caller feature dies -- which may be correct
(it is unverified-by-construction), but it should be a deliberate retirement, not
a side effect. **Ask before removing it.**

## Related

* `8abcc3e` -- the fan-out fix this ruling extends.
* `docs/RESUME-2026-08-13d-shared-unit-docs-and-menu.md`.
* CLAUDE.md still tells agents to pass several `--db` for cross-project
  questions. If the ruling lands, that guidance changes too.
