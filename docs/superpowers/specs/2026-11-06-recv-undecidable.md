# E-RECV-UNDECIDABLE: what the unresolved dotted calls really are

Status: DESIGN, NOT-FOR-MERGE (wave 146, lane x4). Nothing here is built. Owner reviews.

## Result in one paragraph

The backlog row calls this residue "undecidable by definition". The measurement says
otherwise. Micronite2027 has 13,937 dotted calls, and 819 (5.9%) have no target. Only **6 of
the 819 are truly undecidable** from any index. 19 have no declaration to point at, 13 can
only reach a property because the routine behind it is chosen at run time. The other **781
(95%) are decidable** and the resolver declines them for specific, nameable reasons. Four
classes (D01-D04) hold 566 rows, 69% of the residue. Lanes b1 and b3 closed **none** of the
819: they fixed other things (see "What b1 and b3 changed").

## What was measured

DB: `C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite`, read only, engine 1.44.1,
library `library-Win32`. Two files had changed since that index was built (`uMicObjectBase.pas`
and, judging by shifted lines, `Micronite2027.dpr`).

Universe (`refs.kind='call'`, non-empty `receiver_text`):

| outcome | rows |
|---|---|
| local `call_edges` row | 6,208 (2,032 certain, 4,176 ambiguous) |
| `external_target` set | 6,910 |
| **neither: the residue** | **819** (454 with a receiver type text, 365 with none) |
| total | 13,937 |

Do not count with `refs.symbol_id IS NULL`. It gives 11,905, because `symbol_id` is set only
for the 2,032 certain edges, and external and ambiguous calls also leave it NULL.

The 4,176 ambiguous edges are not receiver residue: all of them have a typed receiver. 4,133
are `WriteB` and `read` on `TABZMemoryStream`, so they are an overload question.

## Classes

Rules are first-match and every row lands in exactly one class (sum = 819). Classifying by
receiver and member name was checked by reading a sample site per receiver, not every row.

"Facts" says what the fix needs: **have** = the index already holds them (re-resolve only);
**parser** = extractor change plus re-parse.

| class | rows | shape, example | why it declines today | decidable? | facts |
|---|---|---|---|---|---|
| D01 | 285 | `LIni.ReadBoolean`: project helper `MSCTYPES.TMemIniFileHelper` on library `TMemIniFile` | a library-typed receiver asks only the library; `type_helpers` has the row (`target_name` set, `target_symbol_id` NULL) and nothing reads it for this path | yes | have |
| D02 | 191 | `Application.ProcessMessages` | see "The D02 bug" | yes | have |
| D05 | 79 | `raw.Split`, `S[i].IsInArray`, `True.ToString`, `Trim(S).Replace` | no rung maps a built-in type to its RTL helper (`TStringHelper` is in the library); some also need a subscript or result step | yes | have |
| D03 | 50 | `FConnection.Free`, `sb.Free`, `TDictionary.Free` | a class with no written parent has no ancestor row, so `BindExternally` exits at `Anc = ''`; `DeclaringMember` never tries implicit `TObject`; a generic ancestor is unresolved | yes | have |
| D04 | 40 | `System.SysUtils.DeleteFile`, `WinAPI.Windows.CloseHandle`, `System.Pos` | `BindHead` rung 4 handles `Unit.Type`, no rung handles `Unit.Routine` | yes | have |
| D07 | 39 | `pDst.FieldByName` in `with pSrc do`, `PageFooter.LeftTitle.Clear` | the `with` scope is library-typed or unreachable, so the layer verdict is undecided and the head is declined (correct, not yet proven) | yes, by asking the library surface | have |
| D06 | 33 | `Printer.BeginDoc`, `GlobalContainer.Build`, `RootLookAndFeel.Painter.X` | `BindHead` rung 3 takes `VALUE_KINDS` (var, const); a zero-argument library function is no value | yes; the 4 fluent `RegisterType<T>.Implements<I>` rows also need generic method results | have |
| D11 | 21 | `AConverter.Sections[csBlocks].AddEntity`, `FDNavigator.Canvas.LineTo` | a chain stops at an indexed property or an inherited library member; b3 reports no `default`/indexed fact on a property | yes | parser for the indexed part |
| D08 | 19 | `TBytes.Create`, `TArray<Integer>.Create` | compiler intrinsic: **no declaration exists** | decided, nothing to bind | label only |
| D15 | 13 | `TLotStatusCode.FromByte`, `cl.Create` (class reference), `CSVHelper.Set_INIFile` | mixed; each needs its own look | probably, unverified | unknown |
| D10 | 13 | `AConverter.OnCreate(AEnt)`, `V.OnColumnSizeChanged(V, nil)` | `OK_CALL` excludes property and field; the call goes through an event | property yes; the routine behind it is **run-time** | have |
| D14 | 11 | `Acc.Add` on `TList`, `HTimerExitSemaphore.SetEvent` on `TEvent` | several library declarations of the name; the type text has lost its generic arguments | yes, by arity and uses | have or parser, unverified |
| D13 | 8 | `var CADVM := Unit.Func(...)` then `CADVM.OpenDrawing` | inline-var inference does not follow a unit-qualified initializer | yes | have |
| D12 | 7 | `FVM.LoadSettings`, `FBinders.Free` | the fields are in a class-level `var` section, emitted as kind `var` (2 symbols in this DB), which receiver typing does not treat as a field (inferred from the kinds, the code path was not traced) | yes | parser or reader |
| D09 | 4 | `TComparer<Integer>.Construct`, `TObjectDictionary<string,X>.Create` | type arguments in the head; `IsIdentChain` and head lookup do not strip them (not traced line by line) | yes | have |
| U1 | 3 | `RS.Close`, `Conn.Open` on `OleVariant` | late binding | **undecidable** | none |
| U2 | 3 | `ExceptionManager.Handle` (EurekaLog) | the declaring unit is in no index; decidable only if that source is added to the library | **undecidable here** | library root |

D07 by my reading of the sites: 24 rows have a head that is itself a scope member (`PageFooter`,
`Collection`, `ViewInfo`), 15 a head that needs proof it is not one (`ADataSet`, `pDst`).

Delphi is statically typed, so the truly undecidable set is small by nature: Variant and
dispinterface late binding, code whose source nobody indexed, and run-time targets behind
procedural values.

## The D02 bug

`TLibraryOracle.BindHead` (`src\index\DRagLint.Index.LibraryOracle.pas`) tries a library type
before a library global:

```pascal
if PickType(Head, Visible, C, Why) then Exit(Count(Finish(C.Name), AReason));
if Why = R_AMBIGUOUS then Exit(Count('', R_AMBIGUOUS));   // line 614
```

`Pick` (line 376) reports `R_AMBIGUOUS` when `Hits <> 1`, so **zero visible candidates reads the
same as two**. The library holds typelib interfaces `Graph2010.Application`,
`VBIDE2000.Application` and `Access2000.Screen`, in units nobody uses. `Application` therefore
exits at line 614 and never reaches the value rung that would find `Vcl.Forms.Application`,
although `BindExternally`'s own comment names `Application.ProcessMessages` as its example.

Evidence: `Application` has 398 call and member-access rows, 0 external. `Screen` has 84, 0
external. `CodeSite`, a library var with no same-named type, has 736, 734 external. This is from
reading the code plus those counts; the fix has not been run.

## What b1 and b3 changed

Measured on scratch copies of the DB, with each lane's engine and `--library-db`:

| engine | edge | external | none | note |
|---|---|---|---|---|
| 1.44.1, real DB | 6,208 | 6,910 | 819 | baseline |
| lane/145-int + b3, `--resolve-only` | 6,205 | 6,910 | 822 | 0 closed; +3 new |
| lane/145-int + b1, `--rebuild` | 6,357 | 7,292 | 822 | 0 closed; +3 new |

* Every one of the 819 is still unresolved under both. Class counts are unchanged apart from
  the rows below.
* b3's 3 new rows are `.dpr` main-block calls (`AdmConn.Connect` and two more) that lost a
  certain edge. They bind again under b1's re-parse, and the source lines no longer match the
  stored ones, so I read this as a stale stored parse, not a regression. b3 was not re-run
  after a re-parse to prove that.
* b1's 3 new rows are all in `uMicObjectBase.pas`, which changed after the real DB was built.
  I attribute them to source drift, not to the engine.
* b1's higher totals are 534 new rows, 491 of them `inherited`, not closed residue.
* b3's gain is in `member-access` (its report: subscripted bound 665 -> 701). `S[i]` and
  `Lines[0]` stay: a string and an indexed library property are not list element types.
* First attempt without `--library-db` gave external = 17. That run was discarded.

## Options

A. **Drop** (the backlog's advice, overruled for this wave). Keeps 781 decidable misses and a
   wrong name for them.

B. **Close the classes rung by rung in the oracle and resolver, biggest first.** Each fix is
   small and can be guarded on its own. Most need only a re-resolve.

C. Name-only fallback: bind when one library member of the name exists. Rejected. It closes
   rows fast and writes wrong facts, which `BindExternally`'s contract forbids.

D. Compiler as oracle (map files or xref from a real build). Rejected for now: it needs a
   compiling project per target, which older-target and converted units do not have.

**Chosen: B.** Also: stop calling the leftover "unresolved" when it is not. D08 and U1 should
report as `intrinsic` and `late-bound`, so a reader can tell "no answer exists" from "we
declined". Assumption: this reporting change is wanted; if not, leave those rows as they are.

## Phases

Each phase: DocInsight comment, RED guard with a positive control, fix, GREEN, then measure on
a Micronite copy with the library bound (check external stays near 6,910).

**NEXT-BUMP (trivial, exact change; resolver bump, re-resolve, no re-parse except D12):**

1. D02, 191 calls: `Pick` gets a new reason `R_NOT_VISIBLE` for `Hits = 0` and keeps
   `R_AMBIGUOUS` for `Hits >= 2`. Line 614 then falls through to rung 3. `Count` counts the new
   reason as `AmbiguousType` so the stats keep their meaning. Check every other `Pick` and
   `PickType` caller that tests `R_AMBIGUOUS`. Controls: a used unit's `Application` binds; two
   visible candidates still decline; a project type of the name still wins. Files that write
   bare `Forms` (`UIConnect.pas`) match both `Vcl.Forms` and `FMX.Forms` through `InUses`, so
   they stay ambiguous. Expect `Application` and `Screen` member-access rows (293) to move too.
2. D04, 40 calls: in `BindHead`, before rung 4, if the whole chain names a library unit (exact
   stem, or a suffix as `InUses` matches it, case-insensitive), look the member up among that
   unit's routines. Local units are already handled by `LookupUnitQualifiedRoutine`.
3. D03, 50 calls: a project class with no ancestor row asks `TObject` (`BindExternally`, the
   `Anc = ''` exit). A library class tries `TObject` last in `DeclaringMember`, class kinds only,
   never an interface or record. A name with several class candidates may answer when the member
   is on `TObject`, since all give the same target.
4. D12, 7 calls: treat a `var` whose parent is a class as a field. This one is extraction or a
   resolver reader, so confirm the code path first; it needs a re-parse if done in the parser.

Together: 288 rows, 35% of the residue.

**Next (small design, not trivial):**

5. D01, 285 calls, biggest single win. A library-typed receiver whose member is missing, or a
   project helper naming it, reads `type_helpers` by `target_name` and writes a **local** edge.
   Phase 1: exact type name, helper's unit visible from the calling file. Later: helpers on an
   ancestor. Delphi lets one helper per type be active: pick the nearest in uses order, decline
   on doubt. Also unblocks 277 `LIni` member-access rows.
6. D06, 33: rung for a zero-argument library function as head, typed by its return text.
7. D05, 79: built-in type to helper through the library's `type_helpers`; string subscript to
   `Char`; step through helper function results.
8. D13, D09: inline-var inference through a unit-qualified call; strip generic arguments in a head.

**Later:** D07 (library-typed `with` scopes), D10 (bind to the property, marked indirect, never
as a routine edge), D14, D11 (needs the indexed fact b3 also asks for), D15 (triage one by one).

## Not covered

* `member-access` has its own residue, classified only roughly: 9,728 rows have no
  `member_accesses` row and no external target. 6,207 of those have a bound sibling call on the
  same span, so they are not misses, and 798 have an unbound sibling. **2,723 stand alone.** The
  largest are `TABZMemoryStream.Create` (284) and properties reached through project interfaces
  (`FControlPlan_ViewModel.FTR`, `FBlueprint_ViewModel`). Why those stay unbound was not
  investigated.
* Bare calls: 11,905 unbound, mostly intrinsics (`Exit`, `Length`, `Assigned`).
* One project only. Other projects will have other proportions; the D01 count is one helper's
  usage in one project.

## Owner can reverse

* Keeping this row at all (the backlog said DROP; the plan row said measure and design).
* `intrinsic` and `late-bound` as reported labels instead of plain unresolved.
* D01 writing a local edge rather than an external target.
* Option B's order: by row count, not by rename-refusal impact, which was not measured here.
