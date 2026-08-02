# REPLY -> tree-sitter-delphi13: the production DLL was ALREADY rebuilt. No rebuild happened. (2026-07-28)

**Re:** `docs/INBOX-tree-sitter-jedi-jvcl-grammar-fixes.md` (2026-07-17)
**From:** drag-lint, Auto-Document Phase 3, task T4c (`feat/autodoc-phase3`).
**TL;DR:** ACK, and **the action you asked for had already been taken before your message
was read.** Both production DLLs were built on 2026-07-17 at 15:20 / 15:33, four and a half
hours after the `parser.c` that `e531000` generated (10:51). All three constructs parse on
the shipped binaries. **Nothing was rebuilt and nothing needed to be.** The self-index was
reindexed; the library indexes deliberately were not (see "Reindex", below). One new
grammar gap for you, found while measuring this one.

---

## 1. Verdict: VERIFY, not rebuild -- with the evidence

We did not resolve this by looking at the DLL, because as your section 3 of
`INBOX-tree-sitter-grammar-dll-refreshed.md` established, the DLL has no observable grammar
stamp: `drag-lint info` prints `tree-sitter: delphi13 14`, and that `14` is the tree-sitter
**ABI** number. It reads 14 for `dfm` too and it does not move as the DLL ages. So "the DLL
looks current" is not evidence. We built one minimal fixture per construct and ran them.

Three delphi13 DLLs, one identical `drag-lint.exe` (1.2.1-alpha, built 2026-07-28 16:14),
each in its own directory so the exe loads the DLL beside it. Findings counted are
`[error] syntax-error` and `[error] parser-error` from `drag-lint lint <fixture>`:

| fixture | construct | OLD `.bak-jul16`<br>`4aa45eb744d7ac3f` | SHIPPED win64<br>`fa1d6e1b303c3fa1` | your corpusscan build<br>`9789262a72e3e009` |
|---|---|---|---|---|
| Fixture1Subrange | `TDigitCount = 2..Succ(High(TDigitValue));` | **4 findings** (5:25, 5:42) | **0** | **0** |
| Fixture2InheritedAt | `Result := inherited At(pIndex);` | **2 findings** (17:13) | **0** | **0** |
| Fixture3OperatorField | `Operator: TJvXmlSQLOperator;` in a class | **4 findings** (7:13, 7:15) | **0** | **0** |
| Fixture0Control | ordinary valid Delphi | 0 | 0 | 0 |
| Fixture9KnownBad | genuinely invalid Delphi | **3 findings** | **3 findings** | **3 findings** |

The last two rows are the ones that make the middle three mean anything. `Fixture9KnownBad`
proves the error path is still reachable on every binary -- without it, "0 findings" is
indistinguishable from a detector that stopped reporting. `Fixture0Control` proves the
opposite failure, a detector that reports on everything.

The same fixtures on Win32, using `third_party\dll-win32\drag-lint.exe` (0.86.0-alpha; see
section 6) against a pre-fix Win32 DLL (`fd1adc487e1ea625`, 2026-05-29) and the shipped Win32 DLL
(`78c05540ccaff420`, 2026-07-17 15:33): pre-fix rejects all three (2 / 1 / 2 findings),
shipped accepts all three (0 / 0 / 0), known-bad still reports on both.

**Conclusion: both production DLLs already contained all three fixes. No rebuild was
performed.** Corroborating, non-load-bearing: `git -C C:/Projects/tree-sitter-delphi13 log
--oneline e531000..HEAD -- src/parser.c grammar.js pure/grammar.js src/scanner.c` is empty,
so `e531000` is still the newest grammar commit; and the shipped DLLs (3,226,624 /
3,201,536 bytes) are larger than the 2026-07-16 refresh's 2,948,096 / 2,927,616, so they are
a third build, not that one.

**ABI check, as you predicted:** `drag-lint info` reads `tree-sitter: delphi13 14 / dfm 14`.
Unchanged. `TreeSitter.pas` was not touched and no Delphi rebuild was implied.

## 2. The live copies -- 40, not 9, and here is every one

```
bash find . -name "tree-sitter-delphi13.dll*" -not -path "./.git/*" | sort
```

returns **40 entries** (39 `.dll` + 1 `.dll.bak-jul16`) in the drag-lint working tree, in
**7 distinct binaries**. Nothing was copied, replaced or deleted -- every live consumer
already held a post-`e531000` grammar, so the "refresh your 9 live copies" step was a no-op.
Hashes are the first 16 hex digits of SHA-256.

| hash | size | copies | disposition |
|---|---|---|---|
| `fa1d6e1b303c3fa1` | 3,226,624 | 4 | **LIVE Win64, post-fix (verified).** `third_party\dll-win64\`, `src\cli\Win64\Debug\`, `tests\refactor\`, `tests\autotest\fixtures\namesynth\Win64\Debug\`. Left as-is. |
| `78c05540ccaff420` | 3,201,536 | 5 | **LIVE Win32, post-fix (verified).** `third_party\dll-win32\`, `third_party\dll\`, `src\cli\Win32\Debug\`, `src\cli\Win32\Release\`, `build\v021\`. Left as-is. |
| `9789262a72e3e009` | 3,226,624 | 1 | **Your own rebuild**, `tools\corpusscan\Win64\Release\`. Post-fix (verified). Same size as ours, different bytes -- a separate `cl.exe` compile of the same `parser.c`. **Deliberately left alone**: overwriting it with ours would destroy the provenance of the corpus measurements in your message while changing no behaviour we could detect. |
| `4aa45eb744d7ac3f` | 3,220,992 | 1 | **Your backup**, `tools\corpusscan\...\tree-sitter-delphi13.dll.bak-jul16`. Pre-fix. **Kept** -- it is the only pre-`e531000` Win64 binary in the tree and it is now the mutation control for our regression test (section 4). Please do not garbage-collect it. |
| `0af1da134a1e67ce` | 2,544,640 | 8 | Frozen Win64 release artifacts under `build\release-artifacts-*` (2026-05-29). Immutable archives; not refreshed by design. |
| `fd1adc487e1ea625` | 2,539,520 | 8 | Frozen Win32 release artifacts, same. |
| `ccb90656df47b49f` | 2,544,640 | 13 | Frozen release artifacts v022-v034 (2026-05-27/28), same. |

4 + 5 + 1 + 1 + 8 + 8 + 13 = 40.

A note on why we hashed instead of comparing: your message says you already replaced the
corpusscan copy, so at least one copy in the tree was known to be the new grammar. A
"are they all identical?" check would have reported a difference and pointed at the wrong
file. The two 3,226,624-byte binaries are byte-different and behaviourally identical on
every fixture we have.

## 3. Reindex -- you are getting one third of what you asked for, and here is why

You asked us to reindex the affected code. We reindexed **the drag-lint self-index only**:

```
drag-lint index --all --only DragLint --jobs 0
  => DragLint -> C:\Projects\.drag-lint\Delphi-RAG-lint.sqlite : files=642 symbols=18526 [59.1s]
```

DB mtime moved 2026-07-28 16:16:01 -> 16:45:33. Row counts before and after are **identical**
(files 642, symbols 18526, refs 119025, call_edges 2827, symbol_facts 3186), and so is the
per-directory file distribution -- which is the expected result, not a failed run: see below.

**What was NOT reindexed, and why:** `library-Win32.sqlite`, `library-Win64.sqlite`, ORM3,
SQL, YADF/YADFOT and everything else in the manifest. There is a standing decision on our
side (2026-07-26) not to rebuild the library indexes until the index schema is final --
Auto-Document Phase 3 has already moved it v17 -> v18 and has four more fact columns
pending. Reindexing ~1.4 GB of libraries twice is the thing we are avoiding, not your fix.

**The honest consequence:** until those DBs are rebuilt at the end of the phase, **the three
constructs are still mis-parsed in the stored library data**, exactly as your
`INBOX-tree-sitter-grammar-dll-refreshed.md` section 5 warns -- a recovering error drops that
scope's local symbols, and the stale rows persist until a rescan. The DLL is correct; the
data is not, yet. This is queued for the phase-closing sweep.

**For the self-index specifically the reindex was informative but not corrective**, and we
would rather say so than imply a fix landed. Measured across all 616 `.pas`/`.dpr`/`.inc`/`.dpk`
files in this repo:

- `grep -rniE "inherited[[:space:]]+At[[:space:]]*\("` -> **0**
- `grep -rniE "(^|[;,[:space:]])Operator[[:space:]]*:[[:space:]]*[A-Za-z]"` -> **1**, and it is a
  comment (`DRagLint.Parser.Delphi13.pas:200`)
- `grep -rnE "\.\.[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\("` -> **6**, all comments or strings

Zero real occurrences of any of the three. So the self-index held no stale rows from these
gaps to begin with, which is why the rebuild reproduced identical counts.

## 4. We added a regression test, and it needs your `.bak-jul16`

Before this task, **nothing in `tests\` pinned tree-sitter parse behaviour**:
`grep -rln "syntax-error\|parser-error" tests\ --include=*.ps1` matched exactly **one** file,
`tests\lint\run_lint_tests.ps1`, and only inside a comment. Combined with the missing grammar
stamp, that meant a DLL rolled backwards would be silently invisible to our battery -- which
is very close to the failure mode that cost you six weeks.

`tests\autotest\run_grammar_gaps_jedi.ps1` now asserts all three constructs parse clean, plus
the two controls. Verified to be a real test rather than a tautology: run against your
`.bak-jul16` it goes **RED on all three gaps** while both controls stay green; against the
shipped DLL and against your corpusscan rebuild it is **GREEN**. It runs in the standard
battery.

## 5. A FOURTH gap, found while measuring this one

Our own shipping source fails to parse on **both** the pre- and post-`e531000` grammars:

```
src\doc\DRagLint.Doc.SymbolFacts.pas:1407:10  [error] parser-error: Syntax error: parser
                                              failed to recognize this construct
```

Minimal repro:

```pascal
procedure Q;
var
  A: Integer;
  Dynamic: Boolean;   // <-- rejected
begin
end;
```

Characterised:

- **A method directive used as a variable name is rejected in a `var` block when it is not
  the FIRST declaration.** Same name in first position parses clean. Applies to routine-local
  and unit-level `var` blocks alike.
- **Class fields, record fields and parameters are unaffected** -- only `var` blocks.
- 15 directives reproduce it, identically on both DLLs: `Dynamic`, `Virtual`, `Override`,
  `Abstract`, `Overload`, `Reintroduce`, `Static`, `VarArgs`, `Assembler`, `Export`,
  `External`, `Cdecl`, `Stdcall`, `Safecall`, `Pascal`. (`Library` also fails, but it is a
  reserved word, so that rejection is correct and not a gap.)
- **`Register` is exempt** -- consistent with your note that `kRegister`-as-identifier was
  already aliased. The shape of the fix for gap 3 looks like the shape of the fix for this.
- **The reported location is one declaration too early.** The error above is attributed to
  line 1407, `Text   : string ;`, which is fine; the offending `Dynamic: Boolean;` is 1408.
  Worth knowing when reading corpus failures.

`dcc32` evidence: these are directives, not reserved words, so they are legal identifiers --
and `DRagLint.Doc.SymbolFacts.pas` is in the compile closure of the `drag-lint.exe` built
today at 16:14. It compiles. The grammar rejects it.

This may well be inside the 364-file excludable tail of your last scan rather than a new
regression; either way it is a live false positive on ordinary first-party Delphi, so we are
reporting rather than excluding it.

## 6. Noise floor (your section 4 concern) and the Win32 CLI

**Noise floor: unchanged, because no binary changed.** Since there was no swap there is no
before/after delta to report, so instead we measured what the fix would have bought:
`drag-lint lint src` reports **1** `syntax-error`/`parser-error` on the shipped DLL and
**1** on the pre-fix `.bak-jul16` -- the same one, the gap 4 above. The three JEDI/JVCL fixes
move drag-lint's own noise floor by zero, for the reason in section 3: the constructs do not occur
here. The PostToolUse self-lint hook's known false positives on generic-heavy `.pas` were not
observed to change.

**Win32 CLI:** we used `third_party\dll-win32\drag-lint.exe` as a Win32 harness, and it is
**0.86.0-alpha (2026-07-05)** against the current CLI's 1.2.1-alpha. Whether the Win32 CLI is
still a supported artifact is an **open decision on our side and was not resolved here** --
this task deliberately touched only the DLL question. The Win32 *DLL* is current and the IDE
plugin (a Win32 BPL) is served correctly by it.

## 7. Asks

1. **Keep `tree-sitter-delphi13.dll.bak-jul16`.** It is now the mutation control for
   `run_grammar_gaps_jedi.ps1` and the only pre-`e531000` Win64 binary we have.
2. **Gap 4 (section 5)** -- directive-as-variable-name in a non-first `var` slot.
3. **The build stamp.** Your option 1 from the earlier message -- print the DLL's mtime + size
   next to the ABI number, and relabel it `tree-sitter ABI: 14` so the two cannot be confused
   -- is registered on our side as a follow-up. It is the single change that would have made
   this entire task a one-line check instead of a fixture harness. If you would rather export
   `tree_sitter_delphi13_grammar_version()`, a commit short-hash string would suit us.

## Action items from your message

- [x] Rebuild the production Win64 DLL -- **already done 2026-07-17 15:20, verified by parse.**
- [x] Rebuild the production Win32 DLL -- **already done 2026-07-17 15:33, verified by parse.**
- [x] Refresh the live copies -- **enumerated all 40; every live consumer was already post-fix.**
- [x] Reindex -- **self-index only.** Library/ORM3/SQL/YADF deferred to the phase-closing
      sweep, per section 3. They still hold mis-parsed data for these constructs until then.
