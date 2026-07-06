# Delphi Preprocessor Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the tree-sitter-delphi13 JavaScript preprocessor to in-process Object Pascal so drag-lint resolves `{$IFDEF}` before parsing (per-config-accurate indexing), with no Node.js runtime dependency.

**Architecture:** Three new `DRagLint.Preprocess.*` units mirror the JS modules (lexer -> expr evaluator -> chunk processor). A `Preprocess(utf8, profile): TBytes` call blanks inactive `{$IFDEF}` branches to spaces (offsets stay 1:1). A define-profile resolver derives the active defines from a `.dproj` (projects) or platform built-ins (library scans). The stage wires into the indexer + closure scanner behind a flag; the JS stays as a byte-for-byte reference test oracle.

**Tech Stack:** Delphi 13 (RAD Studio 37), Object Pascal, tree-sitter (current full grammar DLL), SQLite/FireDAC, PowerShell + Node.js (test-only oracle), the delphi-build skill.

**Spec:** `docs/superpowers/specs/2026-07-06-preprocessor-port-design.md` (approved).

## Global Constraints

- **Encoding:** all `.pas` source + fixtures are strict 7-bit ASCII, CRLF, no BOM. Never Unicode/LF. **Never a literal `{` or `}` inside a Pascal `{ }` comment** -- use `//` for any comment mentioning a brace (a literal brace ends the comment + breaks compilation). NOTE: this port is ABOUT `{` `}` directives -- every comment describing a directive MUST use `//`, and directive literals in code are string constants (`'{$'`), never bare braces in `{ }` comments. **Byte-verify every NEW `.pas` and `.ps1` is CRLF (0 lone-LF) before committing** -- dcc64 + node both tolerate LF, so the build won't catch it (D5 lesson).
- **Build (authoritative gate):** run `build\build_draglint_win64.bat` via PowerShell `Start-Process cmd.exe -ArgumentList "/c","<bat>" -RedirectStandardOutput <log> -NoNewWindow -Wait -PassThru`; require ExitCode 0, no `[dcc64 Error]`/`E2xxx`/`Fatal`, and `OK: staged`. Stages `src\cli\Win64\Debug\drag-lint.exe` -> `third_party\dll-win64\drag-lint.exe`. Do NOT use the MCP build tool; do NOT `cmd /c build.bat` from the Bash tool. **If the log says OK but the staged exe timestamp did not advance, orphaned `drag-lint.exe`/`drag_lint_graph.exe` hold a lock -- `taskkill /F /IM drag-lint.exe` + `taskkill /F /IM drag_lint_graph.exe`, then rebuild.**
- **New unit wiring:** every new `.pas` needs a `<DCCReference Include="..\preprocess\DRagLint.Preprocess.X.pas"/>` in `src/cli/drag-lint.dproj` AND a `..\preprocess` entry in `<DCC_UnitSearchPath>` (add it once) AND a `uses` entry where consumed.
- **Test the STAGED exe** `third_party\dll-win64\drag-lint.exe` from a NEUTRAL CWD (`C:\TEMP`), pwsh 7. Fixtures ASCII/CRLF, unit name = filename.
- **The JS oracle** lives at `C:\Projects\tree-sitter-delphi13\preprocessor\` (`lexer.js`, `evalExpr.js`, `preprocess.js`, `cli.js`). Node is a TEST-ONLY dependency -- the shipped exe never calls it. Oracle-diff tests run `node cli.js` and compare bytes to the Pascal port.
- **Include modes:** port ONLY `defines-only` and `off`. Do NOT port `expand` (body-splicing) -- offsets must stay 1:1. `Length(output) = Length(input)` is an invariant asserted by every test.
- **Guardrail (green after each task):** lint 154/154 (`tests\lint\run_lint_tests.ps1`), store 16/16, autodoc 7/7, autofix 9/9, callresolve 12/12. The preprocessor is behind a flag / not yet wired until Task 9, so these cannot regress before then.
- **Grammar:** build against the CURRENT full grammar DLL (`tree-sitter-delphi13`). The `pure` grammar swap is a POST-MILESTONE follow-up, NOT in this plan.

**Key existing locations (verified 2026-07-06):**
- Grammar binding: `src/parser/DRagLint.Parser.Delphi13.pas:31-32` (`external 'tree-sitter-delphi13'`), language set `:1277`.
- Indexer parse path: `src/core/DRagLint.Core.Indexer.pas:249` (`ReadAllBytes`) -> `:268` (`Utf8 := EnsureUtf8Bytes(Source)`) -> parse.
- Closure all-branch scan: `src/index/DRagLint.Index.Closure.pas:17-18` (comment), directive-brace stripping `:213`.
- Test-harness pattern: `tests/callresolve/run_emit_params.ps1` (`Check($n,$ok)` helper, `[CmdletBinding()] param([string]$Exe=...)`, scratch dir under C:\TEMP, staged exe).
- `.dproj` structure: `src/cli/drag-lint.dproj` -- `Cfg_1`=Debug (`DCC_Define>DEBUG;$(DCC_Define)` :81), `Cfg_2`=Release (`DCC_Define>RELEASE;$(DCC_Define)` :95); `<Base>` common; per-platform PropertyGroups keyed by `Condition="'$(Config)'=='X'..."`.
- JS oracle source (the port targets): lexer 150 lines, evalExpr 151, preprocess 196. Chunk shapes: `{kind:'text', value, srcStart, srcEnd}` and `{kind:'directive', dir, args, srcStart, srcEnd, line}`. Known directive keywords: define, undef, ifdef, ifndef, if, ifopt, ifend, else, elseif, endif, i, include.

---

## Task 1: Preprocess unit skeleton + dproj wiring + a Node-oracle test harness helper

**Files:**
- Create: `src/preprocess/DRagLint.Preprocess.Types.pas` (shared records: `TDefineProfile`, `TPPChunk`, `TPPChunkKind`)
- Modify: `src/cli/drag-lint.dproj` (add `..\preprocess` search path + DCCReference)
- Create: `tests/preprocess/lib/oracle.ps1` (helper: run the JS oracle on a fixture, return its stdout bytes)
- Create: `tests/preprocess/fixtures/simple_ifdef.pas`

**Interfaces:**
- Produces: `TPPChunkKind = (ckText, ckDirective);`
  `TPPChunk = record Kind: TPPChunkKind; Value, Dir, Args: string; SrcStart, SrcEnd, Line: Integer; end;`
  `TDefineProfile = record Defines: TArray<string>; NumericDefines: TArray<TPair<string,Integer>>; end;` (Defines are lowercased; IncludeMode + BaseDir added in Task 6.)

- [ ] **Step 1: Create the types unit**

`src/preprocess/DRagLint.Preprocess.Types.pas`:
```pascal
unit DRagLint.Preprocess.Types;

// Shared records for the in-process Delphi port of the tree-sitter-delphi13
// preprocessor. Chunk shapes mirror lexer.js; TDefineProfile is the active
// define set the resolver (Task 6) derives from a .dproj or platform built-ins.
// NOTE: directive literals like '{$' are STRING constants; never write a bare
// brace inside a // comment-free zone... comments here use // exclusively.

interface

uses
  System.Generics.Collections;

type
  /// <summary>A lexed chunk: plain text or a recognized compiler directive.</summary>
  TPPChunkKind = (ckText, ckDirective);

  /// <summary>One chunk from the directive lexer. Value is set for ckText;
  /// Dir (lowercased keyword) + Args for ckDirective. SrcStart/SrcEnd are byte
  /// offsets into the input; Line is 0-based (matches lexer.js lineAt).</summary>
  TPPChunk = record
    Kind    : TPPChunkKind;
    Value   : string ;
    Dir     : string ;
    Args    : string ;
    SrcStart: Integer;
    SrcEnd  : Integer;
    Line    : Integer;
  end;

  /// <summary>The active define profile for one preprocess run. Defines are
  /// lowercased symbol names; NumericDefines maps a lowercased name to an
  /// integer (for {$IF CompilerVersion >= 37} style checks).</summary>
  TDefineProfile = record
    Defines       : TArray<string>;
    NumericDefines: TArray<TPair<string, Integer>>;
  end;

implementation

end.
```

- [ ] **Step 2: Wire the dproj**

In `src/cli/drag-lint.dproj`, add `..\preprocess;` to the `<DCC_UnitSearchPath>` (line ~58, prepend before `..\project`) and add a DCCReference alongside the others (line ~162 area):
```xml
        <DCCReference Include="..\preprocess\DRagLint.Preprocess.Types.pas"/>
```

- [ ] **Step 3: Create the oracle helper + a fixture**

`tests/preprocess/fixtures/simple_ifdef.pas` (ASCII/CRLF, unit name `simple_ifdef`):
```pascal
unit simple_ifdef;
interface
{$IFDEF WIN64}
const PlatformName = 'Win64';
{$ELSE}
const PlatformName = 'Other';
{$ENDIF}
implementation
end.
```

`tests/preprocess/lib/oracle.ps1` (CRLF):
```powershell
# Run the JS preprocessor oracle on a file, return its resolved stdout as bytes.
# Node is a TEST-ONLY dependency; the shipped drag-lint exe never calls it.
param([string]$File, [string[]]$Defines, [string]$IncludeMode = 'defines-only')
$ppDir = 'C:\Projects\tree-sitter-delphi13\preprocessor'
$defObj = @{ defines = $Defines } | ConvertTo-Json -Compress
$defFile = [System.IO.Path]::GetTempFileName()
Set-Content -Path $defFile -Value $defObj -Encoding ascii
$out = & node (Join-Path $ppDir 'cli.js') $File --defines $defFile --include-mode $IncludeMode
Remove-Item $defFile -Force
# Return the raw string (cli.js writes resolved text to stdout).
return ($out -join "`n")
```

- [ ] **Step 4: Build**

Build via delphi-build. Expected: ExitCode 0, `OK: staged`, no `[dcc64 Error]`. (The types unit compiles; nothing consumes it yet.)

- [ ] **Step 5: Byte-verify + commit**

Confirm the new `.pas` + `.ps1` + fixture are CRLF/no-BOM (0 lone-LF). Guardrail battery green (additive unit, no behaviour change).
```bash
git add src/preprocess/DRagLint.Preprocess.Types.pas src/cli/drag-lint.dproj tests/preprocess/
git commit -m "feat(pp): preprocess types unit + dproj wiring + JS-oracle test helper"
```

---

## Task 2: Directive lexer (port of lexer.js)

**Files:**
- Create: `src/preprocess/DRagLint.Preprocess.Lexer.pas`
- Create: `tests/preprocess/run_lexer.ps1` (via a temporary `dump-pp-lex` diagnostic verb -- see Step 3)
- Modify: `src/cli/DRagLint.CLI.pas` (add the `dump-pp-lex` diagnostic verb + dispatch)
- Modify: `src/cli/drag-lint.dproj` (DCCReference)

**Interfaces:**
- Consumes: `TPPChunk`, `TPPChunkKind` (Task 1).
- Produces: `function LexDirectives(const AInput: string): TArray<TPPChunk>;` -- byte-faithful port of `lex()`. Text chunks carry Value+span; directive chunks carry lowercased Dir + trimmed Args + span + 0-based Line. Comments (`//`, `(* *)`, `{ }` without `$`) and string literals are skipped (their bytes stay in text chunks). Unknown `{$X}` directives become TEXT chunks (passthrough), matching lexer.js:127-134.

- [ ] **Step 1: Write the failing test (via a diagnostic verb)**

Add a throwaway-friendly diagnostic verb so the test can exercise the lexer through the exe. In `src/cli/DRagLint.CLI.pas`, add `DoDumpPpLex` (prints one line per chunk: `kind|dir|srcStart|srcEnd|line|value-escaped`) reading the file at `--file`, and dispatch `dump-pp-lex`. `tests/preprocess/run_lexer.ps1` (model on `run_emit_params.ps1`): run `dump-pp-lex --file fixtures/simple_ifdef.pas`, assert: a directive chunk `dir=ifdef args=WIN64`, a directive `dir=else`, a directive `dir=endif`, and text chunks for the const lines with correct `srcStart`/`srcEnd`. Assert the FULL reconstruction invariant: concatenating every chunk's source span `[srcStart,srcEnd)` from the original === the whole file (no gaps/overlaps).

- [ ] **Step 2: Run -> FAIL** (`dump-pp-lex` unknown / `LexDirectives` not implemented).

- [ ] **Step 3: Implement the lexer**

`src/preprocess/DRagLint.Preprocess.Lexer.pas` -- port `lexer.js` faithfully. Key points to preserve EXACTLY (bugs here cascade):
- Work over the string as 1-based Delphi chars but track `SrcStart`/`SrcEnd` as **0-based byte offsets** to match the JS (the input is ASCII/UTF-8; for the ASCII directive bytes, char index-1 == byte offset -- but the port must compute offsets on the UTF-8 byte length, NOT char count, since non-ASCII text bytes exist. SIMPLEST + correct: operate on the UTF-8 `TBytes` directly, not a `string`, so offsets are byte offsets by construction. Convert directive keyword/args slices to `string` only for the chunk fields.) IMPLEMENTER NOTE: prefer a `TBytes`-based scanner over a `string`-based one so byte offsets are exact for UTF-8 -- this is the one real divergence risk from the JS (which uses `charCodeAt` on a UTF-16 string; for our ASCII-directive/UTF-8-text corpus, byte-offset scanning is the correct equivalent and is what tree-sitter needs).
- `//` line comment: skip to newline (byte 10), passthrough (stays in the surrounding text chunk).
- `(* *)`: skip to `*)`.
- `'...'`: string literal, skip; doubled `''` is an escaped quote (consume both); do NOT interpret `{` inside.
- `{`: if next byte is `$`, it's a directive -> flushText before it, read `[A-Za-z]*` keyword (lowercased), read args to matching `}` (depth-count on `}`=125), trim args. If keyword in the known set (define/undef/ifdef/ifndef/if/ifopt/ifend/else/elseif/endif/i/include) -> directive chunk; else -> TEXT chunk (passthrough). Advance `textStart` past it either way.
- `{` without `$`: brace comment, skip to `}`.
- Line numbers: build a sorted array of newline byte positions once, binary-search `lineAt(pos)` (0-based). Port the binary search exactly (lexer.js:62-69).
- `flushText(end)`: emit a text chunk `[textStart,end)` only when `textStart < end`.

Add the DCCReference + `uses DRagLint.Preprocess.Lexer` in CLI.pas (for the diagnostic verb).

- [ ] **Step 4: Build -> run `run_lexer.ps1` -> PASS** (directives + spans + full-reconstruction invariant).

- [ ] **Step 5: Guardrail + byte-verify + commit**

Suites green. New files CRLF.
```bash
git add src/preprocess/DRagLint.Preprocess.Lexer.pas src/cli/DRagLint.CLI.pas src/cli/drag-lint.dproj tests/preprocess/run_lexer.ps1
git commit -m "feat(pp): directive lexer (port of lexer.js) + dump-pp-lex diagnostic"
```

---

## Task 3: {$IF expr} evaluator (port of evalExpr.js)

**Files:**
- Create: `src/preprocess/DRagLint.Preprocess.Expr.pas`
- Create: `tests/preprocess/run_expr.ps1` (via a `dump-pp-eval` diagnostic verb)
- Modify: `src/cli/DRagLint.CLI.pas` (add `dump-pp-eval`), `src/cli/drag-lint.dproj`

**Interfaces:**
- Consumes: a defines set (case-insensitive membership) + numeric-defines map.
- Produces: `function EvalPPExpr(const AExpr: string; const ADefines: TDictionary<string,Boolean>; const ANumeric: TDictionary<string,Integer>): Boolean;` -- recursive-descent port of `evalExpr()`. Grammar: or/and/not/cmp/atom. atom = `defined(X)` | `declared(X)`(->False) | INT (`$hex` or decimal; non-zero->True) | `(expr)` | bare IDENT (numeric-map value if present, else defined-test). Any parse error -> False (conservative). ADefines keys are lowercased.

- [ ] **Step 1: Write the failing test**

`tests/preprocess/run_expr.ps1`: via `dump-pp-eval --expr "<E>" --define WIN64 --define UNICODE` (prints `true`/`false`), assert:
- `defined(WIN64)` -> true; `defined(LINUX)` -> false.
- `defined(WIN64) and defined(UNICODE)` -> true; `... and defined(LINUX)` -> false.
- `not defined(LINUX)` -> true.
- `WIN64` (bare) -> true; `LINUX` (bare) -> false.
- `CompilerVersion >= 37` with `--numeric CompilerVersion=37` -> true; `>= 38` -> false.
- `(defined(LINUX) or defined(WIN64))` -> true.
- garbage `@#$%` -> false (conservative).

- [ ] **Step 2: Run -> FAIL.**

- [ ] **Step 3: Implement the evaluator**

Port `evalExpr.js` as a small `TPPExprParser` record/class over the expr string (1-based char indexing is fine here -- the expr text is ASCII). Preserve exactly:
- `Skip` whitespace; `PeekKW(kw)` = case-insensitive prefix match AND next char is not `[A-Za-z0-9_]` (word boundary, evalExpr.js:129-135).
- Precedence chain: `orExpr` (`or`) -> `andExpr` (`and`) -> `notExpr` (`not` prefix, recursive) -> `cmpExpr` -> `atom`.
- `cmpExpr`: parse an atom, then try ops in order `<=`,`>=`,`<>`,`=`,`<`,`>`; booleans coerce to 1/0 for comparison.
- `atom`: `(expr)`; `defined(IDENT)` -> membership; `declared(IDENT)` -> False; INT (`$`=hex else decimal, non-zero=True); bare IDENT -> numeric-map value if present else membership.
- Wrap `EvalPPExpr` in try/except -> False on any exception (evalExpr.js:144-148). Return: if the parse yields a number, `<> 0`; if boolean, as-is.

IMPLEMENTER NOTE: the JS mixes boolean and number returns (`atom` returns bool for defined() / number for INT). In Pascal, use a `Variant` or a small `TPPValue = record IsNum: Boolean; Num: Integer; Bool: Boolean; end;` to carry both through the chain, coercing at comparisons + the final result. Do NOT collapse to Boolean too early or `{$IF CompilerVersion >= 37}` breaks.

- [ ] **Step 4: Build -> run `run_expr.ps1` -> PASS.**

- [ ] **Step 5: Guardrail + byte-verify + commit**
```bash
git add src/preprocess/DRagLint.Preprocess.Expr.pas src/cli/DRagLint.CLI.pas src/cli/drag-lint.dproj tests/preprocess/run_expr.ps1
git commit -m "feat(pp): {\$IF expr} evaluator (port of evalExpr.js) + dump-pp-eval"
```

---

## Task 4: Chunk processor -- defines/conditionals, no includes yet (core of preprocess.js)

**Files:**
- Create: `src/preprocess/DRagLint.Preprocess.pas`
- Create: `tests/preprocess/run_preprocess_core.ps1` (via a `preprocess-file` diagnostic verb)
- Modify: `src/cli/DRagLint.CLI.pas` (add `preprocess-file --file F [--define X]... [--numeric K=V]...`), `src/cli/drag-lint.dproj`

**Interfaces:**
- Consumes: `LexDirectives` (T2), `EvalPPExpr` (T3), `TDefineProfile` (T1).
- Produces: `function Preprocess(const AUtf8: TBytes; const AProfile: TDefineProfile): TBytes;` -- ports the chunk walk of `preprocess.js` EXCEPT the `{$I}` include block (Task 6 adds that; for now an include directive is blanked). Blanks inactive branches + all directives to spaces (newlines preserved). INVARIANT: `Length(Result) = Length(AUtf8)`.

- [ ] **Step 1: Write the failing test (the invariant + branch selection)**

`tests/preprocess/run_preprocess_core.ps1`: `preprocess-file --file fixtures/simple_ifdef.pas --define WIN64` writes resolved text to stdout. Assert:
- `Length(output) == Length(input)` (byte lengths -- the offset-identity invariant). THE critical assertion.
- The `PlatformName = 'Win64'` line is PRESENT (active branch), the `'Other'` line is BLANKED (all non-newline chars are spaces).
- The `{$IFDEF WIN64}` / `{$ELSE}` / `{$ENDIF}` directive bytes are blanked to spaces.
- ORACLE-DIFF: run `oracle.ps1 fixtures/simple_ifdef.pas -Defines win64` and assert the Pascal output === the JS output, byte-for-byte. (This is the strongest check; add it for this fixture and every later one.)
- Add a nested-IF fixture (`nested_if.pas`: `{$IFDEF A}{$IFDEF B}...{$ENDIF}{$ENDIF}`) + a `{$IF}` fixture (`if_expr.pas`: `{$IF CompilerVersion >= 37}`) and oracle-diff both.

- [ ] **Step 2: Run -> FAIL.**

- [ ] **Step 3: Implement the chunk walk**

Port `preprocess.js:45-147,188-193` (skip the `{$I}` block at 149-186 for now -- blank an include directive). Preserve EXACTLY:
- The IF-state stack: each entry `{ Active, TakenBranch, AnyOuterFalse: Boolean }`, initialized `[{True, True, False}]`.
- `EffectivelyActive` = every stack entry `.Active` is True.
- `BlankifyOrEmit(text)`: if effectively active, append text; else append text with every non-`#10` byte replaced by space (`#32`).
- `BlankifyDirective(srcLen)`: append `srcLen` spaces.
- `define`/`undef`: if effectively active, add/remove the first whitespace-split arg (lowercased) from the defines set. Blank the directive.
- `ifdef`/`ifndef`/`if`/`ifopt`: compute cond (ifdef=member, ifndef=not member, if=EvalPPExpr, ifopt=False); `outerInactive := not EffectivelyActive`; push `{ Active: cond and not outerInactive, TakenBranch: cond, AnyOuterFalse: outerInactive }`. Blank.
- `else`: `top.Active := (not top.TakenBranch) and (not top.AnyOuterFalse); top.TakenBranch := True`. Blank.
- `elseif`: if `top.TakenBranch` -> `top.Active := False`; else compute cond via EvalPPExpr, `top.Active := cond and not top.AnyOuterFalse`, and if cond `top.TakenBranch := True`. Blank.
- `endif`/`ifend`: if stack depth > 1, pop. Blank.
- `i`/`include`: for THIS task, just `BlankifyDirective` (Task 6 replaces this).
- Build output in a `TStringBuilder` or byte buffer; return as `TBytes`.
Use a `TDictionary<string,Boolean>` for the defines set (keys lowercased) so membership + add/remove are O(1); seed it from `AProfile.Defines`. Numeric from `AProfile.NumericDefines`.

- [ ] **Step 4: Build -> run `run_preprocess_core.ps1` -> PASS** (invariant + branch + oracle-diff on 3 fixtures).

- [ ] **Step 5: Guardrail + byte-verify + commit**
```bash
git add src/preprocess/DRagLint.Preprocess.pas src/cli/DRagLint.CLI.pas src/cli/drag-lint.dproj tests/preprocess/run_preprocess_core.ps1 tests/preprocess/fixtures/
git commit -m "feat(pp): chunk processor -- defines + conditionals (no includes) + oracle-diff"
```

---

## Task 5: Oracle-diff corpus test (harden the port against a real fixture set)

**Files:**
- Create: `tests/preprocess/fixtures/` (a set: `undef.pas`, `elseif_chain.pas`, `ifopt.pas`, `passthrough_dir.pas`, `strings_with_braces.pas`, `comment_dollar.pas`)
- Create: `tests/preprocess/run_oracle_corpus.ps1`

**Interfaces:** consumes `Preprocess` (T4) + `oracle.ps1` (T1). No new production code -- this task HARDENS the port by widening oracle coverage before includes/wiring.

- [ ] **Step 1: Build the fixture set + the corpus runner**

Fixtures exercising the tricky lexer/processor corners (each a valid `unit X;`):
- `undef.pas`: `{$DEFINE FOO}...{$UNDEF FOO}{$IFDEF FOO}` (FOO must be inactive after undef).
- `elseif_chain.pas`: `{$IF ...}{$ELSEIF ...}{$ELSEIF ...}{$ELSE}{$ENDIF}` (only the first true branch active).
- `ifopt.pas`: `{$IFOPT R+}` (always false -> else branch).
- `passthrough_dir.pas`: `{$WARN SYMBOL_DEPRECATED OFF}` + `{$INLINE ON}` (unknown directives pass through as TEXT -- must appear verbatim in active output, blanked in inactive).
- `strings_with_braces.pas`: a string literal containing `'{$IFDEF}'` text (must NOT be treated as a directive) + a `{ not a directive }` brace comment.
- `comment_dollar.pas`: `// {$IFDEF X}` in a line comment (must NOT be treated as a directive).

`run_oracle_corpus.ps1`: for EACH fixture, run both `Preprocess` (via `preprocess-file`) and `oracle.ps1` under a fixed profile (`win64`, `unicode`), assert byte-for-byte identical AND `Length(out)==Length(in)`. Loop + a per-fixture Check line.

- [ ] **Step 2: Run -> some may FAIL** (the lexer corner cases -- strings/comments/passthrough -- are exactly where a port diverges). For each divergence, fix the lexer/processor (T2/T4) to match the oracle, rebuild, re-run. This task's VALUE is finding those divergences against the reference.

- [ ] **Step 3: All fixtures oracle-identical -> PASS.**

- [ ] **Step 4: Guardrail + byte-verify + commit**
```bash
git add tests/preprocess/fixtures/ tests/preprocess/run_oracle_corpus.ps1 src/preprocess/
git commit -m "test(pp): oracle-diff corpus -- strings/comments/passthrough/elseif/undef parity"
```

---

## Task 6: Include handling -- defines-only + off modes

**Files:**
- Modify: `src/preprocess/DRagLint.Preprocess.pas` (add the `{$I}` block: defines-only + off)
- Modify: `src/preprocess/DRagLint.Preprocess.Types.pas` (add `IncludeMode` + `BaseDir` to the call, or a params record)
- Create: `tests/preprocess/fixtures/uses_inc/` (`main.pas` with `{$I config.inc}`, `config.inc` with `{$DEFINE FEATURE_X}`)
- Create: `tests/preprocess/run_include_modes.ps1`

**Interfaces:**
- Produces: `Preprocess` gains include handling via a params extension. Add `TPPOptions = record Profile: TDefineProfile; IncludeMode: string; BaseDir: string; end;` and an overload `function Preprocess(const AUtf8: TBytes; const AOptions: TPPOptions): TBytes;` (keep the T4 2-arg form delegating with IncludeMode='off', BaseDir=''). `defines-only`: read the `.inc`, run its directive pass sharing the PARENT defines set (so its {$DEFINE}/{$UNDEF} mutate the parent), BLANK the `{$I}` directive (no body splice). `off`: blank the `{$I}`, ignore its defines. Unresolved include: blank (offsets stay 1:1). NEVER splice (no `expand`).

- [ ] **Step 1: Write the failing test (the defines-only bug-repro)**

`fixtures/uses_inc/config.inc`: `{$DEFINE FEATURE_X}`. `fixtures/uses_inc/main.pas`:
```pascal
unit main;
interface
{$I config.inc}
{$IFDEF FEATURE_X}
const HasX = True;
{$ELSE}
const HasX = False;
{$ENDIF}
implementation
end.
```
`run_include_modes.ps1`: `preprocess-file --file main.pas --include-mode defines-only --define win64` (BaseDir = the fixture dir). Assert:
- `HasX = True` line PRESENT, `HasX = False` line BLANKED (config.inc's {$DEFINE FEATURE_X} propagated to the parent -> the {$IFDEF} took the THEN branch). THE defines-only correctness proof.
- `Length(output) == Length(input of main.pas)` (the `{$I}` directive blanked, NO body spliced -- offsets 1:1).
- ORACLE-DIFF: `oracle.ps1 main.pas -IncludeMode defines-only` === Pascal output, byte-for-byte.
- With `--include-mode off`: FEATURE_X NOT defined -> `HasX = False` branch active (the ELSE). (Proves off vs defines-only differ correctly.)

- [ ] **Step 2: Run -> FAIL.**

- [ ] **Step 3: Implement the `{$I}` block**

Port `preprocess.js:149-186` for defines-only + off ONLY (NOT expand). In the `i`/`include` handler: if not effectively active OR depth >= 64 -> blank. Strip surrounding quotes from the include name, resolve relative to BaseDir. Unresolved -> blank. If mode='off' -> blank. If mode='defines-only' -> read the `.inc` UTF-8 bytes, recurse `Preprocess` passing the SAME defines dictionary by reference (so the child's define/undef mutate it -- in Pascal, pass the `TDictionary` itself, not a copy; use an internal `_shared` overload) with BaseDir = the .inc's dir and depth+1; DISCARD the child's output text; then `BlankifyDirective`. Guard include depth with a maxIncludeDepth=64 param.

IMPLEMENTER NOTE: the JS shares the Set by reference via `options._sharedDefines`. In Pascal, the cleanest port is an internal recursive worker `PreprocessInto(bytes, defines: TDictionary, numeric, includeMode, baseDir, depth)` that the public `Preprocess` seeds + calls; the child call passes the SAME `defines` instance. This also avoids re-seeding on every include.

- [ ] **Step 4: Build -> run `run_include_modes.ps1` -> PASS** (defines-only propagates + 1:1 + oracle-diff; off differs).

- [ ] **Step 5: Guardrail + byte-verify + commit**
```bash
git add src/preprocess/DRagLint.Preprocess.pas src/preprocess/DRagLint.Preprocess.Types.pas tests/preprocess/run_include_modes.ps1 tests/preprocess/fixtures/uses_inc/
git commit -m "feat(pp): include handling -- defines-only + off (no body splice, offsets 1:1)"
```

---

## Task 7: Define-profile resolver (.dproj + platform built-ins)

**Files:**
- Create: `src/preprocess/DRagLint.Preprocess.Profile.pas`
- Create: `tests/preprocess/run_profile.ps1` (via a `pp-profile --dproj F [--platform P] [--config C]` diagnostic verb)
- Modify: `src/cli/DRagLint.CLI.pas` (add `pp-profile`), `src/cli/drag-lint.dproj`
- Create: `tests/preprocess/fixtures/sample.dproj`

**Interfaces:**
- Produces:
  `function PlatformBuiltins(const APlatform: string): TArray<string>;` -- e.g. 'Win64' -> [MSWINDOWS, WIN64, CPU64BITS, CPUX86_64, UNICODE, CONDITIONALEXPRESSIONS, COMPILER_VERSION_37, VER370]; 'Win32' -> [MSWINDOWS, WIN32, CPUX86, UNICODE, ...]. All lowercased.
  `function ProfileFromDproj(const ADprojPath, APlatform, AConfig: string): TDefineProfile;` -- platform builtins UNION the Base + <AConfig> DCC_Define values parsed from the .dproj XML. AConfig defaults 'Release'. APlatform defaults 'Win64'. Missing/unparseable .dproj -> platform builtins for APlatform only (Win64 default).

- [ ] **Step 1: Write the failing test**

`tests/preprocess/fixtures/sample.dproj` (a minimal .dproj with a Base `DCC_Define` = `CUSTOM_BASE;$(DCC_Define)` and a Release/Cfg_2 `DCC_Define` = `RELEASE;$(DCC_Define)` and a Debug/Cfg_1 = `DEBUG;$(DCC_Define)`, mirroring src/cli/drag-lint.dproj's structure at :81/:95). `run_profile.ps1`: `pp-profile --dproj sample.dproj --platform Win64 --config Release` prints the sorted defines. Assert:
- Contains `win64`, `mswindows`, `unicode`, `compiler_version_37` (platform builtins).
- Contains `release` and `custom_base` (from Base + Release DCC_Define).
- Does NOT contain `debug` (that's the Cfg_1/Debug config, not selected).
- `--config Debug` -> contains `debug`, NOT `release`.
- `--platform Win32` -> contains `win32`+`cpux86`, NOT `win64`.
- A nonexistent `--dproj missing.dproj` -> Win64 builtins only (no crash, no custom/release).

- [ ] **Step 2: Run -> FAIL.**

- [ ] **Step 3: Implement the resolver**

Port the platform-builtins table (from `cli.js:38-43` defaults, extended per platform). Parse the `.dproj` XML (it's MSBuild XML) with Delphi's XML support (`Xml.XMLDoc` / `IXMLDocument`) OR a bounded regex over `<DCC_Define>...</DCC_Define>` within the PropertyGroup whose `Condition` matches the target Config. Given the .dproj structure (Base common + `Cfg_2`=Release), collect: the Base PropertyGroup's DCC_Define + the selected config's DCC_Define. Split on `;`, drop the `$(DCC_Define)` MSBuild recursion token, lowercase, union with platform builtins, dedupe. Missing file / parse error -> just `PlatformBuiltins(APlatform)`.

IMPLEMENTER NOTE: the `.dproj` uses `Cfg_1`=Debug / `Cfg_2`=Release indirection (the `<Condition>` on the DCC_Define PropertyGroup is `'$(Cfg_2)'!=''` for Release, `'$(Cfg_1)'!=''` for Debug -- see src/cli/drag-lint.dproj:80,93). Map AConfig 'Release'->Cfg_2, 'Debug'->Cfg_1 by reading the ProjectExtensions `<Key>Cfg_2</Key>` block, OR simpler + robust: match the PropertyGroup whose Condition mentions the literal config name via the `'$(Config)'=='Release'` PropertyGroup (:38) to learn the Cfg_N alias, then find the DCC_Define under `'$(Cfg_N)'!=''`. If the mapping is fragile, fall back to: collect ALL DCC_Define values whose PropertyGroup Condition does NOT mention the OTHER config. Keep it simple; the test fixture locks the behaviour.

- [ ] **Step 4: Build -> run `run_profile.ps1` -> PASS.**

- [ ] **Step 5: Guardrail + byte-verify + commit**
```bash
git add src/preprocess/DRagLint.Preprocess.Profile.pas src/cli/DRagLint.CLI.pas src/cli/drag-lint.dproj tests/preprocess/run_profile.ps1 tests/preprocess/fixtures/sample.dproj
git commit -m "feat(pp): define-profile resolver -- .dproj (Base+Release) + platform builtins"
```

---

## Task 8: Empirical de-risk GATE -- preprocess -> CURRENT full grammar

**Files:**
- Create: `tests/preprocess/run_full_grammar_gate.ps1`

**Interfaces:** consumes `Preprocess` (T6) + the existing full-grammar index path. NO new production code -- this is the GATE from the spec (does the current full grammar parse resolved input at least as well as raw?).

- [ ] **Step 1: Write the gate test**

`run_full_grammar_gate.ps1`: take an IFDEF-heavy real fixture (copy a known-tricky unit -- e.g. a small RTL unit with `{$IFDEF}` platform branches, or synthesize `platform_heavy.pas` with several `{$IFDEF WIN64}`/`{$IFDEF POSIX}` blocks). Index it TWO ways to two scratch DBs: (a) RAW (current path, no preprocess), (b) PREPROCESSED (run `preprocess-file --include-mode defines-only --define win64`, write the resolved text to a temp .pas, index THAT). Compare: assert the preprocessed index has `errors <= raw errors` for the file (parse errors from the index summary), AND the preprocessed index does NOT contain symbols from the inactive `{$IFDEF POSIX}` branch (per-config accuracy), AND the WIN64-branch symbols ARE present.

- [ ] **Step 2: Run.** Expected: PASS (preprocessed parses at least as well + is per-config). **IF IT FAILS** (preprocessed parses WORSE than raw): STOP. This is the spec's gate -- report to the controller/user. Options: the pure DLL becomes a prerequisite after all, or reconsider. Do NOT proceed to wiring (Task 9) on a failed gate.

- [ ] **Step 3: Commit the gate**
```bash
git add tests/preprocess/run_full_grammar_gate.ps1 tests/preprocess/fixtures/
git commit -m "test(pp): GATE -- preprocess -> current full grammar parses resolved input"
```

---

## Task 9: Wire the preprocess stage into the indexer (behind a flag)

**Files:**
- Modify: `src/core/DRagLint.Core.Indexer.pas` (insert Preprocess between EnsureUtf8Bytes and parse, gated)
- Modify: `src/cli/DRagLint.CLI.pas` (add `--no-preprocess` flag + thread the profile into the index path; resolve the profile from `--dproj`/`--platform`/`--config` or default)
- Create: `tests/preprocess/run_index_preprocess.ps1`

**Interfaces:**
- Consumes: `Preprocess` (T6), `ProfileFromDproj`/`PlatformBuiltins` (T7).
- Produces: the index pipeline runs `Preprocess(Utf8, profile)` before parsing when preprocessing is enabled (default ON for the resolved path; `--no-preprocess` reverts to raw). Per-file exception -> fall back to raw + full grammar for that file, log once.

- [ ] **Step 1: Write the failing test**

`run_index_preprocess.ps1`: index `fixtures/platform_heavy.pas` (WIN64 + POSIX branches) with the DEFAULT (preprocess ON, Win64 profile) to a scratch DB; assert a WIN64-branch symbol is present and a POSIX-branch symbol is ABSENT (per-config). Then index with `--no-preprocess`; assert BOTH branches' symbols are present (raw all-branch, unchanged behaviour). This locks: preprocess-on = per-config, `--no-preprocess` = the old behaviour.

- [ ] **Step 2: Run -> FAIL** (preprocess not wired; `--no-preprocess` unknown).

- [ ] **Step 3: Implement the wiring**

In `Indexer.pas`, after `Utf8 := EnsureUtf8Bytes(Source)` (:268), if preprocessing enabled: `try ParseBytes := Preprocess(Utf8, FProfile) except on E: Exception do begin LogOnce(...); ParseBytes := Utf8; end; end;` else `ParseBytes := Utf8;`. Parse `ParseBytes` (still the full grammar). Thread an `FPreprocessEnabled: Boolean` + `FProfile: TDefineProfile` onto the indexer, set from CLI. In `CLI.pas`: add `--no-preprocess` (sets enabled False), and resolve `FProfile` = `ProfileFromDproj(dproj, platform, config)` when `--project`/`--dproj` given, else `PlatformBuiltins('Win64')` (the fallback). Store spans as-is (offsets are 1:1 -- no remap).

- [ ] **Step 4: Build -> run `run_index_preprocess.ps1` -> PASS.**

- [ ] **Step 5: Guardrail (CRITICAL) + byte-verify + commit**

FULL battery: lint 154/store 16/autodoc 7/autofix 9/callresolve 12. NOTE: with preprocess ON by default, does any existing test's expected symbol set change (a fixture with `{$IFDEF}`)? If a callresolve/lint fixture has conditional code, its indexed symbols may shift. INVESTIGATE each change: is it a correct per-config narrowing, or a regression? Most fixtures have no IFDEFs so should be unaffected. If a suite moves, decide: update the expectation (correct narrowing) or gate that suite's index with `--no-preprocess` (if the test intends all-branch). Document each.
```bash
git add src/core/DRagLint.Core.Indexer.pas src/cli/DRagLint.CLI.pas tests/preprocess/run_index_preprocess.ps1 tests/preprocess/fixtures/platform_heavy.pas
git commit -m "feat(pp): wire preprocess into the indexer (per-config; --no-preprocess fallback)"
```

---

## Task 10: Wire per-config into the closure/uses scanner

**Files:**
- Modify: `src/index/DRagLint.Index.Closure.pas` (run Preprocess before extracting uses; gated by the same flag)
- Create: `tests/preprocess/run_closure_preprocess.ps1`

**Interfaces:**
- Consumes: `Preprocess` (T6), the indexer's `FPreprocessEnabled`/`FProfile`.
- Produces: the closure scanner extracts `uses` from the PREPROCESSED text, so a unit `uses`d only under an inactive branch is not discovered/pulled in (per-config file discovery). `--no-preprocess` keeps the current all-branch scan + brace-stripping.

- [ ] **Step 1: Write the failing test**

`fixtures/closure_cond/main.pas`: `uses SysUtils {$IFDEF POSIX}, PosixOnly{$ENDIF} {$IFDEF WIN64}, Win64Only{$ENDIF};` (+ stub `PosixOnly.pas`, `Win64Only.pas`, in the dir). `run_closure_preprocess.ps1`: index the dir with preprocess ON (Win64 profile); assert `Win64Only` is discovered/indexed and `PosixOnly` is NOT (per-config closure). With `--no-preprocess`: assert BOTH are discovered (all-branch, unchanged).

- [ ] **Step 2: Run -> FAIL** (closure still all-branch).

- [ ] **Step 3: Implement**

In `Index.Closure.pas`, where it reads a file's bytes to scan `uses` (before the `PAT_ITEM`/brace-strip at :213), if preprocessing enabled run `Preprocess(bytes, FProfile)` first and scan the resolved text (the inactive-branch `uses` items are now blanked to spaces, so `PAT_ITEM` never sees them). Keep the existing brace-stripping for the `--no-preprocess` path. Thread the same enabled/profile flags the indexer uses.

- [ ] **Step 4: Build -> run `run_closure_preprocess.ps1` -> PASS.**

- [ ] **Step 5: Guardrail + byte-verify + commit**
```bash
git add src/index/DRagLint.Index.Closure.pas tests/preprocess/run_closure_preprocess.ps1 tests/preprocess/fixtures/closure_cond/
git commit -m "feat(pp): per-config closure -- uses scanner honors the active profile"
```

---

## Task 11: Remove diagnostic-only verbs OR promote them; final battery + measure

**Files:**
- Modify: `src/cli/DRagLint.CLI.pas` (decide: keep `preprocess-file` as a supported diagnostic, remove the throwaway `dump-pp-lex`/`dump-pp-eval` if they were scaffolding-only -- keep whatever the tests still need)
- Create: `tests/preprocess/run_full_battery.ps1` (or extend an existing battery runner)

- [ ] **Step 1: Decide verb fate.** `dump-pp-lex` / `dump-pp-eval` were test scaffolding -- if the lexer/expr tests still call them, KEEP them (they're cheap diagnostics + useful). `preprocess-file` is genuinely useful (a user can see resolved output) -- KEEP + add a usage line. Only remove a verb if NOTHING references it. Do not break a test to remove a verb.
- [ ] **Step 2: Full battery** on the staged exe: lint 154/store 16/autodoc 7/autofix 9/callresolve 12 + ALL `tests\preprocess\run_*.ps1` (lexer, expr, preprocess_core, oracle_corpus, include_modes, profile, full_grammar_gate, index_preprocess, closure_preprocess) -> all green.
- [ ] **Step 3: Measure the gain.** Re-index drag-lint's own tree with preprocess ON vs OFF; record the parse-error delta (spec target: CLI.pas 39->1 leaf errors was the v1.1.0 DLL claim; the preprocessor targets the IFDEF class specifically). Note the measured before/after in the commit / a short report.
- [ ] **Step 4: Commit**
```bash
git add src/cli/DRagLint.CLI.pas tests/preprocess/
git commit -m "chore(pp): finalize preprocess verbs + full battery + measured IFDEF-resolution gain"
```

---

## Task 12: Final whole-branch review + publish decision (controller-driven)

- [ ] **Step 1: Final whole-branch review** (superpowers:requesting-code-review) over the diff since the spec commit. Focus: the port matches the JS oracle (byte-for-byte tests are the evidence), the 1:1 offset invariant holds everywhere, the `defines-only` propagation is correct, per-config narrowing is intended (not a lost-symbol regression), encoding, the fallback path (`--no-preprocess` + per-file exception) never hard-fails, no Node dependency in the shipped exe.
- [ ] **Step 2: PAUSE for user sign-off** before any version bump / release. Then decide with the user: publish as a minor version, and whether to ALSO do the post-milestone follow-ups now (notify grammar team PORTED + request pure DLL; the v1.1.x full-DLL refresh).
- [ ] **Step 3 (post-publish follow-ups, separate):** notify the grammar team the preprocessor is ported + passing vs their oracle (+ serve.js not consumed, request the pure grammar DLL); optionally the v1.1.x DLL refresh; swap in the pure grammar as a follow-up milestone.

---

## Self-review notes (author)

- **Spec coverage:** in-process port (T2-T6) / no Node (T1 oracle is test-only) / defines-only+off only, no expand (T6) / 1:1 offsets = no source map (asserted every task) / define-profile from .dproj Base+Release + platform builtins + Win64 fallback (T7) / fully per-config = symbol extraction (T9) + closure (T10) / current grammar first, pure later (T9 uses full grammar; T12 step 3 defers pure) / JS oracle byte-for-byte (T4,T5,T6) / empirical de-risk GATE (T8) / guardrail green throughout (every task) / notify-when-built (T12). All spec sections mapped.
- **Type consistency:** `TPPChunk`/`TPPChunkKind`/`TDefineProfile` (T1) used by T2/T4/T7. `LexDirectives`(T2)->`Preprocess`(T4). `EvalPPExpr`(T3)->`Preprocess`(T4). `TPPOptions`+include overload (T6). `ProfileFromDproj`/`PlatformBuiltins`(T7)->wiring (T9/T10). `Preprocess(bytes, profile/options)` signature consistent T4->T10.
- **Flagged soft spots:** (1) byte-offset vs char-index -- T2 note mandates a TBytes-based scanner so UTF-8 offsets are exact (the one real JS-divergence risk). (2) the JS bool/number mixing in evalExpr -- T3 note mandates a TPPValue carrier. (3) the .dproj Cfg_1/Cfg_2 indirection -- T7 note gives the mapping + a robust fallback. (4) T8 is a GATE -- a failure STOPS the plan (pure DLL becomes prerequisite). (5) T9 battery -- watch for fixtures whose IFDEF symbols shift; investigate each (per-config narrowing vs regression).
- **Build gotchas encoded:** no literal braces in `{ }` comments (acute here -- the whole feature is about braces; directive literals are string constants, comments use `//`); new-file CRLF byte-check (dcc64+node tolerate LF); new unit dproj DCCReference + search path; delphi-build recipe; neutral test CWD; staged exe; Node is test-only.
