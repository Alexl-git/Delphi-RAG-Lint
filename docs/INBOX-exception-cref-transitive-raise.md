> **CONFIRMED 2026-08-16 (session 21) with a worked example, and it is costing more than this note claims.**
>
> `DRagLint.FormsMap.pas:76` documents `<exception cref=""Exception"">` on the SINGULAR `GenerateFormsCsv` overload (declared `:95`). Its implementation at `:1561` is exactly one line -- `Result := GenerateFormsCsv([ADbPath], AProjectFile, ARootForm);` -- and the `raise Exception.Create('forms-csv: no DB paths')` is at `:1545`, inside the ARRAY overload it delegates to. The documented exception is real for any caller; the checker reports *""the body never raises it""* because it inspects only the routine's own body.
>
> **Scope, measured:** this accounts for **3 of the 6** doc-drift findings that survive a fully converged autodoc on our own source (`Project.Resolver.pas:231` and `:256` are the other two). Fixing it would halve that residue -- see `INBOX-docdrift-4-survive-a-converged-autodoc`.
>
> A one-line delegating overload is the cheapest possible case to handle: follow a body that consists of a single call, one level.

# INBOX -- `<exception cref>` is graded body-locally, so a DELEGATING routine is reported

Filed 2026-08-10. Follow-up to commit `176cfb9`, which closed the BODYLESS half of
this rule. Owner ruling that day was explicitly **"skip bodyless decls only"** --
the three sites below were left open on purpose, because deciding how far the rule
should look is a design question, not a bug fix.

## The rule

`DRagLint.Doc.Drift.pas`, finding `ddExceptionNotRaised`:

    documented <exception cref="X"> but the body never raises it

It compares the documented crefs against `Facts.Raises`, which
`TDocFactsBuilder.Build` mines by scanning the source lines from
`ASym.ImplStartLine` to `ASym.ImplEndLine` for `raise <Ident>`. That is
**body-local and one level deep**. The documented contract is about the
exceptions a caller can actually observe, which is a TRANSITIVE property.

## The three surviving sites (drag-lint's own corpus)

| Site | Where the raise really is |
|---|---|
| `TProjectResolver.Resolve` (`DRagLint.Project.Resolver.pas:230`) | `CollectProjectFolders` -- `raise Exception.CreateFmt('.dproj not found: %s', ...)` at `Resolver.pas:711` |
| `TProjectResolver.ResolveProjectOnly` (`Resolver.pas:255`) | same callee, same raise |
| `GenerateFormsCsv` (single-path overload, `DRagLint.FormsMap.pas:75`) | delegates to the `TArray<string>` overload, which raises at `FormsMap.pas:1484`; the documented "index cannot be opened" case is deeper still |

All three document their exception CORRECTLY. A caller of `Resolve` really can
see that `Exception`. The rule is wrong, not the documentation.

## Reproduce

    drag-lint doc-drift --qname DRagLint.Project.Resolver.TProjectResolver.Resolve \
      --db C:\Projects\.drag-lint\DragLint-Cli.sqlite --json

Expected: no `ddExceptionNotRaised`. Actual:

    {"kind":"ddExceptionNotRaised","detail":"documented <exception cref=\"Exception\"> but the body never raises it",...}

Note the JSON field is `detail`, not `message` (`lint-all --json` uses `message`).
Reading the wrong one yields nulls and makes a "reports nothing" assertion pass
vacuously -- that cost a full RED/GREEN cycle while writing
`tests\autodoc\run_doc_ctor_bodyless.ps1`.

## Options considered at ruling time

1. **One-hop callee union** -- satisfy the cref when a DIRECTLY called routine
   raises that type. Clears all three. Needs the ref graph inside the drift
   checker (`GetCallEdgesFromSymbol` is already reachable -- `TDocFactsBuilder`
   uses it for `SeeAlso`), and still misses two-hop cases like `GenerateFormsCsv`'s
   documented "index cannot be opened", so it would half-fix that one.
2. **Stop grading pure delegators** -- never fire when the body's only
   substantive statement is a call. No graph walk, but "is a delegator" is a
   fuzzy test that will misjudge borderline bodies.
3. **Transitive closure with a depth cap** -- the honest model of what a caller
   observes. Most expensive; also most likely to make the rule useful rather than
   merely quiet.

## The trap in ANY of them

`Exception` (the base class) is documented at two of the three sites. A
transitive union will make `Exception` "raised" almost everywhere, because
something down almost every call chain raises something. Whatever shape is
chosen, decide separately whether an ancestor cref is satisfied by a DESCENDANT
raise -- and note that `SameText(RC, DE.TypeName)` is an exact name compare
today, so `EFoo` does NOT currently satisfy a documented `Exception`.

## Why this was not just fixed

Absence over a wrong verdict. A rule that silently accepts any cref because
something somewhere raises is worse than one that over-reports three known
sites: the first cannot be audited, the second is a list of three.

## Implementation note (2026-08-16, session 21) -- the cheap fix is WRONG, do not take it

The tempting fix is to reuse the carve-out already sitting directly above this
check in `Doc.Drift.pas`, which skips grading when the declaration has no body
on the grounds that the rule *""was not observing an absent raise; it was
observing that it had never looked""*. A delegating body is arguably the same
situation, so: skip when `Facts.Raises` is empty and `Facts.Calls` is not.

**That would gut the rule.** *""Calls something and raises nothing itself""*
describes the majority of routines, so the tag would stop being graded almost
everywhere -- trading three false positives for a rule that no longer works.
Narrowing it to `Length(Facts.Calls) = 1` is better but still arbitrary: a
routine that happens to call exactly one helper is not necessarily delegating.

**The correct fix resolves the callee.** `TDocFacts` carries both `Calls` and
`Raises`, and `TDocDrift.Analyze` already receives `AStore`, so the pieces
are present: for each name in `Facts.Calls`, resolve it and ask whether ITS
body raises the documented type; accept the tag if any does. One level is enough
for all three known cases -- each is a one-line delegation.

Cost is the reason it was not done in this session: it needs per-callee facts (or
a store query for raises) inside a checker that currently does no such lookup,
and doing it badly would be worse than the three findings it removes.
