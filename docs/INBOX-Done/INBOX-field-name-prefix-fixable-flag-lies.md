> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21). RE-DIAGNOSED, then fixed as a MESSAGE defect.**
>
> The note says the rule advertises fixable and then refuses. Measured: the rule IS in `FIXABLE_RULE_IDS`, the catalog does say `"fixable": true`, and the fixer **works** -- with `"autofix": ["const-casing"]` in the config it rewrote `badConstName` -> `BadConstName` and reported `applied 1 edit(s)`. Naming fixes are deliberately OPT-IN because they rewrite call sites project-wide (see the comment at the `Cfg.IsAutoFix` gate).
>
> **Two measurement errors were made proving this, both worth remembering.** First, `--fix` printed `no fixable findings` and that was taken at face value. Second, the follow-up check used PowerShell `-ne` on the file text, which is **case-INSENSITIVE**, so a fix that changed only letter case read as "file unchanged" -- the tool was working and the test said it was not.
>
> **Fixed** (message, not behaviour): `--fix` now emits `note: N naming rule(s) here are fixable but NOT opted in: <ids> ... add them to "autofix": [...]`. The remaining true defect -- that the catalog's `fixable` flag is unconditional and does not mention the opt-in -- is recorded in the triage doc.

# `field-name-prefix` advertises `fixable: true` and then refuses to fix

Plan Task 6 recorded this as "one of the two is lying". Confirmed 2026-08-13, and
the obvious suspect was eliminated.

> **UPDATE 2026-08-13 (later session): `local-var-casing` does the SAME thing.**
> This note previously said (below) that `local-var-casing` "is `fixable: true`
> and does work". **That was never tested and it is FALSE.** On YADFOT:
>
>     > drag-lint lint-all --project C:\Projects\YADF\YADFOT.dproj ^
>         --fix --fix-rule local-var-casing
>     autofix: no fixable findings (of 7 finding(s))
>
> Identical refusal, identical unhelpful message. So **2 of 2 naming rules ever
> checked advertise a fix they do not have** -- which kills hypothesis 2 below
> (a never-met gate on one rule) and promotes hypothesis 1 to the working
> explanation: the `fixable` flag was set by copy-paste and is decorative.
>
> The 7 findings were real and worth fixing; they were done BY HAND
> (YADF `91d1f21`, case-only, YADFOT 35->28 and YADFSetup 24->17).
>
> Raises the priority of the walk-every-fixable-id test proposed below: with a
> 0-for-2 hit rate, the remaining 19 `fixable: true` rules should be treated as
> false until each is exercised.

## Reproducer

    > drag-lint rules --json          ->  { "id": "field-name-prefix", "fixable": true }
    > drag-lint lint C:\Projects\YADF\YADF.Groups.pas --fix --fix-rule field-name-prefix
    autofix: no fixable findings (of 2 finding(s))

## It is NOT a stale or wrong index

That was the leading hypothesis, because the same command also prints
`index schema v19 < v21` and the naming autofixes are index-dependent (there is a
dedicated stale-index guard, `tests\autofix\run_fix_stale_index_guard.ps1`).

Ruled out by test. The v19 warning comes from a DIFFERENT defect -- a bare
`lint <file>` opens the manifest's first index rather than the one containing the
file, see `INBOX-lint-single-file-opens-wrong-index.md`. Passing YADF's own
freshly rebuilt index explicitly:

    > drag-lint lint ...YADF.Groups.pas --fix --fix-rule field-name-prefix ^
        --db C:\Projects\YADF\_D-RAG\YADF.sqlite
    autofix: no fixable findings (of 2 finding(s))

Same answer. The refusal is independent of which index is open.

## So one of two things is true

1. The catalogue entry is wrong -- no autofix was ever implemented for this rule,
   and `fixable: true` was set by copy-paste from a sibling naming rule.
   **Most likely -- and now the surviving explanation, see the UPDATE above.**
   (This clause originally read "`local-var-casing` is `fixable: true` and does
   work". Struck: it was an assumption, and testing it showed the opposite.)
2. An autofix exists but is gated by a condition that is never met here, and
   reports the generic "no fixable findings" instead of naming the gate.

Either way the message is the second defect: "no fixable findings (of 2
finding(s))" tells the caller nothing about WHY two findings of a rule
advertised as fixable produced no fix.

## Wider risk -- treat the whole flag as unproven

`rules --json` reports **21 of 172** rules as fixable. Exactly one of them has
been checked. Until each is exercised, the flag is a claim, not a fact, and
anything that drives automation off it (an IDE "Fix all", a CI autofix job) is
building on it.

Cheapest useful guard: a test that walks every `fixable: true` id, lints a
fixture that trips it, runs `--fix --fix-rule <id>`, and asserts the file
actually changed -- or that the rule is honestly demoted to `fixable: false`.
That converts a 172-row claim into 21 checked ones.

## Also noticed in the same output

`rules --json` emits an empty `severity` for every rule, while the catalogue
plainly carries severities (`field-name-prefix` is info; `doc-drift` is warning).
Either the JSON projection drops the field or it is being read from the wrong
place. Not chased.
