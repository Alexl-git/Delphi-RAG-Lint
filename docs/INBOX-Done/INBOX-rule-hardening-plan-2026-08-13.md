> # RETIRED 2026-08-17 (session 24). Every row is settled; the last one shipped today.
>
> **Item 9, `unused-public-symbol`, was the only live row left. It is done: 12 -> 6.**
> The rule now CONSULTS the sibling projects a shared unit's own `dl:shared`
> header names, instead of telling the reader to check them by hand. The 6
> removed are all false; the 6 remaining are all genuine. Commit `fc2d613`,
> covered by `tests\autotest\run_unused_public_shared_siblings.ps1`.
>
> **This note's own arithmetic was wrong and is corrected for the record.** It
> said "9 are YADF shared-unit hints, of which **8** are alive in a sibling and
> `OptionsHelpText` is genuinely dead (reported x3)" -- 8 + 3 does not fit in 9.
> Measured per symbol against each sibling DB: **6 false, 3 genuine.** It also
> left DataCopy's 3 unclassified; they are unreferenced in DataCopy,
> DataCopyTests and SortTest alike, and `uFileUtils.pas` carries no `dl:shared`
> header, so the rule was already right there and nothing needed fixing.
>
> **The pattern across this note's whole life is worth keeping.** Of ten rows,
> ONE needed the fix it described (row 9, and even then with the wrong counts).
> Five were STALE and fired zero times when re-measured. Row 2 was fixed for a
> completely different reason than the one written down (a column-aligned
> `Rows  .Free;` failing a literal text match, not the "guard is the next
> statement" shape). Rows 1, 3 and 10 were already done or were true positives
> all along.
>
> **Re-measure before coding is not advice here, it is the finding.** A backlog
> note is a record of what someone believed on one day; the engine has moved
> under every one of these.
>
> ---
>
> # RE-MEASURED 2026-08-16 (session 22): rows 1, 2, 3 and 10 are SETTLED. Kept open for 4-9.
>
> | row | plan said | measured today |
> |---|---|---|
> | 1 `sql-injection-concat` | 1+ | **0.** Already tightened 2026-08-13 -- the rule now requires an anchored leading SQL verb AND a clause keyword, exactly this plan's proposal. Nothing to do. |
> | 2 `object-leak` (A) | ~15, "guard is the NEXT statement" | **FIXED, 9 -> 0 on the self-index -- but NOT for the stated reason.** The next-statement shape was already handled. The live cause was that `FreedInFinallyBlock` matched literal text, so a COLUMN-ALIGNED `Rows  .Free;` did not match `rows.free`. |
> | 3 `used-before-assignment` | 7, "`out` arg counted as a READ" | **0 in all four consumer projects.** Both the plan's cause and the INBOX note's cause are dead. 39 remain on the self-index in a THIRD shape nobody had written down -- see that note's banner. |
> | 10 `field-name-prefix` | 6, DFM heuristic | **0 false positives.** Visibility-scoped by owner ruling 2026-08-13. DataCopy's 2 are REAL private fields, i.e. true positives. |
>
> **Do not work rows 1, 3 or 10 as written.** Row 2 is done. Rows 4-9 were NOT
> re-measured and their counts should be treated as equally suspect until they
> are -- this is now seven notes across two sessions whose stated mechanism was
> not the live one.

# Rule hardening plan -- can we get rid of these false positives?

Owner question, 2026-08-13: *"Can we harden our rules to get rid of these false
positives or there is no way to improve further?"*

**Short answer: yes, and most of it is cheap.** Every false positive found across
the YADF family and DataCopy has an identified mechanism. None of them is
"the rule is inherently ambiguous"; they are all missing context that the engine
either already has in the AST or already has in the index.

The table is ordered by findings-removed per unit of work.

> # RE-MEASURED 2026-08-16 (session 23): FIVE of the ten items now fire ZERO times.
>
> Measured across ALL FOUR consumer projects (DataCopy + YADF + YADFOT +
> YADFSetup) with the current engine, counting findings by rule id:
>
> | # | Rule | note said | measured 2026-08-16 | verdict |
> |---|---|---|---|---|
> | 1 | `sql-injection-concat` | 1+ | **0** | STALE |
> | 2+6 | `object-leak` (A and B) | ~25 | **1** | all but one gone |
> | 3 | `used-before-assignment` | 7 | **0** | STALE (already known) |
> | 4 | `unused-parameter` | 7 | **1** | DONE this session; the 1 is a TRUE positive |
> | 5 | `try-except-swallowed` | 38 | **0** | STALE -- the single largest item on the list |
> | 7 | `length-zero-compare` | 1+ | **0** | STALE |
> | 8 | `concat-in-loop` | 15+ | **0** | STALE |
> | 9 | `unused-public-symbol` | 5+ | **12** | THE LIVE ONE -- see below |
> | 10 | `field-name-prefix` | 6 | **2** | small, and they are TRUE positives |
>
> **This list is now essentially one item.** Items 1, 3, 5, 7 and 8 fire nothing
> on any consumer project, so there is no false positive left to harden away;
> whatever fixed them did so as a side effect of other work. They are recorded as
> stale rather than deleted, because a rule at zero today can return.
>
> **Item 9 is the only substantial one, and it is already partly handled.** All
> 12 break down as:
> * **9 in the YADF family, every one on a SHARED unit**, and the message already
>   says so: *"Its unit is shared with YADF, YADFOT, YADFSetup -- check there
>   before treating it as dead."* Severity is already `hint`. Checked by hand:
>   **8 of the 9 are alive in a sibling project** (`EmitTokens`, `EncodingOf`,
>   `DetectSourceEncoding`, `RenderGroupTree`, `SaveOptionsToIni` all have real
>   call sites in `YadfMain.pas` / `YADFOT.Wizard.pas` / `YADF.OptionsFrame.pas`),
>   and **`OptionsHelpText` is genuinely dead everywhere** -- 2 textual hits, both
>   in its own unit. It is reported once per project, so it accounts for 3 of
>   the 9.
> * **3 in DataCopy** (`uFileUtils.pas`: `IsValidFileNameChar`, `IsPathDirectory`,
>   `GetSkinInfo`) with no shared-unit caveat -- possible dead public API.
>
> So the remaining engine work is narrow: for a unit whose `dl:shared` header
> NAMES its sibling projects, consult those siblings' DBs before reporting. That
> is a DECLARED relationship read out of the source, not a blind name match
> across the manifest, so it does not violate the authoritative-set rule that
> forbids passing unrelated project DBs. It would take the 9 down to 3, and those
> 3 are a source decision (delete `OptionsHelpText` or mark it).
>
> **Item 10's two findings are not false positives**: DataCopy's
> `uMainZeissCopy.pas:1398-1399` declare private fields `Logger` and `TRLogger`
> without the `F` prefix, in a hand-written class. The fix is two renames in
> consumer source, not a rule change.

| # | Rule | Findings | Cause | Needs | Cost |
|---|---|---|---|---|---|
| 1 | `sql-injection-concat` | 1+ | English prose matched a SQL keyword | regex only | XS |
| 2 | `object-leak` (A) | ~15 | guard is the NEXT statement | AST sibling | S |
| 3 | `used-before-assignment` | 7 | `out` argument counted as a READ | signature (indexed) | S |
| 4 | `unused-parameter` | 7 | fixed-signature callbacks/handlers | ~~store facts~~ **same-file AST -- DONE 2026-08-16** | S-M |
| 5 | `try-except-swallowed` | 38 | handler reports/logs, or is documented | AST + policy call | M |
| 6 | `object-leak` (B) | ~10 | VCL `Owner` transfer | ancestry (indexed) | M |
| 7 | `length-zero-compare` | 1+ | dynamic array read as a string | declared type | M |
| 8 | `concat-in-loop` | 15+ | variable operand, type unknown | declared type | M |
| 9 | `unused-public-symbol` | 5+ | used by a SIBLING project | multi-DB reachability | M |
| 10 | `field-name-prefix` | 6 | DFM heuristic on a hand-written class | policy call | S |

## 1. `sql-injection-concat` -- prose is not SQL

    uMainZeissCopy.pas:3453
      'DataCopy is ACTIVE and is the only thing transferring files from the
       FROM folder right now.' + sLineBreak + ...

The rule matches `(?i)(select | from | where |insert |update |delete |values | set )`.
The word **" from "** appears in an ordinary English sentence in a message box.

Fix: require **two or more distinct** SQL tokens, or a string that *starts* with a
SQL verb. A real injectable statement essentially always has both a verb and a
clause keyword (`SELECT ... FROM`, `INSERT ... VALUES`, `UPDATE ... SET`).

## 2. `object-leak` (A) -- the guard is on the next line

    Lex:= TmwPasLex.Create;
    try ... finally Lex.Free; end;

Reported as a leak. The rule looks at the assignment statement and stops. Fix:
inspect the next sibling statement; if it is a `try` whose `finally` frees the
variable (or whose `except` re-raises), it is protected. Handle the
multi-construct case -- `CSVRoutines.pas:268` builds three objects before one
shared `try`, so protection covers everything constructed since the previous
statement boundary.

## 3. `used-before-assignment` -- an `out` argument is a WRITE

    if SafeDelete(LFile, LSweepErr) then ...
    function SafeDelete(const APath: string; out ErrCode: DWord): Boolean;

`LSweepErr` is written by the callee, not read. The rule treats every argument as
a read. Fix: look up the callee's parameter modifiers -- **already in the index**
(signatures are stored) -- and treat an `out` argument as a definition, a `var`
argument as read+write, and a value/`const` argument as a read. This is the same
lookup the call resolver already performs.

## 4. `unused-parameter` -- some signatures are not ours to change

> **DONE 2026-08-16 (session 23). The mechanism this note proposed was the wrong
> one, and the store it recommended could not have fixed it.**
>
> Re-measured: DataCopy's five findings are **4 callbacks + 1 true positive**.
> Not one of them is an override, an interface method, or DFM-wired -- the three
> things this note said to look up. The real mechanism is a routine being HANDED
> SOMEWHERE as a value, at which point the parameter list belongs to the
> procedural type:
>
>     Register(Pred1)       bare identifier argument
>     Register(@Handler)    address-of
>     OnFoo := Handler      assignment rhs
>
> Shipped as a same-file SYNTACTIC pass 1c (`CollectAddrTaken` in
> `DRagLint.Diagnostics.DeadCodeChecks.pas`), checked next to the existing
> `ContractMethods` guard.
>
> **Why not the store, which this note assumed.** One of the four registrations
> (`EExtraExceptionInfo.pas:533`) sits inside an INACTIVE `$IFDEF`. Nothing was
> compiled, so there is no symbol and no ref -- a store-backed check would still
> have reported it. The raw tree-sitter parse sees it plainly. The rule must also
> work on `lint <file>`, which has no store at all. Pinned as case A4 of
> `tests\autotest\run_unused_param_addr_taken.ps1`.
>
> Also measured: `symbol_facts.dfm_event` exists but is **0 for every DataCopy
> symbol**, i.e. never populated -- so the `DfmEvent` field this note leans on
> would not have answered either. Use `refs.kind='event-binding'` if that path is
> ever taken up.
>
> **Results.** DataCopy `unused-parameter` **5 -> 1**, the survivor being the true
> positive `TZEISSTransfer.isValidZeissFileName` (zero refs anywhere -- an owner
> decision to wire, delete or `dl:ok`, not a rule one). Own source **99 -> 75**;
> all 24 are `IOTAKeyBindingServices.AddKeyBinding` handlers in
> `DragLint.Plugin.Keyboard.pas`, each passed by bare name. YADF and YADFSetup
> unchanged; YADFOT surfaced two now-redundant `dl:ok unused-parameter` markers,
> which were removed.
>
> **Accepted imprecision, deliberately not fixed:** matching is by BARE NAME, so a
> method sharing a name with an addr-taken free routine is suppressed too -- the
> same trade-off `ContractMethods` already makes. Pinned as case A5.
>
> **Follow-ups, still open and NOT part of this change:**
> 1. Store-backed addr-taken for CROSS-unit passing. The data exists today
>    (`refs.kind='read'` on a bare routine argument); needs `Store` + file id
>    plumbed into `TDeadCodeChecker.Check` as `TNamingChecker.Check` already gets.
> 2. DFM event bindings via `refs.kind='event-binding'`, which would retire the
>    hardcoded `IsVclFormEventName` list.
> 3. Interface implementations -- needs heritage resolution via `type_ancestors`.
>    Remains the documented gap below.

    function TfrmZeissCopy.FormHelp(Command: Word; Data: NativeInt;
                                    var CallHelp: Boolean): Boolean;   { VCL }
    procedure DescribeExceptionInfo(const ACustom: Pointer; ...);      { EurekaLog }

Neither parameter list can be shortened without breaking the contract. The
FormHelp shape was closed earlier by `IsVclFormEventName`; the
`DescribeExceptionInfo` shape is the callback case closed above.

## 5. `try-except-swallowed` -- 38 findings, and it needs an owner ruling

Two distinct sub-classes, both currently reported:

**(a) The handler DOES report.** `YADFOT.Wizard.pas:426` and `:529` show the
exception in a `MessageDlg` with class and message. Nothing is swallowed. This
is a straightforward fix: a handler that calls a reporting/logging routine, or
re-raises, is not swallowing.

**(b) The handler is deliberately silent AND says why.**

    uConfigurationService.pas:886
      except
        // Deliberately swallowed. This destructor runs during Spring
        // GlobalContainer finalization; a read-only INI directory ... would
        // otherwise let an exception escape a destructor -- far worse than a
        // lost settings write ...

**This is the remedy the rule is asking for, and the rule does not recognise it
-- while its sibling `empty-except` does.** `empty-except` is comment-sensitive
by design: an explained empty handler is accepted. Two rules describe the same
shape and disagree about whether an explanation counts.

**Owner ruling needed:** should `try-except-swallowed` honour an explanatory
comment the way `empty-except` does? If yes, that is ~38 findings across
DataCopy and YADFOT, and it makes the two rules consistent. If no, they should
be `allow`ed -- but then the two rules should at least be documented as
deliberately different.

## 6. `object-leak` (B) -- VCL ownership

    LTimer:= TTimer.Create(LDlg);   { LDlg owns it and frees it }

Freeing this explicitly would be the bug. Fix: if the constructed type descends
from `TComponent` and argument 0 is a non-nil expression, ownership transfers.
Ancestry is already resolved into the project DB.

## 7 + 8. The type-blind pair

    if (Length(W) = 0) ...        { W is TArray<string>, not a string }
    i := i + Count;               { Integer, not string concatenation }

Both are `.scm` queries reasoning about syntax where the answer depends on a
declared type. Both have the same fix, and there is a precedent already wired in
this codebase: `string-equality-comparison` is a type-blind `.scm` rule that a
store-backed built-in SUPERSEDES when an index is present (`DoLintAll` drops the
`.scm` findings for that id). Copy that pattern.

## 9. `unused-public-symbol` -- cross-project blindness

`SaveOptionsToIni` has **15 call sites** in `YADF.OptionsFrame.pas`, which
`YADF.dproj` does not compile. See
`INBOX-cross-project-symbol-use-defeats-single-project-rules.md`. This is the one
item on the list that the project-DB + library-DB scheme cannot answer on its own
-- it needs reachability unioned across sibling project DBs, or a manifest-level
"these N projects are one product" grouping.

## 10. `field-name-prefix` -- a DFM heuristic on a non-form class

Probed rather than guessed (`scratchpad\fnp.pas`). In an **implicit-first**
section: `Integer` and `string` fields are flagged; `Boolean` and every `T*`-typed
field are exempt. In an **explicit** section: everything is flagged regardless of
type.

The implicit-first exemption exists for the auto-generated DFM component dump --
`Button1: TButton` should not need an `F`. Applied to a hand-written class that
happens to use the implicit-first section (`TGroup` in `YADF.Groups.pas`) it
misfires: `Kind`, `OpenerKind`, `Children`, `Parent` are exempted because their
types start with `T`, while `OpenIdx` and `CloseIdx` are flagged for being
`Integer`. **The `Boolean` exemption is unexplained and looks arbitrary** -- it is
why `ForceClosed` escaped while its six siblings did not.

Owner ruling needed: is `F` required for public data members of a record-like
class at all? If it is a BACKING-field convention, the answer is no, and the rule
should only apply to `private`/`strict private` fields.

## What is NOT fixable by hardening

* **`doc-drift` (21 on DataCopy)** -- real work. Autodoc converged; what is left
  needs human text (a missing `<param>` description, a `<returns>`, an
  `<exception cref>` that is wrong). No rule change will remove these.
* **The complexity family** -- already accepted as reviewed exceptions by owner
  ruling. They are accurate measurements, not defects.

## Recommended order

1 -> 3 -> 2 -> 4 (all small, ~30 findings, no policy calls needed), then the two
owner rulings (5 and 10), then the type-backed pair (6, 7, 8), then 9.
