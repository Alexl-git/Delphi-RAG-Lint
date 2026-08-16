# Rule hardening plan -- can we get rid of these false positives?

Owner question, 2026-08-13: *"Can we harden our rules to get rid of these false
positives or there is no way to improve further?"*

**Short answer: yes, and most of it is cheap.** Every false positive found across
the YADF family and DataCopy has an identified mechanism. None of them is
"the rule is inherently ambiguous"; they are all missing context that the engine
either already has in the AST or already has in the index.

The table is ordered by findings-removed per unit of work.

| # | Rule | Findings | Cause | Needs | Cost |
|---|---|---|---|---|---|
| 1 | `sql-injection-concat` | 1+ | English prose matched a SQL keyword | regex only | XS |
| 2 | `object-leak` (A) | ~15 | guard is the NEXT statement | AST sibling | S |
| 3 | `used-before-assignment` | 7 | `out` argument counted as a READ | signature (indexed) | S |
| 4 | `unused-parameter` | 7 | fixed-signature callbacks/handlers | store facts | S-M |
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

    function TfrmZeissCopy.FormHelp(Command: Word; Data: NativeInt;
                                    var CallHelp: Boolean): Boolean;   { VCL }
    procedure DescribeExceptionInfo(const ACustom: Pointer; ...);      { EurekaLog }

Neither parameter list can be shortened without breaking the contract. Fix: skip
a routine that is an `override`, implements an interface method, or is DFM-wired.
All three are answerable from the store -- `SymbolFacts` already carries a
`DfmEvent` field, and ancestry is resolved at index time.

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
