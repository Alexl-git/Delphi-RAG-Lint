<!-- dl:backlog status=open last-measured=2026-10-27 -->
# Rule-gap survey 2026-10-27 -- C/C++ and Delphi linters vs drag-lint 1.35.1 (195 rules)

Written by WEBSITE (www-5b) at the owner's request; input for ENGINE's rule backlog. Not a plan.
Detail tables:

* `SURVEY-2026-10-27-delphi-linters.md` -- 153 concepts: HAVE 51, PARTIAL 16, FILED 7, NEW 79.
  Tools: Peganza Pascal Analyzer / Pascal Expert, FixInsight, SonarDelphi, RAD Studio
  Audits & Metrics, compiler W/H, CodeHealer, ModelMaker CE, DelphiLint, FPC, nrodear
  StaticCodeAnalyser.
* `SURVEY-2026-10-27-c-cpp-linters.md` -- 134 concepts: HAVE 44, PARTIAL 19 (+2 unsure),
  FILED 7, NEW 62; 18 themes dropped (no Delphi analogue). Tools: clang-tidy, Cppcheck,
  Clang SA, GCC, MISRA, CERT, PVS-Studio, SonarQube C++, PC-lint Plus, Coverity.

## Caveats (read before trusting a status)

* "HAVE" / "NEW" was judged from rule TITLES (`drag-lint rules --json`), not rule code.
  BACKLOG.md (520 KB) was only partly searched, so some NEW rows may already be filed.
* Primary sources fetched: Peganza, SonarDelphi, nrodear, clang-tidy, PVS-Studio, Cppcheck
  (categories). FixInsight, compiler W/H ids, Audits & Metrics, CodeHealer, ModelMaker,
  FPC, CSA, GCC, Coverity, Sonar C++, PC-lint, MISRA, CERT ids are from REPORT-1 or memory
  and are marked "?" in the detail files.
* WEBSITE spot-checked both top-10 lists against the 195 titles: all are absent, except
  that the DFM-event-handler item is PARTIAL (dfm-property-not-declared covers properties,
  not events) and the "interface uses only the implementation needs" item sits next to
  unused-unit-in-uses / global-only-uses-edge without being covered by either.

## Combined shortlist (both surveys, de-duplicated, by value then feasibility)

| # | Concept | Delphi form | Seen in | Ours | Feasibility |
|---|---|---|---|---|---|
| 1 | Owned field created in the constructor, never freed in Destroy | `FList := TList.Create;` in Create, no `FList.Free` | PVS, Coverity, Peganza | PARTIAL: object-leak is per-routine | medium |
| 2 | Wrong size in Move / FillChar | `FillChar(P, SizeOf(P), 0)` on a pointer; `Move(S[1], B, Length(S))` without `SizeOf(Char)`; managed record | PVS, clang-tidy, Cppcheck, Peganza | NEW | medium |
| 3 | Method hides an ancestor virtual (no override / reintroduce) | `procedure Paint;` over a virtual `Paint` | compiler W1010, Sonar, FixInsight | NEW (compiler warns; a lint can name the fix) | easy |
| 4 | Constructor called on an instance | `Obj.Create;` | FixInsight, PVS analogue | NEW | easy |
| 5 | Anonymous method captures a loop / inline variable | `for var I ... TThread.Queue(nil, procedure begin Use(I) end)` | clang-tidy analogue, Sonar | NEW | medium |
| 6 | IndexOf / Pos result used as an index unchecked | `L[L.IndexOf(S)]` | PVS, CERT | NEW | medium |
| 7 | Deref of a call result that may be nil | `FindComponent('X').Tag` | CSA, Coverity, PVS | PARTIAL? (not-assigned-interface is interfaces only) | medium |
| 8 | Use before its own nil / bounds check | `X.Foo; if Assigned(X) then` | PVS V595, Cppcheck | NEW (CFG engine exists) | medium |
| 9 | Exception escaping TThread.Execute or a destructor | `raise` in Destroy; Execute without try/except | clang-tidy bugprone-exception-escape, Sonar | NEW | easy |
| 10 | Unconditional self-recursion | `function F: Integer; begin Result := F; end;` | GCC, PVS, Sonar | NEW (property-references-itself is the property case only) | easy |
| 11 | Manual Free of an item owned by an OwnsObjects container | `List.Add(O); ... O.Free;` | Coverity analogue | NEW | medium |
| 12 | Collection mutated while iterated | `for O in L do L.Remove(O)` | Sonar, PVS, CERT | NEW | easy-medium |
| 13 | DFM event handler missing / orphan handler | `OnClick = Button1Click` with no method | Peganza, nrodear | PARTIAL (properties only) | easy |
| 14 | UPDATE / DELETE literal without WHERE | `'DELETE FROM T'` | Sonar SQL, nrodear | NEW (we parse SQL already) | easy |
| 15 | Copy-paste typo in near-identical statements | `R.Left := A.Left; R.Top := A.Left;` | PVS V778 / V537 | NEW, heuristic | medium |
| 16 | Integer multiply widened afterwards (overflow before widening) | `I64 := A * B;` (Integer A, B) | clang-tidy, CERT INT30, PVS | NEW | medium |
| 17 | Fresh instance passed to a const / interface parameter | `Proc(TFoo.Create)` with an interface param | Sonar, FixInsight | NEW | medium |
| 18 | Interface uses entry only the implementation needs | uses in interface, all refs in implementation | Peganza, FixInsight | NEW (feeds cycles --plan) | easy |
| 19 | Public member used only inside its own unit / class | could be private | Peganza | NEW (unused-public-symbol is the zero-use case) | easy |
| 20 | Must-use results ignored (RTL, Win32 BOOL, Stream.Read count) | `S.Read(Buf, N);` | clang-tidy, CERT, GCC | PARTIAL: function-result-ignored is same-unit only | medium |
| 21 | Begin/End pairing generalised | BeginUpdate / DisableControls / StartTransaction without the pair in finally | PVS, Coverity | PARTIAL? | medium |
| 22 | Taint from source to sink | user text to SQL / ShellExecute / file path | Coverity, Sonar | PARTIAL: sql-injection-concat, unsafe-shellexecute are local | hard |

## Standards pass (CWE, CERT, MISRA, Clippy, DerScanner)

Detail: `SURVEY-2026-10-27-standards-cwe-cert-misra-clippy.md`. Counts are HAVE / PARTIAL /
NEW, plus the NEW rows already in the tables above:

* CWE (Top 25 2025, CWE-1305, CWE-1340): 17 / 17 / 21, plus 8.
* CERT C: 7 / 15 / 9, plus 10.
* MISRA themes: 3 / 10 / 2, plus 4.
* Clippy: 3 / 1 / 31, plus 1.
* DerScanner: the Delphi rule list is not public.

Top new items, not in the shortlist above:

| # | Concept | Standard |
|---|---|---|
| 23 | Weak hash / cipher (MD5, SHA1, DES for secrets) | CWE-327/328 |
| 24 | Indy / HTTP client without timeout (Indy default is infinite) | CWE-1088 |
| 25 | Cleartext transport (`http://`, SMTP/FTP without TLS) | CWE-319 |
| 26 | Returning a local's address (`PChar(LocalStr)`, `@Local`) | CWE-562 |
| 27 | Mismatched alloc / free (`GetMem` + `Dispose`) | CWE-762, CERT MEM34 |
| 28 | `FreeOnTerminate` then `WaitFor` / `Free` | CERT CON39 |
| 29 | Exception text shown to the user / returned in a response | CWE-209/200 |
| 30 | Password stored in clear (INI, registry); DFM password edit with no PasswordChar | CWE-312, CWE-549 |
| 31 | Constant index out of range; comparisons that are always true or false on unsigned types | Clippy out_of_bounds_indexing, absurd_extreme_comparisons |
| 32 | Blocking call while holding a lock; LoadLibrary with a relative name; XXE | Clippy await_holding_lock, CWE-427, CWE-611 |

Easy Clippy style analogues are also NEW: nonminimal_bool, collapsible_if, needless_return,
redundant_else, match_same_arms (case), shadowing, large_stack_arrays.

**CWE tagging (recommended):** add `cwe: [..]` to rule metadata and expose it in
`rules --json` / `lint --json`. In SARIF, add a CWE taxonomy plus `relationships` and
`external/cwe/cwe-N` tags. Lint metadata only, so no extractor bump. Section F of the
detail file maps about 70 of the 195 rules to CWE ids by hand.

## Market notes

* nrodear StaticCodeAnalyser, checked 2026-10-27 (GitHub API + README): author Nicolas
  Gerlach, Bremen; a single committer (about 3,000 commits); created 2025-05; v0.9.18
  (2026-09-10); 41 stars. Its OWN Pascal tokeniser and recursive-descent parser
  (`SCA.Engine/sources/Parsing/uLexer.pas`, `uParser2.pas`, `uAstNode.pas`, `uCFG.pas`) and
  its own DFM lexer and parser (binary DFM too). No DelphiAST, tree-sitter or libclang.
  `--index-root` gives a cross-unit index; no symbol or type resolution is documented, and
  the leak rule matches ownership patterns. It has an IDE plugin (D12 Win32, D13 Win32/64),
  a GUI and a CLI, plus Lazarus/FPC support. Output: SARIF, Sonar generic issues (and a
  push), HTML, CSV, JSON, Jira and a baseline file.


* nrodear StaticCodeAnalyser (MIT, 203 rules, pushed 2026-10-26) now has more rules than
  drag-lint and overlaps the CLI / SARIF / DFM / security niche -- worth a closer look.
* FixInsight's vendor page says "End of Life". SonarDelphi 1.21.0 (2026-09-04).
  Peganza 9.20 (2026-03) added only an experimental SBOM report.
* Only drag-lint has (per the Delphi survey, section 3): interface-reference-cycle,
  layering-violation, the effect-purity rules, the enum-ordinal rules, the Fowler
  refactoring signals, cycles --fix.

## Suggested next step (owner / ENGINE)

Check the 22 rows against BACKLOG.md and the rule code, then pick a batch. Items 3, 4, 9,
10, 13, 14, 18 and 19 are easy and high value; 1, 2, 6, 7, 8 are medium and catch real bugs.
