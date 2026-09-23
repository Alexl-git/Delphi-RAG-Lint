# fix-deps-measure -- measurements (2026-09-23)

DB: C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite (read-only; python `mode=ro` on a scratch copy for the ref scans).
Exe: merged C:\Projects\Delphi-RAG-lint\src\cli\Win64\Debug\drag-lint.exe unless stated.

## D5 arithmetic (deps-report)

Simulated "before EurekaLog" by deleting the 13 `{$IFDEF EurekaLog}` program-section rows of Micronite2027.dpr
in a scratch copy (12 unresolved + EExtraExceptionInfo -> file 625).

| build | edges | ext units | unresolved | used_by sum |
|---|---|---|---|---|
| old, no Eureka | 30,702 | 283 | 283 | 20,138 |
| old, Eureka    | 30,716 | 293 | 293 | 20,151 |
| new, no Eureka |  6,868 | 283 | 283 |  6,868 |
| new, Eureka    |  6,880 | 293 | 293 |  6,880 |

Old +14 edges = +17 new rows - 3 vanished:
- +12 direct program edges (the 12 unresolved rows),
- +5 root-credited transitive edges via EExtraExceptionInfo: ETypes, EEvents, ECompatibility, and Classes/SysUtils again
  (a name was noted at ENQUEUE but marked visited only at DEQUEUE, so it could be noted twice),
- -3: micronite2027->EBase (x2, a duplicate) and ->EDialogWinAPIEurekaLogDetailed used to be emitted at depth 2-3; now depth 1 visits them first.
Old +13 used_by = 10 brand-new externals credited to micronite2027 + 3 (ETypes/EEvents/ECompatibility gained micronite2027);
EBase/EDialog...Detailed already had micronite2027 through a depth<=3 chain.
+12 = unresolved unit_uses ROWS (the charts team's number); unresolved EXTERNAL UNITS moved +10.
New: every counter moves +12 (edges = used_by sum = distinct (file, unit) unresolved pairs: 6,880 by SQL).

## CH-4: member access inside `with` bodies

With spans: 375 `with-statement` findings (lint-all), span = whole statement (verified by reading).
Scope: refs in the files that contain a with.

| zone | kind | n | bound | member_accesses rows |
|---|---|---|---|---|
| inside (incl. single-line headers) | member-access | 283 | 0 (0%) | 0 |
| inside, multi-line BODY only | member-access | 162 | 0 | 0 |
| outside, same files | member-access | 14,818 | 3,212 (21.7%) | 2,854 |
| inside | bare read | 4,605 | 0 | 0 |
| outside | bare read | 37,589 | 444 (1.2%) | 0 |
| inside | bare call | 79 | 10 (12.7%) | 0 |
| outside | bare call | 3,742 | 803 (21.5%) | 0 |
| inside / outside | bare write | 4,336 / 17,803 | 0 / 0 | 0 (DB-wide: 32,909 write refs, none carries symbol_id) |

Twin test (same file, receiver, member, enclosing routine outside the with): 0 twins bound, so the gap cannot be proven
to be the with alone. 10 samples read: 5 were the with HEADER expression (`with CbxSIP3.Properties.Items.Add do`),
3 had a with-member as receiver (`Font.Color` in `with Entity as TsgDXFText`, `PageHeader.LeftTitle.Strings` in `with dxPrinter`),
2 a param of a library type (`PForm.Caption`). src\resolver has no with-scope handling at all.
Answer: no -- member accesses inside with bodies are not bound (0 of 283, 0 member_accesses rows).

## Purity rules shipped OFF (lint-all --enable ...)

| rule | count | read | real |
|---|---|---|---|
| discarded-effect-free-result | 3 | 3 | 3 (TAttrPlan.Describe = `Result:= inherited Describe` -> base returns fPDESCRIPTION; the 3 `Describe;` calls do nothing. Latent bug: TAttrPlan never refreshes its description, unlike every sibling plan) |
| query-name-with-effect | 6 | 6 | 1 (GetOperationNames toggles FSuppressEvents + moves the cursor). FPs: var/out-param "answers" (FindPlanAQL, GetGlobalColors, GetDIB), a copy-in procedure (GetDataFrom), IsSampleof1 via the defect below |
| assert-with-side-effect | 4 | 4 | 0 -- all AP_FP_Greater_Eq / AP_FP_Less_Eq, whose body is `AP_FP_Greater_Eq:= X >= Y` |

DEFECT: a function assigning its OWN NAME (Pascal-style result) is scored `g` "writes <Name> (non-local)".
31 functions on ORM3 CLIENT carry that witness; 20 have summary exactly `g`, i.e. are wrongly NOT effect-free.
Recommend: discarded-effect-free-result ON (3/3; caveat: it does not consider virtual overrides -- correct here only
because TAttrPlan has no descendants); query-name-with-effect OFF (1/6); assert-with-side-effect OFF until the
own-name-result defect is fixed (0/4, would be 0 findings after the fix).

## IDE-5: field-writing event handlers labelled Pure/effect-free?

103 handlers with dfm_event + writes_fields: DB effect_free=0 for all 103.
hover --format md: 103/103 render "Analysis facts" and a Writes line; 0 say Pure or Effect-free.
document --qname (dry-run): 0 Pure, 0 Effect-free. (hover --format plain prints only the name -- not a valid probe.)
Positive control: effect_free=1 routines render "Effect-free (proven)" in both. 25 handlers are effect_free=1;
the 4 largest read (btnExitToITrackClick, btnExitToTrackClick, dxDBGrid1OperationVFocusedRecordChanged,
actAboutExecute) are genuine no-op stubs. IDE-5 is closed.
