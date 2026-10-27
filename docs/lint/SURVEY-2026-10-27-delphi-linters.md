# Delphi / Pascal linter survey vs drag-lint (195 rules)

Compiled 2026-10-27. Updates docs/lint/REPORT-1-delphi-lint-landscape.md (2026-06). Our rule list:
scratchpad/our-rules.tsv (195). Gap docs checked: docs/lint/MISSING-FEATURES.md (MF), docs/lint/BACKLOG.md (BL).
Confidence notes: rule lists for Peganza (all report pages), SonarDelphi (CheckList in repo master) and
nrodear StaticCodeAnalyser (docs/rules.md) were read from the primary source. FixInsight, compiler W/H,
Audits&Metrics, CodeHealer, FPC were NOT retrievable online (DocWiki blocked, vendor PDF not reached) and
come from REPORT-1 / memory: rows that depend on them carry "?".

Tool codes used in section 2: PAL = Peganza Pascal Analyzer, PEX = Pascal Expert, FI = TMS FixInsight,
SD = SonarDelphi (also DelphiLint standalone), SCA = nrodear/StaticCodeAnalyser, YSC = arbsis/Y.StaticCodeAnalyser,
DCC = Delphi compiler, FPC = Free Pascal compiler, GX = GExperts, CN = CnPack, AM = RAD Studio Audits/Metrics.

## 1. Tool table

| tool | licence | maintained (last release) | rule count | source |
|---|---|---|---|---|
| Peganza Pascal Analyzer (PAL) 9.20.0 | commercial | yes, 2026-03-25 (9.16 May 2025 before) | 157 named checks in the check-style reports (STWA12 WARN64 OPTI11 REDU24 MEMO8 CONV32 INCA3 NEXT3) + ~29 sections in reference/control reports (USES9 LSTR5 COWA8 DUP2 EVEN2 CLON2 SECU1) = ~186 | peganza.com/PALHelp/ (reports2.htm and each report page) |
| Peganza Pascal Expert (PEX) 9.20.0 | commercial | yes, 2026-03-25 | ~142 (live subset of PAL, per ideasawakened review) | ideasawakened.com review; delphipraxis ann 15251 |
| TMS FixInsight | freemium (Personal free, Pro paid: CLI) | vendor page now says "End of Life"; Delphi 2006..13 listed; last release year not confirmed (2025?) | ~60 (W5xx ~40, C1xx 11, O8xx 5) | tmssoftware.com/site/fixinsight.asp; REPORT-1 |
| SonarDelphi 1.21.0 | open source (LGPL-3) | yes, 2026-09-04 (1.20.0 2026-08-12, 1.19.0 2026-06-09) | 149 check classes in master (incl. ~10 template/forbidden-X/regex rules); no Vulnerability/Hotspot types | github.com/integrated-application-development/sonar-delphi |
| DelphiLint (IDE plugin over SonarDelphi) | open source | v1.3.0 2025-01-21 (slow) | subset of SonarDelphi, standalone mode + quick fixes (~14 rules) | github.com/integrated-application-development/delphilint |
| nrodear StaticCodeAnalyser (SCA) | MIT | very active (push 2026-10-26, 3000+ commits) | 203 (179 Pascal + 23 DFM + 1 INI); includes SonarDelphi-compatible SCA060+ block; Delphi 12/13 plugin + CLI + Lazarus | github.com/nrodear/StaticCodeAnalyser (docs/rules.md) |
| arbsis Y.StaticCodeAnalyser | MIT | push 2026-05-14 | 41 (21 Pascal + 20 DFM) | github.com/arbsis/Y.StaticCodeAnalyser |
| Delphi compiler dcc32/64 (Delphi 13) | built-in | yes | ~100 {$WARN} ids + ~60 hints (approx, ?) | docwiki Error_and_Warning_Messages_(Delphi) (not fetched); REPORT-1 sec 1 |
| RAD Studio Audits and Metrics (Together-derived) | built-in (older SKUs) | legacy; believed dropped after Delphi 2010 / XE era (?) | ~30 audits + ~25 metrics (?) | DocWiki page not retrievable (403 / no response) |
| CodeHealer (SOCK Software, 2005) | commercial | abandoned: vendor forum silent since 2016 (wiert.me); no current release found | unconfirmed (~100 audits claimed, ?) | drbob42.com/review/healer.htm; wiert.me 2020-06-02 |
| Castalia (Embarcadero, bundled in RAD Studio) | commercial (part of IDE) | yes | ~0 lint rules: structural highlight, parser-level error squiggles | REPORT-1 / memory |
| ModelMaker Code Explorer (MMX) | free | low activity (?) | ~0 lint rules: unit dependency analysis, refactorings, code metrics view (?) | memory; not verified |
| GExperts | open source | yes (Delphi 13 builds) | ~0 lint: Uses Clause Manager, Project Dependencies, To-Do, Code Proofreader (casing) | gexperts.org |
| CnPack Wizards | open source | yes | ~0 lint: Uses Unit Cleaner, Source Statistics, dependency analyzer | github.com/cnpack/cnwizards |
| Free Pascal / Lazarus (FPC 3.2.x / 3.3 trunk) | GPL / LGPL, free | yes (FPC 3.2.2 2021, trunk active; Lazarus 4.x) | ~50 lint-relevant of ~several hundred compiler messages (hints/notes/warnings) | freepascal.org docs (not fetched); memory |
| SciTools Understand (Pascal/Delphi) | commercial | yes | metrics + dependency views, ~0 lint rules (?) | memory; not verified |

Observations on the landscape since REPORT-1: (1) SCA is the new rule-count leader and overlaps drag-lint's
niche (CLI, SARIF, DFM, AI hand-off, security); (2) SonarDelphi keeps adding API (typed binary operators
IS_NOT/NOT_IN in 1.21, constraints, GUID node), no new rule families in 2026; (3) PAL 9.20 added only an
experimental Security Report (SBOM) and false-positive fixes (WARN1/3/4/7/18/19/46/52, STWA5); (4) FixInsight
is end-of-life, which makes its W5xx rule set a frozen reference.

## 2. Concept table

Status: HAVE (our id) / PARTIAL (our id + gap) / FILED (MF or BL) / NEW. "?" = unsure.
Value = defect severity x frequency in real Delphi code. Feasibility: easy = AST pattern, medium = type/symbol
resolution (our M1 resolver / store), hard = data-flow.

### 2a. NEW, value high

| # | concept | tools (ids) | status | ours | Delphi example | value | feasibility |
|---|---|---|---|---|---|---|---|
| 1 | Constructor called on an instance instead of the class | SD InstanceInvokedConstructor; SCA124 | NEW | - | `Obj := TFoo.Create; Obj.Create(5);` (re-runs ctor, leaks members) | high | easy (receiver is a variable, not a type) |
| 2 | Method hides ancestor virtual method (no override/reintroduce) | DCC W1010 ?; PAL WARN55; SCA149 | NEW | only destructor-without-override | `TBase.Run virtual; TChild.Run;` (no override) | high | medium (hierarchy via store) |
| 3 | Anonymous method captures a loop variable / inline var | SD InlineDeclarationCapturedByAnonymousMethod; SCA175 | NEW | - | `for var I := 0 to 9 do Q.Add(procedure begin Use(I) end);` | high | medium |
| 4 | Unconditional self-recursion (stack overflow) | PAL STWA3 (WARN19 lists recursion) | NEW | - | `procedure TFoo.SetX(V: Integer); begin SetX(V); end;` | high | medium (CFG: every path calls self) |
| 5 | Fresh instance passed as const/interface parameter (leak or early free) and class passed where interface expected | FI W534, W536 ?; SD ObjectPassedAsInterface; PAL WARN53 (partly) | NEW | interface-object-mixing is same-routine only | `Show(TImpl.Create);` where `Show(const I: IFoo)` | high | medium |
| 6 | DFM names an event handler that the form class does not declare, and orphan handlers | PAL WARN62, EVEN1/2; SCA028, SCA029, SCA030 | NEW | dfm-property-not-declared covers properties only | `.dfm: OnClick = btnOkClick` but no `procedure btnOkClick` (EReadError at load) | high | medium (dfm + pas) |
| 7 | Move/FillChar/ZeroMemory with SizeOf of a pointer-typed variable | SCA154 | NEW | - | `FillChar(Obj, SizeOf(Obj), 0)` where Obj is a class/pointer (zeroes 8 bytes of the ref) | high | medium |
| 8 | UPDATE/DELETE statement literal without WHERE | SCA058 | NEW | sql-injection-concat only | `Q.SQL.Text := 'DELETE FROM ORDERS';` | high | easy |
| 9 | Interface-section uses entry only needed by implementation section | SD ImportSpecificity; PAL USES5 (optimal uses); GX | NEW | unused-unit-in-uses is all-or-nothing | `interface uses Vcl.Dialogs;` (only used in a method body) | high (breaks cycles; ties to cycles --plan) | easy (unit_uses + refs by section) |
| 10 | Public/published member used only inside its own unit/class (could be private/strict private/implementation-only) | PAL WARN1, WARN2, CONV30/31; SCA050, SCA051, SCA107 | NEW | unused-public-symbol = never referenced only | `public procedure Helper;` referenced only from TFoo's own methods | high | easy (refs + enclosing_symbol_id) |

### 2b. NEW, value medium

| # | concept | tools (ids) | status | ours | Delphi example | value | feasibility |
|---|---|---|---|---|---|---|---|
| 11 | Owned-object containers: TList<T>/TObjectList(False) filled with Create | SCA174 | NEW | - | `L := TList<TFoo>.Create; L.Add(TFoo.Create);` (items never freed) | med | medium |
| 12 | Thread lifecycle misuse: Resume/Suspend, Synchronize in destructor, free without Terminate+WaitFor, use after FreeOnTerminate | SCA108, SCA113, SCA114, SCA177 | NEW | ui-access-in-thread, sleep-in-vcl only | `T.FreeOnTerminate := True; T.Start; T.Name := 'x';` | med | medium |
| 13 | GetMem/AllocMem/New without FreeMem/Dispose on all paths | SCA156 (GetMemWithoutFreeMem) | NEW | object-leak is TObject-only | `GetMem(P, 100); Foo(P); ` no FreeMem | med | medium (reuse object-leak flow) |
| 14 | Int64 target receives product/sum of two 32-bit operands (overflow before widening) | SCA137; DCC W1073 ? | NEW | - | `Total: Int64; Total := Qty * Price;` (both Integer) | med | medium |
| 15 | Constant/literal index out of range, string index 0 | PAL STWA4; DCC range errors | NEW | - | `C := S[0];  A[High(A)+1]` | med | medium |
| 16 | Char/WideChar tested against a set literal (truncated to 8 bit) | DCC W1050 ?; FPC (warning) ? | NEW | - | `if Ch in ['a'..'z', #228] then` with Ch: Char | med | medium |
| 17 | Use of a symbol the declaration marks deprecated/platform/library | DCC W1000, W1002, W1005 ? | NEW | deprecated-rtl-function is a fixed RTL list | `Foo.OldCall;` where `procedure OldCall; deprecated 'use NewCall';` | med | medium (needs hint-directive in index) |
| 18 | Signed/unsigned comparison or mix; comparison always true/false by range | DCC W1023, W1024, W1021, W1022, W1073 ? | NEW | constant-condition literal only | `if Cardinal(N) < -1 then` ; `if B > 255 then` (Byte) | med | medium |
| 19 | Contradictory / subsumed conditions | PAL REDU22, WARN60 (partly) | NEW | repeated-else-if-condition (identical only) | `if (X > 5) and (X < 3) then` | med | hard |
| 20 | TLS verification disabled; plaintext http:// URL | SCA116, SCA115 | NEW | - | `Client.OnValidateServerCertificate := ...(Accepted := True)`; `'http://api...'` | med | easy |
| 21 | Weak/deprecated crypto (MD5, SHA1, DES, RC4) | SCA162 | NEW | weak-random-for-security only | `THashMD5.GetHashString(Pwd)` | med | easy |
| 22 | Interface lacks GUID / duplicate GUID / generic interface with GUID | PAL STWA9, STWA10, STWA11; SD InterfaceGuid; SCA197, SCA198; FI W523/524/530 | NEW | - | `IFoo = interface procedure A; end;` then `Supports(X, IFoo)` | med | easy |
| 23 | Local variable or parameter shadows a class member / outer identifier | PAL CONV19, CONV20; FI W517 | NEW | with-hides-outer-symbol (with only) | `procedure TFoo.Set(FName: string)`; local named like a field | med | medium |
| 24 | TStringList.DelimitedText without StrictDelimiter (splits on blanks) | REPORT-1 sec 7G (no tool lists it) | NEW | - | `SL.Delimiter := ','; SL.DelimitedText := 'a b,c';` | med | easy-medium |
| 25 | Out/var parameter aliasing: same variable passed twice, or as in and out | PAL STWA8, WARN54; FI W539, W540 | NEW | - | `Swap(S, S)` with `var A, B`; `Parse(S, S)` with `out` | med | medium |
| 26 | DFM: Action plus OnClick, duplicate (DataSource,DataField), master-detail loop, component without published field | SCA043, SCA027, SCA032, SCA056, SCA031 | NEW | 2 DFM rules | `Button.Action := actSave; Button.OnClick := ...` | med | medium |
| 27 | Missing `const` on string/record/array/interface value parameter | PAL OPTI1, OPTI2, OPTI3, WARN13; FI O801; SCA170 | NEW | - | `function Foo(S: string): Integer` S never modified | med (perf) | medium (param never written/passed var) |
| 28 | Source-file character hazards: bidi override (Trojan Source), zero-width chars, non-ASCII identifiers, BOM/encoding mismatch | SCA185-193 | NEW | (encoding guard is a test script, not a rule) | U+202E inside a string/comment | med | easy |
| 29 | Raise inside a destructor; bare `raise;` outside an except handler | SCA145, SCA133 | NEW | raise-in-finally only | `destructor Destroy; begin raise EFoo.Create('x'); end;` | med | easy |
| 30 | Compiler-directive bans: {$WARNINGS OFF}, {$HINTS OFF}, switch OFF never switched back on | SD CompilerWarnings, CompilerHints; SCA171 | NEW | ifdef-undefined-symbol (other topic) | `{$WARNINGS OFF}` at unit top | med | easy |
| 31 | Unguarded `Length(x)-1` / `Count-1` index on possibly empty value | SCA049; SD IterationPastHighBound (other half) | NEW (off-by-one-count covers loop bound only) | off-by-one-count | `S[Length(S)]` or `L[L.Count-1]` with no emptiness check | med | hard |
| 32 | Random without Randomize | SCA167 | NEW | - | `X := Random(100);` no Randomize in the project | low-med | medium (project-wide) |
| 33 | ParamByName name not present in the SQL placeholders | SCA199 | NEW | firedac-open-execsql-mismatch (other check) | `SQL := 'select * from T where ID=:ID'; ParamByName('Id2')` | med | medium |
| 34 | Concrete subclass inherits an abstract method without override | PAL WARN39; SCA135 | NEW (abstract-method-instantiation is at construction) | abstract-method-instantiation | `TImpl = class(TAbstractBase) end;` not overriding abstract X | med | medium |

### 2c. NEW, value low

| # | concept | tools (ids) | status | ours | Delphi example | value | feasibility |
|---|---|---|---|---|---|---|---|
| 35 | Value parameter assigned inside the routine (and var->out / var could be const) | PAL WARN9-12, OPTI8; FI none | NEW | out-param-not-set only | `procedure P(N: Integer); begin N := N+1;` | low-med | easy |
| 36 | For-loop variable not used in loop body | PAL WARN42; FI W528 | NEW | - | `for I := 1 to 3 do Inc(Cnt);` | low | easy |
| 37 | Property read/write specifier mismatch; accessor naming Get/Set; accessor visibility | PAL WARN45, CONV14; FI C110; DCC H2369 ? | NEW | - | `property Name: string read FName write SetNam;` mismatched types | low-med | medium |
| 38 | Identifier named like a keyword/directive; redeclared System identifier | PAL WARN50, WARN49 | NEW (49 HAVE via duplicate-global-decl library masking) | duplicate-global-decl | `var Result, Index, String_ ...` | low | easy |
| 39 | Absolute variable; bad threadvar (managed or initialised) | PAL WARN14, WARN25 | NEW | - | `var B: Byte absolute A;` | low | easy |
| 40 | Empty parameter list `()` in declaration; forward directive in interface | PAL WARN37, WARN36; SD EmptyArgumentList; SCA066 | NEW | - | `procedure Foo();` | low | easy |
| 41 | Taking address of nested routine / of string character data | SD AddressOfNestedRoutine, AddressOfCharacterData; PAL STWA5 | NEW | - | `@S[1]` on a string that is then modified | low-med | medium |
| 42 | CharToPChar cast, string cast from raw pointer | SD CharacterToCharacterPointerCast; SCA130, SCA160 | NEW | - | `P := PChar(C);` with C: Char | low-med | easy |
| 43 | Math Min/Max single-overload precision trap | SD MathFunctionSingleOverload | NEW | - | `Max(1.5, X)` picks Single overload | low | medium |
| 44 | `X.Free; X := nil;` -> FreeAndNil; cast before Free (`TFoo(X).Free`) | SCA085, SCA139, SCA123; SD CastAndFree | NEW | redundant-assigned-free (other shape) | `TFoo(Sender).Free;` | low | easy |
| 45 | Override whose body is only `inherited;`; redundant inherited; multiple inherited calls | SD InheritedMethodWithNoCode, RedundantInherited; SCA125, SCA093 | NEW | inherited-bare (different) | `procedure Foo; override; begin inherited; end;` | low | easy |
| 46 | Redundant jump: trailing Exit/Continue; superfluous/double semicolon; missing semicolon | SD RedundantJump, SuperfluousSemicolon, MissingSemicolon; SCA080, SCA082 | NEW | empty-conditional (`then ;` only) | `Exit;` as last statement | low | easy |
| 47 | Empty file / unit without declarations / empty visibility section / empty interface | SD EmptyFile, EmptyVisibilitySection, EmptyFieldSection, EmptyInterface; SCA073, SCA087, SCA092 | NEW | - | `private` with no members | low | easy |
| 48 | Nested routines: count/depth; nested routine inside method | SD TooManyNestedRoutines, RoutineNestingDepth; SCA102 | NEW | - | three levels of local procedures | low | easy |
| 49 | Too many default parameters | SD TooManyDefaultParameters | NEW | too-many-parameters (count only) | `procedure P(A: Integer = 0; B: Integer = 0; C: ...)` | low | easy |
| 50 | Case statement too large | SD CaseStatementSize; SCA091 | NEW | case-with-too-few-branches (opposite) | case with 60 branches | low | easy |
| 51 | Several classes per file | SD ClassPerFile; SCA081 | NEW | unit-too-large | two unrelated classes in one unit | low | easy |
| 52 | Begin/end required on branches; asymmetric begin/end in if/else | SD BeginEndRequired; SCA099, SCA101 | NEW | - | `if A then B else begin C; D; end;` | low | easy |
| 53 | Whitespace/format: tab chars, trailing whitespace, trailing comma, digit grouping, keyword indentation | SD TabulationCharacter, TrailingWhitespace, TrailingCommaArgumentList, DigitGrouping, DigitSeparator, UnitLevelKeywordIndentation, VisibilityKeywordIndentation; SCA061-063, 068, 069, 071 | NEW | line-too-long (F2069 only) | `X := 1000000;` | low | easy |
| 54 | Case-inconsistent references to one identifier / identifiers differing only by case | PAL INCA1, INCA2; SD MixedNames; GX proofreader | NEW | confusable-identifier (underscores only) | `ListBox1` then `listbox1` | low | easy-medium (refs text vs decl) |
| 55 | Constructor/destructor naming; boolean property prefix; event property prefix On/Before/After; identifiers with numerals; hard-to-read names | PAL CONV7, CONV10, CONV11, CONV15, CONV18; SD ConstructorName, DestructorName; SCA172 | NEW | hungarian-or-short-identifier (partial for CONV15) | `constructor TFoo.Make;` | low | easy |
| 56 | Member and visibility-section ordering; consecutive sections; grouped declarations | PAL CONV17; SD MemberDeclarationOrder, VisibilitySectionOrder, Consecutive*Section, Grouped*Declaration; SCA076, SCA079, SCA095 | NEW | - | `var A, B: Integer;` ; two `var` sections in a row | low | easy |
| 57 | Legacy constructs: `object` types, unit-level `begin..end.` init, explicit `class(TObject)`, TypeAlias without `type`, inline asm (have) | SD ObjectType, LegacyInitializationSection, ExplicitTObjectInheritance, TypeAlias; SCA075, SCA088 | NEW | inline-assembly only | `TOld = object ... end;` ; `type TId = Integer;` (no strong alias) | low-med (TypeAlias med) | easy |
| 58 | Inline-var style: explicit type on inline var/const/loop var | SD InlineVarExplicitType, InlineConstExplicitType, InlineLoopVarExplicitType | NEW | - | `var X := Foo;` vs `var X: TFoo := Foo;` | low | easy |
| 59 | `Count-1` style / explicit default property / IndexLast: use `.Last`, `L[i]` | SD IndexLastListElement, ExplicitDefaultPropertyReference, ExplicitBitwiseNot ? | NEW | - | `L[L.Count - 1]` -> `L.Last` | low | easy |
| 60 | DFM hygiene: component default names, duplicate TabOrder, overlap, conflicting accelerators/shortcuts, label without colon, Hint not activated, unassigned OnClick, hardcoded UI text, unused component | PAL COWA1-COWA8; SCA024, SCA025, SCA037, SCA184 | NEW | - | `Button1`, two controls with TabOrder 3 | low-med | medium |
| 61 | DFM data-binding rules: required field without UI binding, control/field type mismatch, DB components on UI form, form with many DB components | SCA034, SCA035, SCA036, SCA039, SCA057 | NEW | - | `TDBEdit` bound to wrong field type | low | hard (needs TField model) |
| 62 | Form class without .dfm / resource | SD FormDfm, FormFmx | NEW | dfm-property-not-declared (other) | `TForm1 = class(TForm)` with no `{$R *.dfm}` | low-med | easy |
| 63 | Routines/variables in the .dpr project file | SD ProjectFileRoutine, ProjectFileVariable | NEW | - | `var Counter: Integer;` in MyApp.dpr | low | easy |
| 64 | Redundant zero/empty initialisation (fields in ctor, managed locals) | PAL REDU8-REDU11; SD VariableInitialization (?) | NEW | - | `constructor Create; begin FCount := 0; end;` | low | medium |
| 65 | Fields used in a single method (could be locals); local used only at lower scope | PAL REDU17, REDU2, REDU3 | NEW | - | `FTemp` written and read in one method only | low | easy (enclosing_symbol_id) |
| 66 | Common subexpression; default argument that can be omitted; method called once | PAL REDU20, REDU21, REDU14 | NEW | duplicate-code (token level) | `Foo(A, nil)` where nil is the default | low | medium |
| 67 | "Consider interface type": object variable could be declared as interface | PAL REDU18 | NEW | - | `L: TStringList` used only via IStrings-like members | low | hard |
| 68 | Virtual method never overridden (could be static); inline routine defined after its call; array property in loop; nested-routine capture cost; managed local declare inline | PAL OPTI4-OPTI7, OPTI9-OPTI11; FI O805 | NEW | field-by-name-in-loop (one case) | `procedure Foo; virtual;` no overrides anywhere | low | easy-medium |
| 69 | Classes with more than one destructor; non-public constructor/destructor | PAL WARN17, WARN43 | NEW | - | `destructor Done; destructor Destroy; override;` | low | easy |
| 70 | Weighted methods per class and size metrics: WMC, NOM, NOA, comment density, maintainability index | PAL Complexity Report, Totals; AM (Together metrics) ? | NEW | CK DIT/NOC/CBO/RFC/LCOM4 (no WMC) | class with 40 methods of CC 10 | low | easy |
| 71 | Near-identical identifier names (Soundex); duplicate identifiers in overlapping scope | PAL DUP1, DUP2, Similarity | NEW | confusable-identifier | `Customer` / `Custumer` | low | easy |
| 72 | ShowMessage/MessageBox left in non-UI code | SCA017 | NEW | writeln-in-source, outputdebugstring | `ShowMessage('here');` in a service | low | easy |
| 73 | SetLength(arr, Length(arr)+N) in a loop; Variant use in a loop; long concat vs Format | SCA157, SCA173, SCA044 | NEW | concat-in-loop (string only) | `SetLength(A, Length(A)+1)` in loop | low | easy |
| 74 | Runtime unit initialisation order report | PAL USES6 | NEW | cycles --plan (separate verb) | two units whose initialization sections depend | low | medium |
| 75 | SBOM / third-party dependency inventory | PAL SECU1 (experimental), Third-party Dependencies Report | NEW | unit-not-in-library (related) | CycloneDX file of units->products | low | medium |
| 76 | DUnitX attribute hygiene: [Ignore] w/o reason, [Category] w/o name, [TestFixture] without [Test], duplicate attribute | SCA179-183 | NEW | - | `[TestFixture] TFoo = class end;` | low | easy |
| 77 | Text after final `end.`; parser-level garbage | DCC W1011 ? | NEW | parser-error / syntax-error | `end.` then more text | low | easy |
| 78 | Loop that can never run (constant bounds) | DCC H2135 ? | NEW | loop-executes-at-most-once (opposite) | `for I := 5 to 1 do` | low | easy |
| 79 | Unit has no header comment; missing licence header | SCA143 | NEW | missing-doc (decl level) | unit without header | low | easy |

### 2d. PARTIAL (ours covers part)

| # | concept | tools (ids) | status | ours / what is missing | Delphi example (the missing part) | value | feasibility |
|---|---|---|---|---|---|---|---|
| 80 | Object field created in ctor never freed in destructor (unbalanced Create/Free across methods) | PAL MEMO4; SCA FieldLeak | PARTIAL? | object-leak (locals, with ownership oracle); fields across ctor/dtor not confirmed | `constructor Create; FList := TList.Create;` destructor lacks `FList.Free` | high | medium |
| 81 | Nil dereference of object results (Find/Lookup returning nil) | SCA008 NilDeref | PARTIAL | not-assigned-interface (interfaces only) | `C := Find(Id); C.Name := 'x';` | med-high | hard |
| 82 | Created twice without free in between; created in try body; referenced before create | PAL MEMO3, MEMO5, MEMO6 | PARTIAL? | create-inside-try, object-leak, used-before-assignment; overwrite-leak not confirmed | `X := TFoo.Create; X := TFoo.Create;` | med | medium |
| 83 | FreeAndNil on non-object (record, pointer, array) | SD FreeAndNilTObject; FI W531; PAL WARN56 | PARTIAL | freeandnil-on-interface only | `FreeAndNil(Rec);` | med | medium |
| 84 | Catch-all `on E: Exception` without re-raise | SD CatchingRawException; SCA078, SCA132 | PARTIAL? | bare-except (no on-clause), try-except-swallowed | `except on E: Exception do Log(E.Message);` | med | easy |
| 85 | Ambiguous unit references (same identifier from two used units, last uses entry wins) | PAL STWA2 | PARTIAL? | duplicate-global-decl (declaration side) ; reference-side check absent | `uses A, B; X := TheValue;` | med | medium |
| 86 | Possible bad assignment: narrowing integer/float assignment | PAL WARN52; DCC | PARTIAL | nativeint-truncation, win64-pointer-cast, lossy-cast; general Int64->Integer, Double->Single missing | `I32 := I64Value;` | med | medium |
| 87 | 32/64-bit parameter mismatch | PAL WARN63 | PARTIAL | nativeint-truncation covers casts, not passing a 32-bit var where 64-bit param expected | `GetWindowLongPtr(H, I32Var)` ? | low-med | medium |
| 88 | Mixed operator precedence | PAL WARN58; SCA202; FI W520 | PARTIAL | not-in-precedence, not-comparison-precedence; and/or against comparison not covered | `if A and B = C then` | med | easy |
| 89 | Format string syntax validity (bad specifier) | SD FormatStringValid | PARTIAL | format-argument-count, format-specifier-type-mismatch | `Format('%q', [X])` | low | easy |
| 90 | Boolean assignment can be shortened (any variable, not just Result) | PAL REDU16 | PARTIAL | boolean-result-returned-directly (Result only) | `if C then B := True else B := False;` | low | easy |
| 91 | Class field accessed from outside (not through a property) | PAL Class Field Access Report | PARTIAL | public-field, public-writable-field (declaration side) | `Form1.FCount := 3;` from another unit | low-med | easy |
| 92 | Custom/forbidden API and regex rules | SD ForbiddenType/Routine/Property/Field/Constant/EnumValue/Identifier/ImportFilePattern, CommentRegularExpression, StringLiteralRegularExpression; SCA023 | PARTIAL? | user .scm rules (rules\ dir) possible; no config-only forbidden-list | forbid `ShowMessage`, `TIniFile` | med | easy |
| 93 | Hardcoded strings: user-visible literals / repeated literal -> const/resourcestring | PAL LSTR2-LSTR4; SCA015, SCA152; SCA025 | PARTIAL / FILED | magic-literal covers numbers only; BL sec 4 lists `magic-string` | `ShowMessage('Saved');` x 5 | low-med | easy |
| 94 | Hardcoded IP/secret in ini | SCA201 | PARTIAL | hardcoded-ip-address (source only) | `Host=10.0.0.5` in .ini | low | easy |
| 95 | Overwritten/dead store | SD DeadStore, RedundantAssignment; PAL REDU6/7, WARN46; FI W508 | PARTIAL? | overwrite-before-read, write-only-local; cross-statement dead store on fields not covered | `X := 1; X := 2;` | low-med | hard |
| 96 | Unused locals/params and "Local variable assigned but never used" | DCC H2164 H2077 ; PAL WARN46 | HAVE (listed here for completeness) | unused-local, write-only-local, unused-parameter | - | - | - |

### 2e. FILED (already in MF / BL, not shipped)

| # | concept | tools (ids) | status | where | Delphi example | value | feasibility |
|---|---|---|---|---|---|---|---|
| 97 | TStringList.Duplicates = dupIgnore without Sorted | SD StringListDuplicates | FILED | BACKLOG.md sec 3 (M1 resolver item 4: `stringlist-duplicates-unsorted`) | `SL.Duplicates := dupIgnore;` (Sorted False) | low-med | medium |
| 98 | ParamByName inside a loop | SCA111 | FILED | BACKLOG.md sec 4 FireDAC (`parambyname-in-loop`) | `for ... do Q.ParamByName('A').Value := ...` | low-med | easy |
| 99 | magic-string (literal strings) | PAL LSTR3; SCA015 | FILED | BACKLOG.md sec 4 Maintainability (`magic-string`) | see row 93 | low-med | easy |
| 100 | Variant-record type punning | PAL (STWA6 area) | FILED (deferred) | MISSING-FEATURES.md sec 9 | `case Boolean of True: (I: Integer); False: (S: Single)` | low | hard |
| 101 | Unvalidated deserialization | REPORT-1 sec 7G | FILED (no clean signal) | MISSING-FEATURES.md sec 10 | `Stream.ReadComponent` from user file | med | hard |
| 102 | Replace Temp with Query, Primitive Obsession, Speculative Generality, Data Clumps; PAL REDU4/REDU5 set-and-used-once | PAL REDU4, REDU5 | FILED (won't-fix) | MISSING-FEATURES.md sec 14 | `T := A+B; Foo(T);` | low | medium |
| 103 | Refactoring apply (Extract Method, Change Signature, ...) | CnPack/MMX/IDE | FILED (deferred) | MISSING-FEATURES.md sec 13 | - | - | - |

### 2f. HAVE (concept -> our rule), grouped

| # | concept | tools (ids) | status | our id |
|---|---|---|---|---|
| 104 | Empty except / on-handler / finally / then / else / case branch / loop / method | PAL WARN27-35; FI W501 W502 W505 W506 W519; SD EmptyBlock EmptyFinallyBlock EmptyRoutine; SCA002 SCA020 SCA077 SCA083 SCA159 | HAVE | empty-except, empty-on-handler, empty-finally, empty-conditional, empty-case-branch, empty-loop-body, empty-procedure-body |
| 105 | Unreachable code after Exit/raise/Break | FI W509; PAL (STWA); SCA011 | HAVE | code-after-exit |
| 106 | Self-assignment; identical operands; identical then/else; repeated else-if | PAL WARN61 STWA12; FI W503 W507 W510 W512; SCA047 SCA055 | HAVE | self-assignment, comparison-same-operands, identical-then-else, repeated-else-if-condition |
| 107 | Constant condition | PAL WARN60; DCC W1021/22 | HAVE (literal level; see NEW 18/19 for logic level) | constant-condition |
| 108 | Float equality | PAL WARN59; FI W542; SCA144 | HAVE | float-equality-comparison |
| 109 | Missing inherited in ctor/dtor; destructor not override; virtual call in ctor | PAL WARN15 WARN16; FI W504 W525 W522; SD ConstructorWithoutInherited; SCA048 SCA096 SCA097 | HAVE | missing-inherited-ctor, missing-inherited-dtor, destructor-without-override, virtual-method-in-constructor |
| 110 | Property references itself | PAL STWA1; FI W527 | HAVE | property-references-itself |
| 111 | Raise raw Exception; re-raise loses stack; exception constructed not raised; raise in finally; duplicate on-class | SD RaisingRawException ReRaiseException MissingRaise; FI W529; PAL WARN48 | HAVE | raise-bare-exception, reraise-loses-stack, exception-constructed-but-not-raised, raise-in-finally, duplicate-exception-handler |
| 112 | Exit/Break/Continue in finally (dangerous Exit) | PAL WARN20 WARN21 | HAVE | control-flow-in-finally |
| 113 | Format() argument count / type | PAL WARN64; FI W513 W537; SD FormatArgumentCount FormatArgumentType; SCA005 | HAVE | format-argument-count, format-specifier-type-mismatch |
| 114 | IfThen evaluates both branches | SD IfThenShortCircuit; SCA131 | HAVE | ifthen-both-branches |
| 115 | Off-by-one `0 to Count`; loop runs at most once | FI W514; SD IterationPastHighBound LoopExecutingAtMostOnce; SCA203 | HAVE | off-by-one-count, loop-executes-at-most-once |
| 116 | Non-exhaustive enum case; case without else | PAL WARN57; FI W535; SD ExhaustiveEnumCase; SCA168 | HAVE | exhaustive-enum-case (OFF by default) |
| 117 | Function result not set / out param not set | PAL WARN18 WARN51; FI W521; DCC W1035; SCA121 SCA196 | HAVE | function-result-not-set, out-param-not-set |
| 118 | Used before assignment / uninitialised | PAL WARN3 WARN4 WARN7 WARN8; DCC W1036; FPC; SCA166 | HAVE | used-before-assignment |
| 119 | Set but never read / referenced never set | PAL WARN5 WARN6 WARN46 WARN3; DCC H2077 | HAVE | write-only-local, referenced-never-set |
| 120 | For-loop variable read after loop | PAL WARN40 WARN41; DCC W1037 | HAVE | loop-var-after-loop |
| 121 | Unused local / parameter / private member / public symbol / unit in uses / constant / type / field | DCC H2164 H2219; PAL REDU1 REDU24; FI O802 O803 O804; SD Unused*; SCA007 SCA052 SCA053 SCA054 SCA147 SCA164 | HAVE | unused-local, unused-parameter, unused-private-member, unused-public-symbol, unused-unit-in-uses |
| 122 | Unprotected Free; Create inside try; use after free; double free; object leak | PAL MEMO1 MEMO2 MEMO3 MEMO7; FI W511 W515; SCA009 SCA134 | HAVE | unprotected-object-free, create-inside-try, use-after-free, double-free, object-leak |
| 123 | Interface/object mixing; FreeAndNil on interface; interface ref cycle | PAL WARN53; FI W531; SD ObjectPassedAsInterface | HAVE (partly, see 5, 83) | interface-object-mixing, freeandnil-on-interface, interface-reference-cycle |
| 124 | Abstract method instantiation | PAL WARN26 | HAVE | abstract-method-instantiation |
| 125 | Critical section / lock not released | SCA109 SCA153 | HAVE | criticalsection-not-released |
| 126 | UI access from thread; Sleep in VCL | (none list it directly; SCA108 related) | HAVE | ui-access-in-thread, sleep-in-vcl |
| 127 | Redundant boolean comparison / parentheses / cast / not not / as TObject / Assigned+Free guard | PAL REDU15 REDU19 REDU23; FI C109; SD RedundantBoolean RedundantParentheses RedundantCast AssignedAndFree; SCA072 SCA084 SCA094 | HAVE | boolean-comparison-true, redundant-parentheses, redundant-cast, redundant-not-not, redundant-as-tobject, redundant-assigned-free |
| 128 | Nil comparison -> Assigned | SD NilComparison; SCA126 | HAVE | nil-comparison |
| 129 | with / nested with / multiple with / ambiguous with refs; goto | PAL CONV13 CONV29 WARN38 CONV16; FI C108; SD WithStatement GotoStatement; SCA045 SCA060 SCA155 | HAVE | with-statement, nested-with, with-multiple-items, with-hides-outer-symbol, goto-statement |
| 130 | Commented-out code; TODO markers | SD CommentedOutCode; PAL To-Do Report; SCA019 SCA070 | HAVE | commented-out-code, compiler-magic-comments |
| 131 | Method length / params / locals / nesting / exit points / cyclomatic / cognitive / unit size | FI C101-C103; SD TooLargeRoutine TooManyParameters TooManyVariables Cyclomatic Cognitive; PAL Complexity; SCA012 SCA013 SCA018 SCA022 SCA140 SCA176 | HAVE | method-too-long, too-many-parameters, too-many-locals, deep-nesting, too-many-exit-points, cyclomatic-complexity, cognitive-complexity, unit-too-large |
| 132 | Clone detection | PAL CLON1 CLON2, WARN47; SCA021 | HAVE | duplicate-code |
| 133 | CK metrics: DIT NOC CBO RFC LCOM; fan-in/out; god class | PAL OO Metrics; SCA138 SCA141 | HAVE | deep-inheritance, too-many-children, high-coupling, high-response, low-cohesion, fan-in, fan-out, instability, god-class |
| 134 | Naming: T/E/I/P prefix, F field, param prefix, casing, keyword casing, unit=file | PAL CONV1-4 CONV23-27 INCA3; FI C104-C107 C111; SD *Name rules LowercaseKeyword UnitName; SCA064 SCA100 SCA103-106 SCA118 SCA119 | HAVE | type-name-prefix, field-name-prefix, param-name-prefix, const-casing, local-var-casing, method-pascalcase, reserved-word-casing, unit-name-matches-file, local-field-prefix |
| 135 | Public field / class fields not private | PAL CONV5 CONV22; SD PublicField; SCA089 | HAVE | public-field, public-writable-field |
| 136 | Multiple statements per line; Hungarian/short ids | PAL CONV32; SD ShortIdentifier | HAVE | multiple-statements-per-line, hungarian-or-short-identifier |
| 137 | Assert without message; side effects in Assert | SD AssertMessage; SCA074 SCA169 | HAVE | assert-call, assert-with-side-effect |
| 138 | Inline asm | SD InlineAssembly; PAL NEXT3; SCA067 | HAVE | inline-assembly |
| 139 | Win64 / NativeInt / pointer casts / PChar arithmetic / SizeOf pointer | SD PlatformDependentCast PlatformDependentTruncation; PAL STWA5 WARN63; FI W541; SCA158 SCA161 | HAVE | win64-pointer-cast, nativeint-truncation, pchar-arithmetic, sizeof-pointer-assumption |
| 140 | Ansi lossy cast | DCC W1057 W1058; SD UnicodeToAnsiCast; SCA129 | HAVE | lossy-cast |
| 141 | Locale-sensitive conversions; default encoding I/O | SD DateFormatSettings ImplicitDefaultEncoding; SCA059 SCA128 | HAVE | locale-sensitive-conversion, default-encoding-io |
| 142 | Unsafe string API; deprecated RTL | DCC W1000; PAL; SD | HAVE | unsafe-string-api, deprecated-rtl-function |
| 143 | SQL injection; hardcoded credential/connection/IP/path; shell exec; path traversal; temp file; weak random | SCA003 SCA004 SCA016 SCA163 SCA178 SCA200; YSC | HAVE | sql-injection-concat, hardcoded-credential, hardcoded-connection-string, hardcoded-ip-address, hardcoded-absolute-path, unsafe-shellexecute, path-traversal, insecure-temp-file, weak-random-for-security |
| 144 | DFM credentials; DFM property not declared | SCA026; YSC; PAL Missing Property Report | HAVE | dfm-hardcoded-credential, dfm-property-not-declared |
| 145 | FieldByName in loop; dataset left open | SCA112 | HAVE | field-by-name-in-loop, dataset-open-without-close |
| 146 | String concat in loop; Length(s)=0; UpperCase compare | SCA110; SD (none) | HAVE | concat-in-loop, length-zero-compare, uppercase-compare |
| 147 | Circular uses; uses vs dpr; unit not found | PAL USES2 USES3 USES7; SCA194 SCA195 | HAVE | circular-uses, unit-not-in-dpr, used-unit-not-resolvable, cycle-participant-unit |
| 148 | Unsafe hard cast without `is` | DCC W1044; SD NonLinearCast | HAVE | unsafe-typecast-without-is (OFF) |
| 149 | Undocumented public API; doc comment drift | DCC W1201-W1208 (XML doc); SCA117 | HAVE | missing-doc, doc-drift, doc-param-not-in-signature, doc-param-no-description |
| 150 | Function result ignored (function called as procedure) | PAL WARN44 REDU12 | HAVE | function-result-ignored (OFF), discarded-effect-free-result |
| 151 | Duplicate declarations across units / masking RTL names | PAL WARN49, DUP1 | HAVE | duplicate-global-decl |
| 152 | ClassName compared to string | FI W538 | HAVE | classname-string-compare |
| 153 | Compile-limit hazards (line > 1020 chars) | DCC F2069 | HAVE | line-too-long |

Row counts (153 rows): NEW 79, PARTIAL 16, FILED 7, HAVE 51 (HAVE rows 104-153 are grouped, each covering several concepts).

## 3. Things we have that none of the surveyed tools have (checked against rule lists above)

- interface-reference-cycle (ARC leak across interface fields): no tool in the survey lists it (REPORT-1 sec 8 point 2 still holds).
- Index-backed project rules: layering-violation (architecture DAG over uses-graph), global-only-uses-edge, uses-global-census, cycle-participant-unit (PAL has Uses Report and Lattix.xml export, but no rule-style layering check), dependent-project-not-recompiled, platform-divergent-define, ifdef-undefined-symbol, unit-not-in-library.
- Effect-purity rules built on a proven-effect oracle: assert-with-side-effect (SCA169 has a syntactic cousin), query-name-with-effect, discarded-effect-free-result, separate-query-from-modifier.
- enum-ordinal-persisted, enum-bare-read-scoped, enum-read-inside-with, enum-helper-separate-units ($SCOPEDENUMS and helper hazards).
- stat-gated-destructive (destructive act gated on a file-existence check).
- uppercase-compare-always-false (and the correct-case sibling uppercase-compare).
- firedac-open-execsql-mismatch (SCA has ParamByName/placeholder, not Open vs ExecSQL).
- Fowler refactoring signals as lint: feature-envy, split-variable, middle-man, message-chain, repeated-type-switch, boolean-flag-parameter, loop-control-flag, mutable-global-variable (nobody else; SD/PAL stop at classic smells).
- CK extras: fan-in, fan-out, instability (PAL stops at the CK suite; SD has none).
- Review-marker governance family (review-marker-stale, -unused, -malformed, -placeholder-hash, -reason-unreviewed): suppression hygiene; SCA has SCA165 (unused noinspection) only.
- hardcoded-absolute-path with sink modelling (SCA016 has a flat check).
- dfm-property-not-declared checked against the component class hierarchy (SCA/PAL check DFM against code, not class property declarations).
- Cross-project index awareness: dependent-project-not-recompiled, drag-lint reconcile-project, doc-orphan-block.
- Rule-quality tooling: --fix with dry-run default, baselines, SARIF, per-rule thresholds (SCA also has SARIF + baseline; PAL/FI lack CI-grade output).

## 4. Sources

- Peganza Pascal Analyzer help: https://www.peganza.com/PALHelp/ ; report pages strong_warnings_report.htm, warnings_report.htm, optimization_report.htm, code_reduction_report.htm, memory_report.htm, convention_compliance_report.htm, inconsistent_case_report.htm, nextgen_readiness_report.htm, uses_report.htm, duplicate_identifiers_report.htm, similarity_report.htm, literal_strings_report.htm, used_outside_report.htm, class_field_access_report.htm, control_warnings_report.htm, events_report.htm, missing_property_report.htm
- Pascal Analyzer / Expert 9.20.0 announcement (2026-03-26): https://en.delphipraxis.net/topic/15251-ann-march-updates-for-pascal-analyzer-pascal-expert-and-pascal-browser/
- Pascal Expert review (142 checks): https://ideasawakened.com/post/product-review-pascal-expert
- TMS FixInsight product page (EOL notice, Personal/Pro): https://www.tmssoftware.com/site/fixinsight.asp
- FixInsight rule ids (W5xx/C1xx/O8xx): C:\Projects\Delphi-RAG-lint\docs\lint\REPORT-1-delphi-lint-landscape.md sec 4 (secondary; vendor PDF not reached); 2016.03 release note https://blogs.embarcadero.com/fixinsight-version-2016-03-code-analysis-tool-for-embarcadero-delphi-has-been-released/
- SonarDelphi: https://github.com/integrated-application-development/sonar-delphi (releases v1.21.0 2026-09-04; checks list from repo tree; CHANGELOG.md)
- DelphiLint: https://github.com/integrated-application-development/delphilint (v1.3.0 2025-01-21)
- nrodear StaticCodeAnalyser: https://github.com/nrodear/StaticCodeAnalyser (README.md, docs/rules.md, DETECTORS.md)
- arbsis Y.StaticCodeAnalyser: https://github.com/arbsis/Y.StaticCodeAnalyser
- CodeHealer (SOCK Software): https://www.drbob42.com/review/healer.htm ; https://wiert.me/2020/06/02/
- GExperts: https://www.gexperts.org/ ; CnPack: https://github.com/cnpack/cnwizards
- Delphi compiler messages: https://docwiki.embarcadero.com/RADStudio/Athens/en/Error_and_Warning_Messages_(Delphi) (403, not read; ids from REPORT-1 and memory); Marc Durdin table https://marc.durdin.net/2012/05/delphi-xe2s-hidden-hints-and-warnings-options/
- Audits and Metrics: https://docwiki.embarcadero.com/RADStudio/Athens/en/Audits_and_Metrics (403 / docwiki MCP no response; row marked ?)
- Free Pascal messages: https://www.freepascal.org/docs-html/current/user/ (not read; memory)
- Our own: docs/lint/MISSING-FEATURES.md, docs/lint/BACKLOG.md (sec 3, 4), scratchpad/our-rules.tsv

