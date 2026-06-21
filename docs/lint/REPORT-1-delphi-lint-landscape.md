# Report 1 — The Delphi Lint / Static-Analysis Feature Landscape (Free + Commercial)

> Research compiled 2026-06-19..21 for the drag-lint project. Companion document:
> [REPORT-2-draglint-implementation-plan.md](REPORT-2-draglint-implementation-plan.md),
> which maps everything below onto what drag-lint can actually build.
>
> Sources are linked inline throughout. This report catalogues *what features exist*;
> Report 2 decides *what we implement*.

---

## 0. Executive summary

Delphi's static-analysis ecosystem is **mature in the "classic" lint areas** — metrics,
dead-code, coding-standards/naming, and a solid set of bug-pattern checks — but
**weak in the modern "semantic" areas** that Rust (Clippy), C++ (clang-tidy) and
C#/Python analyzers now take for granted: ownership/lifetime flow, interface
reference-cycle detection, thread-safety, UI-thread-affinity, framework-API misuse
(FireDAC, ToolsAPI, WinAPI), architecture/layering rules, nullability, and rich
auto-fixes.

The practical landscape is six tools plus the compiler:

| Tool | License | Engine | Delivery | ~Rule/check count |
|---|---|---|---|---|
| **Delphi compiler (dcc32/64)** | built-in | the real compiler | inline / build | ~40 useful hints+warnings |
| **SonarDelphi** (+ **DelphiLint** IDE plugin) | open source (LGPL-3) | ANTLR-style grammar + symbol table | CI (SonarQube) / IDE | **~148 rules** |
| **Peganza Pascal Analyzer (PAL)** / **Pascal Expert (PEX)** | commercial | own parser + dataflow | CLI+GUI / IDE | **~188 named checks** (231+ sections) |
| **TMS FixInsight** | freemium (Lite free, Pro paid) | DelphiAST | IDE / CLI (Pro) | **~60 checks** (W/C/O families) |
| **GExperts** | open source | own parser | IDE | a few *analysis* features |
| **CnPack Wizards** | open source | own parser | IDE | a few *analysis* features |
| newer OSS: **Y.StaticCodeAnalyser**, **nrodear/StaticCodeAnalyser** | open source | DelphiAST + DFM | CLI+IDE | 41 / 150+ detectors |

drag-lint already plays in this space (tree-sitter AST + an AST-exact SQLite symbol/refs
index + an IDE plugin + a graph viewer). Its differentiators are the **exact symbol/refs
index** (cross-file call graph, uses-graph, impl-ranges) and **AI-/CLI-first output** —
which open the door to checks the AST-only tools can't easily do (cross-unit dead code,
fan-in/out, architecture/layering, FireDAC-sequence misuse) and to the *semantic frontier*
that essentially no Delphi tool covers today.

---

## 1. The Delphi compiler itself (dcc32/dcc64) — the baseline linter

Every diagnostic has a `{$WARN <NAME> ON|OFF|ERROR}` directive. Reference:
[Error and Warning Messages (Delphi) — DocWiki](https://docwiki.embarcadero.com/RADStudio/Athens/en/Error_and_Warning_Messages_(Delphi)),
and the complete directive list at [Marc Durdin's table](https://marc.durdin.net/2012/05/delphi-xe2s-hidden-hints-and-warnings-options/).

**Highest-value built-in checks** (a linter should *surface/aggregate* these, not duplicate them):

- **Hints:** `H2077` value assigned but never used · `H2164` variable declared but never used ·
  `H2219` private symbol declared but never used · `H2135` loop body deleted (dead) ·
  `H2369`/`H2443`/`H2444`/`H2445`/`H2456` property-accessor naming & inline-not-expanded.
- **Warnings:** `W1035 NO_RETVAL` (function result might be undefined) · `W1036 USE_BEFORE_DEF`
  (variable might not be initialized) · `W1021/W1022` comparison always false/true ·
  `W1023/W1024` signed/unsigned compare/combine · `W1009 HIDING_MEMBER` · `W1010 HIDDEN_VIRTUAL` ·
  `W1011 GARBAGE` (text after final `end.`) · `W1044 SUSPICIOUS_TYPECAST` ·
  `W1057/W1058 IMPLICIT_STRING_CAST[_LOSS]` (the key Unicode-migration lint) ·
  `W1000 SYMBOL_DEPRECATED` (default OFF) · `W1066` extended-precision loss ·
  `W1201–W1208 XML_*` (DocInsight doc-comment validation).

**Takeaway:** the compiler already does a lot of the dataflow-heavy work (use-before-def,
result-undefined, dead comparisons). A linter adds most value by covering what the compiler
*doesn't*: style/naming, structural smells, security, cross-file analysis, and richer
exception/resource patterns.

---

## 2. SonarDelphi (+ DelphiLint) — the open-source heavyweight

- Repo: [integrated-application-development/sonar-delphi](https://github.com/integrated-application-development/sonar-delphi)
  (~148 rules in `CheckList.java`). IDE front-end: [DelphiLint](https://github.com/integrated-application-development/delphilint)
  (standalone mode = local curated ruleset; connected mode = SonarQube profile).
- Type split: ~105 Code Smell, ~40 Bug, **0 Vulnerability / 0 Security Hotspot** (security is a gap even here).
- **Quick fixes** on ~14 rules (LowercaseKeyword, MixedNames, RedundantParentheses, UnusedImport removal, AssignedAndFree guard removal, MissingRaise insert, IterationPastHighBound `- 1`, …).

Representative rules by area (full list in the research appendix):

- **Unused/dead:** UnusedImport, UnusedLocalVariable, UnusedField, UnusedRoutine, UnusedType,
  UnusedConstant, UnusedProperty, UnusedGlobalVariable, CommentedOutCode, RedundantAssignment,
  RedundantJump, InheritedMethodWithNoCode, RedundantInherited, EmptyRoutine, EmptyBlock,
  EmptyFinallyBlock, EmptyArgumentList.
- **Naming:** ClassName(T/E), RecordName, EnumName, InterfaceName(I), HelperName, AttributeName,
  PointerName(P), ConstantName, FieldName(F), VariableName, RoutineName, ConstructorName(Create),
  DestructorName(Destroy), UnitName, ShortIdentifier(<3), MixedNames(case), LowercaseKeyword.
- **Complexity/size:** CyclomaticComplexityRoutine(20), CognitiveComplexityRoutine(15),
  TooLargeRoutine(100 stmts), TooLongLine(120), TooManyParameters(7), TooManyVariables(10),
  TooManyNestedRoutines, RoutineNestingDepth, CaseStatementSize, ClassPerFile.
- **Exceptions:** CatchingRawException, RaisingRawException, SwallowedException, EmptyFinallyBlock,
  **ReRaiseException** (`raise E;` loses stack — Blocker), **MissingRaise** (constructed not raised).
- **Control-flow/style:** WithStatement, GotoStatement, LoopExecutingAtMostOnce,
  **IterationPastHighBound** (off-by-one), ExhaustiveEnumCase, **IfThenShortCircuit**
  (`IfThen` evaluates both branches), BeginEndRequired, MissingSemicolon, RedundantParentheses,
  PascalStyleResult, NilComparison (prefer `Assigned`), RedundantBoolean.
- **Inline vars:** InlineVarExplicitType, InlineLoopVarExplicitType, InlineConstExplicitType,
  **InlineDeclarationCapturedByAnonymousMethod** (Bug).
- **Resource/memory:** **FreeAndNilTObject** (arg not a class — Blocker), AssignedAndFree
  (redundant guard), CastAndFree, ConstructorWithoutInherited, DestructorWithoutInherited,
  InstanceInvokedConstructor, ObjectPassedAsInterface.
- **Delphi type-safety:** NonLinearCast, PlatformDependentCast/Truncation, UnicodeToAnsiCast,
  RedundantCast, CharacterToCharacterPointerCast.
- **API patterns:** **DateFormatSettings** (locale), MathFunctionSingleOverload,
  ImplicitDefaultEncoding, **StringListDuplicates** (dupIgnore w/o Sorted), IndexLastListElement,
  AddressOfCharacterData, AddressOfNestedRoutine.
- **Legacy/directives:** ObjectType, LegacyInitializationSection, InlineAssembly,
  ExplicitTObjectInheritance, CompilerWarnings/Hints OFF directive bans.
- **Structure:** GroupedField/Parameter/VariableDeclaration, ConsecutiveConst/Type/Var/VisibilitySection,
  MemberDeclarationOrder, VisibilitySectionOrder, ProjectFileRoutine/Variable, PublicField, InterfaceGuid.
- **Routine quality:** RoutineResultAssigned, UnspecifiedReturnType, NoreturnContract, AssertMessage,
  NilComparison, RedundantBoolean, VariableInitialization.
- **Format strings:** FormatStringValid, FormatArgumentCount, FormatArgumentType.
- **Forms:** FormDfm / FormFmx (class lacks resource).
- **Imports:** UnusedImport, ImportSpecificity (intf-only used in impl), FullyQualifiedImport.
- **Template/forbidden:** ForbiddenType/Routine/Property/Field/Constant/EnumValue/Identifier/ImportFilePattern,
  CommentRegularExpression, StringLiteralRegularExpression, InheritedTypeName.

---

## 3. Peganza Pascal Analyzer (PAL) / Pascal Expert (PEX) — the commercial heavyweight

[peganza.com](https://www.peganza.com/) — PAL is a standalone CLI+GUI batch analyzer
(53 reports, 231+ sections); PEX is the live-in-IDE subset (~142 checks). The richest
*dataflow* and *cross-reference* analysis in the Delphi world.

Grouped check families (codes are Peganza's):

- **Strong Warnings (STWA1–12):** property-recursion in own accessor; ambiguous unit references;
  unconditional self-recursion (stack overflow); index/pointer/typecast errors; bad for-loop
  conditions; out-param aliasing; interface GUID problems; identical then/else.
- **Warnings (WARN1–64):** the big dataflow set — variables referenced-but-never-set /
  set-but-never-referenced / used-before-assignment (definite *and* possible via opaque calls);
  var/value/out parameter misuse; **function result not set**; functions called as procedures;
  constructor/destructor without inherited; destructor without override; abstract-method
  instantiation; bad object creation (leak); property read/write specifier mismatch; member
  hiding; orphan event handler; bad assignment/truncation; interface/object mixing; 32/64-bit
  mismatch; mixed operator precedence; explicit float comparison; constant condition;
  self-assignment; dangerous Exit/Raise/labels; for-loop-var read after loop; empty/short-circuited
  blocks (if/case/for/while/repeat/on/except/finally); enum value missing in case; FreeAndNil on
  non-object; **misformed Format() calls**; absolute/threadvar hazards.
- **Optimization (OPTI1–11):** missing `const` for unmodified string/record/array params;
  array-property access in loops; non-overridden virtuals → static; nested-routine capture cost;
  `var`→`out`; inline-ordering; managed-local placement (declare inline / move out of loop).
- **Code Reduction (REDU1–24):** unused identifiers; locals usable at lower scope; set-and-used-once;
  overwritten-before-read; redundant zero-init in constructor; redundant empty-string init;
  functions called only as procedures; routines called once; unneeded boolean comparison;
  boolean assignment shortenable; field used in single method; redundant parentheses; common
  subexpression; omit default args; redundant typecasts.
- **Memory (MEMO1–8):** unprotected Free (no try-finally); create-inside-try; unbalanced
  Create/Free; multiple creations w/o free; reference-before-create; reference-after-free.
- **Convention Compliance (CONV1–32):** T/E/P/I prefixes; field private + `F` prefix; getter `Get`/
  setter `Set`; constructor/destructor names; with-variable count; visibility ordering; shadowing;
  multiple statements per line; param prefixes; old-style function result.
- **Inconsistent Case (INCA1–3)** + **Prefix Report** (component Hungarian prefixes).
- **Metrics:** Totals; Complexity (McCabe DP, LOC, comment density — 18 ranked lists);
  **OO Metrics (CK suite): WMC, DIT, NOC, CBO, RFC, LCOM**.
- **Reference reports (PAL only):** call tree / reverse call tree / most-called; cross-reference;
  **Uses report** (unnecessary units, units in dpr-not-source and vice-versa, circular uses,
  optimal ordering); **Clone detection (CLON1–2)**; exception-propagation tree; literal-strings
  (replaceable by const/resourcestring); to-do; third-party deps; conditional symbols/directives.
- **Class reports (PAL only):** hierarchy; class field external-access (encapsulation breaks).
- **DFM/Controls reports (PAL only):** control alignment/size/tab-order/warnings; events
  (unconnected handlers); missing properties.
- **Security:** SECU1 = experimental SBOM (CycloneDX) — security is minimal even here.

---

## 4. TMS FixInsight — the popular bug-oriented IDE linter

[tmssoftware.com/site/fixinsight](https://www.tmssoftware.com/site/fixinsight.asp). Built on
DelphiAST. Three families; CLI (`FixInsightCL.exe`) in Pro; suppression via `//FI:W508`
trailing comment, `//FI:ignore` first line, or `{$IFNDEF _FIXINSIGHT_}`. **No quick fixes.**

- **W5xx Warnings:** W501 empty `except` · W502 empty `finally` · W505/W506 empty `then`/`else` ·
  W511 object created in `try` · W504 missing inherited in destructor · W525 missing inherited in
  constructor · W522 destructor missing `override` · W509 unreachable code (after Exit/raise/Break) ·
  W529 raise-object instead of bare re-raise · W503 self-assignment · W507 identical then/else ·
  W508 successive assignment (overwrite) · W510 equal operands · W512 odd else-if (repeated test) ·
  W514 loop iterator out of range (`0..Length`) · W517 variable hides class member · W520 missing
  parens with `in` (`not X in [..]`) · W527 property references itself · W528 unused loop variable ·
  W521 undefined return value (incl. managed types) · W523/W524/W530 interface GUID problems ·
  W526 pointer to nested method · W515 suspect Free · W531 FreeAndNil non-instance · W534
  class passed where interface expected · W536 new instance as const interface (leak) · W539
  interface receiver also out-param · W535 enum value(s) missing in case · W519 empty method ·
  W513/W537 Format arg count/type mismatch · W538 ClassName compared with string literal ·
  W540 string var as both in and out · W541 pointer↔integer cast · W542 direct float comparison.
- **C1xx Conventions:** C101 method too long · C102 too many params · C103 too many locals ·
  C104 class `T` · C105 interface `I` · C106 pointer `P` · C107 field `F` (prefix configurable) ·
  C108 nested `with` · C109 unneeded boolean comparison · C110 getter/setter name mismatch ·
  C111 exception `E`.
- **O8xx Optimizations:** O801 `const` for string param · O802 unused resourcestring · O803
  unused constant · O804 unused parameter · O805 inline routine defined after its call.

---

## 5. Free IDE expert packs (analysis features only)

- **GExperts** ([gexperts.org](https://www.gexperts.org/)): Uses Clause Manager (identifier→unit
  index, light symbol search), Grep Search (regex w/ "ignore comments"), Project Dependencies
  (unit dependency graph), To-Do List (TODO/FIXME scan), Code Proofreader (as-you-type casing).
  Primarily productivity, not analysis.
- **CnPack Wizards** ([github.com/cnpack/cnwizards](https://github.com/cnpack/cnwizards)):
  **Uses Unit Cleaner** (removes unused units — real analysis), Source-Module Relation Analyzer
  (dependency graph), Source Code Statistics (LOC metrics), Code Formatter, Structure Highlight.

---

## 6. Newer open-source AST analyzers (worth watching)

- **Y.StaticCodeAnalyser** ([github.com/arbsis/Y.StaticCodeAnalyser](https://github.com/arbsis/Y.StaticCodeAnalyser))
  — 41 detectors (21 Pascal AST + 20 **DFM**): memory leaks, **SQL injection**, hardcoded secrets,
  dead event handlers, **DB credentials in form files**; SARIF output for CI.
- **nrodear/StaticCodeAnalyser** — 150+ detectors (Pascal + DFM): leaks, SQL injection, dead
  handlers, hardcoded secrets, locale traps, **Win64 pointer bugs**; SARIF + "Claude AI hand-off".
- **DelphiAST** (parser foundation), **DGrok/PasParse**, **Castalia parser** — parsing layers, not
  analyzers themselves.

These two newer tools are the closest in spirit to where drag-lint is going (CLI, SARIF, AI
hand-off, DFM-aware), and they prove there is appetite for **security + DFM** checks.

---

## 7. Consolidated master catalogue (deduplicated, by category)

The union of distinct check *types* across all tools above, grouped into the nine working
categories used in Report 2. (Coverage notes: C=compiler, S=SonarDelphi, P=Peganza, F=FixInsight.)

**A. Complexity & size:** cyclomatic (S,P,F-ish) · cognitive (S) · nesting depth (S) · method
length/statements (S,P,F) · too many params (S,P,F) · too many locals (S,P,F) · too many nested
routines (S) · class too broad / God class (P-metrics) · unit too large · case-too-small (S) ·
boolean-expression complexity · CK metrics WMC/DIT/NOC/CBO/RFC/LCOM (P) · fan-in/fan-out (P).

**B. Naming conventions:** type `T`/exception `E`/interface `I`/pointer `P` (C,S,P,F) · field `F`
(S,P,F) · constant casing (S,P) · method PascalCase (S,P) · param prefix (S,P) · short/cryptic
(<3) (S) · names differ only by case (P-INCA) · unit name ≠ file (S,P) · getter `Get`/setter `Set`
(P,F,H2369) · enum-value prefix · component Hungarian prefix (P-Prefix) · keyword lowercase (S).

**C. Dead/unreachable/redundant:** code after Exit/raise/Break (S,P,F) · unused unit in uses
(S,P,Cn) · unused private member (S,P,H2219) · unused local (C-H2164,S,P,F) · unused param
(S,P,F-O804) · unused const/type/field/property/global (S,P) · write-only / set-never-read (P,F) ·
overwrite-before-read (P,F) · redundant boolean comparison (S,P,F) · redundant cast (S,P) ·
self-assignment (S,P,F) · empty block/then/else/method (S,F) · commented-out code (S) ·
redundant inherited / inherited-only override (S) · redundant parentheses (S,P) · identical
then/else (P,F) · odd else-if repeated test (F).

**D. Exception-handling:** empty except (S,P,F) · swallowed (no log/re-raise) (S) · bare/broad
catch (S) · raise bare Exception (S) · **re-raise via `raise E`** (S,F) · raise in finally · empty
finally (S,P,F) · missing-raise (constructed not raised) (S) · duplicate `on` class (P) · exception
as control-flow · except without on-clause.

**E. Resource/memory:** Create not in try-finally (P-MEMO,F-W511) · Create inside try (P,F) ·
missing Free / unbalanced Create-Free (P) · double Free · **FreeAndNil on non-object/interface**
(S,P,F) · interface/object ref mixing (S,P,F) · stream/critical-section/file-handle leak ·
constructor/destructor missing inherited (S,P,F) · destructor missing override (P,F) ·
abstract-method instantiation (P) · `if Assigned(x) then x.Free` redundant guard (S).

**F. Control-flow & expression:** `with` (S,P,F) · nested `with` (F-C108) · goto (S,P) · missing
`else` on enum case / non-exhaustive (S,P,F) · float `=` comparison (S,P,F) · mixed precedence /
missing parens (P,F-W520) · **off-by-one loop bound `0..Count`** (S,P,F) · boolean literal in
condition (S,P,F) · constant condition (C-W1021/2,P) · function result ignored (P) · `IfThen`
both-branches (S) · loop executing at most once (S) · property references itself (P-STWA1,F-W527).

**G. Security:** SQL string-concat injection (Y,nr) · Format string mismatch (S,P,F) · hardcoded
password/secret/connection-string (Y,nr) · DB credentials in DFM (Y,nr) · unsanitized
ShellExecute/CreateProcess · weak `Random` for security · path traversal · unsafe string APIs
(StrCopy…) · unsafe typecast w/o `is` (C-W1044) · unvalidated deserialization · TStringList
delimiter pitfall · insecure temp file. *(Largest gap across all commercial tools.)*

**H. Maintainability/smells:** magic numbers (S-ish) · duplicated code / clones (P-CLON) ·
commented-out code (S) · TODO/FIXME/HACK markers (P,GExperts) · god class (P-metrics) · long
parameter list (S,P,F) · public mutable field (S-PublicField) · deep inheritance (P-DIT) ·
literal strings replaceable by const/resourcestring (P-LSTR) · multiple statements per line (P).

**I. Delphi-platform-specific:** 32/64-bit pointer↔int cast (S,P,F-W541) · NativeInt truncation
(S,P,W1023/4) · lossy Ansi/Unicode cast (C-W1057/8,S) · locale-sensitive Date/Str without
TFormatSettings (S,P) · default-encoding file IO (S) · platform `SizeOf` assumptions ·
inline-after-call ordering (P-OPTI9,F-O805) · deprecated RTL/API (C-W1000) · PChar arithmetic ·
variant-record type punning.

---

## 8. The semantic frontier — what almost no Delphi tool does (the opportunity)

Synthesized from the project's own landscape note. These are the high-value gaps where a
symbol+refs+call-graph index like drag-lint's can leapfrog the AST-only tools:

1. **Ownership / resource-lifetime flow** — object escapes a routine without ownership transfer;
   "created here, never freed on any reachable path" across the *call graph* (not just one body).
2. **Interface reference-cycle detection** — A holds `IB`, B holds `IA` → ARC leak. Essentially
   undetected by any Delphi tool.
3. **Thread-safety** — shared mutable field (`FList.Add`) touched from multiple threads without a
   lock; lock acquired without paired release across paths.
4. **VCL/FMX UI-thread violations** — UI property/method touched from a worker thread
   (not inside `TThread.Synchronize`/`Queue`).
5. **FireDAC misuse** — `Open` vs `ExecSQL` on the wrong statement; dataset opened twice;
   missing transaction commit/rollback; connection/query leak; FetchAll misuse.
6. **WinAPI contract misuse** — e.g. `ReadFile` on an OVERLAPPED handle without an event;
   ignored `BOOL`/`HANDLE` return values.
7. **Component lifecycle / ownership-through-Owner** — `TComponent.Create(Self)` then explicitly
   freed (double ownership); `TTimer.Create(nil)` never freed.
8. **Architecture / layering rules** — UI unit directly using a Data-layer unit; enforce a
   dependency DAG over the **uses-graph** (drag-lint already has `unit_uses`).
9. **Nullability** — `Customer := Find(...); Customer.Name` without a nil/`Assigned` check.
10. **Generics/RTTI misuse** — `TObjectList<T>` with `OwnsObjects=False` while code assumes
    ownership; `TRttiContext.Create` in hot loops.
11. **Auto-fixes & CI ergonomics** — SonarDelphi/DelphiLint lead on quick-fixes; SARIF output and
    non-zero CI exit codes are still patchy (FixInsight CLI returns 0 even with findings).

**drag-lint's structural advantages for these:** an exact cross-file **symbol table** (kinds,
visibility, parent, impl-ranges), a **refs/call table** (`read`/`write`/`call`/`type_use`), a
**uses-graph** (`unit_uses`, interface vs implementation, resolved targets), and DocInsight
extraction — i.e. the raw material for cross-file dead-code, fan-in/out, architecture/layering,
and the first rungs of ownership/lifetime analysis that the single-file AST tools cannot reach.

---

## 9. Conclusion / direction for drag-lint

1. **Reach parity cheaply** on the classic, high-signal, low-false-positive checks (categories
   B/C/D/E/F) — most are expressible as tree-sitter `.scm` rules with no recompile.
2. **Differentiate with the index** on cross-file checks the AST-only tools struggle with: unused
   *public* symbol across the whole project, fan-in/out, **architecture/layering over the
   uses-graph**, cross-unit dead code, FireDAC-sequence misuse.
3. **Own the security niche** (category G) that even the commercial tools neglect — and add the
   **DFM-aware** checks (DB credentials/passwords in form files) the newest OSS tools pioneered.
4. **Lead on AI/CI ergonomics** — JSON today; add SARIF + suppression comments + per-rule
   enable/disable; the AI hand-off is already drag-lint's home turf.

The detailed, prioritized build order is in
[REPORT-2-draglint-implementation-plan.md](REPORT-2-draglint-implementation-plan.md).
