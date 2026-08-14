# Shared-unit caller lists: per-project attributed segments

**Owner decision, 2026-08-13.** Supersedes the open `docs.max_callers` question
left by `RESUME-2026-08-13d` ("raise the cap OR teach the merge to reconcile
truncated lists -- owner decision, not taken").

## The problem, measured not theorised

A unit that is a member of several projects gets its managed fact block
rewritten by whichever project ran `document` last, because the facts are
computed from THAT project's compile closure. Measured today on
`YADF.Tokens.pas`:

    YADF   writes: Used by: declaration (YADF.Debug.pas), declaration (YADF.Groups.pas), ... (+6 more)
    YADFOT writes: Used by: declaration (YADF.Groups.pas),  YADF.Guard.ExtractContent ... (+5 more)

Autofixing YADFOT's 2 `doc-drift` findings took YADFOT 12 -> 10 and pushed
**YADFSetup 12 -> 14**. The projects fight over one line, forever.

### The trap: it is NOT just the number

The obvious reading is that `(+N more)` churns because N differs. It does -- but
`declaration (YADF.Debug.pas)` also drops out of the NAMED portion, because
`YADF.Debug.pas` is a member of YADF and YADFSetup but not of YADFOT.

**So "drop the count, keep the names" does not fix this.** Any design that
stabilises only the tail marker still churns on the names. This killed the
cheapest variant and is the single most important fact in this spec.

The union merge shipped in `57b0be4` already handles the non-truncated case. It
refuses truncated lists on purpose -- a window onto a list is not the list, and
unioning two different windows invents a third that was never true.

## The decision

**Each project owns its own segment of the fact line. No project ever rewrites
another's.**

    /// <!-- drag-lint:auto BEGIN -->
    /// Used by:
    ///   YADF: declaration (YADF.Debug.pas), declaration (YADF.Groups.pas) (+10 more)
    ///   YADFOT: YADF.Guard.ExtractContent (YADF.Guard.pas) (+5 more)
    ///   YADFSetup: YADF.Layout.NormalizeOperatorSpacing (YADF.Layout.pas) (+7 more)
    /// <!-- drag-lint:auto END -->

Rejected alternatives, and why:

* **Raise `docs.max_callers` so nothing truncates.** Cheapest (zero engine code
  -- the existing union merge then just works), but it only postpones: it fails
  again the first time a shared unit exceeds the new cap, and it silently
  lengthens every fact line in every project.
* **`(+more)` with no number, and freeze the line.** Ends the churn outright,
  but the frozen line goes stale as callers are added, and it makes the first
  project to run the winner -- an arbitrary authority the rest of the design
  works hard to avoid.

The chosen design is the most engine work of the three and produces the longest
lines. It was chosen because it is the only one that stays TRUE as projects are
added, and because attribution answers a question the flat list never could:
*which project sees this caller?*

## Why this is consistent with the DB-role ruling

`specs/2026-08-13-db-authority-and-freshness.md` established that DESTINATION is
a third axis: a fact may be shown but not written. Per-project segments are the
same principle applied to authorship -- a project may write only what its own
compile closure proves. A segment is a claim scoped to its prover.

## Implementation notes

1. **The writer must know which project it is.** Today's fact rendering is
   project-agnostic. The segment key should be the manifest SECTION name (`YADF`,
   `YADFOT`), not the DB filename and not the folder -- five folders host 2-3
   projects, and the section name is what `--only` already uses.
2. **Rewrite exactly one segment.** Parse the block, replace the line whose key
   matches the current project, leave every other line byte-identical, re-emit.
   Segment order should be stable (alphabetical) so a reordering never shows up
   as a diff.
3. **`doc-drift` must compare only the current project's segment.** Otherwise
   every project reports drift on every other project's line -- the current bug
   with extra steps.
4. **Only for shared units.** A single-project unit keeps today's flat rendering;
   `TSharedUnit` already answers this (and per RESUME-2026-08-13d still reads the
   file on every call -- cache it while in here).
5. **Migration.** Existing flat blocks must be readable. Simplest: on first write
   by project P, convert the flat line into a single `P:` segment and let the
   others populate as they run.

## Tests this needs

Per the fixture trap already paid for twice in this area (a fixture whose block
ends with `Pure` cannot catch a slice overrun; expectations are line-anchored, so
new cases go LAST):

* three projects sharing one unit; run document in all 6 orders; assert the file
  is byte-identical at the end of every order. **Order-independence is the whole
  point of the feature and is the assertion that would have caught this class in
  the first place.**
* a project whose segment is empty (no callers in that closure) -- must the
  segment be omitted or written as empty? Omitting hides the difference between
  "not run" and "no callers"; decide and test it.
* drift on project A's segment must not be reported when running project B.
* migration from a flat block.

## Not covered by this spec

The autodoc backlog this does NOT touch, and which gates any corpus-wide
`--apply` more than truncation does:

* `INBOX-autodoc-caller-list-fabricates-callers-for-common-method-names.md`
  (severity high -- writes a false claim that reads as verified)
* `INBOX-document-qname-second-apply-nests-block-on-stale-anchor.md`
* the UNEXPLAINED block duplication seen 2026-08-13 when a stray autodoc run
  produced two `<remarks>` for `ResolveProfileIniPath` and orphan blocks with no
  declaration attached in `YADF.Groups.pas` / `YADF.Tokens.pas`. Patch saved at
  `scratchpad/rogue-autodoc-2026-08-13.patch`. Same family as the stale-anchor
  note; never reproduced deliberately.
