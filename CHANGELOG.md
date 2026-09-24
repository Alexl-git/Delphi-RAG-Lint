# Changelog

All notable changes to Delphi-RAG-Lint. This project is **alpha -- expect
breaking changes** until v1.0.

## Unreleased

### Fixed (extractor 1.18.0-alpha -> 1.19.0-alpha: every index re-parses once)

- **D18 -- `symbol_facts.sql_reads` now sees SQL built line by line.** Consecutive
  `<ds>.SQL.Add('...')` / `.CommandText.Add` (and `SelectSQL`/`InsertSQL`/`ModifySQL`/`DeleteSQL`/
  `RefreshSQL`) statements of one statement list are assembled per receiver, in order, and run through
  the same classify/extract pipeline as a single literal. Any other statement ends the run; a
  comment or directive between two Adds does not; a non-literal argument drops the run. Measured on
  ORM3 SERVER: routines with `sql_reads` 19 -> 112 (distinct tables 14 -> 104), `sql_writes`
  unchanged at 148, purity unchanged. Guard: `tests\autotest\run_sql_reads_multiline_add.ps1`.
- **D19 -- the SQL-script extractor keeps QUOTED identifiers.** `"ACTION"` / `"TABLE"` columns (and
  `CREATE TABLE "Name"`) are stored the Firebird way: quotes stripped, `""` unescaped, case verbatim
  (`docs\INDEX-SCHEMA.md`). Same routine: the table-constraint skip is now whole-word, so columns
  `UNIQUE_FLAG` / `CONSTRAINT_NAME` are no longer dropped. Measured on the 12 scripts of
  `drag-lint-sql.sqlite`: `sql_column` rows 3820 -> 3826 (MS1.SQL `IPCHART.ACTION`,
  `FOLDERCOUNT.TABLE`, 2x `UNIQUE_FLAG`, 2x `CONSTRAINT_NAME`). Guard:
  `tests\autotest\run_sql_quoted_identifiers.ps1`.
- **P1 -- Delphi 12+ multi-line string literals no longer break the parse.** The grammar's
  triple-quote token loses to its single-quote token when the body holds an odd number of
  apostrophes (and has no 5-quote form), failing the whole unit at 1:1; the directive lexer read a
  body line as code, so an IFDEF written in the text became live. `Preprocess` now runs
  `NeutralizeMultilineStrings` first (unconditionally): in the literal's body apostrophes,
  open-braces and the `(` of `(*` become spaces, a 5+-quote delimiter becomes `'''`. Byte length and
  every LF preserved. Not applied under `--no-preprocess`. The grammar fix proper belongs to
  tree-sitter-delphi13. Guard: `tests\preprocess\run_multiline_string.ps1`.

### Added

- **Resolver 1.8.0-alpha -- bare WRITES bind (D13).** A fifth calls-stage stream
  (`ResolveWriteRefs` -> `TCallResolver.ResolveWriteRef`) sets `refs.symbol_id` for a `write` ref
  (`X:= ...`) to the local, parameter, field, property, class var or unit-level var/const it
  assigns -- Delphi's scope order, certain or nothing, identity only (no call_edges /
  member_accesses row). Declines counted on a new `writes:` log line: `Result`, the function's own
  name, a `with` above the site, two equally near candidates, not found. ORM3 CLIENT: 0 -> 17,720 of
  32,909 write refs bound (10,481 `Result`, 4,417 `with`, 240 not found, 49 own-name, 2 ambiguous);
  the stream costs 30.5 s of a 331 s whole-DB calls stage there. Guard:
  `tests\callresolve\run_write_refs_bind.ps1` (12 positives, 5 negatives, log line, scoped unbind).
  **Merged with the `with`-scope work (D14) into the same 1.8.0-alpha:** the write stream now asks
  `WithScopeAt` at the write's position instead of declining every write below any `with` in the
  routine -- a with target's property/field binds, a name the fully typed target lacks falls through
  to the ordinary scopes, a write after a completed `with` binds normally, and only an untypable
  target (or one whose ancestry leaves the index) declines. Rung 4b likewise declines when the with
  scope may own the receiver's first segment (an untypable target's member spelled like a unit had
  bound to that unit's routine). Same CLIENT copy, merged build: 17,720 -> **21,916** write refs bound
  (with-scope declines 4,417 -> 215; +4,196 = 2,096 fields, 2,060 properties, 40 locals after a
  closed `with`; none of the 17,720 lost or moved); `call_edges` 23,784 (with-scope build) -> 23,790
  (+6, ENG-16); `member_accesses` 13,630 unchanged; effect-free 2,918; `assert-with-side-effect` 0.
  Guards: `run_write_refs_bind.ps1` (15 positives incl. W-WITH-MEMBER / W-WITH-FALLTHROUGH /
  W-AFTER-WITH, NEG-WITH-UNDECIDED), `run_unit_qualified_call_bind.ps1` (NEG-WITH-UNDECIDED).
- **Resolver 1.8.0-alpha -- unit-qualified free-routine calls bind (ENG-16).** Rung 4b of
  `ResolveOne`: `Pipes.Commands.DispatchCommand(...)`, `uHelp.DoIt` -- the receiver resolves to ONE
  unit and the routine is picked by arity among that unit's visible routines; a local/member spelled
  like the unit shadows it. ORM3 CLIENT: 6 unbound sites (5 calls + 1 parenless) -> 0. Guard:
  `tests\callresolve\run_unit_qualified_call_bind.ps1`.

- **Project tags on shared doc facts, and `doc-forget` to reap them (ENG-4).** On a block reconciled
  across projects (a `dl:shared` unit, or one holding facts the current index cannot see) each inbound
  entry carries the projects whose index rendered it: `Called from: [DataCopy,DataCopyTests]uX.Foo
  (uX.pas)`. The tag is the `--db` base name; a run adds/removes only its own tag and an entry goes
  when its set empties, so a caller deleted in project P now disappears on P's next run (the untagged
  union could never reap it). Untagged legacy entries keep the old rules; a wholly untagged line that
  has not changed is left byte-identical; once a line is tagged the other projects adopt their entries
  on their next run. New verb `doc-forget --scope <file|dir> (--project <Tag> [--rename <Tag>=<New>] |
  --untagged | --list-tags) [--apply|--no-backup]`, text-only. Guard:
  `tests\autodoc\run_doc_project_tags.ps1` (two fixture projects sharing one unit, 45 checks).
- **`document --migrate-pure`.** The explicit switch for the deferred purity-v1 migration (see Fixed).
- **`convert-validate` checks `G[I/N]` glyph expressions on `#link` (CV-4, the validate half of
  the glyph grammar).** `#link <ToPath> <- <FromPath> G[..] [: <Cast>]`: the expression is split off
  at the first ` G[` and kept verbatim (`TConversionRule.GlyphExpr`), so FromPath is the bare source
  property again. New pure unit `src\report\DRagLint.Convert.GlyphExpr.pas` (`ParseGlyphExpr`,
  `ValidateGlyphExpr`, `IsGlyphCountExpr`, `IsGlyphCountPropName`). Errors, with the rule line AND the
  column inside the expression, in parse-only mode too: malformed term, I < 1, N < 1, I > N, mixed
  denominators, two alternatives for one N, two denominator-less alternatives, `G[count]` not alone,
  and `G[count]` without exactly one image link from its FromPath in its `#convert` block. New
  `line N: warning:` output (exit code unchanged) for a straight `NumGlyphs` carry beside a G-link.
  `convert-apply`/`convert-reemit` REFUSE a G-linked book (exit 1) until CV-2 realises it, rather
  than carry the image whole. Not yet: the no-N-reader class error (needs CV-2's reader table).
  Guard: `tests\autotest\run_convert_glyph_expr.ps1` (38 checks). No extractor/resolver bump.
- **New rule `enum-read-inside-with` (bug-patterns, warning, ON by default).** A bare name inside a
  `with` body that is BOTH a member of a with-target (class with ancestry, or record) AND a read the
  index binds to an enum value. The compiler binds the member; the resolver records the enum value
  (risk R7, `docs\MEASURED-enum-value-refs-2026-09-23.md`). The message names both. It needs the
  same-named member and the index's own enum_value binding at that exact position, so the bare
  "enum read in a with-bearing routine" population stays silent. `with-hides-outer-symbol` did not
  already cover it (measured: silent on the positive fixture). Emitted from the same walk as
  `with-hides-outer-symbol`, sharing its with-target surfaces. Guard:
  `tests\autotest\run_enum_read_inside_with.ps1` (17 checks). 183 -> 184 rules.
- **`assert-with-side-effect`** (project-wide, warning, OFF by default) -- a resolved call inside
  `Assert(Cond[, Msg])` to a routine with a PROVEN effect (`symbol_facts.effect_free = 0` and a stored
  `effect_summary` carrying `g`, `h`, `s` or `p<k>`). Release builds compile `Assert` out, so the effect
  happens in Debug only. A summary that is only `?`, an unbound or ambiguous callee, and a same-line call
  outside the Assert never fire; the message carries the callee's summary and witness. OFF for the same
  reason as the two purity v2 rules: it needs a resolved index with the `purity` stage. Rule count
  184 -> 185 (132 built-in). Guard: `tests\lint-project\assert-side-effect\run_assert_side_effect.ps1`.
- **New rule `ifdef-undefined-symbol` (project-wide, warning, OFF by default).** Flags `{$IFDEF X}`, `{$IFNDEF X}` and `defined(X)` in `{$IF}`/`{$ELSEIF}` where `X` is defined nowhere: not a compiler-predefined conditional for any platform (`VER<nnn>`, `CPU*`, `MSWINDOWS`, `WIN32`, `CONSOLE`, ...; `DEBUG`/`RELEASE` are NOT predefined), not in any `DCC_Define` of any PropertyGroup of the `.dproj` (the union over every config and platform, including `Base_<P>` and `Cfg_N_<P>`), not `{$DEFINE}`d anywhere in the unit or its `{$I}` includes, and not in the new `drag-lint-lint.json` top-level `"ifdef_allow": [...]` list. A `$DEFINE` in another unit or the `.dpr` does not count -- the compiler scopes it to its own module. Runs only with a project (`--project`, or the project that owns `--db`); a bare `lint <file>` reports nothing, and a file whose `{$I}` cannot be resolved is skipped. The message suggests the nearest defined symbol within edit distance 2. Measured on ORM3 CLIENT (151 of 152 `.dproj` members): 175 findings over 6 symbols (`TRACE_BP`, `TRACE_BP3`, `TRACE_BP6`, `TRACE_CODESITE`, `M2022_REFERENCE`, `NOABLAS`), all deliberate trace switches, none a typo; the `.dpr`'s `{$IFDEF EurekaLog}` (defined only in `Base_Win32`/`Base_Win64`) is silent. Hence OFF by default: opt in with `--rule ifdef-undefined-symbol` or `"enabled"`. New unit `src\lint\DRagLint.Lint.IfdefUndefined.pas`, outside the extractor surface (no extractor bump). Guard: `tests\autotest\run_ifdef_undefined_symbol.ps1`. Rule count 185 -> 186.
- **New rule `review-marker-placeholder-hash` (review-markers, hint, ON by default).** A `dl:ok` whose
  `@hash` was never computed -- `@0000` or non-hex (`@xxxx`) on a `//` marker, or an `@0000` marker
  stranded in a `{ }` / `(* *)` / `///` comment, where no marker is ever read. It suppressed nothing and
  was reported by nothing (a block-comment marker) or misreported as `review-marker-stale` /
  `-unused` (a `//` one). A hash that matches the line is still honoured, so a genuine `@0000` (1 in
  65536) verifies. In block comments only a KNOWN rule id with an ALL-ZERO hash counts, so prose quoting
  the grammar stays silent: 1 finding on this repo (`DRagLint.Analysis.LintTree.pas`, now a live
  marker), 0 across the 282 `dl:ok` lines in DataCopy/YADF/ORM3. INBOX B1.
  Guard: `tests\autotest\run_review_marker_placeholder_hash.ps1`.
- **New rule `review-marker-reason-unreviewed` (review-markers, hint, OFF by default) and the optional
  `REVIEWED <yyyy-mm-dd>` stamp** (owner ruling OWN-7). Write `REVIEWED 2026-09-23` anywhere in a
  marker's reason (uppercase, case-sensitive, whole word) to record when it was last re-read; it is a
  comment, so it never changes the `@hash` or makes the marker stale (pinned). The rule flags a missing
  stamp, an invalid or future date, or one older than `max_age_days` (threshold key
  `review-marker-reason-unreviewed`, default 180, `0` = presence only). OFF because every older
  marker would report (50 on this repo). The "older than the last change to the line" check was NOT
  built -- it needs VCS history the linter does not read; the `@hash` already covers code change.
  INBOX B2. Guard: `tests\autotest\run_review_marker_reason_unreviewed.ps1`. 186 -> 188 rules
  (135 built-in, 158 on by default).

### Fixed

- **`lint-all --rule X` runs only what can emit X (D17).** Every per-file checker, the whole `.scm`
  catalogue and every project-wide phase (project rules, class metrics, doc-drift, missing-doc,
  duplicate-code, interface cycles, layering, unit-not-in-dpr, used-unit-resolvable) ran for any `--rule`
  and only the REPORT was filtered. Each is now gated on the same `LINT_GATE_*` lists `lint` uses, the
  project pass and class metrics are handed the rule, and the `.scm` pass runs only X's query
  (`TLinter.OnlyRuleId`, which also skips parsing a file nothing wants). `lint` gets the `.scm` narrowing
  too. Measured on this repo's self index (129 files): `--rule unused-local` 357.8 s -> 4.9 s,
  `--rule overwrite-before-read` ~420 s -> 99 s (the flow checker is the cost itself), `--rule
  concat-in-loop` 4.0 s, `--rule doc-drift` 188 s, against 447 s for a full run; for all six rules
  measured the findings are IDENTICAL to the full run's with the same engine. Two defects
  fixed on the way: the inline `lint` gates were SHORT of `local-field-prefix` and `doc-orphan-block`
  (`lint --rule` answered 0) and of the doc-drift family's `doc-param-*` ids -- all multi-id gates are now
  shared constants pinned against the checkers' sources; and `lint --rule review-marker-unused`
  narrowed away the checkers the marker rule is computed from, so it reported a LIVE marker as unused
  ("remove it") -- a `review-marker-*` rule now runs everything and is narrowed at report time
  (`LintNarrowRule`). Guard: `tests\autotest\run_lint_rule_narrows_checkers.ps1` (sections L, R, G and
  the two new gate-list drift checks).
- **A `"rule"` key in `.drag-lint.json` no longer narrows a whole-project run (L1).** It was copied into
  `--rule` for EVERY verb, silently, so a stray key above the CWD turned every `lint-all` into a one-rule
  run. It is now a default for `lint` only (the file or folder the user named), announced on stderr;
  every other verb ignores it and says so; an explicit `--rule` wins with no note. Guard:
  `tests\autotest\run_config_rule_key_scope.ps1`.
- **`lint-all` says which ownRoots it defaulted to (L2, and the cause of L8).**
  `_D-RAG\drag-lint-project.json` is gitignored, so a fresh clone or a git worktree lacks it and ownRoots
  defaults (per the house rule) to the project file's folder -- for a `.dproj` in a subfolder that skips
  most of the codebase, and the short run read as a small project. With no declaration the run now
  prints the defaulted root, and when that skipped files a loud NOTE naming the missing file, the
  skipped count and the fix. This is also why per-file `lint` "reported" `unused-unit-in-uses` in
  `DRagLint.Query.Callers.pas` while `lint-all` did not (L8): in a worktree lint-all had skipped the
  file as third-party; with the file in scope both verbs report both imports (measured on this worktree
  and a copy of the main index), and the two imports were genuinely dead -- removed. Guard:
  `tests\autotest\run_ownroots_default_note.ps1`.
- **JSON output on a stale index: the staleness is in the envelope, and stdout always parses (ENG-3).**
  The note was already on stderr (since 2026-09-14); the reported splice was stderr merged into stdout
  by the consumer. The audit found no json verb writing it to stdout. The object envelopes of
  `reverse-calltree`, `butterfly`, `callgraph`, `sql`, `schema` and `deps-report` now carry `"stale"`
  and `"stale_files"` (as `sql/1` carries `truncated`), so staleness can be surfaced without stderr.
  Guard: `tests\autotest\run_json_stdout_parses_on_stale_index.ps1` -- 23 json verbs, stdout parsed alone
  on a fresh and on a deliberately stale index, envelope asserted false then true.
- **`allow` refuses every rule that is not a finding about code (L4).** Only `review-marker-stale` and
  `review-marker-unused` were refused, by id, so the three review-marker rules added since
  (`-malformed`, `-placeholder-hash`, `-reason-unreviewed`) and `parser-error` were written as live
  markers. The refusal is now the whole `review-markers` CATEGORY plus `parser-error` (exit 2, with the
  cure), so a future meta rule is refused without an edit here. Guard:
  `tests\reviewmarker\run_allow_command.ps1`.
- **Re-hashing a stale `dl:ok` marker drops its `REVIEWED` stamp (L3).** `allow` on a stale marker
  re-hashes it to the changed code and used to carry the reason over verbatim, so an old
  `REVIEWED yyyy-mm-dd` vouched for code nobody is recorded as having re-read, and kept
  `review-marker-reason-unreviewed` quiet. A re-hash is not a re-review: `TReviewMarkers.InsertInto`
  now drops the stamp (keeping the rest of the reason) whenever it re-hashes, and `allow` prints a
  `note:` saying so. A marker whose hash still matches is untouched. Guards: `ReviewMarkerTests`
  `TestRehashDropsStamp` (L3a-e), `run_allow_command.ps1` (L3 block).
- **`overwrite-before-read` no longer reports nil-inits separated from their `try` by an unrelated
  statement (D15).** `ProtectedByFollowingTry` walked from the store to the `try` over sibling
  ASSIGNMENTS only, so `A := nil; B := nil; for G := ... do X[G] := nil; try ... finally A.Free; B.Free;
  end;` (`Report.Deps.pas:686-693`) stopped at the `for` and reported three stores the `finally` depends
  on. The walk now also skips any statement that never MENTIONS the name (it can neither read nor
  overwrite it); a statement that does name it still ends the walk, and a handler that ignores the name
  still reports. Measured on this repo (`lint-all --rule overwrite-before-read`, self index): 28 -> 23,
  the three Deps stores, `ProjectRules.pas:4203` (a comment line between `Root := nil` and the try whose
  handler frees Root) and `Storage.SQLite.pas:12546` (handler-assigned, the pre-existing "handler
  mentions it" semantics). Guard: `tests\autotest\run_overwrite_before_read_pretry.ps1`
  (`ProtectedAcrossLoop`, control `LoopThenUnrelatedTry`).
- **`concat-in-loop` no longer fires on a string REBUILT every iteration (L6).** `T := 'row '; T := T +
  IntToStr(J);` in a loop body never accumulates, so there is nothing quadratic to report. New `.scm`
  predicate `#not-reset-in-loop?` (`DRagLint.Lint.QueryRules`, `ResetInSameIteration`) drops the match
  when the same variable is also assigned, from an expression that does not read it, by a sibling
  statement on the path up to the NEAREST loop -- i.e. unconditionally in the same pass, before or after
  the concatenation. `S := S + X` with no reset still fires, and so do a reset inside an `if`, a "reset"
  that reads the variable (`T := Trim(T)`) and an inner loop whose outer loop resets. Guard:
  `tests\autotest\run_concat_in_loop_precision.ps1` (7 new checks).
- **The IDE About window names the `index-newer` freshness verdict.** `info --json` has reported
  `index-newer` (the index was built or resolved by a NEWER engine) since C2, but the plugin's
  `VerdictLine` had no case for it, so it showed as a bare, unexplained warning. It is now its own
  `dsWarn` line: reads are fine, re-indexing with this engine is refused, deploy the newer engine.
  Guard: `tests\plugin\run_about_freshness_states.ps1` (engine half ages the resolver stamp FORWARD and
  requires `index-newer`, outranking `reparse-owed`; plugin half requires the case and its remedy text).
- **`TLintConfigWriter.WriteAnsiCrlf` no longer truncates non-ASCII characters (L5).** It stored
  `Ord(Ch)` into a byte, so a character above #255 silently lost its high byte and #128..#255 went out
  as raw non-ASCII bytes -- a changed value and a breach of the 7-bit ASCII rule, with no error (the
  file then failed to load). Every non-ASCII UTF-16 unit is now written as a JSON `\uXXXX` escape: the
  file stays strict ASCII and the value round-trips exactly (escape chosen over refusing, because
  refusing would lose the user's edit). Guard: `tests\lintconfig\LintConfigTests.dpr`
  `TestNonAsciiEscaped` (L5a-f, Latin-1, CJK and a surrogate pair).
- **`tests\ergonomics\run_threshold_test.ps1` runs from any directory (DOC-9).** It resolved
  `third_party\...` and `tests\ergonomics\...` against the CURRENT directory, so it died in
  `Resolve-Path` unless launched from the repo root. Every path is now anchored on `$PSScriptRoot`,
  and `-Exe` overrides the engine.
- **Purity: a result assigned through the function's OWN NAME is not a global write (D12).**
  `Greater:= X > Y;` (and a nested routine assigning the outer function's name) was scored `g`.
  ORM3 CLIENT: effect-free routines 2,895 -> 2,918; the 34 own-name routines go from 0 to 20
  effect-free (the other 14 have real effects); `assert-with-side-effect` 4 findings -> 0 (all 4 were
  this). Guards: `run_purity_stage.ps1` (D12 block + positive control), `run_assert_side_effect.ps1`
  (CONTROL-9). `DRAGLINT_RESOLVER_VERSION` 1.7.0-alpha -> 1.8.0-alpha for all three (derived rows
  only: remedy `index --all --resolve-only`); the C2.3 + IsStub reservation moves to 1.9.0-alpha. No
  extractor bump (extractor baseline hash re-recorded, CallResolver.pas only).

- **Read verbs no longer fail "database is locked" under concurrent readers, and no longer convert a
  WAL index to a rollback journal.** 12 parallel `sql` processes x 25 calls, no writer: 1 of 300
  exited 3 with `database is locked` and no stdout (INBOX-readonly-sql-verb-hits-database-locked).
  Cause: `PRAGMA busy_timeout = 5000` ran AFTER `Connected := True`, but FireDAC runs its own
  pragmas INSIDE the connect (cache_size reads the schema) with busy timeout 0 unless
  `UpdateOptions.LockWait` is set -- so an opener that landed while the last WAL connection held
  the file EXCLUSIVE to checkpoint on close failed at once. Now every open arms the timeout BEFORE
  the connect (`ArmBusyTimeout`, `ConnectReadOnly` in `DRagLint.Storage.FileMembership`): the
  store's read AND write paths, the lint-all library probe, the membership probe. Separately,
  `top`, `graph`, `diff`, `query hints`, `export obsidian`, `workspace status`, the enum export and
  `--selftest-schema` opened raw connections with FireDAC's DEFAULT params (LockingMode=Exclusive,
  JournalMode=Delete): each run rewrote a WAL index's header 2 -> 1 and held it exclusively. They
  now use the shared reader open (query_only, the file's own journal mode, normal locking).
  Not SQLITE_OPEN_READONLY: that still fails on a WAL index without -shm write access (see
  `DbContainsFile`). `sql` on a pre-migration DB still reads it as-is (it is the raw passthrough);
  it does not migrate. Guard: `tests\autotest\run_readonly_concurrency_guard.ps1` (45 checks; a
  held byte-range lock makes the race deterministic -- RED 23 fails on the old exe, GREEN on the
  new). No extractor/resolver bump.
- **`document --apply` no longer deletes `Called from:` entries the chosen DB cannot see
  (docs\INBOX-document-apply-drops-facts-outside-the-db.md).** A stored line carrying `(+N more)` was
  never merged, so the whole line was replaced by the project's own capped render and every visible
  foreign entry went with it. A reconciled block is now rendered with WHOLE inbound lists (writer and
  checker both ask `TSharedFacts.WantsWholeInboundLists`) and a stored window is merged on its visible
  entries. The `(+N more)` marker is also no longer split in as an entry, which had made every
  truncated block read as "foreign". `doc-drift` offers the repair as fixable on such a block when the
  merge drops nothing it cannot vouch for.
- **A stored legacy `<para>Pure</para>` line is no longer churn.** Purity v2 relabelled or retracted it
  on EVERY `document` run over untouched code (measured: 2 blocks, 4 edits on a two-routine fixture),
  and `doc-drift` called those blocks stale. A block whose only difference is that line is now left
  byte-identical and is not drift; a block that differs in anything else is regenerated as before.
  `document --migrate-pure` restores the rewrite for the owner's one-time migration. Guard:
  `tests\autodoc\run_doc_legacy_pure_untouched.ps1`.
- **Misplaced DocInsight comment on `TReviewMarkers.InsertInto` (L7).** f4132d1b inserted `RemoveFrom`
  between `InsertInto`'s comment and its declaration, stacking two comments into one region
  (`doc-orphan-block`) and leaving `InsertInto` with an auto-generated stub. Hand edit, not autodoc:
  the documenter correctly refused to attach a region separated by another declaration.
- **`query find-callers --resolved`: `line` is the CALL SITE on every row (C1).** The rows built from
  `call_edges` -- routine call, property/field access, enum-value read, parenless call -- put the
  caller ROUTINE's declaration line in JSON `line`, while callback rows put the site there: one key,
  two meanings, chosen by the arm. JSON `line` is now the site on every row; the declaration line
  moved to a new key, `caller_line` (omitted when the enclosing routine is unknown). The text form,
  which printed no line for those rows, now prints `(<file>:<site line>)` on every row, the same
  number as the JSON. **Consumers reading `line` as the caller routine's line must switch to
  `caller_line`.** The LSP hover bundle already used the site and is unchanged. Reader-side only
  (`DRagLint.Query.Callers`, CLI rendering): no extractor or resolver bump. Guard:
  `tests\callresolve\run_find_callers_site_line.ps1` (one fixture, all five arms, text and JSON).
- **`info --json --db`: an index NEWER than the engine is `index-newer`, not owed a re-resolve (C2).**
  The verdict compared fingerprints for inequality, so an index resolved at a newer resolver (or
  parsed by a newer extractor) than the running engine read `resolve-owed` / `reparse-owed` with a
  remedy that is exactly the downgrade `index` refuses (ENG-2). Both axes now use the refusal's own
  `CompareDottedVersions`: newer -> verdict `index-newer`, remedy "use a newer engine", new booleans
  `indexer_newer` / `resolver_newer`, and the matching `*_stale` false. Older and absent stamps are
  unchanged. The IDE About window shows the new verdict through its generic branch (warning, verdict
  text only). Guard: `tests\autotest\run_info_index_newer_than_engine.ps1` (with older-stamp controls).
- **`lint <file> --rule with-hides-outer-symbol` runs the check (D2).** `CheckWithHiding` sat under the
  type-aware rule gate, whose id list names `enum-read-inside-with` but not `with-hides-outer-symbol`,
  so the named rule always answered 0. The with-hiding walk now has its own gate (both of its ids); the
  type-aware checker keeps running as before, and its indentation no longer suggests a gate it never
  had. Guard: `tests\autotest\run_with_hiding_rule.ps1` (four new D2 checks).
- **`lint <file> --rule X` runs only the checkers that can emit X (D3).** The type-aware map, the
  flow analysis, the whole-store project pass, used-unit resolvability, class metrics and the
  platform-library open all ran for ANY `--rule` and were filtered afterwards; the project pass walks
  the whole store, so a one-rule question about a unit indexed in the 2 GB library ran for 20+
  CPU-minutes. Each is now entered only when `--rule` names one of its ids (`LINT_GATE_*` in
  `DRagLint.CLI.pas`), and the project pass and class metrics are handed the rule so they narrow
  inside too -- which also makes an OFF-by-default project rule (`global-only-uses-edge`,
  `assert-with-side-effect`, ...) answer `lint <file> --rule <id>` instead of silently reporting 0,
  the contract `lint-project` already honoured. Measured on this repo's self-index (best of 2, no
  library): `DRagLint.CLI.pas --rule unused-local` 55.3 s -> 12.4 s, `--rule
  float-equality-comparison` 57.6 s -> 14.3 s; `DRagLint.Lint.ProjectRules.pas --rule unused-local`
  18.0 s -> 2.5 s; identical findings. `DRAGLINT_DEBUG` now traces each heavy checker entered
  (`[lint-checker] <name>`, stderr). Guard: `tests\autotest\run_lint_rule_narrows_checkers.ps1`,
  which also pins every gate list against its checker's emit sites both ways.
- **`lint-all --rule <id>` means what `lint --rule <id>` means (D4).** lint-all never read `--rule`
  (bar `ifdef-undefined-symbol`): it printed every OTHER rule, and an OFF-by-default rule appeared
  only with `--enable <id>` as well. Now `--rule` narrows the report to that rule and opts an OFF
  rule in for the run -- the id is dropped from the default-disabled list and added to the project
  pass's opt-in set. The narrowing sits in `FinalizeAndOutput`, after the review markers, so it also
  stops a `--rule` run of any lint verb reporting `review-marker-*` for markers of rules it never
  ran, and `check-ast` gains `--rule` for free (documented). The report's circular-dependency
  section says `NOT REPORTED` on a run narrowed to another rule instead of "none detected".
  Documented on the `lint-all` and `check-ast` banner lines, README and AI-USAGE. Guard:
  `tests\autotest\run_lintall_rule_enables.ps1`. A `review-marker-*` finding ABOUT the requested rule
  (its message names the marker's rule as `"<id>"`) survives the narrowing, so `lint --rule X` still
  reports a stale `dl:ok` for X with its re-record command (`run_marker_metric_scope.ps1` check 6).
- **An older engine refuses to re-resolve a NEWER index (ENG-2, urgent).** `RefuseIfEngineOlderThanDb`
  covered the extractor and schema axes, not the resolver: `resolver_fingerprint` is compared for
  inequality, so an engine on resolver 1.5.1 running `index` (or `index --resolve-only`) against an
  index stamped `r=1.6.0-alpha` cleared every call edge, re-derived them with the older resolver and
  stamped the database DOWN, exit 0. The resolver is now the third axis, with the extractor's
  semantics: older refuses (exit 2, both versions named, file byte-identical), equal or newer
  proceeds, an absent stamp is stale (never newer), compared semantically, and no flag -- not
  `--rebuild`, `--force-reparse` or `--resolve-only` -- overrides it. Covers the single-target and
  `index --all` paths. The read-side freshness note now states the DIRECTION: an index resolved by a
  NEWER resolver is named as such instead of being told to re-derive with `--resolve-only` (the
  downgrade itself). No version constant moves. Guard:
  `tests\autotest\run_index_never_downgrades_resolver.ps1`.
- **`deps-report` credits a unit only to the units that NAME it.** The BFS continuation in `WalkBfs` (`src\report\DRagLint.Report.Deps.pas`) credited every transitively reached external to the BFS ROOT, so on ORM3 CLIENT the program `micronite2027` was listed in `used_by` of `ETypes`/`EEvents`/`ECompatibility`, which only `EExtraExceptionInfo.pas` names (implementation uses). It also appended one edge per sighting, so the edge list held duplicates. Edges from an expanded unit are now credited to that unit, and each (importer, external) pair yields one edge. ORM3 CLIENT: `external_edge_count` 30,716 -> 6,880 (= the 6,880 distinct unresolved (file, unit) `unit_uses` pairs), `used_by_count` sum 20,151 -> 6,880; per-group `project_unit_count` falls with it (FireDAC 516 -> 192, DevExpress 98 -> 65); the external set (293) and every `shortest_path` are identical. The EurekaLog `{$IFDEF}` going live now moves edges, the `used_by` sum and unresolved rows by the same +12 (was +14/+13/+12). A reader: no extractor or resolver bump. Guard: `tests\autotest\run_deps_report.ps1` (program -> two mids -> external fixture).
- **RAD Studio options frame: `ifdef_allow` is now editable (D9).** The frame already rendered a text box for
  `ifdef-undefined-symbol`'s list parameter, but loaded it from the catalogue default and silently skipped it
  on save. It now loads and saves `IfdefAllow` (comma-separated). `TLintConfigWriter` OWNS the top-level
  `ifdef_allow` key: verified first that `SaveToFile` already PRESERVED it through unrelated edits, but a
  preserved key cannot be edited -- the on-disk value won over `ACfg`. It is written from `ACfg` when
  non-empty and removed when cleared. Guard: `tests\lintconfig\LintConfigTests.dpr` TestIfdefAllow.
- **`used-before-assignment` and `out` parameters (ENG-7): re-measured, NOT reproduced, now guarded.** The
  DataCopy report (an `out` argument in `if not F(...)`, callee in another unit with a wrapped signature)
  does not reproduce on this build -- not on a copy of its shape, not on DataCopy's own rev-339 sources.
  `out` has been modelled since 2026-08-28. `tests\autotest\run_uba_out_param_datacopy_shape.ps1` pins the
  exact reported shape, with a by-value positive control that must still fire. No engine change.
- **The define profile reads the PLATFORM PropertyGroups.** `ProfileFromDproj` (and so `pp-profile`,
  every `index` preprocess, and every project closure) used to union only the `.dproj`'s `Base` group
  and the selected config's `Cfg_N` group. MSBuild also applies `Base_<Platform>` and
  `Cfg_N_<Platform>`, so a define set ONLY per-platform was silently inactive. Measured on ORM3 CLIENT:
  `EUREKALOG` lives in `Base_Win32`/`Base_Win64`, so the `.dpr`'s `{$IFDEF EurekaLog}` uses block was
  blanked, and `index --project` evicted the local `EExtraExceptionInfo.pas` from a closure the
  compiler does build (625 -> 624 files). All four groups are now read in MSBuild order.
  `DRAGLINT_EXTRACTOR_VERSION` moves **1.17.0-alpha -> 1.18.0-alpha**, because this changes which
  `{$IFDEF}` branches are parsed. That means one full re-parse of every index. `DRAGLINT_VERSION`
  moves to 1.17.0-alpha. Guard: `tests\preprocess\run_profile.ps1` with the new
  `fixtures\platform_groups.dproj`, which mirrors Micronite2027's layout, including the selector
  groups that name `$(Base)` and `$(Base_Win64)` together. Note:
  `docs\INBOX-pp-profile-ignores-platform-propertygroups.md`.

### Changed
- **`cycles --plan` is now a mechanical playbook (INBOX-test-cycle-playbook-followability-haiku-flash).**
  Haiku followed the old playbook on `circular-demo` and failed: told to "extract the shared contract",
  it moved the CLASS `TDemoSession` without its method bodies (E2065 x5), and was told the cycle
  "should be gone" when a legal implementation-only cycle remained. New unit
  `src\report\DRagLint.Report.CyclePlan.pas` renders, per cycle: each symbol's KIND and a recipe for
  it (enum / record / const / var move unchanged, exact lines incl. doc comment; a class whose method
  bodies use the cycle gets a BASE CLASS extracted with only the members its consumers use, with the
  reason and its body line ranges; a class whose bodies are cycle-free moves whole); every consuming
  unit with section + first-use line; a per-unit keep / move-to-implementation / remove decision on the
  old uses entry; the full text of each new `<Declaring>.Contracts` unit and its uses rule; every edit
  (units, `.dpr` `in` clause, `.dproj` `DCCReference`) as current + new text, bottom-up; a DONE
  definition; a numbered checklist ending in the re-index command and the exact `cycles` output,
  PREDICTED by replaying the uses changes on the graph; and a compile-error table. Part A cuts the
  interface coupling; an optional Part B names the next mechanically cuttable edge, and re-running
  `--plan` on an implementation-only cycle prints it as the same steps (or says no edge can be cut and
  why). Proven end to end on copies: `circular-demo` Part A and Part B applied by a script that knows
  only the playbook's markup compile, match the predicted output at each stage (last: `No circular unit
  dependencies found.`), and the program's output is byte-identical to the original's;
  `docs\examples\circular-uses-demo` compiles and ends acyclic. The old "invert the dependency" recipe
  for a COMMON -> CLIENT/SERVER edge is now a note. `--edges` / `--causes` / `--format json` unchanged;
  their line formats are now shared constants with the playbook. Guard:
  `tests\autotest\run_cycles_plan_followable.ps1` (29 checks). No extractor/resolver bump.- **Parenless calls bind (resolver 1.7.0-alpha, defect D1).** A value-returning routine with no required parameters called WITHOUT parentheses in an EXPRESSION -- `Assert(NextId > 0)`, `N := NextId`, `Consume(NextId)`, a bare `Tick` or `Self.Tick` inside its class -- is recorded by the parser as a `read` ref, and the `calls` stage never streamed `read` refs, so none of those sites owned a `call_edges` row: `assert-with-side-effect`, the purity callee walk, `find-callers --resolved` and the who-calls charts all missed them. A third calls-stage stream now decides, per read, whether it IS a call: the NEAREST declaration of the name wins (lexical scopes, the enclosing class and its ancestors, the own unit, the interfaces of used units); a shadowing value (local, parameter, field, property, const, var, type, enum value) declines, as does a routine set with any member that needs an argument or returns nothing, a procedure-VALUE site (`@F`, or `F` as the whole right side of an assignment / a whole argument whose declared type is procedural), and any `with` earlier in the enclosing routine. Every decline is counted on a new `calls      parenless:` log line. Measured on a copy of ORM3 CLIENT (resolver 1.6.0 -> 1.7.0, `--resolve-only`): **2,205 candidate reads, 1,237 bound** (1,222 certain, 15 ambiguous), declined shadowed 725, not-callable 174, with-scope 57, not-found 12, proc-value 0; `call_edges` 20,409 -> 21,646, exactly +1,237, no other edge moved. Before the fix 1,715 of those reads named a parameterless value-returning routine and all were unbound. `find-callers --resolved` no longer ALSO lists such a site as a `callback` row. Known blind spot: a procedural target whose type the index cannot see (an RTL `TFunc<T>` behind an alias it does not hold, a property of a class outside the index) is not detected, and the read binds. No re-parse: remedy is `index --all --resolve-only`. Guard: `tests\callresolve\run_parenless_call_bind.ps1` (7 checks, 11 negative controls); `assert-with-side-effect` fixture gained a parenless trigger and control.
- **The resolver models `with` scope; bare property/field reads bind (resolver 1.8.0-alpha, defects D14 + D16).** Inside `with A, B do`, a bare name now resolves the way Delphi resolves it: against the members of the innermost target first (last-listed entity first, then enclosing withs), and only then against locals, the class and the unit. It applies to a bare call (it binds the target's method, with the target as the receiver type), to the leading identifier of a receiver (`with AObj do Inner.Ping`), and to the enum-value and parenless passes, which drop 1.7.0's "any `with` in the routine declines" rule for the real scope. The with spans come from parsing the source inside the resolver (same grammar and byte transform as the indexer; nothing stored). **A target the index cannot type, or whose ancestry leaves the index (a class descending from `TForm`, any library type), may declare any name, so every bare name under it binds NOTHING** -- the one exception is the enum pass, which keeps its pre-1.8 binding there (counted as `bound under an undecidable with target`), and `enum-read-inside-with` now reports exactly that residual: the rule is silent where the resolver binds the member, and fires where it could not type the target but the rule can (by name, across the library index too). A FOURTH calls-stage stream binds bare `read` refs to a with target's property or field, to the enclosing class's PROPERTY (`N := Total`, D16a), and `Self.X` to either -- a same-named local no longer hides `Self.X` (controller addition) -- recorded exactly like a member access: `refs.symbol_id`, a `member_accesses` row (mode `read`) and a call edge to a method getter. A bare own-class FIELD read stays unbound by design (it is every field read in a codebase). Parenless procedure-value test: an argument list or assignment split over several lines is read as one site (D16c -- `RegisterGen(` + newline + `NextId)` bound as a call before), and a qualified `System.SysUtils.TFunc<T>` or Spring `Func<T>` is recognised as procedural (D16b); a library ALIAS of a zero-argument function type is still not seen. New log lines `calls      member-reads:` and `calls      with-scope:`; the `enum-values:` line gains the two with counters. **Measured on a copy of ORM3 CLIENT** (`index --resolve-only`, 1.7.0 build of e3f63801 vs this one): 380 with statements in 145 files. Bare READS inside with bodies 0 of 4,452 bound -> 4,137 (2,077 fields, 2,060 properties; 10 read -- all the generated `with Dest as TmcX do X := fX` shape, all correct). MEMBER ACCESSES inside with bodies 0 of 162 -> 0 of 162: every one goes through a library-typed receiver (DevExpress printer/grid, `TDataSet`/`TField`, VCL controls) the project index cannot bind with or without the scope -- the mechanism is proven on the fixture (`W-RCV`), not on this corpus. Bare CALLS inside with bodies 11 bound -> 1: the 11 lost were all read and all CORRECT (`StrToIntA` under `with Z14slctFrm do`, `ExtractAQL` under a DevExpress combo, one under a `TDataSet`), declined because the scope cannot prove a library ancestor lacks the name; +1 newly bound (`ApplySelections`, the form's own method). Enum bindings 6,013 -> 6,013, none moved; 4 enum-named reads (`fM1`..`fM4`, uIPCHART) now bind to their with target's field; 0 enum bindings sit under an undecidable target, so the R7 channel had no live instance inside a with BODY on CLIENT (the 178 were in with-bearing routines, outside the bodies). Parenless 1,237 -> 1,242 (+5 reads after a completed `with` statement, read and correct; with-scope declines 57 -> 13). Own-class property reads: 182 newly bound (6 read, correct). Outside with bodies, member-access and call bindings are byte-identical (10,176 / 14,511); `call_edges` 21,646 -> 23,784 and `member_accesses` 9,311 -> 13,630 (getter edges and accesses of the new reads); purity 2,895 effect-free before and after. The calls stage got FASTER, 276.7 s -> 72.5 s: the resolver now caches symbol rows and ancestor lists per run (uncached, the new stream took it to 473.6 s). `DRAGLINT_RESOLVER_VERSION` 1.7.0-alpha -> 1.8.0-alpha; extractor NOT bumped (hash re-pinned, `CallResolver.pas` is the only surface file that moved). Remedy: `index --all --resolve-only`. Guards: `tests\callresolve\run_with_scope_bind.ps1` (new, 30 checks), `run_parenless_call_bind.ps1` (D16b/c cases; three NEG reads now bind to the member they name), `tests\autotest\run_enum_read_inside_with.ps1` (positive moved to an undecidable target; the old positives are R7-closed controls).
- **`run_shared_unit_staleness.ps1` asserts one ADOPTION round.** With project tags, a line written in
  tagged form by one project is adopted by each other project once (it tags its own entries), so
  convergence is one write per project per line; the suite now asserts that round and the fixed point
  after it.
- `TSharedFacts.HoldsForeignInboundEntries` lost its unused `AUnitPath` parameter;
  `TDocFactsBuilder.Build` gained a trailing `AWholeInboundLists` (default False).
- **Parenless calls bind (resolver 1.7.0-alpha, defect D1).** A value-returning routine with no required parameters called WITHOUT parentheses in an EXPRESSION -- `Assert(NextId > 0)`, `N := NextId`, `Consume(NextId)`, a bare `Tick` or `Self.Tick` inside its class -- is recorded by the parser as a `read` ref, and the `calls` stage never streamed `read` refs, so none of those sites owned a `call_edges` row: `assert-with-side-effect`, the purity callee walk, `find-callers --resolved` and the who-calls charts all missed them. A third calls-stage stream now decides, per read, whether it IS a call: the NEAREST declaration of the name wins (lexical scopes, the enclosing class and its ancestors, the own unit, the interfaces of used units); a shadowing value (local, parameter, field, property, const, var, type, enum value) declines, as does a routine set with any member that needs an argument or returns nothing, a procedure-VALUE site (`@F`, or `F` as the whole right side of an assignment / a whole argument whose declared type is procedural), and any `with` earlier in the enclosing routine. Every decline is counted on a new `calls      parenless:` log line. Measured on a copy of ORM3 CLIENT (resolver 1.6.0 -> 1.7.0, `--resolve-only`): **2,205 candidate reads, 1,237 bound** (1,222 certain, 15 ambiguous), declined shadowed 725, not-callable 174, with-scope 57, not-found 12, proc-value 0; `call_edges` 20,409 -> 21,646, exactly +1,237, no other edge moved. Before the fix 1,715 of those reads named a parameterless value-returning routine and all were unbound. `find-callers --resolved` no longer ALSO lists such a site as a `callback` row. Known blind spot: a procedural target whose type the index cannot see (an RTL `TFunc<T>` behind an alias it does not hold, a property of a class outside the index) is not detected, and the read binds. No re-parse: remedy is `index --all --resolve-only`. Guard: `tests\callresolve\run_parenless_call_bind.ps1` (7 checks, 11 negative controls); `assert-with-side-effect` fixture gained a parenless trigger and control.
- **`--resolve-only` no longer promises cross-store edges (ENG-5, owner ruling 2026-09-22).** `--help`,
  README and AI-USAGE now say what was measured: the pass writes edges INSIDE the one index it is run
  on, and no cross-store edge is written (0 `refs.external_target` in every project DB; re-resolving
  the platform libraries added 13 intra-library edges per platform). Attaching the library as an extra
  store at index time is filed as a separate item.
- **`--output` is the documented spelling everywhere; `--out` is a silent alias (ENG-6, owner ruling
  2026-09-22).** The banner named `--out` on `forms-csv`, `convert-scaffold` and `glyph-vacuum`, and
  `export enums` documented neither; every one now reads `--output`, as do the `convert-scaffold` and
  `glyph-vacuum` usage strings. `--out` is accepted exactly as before and is recorded once in
  AI-USAGE. `run_docs_sync_guard.ps1` exempts it as a class-(b) alias and allows that one prose
  record, two-way asserted; `run_flag_verb_map.ps1` re-baselined (see its header for the count).
  No behaviour change.
- **Enum-value references bind (`refs.symbol_id`).** The `calls` resolve stage now derives `refs.symbol_id` for two ref shapes that were NULL on every index ever built: a bare `read` ref whose name is an enum value (`cmdDelta`), and a `member-access` ref qualified by the enum type or by the declaring unit (`TCommandID.cmdDelta`, `Pipes.Protocol.cmdDelta`). Binding is by name and SCOPE, never by name alone: R1 visibility (own file either section; another unit's INTERFACE section only, through a direct uses edge), R2 uniqueness (two visible candidates decline -- uses-clause order is not modelled), R3 shadowing (a same-named local, param, class member, ancestor member, or unit-level const/var/routine/type declines), R4 unit-level code, plus rule-0 collapse of content-identical duplicate declarations. The result is `certain` or NULL; there is no `ambiguous` value binding. What is NOT written: **no `call_edges` row, no `member_accesses` row, no new table, no new column** -- `CanBeCallTarget` and `CallSiteRefKindSql` are untouched, so the unresolved-call complement universe (register item E1) is unchanged and `ambiguous-calls` lists no enum site. `DRAGLINT_RESOLVER_VERSION` moves **1.5.1-alpha -> 1.6.0-alpha**; `DRAGLINT_EXTRACTOR_VERSION` (1.17.0-alpha) and `SCHEMA_VERSION` (23) do NOT move. This is DERIVED data only, so the remedy is a re-resolve, not a re-parse: `index --all --resolve-only` (~6 min for all project sections, and up to ~73 min per platform library -- measured 2026-09-22 at Win32 3641.4 s calls + 726.8 s purity = 72.8 min and Win64 3500.6 s + 635.3 s = 68.9 min). Until that runs, an index resolved under 1.5.1-alpha has NONE of these bindings. Expectation after the re-resolve (M1): `SELECT name_text, kind, symbol_id IS NOT NULL, COUNT(*) FROM refs WHERE name_text IN ('cmdDelta','cmdTableLoad') GROUP BY 1,2,3` reports every row bound -- ORM3 CLIENT `cmdTableLoad` 42 and `cmdDelta` 38, SERVER 2 and 2, all previously 0. **Known limitation -- scoped enums.** Under `{$SCOPEDENUMS ON}` a value is legally reachable only as `TEnum.Value`, but the extractor does not record scopedness, so a bare `read` that happens to name a scoped enum's value can bind where the compiler would have rejected the source. Exposure is narrow: R3's shadow checks already decline on a same-named local, param, class member or unit-level const/var/routine/type, and a same-named UNSCOPED value declared elsewhere makes R2 decline. It is not fixed here because the fix needs the extractor to record scopedness -- an extractor version bump and the ~3h17m full re-parse of every database that comes with it, for a feature whose own remedy is a ~6 minute re-resolve. If you rely on enum bindings inside scoped-enum units, verify a bare-name binding against the declaration before trusting it; qualified (`TEnum.Value`) reads are unaffected. Scoped enums are risk **R5** and `with`-blocks are risk **R7** -- two distinct risks, and Task 7 MEASURED both on the corpus, together, because their exposed populations substantially overlap. **R5 measured zero.** Across all 33 PROJECT databases, 1758 distinct enum values have a bound bare read and NONE of them is declared under `{$SCOPEDENUMS ON}`, so 0 bare reads bind to a scoped value against 13443 that bind to an unscoped one (positive control: of 1185 indexed `.pas` files exactly one, `DUnitX.TestFramework.pas`, carries `{$SCOPEDENUMS ON}` at all, and the 4 bare reads naming its 14 scoped values are unbound). **That zero is a statement about the PROJECT databases only -- the platform LIBRARY indexes were deliberately NOT measured**, and RTL/VCL scoped enums live exactly there, so the "verify a bare-name binding against the declaration" instruction above stands until the deferred owner-gated library pass measures them. **R7 measured NON-ZERO, and it is this branch's only known wrong-bind channel** (since resolver 1.8.0-alpha the `with` scope is modelled -- see the 1.8.0 bullet above; what remains of R7 is a bare enum read under a `with` target the index cannot type). On ORM3 CLIENT alone, **178 bound bare reads sit inside a routine that contains a `with` block** (9 more declined; 187 candidate reads in that population, against 5771 bound of 5843 outside it). The engine does not model `with`-block scope, so inside such a routine a bare name that matches an enum value may really be naming a member of the `with` receiver, and the binding would then be wrong. **Give a bare-name binding inside a `with`-bearing routine the same treatment as one inside a scoped-enum unit: verify it against the declaration before trusting it.** Qualified reads (`TEnum.Value`, `Unit.Value`) are unaffected by R5 and by R7 alike, because the source qualified the name itself. No rule was added -- R7 is a stated non-goal of this branch; the per-routine breakdown is in `docs\MEASURED-enum-value-refs-2026-09-23.md` and the owner note is `docs\INBOX-enum-binding-inside-with.md`. The `find-callers` and autodoc consequences of this binding do not ship with this bullet; they land with the reader arm and are described in the `find-callers --resolved` bullet below. Spec: `docs\superpowers\specs\2026-09-23-enum-value-ref-binding.md`.
- **`find-callers --resolved` reports bound ENUM-VALUE reads.** An enum value passed to `query find-callers --name <value> --resolved` now lists every read the resolver bound to it -- bare (`cmdDelta`) or qualified (`TCommandID.cmdDelta`) -- as a row tagged `[certain, read]` (JSON `mode`), one row per SITE rather than per caller. A read the resolver declined (two visible candidates, or a same-named local/const/member in scope) is NOT listed, so an absent caller means "not bound with certainty", never "not present". `FindResolvedCallers` grows a third UNION arm for this; the arm excludes any ref that already owns a `call_edges` or a `member_accesses` row, so ROUTINE and PROPERTY/FIELD rows are byte-identical to before -- it adds a bucket, it does not re-shape the existing two. `mode` is the literal `read` for both shapes, including the qualified one whose ref kind is `member-access`: an enum value can only be read. Requires an index resolved at `DRAGLINT_RESOLVER_VERSION` 1.6.0-alpha or later (`index --all --resolve-only`); an older index answers 0. No schema, extractor or resolver-surface change -- `SCHEMA_VERSION` stays 23 and the resolve hash does not move (`FindResolvedCallers` is a query-side reader, `EXCLUDE`d in `tests\resolver-surface.txt`). `--help`, `README.md` and `docs\AI-USAGE.md` updated in the same change. Guard: `tests\callresolve\run_enum_value_refs_bind.ps1` checks 9 (the arm) and 10 (the anti-double-listing regression guard).
- **Autodoc: what this does and does NOT do to an enum value's `Used by:` block.** MEASURED on a real corpus (drag-lint's own 270-`enum_value` self-index), not predicted. The spec's premise that bound entries "lose their ` ?` suffix" is FALSE -- an enum value's list was uniformly `unverified` before and so rendered plain already (`JoinRefs` renders ` ?` only on a MIXED list), and the ungated name bucket that supplies those entries is never gated off for a non-callable kind. **There are two independent churn channels, and they have different bounds.** (1) RE-WINDOWING: the caller cap keeps the first `AMaxCallers` (default 5) in first-seen INSERTION order, and bound sites now enter from the resolved bucket first, so a different 5 of the same N survive -- same caller set, same `(+N more)` total, no marker change. Only values with more than 5 distinct callers can move: **44 of 270 on this repo's index, an upper bound** (a 16-caller value was verified to render byte-identically). (2) MARKER APPEARANCE: for a **partially bound** value the ` ?` count goes **0 -> N, it does not go to zero**. `FindUnresolvedNameCallers` matches on bare `name_text`, excludes only refs owning a `call_edges` row -- not refs this binder just bound -- and hard-codes `unverified`; `AddDistinct` folds only on `(Display, Location)`. So any name-bucket entry the resolved bucket does not also produce survives as unverified, `Mixed` flips False -> True, and every such entry gains ` ?`. Two ordinary shapes cause it: a read of a DIFFERENT same-named value in another enum type, and a read of this value the resolver DECLINED (R1/R2/R3). **A ` ?` is a re-qualification**, so channel 2 is not cosmetic, and it can fire at ANY caller count -- including at or below the cap, so it is outside the 44 and outside the "208 render identically" set. Channel 2 measured **0 occurrences on this index** (every enum value here is fully bound with no surviving same-named reader), but that is a property of this corpus, **not a bound** -- a corpus with declined or same-named reads will show more. The one owed `document --apply` per corpus should be folded into the deferred `Pure` -> `Effect-free (proven)` regeneration, after the library re-resolve. Detail: `docs\MEASURED-enum-value-refs-2026-09-23.md`, section "Task 6 -- R-B churn shape".
- **`lint-tree` sees a removed or renumbered ENUM MEMBER.** `enum_value` joins the kinds `LintTree.IsRoutineKind` admits -- the routine kinds plus `property` and `field`, i.e. every kind whose references the resolver binds by id -- so a member dropped from an enum in the edited unit now reports `stale-interface-reference` at every BOUND read of it across the dependent closure, and `enum_value` no longer appears in the report's `not_reportable` list. The gate was widened LAST, after the resolver binding was proven -- the same discipline the 2026-09-16 property change established, because widening the gate alone makes a kind count as "handled" and hands the caller silence. It therefore requires an index resolved at `DRAGLINT_RESOLVER_VERSION` 1.6.0-alpha or later; on an older index the reads are unbound and `lint-tree` reports nothing, exactly as before. **The two verbs now say different things, because they have different consequences.** A REMOVED member keeps the long-standing wording ("this reference will not compile until it is updated"). A CHANGED declaration on an enum value does NOT: dropping an earlier member shifts every later member's ordinal, so each of them reports a changed declaration while `if C = cmdDelta then DoWork;` goes on compiling. That finding now reads "this reference still compiles, but the member ordinal has moved -- any ordinal already persisted or transmitted now means a different member", which is the hazard that actually follows. Every other kind keeps the original wording on both verbs -- for a routine, property or field a changed declaration IS a signature change. Guard: `tests\callresolve\run_enum_value_refs_bind.ps1` check 11 pins both classes of finding, that nothing else leaks in, and that `enum_value` has left `not_reportable`.
- **A forward declaration is not a class (C2.5).** `TFoo = class;` completed later in the same unit is folded into the real declaration by every by-name reader: `query --name/--qname` returns ONE row (the real one) with `forward at line N` / `forward_line`; `hover --qname` renders the real declaration; the LSP hover on the stub's line renders the real one led by `forward declaration -> line N`; ClassMetrics measures the real class once (it used to parent every descendant to the stub and anchor `too-many-children` on the stub's line); `outline` keeps both rows and tags the stub `[forward -> line N]` / `forward_target_line`; LSP completion (`FindSymbolsByPrefix`) offers the type once instead of twice. Interface stubs follow the same rule. A lone stub (`TOnlyStub = class;` with no completion in the unit) and an empty class (`TEmpty = class end;`) still count as classes. Resolution-side join -- no schema or extractor change; no re-index needed. The call resolver's cross-store receiver lookup (`CallResolver` declines when a name matches more than one row) now resolves receivers whose RTL type is forward-declared (`TComponent`, `TReader`, `TWriter`, ...) -- an index resolved before this change lacks those edges until `index --all --resolve-only` is run (or the next resolver bump re-resolves everything). `DRAGLINT_RESOLVER_VERSION` was deliberately NOT bumped (spec S8; owner decision pending). New `DRagLint.Core.ForwardStub`; guards `run_forward_stub_pairing.ps1`, `run_forward_stub_is_not_a_class.ps1` (CASE E drives `textDocument/completion`). Spec: `docs\superpowers\specs\2026-09-17-forward-stub-is-not-a-class-design.md`.

### Known
- `ResolveTypeNameToClass.IsStub` (resolver-side) keeps its own narrower stub filter (heritage empty AND end_line <= start_line, no children/same-file test); unifying it with `DRagLint.Core.ForwardStub` is a resolver-surface change deferred to `DRAGLINT_RESOLVER_VERSION` 1.9.0 (it was 1.6.0 until 2026-09-23, when 1.6.0-alpha was taken by the enum-value ref binding, then 1.7.0 until 1.7.0-alpha was taken the same day by the parenless-call binding, then 1.8.0 until 1.8.0-alpha went to the resolver batch -- the `with` scope above, D12 own-name result writes, D13 bare write binding and ENG-16 unit-qualified calls).

## v1.16.0-alpha -- 2026-09-22

MINOR: two new lint rules, both OFF by default. Extractor 1.17.0 and schema v23
are UNCHANGED -- no index needs a re-parse. `DRAGLINT_RESOLVER_VERSION` moves
1.5.0-alpha -> 1.5.1-alpha for the witness-text fix below, so an index resolved
under 1.5.0-alpha owes one `index --all --resolve-only` (minutes, not hours).

### Added
- **`discarded-effect-free-result`** (project-wide, info, OFF by default) --
  a PROVEN effect-free value-returning routine is called in statement position
  and its result thrown away, so the call cannot do anything. Driven by the
  stored `symbol_facts.effect_free` verdict, never by "is a function": a
  routine that returns a value AND fills an out parameter has summary `p<k>`,
  is not effect-free, and never fires. Statement position is decided by a
  balanced, string-aware scan of the call line PLUS the preceding code line, so
  a wrapped expression (`X := A +` / newline / `Twice(3);`) is not mistaken
  for a discarded call.
- **`query-name-with-effect`** (project-wide, info, OFF by default) -- a
  `Get*`/`Is*`/`Has*`/`Find*`/`Can*`/`Should*` routine whose stored
  effect summary carries `g`, `h` or `s`: it answers a question and also
  changes something. A summary that is only `?` (a binding gap) or only
  `p<k>` never fires, which is the axis on which it differs from the AST-only
  `separate-query-from-modifier` -- that rule ships beside it, unchanged.
- Opt in with `--enable <id>` or `"enabled":["<id>"]`. Catalogue totals move
  to **183 rules, 130 built-in**; fixable stays 23 and default-on stays 156.
- Guard `tests\lint-project\purity-rules\run_purity_rules.ps1`: a bare
  `lint-all` must report zero for both ids, and the same run with `--enable`
  must report the exact expected counts.

### Fixed
- The `purity` stage no longer concatenates `symbol_facts.touches` into the
  effect witness raw. That column is the two-field wire string
  `resources|transactions` whose separator is always present, so the witness
  read `touches file system|` -- visible to users through the new
  `query-name-with-effect` message and in the stored column. It is now split
  the way `DRagLint.Doc.Regions` already renders the fact, with the
  transaction half labelled: `touches file system; transactions: starts,
  commits`. Verdicts are unchanged -- `effect_free` and `effect_summary`
  are identical; only the witness text moves.

## v1.15.1-alpha -- 2026-09-17
PATCH: fixes a regression shipped in 1.15.0 (dotted unit names invisible to
`unit-usage` / `unused-unit-in-uses`). Extractor 1.17.0 / schema v23 /
resolver 1.4.0 are UNCHANGED; an index built by 1.15.0 needs no re-parse.

### Fixed
- `FindSymbolsByExactName` tries the VERBATIM dotted name first: unit names are stored with their dots (`A.Lib`, `Vcl.Controls`), and the per-segment split from fdb05c9d (`TList<T>.Add` -> `Add` + qualified-name suffix) ran first and found nothing, so `query unit-usage --unit A.Lib` degraded to `exports_known:false` and `unused-unit-in-uses` reported zero for every dotted unit. The split now runs only when the verbatim lookup misses; pinned by `run_generic_symbol_names.ps1` (D1, through `unit-usage`, which has no qualified-name fallback of its own).
- glyph-vacuum (converter): `FindCountProp` matches dotted count props by
  their last segment (2df9601f); length-prefixed bare bitmaps
  (`TBitBtn.Glyph.Data`) and raw SVG (`TdxSmartGlyph`) decode, and EMF
  requires the ` EMF` signature -- 852+3 of 1016 ORM3 rows were undecoded
  (2343c0bc); `runtime_refs` derived from the merged write set, the
  class-tree count fallback matches dotted names, the collection scan fires
  only at an end-of-line `= {`, gallery cards sorted by sha (6a2803f4).

### Changed
- `docs\GLYPH-CLASSES.md` seeded from the first glyph-vacuum run on ORM3,
  re-measured after the SVG / length-prefix decoders, and the M2022 corpus
  added (d298ae1d, 64a5d5db, 7df84bc1).
- glyph-vacuum fixtures for bare-BMP-at-offset-0 geometry and the
  Int32-equals-length collision fall-through (fd810e91).
- autodoc: the CLI project's doc-comments regenerated after extractor 1.17.0
  (inherited fields, nested locals in facts) -- comment-only (1307e778).

## v1.15.0-alpha -- 2026-09-17

### Added
- `glyph-vacuum --root <dir> --out <dir> [--db <db>] [--append]` (converter):
  walks every `.dfm` / `.fmx` under the root, decodes every streamed graphic
  (a binary `.dfm` is converted in memory), and writes `instances.tsv`, the
  decoded images, a per-class `classes.tsv` (count property, inferred strip N,
  agreement, kind, format and distinct-payload distributions, `runtime_refs`
  counted through resolved property refs when `--db` is given) and a
  `gallery.html` with one card per distinct payload per class, slot separators
  overlaid at width div N. Unparseable files are listed in `skipped.tsv`, never
  dropped; `--append` merges a rescan by (dfm_path, object_path, property), so
  a second run is idempotent. The input to `docs\GLYPH-CLASSES.md` and the
  `G[I/N]` grammar.
- ConvRulesEditor: the Unit Rules tab lists each used unit with the section it
  is declared in (interface / implementation) and fills the moment a unit is
  picked -- Browse, combo select or Fill, form or not. The declared-class list
  on the same tab was empty for every input (`ScanClassesDeclared` started its
  backtrack past the keyword and never met the `=`).

### Changed -- extractor 1.17.0-alpha / schema v23 (re-parses every index)
- Generic types and methods are indexed under their BARE name; the parameter
  list is in `symbols.generic_params`. Ancestor edges carry
  `ancestor_type_args` and resolve by arity before the scope rules:
  `TObjectList<T: class>` now climbs to `System.Generics.Collections.TList<T>`
  (was `System.Classes.TList`); ORM3's 134 `TMicObjectBase<I>` descendants
  resolve their base. `query --name` accepts `TList<T>`, and a dotted name is
  stripped per segment, so `Unit.TList<T>.Add` finds the METHOD (was the class).
  Arity counts PARAMETERS, not commas: `<T: class, constructor>` is 1 and
  `<S: IUnknown; I: IUnknown>` is 2, so edges onto constrained generics resolve.
- Nested-routine locals and inline `var` / `for var` declarations are
  `local_var` symbols parented to the innermost routine. Two sibling
  `for var Item: T in` loops of DIFFERENT element types leave `Item.M` calls
  unresolved (decline) rather than typing both from the first loop.
- `symbol_facts.reads_fields` / `writes_fields` include INHERITED fields
  (own first, nearest ancestor next) via the new `facts-inherited` index stage.
- `query ancestors --json` rows carry `type_args` ('' on a plain edge). The
  LSP's ephemeral store for a file no index owns now runs the `facts-inherited`
  stage too, so hover on such a file shows a same-unit inherited field in
  `Writes:`.

### Fixed
- `context --task "modify Class.Member"` resolves when exactly one symbol's
  qualified name ends with that dotted suffix (segment-aligned; an ambiguous
  `Class.Member` still declines). A RECORD's class surface lists every field:
  the lean DFM-component filter now runs only when the owner is a class, so
  `modify TTypeAncestor` no longer prints one field of eight.
- A property whose accessor is OVERLOADED (`read GetItem` beside two `GetItem`
  declarations) binds the overload whose parameter count is the property's index
  count (+1 for a setter); when the count leaves several, the access records no
  accessor and no call edge instead of the first-declared one (resolver 1.4.0, re-pinned).
- `FindSymbolsByExactName` (`query --name`) splits a dotted input per segment:
  `TList<T>.Add` finds the METHOD `gnB.TList.Add`, not the class, and a dotted
  path keeps only rows whose qualified name ends with it.
- `dataset-open-without-close` ignores a member named `Open` that is indexed, passed as
  an argument or assigned -- only a bare `X.Open;` / `X.Open();` statement is a
  dataset open. A record field `Open: TArray<...>` read as `AState.Open[i]` fired
  eight times on drag-lint's own source (INBOX 2026-09-17, section 2).
- `GetSymbolFacts` / `GetSymbolDoc` initialise a managed `Result` with
  `Default()`, not `FillChar` (leak when a caller reused the variable).
- `uses-report --name <pattern>` matching NO source unit now exits 2 with
  `ERROR: uses-report: no index passed contains a source unit named <pattern>`
  on stderr and writes no output file (an existing `--output` is left
  untouched). It used to print `0 source units, 0 rows written` and exit 0 --
  a complete-looking report against a corpus that did not contain the subject,
  while `outline` on the same file and DB refused. Converter gap 2026-09-16
  (`stats\draglint-gaps.log`, class `wrong`). Guard:
  `tests\autotest\run_uses_report_name_no_match.ps1`.

## v1.14.0-alpha -- 2026-09-17

### `Catches:` -- the exceptions a routine HANDLES (INBOX-report-exceptions-raised-and-handled, gap 3)

The managed facts block gains one line per routine with a `try..except`:
`Catches: EConvertError (dialog: ShowMessage); Exception (re-raise)` -- one
entry per (class, disposition), sorted by class name, deduped, capped at
`docs.max_handles` (default 8) with a visible `(+N more)`. An `else` arm
and a bare `except .. end` both count as `Exception`. Dispositions, first
match wins: `re-raise` (a bare `raise;` or `raise` of the handler's own
variable), `raises X` (the handler raises a DIFFERENT class -- the plan's four
did not cover the translation shape, and `swallowed` would misdescribe it),
`dialog: <name>` (a call on `docs.dialog_routines`, the witness spelled as
the source spells it), `empty`, else `swallowed`. Mined from SOURCE at doc
time on the raise miners' own comment/literal scan state (`TDocFactsBuilder.
MineHandlers` / `RenderCatches`), NOT an index-time `symbol_facts` column
-- no extractor bump, no reindex, and a handler in a comment or string literal
is never reported. The label is `Catches:`, not a second `Handles:`:
`Doc.SharedFacts` bounds a fact's slice in the flattened stored block by
label, so two lines under one label would collide there. New manifest keys
`docs.dialog_routines` (default the VCL four; `[]` is the off switch) and
`docs.max_handles`, read by `document`, `doc-drift`, `hover` and the
LSP through one `TDocHandlesOptions` threaded like the caps, so the writer
and the checker cannot disagree. `document --project` was run to a fixed
point on this repo in the same change (76 `Catches:` lines). Guard:
`tests\autodoc\run_doc_exception_handles.ps1` (27 assertions, RED-first).
### Property and field references RESOLVE (resolver 1.3.0-alpha; re-resolve every index)

A `member-access` ref naming a PROPERTY or FIELD (`FConnection.Connected`)
reached the resolve pass since v20b and was discarded there, because only a
routine could own a `call_edges` row -- so `find-callers --resolved` answered 0
for a property that a method on the same receiver answered 4 for, and
`lint-tree` reported "0 place(s)" when a public property with 207 dependents
was removed. Per the owner's ruling: the ref now binds to the member
(`refs.symbol_id`); a READ is also a resolved call to the read accessor and a
WRITE to the write accessor (a `call_edges` row when the accessor is a method
-- `call_edges` stays routine-only); a FIELD-backed accessor lists the access
as a use of that field. New `member_accesses` table (additive, no schema bump;
readers probe for it). `find-callers --resolved` on a property or field prints
`[certain, read]` / `[certain, write]` (JSON `mode`); `lint-tree` reports a
removed property's stale references and `property`/`field` leave
`not_reportable`. **Every index resolved before 1.3.0-alpha answers 0 for
properties until `index --all --resolve-only` (or its next `index`).** A bare
property access inside its own class (`if Flag then`) is a `read` ref, not
`member-access`, and is not bound by this change.
### convert-apply: unlinked source properties are warned by default, as "N of M instances", keyed by (source type, property)

A source property some converted instance carries that no `#link` carries and
no `#ignore` acknowledges is now warned ONCE per (source type, property):

```
TabcToggleBtn.Style: no #link carries it -- dropped on 20 of 20 converted instance(s); add a #link, or #ignore Style to accept the drop
```

Read the fraction, not the count: `2 of 20` is the two controls somebody
deliberately styled (`ParentFont = False`) and is the STRONGER signal; `20 of
20` is a structural non-mapping. Keyed by source type so two `#convert` blocks
both dropping `Style` are two rows, not one. `--format json` carries
`unlinked_source_properties` (rows), `unlinked_source_property_sites` (sum of
sites -- both keep their step-1 meaning) and an additive `unlinked[]`
(`from_type`, `path`, `sites`, `instances`); the warnings are `items[]` of kind
`unlinked-source-property`. `--no-warn-unlinked` drops the warnings and keeps
the count. Default-on because the number earned it: 2 distinct / 22 sites on a
real 36-link book.

### convert: `#link` between class-typed properties carries sub-leaves on TYPE IDENTITY

`#link Font <- Font` with `TFont` on both sides now carries every sub-leaf the
`.dfm` streams (`Font.Charset`, `Font.Name`, ...) automatically -- the five
hand-written `Font.*` lines become one. When the types DIFFER
(`OptionsImage.Glyph <- Picture`, `TdxSmartGlyph <- TPicture`) nothing is
carried implicitly and every dotted leaf must still be named, because an
invented target path is how a form stops loading. An explicit per-leaf `#link`
/ `#ignore` / `#remove` always wins over the carry; a carried leaf is reported
(`sub-leaf-carried` with `path` and `rule_line` in apply/1; `report.carried[]`
in `convert-reemit`) so the leaves nobody typed are visible. Not implemented:
the "target type is an ancestor of the source type" case. Two step-4b defects
fixed alongside: VCL-shaped dotted leaves (`Font.Size = 9` as one child) were
reported "absent from the F DFM", and class-typed containers were listed under
"defaults may diverge".

### duplicate-global-decl: LIBRARY tier

A project global whose NAME is also an interface-level global of a library
unit that the declaring file USES (interface or implementation `uses`;
`SysUtils` matches `System.SysUtils`) is reported -- masking an RTL name is
almost always a naming error. 2+ project units AND the library is the stronger
three-declaration message. Severity `warning`, NO autofix (only you know which
declaration is meant). Measured before the severity was final: 44 findings on
ORM3 CLIENT (every one a genuine RTL/WinAPI re-declaration), rule cost 1.6 s
against the 3.7 GB Win32 library.

### lint: two false positives fixed

* `hardcoded-ip-address` no longer reads a dotted-quad VERSION const
  (`YADF_MIN_VERSION = '1.0.6.6'`) as an IPv4 address. New rule predicate
  `(#in? @cap "nodeType" ["nameRegex"])` / `#not-in?` -- "some ancestor of the
  captured node has that type and its `name:` matches" -- documented in
  `rules\README.md`.
* `review-marker-unused` no longer fires on a `dl:ok` that IS suppressing a
  store-backed (project-scope) finding: the marker join keyed the finding's
  ABSOLUTE path against the scanned file's path as typed, so a relative `lint
  src\X.pas` never matched. Both sides are now normalised.
## v1.13.0-alpha -- 2026-09-16

### Fixed: `outline --file X` said no database resolved for a file `resolve-dbs --in X` found three for

Reported independently **twice** by the converter team (their own
`ConvRules.Usage.pas`, and ORM3's `COMMON\OBJECTS\iFOLDERS.PAS`):

```
resolve-dbs --in ...\iFOLDERS.PAS  -> Micronite2027, MicroniteMW1Service, TestMicroniteObjects
outline --file ...\iFOLDERS.PAS    -> "no project database resolves here"
```

Two statements about the same file at the same moment, and the second is the
false one -- the worse kind of false, because it names a **remedy** ("pass
`--db`") for a condition that does not hold, sending the reader after a missing
index instead of a resolution bug.

`DoOutline` resolved only through `AArgs.DbPath`, which is driven by
`--platform` / the cwd / the manifest default and knows nothing about the file
being read. `resolve-dbs --in` additionally runs a **membership probe**, asking
each candidate index whether it actually contains the file -- and that is what
finds a unit living outside its own `.dproj`'s folder, which is most of ORM3's
`COMMON\` and most of this repo (whose `.dproj` sits in `src\cli` and pulls in a
dozen sibling folders).

**Fixed as shared code, not a second copy.** Both verbs now call
`ResolveReadDbsForFileWith`; the manifest *load* stays with each caller (because
`resolve-dbs` honours `--config` and must exit 2 on a bad one) and only the
ordering is shared. `outline` then walks the resolved list and uses the first
index that actually holds the file -- the same walk `hover` uses -- because
"ordered first" is not "contains it", and answering from an index that does not
hold the file prints an empty outline indistinguishable from a file with no
symbols.

A file in **no** index is still refused (exit 2), never answered with an empty
outline.

Guarded by `tests\autotest\run_outline_resolves_from_file.ps1`, which asserts
the **agreement** between the two verbs rather than the implementation, so it
still fails if the logic is ever re-forked. Every invocation runs from a
**neutral working directory** -- run from inside the repo, cwd resolution alone
can find the index and the guard would pass against the unfixed build.

### Fixed: fourteen more read verbs silently MIGRATED the `--db` they were told to read

**This completes the breaking change v1.12.0-alpha announced for four verbs.**
Those four (`usages`, `typeat`, `deps-report`, `uses-report`) stopped migrating a
caller-supplied index; fourteen more were doing exactly the same thing and were
listed as `unaudited` in the guard that found them:

`hover`, `wiring`, `impact`, `slice`, `bench-context`, `generate-docs`,
`find-deadcode`, `check-unit --resolve-uses`, `cycles`, `uses-audit`,
`uses-fix`, `uses-fix` (sweep form), `generate-test`, `check-ast`.

Each opened the path read-write and called `.Migrate` before reading, so pointing
a *read* verb at an old index silently upgraded it on disk -- a write nobody
asked for, from a command that only claims to answer questions. All fourteen now
use `OpenReadOnlyStore` + `StaleDbRefusesRun`: a stale explicit `--db` exits 2,
says so on stderr, answers nothing, and **leaves the database at its original
schema**.

`run_migrate_site_guard.ps1` goes from `sites: 33  listed: 30  writes: 16
unaudited: 14` to `sites: 19  listed: 16  writes: 16  **unaudited: 0**`.

**The `uses-fix` pair is the one worth noting.** Both routines edit *source
files*, which reads like a write -- but the exemption list is only ever about
writes to the **index**, so both are read verbs and both were fixed. And
`uses-fix` reaches two different routines: with a `<unit>` target it is
`DoUsesFix`, with none it is `DoUsesFixSweep`, so it appears **twice** in the
test matrix or the sweep form would have gone untested.

Fifteen rows added to `run_explicit_db_strict.ps1`'s stale matrix (T5/T5b/T5c/
T5d). Every row is **argument-complete and was verified against a current
database first**: a verb that exits 2 *before* opening any database passes all
four checks without testing anything, which is the trap the existing
`uses-report` row already documents. `uses-fix <unit>` needs `--project` for
exactly that reason, so the fixture now writes a stub `.dproj` -- it only has to
exist, since the store is opened before the project is used. A named coverage
assertion fails with *which* row was dropped rather than an off-by-one.

### Fixed: `format` -- the verb that rewrites your source had no safety net, and `--dry-run` was a lie

`drag-lint format` overwrites a `.pas` in place. It was also the only verb with
**zero test coverage anywhere under `tests\`** -- a `Select-String` for
`TYadfFormatter|drag-lint format|yadf-path` over every runner returned nothing.
Four things were true at once:

* **`--dry-run` rewrote the file.** The flag parsed (it is global) and `DoFormat`
  ignored it, so a user who typed it *specifically* to avoid touching the file
  had the file rewritten anyway. `--diff` did not exist at all.
* **No verification.** A formatter that corrupted the file printed `Formatted:`,
  exited 0, and left the corruption on disk.
* **No version gate.** A YADF old enough to split inline `var` declarations ran
  happily.
* **Two hardcoded Win32 fallbacks** (`...\YADF\Win32\{Release,Debug}\...`) that
  could never resolve, since every YADF build on this box is **Win64** -- each
  carrying a `dl:ok hardcoded-absolute-path` review reading *"an
  existence-checked dev-box fallback, never the only source"*, which justified
  exactly the mechanism that made the original defect silent.

Now:

| | |
|---|---|
| `--dry-run` | resolves, version-checks, prints the binary it **would** run, writes nothing |
| `--diff` | formats a **copy** in a scratch dir and prints a diff; the original is never opened for writing |
| version gate | refuses YADF older than **1.0.6.6**, naming the found version, the floor and the path (**exit 4**, nothing written) |
| verification | re-parses after formatting and compares the **declared symbol set**; on divergence the file is **restored** (**exit 5**) |
| resolution | `--yadf-path` or `HKCU\Software\YADF\ExePath`. **No hardcoded fallback** -- both constants and their `dl:ok` markers are deleted |

Exit codes are now distinct (3 = no YADF, 4 = too old, 5 = corrupted and
restored) because "it did not format" is not actionable on a verb that rewrites
source.

**The gate reads the exe's VERSION RESOURCE, not `--version`.** Measured:
`YADF.exe --version` exits 2 with `unknown option --version`. The probe the plan
called for is not buildable; the resource needs no cooperation from YADF and
costs no subprocess. An **absent** version resource (a wrapper script) proceeds
with a warning rather than being refused -- refusing the unverifiable would
break `--yadf-path` for no gain, since the post-format verification protects the
file regardless.

Guarded by `tests\autotest\run_format_verb_guard.ps1` (21 assertions). The
version-floor pair uses the two **real** YADF builds on the box -- Release
1.0.17.0 (accepted) and Debug 1.0.3.0 (refused) -- rather than a stub, because a
`.bat` has no version resource and could never exercise a resource-based gate;
using both proves the refusal keys on the **version**, not on the binary's
identity. Those two assertions SKIP loudly where YADF is not installed. Note the
Debug build is *older in version* but *newer on disk*: mtime does not order
versions.

### Fixed: `convert-apply` blamed the `.dfm` when the real cause was "not indexed"

On a unit covered by no supplied `--db`, `convert-apply` printed, once per
instance:

```
btnTop: could not locate .dfm object block for "btnTop: TabcToggleBtn"
        in ...\VARINSP.dfm -- instance skipped        ... x20
```

That sentence is **false about the file**. The converter team verified the
`.dfm` was text (not binary) and that all twenty blocks were present at lines
4880, 14705, 17564, ... before concluding anything -- then spent a day
disproving three plausible readings the message invited (binary `.dfm`, nesting
depth, qualified-vs-bare `#convert` type) before finding the real condition:
`convert-apply` resolves `.dfm` blocks **through the index**, and the unit was in
no supplied index. Indexing it converted all twenty.

The lookup fails for two different reasons and the old text asserted the second
unconditionally. `Length(DfmFileSyms) = 0` discriminates them exactly -- which
works because `FindConvertInstances` reads the `.dfm` TEXT, so an unindexed unit
still produces instances to warn about at all.

**No behaviour change.** Requiring an index may be load-bearing and nobody asked
for it to be relaxed; instance counts and the skip/convert accounting are
identical. Only the sentence differs:

```
btnTop: MyForm.pas is not covered by any supplied --db; convert-apply resolves
        .dfm blocks through the index. Index it, or pass a --db that covers it
        -- instance skipped
```

The genuine case **keeps the original wording**, plus a clause naming the two
causes that remain once the index is ruled out (the object is absent, or the
index is stale). Replacing both branches would have traded one false claim for
another and made the real not-in-the-`.dfm` case undiagnosable.

Guarded by `tests\autotest\run_convert_apply_index_precondition.ps1`: the
converter team's own repro shape (a depth-1 and a depth-2 instance, since depth
was one of the disproved hypotheses), two positive controls, and a
**discrimination control** proving an indexed unit with an unknown object still
gets the original message.

### Added: hovering an INTERFACE now names what implements it

Hovering `var ABC: ImcSTATIONS;` answers `TmcSTATIONS`. Before this, hover on an
interface carried Used-by and Used-in-units and nothing about its implementors,
while `query descendants --of ImcSTATIONS` answered instantly -- the data was
indexed, and no surface carried it. Hover on the CLASS did not carry the forward
edge either: `Implements:` is a Phase-1.x doc-only fact.

Two lines, never merged, because a class that implements a contract and an
interface that extends it are different claims:

```
# pFIBInterfaces.IFIBObject
- Implemented by: TFIBCustomDataSet, TFIBDatabase, TFIBDataSet, TFIBQuery, TFIBTransaction, TFriendDatabase (+14 more)
- Extended by: IFIBConnect, IFIBDataSet, IFIBQuery, IFIBSQLObject, IFIBTransaction
```

**The autodoc carries the identical fact, by construction rather than by a second
implementation.** `document`'s managed block and `hover` both format through
`TDocRegions.FormatPhase2FactLines` -- the v(ADP2 T9) consistency lock -- so the
fact was added to `TDocFacts`, not to a renderer. Both lines are appended after
the last existing emitter, so already-documented blocks stay byte-identical but
for the new trailing lines.

**A shipping primitive could not answer half of it, and that is now on record.**
`FindDescendantNames` filters `s.kind IN ('class','type')` at BOTH hops of its
CTE, so an interface can be neither emitted nor **crossed** -- and crossing is the
half that is easy to miss. Measured on library-Win64: `query descendants --of
IFIBObject` printed `(none)` while `type_ancestors` held IFIBConnect,
IFIBSQLObject and IFIBTransaction. That filter is correct for its caller (it
backs the conversion editor's class pickers, which must never be offered an
interface), so its behaviour is untouched; the new fact uses a kind-aware
`FindDescendantNamesOfKind` whose walk admits interfaces and which filters only
what it emits. Logged as `wrong` in `stats\draglint-gaps.log`.

`query descendants`' `--help`, README and AI-USAGE entries now say **class**
rather than "type", and state the interface exclusion, instead of promising
something the verb does not do.

Guarded by `tests\autotest\run_hover_interface_implementors.ps1`, which ships an
**absence control** (an interface with no implementor must not have one
fabricated), a **cap control** (more implementors than `OVERRIDDENBY_CAP` must
report the truncation, not silently shorten), a **kind-separation control**
(a derived interface must not appear on the Implemented-by line), and a
**fixture control** (`query descendants` must see the fixture at all, so a red
run cannot be blamed on the feature when the fixture is what broke).

### Fixed: `query descendants` shipped without ever appearing in `--help`

`query descendants --of <ancestor>` -- the reverse of `query ancestors`, and the
query behind the conversion editor's control-class pickers -- appeared **zero
times** in the 341-line help banner. Its own sibling `ancestors` was documented.
It is now in `--help`, `README.md` and `docs\AI-USAGE.md`.

**The banner line is the smaller half of this change.** `run_docs_sync_guard.ps1`
existed precisely to stop this, and could not see it: check 1 enumerates
TOP-LEVEL verbs only (`Args.Command = 'x'` against `^  drag-lint <verb>`), and
`query` is in both, so the guard PASSED while a shipping subcommand stayed
invisible. That is this repo's founding DOCS-IN-SYNC failure -- "four shipping
verbs missing from `--help`" -- repeating one level down, inside the guard
written to prevent it.

New **check 10** closes the axis. The verb -> subcommand map is derived FROM
SOURCE by `Get-CliVerbSubcommandMap` in `tests\autotest\lib\CliFlagVerbMap.ps1`,
reusing the lexer and dispatch-closure machinery check 9 already uses for flags:
a subcommand binds to the verb whose dispatch closure reaches the routine that
compares it. A flat literal harvest would have been wrong -- it cannot tell
`query`'s eight from `selftest`'s fifteen. Measured: 28 literals, all bound,
across `query` (8), `selftest` (15), `workspace` (3), `export` (2). Subcommands
of a verb that is itself `$UndocumentedOnPurpose` inherit that exemption, so
`selftest`'s internals are reported as skipped rather than demanded.

Three positive controls ship with it, because every assertion is of the form
"this set difference is empty" and a broken derivation produces that for free:
a synthetic subcommand must classify as UNDOCUMENTED, a documented one must
classify as DOCUMENTED (otherwise the check is a guard that always fails), and
the derivation must bind known subcommands to `query`.

### Fixed: a `context` bundle from a BARE name silently omitted the target's body

`context --task "modify DoHover"` returned 870 bytes with **no `## Impl slice`**,
while `context --task "modify DRagLint.CLI.DoHover"` returned 5,035 bytes with
one. The bare form was not a miss -- it RESOLVED, and its own header said so
(`# Context bundle: modify DRagLint.CLI.DoHover`). It then dropped the one thing
a `modify X` task asks for: X's own body.

The bare-name fallback added earlier set `Result.QName` to the resolved
qualified name, so the HEADER became honest. Three consumers kept reading the
raw, still-bare `AQName` -- the class-surface parent, the impl slice and the
caller lookup -- and asked the store about a name it cannot match. The header
was fixed; the body was not. All three now use the resolved name.

This is the verb the token-saving path runs on, so the failure mattered more
than its size: an agent handed the short bundle edits a routine it never saw,
and nothing about the result looks wrong. Bare and qualified forms are now
byte-identical (5,035 bytes both).

An AMBIGUOUS bare name still resolves to nothing, deliberately -- picking one of
several same-named symbols would be a confidently wrong bundle, which is worse
than an empty one. Guarded, with that case pinned, by
`tests\autotest\run_context_bare_name_body.ps1`.

### Changed: the usage log records WHICH tool was replaced, and what the index cost

`stats\draglint-usage.log` gains two optional fields --
`ISO8601 what units_avoided tokens_avoided **tool tokens_used**` -- where `tool`
is `grep` or `read`. `stats\daily-report.ps1` now prints a per-tool breakdown
with a **net** figure (avoided minus spent).

The split exists because the two are not the same claim: for a GREP avoided the
saving is a genuine estimate, while for a READ avoided it is **measured** -- the
file's own size is a fact. The report labels each row's basis so a reader can
weigh it. Reporting `tokens_used` keeps the section honest; a saving that never
subtracts its own cost is marketing.

Pre-existing 4-field rows still count exactly as before -- the parser treats the
new fields as optional. Nothing was migrated.

### Docs: `AI-INDEX-FIRST.md` no longer tells agents to widen `--db` across projects

The published AI rule block still carried *"a cross-project question needs
several `--db` flags"* -- advice the owner **superseded on 2026-08-13**, and the
exact mechanism that wrote `dxXMLWriter`, `FireDAC.Comp.QBE`,
`Spring.Data.ExpressionParser` and `System.JSON` into YADF's shared source. It
now states the authoritative set (project DB + platform library, nothing else),
that authority is per QUESTION rather than per database, and that a genuinely
cross-project question is answered by SEPARATE runs correlated on an explicit
key -- never by widening one query's `--db` list.

The same file, `docs\AI-USAGE.md` and the global AI instructions also gain the
unbounded-`Read` rule: orient with `outline`/`context`, act with a targeted
`Read`, and never read a `.pas` over ~2,000 lines without first knowing which
lines you want.

### BREAKING (behaviour): a late-resolved type-alias ancestor now answers to BOTH names

**What changes for a caller.** `query ancestors --name T --of A` returns **True**
for strictly more `A` than before: when a heritage entry is a TYPE ALIAS that
resolves to a class, the ancestry closure now answers to the alias AND to the
class it resolves to. The alias name as written keeps answering exactly as it
did -- nothing that was True becomes False.

```
  before:  query ancestors --name TcxButton --of TCustomButton   ->  False
  after :  query ancestors --name TcxButton --of TCustomButton   ->  True
  before and after:
           query ancestors --name TcxButton --of TcxBaseButton   ->  True
           query ancestors --name TcxButton --of TControl        ->  True
           query ancestors --name TcxButton --of TCustomEdit     ->  False
```

`GetTransitiveAncestors` already late-resolved the alias and stamped the row
with the TARGET's symbol id, file id and kind -- so the walk DID traverse it,
which is why `--of TControl` was already True -- but it left `Name` as the alias
and the target's own NAME never entered the closure. Marked breaking because
every ancestry consumer reads this contract, not because a caller must change:
the change is purely additive, and a caller only sees answers it should always
have had.

* **`TTypeAncestor` gains `ResolvedName`** -- '' on every ordinary edge, the
  target class on a late-resolved alias. `Name` is untouched. The row COUNT and
  ordinals are untouched.
* **By-name ancestry matching moves to `TTypeAncestor.MatchesName`**, which
  consults both names. Callers that read `SymbolId` are unaffected -- they never
  read the new field.
* **`query ancestors --json` gains `resolved_name`** on every ancestor element;
  the text form renders `TcxBaseButton [class] -> TCustomButton`.
* Consumers widened to both names: `IsDescendantOf`, `ImplementsInterface`,
  LSP completion's type test, `IsTestRoutine`'s `TTestCase` climb, PropTree's
  `TComponent` test and its `--to-persistent` stop-class test, ProjectRules'
  `TDataModule` and behavioural-root climbs, and ClassMetrics' CBO/Ca ancestor
  exclusion (an ancestor reached only through an alias is no longer also counted
  as efferent coupling). `UnresolvedAncestorNames` is unchanged by construction
  (it reads only UNRESOLVED rows).

**Neither of the two obvious fixes was taken, and that is the load-bearing part.**
Overwriting `Name` with the target would have broken every consumer that
legitimately asks about the alias as written (PropTree's `ScopeSymbolFor`
resolves `A.Name` in the declaring class's unit scope). Appending a SECOND row
for the target would have put two rows on one symbol id, and
`CallResolver.LookupMethodOnType` counts matches ACROSS ancestor rows and reads
two candidates as AMBIGUOUS -- every inherited method would double and resolved
call edges would be REMOVED, which that code's own comment calls the one outcome
a resolution change must never produce. One row, two names.

Query-side only: **no extractor change, no reindex, and existing indexes get the
new answers as they are.** `DRAGLINT_VERSION` and `DRAGLINT_EXTRACTOR_VERSION`
are both unchanged.

Measured on `library-Win64`: the entire affected population is **6** heritage
edges naming an alias whose target is a class (`TcxBaseButton -> TCustomButton`,
`TMessage -> TMessageBase`, `TSkCustomPrinter -> TPrinterWin`,
`TEurekaStackList -> TEurekaStackListV7`, `TBaseTransportFilter ->
TFactoryObject`, `TFrame -> TFIBEditorCustomFrame`), every one a genuine
`X = Y;` declaration. The ambiguous `TFrame` still DECLINES to resolve, so no
wrong ancestor is grafted. **`query descendants --of TControl` is 2923 before
and after** -- unchanged by design: `FindDescendantNames` is a recursive SQL CTE
that never calls `GetTransitiveAncestors`, so the two verbs reach an alias by
different paths.

Guards: `tests\autotest\run_ancestors_alias_target_name.ps1` (asserts BOTH
directions -- the target became reachable AND the written alias name did not
vanish -- plus row-shape cases that fail the duplicate-row fix), and a new `A3`
line in `tests\autotest\run_descendants_alias_hop.ps1`, which had asked for it
by name. Closes `docs\INBOX-late-resolved-alias-keeps-the-alias-name.md` and the
converter team's ask 2 in `INBOX-forward-decl-shadows-real-class-declaration.md`.

### Fixed: the documentation generator's two owner-reported defects (PLAN-autofix-campaign 4.2, session 93 W4-M0)

Both fixes are RENDER-TIME. Raises are mined by a source-line scan at
`document` time (`TDocFactsBuilder.MineRaises` / `MineRaisesDetailed`), not
by the extractor, so neither bills `DRAGLINT_EXTRACTOR_VERSION`; both version
constants are unchanged.

* **`<exception cref="E">` is no longer fabricated from a re-raise.**
  `on E: Exception do ... raise E;` (ORM3 `BASICSF.CopyRecords`) documented the
  handler VARIABLE as a class. The scanners now record `on <Var>: <Type> do`
  bindings and resolve a bare `raise <Var>` to the declared type (most recent
  binding); a bare variable with no binding emits NO tag (absence over wrong),
  and `raise Unit.Class.Create(...)` names the CLASS instead of the unit
  (was `cref="System"`). `raise Class.Create('msg')` is unchanged, message
  included. `DRagLint.Doc.Facts`: `ResolveRaiseClass`, `RecordHandlerBinding`,
  `TBodyScanState.HandlerVars/HandlerTypes`. Guard:
  `tests\autodoc\run_doc_exception_reraise_var.ps1`.
* **An unmarked (hand-written) tag now survives `document --apply`
  byte-identical**, as `docs\AI-USAGE.md`'s provenance contract promises
  ("not its text, not its whitespace"). The repair path rebuilt every
  preserved tag from the parsed model -- blank runs collapsed, continuation
  lines trimmed, `<param name="Count">` re-spelled to the signature's `COunt`.
  Every preserve arm (summary, deprecated, param, returns, exception, example,
  see/seealso, since, remarks prose) now emits the author's own raw lines when
  they exist and say what the model says, with a whitespace-collapse compare
  as the safety net so every nested/duplicate/exotic shape falls back to the
  previous behaviour. `DRagLint.Doc.Regions`: `VerbatimTagLines`,
  `VerbatimRemarksProseLines`, `CollapseForCompare`, `EmitPreserved`. Guard:
  `tests\autodoc\run_doc_unmarked_block_byte_identical.ps1` (whole-line
  equality, ordered for the canonical shape, plus `strip(apply(x)) == x`).
  RESIDUAL, filed as `docs\INBOX-doc-preserved-tags-reordered.md`: the
  engine's fixed emission order still MOVES a `<returns>` written before the
  `<param>`s -- bytes preserved, position not; owner's call.
* **`document --strip` now removes the engine's own `<exception>` tags.**
  `ManagedTagCloser` never learned the `<exception` opener and the stripper
  did not know `AUTO_EXC`, so every generated exception tag survived `--strip`
  -- found by the new guard's inverse check. Both fixed in
  `DRagLint.Doc.Strip` (`MarkedTagMayHoldHumanText` keeps the D-4 exception
  for a human's text inside a bare-marker tag).

Sweep of sibling defects: `<returns>`'s `Observed: nil; Typed.` is the mined
`Result :=` list (`Typed` is a local in `uPLANLIST.LoadByID`) -- by design,
unlabeled. The `doc-drift` on `Core.Interfaces.pas:410` is "names facts in
unit(s) this index does not hold; not auto-fixed" -- the cross-project caller
union that `dl:shared` exists for, not a generator bug. Remaining raise
shapes filed as `docs\INBOX-doc-raise-shapes-still-unresolved.md`.

### Tests: the per-verb flag axis is now derivable, and the gap is measured (plan section 10)

`CLAUDE.md`'s DOCS-IN-SYNC table promises that **every flag a verb accepts is
listed on that verb's line**. Only the first half of that rule -- every verb is
listed -- was checkable: `ParseArgs` is verb-agnostic, so nothing in the parser
says which verb takes which flag, and `run_docs_sync_guard.ps1` check 9
therefore polices flags as SETS and records the per-verb axis as a follow-on.

**`tests\autotest\lib\CliFlagVerbMap.ps1` is that missing truth source**, from
source alone: flag -> `TArgs` field (the `ParseArgs` chain) -> reading routine
(`AArgs.<Field>`) -> verb entry routine (transitively, through the routines a
verb hands `AArgs` to) -> verb (the `Args.Command` dispatch arms). It does
**not** use the index, deliberately: the resolver walks `kind = 'call'` only
(`docs\INBOX-property-refs-never-resolve.md`), so a field reference never gets a
`refs.symbol_id` and a map built on those refs would be a ghost measurement.

It lexes before it scans, because a text scan of Pascal is wrong three ways and
all three are live in `DRagLint.CLI.pas`: comments there discuss `Result.Edges`
in prose, `PrintHelp` PRINTS the text `{$IFDEF}` from inside a `Writeln`, and
`:23773` is a real `{$IFNDEF WIN64}` whose dead arm must not contribute a
cell. A conditional symbol with no ruling keeps BOTH arms and is named, never
silently dropped.

**`tests\autotest\run_flag_verb_map.ps1` proves the derivation and reports the
gap.** MEASURED against the deployed banner: the code consumes **439** (verb,
flag) cells and **124 of them, across 33 verbs, are absent from that verb's own
`--help` block** -- 51 of the 124 being the same seventeen lint/autofix/doc
flags repeated on `lint-project`, `check-ast` and `lint-all`, which the banner
today factors onto the `lint` line. Closing that is a banner-design decision
with an owner's name on it, so **the guard does not land red over it**: the gap
is printed in full every run and RATCHETED against the recorded baseline, so it
can grow no further silently. What the guard does hard-fail on is the
derivation -- four planted cases (a read in a comment, in a string literal, in
an inactive `{$IFDEF}` branch, and a positive control that the same read IS
found when it is none of those) and four structural assertions, each encoding a
defect measured while building the map: a qualified `TFbSnapshot.Run(AArgs.X)`
read as a call to the DISPATCHER (which silently gave two verbs all 161 flags),
`Run`'s interface forward declaration matched instead of its implementation
(zero verbs, every downstream set legitimately empty), the four multi-line
dispatch arms scoring as unresolved, and a branch's GUARD read of
`Result.Command` counted as a binding (which handed `--dir`/`--root`/`--unit`
to nearly every verb).

The map independently reproduces the prediction the plan recorded for it:
`--size-guard-mb` and `--force32` are consumed by exactly `index`, `query`,
`lsp` and `serve`, and appear on none of those four verbs' lines.

### Docs: README and AI-USAGE now name every `--help` flag (plan 7d, unguarded by design)

The flag long tail is closed: re-derived against the deployed banner (162
flags), `README.md` lacked 27 and `docs\AI-USAGE.md` 45 -- more than the 16/34
the plan recorded, because the banner has grown since (walk scoping, size
guard, `lsp` client tokens, `--no-seealso`, `shutdown`). Both now lack only
`--n`, which the guard's prose regex cannot see by construction (it requires
two characters after `--`). Each new cell says what the flag is FOR, in the
row of the verb that takes it: walk scoping and `--force-reparse`/`--no-skip`
on `index`, `--size-guard-mb`/`--force32` wherever a DB is opened,
`--parent-pid`/`--stdio`/`--clientProcessId` on `lsp`, `--no-seealso` and
`--since [--base-dir]` on `document` (AI-USAGE previously listed `--seealso`
as if it were still the opt-in), `--with-rules`/`--compile` on `lint-tree`,
`--layers` on `lint-project`, and the `preprocess-file`/`ghost-check`/
`pp-profile`/`fb-snapshot` flags in AI-USAGE's diagnostic section. **Check 9's
F4 scope is unchanged**: the guard still demands only the promoted set, and
this pass is not a guard obligation.

### `drag-lint shutdown` -- a maintenance control channel for lingering `lsp` engines (owner request 2026-09-14)

**An engine started in `lsp` mode now listens on a per-user, per-session
named pipe** (`\\.\pipe\drag-lint-ctl-<sid>-s<session>-p<pid>`, explicit DACL
for the creating user only, remote clients rejected, never a TCP port) that
answers exactly two messages: `status` (pid, versions, the databases it holds)
and `shutdown`. Until now nothing could ask an engine another process spawned
to let go of an index or of `drag-lint.exe`: LSP `shutdown`/`exit` rides the
editor's own stdio, `--parent-pid` and the Job Object fire only when the
spawner dies, and `ide-release` reaches the Delphi plugin but not a VS Code
server. The alternative was `TerminateProcess`, which leaves `-wal`/`-shm`
sidecars and in-flight work behind.

**New verb `drag-lint shutdown [--db <f>]... [--wait <sec>] [--dry-run]
[--all] [--force]`.** Discovery is the pipe namespace itself (no instance file
to go stale); `--db` keeps only engines holding that index; `--dry-run` lists
and changes nothing. An asked engine stops reading, closes every store, replies
`exiting` and exits 0 -- measured: no sidecar left, database byte-identical.
An engine inside a request answers `busy <method>` and keeps running (verb
exit 1); `--force` escalates to `TerminateProcess` ONLY after that refusal and
says `ESCALATING`. Every honoured or refused request is audited (asking pid +
exe, time) on the engine's stderr and in
`%LOCALAPPDATA%\drag-lint\control-channel-audit.log`. Only `lsp`-mode engines
listen -- ONE gate, `ControlChannelEnabledFor`, provisional pending the
owner's answer; widening is additive. New unit `DRagLint.Core.ControlChannel`;
`run_control_channel_guard.ps1` (RED against 1.12.0-alpha) with positive
controls: a killed reader DOES leave `-shm`, the DACL reader DOES see an
Everyone ACE, `serve` does NOT listen, a stray message stops nothing.

### The extractor never downgrades an index; the LSP server is a reader (owner rulings 2026-09-14)

**`index` and `index --all` REFUSE a database built by a NEWER extractor.**
The fingerprint gate compared for inequality only, so an engine whose
`DRAGLINT_EXTRACTOR_VERSION` was OLDER than the stamp (the VS Code extension's
private copy sat at 1.15.0 while the canonical engine had just written 1.16.0
in a 7-hour re-parse; a stale CLI on PATH is the same shape) re-parsed every
file with the older extractor and stamped the database DOWN -- exit 0, evidence
gone. Now: engine older than the stamp -> exit 2 (`index --all`: the section
fails), both versions named on stderr, file byte-identical, no flag overrides
it (`--rebuild` and `--force-reparse` would still produce a downgraded index).
Compared SEMANTICALLY (`CompareDottedVersions`, new unit
`DRagLint.Core.Versions`): `1.100.0` is above `1.16.0`, which a string
comparison gets wrong. A NEWER `schema_version` refuses the same way, and
`TSQLiteSymbolStore.Migrate` raises `EIndexNewerThanEngine` before its first
DDL as the net under every other writer. `run_index_never_downgrades.ps1`
(RED against 1.12.0-alpha; positive control: an OLDER stamp still re-parses).

**`lsp` opens every `--db` READ-ONLY and never migrates it.** Until now the
server opened each database writable and ran `Migrate` (DDL), so every editor
held a writable, migrated connection to the project index and the 2.98 GB
library index, and an editor on an older engine migrated the database it was
only meant to read. A `--db` whose schema predates the engine is refused on
stderr with the read verbs' actionable line and skipped; the stores behind it
still serve. Each opened store is announced on stderr with the engine's
version, its extractor version and the index's stamp, so an engine/index skew
is visible in the editor's engine log. `run_lsp_reader_guard.ps1`: a full
session leaves a project DB byte-identical, a v12 DB named first is refused
and untouched (positive control: `index` on the same file moves its md5).

**The read-only connection names the journal mode the file already has.**
`TSQLiteSymbolStore.Connect`'s read-only path asked for WAL unconditionally
(and its comment claimed the mode was untouched); FireDAC runs
`PRAGMA journal_mode = <param>` on every connect, so every read verb and the
LSP rewrote a rollback-journal database's header (byte 18: 1 -> 2). Now the
header is read first (`HeaderSaysWal`, exported from
`DRagLint.Storage.FileMembership`, the same reading W1 used for the
membership probe). Pinned by `run_lsp_reader_guard.ps1` C2.

**`circular-uses` no longer infers an edge from a DOTTED, un-indexed unit's
last segment.** `FireDAC.Phys.SQLite` fell through to stem `sqlite` and became
an edge to `DRagLint.Storage.SQLite`, so every unit opening a FireDAC
connection reported a phantom 2-unit cycle. The stem fallback now applies only
to an unqualified name (`uses SQLite`), which is what the unit-scope-name map
is for. `run_circular_uses_message.ps1` pins both halves.

### A forward-declaration stub no longer shadows the real class in a BY-NAME pick

DevExpress forward-declares its classes (`TcxCustomButton = class;`) and
declares them for real further down. Both are `kind='class'` rows; the stub has
no heritage, no members, no `type_ancestors` rows -- and the lower id.
`FindSymbolsByQualifiedName` already ordered a body before a stub, but the
BY-NAME lookup (`FindSymbolsByExactName`) ordered by `qualified_name` alone,
which the two rows share, so every consumer that takes the first class-kind
row by name started at the stub. Measured on library-Win64:
`query ancestors --name TcxCustomButton` -> `(none)` while
`--of TControl` on the same class said True.

The by-name pair now carries the same body-before-stub leading term (then
`qualified_name`, so two REAL declarations in two units keep their order).
One change, every first-pick consumer: `query ancestors --name`, the
abstract-instantiation class pick, `typeat`'s any-store lookup,
virtual-method hiding (`ResolveTypeSymbolId`) and `wiring`'s form lookup.
A class whose ONLY row is a stub still resolves as a class with no ancestors.
`run_forward_decl_shadow.ps1`, RED against 1.12.0-alpha.

### `query descendants` crosses a type alias standing in heritage position

`TcxBaseButton = TCustomButton; TcxCustomButton = class(TcxBaseButton, ...)`.
The alias row owns its `type_ancestors` edge since member C, but the
descendants CTE joined `kind='class'` at every hop, so the alias never entered
the name set and everything below it was silently absent: 2918 `TControl`
descendants on library-Win64 without `TcxButton`, so the conversion editor
could not offer it. Now 2923, `TcxButton` present, and an alias NAME is never
emitted (an alias is not a class). Strong aliases (`= type X`) carry no
heritage row and are neither crossed nor emitted.
`run_descendants_alias_hop.ps1`, RED against 1.12.0-alpha.

The converter note that reported both blamed the stub for both symptoms; the
stub is invisible to `descendants` (no ancestor rows, name-walked), and its
symptom B (`OptionsImage` a bare leaf in `proptree`) did not reproduce on
either library index with either engine -- proptree routes every pick through
`BodyOf`. Found while guarding: the late alias resolution in
`GetTransitiveAncestors` keeps the ALIAS name on the resolved row, so
`TcxButton --of TCustomButton` is False while `--of TControl` is True. Filed,
not fixed here (`INBOX-late-resolved-alias-keeps-the-alias-name.md`).

### `usages`, `typeat`, `deps-report` and `uses-report` no longer MIGRATE a stale `--db` in place

Handed an explicit `--db` at an old schema, the four verbs opened it
read-write, ran the full schema migration on it (measured: schema_version
12 -> 22, 4 tables -> 31, 28 KB -> 320 KB, journal delete -> wal) and then
answered from it -- exit 0, nothing on either stream. Against the 1.4 GB
library index that is minutes under a write lock while the operator believes
they ran a read, and afterwards the evidence that the index was ever stale is
gone, so the refusal C3 introduced could never fire for them.

They now open every `--db` read-only through the same path as the other read
verbs, and a stale EXPLICIT `--db` is **refused (exit 2)** with the schema gap
and both migrate commands on stderr -- the contract every other multi-db verb
already had. A stale manifest-resolved db is still skipped, not refused.
`run_explicit_db_strict.ps1` T5d now covers all seventeen verbs.
(`uses-report` is `deps-report`'s twin -- the same `OpenStores` shape -- and
the original measurement missed it.)

A new guard, `run_migrate_site_guard.ps1`, pins the shape rather than the
four instances: every `.Migrate` call in `src\cli` must sit in a routine on a
named exemption list, with a reason. The list may only shrink. It records
sixteen verbs that migrate BY CONTRACT (`index`, `rename`, the lint family,
the self-tests) and fourteen read-shaped verbs that still carry the same defect
(`hover`, `slice`, `cycles`, `generate-docs`, `check-ast`, ...) -- listed so
the guard is green for the work that is done and red for the work being undone
again, not as an endorsement.

### The membership probe no longer rewrites a database's journal header

`DbContainsFile` (what `resolve-dbs --in`, `lint`, `query unit-usage` and
`query type-usage` use to ask "does this index hold this file?") asked FireDAC
for `JournalMode=WAL` unconditionally, so probing a rollback-journal database
flipped its header to WAL -- a write, from a function documented read-only.

The obvious fix -- drop the parameter -- would have been worse: FireDAC runs
`PRAGMA journal_mode = <param, else Delete>` on EVERY connect, so an absent
parameter converts every real (WAL) index back to a rollback journal on each
probe, or fails BUSY under a live LSP reader and reads as "not mine". The
probe now reads the mode from the SQLite file header and asks for that, so
the pragma is a no-op in both directions. `run_project_db_resolve.ps1` (6d)
pins both: a rollback-journal fixture stays `delete`, a real index stays `wal`.

Not changed: `TSQLiteSymbolStore.Connect`'s read-only path still passes WAL
unconditionally, so a read verb that OPENS a stale non-WAL database (rather
than merely probing it) still flips its header. Its own comment says the
journal mode is untouched; it is not. Recorded, not fixed here.

## v1.12.0-alpha -- 2026-09-14

**Two breaking changes.** Both are about a command that used to succeed while
doing less than the caller asked for: a `--db` that did not exist was dropped
and the run reported success anyway, and `default-resolved` -- a receipt for
work that already worked -- buried the four kinds a human must act on inside
`items[]`.

Note on numbering: **v1.11.0-alpha was prepared but never published** (version
bump and CHANGELOG only -- no tag, no release), so this release carries
everything since the last published one, **v1.10.1-alpha**.

### `--help` lists every flag the CLI accepts, and the guard now enforces that

19 flags were accepted by `ParseArgs` and printed by `--help` nowhere, so a user
reading the banner could not discover them. 12 are now documented; 7 are
recorded as deliberate exemptions with a reason each (verb-is-itself-exempt,
back-compat alias, or test-harness entry point).

Newly listed: `--exclude-under`, `--include-only`, `--max-file-kb`,
`--no-use-ignore`, `--no-sql-ms`, `--deep`/`--shallow` (all `index` walk
scoping), `--scan-libraries` (named as the alias it is), `--size-guard-mb` and
`--force32` (they apply wherever a db is opened, so they went in the `Databases`
block), `--clientProcessId` (`lsp`), and `--no-seealso`.

**One banner line was WRONG, not merely incomplete.** It read "add `--seealso`
to any document mode to emit `<seealso cref>` links". `DocSeeAlso` has defaulted
to True since the flag became the default; `--seealso` is a kept no-op and
`--no-seealso` is the real switch. A reader following that line would have
concluded the links were off.

`tests\autotest\run_docs_sync_guard.ps1` gains **check 9**, which polices flags
the way it already polices verbs: every accepted flag must be in `--help` or
exempt (both directions asserted, so the exemption table cannot outlive what it
exempts); no `--help` flag may be a phantom; no prose doc may name a flag
`--help` does not carry; and every flag the banner PROMOTES -- its COMMON
QUESTIONS block, its Output/CI block, and anything on five or more verb lines --
must be named in README and `docs\AI-USAGE.md`.

That last rule is narrow on purpose. Demanding all ~147 flags in all three
documents is ~50 doc cells now and two more per flag forever, in documents whose
job is orientation; README says in its own voice that the authoritative flag
list is `--help`. A guard that fails because `--parent-pid` is missing from
README is a guard someone weakens, and this repo holds that a rule which is on
but ignored is worse than one that is off.

It found a real gap on its first run: `--enable`, `--profile` and `--fail-on` --
the lint CI contract -- were absent from the document written for agents. Now
documented there.

Also new: **F0**, which compares the deployed exe's `--help` against `PrintHelp`
in source and says "rebuild first" instead of reporting doc drift. The exe is
not tracked, so the guard had been comparing two points in time.

### BREAKING: `default-resolved` leaves `items[]` for its own `resolved_defaults[]`

`convert-apply --format json` gains a top-level `resolved_defaults[]` array, and
`default-resolved` no longer appears in `items[]` or in `reemit_notes[]`.

It is the one kind that is a RECEIPT rather than a remainder -- it records work
that already succeeded -- and the only one whose volume scales with the SIZE of
the form rather than with what is wrong with it. The converter team measured
**~2,156 of these against at most 1,229 real properties** on a single form. In
`items[]`, which is the array their contract tells them to dispatch on, that
buried the four kinds a human must act on under work that had already worked.

Six typed keys per entry -- `instance`, `from_path`, `to_path`, `value`,
`rule_line`, `line`. **`to_path` and `value` are newly recoverable**: they
existed only inside the prose before, so reading them meant parsing English.
`kind`/`field` would be constant on every entry, `file` is the document's own
`dfm`, and `text` carried nothing that is not now a typed key.

The array is always present (`[]` when empty) and is **disjoint from `items[]`
and from the six arrays** -- a consumer summing those six to predict
`items.length` must not add it in. Text mode prints a one-line count instead of
the entries.

**Why it stays `apply/1`.** Adding a key is additive by the stated rule; a kind
LEAVING `items[]` is not covered by it. The repo's closest precedent (the
`default-superseded` rename, where "a consumer pinned to it sees the kind
disappear") shipped as a `!` commit with no bump because nothing consumed it.
Re-measured the same day rather than inherited: zero code hits in `src\tools\`,
and the converter side's own note states the editor calls no `convert-apply`
yet. With a real consumer this would have been `apply/2`.

Measured on the way, and it corrects a documented limitation: **an owned part's
absent-because-default property IS resolved and reported**, exactly once, under
the part's own instance name. `AI-CONVERT-RUNBOOK` said otherwise; that sentence
was about `HandleNested`, which re-runs a part with the PARENT's trees, and not
about the instance loop, which is how a part actually reaches `apply/1`.

`convert-reemit`'s own JSON (`report.defaultsResolved`, camelCase, no `schema`
key) is a different surface and is unchanged.

### BREAKING: an explicit `--db` that does not exist now refuses the run

Most verbs did `if not TFile.Exists(Db) then Continue` -- they dropped a `--db`
the caller had named, answered from whatever remained, and exited 0 with nothing
on either stream. `convert-scaffold --db app --db lib-typo` drafted rules from a
corpus smaller than the operator asked for, `convert-validate` then passed them,
and `convert-apply` rewrote a form on that basis, each step reporting success.

Reported by the converter team against `proptree`; an audit found **40 sites, 31
needing the change**, including three `query` subcommands -- so `query` was not
self-consistent -- and:

* **`lint <file> --db <missing>` silently dropped every store-backed rule and
  reported FEWER findings.** Measured on `DRagLint.CLI.pas`: 429 findings with a
  real index, 422 with a missing one, identical exit code, silence on both
  streams. "I ran the linter and it was clean" could be false for an invisible
  reason.
* **`lint-all` and `serve` CREATED the database they were told did not exist** --
  SQLite makes an empty file for a path opened for write, so a typo manufactured
  a brand-new, authoritative-looking, entirely empty index that then answered
  "nothing found" convincingly.

Now: every missing path is named on **stderr** with its position (`--db #2 of 3`)
and the repair command, stdout stays empty, and the verb exits 2. All 28 verbs
route through one helper, `ExplicitDbsExist`, so strictness cannot drift per-verb.

**Manifest-resolved runs (no `--db`) are unaffected by construction** -- the
helper reads only the explicit list, and `TDbSelect.Resolve(ARequireExists=True)`
already dropped absent files there.

Errors move from stdout to stderr for `query` and `query --text`, which were the
two strict verbs writing to stdout. stdout is the document under
`--format json|sarif`; **exit 2 is the machine-readable signal, not the prose.**

### BREAKING: an explicit `--db` at an OLD SCHEMA now refuses the run too

The other half of the same hazard, with a different cause: the file is there, but
it was written by an older build. 19 multi-db loops did `if not RoOk then
Continue` -- they skipped the stale store and answered from the rest, exit 0.
And the CLI contradicted itself, because single-db verbs already refused: `outline
--db <v12>` exited non-zero while `query --db <v12> --db <good>` quietly dropped
it. The same database, two contracts, decided by which verb you happened to run.

Now a stale database the operator named with `--db` refuses the run: the reason
and BOTH migrate commands go to stderr, stdout stays empty, exit 2. This is the
2026-08-13 ruling applied where it had never reached -- *a stale DB is not
authoritative, and the answer is to rescan, not to report*. Manifest-resolved
runs still skip a stale sibling, which is what the caller asked for.

**The cost, stated plainly:** an operator whose standing `--db P --db L` list has
a stale L is blocked on every verb until they reindex.

Also fixed, and the reason `--format json` could break on a stale index: the
`index schema vN < vM` line went to **stdout**. Measured across 13 verbs, 11
printed it there -- into the middle of the JSON or SARIF document they were
writing. Both emitters (`OpenReadOnlyStore` and `OpenWritableStore` -- the latter
is the one `proptree` actually hits, since it opens writable by default) now write
to stderr.

Two things the measurement corrected on the way:

* **`usages`, `typeat` and `deps-report` MIGRATE a stale `--db` in place** --
  schema 12 to 22, 4 tables to 31, 28 KB to 320 KB, exit 0, silence. They call
  `Store.Migrate` on whatever they are handed, against the documented policy of
  never migrating someone else's gigabytes as a side effect of a read. There are
  37 such call sites; these three were measured. Out of scope for this change and
  NOT fixed here -- the guard's T5d pins the no-migration property for the 13
  verbs it covers, so a regression into them is caught.
* A stale index still answers `DbContainsFile`, so `query unit-usage` and `query
  type-usage` probe membership BEFORE checking the schema. They refuse correctly
  once the stale index actually holds the file, which is the realistic case.

## v1.11.0-alpha -- 2026-09-11

### Tier-3 compile: 382 s -> 30.1 s on a 207-dependent unit

* `lint-tree --compile` ran ONE dcc invocation per dependent. It now compiles
  once, via a generated probe unit in the shadow directory whose `uses` clause
  names every dependent, with a capped re-run per independent breakage root.
* The tier-3 compiler never dropped `<BDS>\source` from `-U` although its
  sibling always had -- the two builders had drifted. dcc was recompiling the
  RTL from source on every invocation and dying before it reached the unit under
  test, which is why 216 of 219 findings were `F1026` on `.inc` files and none
  were about the user's code.
* `-I` is now set at all. It never was, so every include (`Spring.inc`,
  `cxVer.inc`) failed to resolve. Built from the same filtered list as `-U`.
* Cloud-backed roots (OneDrive and friends) are excluded from both flags by
  string. Enumerating them stalls dcc; `DRAGLINT_EXCLUDE_ROOTS` is the hatch for
  other providers.
* The project's own `<DCC_DcuOutput>` is on `-U`, so prebuilt DCUs are reachable.
* `check-unit` and tier 3 now share ONE builder instead of two drifted copies.

### Plugin fixes found by in-IDE testing

* **The interface fan-out had never once run.** `CheapHash`/`CheapBufferHash`
  are wraparound hashes and the design-time package compiles with `-$Q+`, so
  both raised `EIntOverflow` on every call. Hidden by a bare `except` with an
  empty body AND by a test harness that compiled with overflow checks OFF; all
  three plugin harnesses now build with `-$Q+ -$R+`.
* **The IDE could not exit.** `AggregateDiagnostics` held the provider lock
  across a minutes-long run while `UnregisterDiagnosticProvider` needed it on
  the main thread. The lock now covers only the list copy.
* A fan-out launch the worker could not start was silently lost; it is taken
  back and retried.
* The live runner analysed RAD Studio's own sources if you opened one -- a
  217 KB RTL file started a run that held the lock for 625 CPU-seconds.

### lint-all

* Progress no longer sits at 100% while thirteen further phases run; the scan
  scales to 90% and each phase reports itself by name.
* Findings go to a `drag-lint lint-all` tab, nested under one row per run
  (`<Project>-lint-all-<date>-<time>`), instead of flat in the Build tab.

### About

* Reports YADF / YADFOT / YADFSetup versions, resolved through the IDE's own
  Known Packages.
* "Check for Updates" compares against GitHub releases numerically, field by
  field -- a string compare puts 1.10.1 below 1.4.0. Offline reads as
  "unknown", never "up to date".

### Rules

* `criticalsection-not-released` understands `TMonitor.Enter/Exit` (was 12 of
  the 13 errors in the plugin project, all false).
* `referenced-never-set` counts a member call on a field as a write.
* `dfm-property-not-declared` reads `DefineProperties` pseudo-properties:
  321 findings on ORM3 CLIENT became 2.

### Extractor

* `DRAGLINT_EXTRACTOR_VERSION` 1.15.0-alpha -> 1.16.0-alpha, discharging the
  deferred re-parse for unit-qualified routine references.
## v1.10.1-alpha -- 2026-09-07


**Upgrade if you use `document --apply`.** v1.10.0-alpha and every release
before it could DELETE documentation you wrote. Two independent defects did it,
both fixed here, both reproduced on real source before a line was changed.

### `document --apply` no longer deletes prose a human wrote

Two shapes destroyed authored text. Neither announced itself: the run reported
success, and the words were simply gone from the next diff.

**1. A stacked doc region swallowed its neighbour's prose.** Two `///` blocks
with no blank line between them were read as one, and the second declaration's
authored text was absorbed and lost.

**2. A `<summary>` carrying the engine's marker but holding YOUR words was
deleted outright.** If you typed into a generated stub without removing its
`<!-- drag-lint:auto -->` comment -- the ordinary thing to do -- the engine read
the marker as proof the tag was its own, found it had nothing to refill the tag
with, and removed the whole thing. Measured on this repo's own source: 53 words
of a developer's explanation, gone in one sweep.

The fix is a new ownership marker, `<!-- drag-lint:auto sum -->` (`AUTO_SUM`),
which says "this summary's body is the engine's HARVESTED prose". That
distinction was not expressible before, and without it two situations are the
same string:

| you see | what it means | correct behaviour |
|---|---|---|
| marker + your words | you typed into a stub | **KEEP the words, drop the marker** |
| marker + harvested prose whose source comment was deleted | the engine's own text, now orphaned | **REMOVE it** |

Reading the old marker either way broke one of them, which is why this needed a
marker and not a smarter guess. It is the third time the same answer has been
reached here, after `AUTO_TYPE` and `AUTO_EXC`.

**Nothing is asked of you.** Existing marked summaries migrate on the next run
with no content comparison and no edits to your source: a summary whose comment
still yields a harvest simply takes the ordinary refill path and comes back
re-marked. Measured on this repo: 103 of 103 migrated. Only the genuinely
ambiguous case (marker present, nothing left to harvest) falls through, and it
fails SAFE -- your words are kept.

`--strip` follows the same rule, so it cannot become a second route to the same
loss.

### `query find --decl-contains` -- search the declaring source line

Finds clauses the extractor does not model, by searching the DECLARING SOURCE
LINE rather than the symbol table. 97 matches in 298,982 candidates on the
Win32 library index in 18.9 s.

### IDE plugin: save-triggered refreshes are queued, not spawned

`refresh-findings` was launched detached from both the save hook and the idle
tick, with nothing to coalesce or serialise it. A measured live session showed
**32 spawns, ~20 of them inside 9 seconds**; since each one recompiles units,
the LSP started into that load and its `initialize` took 101 s against a 45 s
timeout -- surfacing as *"LSP initialize handshake failed"*, about a handshake
that had actually succeeded.

It now goes through the job queue with a per-database coalesce key, so a burst
of saves collapses to one pending sweep and cannot collide with a reindex
holding the WAL lock.

Also in the plugin: the caret line selects its corresponding finding in the
drag-lint panel.


### doc-drift compares an inbound list as a SET, so reordering is not drift

Owner ruling, 2026-09-06: *"Order is not important. We should compare parts.
I.e. all parts (lines) are there and not missing, then the Documentation is OK.
If unit is used by several projects then the order might change and this is
OK."*

What prompted it: `document --apply` rewrote a facts block by SWAPPING TWO
`Used by:` entries and changing nothing else, after which `doc-drift` called the
block stale and FIXABLE while `document --qname` said "up to date (no change)" --
the checker and the writer disagreeing about a block whose CONTENT was never
wrong. Restoring the original order by hand cleared the finding, which is what
proved the order was the whole of it.

`TSharedFacts.BlockDrifted` already knew how to do this: it has compared inbound
lists as SETS since 2026-08-13, for units marked `dl:shared`. The only thing
keeping every other unit on a whole-block byte compare was an early `Exit`. That
`Exit` is gone, so the set comparison is now what every unit gets.

Three things deliberately did NOT change, and the new guard pins each:

* an entry the FRESH render found and the source does not record is drift, for
  every unit -- that asymmetry is how a genuinely new caller gets written down;
* the reverse (an entry only the SOURCE records) is still forgiven ONLY on a
  `dl:shared` unit, where another project may legitimately have written it. On
  an unmarked unit it is a stale entry, and is still drift;
* the RESIDUAL -- `Calls:`, `Complexity:`, everything that is not an inbound
  label -- keeps byte-compare semantics. Order-insensitivity was ruled for
  used-by; nothing about it makes a wrong `Calls:` line right.

A DUPLICATED inbound label falls back to the byte compare. `ParseBlock` keys its
map by LABEL, so a block carrying two `Called from:` elements collapses to ONE
entry set and the other silently leaves the comparison -- harmless under a
whole-block byte compare, a hole under a set compare. NOT hypothetical:
`run_doc_drift_unseen_units`' CONTROL-1 plants exactly that shape and went RED
on the first battery after the set compare landed, which is what that control
exists for. Falling back is this unit's documented direction ("if a block cannot
be parsed confidently ... the answer is the byte compare").

New guard `tests\autotest\run_doc_drift_order_insensitive.ps1`, RED-checked: on
the pre-change engine exactly ONE assertion fails (the reordering one) and all
FOUR controls still pass -- dropped entry, invented entry, duplicated label, and
a tampered non-inbound line -- so the widening is not the drift rule being
switched off.

**A PREDICTION THIS REFUTES.** The note carrying the 1229-edit autodoc backlog
recorded a guess that an unknown but possibly large share of those edits were
pure reorderings, so this fix might shrink the sweep substantially. Measured:

```
  pre-A1 engine          1229 edits / 91 files
  with A1                1243 edits / 92 files
  with A1 + this fix     1228 edits / 91 files
```

**One edit.** The fix is in the CHECKER; the 1229 comes from the WRITER, which
decides to propose an edit by byte-comparing its merged output. Making the
checker order-insensitive does not stop the writer re-emitting a list in a
different order, so the sweep is the same size it was and the writer's churn is
still unsolved. Recorded in the backlog note rather than left as a hope.

On this repo the change removes exactly one finding: 3874 -> 3873
(doc-drift 617 -> 616).

### A raised exception now documents its MESSAGE, not just its class

`TCompileChecker.SpawnAndCapture` documented itself as "Raises Exception" and
threw away the only useful half. The raise miner now keeps the message literal,
so the generated tag reads:

```
<exception cref="Exception">CreatePipe failed; CreateProcessW failed: %d</exception>
```

ALL the messages for a class, not the first. One `<exception cref>` is emitted
per class, but a routine routinely raises one class from several places --
SpawnAndCapture raises `Exception` twice. Taking the first would pick by source
order, and a reader seeing one message would reasonably conclude it was the only
one.

`TDocFactsBuilder.MineRaisesDetailed` is a SECOND miner, parallel to
`MineRaises` rather than a widening of it: `MineRaises` feeds Doc.Drift's
`ddExceptionNotRaised` as a deduped, case-insensitive SET of class names, and
changing that shape would change which findings that rule produces.

**The message needed its own ownership marker, and that is the whole story of
this change.** Ruling D-4 decides who owns an `<exception>` body by EMPTINESS:
marked-and-blank is the engine's (regenerate it, and delete it when the `raise`
goes away), marked-with-text is a human's (keep the words, drop the marker). The
moment the engine wrote a message into that body, its own output became
indistinguishable from a human's -- pass 2 took the preserve path, re-emitted the
tag without its marker, the file changed on every run, and a deleted `raise` no
longer deleted its tag. `run_doc_exception_cref` caught all three.

That is the same breakage `DESIGN-2026-08-10` records for typed `<param>`
bodies, with the same cause -- ownership INFERRED from content rather than
stated -- and it takes the same fix: a second explicit marker,
`AUTO_EXC = '<!-- drag-lint:auto exc -->'`, meaning engine-owned regardless of
what follows. **D-4 is untouched** and still governs a plain `AUTO_MARK` tag, so
a human's text inside one is as safe as it was. Like `AUTO_TYPE`, `AUTO_EXC` is
deliberately not a superstring of `AUTO_MARK`, which means every consumer must
search for it explicitly -- `RegionFullyEngineOwned` did not, and a comment whose
only content was a mined exception survived after its `raise` was deleted.

New guard `tests\autodoc\run_doc_exception_message.ps1`, RED-checked against the
pre-change engine. It pins the limits as well as the wins: a message on a later
line than the `raise` (the case the cross-line scan state exists for) IS
captured; a `raise` inside `{ }` or after `//` is NOT (this repo has fabricated
an `<exception cref>` from commented-out code before); and a concatenated or
`Format(...)` message captures the first literal verbatim, recorded as observed
behaviour so the day it changes the test says what changed.
`run_doc_exception_cref` gained an assertion that the message is carried, so it
now fails against an engine that silently stopped mining.

This repo's own report is unchanged at 3874 findings (22/1413/2431/8).

### C1b: the flow oracles now live on the store, and the flow checker is 36% faster

C1a (v1.10.0-alpha) memoised the three flow oracles that had no cache at all,
but every memo was a LOCAL of `TFlowChecker.Check` -- which runs once per FILE,
so each file re-paid every cold miss. C1b moves them onto the symbol store
(`ISymbolStore.FlowOracles`, a `TFlowOracleCache` created and freed with the
store and cleared where `FAnchorCache` is cleared), so a callee resolved once is
resolved for every file that calls it.

Measured on ORM3 (566 files, the attribution corpus -- a small corpus cannot
size a large one, and this repo understated the win by 3x):

```
FlowChecker.Check     35.89 s -> 22.99 s   (-35.9%,  63.4 -> 40.6 ms/file)
  oracle owns         17.58 s ->  8.27 s   misses 3968 -> 1327  (26.9% -> 9.0%)
  oracle param-mode    4.41 s ->  0.96 s   misses 7045 -> 2133  (10.3% -> 3.1%)
lint-all TOTAL       251.67 s -> 236.70 s  (-5.9%)
```

The three TYPE oracles (record-def, record-type, managed-type) did not move at
all, and that is by construction rather than a disappointment: their keys carry
a FILE ID, so there is nothing for a store-lifetime memo to share. They were
lifted anyway, because a file id means nothing except relative to the store that
issued it -- keeping them in a process-wide global would have let two stores
collide on the same integer.

`oracle owns` is the honest asterisk. Its misses fell 67% while its SECONDS fell
53%, and on this repo's smaller corpus they fell 41% for a 5% time saving: the
misses that C1b removes are the CHEAP repeats, and what remains are the ones
that force a fresh parse of the callee's declaring unit. The plan's headline
("46.88 s of a 71.54 s checker") was the size of the SLOT, not the size of the
prize.

### A self-check for the memo, and the defect it caught

`DRAGLINT_VERIFY_ORACLE=1` recomputes every cache HIT through the uncached path
and raises `EFlowOracleMismatch` on disagreement; `=break` corrupts the cached
answer first so the check is SEEN to fail. Both are documented in
`docs\AI-USAGE.md`, which now has an environment-variable section -- it had
none, so the sibling `DRAGLINT_VERIFY_GEN` had gone undocumented too.

**It earned itself on the first real run.** On DataCopy it raised three times on
key `copy#0`, cached `pmConst` against a fresh `pmUnknown`. The cause was in
this change: the param-mode key lower-cased the callee name, but the answer is
computed from `FindSymbolsByExactName`, which matches BYTE-EXACTLY first and
only falls back to a case-insensitive lookup when that finds nothing. So
`Copy(...)` and `copy(...)` resolve to different symbol sets -- and DataCopy
writes both spellings, 93 and 44 call sites. The key was LESS SPECIFIC than the
thing it cached. It is now case-sensitive, matching `owns`.

That defect was already latent at C1a's per-file scope; it needed both spellings
in ONE file to bite. What matters is how it was found: **the byte-identical A/B
passed on all three corpora WITH the bug present.** An A/B can only see entries
the linted files happened to exercise consistently, which is exactly why a
persisting memo needed a verifier and a per-file one did not.

The other four keys were audited against the same question and are sound: `owns`
was already case-sensitive over the same lookup, and the three type keys carry
raw type text where their computations trim or fold it, so those keys are MORE
specific than their answers.

### Gates

* Full battery **479 pass / 0 fail / 0 timeout of 479**, 30.7 min.
* The autodoc fix was RED-CHECKED against the unfixed build, and its guard
  carries a positive control asserting the engine still writes its facts in the
  same run -- without which an engine that documented NOTHING would have passed.
* Two guards that pinned the OLD `<summary>` behaviour as deliberate were
  reversed on an explicit owner ruling and re-pinned to the new rule, with the
  reasoning recorded in each. Neither was weakened.
* The 91-file documentation sweep over this repo's own `src\` was re-run and
  measured at **0 authored words lost**, down from 154 and then 54 in the two
  preceding attempts. The metric carries its own positive control.
* No extractor or resolver change: neither `DRAGLINT_EXTRACTOR_VERSION` nor
  `DRAGLINT_RESOLVER_VERSION` moves, and **no index re-parses are owed**. Both
  surface digests were re-baselined without a version bump, having been proven
  comment-only (253 and 633 doc lines changed, zero code lines).

* **Byte-identical** `lint-all` output, OLD vs NEW, on all three corpora
  (this repo, DataCopy, ORM3 -- 56,486 findings on ORM3).
* **Zero** `EFlowOracleMismatch` under `DRAGLINT_VERIFY_ORACLE=1` on all three,
  with the verified report byte-identical to the plain one (a raise makes
  `lint-all` SKIP the file, so a mismatch would show up as a shorter report even
  if nobody read stderr).
* `tests\autotest\run_flow_oracle_memo.ps1` -- new, and RED-CHECKED against the
  unfixed engine before being trusted: it fails there with misses scaling
  exactly 3x (2 -> 6 for both oracles, one caller unit to three) and with the
  `=break` fault going uncaught. Its fixture calls shared callees from three
  byte-identical caller units, so V2 measures cache LIFETIME rather than fixture
  size.
* This repo's own report is unchanged at **3874 findings (22/1413/2431/8)** --
  the new code adds none.
* No extractor change: `DRAGLINT_EXTRACTOR_VERSION` does not move and **no index
  re-parses**.

### Known issues

* A managed facts block can name users of a type that no longer exist;
  `doc-drift` reports it as `fixable` and the fix does not clear it. Affects
  classes/records/interfaces, not enums.
* A managed `<para>` can swallow the `<seealso>` tags below it and grow on each
  run. Seen once across this repo's `src\`; repaired here, engine fix pending.
* Repeated `document --apply --reindex` runs reorder inbound lists once before
  settling. Cosmetic -- membership and truncation are unaffected.

## v1.10.0-alpha -- 2026-09-06

**The release where a `.dfm` stopped being read as a complete document.** Delphi
does not stream a published property whose value equals its declared `default`,
so an ABSENT property is not an unknown -- most of the time it is a value that
can be read straight off the declaration. The converter had been treating absent
as unknown, which made it pessimistic about exactly the properties that are most
often at their default.

**No schema change, no extractor change.** Schema 21,
`DRAGLINT_EXTRACTOR_VERSION` `1.10.0-alpha` and `DRAGLINT_RESOLVER_VERSION`
`1.1.0-alpha` are all untouched: everything below is resolved at QUERY time, so
**no index re-parses** because of this release.

> Note for anyone reading the two version strings side by side: as of this
> release `DRAGLINT_VERSION` and `DRAGLINT_EXTRACTOR_VERSION` are BOTH the
> string `1.10.0-alpha`, and that is a coincidence, not a coupling. They are
> independent constants -- the extractor one moved on its own schedule and last
> changed in the 2026-08-30 extractor batch. Do not infer from the match that
> bumping one bumps the other.

### lint-all is 17% faster, and the flow checker 42%

`FlowChecker.Check` was 38.3% of a `lint-all` run. It is now **26.6%**.

Profiling the five flow ORACLES -- the store-backed predicates the dataflow
lattices ask about ownership, parameter modes and type categories -- found
**three of them with no cache at all**, at a 100% miss rate. `IsRecordType`
recomputed `ResolveTypeCategory` **46,236 times** in a single run of this repo's
own corpus. Memoising them within a file:

```
FlowChecker.Check   123.79 s -> 71.54 s   (-42.2%)
lint-all TOTAL      322.88 s -> 268.68 s  (-16.8%)
```

The largest single component was one nobody had predicted: the
`definite-assignment replay` phase fell **32.56 s -> 1.46 s**, having been
almost entirely oracle traffic rather than replay work.

**Findings are byte-identical.** The change was gated on a full `lint-all`
output comparison across the corpus -- same findings, same order, same summary
line. The memos are scoped to one file and cleared on entry to each file's
check, so no answer can cross a file or a database.

The profiling counters ship enabled and print under `DRAGLINT_PROFILE`; only the
printing is gated, so the measured code is the shipped code.

### A project index now tells you when it holds rows it cannot refresh

A project database can contain files that are not members of that project --
historically from pointing a folder scan at a project DB, which widened its
scope permanently. Two individually correct behaviours combined badly:
`index --project` walks the compile closure, so it never visits a non-member;
and eviction is deliberately bounded to the project's own roots, so a shared
database never has another project's rows silently deleted.

The result was a freshness warning that could never be cleared, on every run,
advising a command that could not possibly work. On this repo's own self-index
that was **81 of 199 rows**.

`index --project` now reports them, without deleting anything:

```
scope: 81 indexed file(s) are outside this project's compile closure
(NOT evicted -- they lie outside every eviction root; pass --rebuild to drop them):
```

and the freshness note is honest about its own limits, naming `--rebuild` as the
only remedy that applies to those rows. Nothing is deleted: dropping them
changes what `lint-all` reports on, which is the operator's decision, and
`--rebuild` remains the way to make it.

### Guard and tooling fixes

* **`--help` verbs are now held against `README.md` and `docs\AI-USAGE.md`.**
  The docs-in-sync rule always named all three surfaces, but nothing checked the
  two prose ones against the verb list -- which is how `--castlib` came to be
  documented in `--help` and neither doc. Two verbs (`migrate-dbs`,
  `shared-unit`) were missing from AI-USAGE and are now documented.
* A test that asserts the ORDER of two output streams was reading them through
  two OS pipes merged in drain order, which reordered about 10% of the time.
  It now captures through a single handle.

### A .dfm is SPARSE

`#default` is a real fallback again. A source property that is absent because it
sits at its declared default now RESOLVES, and the resolved value is emitted
explicitly rather than silently dropped. Two new report kinds carry it:
`default-superseded` and `default-resolved`.

> **Renamed after this release.** `default-superseded` became
> **`default-rule-superseded`** on 2026-09-08, at the converter team's request:
> "default" meant our `#default` RULE DIRECTIVE in this one kind and the Delphi
> `default` CLAUSE in the three beside it. A consumer pinned to the old spelling
> sees the kind vanish rather than change. Nothing had built against it yet,
> which is why it was taken immediately.

`#when` now matches a resolved default exactly as it matches a streamed value,
so a mapping over an enum finally fires on that enum's own default.
**`mapping-source-absent` is correspondingly NARROWED** to the only case where
nothing can honestly be said: absent, and no clause to resolve it to.

**`#else` fires when the source value RESOLVED -- present, or absent and carried
from its declared `default` -- and no `#when` arm matched.** It stays gated OFF
in the one case where nothing can be resolved (absent AND no usable default),
because firing it there would invent a target value out of nothing.

D2 therefore makes `#else` fire in strictly MORE cases than before, not fewer:
an absent leaf with a `default` clause now resolves and can reach it, where
previously it went straight to `mapping-source-absent`.

> **CORRECTED 2026-09-08. The two paragraphs above previously said the exact
> reverse** -- that `#else` "now fires only when the source is absent AND has no
> usable default", and that a `#when` catching an enum's default by way of
> `#else` "will stop firing". Both were wrong, and the second described a
> behaviour that never existed: before D2 an absent leaf did not reach `#else`
> either. The CODE and the tests were right throughout
> (`DfmReemit.pas` `EvaluateMapping` exits before the `#else` check when
> `ResolveLeafValue` fails; `run_dfm_reemit.ps1:392` pins it). The converter
> team caught it while relabelling their `#else` UI to match this text, which
> would have put the false statement in front of users.

`stored` is honoured. `Vcl.Controls.pas` declares
`Color ... stored IsColorStored default clWindow`; with `ParentColor` set,
`Color` is omitted regardless of value, so resolving it to the declared default
would write a wrong value AND clear the inheritance.

### Enum casts EXECUTE, and `.castlib` has a grammar

A `#link` carrying a `: Cast` suffix now translates its value through the
`.castlib`'s `enum` blocks instead of copying it verbatim. The `.castlib` parser
moved into the engine so it can read one, and a new `--castlib <file>` flag on
`convert-apply` and `convert-reemit` names it. **Without `--castlib`, a
cast-bearing `#link` passes the value through UNCHANGED.** A value with no `map`
and no `else` reports the new `enum-cast-unmapped` kind.

### `--castlib` is now in README and AI-USAGE, where it was missing

The flag shipped in `--help` but appeared in neither `README.md` nor
`docs/AI-USAGE.md`, so a reader of either could not discover that a cast-bearing
`#link` silently passes its value through without it. Both now document it.

> `convert-reemit` remains deliberately undocumented, and this release does NOT
> change that. It is classified as an internal stage of the conversion pipeline
> in `run_docs_sync_guard.ps1`'s `$UndocumentedOnPurpose` list. That guard is
> two-directional and refused an attempt to document it during this release --
> correctly. **Open question for the owner**, not decided here: session 69 gave
> `convert-reemit` a user-facing `--castlib` flag and the converter team may now
> want to run it directly to debug a rule. If so, it should be promoted to the
> public surface and the exemption dropped; until someone decides that, it stays
> internal.

### Fixes

* Four ways default-resolution wrote WRONG values into a form, two of them
  reproduced by running the engine at exit 0: owned-part recursion resolved a
  child `#link` against the PARENT's defaults, set defaults were truncated into
  malformed DFM, and `#remove` was not honoured.
* `overwrite-before-read` now counts a read inside a NESTED routine.
* `run_index_all_jobs_spawns_workers` asserted a coin flip: it sampled the
  process table on a run lasting 235-780 ms, while one sample costs about as
  much, so it got exactly one poll. It now asserts the parallel path's own
  summary line, which is deterministic.
## v1.9.0-alpha -- 2026-08-31

**The release where three checks stopped asking for things the caller could not
do.** Every change below came from a downstream project that MEASURED rather
than asserted, and the version number moved specifically so those reports stay
unambiguous: v1.8.0-alpha was never tagged, but it had already been quoted in
bug reports, and reusing the string for a materially different binary would make
"which build were you on?" unanswerable.

**No schema change, no extractor change.** `SCHEMA_VERSION` 21 and
`DRAGLINT_EXTRACTOR_VERSION` 1.9.0-alpha are both untouched, so **no index
re-parses** because of this release.

### An absent resolver stamp is stale

A grandfather clause treated a database with no `resolver_fingerprint` as
current, on the reasoning that "protection begins at the next resolve". There is
no next resolve -- the run writes the stamp on its way out, so every later run
matches. It did not defer protection, it cancelled it for every index predating
the stamp.

Measured: `index --all` across 31 project sections printed
`resolve: calls skipped` **25 times**, ran the calls pass **0 times**, and
stamped all 31 as current. Forcing the pass afterwards on one of them took
`refs.symbol_id` from **4,522 to 28,011**.

**The miss was self-concealing, so upgrading is not enough.** Once the stamp is
written no build can tell the pass never ran. Any index touched by v1.8.0-alpha
must be repaired with **`index --all --resolve-only`** -- which is also fixed
here, because `--all` accepted the flag and silently dropped it.

### Rules that could not be satisfied

* **`unsafe-shellexecute` on `CreateProcess` was unsatisfiable.** It tested only
  whether `lpCommandLine` was a literal and never looked at
  `lpApplicationName`, while advising "use a fixed literal" at severity ERROR --
  advice unavailable to any caller passing a path. The rule now turns on whether
  a **shell** interprets the line: a non-nil `lpApplicationName` is ordinary
  argument passing and is silent; a nil one still reports, and names the
  interpreter when there is one. Real injection still fires, with an achievable
  remedy in the message.
* **`method-pascalcase` flooded xUnit suites** -- 330 findings on one test
  project, 71% of its report. `Subject_does_the_thing` is not a style lapse when
  the runner prints the method name. Now exempt on DUnitX-attributed methods
  (`Test`, `TestCase`, `Setup`, `TearDown`, ...), scoped by the **attribute**
  rather than by the project so casing lapses in test *helpers* are still
  reported.
* **`unused-unit-in-uses` is `info`, not `warning`** -- interim. The reporting
  project commented out 23 candidates and compiled: 20 safe, **1 broke the
  compile** (`TStringHelper` methods are declared in `System.SysUtils` and the
  unit named no other symbol from it), **2 built clean and were unsafe at
  runtime** (EurekaLog units working through `initialization`; removing the
  call-stack provider yields crash reports with empty stacks). Wrong ~13% of the
  time toward breaking the product is not a warning. Downgraded rather than
  suppressed -- the 20 true positives are real -- and the message now names all
  three blind spots. It returns to `warning` once type-helper calls resolve to
  their declaring unit and a DFM-instantiated class counts as a use of the unit
  that registers it.

Together these took that project's test-suite report from **463 findings to
133**.

### Known, and deliberately not changed here

* `hardcoded-absolute-path` still fires on fixture literals that nothing opens
  (73 findings). The fix is dataflow to a filesystem operand, not a test-project
  exemption.
* A `dl:ok` marker on a **wrapped** statement lands one line below the finding,
  so the site reports twice and the marker is called dead. Accepted; it belongs
  in the marker matcher, where it fixes every rule at once.
* **Flow analysis has no CFG edge from a statement to its enclosing `except`**,
  so an initialiser read only by the handler looks like a dead store. Acting on
  that advice introduces a crash, because Delphi does not zero locals. A
  severity downgrade was proposed and declined: the rule is correct in shape, so
  demoting it would hide true positives in exactly the code where a dead store
  is most likely to be real. The missing edge is the fix.

## v1.8.0-alpha -- 2026-08-31

**The release where the linter learned to ask what a dependency actually is.**
142 commits since v1.7.0-alpha. Five new rules, and not one of them is about
style: they ask which unit really depends on which, and why. Underneath them the
extractor stopped losing whole classes of reference that the compiler resolves
without difficulty -- a gap that had let a "safe to delete" check clear a const
the build needed.

**No schema change.** `SCHEMA_VERSION` is 21 before and after.
**178 rules across 16 categories**, 23 auto-fixable.

> ### ONE FULL RE-PARSE IS OWED.
> `DRAGLINT_EXTRACTOR_VERSION` moved **1.6.0-alpha -> 1.9.0-alpha** over three
> bumps in this window, so every index re-parses once on its first run under this
> build. The charge is for real extraction changes -- references that were being
> dropped -- and not for the version number; the split introduced in v1.7.0 is
> what keeps that difference legible. `tools\reindex-all.ps1` runs the libraries
> and the project sections in parallel, and per-file resume means an interrupted
> walk continues rather than restarting.

> ### AND ONE RE-RESOLVE, WHICH IS NOT THE SAME CHARGE.
> `DRAGLINT_RESOLVER_VERSION` is new in this release and stands at
> **1.1.0-alpha**, so an index stamped `r=1.0.0-alpha` re-derives its edges once.
> That costs **minutes**, not hours, and it happens automatically on the next
> `index` run -- or on demand with `index <dir> --db <db> --resolve-only`. The
> whole point of the second stamp is that this is no longer priced as a re-parse.

### Extraction: references the index was silently dropping

Each of these is a reference the compiler resolves and the index did not hold,
which means `find-callers` and every delete-safety query answered "nobody uses
this" about a name that was load-bearing. They were found by four different
routes, and one of them was a broken build.

* **A const in a TYPE position emitted no ref.** `TArr = array [1..CBound] of
  Integer`, `F: array [0..CBound] of Byte`, `TStr = string[CLen]`,
  `TSub = 0..CHigh` -- all silent. The filed note called it "array bounds"; the
  measurement widened it before any code was written, because case labels and
  const initialisers look like the same family and are fine. It surfaced when an
  owner-ruled const deletion was pre-checked against `refs`, came back SAFE, and
  broke the ORM3 build with E2003 plus two cascades.
* **`with A, B do` emitted `A` only.** Slots 2..n of a multi-entity `with` were
  dropped entirely.
* **The library expression of an `external` directive** emitted nothing.
* **Array ELEMENT types** in a type declaration or a global var
  (`TArrT = array [0..3] of TPayload`) emitted no type use, though the same
  declaration as a record or class field did.

Measured across three corpora, the batch adds 0.05-0.07% more refs and removes
none -- 361 new rows on ORM3 CLIENT, 116 on SERVER, 107 on the self-index.

### Resolution: edges that existed but bound to nothing

* **Helper-method calls now resolve.** 887 of 1,118 helper-member call refs bind
  to a real target, up from **zero**. A record or class helper's methods were
  invisible to the call graph.
* **An ENUM-typed receiver can now be typed**, which is what makes enum helpers
  resolve at all.
* **A call through a plain type alias** (`TFoo = TBar`) now resolves to a real
  edge instead of stopping at the alias.
* **The lint walk resolves conditionals** the way the index side always did, so
  the two no longer disagree about which branches exist.

### New rules: coupling, not style

| rule | question it asks |
|---|---|
| `global-only-uses-edge` | is an interface-section global the ONLY reason A depends on B? Then relocating it deletes the uses edge. |
| `uses-global-census` | how HEAVY is a uses edge -- how many of B's globals does A actually touch, out of how many B declares? Deliberately not the same question as the one above. |
| `duplicate-global-decl` | the same name declared at interface level in two units -- const, var, type, record, class, interface, enum or routine -- so which one compiles depends on uses order. |
| `with-hides-outer-symbol` | a `with` block silently shadowing an outer name. Found ORM3 `Assign` methods that copy nothing. |
| `stat-gated-destructive` | requested by DataCopy: a destructive act gated on a stat that can go stale between the check and the act. |

`global-only-uses-edge` names the cure precisely rather than always saying
"inject": only an INTERFACE-typed global earns that word, because a Boolean
cannot be registered in a container. Its design-time DFM demotion is a blessing,
so it now requires positive evidence -- a form binding to a datamodule's style or
image list is legitimate; binding to its query or event handler is the finding.

**`duplicate-global-decl` now covers every kind `uses` can put into scope**, not
just `const` and `var`. Its own message -- *which one compiles depends on uses
order* -- is exactly as true of a type, and the report that prompted this was
about importing a global TYPE that already existed elsewhere. Measured on ORM3
before widening: the rule saw 10 of 28 duplicated interface names on CLIENT and
10 of 26 on SERVER. It immediately found `TARecTDistr` declared as
`array [1..500]` in one unit and `array [1..100]` in another, and `Bool` as
`Bytebool` against `Longbool` in a vendored library.

Two guards came with it. `Register` is excluded by name -- it is Delphi's
design-time registration protocol, declared in 134 ORM3 units, and the finding
listed all 134 paths in one message. And the site enumeration is now capped at
six with an "and N more" tail: a report line nobody can read is the same defect
as a rule that floods, it just arrives as one row instead of many.

**`uses-global-census` now states the RATIO, and skips forms.** It said how many
globals a reader draws; it now also says how many the used unit declares, plus
its DFM object count. Neither number alone answers "consolidate, inject, or
leave it": 7 of 9 is a unit that travels with you, 7 of 206 is one you are
dragging in for almost nothing.

A used unit that has a `.dfm` is now skipped **unless its root object descends
from `TDataModule`**. A form opened from a button cannot be injected without
fighting RAD -- the designer and the DFM both assume the concrete class -- so
reporting it is advice nobody can act on; a datamodule usually can be resolved
through a container. That needed an ancestry climb rather than a name test: the
DFM root's stored signature is its own class, and 0 of 61 roots on ORM3 CLIENT
contain "datamodule". Measured before shipping -- 61 roots, exactly 2
datamodules, and `uStyles` is one, so the canonical 26-edge case survives while
~43 plain-form edges go quiet (161 -> 118 on CLIENT).

The acknowledgement is now `// dl:unit <unit> accepted`, which reads better in a
uses clause; `// dl:census-ok <unit>` keeps working, because an acknowledgement
someone has already written must not stop working when the wording improves.

### `exceptions-sync`: bare raises become named classes

`raise Exception.Create('...')` gives every failure in a codebase the same type,
so no caller can catch one without catching all of them. This release turns that
into a two-part workflow, and the split is the design rather than an accident of
where the code sat.

```
exceptions-sync --db <db> [--config <cfg>] [--apply] [--json]   -- dry run by default
lint <f> --db <db> --fix --fix-rule raise-bare-exception [--apply]
```

* **The unit WRITER is a verb**, because its input is the project-wide harvested
  message set and its output is one file -- neither of which is a per-finding
  fix-it.
* **The call-site rewrite is a fix-it** and stays on `lint --fix`, so it remains
  reachable as an IDE code action. `raise-bare-exception` joins the auto-fixable
  set, 22 -> 23.

**The persisted map is the unit itself.** Each generated declaration carries its
raw message in a same-line `//` comment, and the normalised form of that comment
is the key -- so a human can rename a mediocre generated class and keep its
binding. A `//` comment and never a brace one: a message containing `}` would
end a brace comment, and writing this unit's own header tripped exactly that
trap.

Two defects were found by running `--apply` twice against ORM3, and neither was
reachable from a fixture:

* **A message ending in a space could not survive its own read-back.** The
  comment is written verbatim and read back with `Trim()`, and 11 of ORM3's 78
  real messages end in a space -- so the second run rewrote the unit while
  correctly reporting `0 class(es) added`. Every message in the fixture was tidy.
  Now canonicalised at write time.
* **A configured ancestor declared in ANOTHER unit never reached the `uses`
  clause**, so the generated unit did not compile.

`--json` emits one document on stdout with the prose on stderr, so the verb is
scriptable without parsing English.

### Staleness that could not be detected

`DRAGLINT_EXTRACTOR_VERSION` answers *"would this build PARSE bytes
differently?"* and a bump costs a ~5 hour re-parse. The resolve pass asks
*"would this build DERIVE different edges from parses it already holds?"* and its
remedy is minutes. One stamp cannot answer both, and measured against real
history it got both wrong **in opposite directions**: 19 resolve-only commits
each demanded a full re-parse, while 42 resolve-write commits -- one every 2.2
days -- moved nothing and left every index silently stale.

* **`DRAGLINT_RESOLVER_VERSION`**, scoped by FUNCTION rather than by directory,
  because no line through the tree separates the two questions. The manifest is
  derived from what each routine WRITES, then closed over the callees the autodoc
  facts already record -- not from a name regex. Eleven exclusions each carry a
  reason.
* **`schema_meta.resolver_fingerprint`**, written beside `indexer_fingerprint`
  so it rides the same guarantee: only a run whose resolve completed stamps it.
  A mismatch JOINS the terms that force a re-resolve rather than replacing any of
  them -- it is the one that fires when nothing on disk changed but the code
  deriving edges did.
* **`index --resolve-only`** -- re-derive every edge without walking a single
  file. Both halves matter and either alone would pass for the wrong reason: it
  must not walk (or it is `index` wearing a flag), and it must still resolve
  (with the walk skipped, every other term in the resolve gate is false).
  **`index --all` honours it too** -- it accepted the flag and silently dropped
  it, which mattered because `--all` is the only command that reaches every
  section.

**An ABSENT stamp is stale, and getting that wrong cancelled the whole
feature.** Both staleness checks were written as `(PrevRfp <> '') and (PrevRfp
<> CurRfp)`, grandfathering a database with no stored value on the reasoning
that *"protection begins at the next resolve"*. There is no next resolve: the
run adopts the current stamp on its way out, so every later run matches. The
clause did not defer protection, it **cancelled** it for every index that
existed before the stamp shipped -- which, in this release, is all of them.

Measured before the fix: `index --all` over 31 project sections printed
`resolve: calls skipped` **25 times**, ran the calls pass **0 times**, printed
`Resolver changed` **0 times**, and stamped all 31 as current. Forcing the pass
afterwards on one of them took `refs.symbol_id` from **4,522 to 28,011** -- 84%
of the resolved rows had been missing from a database reporting itself freshly
resolved.

The miss was also **self-concealing**, which is what made it expensive rather
than merely wrong: once the stamp is written, no later build -- including a
fixed one -- can tell the pass never ran, because the only signal it has now
agrees. Recovering an index stamped by an affected build therefore needs
`index --all --resolve-only`, not an upgrade.

The old comment justified the grandfather clause as being "like the indexer
fingerprint". That analogy does not carry: the indexer has per-file mtime/sha as
an INDEPENDENT staleness signal, so grandfathering its fingerprint blinds
nothing, while the resolver stamp is the only signal there is.
`run_resolver_stamp_absent_is_stale.ps1` pins four cases, and the third is not
optional -- a matching stamp on an unchanged corpus must still SKIP, or the fix
degenerates into "always re-resolve" and the 2,252s-to-17s saving is gone.

This is not theoretical. On 2026-08-30 a sequence re-ran all 31 project sections
specifically to pick up a resolve fix, and the calls pass executed in **three of
them** -- incremental scope is decided by changed FILES, and a changed resolver
is not a changed file.

### `refs.symbol_id` is populated

`refs.symbol_id` was NULL on **every row of every index** -- 0 of 543,482 on ORM3
CLIENT, across all eight ref kinds -- while `INDEX-SCHEMA.md` documented
`refs.symbol_id -> symbols.id` as a working join. Every consumer was name-joining
whether it meant to or not, and a name join cannot separate two same-named
symbols. It is also why `GetReferencedSymbolIds` returned nothing, leaving the ID
half of `unused-public-symbol` and `unused-private-member` as dead code nobody
had noticed. The documented join now matches 7,593 rows on this repo's index,
against 0 before.

Two limits, both deliberate and both stated in the schema doc so the column is
not over-trusted: **only `certain` edges** (writing one of several plausible
targets would launder a guess into a fact), and **only `call` and
`member-access` refs** -- `read`/`write`/`type_use` remain 0, because the
resolver knows a call's target only because it is already computing it. A NULL
still means "not resolved", never "no such symbol".

### Performance

* **Definite-assignment gen-set memoised** -- `lint-all` 223.5 s -> 182.2 s.
* **A `.scm` query is skipped when the file cannot contain what it matches** --
  33% off the query-rule pass.
* **A run that only ADDS type names scopes the call-resolve** instead of
  rewalking the whole database -- 4.2x on the measured corpus -- and a prune or
  eviction no longer throws that scoping away.
* **Code-lens caller counts run over the warm LSP**: 137 process spawns become
  none.

Two of these exist because per-solve counters replaced an aggregate ratio that
was hiding the decision. The remaining target is now a single function.

### CLI

* `--library-db`, so the cross-store ancestry bridge is testable at all.
* `--stand-in-for`, and the IDE finally passes a `--db`.
* `query --name-like`, substring search over symbol names.
* `query type-usage` -- which of these type names does this file reference?
* `schema --format json` now carries what a column MEANS, not just its type.
* `index --all` rolls up its failed sections by name instead of burying them.
* `lint-all` gained a cycles SECTION that states the outcome, including the
  negative one.
* The deprecated `scan-all` verb is retired.
* `<verb> --help` FATALed on every verb, and `-h` was worse. Both fixed.
* `serve` warns when more than one `--db` is given, and names the ones ignored.
* `-Jobs N` on the battery driver, default 1, with a serial quarantine.

### The IDE plugin and LSP

* **Per-severity icons in the editor gutter**, drawn rather than rasterised, and
  on the Diagnostics rows in place of the `[E] ` text tag.
* **The engine is released so it can be rebuilt with the IDE open** -- previously
  a running IDE blocked every build.
* **`draglint/usages` answers Find Usages without a process spawn.**
* **`lsp --proxy --trace <file>`** records a live LSP session without altering
  it. Phase 1a of the merge-proxy plan, and a prerequisite rather than a nicety:
  Phase 1b registers the relay as the IDE's Pascal language server, the step
  where a drag-lint bug stops costing drag-lint features and starts costing all
  of Code Insight. The assertion that matters is not that the trace captures
  things -- it is that it changes nothing, so the guard feeds identical input
  through the proxy with and without `--trace` and requires the relayed bytes to
  be byte-identical.
* The VS Code client runs a private engine copy, so it too stops blocking builds.
* A hover in an unindexed file no longer answers from the LIBRARY index.
* The Options page rewrote `drag-lint.json` minified and with a BOM. Fixed.

### Fixes worth naming

* **`unused-unit-in-uses` reported ZERO everywhere** -- both layers were wrong.
* **A generic export needs stripping on BOTH sides** -- 19 false positives.
* **`unsafe-shellexecute` cried CWE-78 at Explorer and missed real injection.**
  A plain `ShellExecute` open is now silent, by owner ruling.
* **Config discovery is anchored to the FILE and to the `--db` path**, not to
  whatever the current directory happened to be.
* **`absolute` aliasing is modelled** as one storage cell and one slot.
* **`too-many-exit-points` counted `Exit(Value)` twice.**
* **A `.dpr` walk needs the `.dproj` search paths**, or reconcile reports false
  EXTRA units.
* **A build can no longer kill a running reindex** -- it once cost a five-hour
  job.
* **A directory walk no longer writes to -- or reports on -- files no project
  compiles.** Pointing `lint` at a folder linted everything in it, including
  units belonging to other projects; with `--fix --apply` it EDITED them. Owner
  ruling, verbatim: *"they are completely unrelated and might belong to some
  other project and reading or modifying those might break something else."*
  The first attempt at this filter was a no-op that looked installed -- it read
  the argument that `check-unit` and `ghost-check` use, while `lint` takes its
  path from a different one -- and was caught by checking which files actually
  received edits, not by the absence of a skip message.
* **`lint --fix` cached source lines per FINDING rather than per FILE**, so a
  file with many findings was re-read once per finding.

### Documentation and guards

* The backlog was consolidated from four disagreeing places into one enumerated
  index with machine-readable statuses, guarded against drift.
* `index` warns when the index no longer describes the source on disk.
* The intermittent FK violation on incremental reindex now names the failing
  edge when it fires.
* **The docs-sync guard could not see a claim that WRAPS.** `README.md` carried
  "152 enabled by default" against a live 154, with the number and the phrase on
  different lines, so the per-line scan never saw it -- a probe breaking the
  figure to 999 stayed GREEN. Each doc is now scanned whole (newlines folded to
  spaces, offsets preserved so line numbers survive), every pattern self-tests
  that it matches at least one live claim, and coverage widened from 17 claims to
  32 -- every count `rules --json` can answer, including per-category totals and
  the built-in/external split.

## v1.7.0-alpha -- 2026-08-23

**The release where the IDE became the product surface.** v1.5.0-alpha and
v1.6.0-alpha were bumped in code but never described here, so this entry covers
everything since v1.4.0-alpha -- 32 commits. The centre of gravity moved from the
CLI to the live IDE: a warm LSP behind the plugin, a hover popup and a completion
popup that theme themselves, and a relay that lets Code Insight and drag-lint
coexist.

**No schema change.** `SCHEMA_VERSION` is 21 before and after.
**173 rules across 16 categories**, 22 auto-fixable, 149 on by default.

> ### THE v1.4.0 RE-PARSE WARNING NO LONGER APPLIES -- read this instead.
> v1.4.0-alpha warned that "a release bump invalidates every stored parse whether
> or not extraction changed". That was true then and is **not** true now:
> `DRAGLINT_EXTRACTOR_VERSION` was split out of the indexer fingerprint, and this
> release is the proof -- the product version moved 1.6.0 -> 1.7.0 and the
> extraction surface hash did not change, so **v1.7.0 by itself costs nothing**.
>
> **One re-parse IS owed, for a different reason.**
> `DRAGLINT_EXTRACTOR_VERSION` moved 1.4.0-alpha -> 1.6.0-alpha because consts
> now carry a type and a value, which is a genuine change to what is extracted.
> Every index re-parses once on its first run under this build. That is the cost
> the split exists to make *legible*: it is charged for the const work, not for
> the version number. `tools\reindex-all.ps1` runs the libraries and the project
> sections in parallel, and per-file resume means an interrupted walk continues
> rather than restarting.

### Indexing and extraction

* **A const now carries its type AND its value.** `signature` was empty for every
  const in every index, so the completion popup and the hover described
  `const MaxItems` with no hint of what it is or holds. The format was chosen by
  measuring 801 consts across three real corpora: 24% declare a type, 66% are a
  bare literal whose type follows from the literal, and 10% are an expression
  that cannot be typed without evaluating it. Type alone would have left that
  last 10% blank -- the defect being fixed -- so both are carried, and an
  expression is never folded to a value (`VERSION = DRAGLINT_VERSION` stays
  untyped rather than asserting something the source does not say).
* **A class, record, interface or enum describes itself in the popup** -- its
  ancestors, or its first members for an enum. Done in the LSP rather than the
  extractor, because `heritage` has been indexed since v11 and enum members are
  already child symbols: writing them into `signature` would have charged a
  second full re-parse to restate what the index already knew. Nothing is
  invented -- a bare `TBase = class` declares no ancestor and stays blank.
* **The extraction identity is separate from the product version.** Previously
  the indexer fingerprint embedded `DRAGLINT_VERSION`, so every release re-parsed
  every database whether or not the parser had changed -- hours of machine time
  bought for nothing, recurring on every bump. `DRAGLINT_EXTRACTOR_VERSION` now
  carries that identity alone, guarded by
  `tests\autotest\run_extractor_version_guard.ps1`, which fails when extractor
  sources move without it.
* **A constructor inside a class is a constructor, not a method.** Every class
  member was extracted as `skMethod`, so a constructor hovered and completed as
  `method`.
* **Member lookups stopped being answered from the wrong GUI framework.**
  `TPath.GetDirectoryName` resolved into FMX in a VCL project. Resolution now
  ranks the file's own unit first, its used units second, and a flat lookup last.
* **`resolve-dbs --in` resolves by index membership**, not by the project file's
  folder -- a project whose `.dproj` sits in a subdirectory of the code it owns
  was resolved to the wrong database.

### The IDE plugin

* **An About/status window, a diagnose report, and a restructured menu.**
* **Continuous LSP status** in place of a modal that asserted a failure.
* **The hover and completion popups follow the IDE theme.** The IDE themes itself
  through `IOTAIDEThemingServices`, not the process-global VCL `TStyleManager`,
  so a bare `clWindow` stayed white while the IDE was visibly dark.
* **Completion rows read as Delphi.** The kind is spelled out, parameters stay
  attached to the name, and the declared type follows a colon -- `function
  Split(const S: string; ASep: Char): TArray<string>`, not `f Split - ...`. A
  symbol with no signature contributes nothing rather than its own qualified
  name.
* **Gutter marks appear on file open**, including the first run before the LSP is
  up, and the refresh-findings spawn storm on every idle tick is gone.
* **The library index is resolved from the manifest**, and a failed resolve says
  why instead of failing silently.

### LSP

* **`drag-lint lsp --proxy` -- a relay in front of DelphiLSP**, so Code Insight
  and drag-lint can both answer. `drag-lint-switch` is the rollback lever.
* **Cursor positions read the client's live buffer, not the disk.** An index
  being fresh is not the same as the CURSOR being fresh: a position names a spot
  in the editor's buffer, so a `didChange` the server ignored made every request
  during typing silently answer about stale text.
* **The whole hover popup is served over the warm LSP**, instead of spawning the
  engine twice per hover against a multi-gigabyte library index.
* **The completion endpoint is served**, rather than accepted and dropped.

### Documentation and guards

* **A per-feature wiki (125 pages)**, a rewritten README CLI/MCP reference, and
  the whole manual generated as a single Word + PDF with a freshness guard.
* **A docs-sync guard that fails the battery on drift.** It was written after one
  afternoon found four shipping verbs missing from `--help`, the entire autofix
  flag set undocumented, and README claiming "130+ rules" against a real 173.
* **The CLI surface that was hidden is now documented**, along with four defects
  found while documenting it.
* The battery is **347 runners**.

### Fixes

* `pchar-arithmetic` no longer fires on ALL-CAPS constants.
* `generate-test` no longer treats a unit-name segment as the enclosing class.
* The MCP server answers each list method with its own key, and no longer reports
  itself as v0.31.

### Housekeeping

* The kill-on-close job object moved out of the plugin into core.
* 2.2 GB of dead build artifacts and the tracked manual were dropped from the
  repository.

## v1.4.0-alpha -- 2026-08-17

A performance and correctness release. **`lint-all` on a 566-file project goes
572 s -> 277 s across v1.3.0 and this release, with the report byte-identical at
every step.**

**No schema change.** `SCHEMA_VERSION` is 21 before and after.

> ### ONE-TIME COST: every index re-parses once on its first run under v1.4.0.
> The indexer fingerprint embeds the product version, so a release bump
> invalidates every stored parse whether or not extraction changed -- and this
> release did **not** change what the parser extracts. For the ~7,000-file
> library index that is a long walk. Two things make it survivable: **per-file
> resume** (an interrupted walk continues instead of restarting) and the new
> **whole-database announce** (a long pass now says so, instead of looking
> hung). The underlying design issue is filed as
> `docs/INBOX-extraction-fingerprint-uses-the-product-version.md`.

### Performance

* **`seealso` doc-source: 18.57 s -> 2.29 s.** Memoised on the PARENT symbol id,
  caching the filtered routine list rather than every child row. 913,357 sibling
  rows materialised -> 17,559.
* **`class-metrics`: 58.04 s -> 19.24 s.** `ResolveTypeCategory` was 40.99 s over
  266,715 calls with only 7,568 distinct `(name, file)` keys; memoised per call,
  local to the run because file ids are per-database.

### Correctness

* **`lint-all` output is now stable across a reindex.** `class-metrics` emitted
  in `TDictionary` order keyed by symbol id, so reindexing the same sources moved
  61 findings -- same count, same byte total, different file. Now sorted on
  source coordinates. This mattered because byte-identity of `lint-all` is the
  project's own verification gate, and it was silently valid only within one
  index state.
* **The two index entry points now agree about a database's fingerprint.**
  `index --all --only <Section>` recorded `plat=` while `index <dir> --db`
  recorded `plat=win64`, so alternating them re-parsed every file for no engine
  change -- and silently disabled per-file resume on the manifest path, which is
  the path the long library walk uses. Both now record the effective preprocess
  platform.

### Diagnostics

* **The call-target resolve announces WHOLE-DB and its REASON before it runs**,
  not after. A documented ~37-minute pass previously printed nothing until it
  finished, which is how a healthy run was once killed at 8 minutes and filed as
  a hang. The reason is recorded at the latch, so it names the actual condition.
* **`lint-all --profile` attribution** for the per-file scan (per check, with file
  counts), `class-metrics`, and the `seealso` block.

### Tooling

* `tools/perf/scoped-resolve-ab.ps1` -- A/B equivalence harness for the scoped
  call-target resolve. Baseline: scoped 46.7 s vs whole-database 195.5 s with
  identical `call_edges` digests.
* `tools/lsp-diag/bpl-inventory.ps1` -- design-time package inventory (registry +
  on-disk sizes), the headless half of the IDE RAM audit.

### Notes for maintainers

Two long-standing performance suspects were **measured and refuted**: the
quadratic `Findings := Findings + X` accumulation costs **0.00 s**, and the
`.scm` double parse is real but worth **1.38 s of 271 s**. Neither should be
revived. What remains is `.scm` rule execution at 54 s -- time individual rules
before changing anything.

## v1.3.0-alpha -- 2026-08-12

A feature release, not a patch: it changes **where every index lives** and **what
`lint-all` reports**, and it makes `lint-all` finish on a project where it
previously could not.

**No schema change.** `SCHEMA_VERSION` is 21 before and after. Existing databases
were relocated by `migrate-dbs`, verified row-for-row, and needed no reindex --
what moved is where a database lives, not what is inside it.

### `lint-all` completes on a large project (2026-08-12)

- **ORM3-Micronite2027 went from 8,705 CPU-seconds unfinished to 732 s**, with
  byte-identical findings (the same 19,024). Three project rules each asked the
  store per *occurrence* what could be asked once per run:
  `unused-private-member` (447.8 s -> 0.01 s) and `unused-public-symbol`
  (59.0 s -> 0.36 s) ran two row-materialising queries per symbol just to compare
  a length with zero -- the second a full scan of `refs`, which has no
  `name_text` index -- and `unused-unit-in-uses` ran one query per *reference*.
  The first two now read two DISTINCT scans into sets once per run (new store
  methods `GetReferencedSymbolIds` / `GetReferencedNamesLower`); the third
  memoises name -> unit stems.
- **`DRAGLINT_PROFILE=1` now profiles `lint-all`**, per phase and per project
  rule, on stderr. Phases are announced when they open and costed when they
  close, so a run that never terminates still names the phase it died in.
- Known remainder, measured and filed: `doc-drift` is now the dominant phase
  (454.9 s of ORM3's 732.3 s). It was invisible behind the above.

### Project DB home (`_D-RAG`), and `lint-all` scoped to the project's own code (2026-08-11)

- **Every project's index moved out of the shared `.drag-lint` folder into a
  hidden `_D-RAG` folder beside its own project file.** Two days after the
  2026-08-09 move to `C:\Projects\.drag-lint\<Repo>-<Project>.sqlite`, each
  project DB moved again, this time to `<project folder>\_D-RAG\<project file
  base name>.sqlite` (e.g. `C:\Projects\YADF\_D-RAG\YADF.sqlite`,
  `C:\Projects\DB\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite`). All 27 project DBs
  were migrated and verified row-identical at the new path. `_D-RAG` also holds
  that project's `drag-lint-project.json` (ownership roots, next bullet) and
  its ghost-compile recovery journal. Only DBs with **no owning project
  folder** stay in `C:\Projects\.drag-lint\`: `library-{platform}.sqlite` and
  the SQL index (`C:\Projects\DB\SQL\drag-lint-sql.sqlite`). Both manifest
  copies (`third_party\dll-win32\drag-lint.json` and `dll-win64\
  drag-lint.json`) resolve an omitted section `db` to this path automatically
  (`ExpandSectionDb` in `DRagLint.Index.Manifest.pas`); `resolve-dbs` is still
  the right way to find a DB without hardcoding the path.
- **The IDE plugin's DB path template follows the move.** The default is now
  `<projdir>\_D-RAG\<projname>.sqlite`; the pre-relocation flat
  `<projdir>\drag-lint.sqlite` is still probed as a fallback, so an IDE whose
  registry still holds the old template keeps finding an index.
- **`lint-all` now reports only the project's own code.** Ownership is
  declared in `<project folder>\_D-RAG\drag-lint-project.json` (key
  `ownRoots`, entries absolute or relative to that folder), defaulting to the
  project's own folder when the file is absent. A vendored/third-party root
  the project compiles against is reported as **skipped** (named, with its
  file count), not silently dropped; `--lint-third-party` restores the old
  unscoped behavior. Measured: YADF went from 1,072 findings to 305
  (`C:\Projects\DelphiAST`, 8 files, skipped); ORM3-Micronite2027 scans 565
  files instead of 641, keeping all 295 `COMMON\OBJECTS` units while dropping
  the 76 `PDFlibPas` ones.
- Docs updated: `README.md`, `docs/INDEXING-AND-DB-ARCHITECTURE.md`,
  `docs/SCAN-DATABASES.md`, `docs/INSTALL.md`,
  `docs/editors/vscode-and-zed-mcp.md`, `skills/relint/SKILL.md`.

### Project-scoped indexing: scan type vs mode, and one DB per project (2026-08-09)

- **Scan TYPE and MODE are two independent axes.** TYPE is **declared by the
  target**: an `include` entry (or `index` argument) ending `.dpr`/`.dproj`
  makes a **project** section, a folder makes a **library** section. MODE is
  **chosen per run**: `--rebuild` (from scratch) or `--recompile` (incremental,
  the default). Neither implies the other.
- **A project index is exactly the compile closure**: the `.dproj` members, the
  project-local units they use transitively, each unit's sibling `.dfm`, the
  `{$I}` include files, and the project file. Units resolved through a Delphi
  **Library/Browsing** path are excluded (they belong to the library index);
  loose unreferenced files in the project folder are excluded.
- **Per-repo union DBs retired; one DB per project.** DBs now live under
  `C:\Projects\.drag-lint\` as `<Repo>-<Project>.sqlite`. ORM3's union DB
  (`C:\Projects\DB\ORM3\drag-lint.sqlite`) is replaced by eight project DBs
  (`ORM3-Micronite2027`, `ORM3-MicroniteMW1Service`, `ORM3-Interfaces`,
  `ORM3-TestMicroniteObjects`, `ORM3-MicroniteTests`, `ORM3-TestCachedUpdates`,
  `ORM3-PdfOcrImportTests`, `ORM3-TEST_uSetupDefaultsFrm`); this repo's own
  self-index is now `DragLint-Cli.sqlite` (plus `DragLint-Wizard`,
  `DragLint-Tests`, `DragLint-CorpusScan`).
- **Deleted DB files** (any doc or script naming them is stale):
  `Delphi-RAG-lint.sqlite`, `TableTools.sqlite`, `OCRPDF.sqlite`,
  `DataCopy.sqlite`, `Delphi-RAG-Lint-Graph.sqlite`, `M2022.sqlite`,
  `active-projects.sqlite`, `convrules-worktree.sqlite`, `library.sqlite`,
  `projects.sqlite`, `samples.sqlite`, and the ORM3 union DB above.
- **`resolve-dbs` is how you find a DB.** `--platform <p>` lists every
  configured DB; `--project <file.dproj>` and `--in <file.pas>` resolve the one
  covering a given target. **Cross-project questions need several `--db`
  flags** -- with per-project DBs, a single-DB `find-callers` answer can be
  wrong across projects.
- Docs updated: `README.md`, `docs/INDEXING-AND-DB-ARCHITECTURE.md`,
  `docs/SCAN-DATABASES.md`, `docs/AI-INDEX-FIRST.md`, `docs/AI-USAGE.md`,
  `docs/INSTALL.md`, `docs/AI-CONVERT-RUNBOOK.md`,
  `docs/editors/vscode-and-zed-mcp.md`, `docs/INDEX-SCHEMA.md`;
  `docs/FIX-2026-08-03-index-project-scope.md` marked superseded.

## v1.2.2-alpha -- 2026-08-03

### Auto-Document Phase 3 -- provenance, comment harvesting, four new facts (schema v19)

- **Uniform provenance marker, and the content sniff is gone.** Every
  engine-owned tag now carries `<!-- drag-lint:auto -->`. Ownership is
  MARKER-KEYED, never content-keyed: the old `StartsText('Observed:')` sniff --
  which silently adopted any human sentence that happened to begin that way --
  is deleted. **The contract in one line: text inside a marked tag is
  engine-owned and will be regenerated; remove the marker to take ownership; a
  tag without the marker is never touched.**
- **`document --strip`.** Removes the engine's own managed blocks and marked
  tags and leaves everything else byte-identical, so a documented tree can be
  returned to its pre-`document` state exactly. The marker is what makes this
  exact rather than heuristic.
- **Comment harvesting.** A plain `//` comment above a declaration is promoted
  into a managed `<summary>` (first paragraph) and `<remarks>` prose (the rest),
  XML-escaped. Interface-side is preferred; implementation-side is where the
  volume actually is (on the YADF corpus, 120 of 121 harvestable comments sit
  above the body). **COPY, NEVER MOVE:** the original comment stays exactly
  where it was. A hand-written `<summary>` always wins over a harvest.
- **Harvest drift is reported, not applied silently.** A new `ddHarvestDrift`
  doc-drift finding fires when a marked `<summary>` no longer matches the
  comment it was harvested from -- refreshed when the source comment changed,
  removed when the source comment is gone -- naming the symbol and both texts.
  Fixable: the next `document --apply` (or `lint-all --fix`) satisfies it.
- **Repair is non-destructive.** The repair path may no longer delete a tag it
  does not model; every unmodeled tag is preserved byte-for-byte. Accepted
  consequence: a stale unmodeled tag lingers until a human removes it.
- **Render fixes:** an empty tag is never written (a blank `<summary>` renders
  as a blank tooltip, which is worse than no tooltip); the ` ?` uncertainty
  marker appears only on genuinely mixed lists; a non-callable renders
  `Used by:` rather than `Called from:`.
- **Four new facts + `Pure`** (schema v19 adds `mutates_params`, `ui_affinity`,
  `touches`, `wiring` to `symbol_facts`):
  - `Mutates: AList (var), AReason (out)` -- the `var`/`out` parameters a
    routine writes through. Closes the Phase-2 gap that covered fields only.
  - `UI thread only -- touches FPanel, Application` -- **positive findings
    only.** Its absence means "no UI touch was detected", never "thread-safe".
  - `Touches: file system, registry` and `Transaction: starts, commits` --
    categories, not call sites.
  - `Registered as: IFolderService (singleton)` and
    `Dataset: qryFolders -> FOLDERS (ID, NAME)` -- a pure join over
    `di_bindings` / `orm_links` / `fb_relations` / `fb_columns`, no new AST
    analysis. Computed at render time, like `Covered by:`, because `orm_links`
    is written by a separate post-index pass.
  - `Pure` -- DERIVED at render time from the other facts, with no column of its
    own so it cannot disagree with them. It means "none of the effects this
    engine can detect were detected", and it never creates a doc block on its
    own: a block is only written when there was something else to say.
- **Schema 18 -> 19 is purely additive.** Four columns on the existing
  `symbol_facts` table; nothing removed or renamed, the version gate stays a
  `>=` check. A consumer issuing `SELECT *` on `symbol_facts` now gets four more
  columns -- select by name if position matters. **`symbols.id` is reassigned by
  the full reindex: re-resolve by `qualified_name`, never by a cached id.**


- **Fixed: a used unit's name was stored with the source's alignment padding,
  and the `uses` edge was silently lost.** `unit_uses.unit_name` came from
  `Trim(NodeText(moduleName))`, but a `moduleName` node spans the WHOLE dotted
  name, so a house-style-aligned clause (`Alpha  .Config,`) was stored verbatim.
  `ResolveUnitUseTargets`' pass 1 keys on `LOWER(unit_name) = :un`, which a
  padded value can never satisfy; pass 2 keys on the dotted tail and quietly
  rescued the row whenever that tail was unique, so the defect was invisible
  until two units shared a tail -- then the edge was simply dropped. Now
  stripped at the store, at BOTH sites that read the node (the `uses` clause and
  a unit's own `unit Foo.Bar;` declaration, which is the qualified-name prefix
  of every symbol the unit declares). **This is an INDEX-TIME fix: existing
  indexes keep their bad rows until they are reindexed.** Measured before the
  fix: 147 of 1836 `unit_uses` rows in this repo's own index (137 unresolved)
  and 286 of 14223 in ORM3 (285 unresolved); 0 in `library-Win64` and 0 in
  M2022, because the alignment is our house style and not third-party code. If
  you rely on `find-callers`, `query descendants`, the unit graph or `--json`
  uses output over an index built before this, **reindex** -- until then those
  rows still read as unresolved. Not handled: a comment written inside the
  dotted name (`Alpha.{x}Config`).
- **Fixed: `index` lost up to 127 bytes of its own progress log whenever the
  process was killed.** `Output` is buffered through Delphi's 128-byte
  `TTextBuf` and reaches disk only when that buffer fills or when the RTL closes
  it during a normal `_Halt0`, so an `index` run terminated externally
  (`Stop-Process`, `taskkill`, a fault) ended its log mid-token at the last
  128-byte boundary -- which cost five runs of a library rebuild investigation,
  because the last visible token looked like the crash site and was not.
  `TIndexer.IndexFile`'s per-file `finally` now flushes, covering the progress
  line, its `DIAG:` lines and the `ERROR indexing` path alike, at one <=128-byte
  write per file. Scope, stated plainly: this guarantees no COMPLETED line is
  left in the buffer; a single emitted line longer than 128 bytes (a `DIAG:`
  line on a deep path) still reaches disk in pieces and can still be read
  cut mid-line. Other long-running verbs (`lint --project`,
  `document --project`, `convert`, `workspace index`) are unchanged and still
  truncate. See `docs/INBOX-REPLY-index-win32-abort-2026-07-29.md`.
- **Auto-Document Phase 2: six analysis facts in `document` and `hover`.**
  Beyond Phase 1's cheap index lookups, the managed `<!-- drag-lint:auto -->`
  block -- and the `hover --format md` popup, rendered from the same shared
  formatter so the two surfaces can never disagree -- now also carries up
  to six *analysis* facts per routine: a bounded dataflow/CFG/escape-
  analysis pass over the body, computed once at index time and persisted in
  a new `symbol_facts` table (schema **v18**). `Complexity: N (cyclomatic),
  M lines` (cyclomatic complexity + body LOC, shown only when `N >=` the
  new `docs.complexity_min` config key, default `10`; applied at RENDER
  time, so changing it needs no reindex). `Reads: a, b   Writes: c`
  (own-class instance fields read vs. written; a field passed to an
  ordinary call's `var`/`out` parameter is conservatively counted as a
  read, not a write -- absence over a wrong write). `Owns returned: new
  (caller owns)` / `borrowed` / `self` (conservative escape analysis on
  `Result`, emitted only when every return site in the routine unanimously
  agrees -- absence over a wrong verdict, since a wrong `new` invites a
  double-free). `Handles: Button1.OnClick` (the paired `.dfm`'s event
  wiring for a published method). `SQL: reads A, B; writes C` (table names
  mined from SQL-shaped string literals in the body; best-effort --
  dynamically-concatenated SQL, subqueries, and CTE bodies are skipped, not
  guessed at). `Covered by: A, B (+N more)` (test callers -- a `*Test`/
  `Test*`-named unit or a `TTestCase`-descended class -- reachable within 3
  reverse call-graph hops). Five of the six facts are index-time snapshots
  and go stale, like the rest of the index, after a `document --apply`
  (which shifts line numbers) or any source edit -- reindex to refresh
  them. `Covered by` is the one exception: computed LAZILY at
  `document`/`hover` render time straight from the live call graph, so it
  is always current and adds zero index-time cost. See `docs/AI-USAGE.md`
  (Docs section) for the full per-fact reference, limitations, and the
  `docs.complexity_min` config note.
- **Benchmark: the always-on facts add ~1.5x to index time.** Indexing this
  repo's own `src/` tree (154 files, 14,324 symbols, 103,752 refs -- a
  bounded, routine-dense corpus, not the giant Library corpora) with the
  Phase 2 facts analyzer always on took **43.2s** (avg of 2 runs, fresh DB
  each time), vs. **29.4s** for the pre-Phase-2 build (`main` at
  `2556cc3`, same corpus, same machine) -- a **1.47x** ratio. Well under
  the 2x threshold the design flagged as worth an opt-in gate, so no
  follow-up was filed; the always-on decision (every `index` run computes
  all six facts, no flag) stands as designed.

## v1.2.1-alpha -- 2026-07-22

- **Fix a source-corrupting bug in `document --apply`.** When a hand-written
  `<summary>` / `<param>` / `<returns>` description spanned several source lines,
  the merge step emitted it on a single line with the interior newlines intact --
  leaving the continuation lines with NO `///` prefix. That corrupted the source
  AND broke the `///`-comment block, so a second run mis-parsed the fragment and
  injected/duplicated managed blocks (comments split into parts, un-prefixed
  lines, duplicated `<summary>`/`<remarks>`). Multi-line descriptions are now
  re-prefixed line-by-line (as the remarks-prose path already was). Regression
  lock `tests/autodoc/run_doc_multiline.ps1`.
- **`Overload k of n` now covers free (unit-level) function/procedure overloads,**
  not just methods (the cheap-fact guard excluded `skFunction`/`skProcedure`).
  Also drops the spurious self-`Calls:` a free routine picked up from its own
  `Name(` header line.
- **Mined `Result:=` return cases are shown even alongside a hand-written
  `<returns>`** -- as a managed `Returns: ...` fact line (the author's tag is
  preserved). A managed/empty `<returns>` still carries them in the tag itself,
  so they live in exactly one place and stay idempotent.
- **Hover popup: show observed return cases + resolve the overload under the
  cursor.** The markdown hover now renders a `Returns (observed): ...` line from
  the live-mined cases (previously only the JSON format had them), and
  `textDocument/hover` disambiguates an overloaded name by cursor position
  instead of always showing the first overload.
- Design doc for the deferred Phase 2 analysis facts (index-time facts layer):
  `docs/superpowers/specs/2026-07-22-autodocument-phase2-analysis-facts-design.md`.

## v1.2.0-alpha -- 2026-07-21

- **DocInsight XML-escaping: generated doc comments are always well-formed.**
  `document` / `document --project` now XML-escape *every* mined value written
  into the managed `<!-- drag-lint:auto -->` block -- deprecated messages,
  caller/callee names, `Overrides` / `Overridden by` / `Implements` / `Raises`
  types, and `<seealso cref>` -- not just the `<returns>` "Observed:" cases that
  were already escaped. Previously a generic type (`TList<T>`), an operator
  method, or a `deprecated '...'` message containing `<`, `>` or `&` produced
  ill-formed XML ("Bad XML documentation comment") during DocInsight
  generation; and a fact containing a literal `</remarks>` additionally broke
  idempotent regeneration (the non-greedy re-parse stopped at the injected close
  tag, so the managed fence failed to strip on a second run and hand-written
  prose after it was dropped). Hand-written summary / param / remarks prose is
  still preserved verbatim -- only generated/mined content is escaped. Covered
  by `tests/autodoc/run_doc_xml_escape.ps1`.
- **Whole-Project Auto-Document Phase 1: config-driven returns/callers, a
  trivial-accessor skip, five cheap fact lines, and an IDE menu item.** A new
  manifest `docs` section gains two more optional keys alongside the existing
  `max_return_cases`: `max_callers` (production ships `5`) caps the generated
  "Called from:" list at N entries, appending `(+N more)`; and
  `accessor_trivial_max_lines` (default `2`, code-level -- stays ON even with
  no `docs` section at all) sets the trivial-accessor threshold below.
  Production also now sets `max_return_cases: 6`, so `<returns>` gets a real
  "Observed: Result := ...; ..." suffix mined from the method body instead of
  a bare `TODO: describe.`. Batch document modes (`document --unit`,
  `document --project`, `document-all`) now skip a public `Get*`/`Set*`-named
  method whose impl body is `<= accessor_trivial_max_lines` lines, cutting
  noise from one-line property accessors; the run summary reports "N trivial
  accessor(s) skipped" and a new `--include-accessors` flag opts back in.
  `document --qname` (one explicit symbol) is never filtered, even when it
  names a trivial accessor. The managed `<!-- drag-lint:auto -->` block also
  gains five new omit-when-empty fact lines for method-like symbols:
  `Overrides: TAncestor.M`, `Overridden by: A, B (+N more)`, `Implements:
  IFoo.Bar` (a name-based heuristic against interface ancestors, not a
  compiler-verified check), `Overload k of n`, and bare `virtual`/`abstract`
  markers. (A per-symbol Platform/`{$IFDEF}` fact was designed but deferred
  to Phase 2 -- the index has no per-symbol conditional-compilation guard
  yet.) Finally, the IDE plugin's drag-lint menu gains **Generate && Export
  -> "Auto-Document Whole Project..."**, which runs `document --project
  <active.dproj> --apply` on the active project directly -- no preview
  dialog; a `.bak` per modified file plus git are the safety net. See
  `docs/AI-USAGE.md` (Docs section) for the full config/flag reference.
- **Proptree assignability engine: `prop_access` (schema v17), `proptree/2`,
  `--min-visibility`, and `convert-scaffold --surface`.** The index now
  captures each property's real accessor shape: a new additive
  `symbols.prop_access` column (`'ro'` read-only / `'rw'` read+write / `'wo'`
  write-only), stamped from the property's own `read`/`write` accessor
  clause at parse time. NULL for non-properties and for a bare property
  redeclaration with no own accessor (resolved from the nearest class
  ancestor at query time); migration-safe like every prior bump (`ALTER
  TABLE` on next open, `NULL` until re-indexed). `proptree`'s JSON output
  moves to schema **`proptree/2`** (additive over `proptree/1` -- every
  existing field kept): each leaf now also carries `is_writable` (true
  unless the resolved `prop_access = 'ro'`, or a typed class constant for a
  field leaf; **defaults to `true`** when absent, so an un-re-indexed DB
  behaves exactly like `proptree/1`), `visibility` (`published`/`public`/
  `protected`/`private`/`''`, with `strict private`/`strict protected`
  collapsed to their base; defaults to `''`), and `member_kind`
  (`property`/`field`; defaults to `property`). `type` is now the
  class-accurate CONCRETE per-class type (e.g. on `TcxCheckBox`,
  `Properties` resolves to `TcxCheckBoxProperties`, never a same-named
  sibling class's type). A new `proptree --min-visibility published|public`
  flag filters emitted leaves by effective visibility (unset = all leaves,
  back-compat; `published` = the DFM-streamable surface, fields never
  included; `public` = published+public, including public fields).
  `convert-scaffold` consumes the same fields to restrict auto-`#link`
  TARGETS to genuinely valid assignment targets: a new `--surface dfm|pas`
  flag (default `dfm`) picks the bar -- `dfm` requires
  `member_kind='property'` and `visibility='published'` (the DFM-streamable
  surface); `pas` relaxes to `visibility` in (`published`,`public`) and any
  `member_kind` (so a public field can be a target too). On either surface
  `is_writable=false` is never a valid target, and on a `proptree/1`-shaped
  (pre-v17 / un-re-indexed) DB the filter degrades to prior (unfiltered)
  behavior via the documented defaults. See `docs/CONVERSION-RULES.md` and
  `docs/INDEX-SCHEMA.md` (symbols table, section 2.2).
- **Fresh compiler findings: `refresh-findings` keeps DCC hints/warnings/errors
  current.** drag-lint replicates the Delphi compiler's diagnostics alongside
  its own lint rules, but the incremental compile it ran skipped clean units --
  so a hint like `H2219 Private symbol ... declared but never used` on an
  unchanged unit never surfaced (its `.dcu` was up to date, so DCC did not
  re-emit it). A new per-file compile timestamp `files.last_compiled_unix`
  (schema **v16**) tracks the last successful compile of each unit; a new verb
  `refresh-findings --project X --db D [--full] [--json]`
  recompiles only the STALE units (`last_compiled_unix IS NULL OR <
  mtime_unix`) and refreshes `compiler_findings` per file: `>= 2` stale runs a
  full build (`/t:Build`, `dcc -B`, catches every unit's hints), exactly 1
  stale runs an incremental compile, 0 stale is a fast no-op, and `--full`
  forces a full build. A failed compile stores its errors but leaves the file
  stale (so it retries) rather than stamping a bad timestamp. The IDE plugin
  spawns the verb fire-and-forget (Win64 child, so the compile never taxes the
  32-bit IDE) on save and on idle, and adds a **"Full Compile Sweep"** menu item
  (`--full`). (Also fixes a latent bug: the stale query filtered
  `language = 'pascal'`, but the indexer records Pascal source as `'delphi13'`,
  so the intended filter matched zero rows.)
- **`convert-apply`: the component-conversion applier is shipped.** The new
  `convert-apply --unit F.pas --rules <file> --db PATH [--only Name1,...]
  [--apply] [--no-backup]` verb rewrites all 5 conversion surfaces for every
  `.dfm` component instance matching a `#convert` rule: (1) `.pas` declaration
  retype, (2) `.pas` uses-add, (3) `.dfm` object-block re-emit (via the Batch
  2a-i `ReemitComponent` engine, including moved-depth properties and event
  renames), (4) `.pas` property/event access-site rewrite at every use of a
  converted instance (via ref-gap G's `member-access` refs -- the piece that
  makes the result actually compile), and (5) runtime-creator retype plus an
  unconditional `{ TODO: verify creator }` marker. Dry-run (preview, no writes)
  by default; `--apply` writes for real, guarded by a freshness check
  (refuses to build a plan from a stale/unindexed F or T type) and, unless
  `--no-backup`, protected by a `.BCK<n>` backup of every touched file, a
  `recovery.txt` written BEFORE the writes land, and a `// drag-lint
  convert-apply` comment prepended to the converted `.pas`. Still deferred:
  split/merge, the expression interpreter, and full property-default fidelity
  (see `docs/CONVERSION-RULES.md`).
- **Ref-gap G: member-access indexing.** The reference index now captures
  property/field MEMBER access on typed receivers (`Edit1.Caption`) under a new
  `kind='member-access'` ref, emitted (under `--deep`) when the receiver is a
  plain identifier that is NOT `Self` (the complement of ref-gap D's `Self.`
  gate) and the member is a plain identifier. Chained (`a.b.Caption`), call
  (`f().Caption`), and indexed (`arr[i].Caption`) receivers are excluded, so the
  index is not flooded -- verified on a real unit: `member-access` was ~12% of
  refs, and existing `read`/`write`/`type_use`/`call` counts were untouched (the
  distinct kind never pollutes them). This is a SUPERVISED core-parser change
  (the exact diff was reviewed and approved before it was applied), mirroring the
  discipline of ref-gaps D and E. **Effect:** powers the `convert-apply` verb's
  instance-scoped property/event access-site rewrite (`Edit1.Caption` ->
  `Edit1.Text`) -- surface #4 of the applier (see above).

## v1.1.0-alpha

- **Ref-gap E: type-reference indexing (H4).** The reference index now captures
  four type-USE shapes it previously missed, under `--deep`: (1) the class
  qualifier on a method-IMPLEMENTATION header (`Widget.Use` -> the `Widget`);
  (2) the PARAM and RETURN types on that impl header (`procedure Widget.Use(p:
  Widget): Widget`); (3) local-var type annotations inside a method body
  (`Local: Widget`); and (4) `is`/`as` type-test operands (`X is Widget`). All
  emit the existing `kind='type_use'` ref, so the naming autofix (which finds
  sites by name via a kind-agnostic query) rewrites them with no consumer
  change. Each emit is tightly AST-gated (mirrors ref-gap D) -- verified no
  over-capture (a `type_use` never lands on a variable/param name, and the
  `is`/`as` gate never fires on arithmetic/comparison operators). **Effect:** a
  `type-name-prefix` `--fix` rename (e.g. `Widget` -> `TWidget`) now rewrites
  EVERY use site, so it no longer silently strands old-name references.
- **Naming `--fix` warning narrowed.** Because ref-gaps D+E now cover every
  type-reference site, the `--fix` stderr warning is **retired for
  `type-name-prefix`**. It is **retained for `field-name-prefix`**, narrowed to
  name the one remaining uncovered shape -- a bare field read used as an
  expression operand (`Result := client + 1`), which is not yet indexed
  (tracked as ref-gap F). `param-name-prefix` remains warning-free.
- **`butterfly` chart verb (Track 5.3 slice, Batch H2).** A new CLI verb:
  `drag-lint butterfly --qname X [--depth N] [--format dot|mermaid|text|json]
  [--output F] --db PATH [--db ...]` composes a symbol's **callers (upward
  wing)** and **callees (downward wing)** into one chart -- the static-export
  counterpart to the in-IDE butterfly renderer (Batch F). No new engine:
  reuses the shipped `BuildReverseCallTree`/`BuildForwardCallTree`
  (`DRagLint.Report.RCallTree`); the two trees share the same root qname, so
  the composed chart attaches both wings to one center node. `--depth` applies
  to both wings (default 3). Default format is `dot` (a chart verb, unlike
  `reverse-calltree`'s `text` default). `dot`/`mermaid`: callers render
  `caller -> X`, callees render the REVERSED `X -> callee`; the root node is
  styled distinctly (`#ffd` fill, bold) so the chart's center is obvious.
  `json`: schema `butterfly/1` wraps the two full `reverse-calltree/1` tree
  objects under `callers`/`callees`. `text`: two headed sections (`CALLERS
  (upward):` / `CALLEES (downward):`). Read-only, CLI-only (no BPL/IDE
  change). Multi-db root resolution mirrors `reverse-calltree`: first db that
  resolves the qname wins.

- **Component-conversion FOUNDATION -- 3 read-only verbs + a reFind-superset
  DSL (Track 3, Batch 1).** Index-driven planning for a component/type
  migration (`TDBEdit` -> `TcxDBEdit`, or any `TPersistent`-rooted pair) from
  the REAL, AST-exact property trees of both types. `drag-lint proptree --qname
  X [--depth N] [--no-to-persistent] [--format text|json] --db PATH` is a
  recursive deep-property enumerator: it walks a class's own + inherited
  `property` symbols and recurses into class-typed property types (depth cap 6,
  visited-type cycle guard), emitting flattened dotted paths (`Font.Color`,
  `Sub.Color`) with type/declared_in/kind; JSON schema `proptree/1`. `drag-lint
  convert-scaffold --from F --to T [--out FILE] --db PATH` auto-generates a
  VALID rules file from BOTH trees -- a concrete `#link ToPath <- FromPath`
  where exactly one source matches by leaf-name+type, `??? ` + a `candidates:`
  note where ambiguous, `#default ToPath = ???` for target-only props, and
  `DROPPED` notes for orphaned source props. `drag-lint convert-validate
  --rules FILE [--from F] [--to T] [--print-parsed] --db PATH` parses the DSL
  and validates its `#link`/`#default` paths against the real trees (exit 0
  valid / 1 errors / 2 bad args). The DSL is a strict SUPERSET of Embarcadero
  reFind (adopts `#unuse`/`#remove`/`#migrate` + the raw PCRE escape hatch; adds
  `#convert`/`#link`/`#default`/`#note`). The thesis: reFind is blind PCRE and
  GExperts converts only 1 level, so both miss the deep matches; drag-lint knows
  the real trees down to `TPersistent` and generates correct, validated links.
  Full reference: `docs/CONVERSION-RULES.md`. Read-only, CLI-only, headless. NOTE:
  **apply** (rewriting `.pas` + `.dfm` from a validated rule set) is Batch 2 and
  is NOT yet shipped -- Batch 1 is the read-only foundation.

## v1.0.0-alpha -- 2026-07-09

IDE startup splash, Help>About live self-info, and the new `info` verb (Batch G).

- **IDE startup splash.** The drag-lint logo (reused from TableTools) plus
  `drag-lint (MIT) v1.0.0-alpha` now appears on the RAD Studio splash screen
  while the IDE loads, registered via `SplashScreenServices.AddPluginBitmap`.
  Startup-only and static -- no exe call, so it never delays IDE load.
- **Help -> About -> drag-lint entry.** A new About box entry (icon + MIT +
  version + description). When viewed, it shows **live engine self-info**
  fetched from `drag-lint.exe` on a background thread (never blocks IDE
  startup): engine version + build date, tree-sitter versions, capabilities
  (FTS5, CLI verb count), exe path, platform, and the plugin log path. If the
  exe call fails, it shows a structured diagnostic error block (resolved exe
  path + failure reason) instead, so problems self-diagnose.
- **New CLI verb `info [--json]`.** Read-only engine self-info -- no DB, no
  side effects. `--json` emits schema `info/1` (name, version, build_date,
  license=MIT, description, `tree_sitter` versions, `capabilities` (fts5,
  cli_verbs), exe_path, platform); without `--json`, a human-readable block.
  This is what the About box calls.
- **Removed the `Test Connection...` debug menu item.** Its diagnostics
  (exe-path resolution, spawn/handshake, build tag) are now covered by the
  About box's live-info + error block. The `Tools > drag-lint` menu keeps
  `Open Plugin Log` and everything else.

## v0.99.0-alpha -- 2026-07-09

Butterfly Call Graph dock tab and saved naming presets (Batch F).

- **Butterfly Call Graph dock tab.** A new **"Call Graph"** tab in the drag-lint
  dock renders callers (who calls the symbol) above and callees (what the
  symbol calls) below it, as a navigable `TTreeView` -- double-click a node to
  jump to its file:line. Invoked via **Ctrl+Alt+B**, the **Uses & Dependencies
  -> "Call Graph (Butterfly)..."** menu item, and right-clicking a symbol in
  the Structure tab -> **"Show in Call Graph"**. IDE-only: it reuses the
  `reverse-calltree` verb under the hood and adds no new CLI verb.
- **`reverse-calltree --direction callers|callees`.** The reverse call tree
  verb gained a `--direction` flag: `callers` (default, unchanged) walks
  upward via the existing engine; `callees` walks downward via a new
  `BuildForwardCallTree` engine (what X calls, and what those call). Both
  directions emit the same `reverse-calltree/1` JSON schema.
- **Save-your-own naming presets.** The dock's Lint Options page "Naming
  preset" combo now lists built-ins (Embarcadero/House) plus user-saved
  presets plus Custom, with **Save as...** and **Delete** buttons. Saved
  presets persist to the project's `drag-lint-lint.json` under a top-level
  `naming.presets` array (name + the 8 naming-convention values). IDE-only for
  now -- the CLI does not yet read `naming.presets`.

## v0.98.0-alpha -- 2026-07-08

Library-folders fix, clickable reverse call tree in the IDE, and ref-gap D (Batch E).

- **Library/Browsing folders list no longer collapses to empty.** The Indexer
  Options page's Library/Browsing folder list box had no minimum height, so it
  could render as an empty-looking 0-visible-row control depending on the
  frame's layout pass. `Constraints.MinHeight` now floors it to show at least
  ~20 rows; the list remains user-resizable.
- **Reverse call tree, clickable, in the IDE Messages window.** A new action
  **"Reverse Call Tree (clickable, Messages window)"** runs `reverse-calltree`
  for the symbol under the cursor and posts each node as a clickable
  `AddToolMessage` row in the IDE's Messages window -- double-click a row to
  jump straight to that call site, instead of reading a flat text report.
  Bound to **Ctrl+Alt+K** for fast access alongside the top menu entry. (An
  editor right-click submenu entry was investigated and skipped: RAD Studio 37
  exposes no supported OTA API for adding to the editor's local-menu/right-click
  context menu, so the keybinding and top menu remain the entry points.)
- **`reverse-calltree --format json` now emits `file` + `line` per node.** Each
  node in the JSON tree carries the caller's absolute source file path and the
  call-site line number (previously only the `site` string `unit:line`), which
  is what the new Messages-window action uses to build clickable navigation
  rows.
- **Ref-gap D fixed: `Self.`-qualified field references are now indexed.**
  Under `--deep`, `Self.client` (an `exprDot` node whose LHS base is the `Self`
  identifier) now also emits a `read` reference for the RHS member (`client`),
  gated strictly to an LHS base of `Self` so no other dotted member access
  (`other.Method`, `obj.Prop`) gains a spurious ref. This means
  `field-name-prefix` rename-at-use now catches `Self.`-qualified use sites of a
  field that were previously missed. **Ref-gap E (type-annotation references)
  remains deferred** -- the `field-name-prefix`/`type-name-prefix` `--fix`
  stderr warning (see v0.97 notes) stays in place until that gap closes too.
- Removed the orphaned `T52_options` test fixture (dead since Batch D
  verification; no longer referenced by any script).

## v0.97.0-alpha -- 2026-07-08

Engine fixes, naming autofix phase 2, and IDE ergonomics (Batch D).

- **Naming autofix phase 2 -- prefix-adding.** The naming rules `field-name-prefix`,
  `param-name-prefix`, and `type-name-prefix` are now *fixable*: `lint --fix` (and the
  IDE "Fix it") add the missing convention prefix to the identifier and every reference
  via the rename engine (`client -> FClient`, param `x -> pX`, `myclass -> TMyClass`).
  Opt-in via the `autofix` id list in `drag-lint-lint.json` (off by default), dry-run
  unless `--apply`. `param-name-prefix` renames the routine-local scope safely with a
  new collision guard (skips if the prefixed name already exists in scope).
  **Caveat:** `field-name-prefix`/`type-name-prefix` currently rely on the reference
  index, which does not yet capture `Self.`-qualified field uses or type-annotation
  references, so `--fix` on those two emits a stderr warning to review the diff. (The
  case-only phase 1 rules -- `method-pascalcase`/`local-var-casing`/`const-casing` --
  are unchanged and fully safe.)
- **`rename` verb now renames a method's implementation header.** A bare global rename
  of `TFoo.Bar` previously updated the interface declaration and call sites but left the
  `procedure TFoo.Bar;` implementation header stale. `TRenameRefactoring.Build` now
  renames it too.
- **Bare-identifier assignment reads are indexed.** Under `--deep`, a right-hand-side
  bare identifier (`Result := maxItems;`) now produces a `read` reference, so
  Find-Usages / impact / rename-at-use see const/var reads that were previously missed.
- **Naming-convention presets in the IDE.** The drag-lint dock's Lint Options tab has a
  preset selector -- *Embarcadero* (`AValue` params), *House* (`pMyParam` / `FMyField` /
  `TMyClass`), or *Custom* -- that bulk-sets the naming rules for the project.
- **Reverse call tree from the editor.** A new **Uses & Dependencies > "Reverse Call
  Tree..."** right-click runs `reverse-calltree` for the symbol under the cursor and
  opens the text report in the editor.
- **Dock no longer steals focus.** The drag-lint dockable panel no longer re-selects
  itself to the front when you switch to another IDE tab (Project Manager, etc.); it
  surfaces once and then stays put, updating its content in the background.
- Fixes: `TTextEditApplier` now orders same-line edits by column (correct back-to-front
  application of differing-length edits); the IDE writes the `max_return_cases` manifest
  as UTF-8 to match the CLI; removed a dead internal Options frame unit.

## v0.96.0-alpha -- 2026-07-08

- **Reverse call-tree report (`reverse-calltree`)** -- a new CLI verb: the N-deep
  *upward* "who calls X, and who calls them" tree, per symbol, with call sites
  (`unit:line`) and cycle markers. `--depth N` (default 3); `--format
  text|json|dot|mermaid` (`json` schema `reverse-calltree/1`; `dot`/`mermaid`
  render in the graph viewer); multi `--db` (the first index that resolves the
  symbol wins). Exit 0 on success, 1 when the symbol resolves in no index, 2 on
  usage/db error. Reuses the resolved caller traversal; the pure engine
  `src/report/DRagLint.Report.RCallTree.pas` is designed so AutoDoc can later reuse
  it at depth 1. CLI-only this release. Headless test `run_reverse_calltree.ps1`.
- **Naming-convention autofix, phase 1 (re-casing)** -- the naming rules
  `method-pascalcase`, `local-var-casing`, and `const-casing` are now *fixable*:
  `lint --fix` (and the IDE "Fix it") re-cases the offending identifier and every
  reference via the existing global-rename engine (routine-local vars use the
  routine-scoped rename). Opt-in via the existing `autofix` id list in
  `drag-lint-lint.json` -- **off by default**, dry-run unless `--apply`, and every
  synthesized rename is collision-checked and skipped if unsafe. Prefix-adding
  (e.g. `client -> FClient`) is deferred to phase 2. Synthesizer
  `src/refactor/DRagLint.Refactor.NamingFix.pas`; tests `run_naming_synth.ps1` +
  `run_naming_autofix.ps1`.
- **IDE fix: Structure tree "Code Elements (0)"** -- the plugin's DB resolver now
  also probes `<projdir>\<projname>.sqlite` (the project-name-indexed DB that
  `index --project` and older workflows produce), preferring whichever of the
  template-named or project-name file exists and is non-empty. Previously only
  `<projdir>\drag-lint.sqlite` was tried, so a project-name-indexed workspace fell
  back to an unrelated DB and the outline showed zero elements (diagnostics were
  unaffected -- they come from the LSP, not `outline`).

## v0.95.0-alpha -- 2026-07-08

- **Third-party dependency report (`deps-report`)** -- a new CLI verb that reports
  the external/library units a project depends on, over the index uses-graph.
  Per external unit: which project units import it, the count, the shortest
  uses-path, and a library grouping (RTL / DevExpress / Spring4D / FireDAC /
  other / unknown). Rollup by default; `--edges` for the flat
  project-unit -> external-unit list; `--format text|json|csv`; multi `--db`.
  A unit is "external" when it is not indexed (`unit_uses.target_file_id`
  unresolved) OR resolves to a library path. Pure engine in
  `src/report/DRagLint.Report.Deps.pas`; headless test `run_deps_report.ps1`.
- **Index schema introspection + documentation** -- a new read-only `schema`
  verb dumps the live index schema (schema_version + every table with its
  columns + row counts; `--format json`), and `docs/INDEX-SCHEMA.md` documents
  the SQLite index for external consumers, including the project-vs-external
  boundary rule. So other tools can consume the drag-lint index directly.
  `run_schema.ps1`.
- **IDE configuration consolidated into four Tools -> Options sub-pages**
  (`Third Party > drag-lint > General | Indexer | Linter | Editor`) sharing the
  registry round-trip, replacing the single page + the hand-coded settings modal
  (now retired; "drag-lint Options..." opens Tools -> Options). Adds
  `max_return_cases` on the Linter page (manifest-backed, per-project dotted
  `.drag-lint.json` / global `drag-lint.json`), a read-only Library/Browsing
  folder list + scope + time warning on the Indexer page, and an
  "Edit lint rules (165+)..." button routing to the dock Lint Options tab.
- **Project Manager "drag-lint: Project Rules..." right-click** -- activates the
  clicked project and opens its Lint Options dock tab.
- **Clean plugin teardown** -- the Options pages + the project-menu notifier now
  unregister in `Wizard.Destroyed` + unit finalizations (fixes a pre-existing
  leak where `UnregisterDragLintOptions` was never called; no orphan Options
  node / AV on package unload).
- **Two lint false-positive fixes** -- `doc-drift` no longer mis-parses a class's
  ancestor/interface list as `<param>` tags (param/return drift is now gated to
  routine symbols); `object-leak` no longer flags `X := TSomething.Create(Self)`
  where a non-nil `AOwner` on a `TComponent` transfers ownership (`Create(nil)`
  and non-owned constructions are still checked).
- **Hover Help-Insight restyle** -- the IDE hover popup renders as a
  Delphi-Help-Insight-style tooltip instead of a plain-text dump: a one-line
  clickable signature header (`unit.pas Line N` right-aligned, click -> jump to
  definition), a colored + selectable `TRichEdit` body using the IDE's own editor
  font and syntax colors (WCAG-contrast-guarded against unreadable dark-theme
  pairings, `src/cli/DRagLint.Hover.Contrast.pas`), column-aligned parameters with
  `const`/`var` modifiers, a mined **Returns** section (distinct `Result :=`/
  `Exit(...)` RHS expressions from the routine body span, capped at 10,
  `src/cli/DRagLint.Hover.Returns.pas`), and a **Called from** section matching
  AutoDoc's caller-facts display (<=15 shown in full, >15 shown as 10 +
  "...and NN more"). Includes a hardening guard in `DoHover`
  (`src/cli/DRagLint.CLI.pas`) against an inverted body-line span on a stale
  index (`ImplStartLine` past EOF), which now yields an empty Returns mine
  instead of crashing. IDE live smoke is open (user-driven, per convention).

## v0.94.0-alpha -- 2026-07-07

Enum-Helper Generator: automates the standard enum `record helper`
(`ToByte`/`FromByte`/`ToInteger`/`FromInteger`/`ToString`/`FromString`
[+`ToDescription`]) that ORM3's `MSCTYPES.PAS` hand-writes ~45x. Right-click an
enum (or enum member) in the IDE -- or run one CLI verb -- and drag-lint resolves
the enum, generates a deterministic Byte-family helper referencing only the real
named members, and places the declaration + method bodies into the unit (populating
an empty implementation section if needed). Create-only-if-missing and idempotent (a
second run is a byte-identical no-op). Backed by **first-class helper indexing**
(new `type_helpers` edge table, **schema v14 -> v15**) so the guard and a new lint
rule never string-parse heritage. The acceptance gate is a real build + round-trip
test (the generated Pascal compiles and its converters round-trip), not text-matching.

### Added

- **`create-enum-helper` CLI verb** -- `create-enum-helper --qname <TEnum>
  [--apply] [--no-backup] [--json] [--methods <csv>] [--tostring rtti|case]
  [--db <db>]`. Mirrors `document --qname`: previews a `TTextEdit` set by default,
  `--apply` writes it. `--methods` subsets the six converters (default all six);
  `ToDescription` is added automatically when a same-unit `<Enum>Descriptions`
  array exists. `--json` emits `{qname,file,action,edits,applied}`; refuse cases
  (`exists`/`no_impl_section`/`not_found`) exit non-zero with a message.
- **`helpers-of <T>` CLI verb** -- lists every record/class helper edge targeting
  type `T` anywhere in the index (`--json`); exits 0 with an empty result when none
  (drives the IDE menu's enablement).
- **IDE "Create helper class" context menu** (Structure tab) -- enabled on an enum
  (or an enum member) that has no helper yet; spawns `create-enum-helper --apply`
  via the shared exe resolver and reloads the buffer. (Live smoke is user-driven,
  as with every IDE feature.)
- **First-class helper indexing (schema v15)** -- a new `type_helpers` table stores
  each `record/class helper for T` as a resolved edge (helper symbol, target name,
  resolved target symbol id/file), mirroring `type_ancestors`. New store methods
  `FindHelpersOfType(name)` (name-scoped, for the diagnostic verb) and
  `FindHelpersOfTypeSymbol(id)` (symbol-identity-scoped, for the guard + lint rule).
  A pre-v15 DB self-heals via the migration path (new table + `is_helper` column);
  regression-tested against a hand-built v14 DB.
- **`enum-helper-separate-units` lint rule (ON by default)** -- flags a helper
  declared in a different unit than its target enum, using the symbol-identity
  helper edge (never a heritage string). Honored in **both** `lint-all` and
  `lint-project`. Validated at **0 false positives** on the self-index (the
  symbol-identity match avoids cross-linking same-named enums in different units).

### Details

- **One Byte-family template** for every enum: `To*` = `Ord(Self)`; `From*` = a
  `case Ord(member)` mapping each real named member, `else` the first declared
  member (no clamp, no ShortInt variant, no dummy filler members). Negative or
  gapped ordinals are just their byte value -- padding is the enum author's job.
- **`ToString`/`FromString`** default to RTTI (`GetEnumName`/`GetEnumValue`, adds
  `System.TypInfo` to the implementation `uses` when needed); `--tostring=case`
  emits editable per-member string literals instead. Enums with **explicit
  non-sequential ordinals** lose Delphi's automatic RTTI, so the generator
  **auto-falls-back to case-mode** for them even under the default -- the output
  always compiles.
- Generated Object Pascal is strict 7-bit ASCII / CRLF, like all project source.

## v0.93.0-alpha -- 2026-07-06

AutoDocument Finish: completes the AutoDocument track. drag-lint now generates
and repairs DocInsight `///` doc-comments across a whole unit or project (not just
one declaration), enriches them with three new ground-truth doc-sources, detects
structurally-stale docs, and ships two documentation lint rules. Everything obeys
the two AutoDocument invariants: **never fabricate prose** (a missing `<summary>`
is a `TODO: describe.` marker, never a guess; every emitted fact is ground-truth
from the index/signature/directive/git) and **idempotency** (a second run is
byte-identical). No index-schema change (still v14).

### Added

- **Whole-unit / whole-project batch** -- `document --unit <file>`,
  `document --project <dproj>`, `document-all` drive the single-declaration
  documenter across every public (interface-section) declaration in one edit set.
  **Facts-only by default** (only writes/refreshes the managed facts block +
  preserves hand prose; skips a pure all-`TODO` create); `--stubs` opts in to a
  `TODO: describe.` summary for a decl with no derivable facts.
- **Three doc-sources** (into the managed `<!-- drag-lint:auto -->` block, all
  ground-truth):
  - **`@deprecated`** -- a deprecation note when the declaration carries Delphi's
    `deprecated` directive (with its message).
  - **`<seealso>`** -- `<seealso cref>` links to the most-related symbols
    (resolved callees + type siblings), capped and deduped; opt-in via `--seealso`.
  - **`<since>`** -- a `<since>YYYY-MM-DD</since>` from `git blame` of the
    declaration line; opt-in via `--since`, and **degrades silently** (emits
    nothing rather than a wrong date when git is absent or the line can't be
    attributed).
- **`doc-drift` lint rule** (ON by default) -- flags a doc-comment that is
  structurally stale vs the code, via a deterministic doc-vs-code diff (no LLM):
  renamed/removed/missing `<param>`, `<returns>` present-but-void or
  value-but-undocumented, return-type change, `<exception cref>` no longer raised,
  a summary/remarks identifier that was removed, and an out-of-date facts block.
  `--fix` applies ONLY the mechanically-safe subset (refresh the facts block, add
  a missing `<param>`/`<returns>` stub) and **never rewrites hand-written prose**.
- **`missing-doc` lint rule** (OFF by default / opt-in) -- flags a public
  declaration with no DocInsight doc-comment (public surface only). Its "Fix it"
  inserts a full documenter-generated doc-comment for a **single** finding (IDE +
  `lint --fix-line`); it is deliberately **excluded from the blanket
  `lint-all --fix` batch** (project-wide documentation is `document --project`'s
  job). Ships off-by-default after a measured first-run wave.
- **IDE menus** -- "Document unit" / "Document project" context-menu items; the
  existing "Fix it" menu now offers `doc-drift`'s safe fixes automatically.
- **Diagnostic verbs** -- `preprocess`-style `doc-drift --qname X` (dump drift
  findings for one symbol); `document --unit`/`--project`/`document-all` help.

## v0.92.0-alpha -- 2026-07-06

In-process Delphi preprocessor: drag-lint now resolves `{$IFDEF}` compiler
directives *before* parsing, so indexing is per-config-accurate -- only the
active branch's symbols and `uses` are indexed for a given platform/config, and
the `{$IFDEF}`-cross-branch parse-failure class is eliminated. This is a native
Object Pascal port of the tree-sitter-delphi13 JavaScript preprocessor -- **no
Node.js runtime dependency**; the JS remains a byte-for-byte test oracle only.
The stage blanks inactive branches and all directives to spaces (newlines
preserved) so output byte-length equals input byte-length -- offsets stay 1:1
with the original file, so tree-sitter spans need no source map. Preprocessing is
**ON by default**; `--no-preprocess` reverts to the prior all-branch behavior,
and a per-file exception falls back to raw indexing for that file (never a
hard-fail). The grammar team reviewed this port against their JS oracle and
declared the Delphi port **canonical** for drag-lint. Built against the current
full grammar DLL; a pure-grammar swap is a separate follow-up. No schema change
(still v14).

### Added

- **`DRagLint.Preprocess.*` units** (`src/preprocess/`) -- a native directive
  **Lexer** (byte-offset chunk stream), an **`{$IF expr}` Evaluator**
  (recursive descent: `or`/`and`/`not`/comparison/`defined()`/`declared()`/
  numeric `CompilerVersion` checks, conservative-false on any parse error), and a
  chunk **Processor** that maintains an `{$IFDEF}`/`{$ELSE}`/`{$ELSEIF}`/
  `{$ENDIF}` state stack + a live defines table and blanks inactive branches.
- **Include handling** -- `defines-only` mode: a `{$I X.inc}`'s `{$DEFINE}`/
  `{$UNDEF}` propagate to the *parent's* defines set (fixes the wrong-branch bug
  when a config `.inc` defines a switch a parent `{$IFDEF}` tests), the `{$I}`
  directive is blanked, the body is **not** spliced (offsets stay 1:1); plus
  `off` mode. `expand` (body-splice) is deliberately not ported.
- **Define-profile resolver** (`DRagLint.Preprocess.Profile.pas`) --
  `ProfileFromDproj` derives the active defines from a `.dproj` (Base + selected
  config `DCC_Define` union platform built-ins), `PlatformBuiltins` for library
  scans. Win64/Win32 built-in define sets for RAD Studio 37 (CompilerVersion 37).
- **Diagnostic verbs:** `preprocess-file --file F [--define X]... [--numeric K=V]...
  [--include-mode off|defines-only]` (writes resolved source to stdout);
  `pp-profile --dproj F [--platform P] [--config C]` (dumps the resolved define
  set); plus `dump-pp-lex` / `dump-pp-eval` (lexer/evaluator diagnostics).

### Changed

- **The indexer runs `Preprocess` between UTF-8 transcoding and parsing** when
  enabled, so only the active branch's symbols are extracted. The incremental
  up-to-date sha is still computed over the raw on-disk bytes (no forced mass
  reindex); doc-comment scanning follows the preprocessed bytes the parser saw.
- **The closure/uses file-discovery scanner honors the active profile** -- a unit
  `uses`d only under an inactive branch is no longer discovered/pulled into the
  index (per-config file discovery). `--no-preprocess` keeps the prior
  all-branch brace-strip scan byte-for-byte unchanged.

## v0.91.0-alpha -- 2026-07-06

D5 call resolution: resolve each Delphi call site to its specific target symbol
by typing the receiver, and switch AutoDocument + the call-graph verbs to precise
resolved callers instead of name matches. This fixes the AutoDocument "Called-from"
name-collision bug -- `document --qname X.Run` no longer lists callers of every
other `Run` in the codebase; it lists only the true callers of *that* `Run`,
excludes callers confirmed to target a different method, and marks receivers it
could not type with a trailing `?`. The whole feature is FP-conservative: when the
receiver type or the target method is ambiguous, no edge is claimed (an honest `?`
beats a wrong exclusion). Schema bumps **v13 -> v14** (forces a full reparse; a
`call_edges` table is created automatically on the next index of an existing DB).

### Added

- **`call_edges` table (schema v14)** -- one row per resolved call site: `ref_id`
  (the call), `target_symbol_id` (the resolved callee), `confidence`
  (`certain`|`ambiguous`), `receiver_type_symbol_id` (the statically-known receiver
  type). Rebuilt from scratch on every index by the new resolution pass.
- **Typed local vars + params in the index** -- the parser now emits each routine's
  formal parameters (`skParam`) and local `var`s (`skLocalVar`) as symbols carrying
  their declared type, so a call-site receiver that is a param/local can be typed.
  (Numerous; shed on demand with `purge-locals`.)
- **`TCallResolver` receiver-typing engine** (`src/index/DRagLint.Index.CallResolver.pas`)
  -- types the receiver at each `X.M` site across kinds: bare/`Self`/`inherited`,
  field, property, typed local, param, and hard cast; resolves the type to a
  class/interface/record symbol (single in-scope or single global, else unresolved);
  walks the type + ancestor chain for `M`. Exactly one match -> `certain`; more than
  one -> `ambiguous`; unresolved/unknown -> no edge.
- **`ResolveCallTargets`** -- a whole-DB post-index pass (runs after `ResolveAncestry`)
  that populates `call_edges`.
- **Precise call-graph verbs:**
  - `query find-callers --name X --resolved` -- callers grouped by resolved target,
    each tagged `certain`/`ambiguous` (without `--resolved`, the old name-based list
    is unchanged).
  - `find-callees --qname X` -- the resolved outgoing calls of a routine.
  - `ambiguous-calls [--qname X | --file F]` -- resolver-coverage diagnostic: call
    sites that stayed `ambiguous` or untypable.
  - `call-path --from A --to B [--max-depth N]` -- shortest resolved call path (BFS).
  - `callgraph --qname X [--direction callers|callees] [--depth N]` -- an N-deep
    resolved call tree (cycle-safe).
  - `dump-call-edges --db X` -- diagnostic dump of the resolved edges.
- **`purge-locals --db X [--json]`** -- size escape hatch: deletes the local/param
  symbols and `VACUUM`s, while keeping `call_edges` (and every resolved query)
  byte-identical. Re-inflated on the next full index.

### Changed

- **AutoDocument "Called-from" is now resolved** (the bug fix): built from the
  resolved `call_edges` for the target symbol, not a name match. Certain callers of
  the target render plain; callers confirmed to target a different method are
  excluded; name-matching callers whose receiver could not be typed render with a
  trailing `?`. Idempotency preserved (file-name-only locations, no line numbers).
- **AutoDocument "Calls" facts prefer resolved qualified callees** -- a resolved
  outgoing call shows its qualified name (`Unit.TType.M`); the bare-identifier
  body-scan remains only for sites that did not resolve (nothing lost). Sorted for
  idempotent output.
- **`used-in` note:** `used-in` intentionally stays name-based (it counts type-name
  references, which are not call sites and not in `call_edges`).

### Migration

- Opening a v13 index with this build creates the `call_edges` table and stamps
  `schema_version = 14`; the next index populates the edges. No manual step needed.

## v0.90.0-alpha -- 2026-07-06

AutoDocument Chunk 1: generate and repair DocInsight doc-comments from what the
index already knows. This is the first slice of the AutoDocument track and the most
differentiated capability drag-lint has -- nobody else can auto-write DocInsight
from a symbol index. The core design is **managed regions**: drag-lint owns
sentinel-fenced parts of a `///` comment and regenerates them idempotently, while
everything outside those fences is hand-written and never touched. It never
fabricates prose -- a missing `<summary>` or `<param>` gets a `TODO: describe.`
marker, and every emitted fact is ground-truth from the index or the signature.
No index-schema change (still v13); the DB is opened read-only.

### Added
- **`document --qname <Foo.TBar.Baz> [--apply] [--json] [--no-backup] [--db PATH]`**
  CLI verb. Dry-run by default (prints the merged comment preview); `--apply` writes
  the comment above the declaration (+ a `.bak` unless `--no-backup`); `--json`
  emits `{qname, file, line, action, edits, applied}` with `action` in
  `created | extended | unchanged | not_found`. Exit 0 on ok/unchanged, 1 on
  not-found, 2 on usage. The legacy print-only `generate-docs` is unchanged.
- **Managed-region model.** A fenced facts block inside `<remarks>`
  (`<!-- drag-lint:auto BEGIN -->` .. `<!-- drag-lint:auto END -->`) carrying
  index-grounded facts: **Called from**, **Calls**, **Used in units**, **Raises**,
  and **Returns**. A list longer than 15 shows its top 10 + `(+N more)`. Auto-added
  `<param>` tags carry a `<!-- drag-lint:auto param -->` marker. Regeneration is
  idempotent -- a second `document` run on an up-to-date comment reports `unchanged`
  and makes zero edits (verified byte-identical).
- **Repair mode.** An existing comment's hand-written `<summary>`/`<param>`/`<remarks>`
  prose is preserved verbatim (multi-line remarks kept per-line); missing `<param>`
  tags are added, managed tags for deleted params are dropped, and a hand-typed
  `<param>` for a deleted param is flagged (never deleted).
- **IDE "Document it"** context-menu item on a symbol node in the Structure tab --
  spawns `document --qname --apply` against the project index and reloads the buffer.
- Three new focused units under `src/doc/`: `DRagLint.Doc.Facts` (index -> facts,
  no text), `DRagLint.Doc.Regions` (sentinel-fenced text manipulation, no index),
  `DRagLint.Doc.Document` (orchestrator -> `TArray<TTextEdit>`).

### Notes
- The outgoing **Calls** section is a bounded, best-effort body text-scan (an
  identifier immediately followed by `(`, lexer-skipping strings/comments) -- it may
  over-capture a few non-calls (e.g. `Create`, typecasts); the section is omittable
  and **Called from** is the solid headline.
- The `DocStub` signature helpers (`ExtractParamList`, `ParseParamNames`,
  `SignatureHasReturn`) are now exported (visibility move only; `generate-docs`
  unchanged).

## v0.89.0-alpha -- 2026-07-05

AutoFix Chunk 2: widen the fixable-rule set and close the deferred items. Chunk 1
proved the "Fix it" vertical slice on three rules; this release makes **six more
rules fixable** (three total -> nine), adds a **risky-fix tag** to contain the one
behaviour-changing fix, locks the already-correct batch-gating behaviour with a
test + docs, and closes two Minors. An exhaustive 163-rule sweep confirmed nine is
the full mechanically-safe set -- the other 154 rules are report-only detectors that
need type/flow/rename/restructure, so no rule-widening remains. No index-schema
change (still v13); no IDE code change (the catalog `fixable` flag, "Fix it" menu,
and auto-fix checkbox all light up automatically from the registry).

### Added
- **Six more fixable rules** (each = a `FIXABLE_RULE_IDS` entry + a
  `BuildAutofixEdits` branch + a fixture): `redundant-not-not` (`not not X` -> `X`),
  `redundant-as-tobject` (`X as TObject` -> `X`), `boolean-comparison-true`
  (`X = True`/`X <> False` -> `X`; `X = False`/`X <> True` -> `not X`, with a
  compound-operand paren guard so `(A and B) = False` -> `not (A and B)`),
  `reserved-word-casing` (lowercase the keyword), `redundant-assigned-free`
  (`if Assigned(X) then X.Free;` -> `X.Free;`, whole-word `then` match + single-line
  guard), and `off-by-one-count` (append ` - 1` to the loop bound -- see Risky).
- **Risky-fix tag.** `off-by-one-count` is behaviour-CHANGING (it assumes a
  `to List.Count do` loop is a bug). Its fix is still applied by `--fix`, but the
  `--fix --json` output flags it `"risky": true` and the text preview prints a
  `[risky]` note so a human/AI reviews before a batch apply. Backed by a new
  `RISKY_FIX_RULE_IDS` registry + `IsRiskyFixRule`.
- **`IsSingleTokenAtom` helper** -- decides whether `not X` needs parentheses;
  treats an already fully-parenthesized operand as atomic (no double-wrapping).

### Changed
- **Batch fix respects the active rule set (documented + tested).** `lint --fix`
  and `lint-all --fix` apply quick-fixes only for *enabled* rules: a rule disabled
  in `drag-lint-lint.json` (or via `--disable`) is filtered out before the fix stage,
  so its findings are neither reported nor fixed. This already held (findings pass
  the `ShouldKeep` config filter before the `--fix` block); it is now locked by a
  regression test and documented in `docs/AI-USAGE.md`.

### Fixed
- **`--fix --json` `applied` is now per-finding.** It reflects whether an edit was
  actually produced for that finding (keyed by file|line|rule), not merely that
  `--apply` was passed -- a fixable-rule finding whose guard yields no edit, or a
  non-fixable finding targeted with `--apply`, now correctly reports `applied: false`.
- **`--fix --format sarif`** no longer silently falls back to text: it prints a
  clear stderr note (`--fix does not support SARIF output; using text output.`) and
  proceeds. Non-breaking.
- **Registry desync** -- `redundant-as-tobject` and `boolean-comparison-true` had
  fix branches but were missing from `FIXABLE_RULE_IDS`, so `rules --json` reported
  them `fixable: false` and the IDE "Fix it" menu would not offer them. Both are now
  registered (caught by the fixable-catalog test before release).

## v0.88.0-alpha -- 2026-07-05

AutoFix Chunk 1: the full "Fix it" vertical slice. drag-lint could already detect
lint problems and apply a whole-file `--fix` for three rules; now a single finding,
a unit, or a whole project can be fixed from the CLI (with `--json` for AI
orchestration) or from the IDE via a context menu, and the rule catalog advertises
which rules are fixable. Proven end-to-end on the three existing fixable rules
(`self-assignment`, `redundant-parentheses`, `redundant-cast`); widening the set is
a later chunk. No index-schema change (still v13).

### Added
- **Queryable fix registry.** The fixable-rule set (`self-assignment`,
  `redundant-parentheses`, `redundant-cast`) is now a single source of truth
  (`FIXABLE_RULE_IDS` + `IsFixableRule`) that both the catalog and the fixer read
  from; `BuildAutofixEdits` behaviour is byte-identical.
- **`fixable` flag in the rule catalog.** `rules --json` now emits
  `"fixable": true|false` per rule -- the one field that drives every downstream UI
  decision (which rules show a "Fix it" item and an auto-fix checkbox).
- **Single-finding fix.** `lint --file F --fix --fix-line L --fix-rule R [--apply|--json|--no-backup]`
  fixes exactly the finding at `(L, R)`. `--json` emits one object per targeted
  finding (`file, line, rule, fixable, applied, preview`) so an AI orchestrator can
  drive fixes token-free, bounded by the safe-fix registry. With no targeting flags,
  `--fix` behaves exactly as before (whole file).
- **Whole-unit and whole-project fix.** `lint <F> --fix --apply` fixes every fixable
  finding in a unit; `lint-all --fix --apply` fixes across every indexed unit and
  reports `applied N fix(es) across M file(s)`, `--json` aggregating per file.
- **IDE: "Fix it" / "Fix all" on the Diagnostics tree.** A context-sensitive popup:
  right-click a fixable finding -> **Fix it** (strips the issue, reloads the buffer,
  writes a `.bak`); right-click the **Diagnostics** root -> **Fix all in unit** /
  **Fix all in project**. Non-fixable findings grey the item. The buffer reload uses
  the deferred `ForceQueue` + `IOTAModule.Refresh` pattern.
- **IDE: per-rule "auto-fix" checkbox in Lint Options.** Every fixable rule gains a
  second **auto-fix** checkbox that round-trips an `"autofix"` array in the project's
  `drag-lint-lint.json` (new `FAutoFix` id-array in `TLintConfig`). (Gating "Fix all"
  by the active rule set lands in the next chunk.)

### Fixed
- **`lint` honours `--file` as a path alias.** `lint` previously read its target only
  positionally; it now accepts `--file <F>` (positional still wins if both are given),
  so the IDE's `lint --file ... --fix` command and the documented contract work.
- **`BuildAutofixEdits` doc-comment** now lists all three fixable rules (was missing
  `redundant-cast`).

## v0.87.0-alpha -- 2026-07-05

forms-csv navigation v4: the plan-editor form family that a tester reaches through the
`frmControlPlan2` **Plan** button -- but that static call-graph fan-in could not follow --
now renders a real click-path instead of "(no path from MAIN)". Bundles two earlier
same-day forms-csv / live-lint fixes into a release. No index-schema change (still v13).

### Added
- **forms-csv v4 -- interface-dispatch + hook-registration navigation.** The plan-editor
  family (`Z14slctFrm`, `Z19slctFrm`, and ~18 `TxxxPlan.EditForm` editors) now resolves to
  `frmMAIN -> ... -> frmControlPlan2 -> 'Plan' -> <form>` on a COMMON-inclusive (full-tree)
  index. Three layers: **L1** -- polymorphic interface dispatch (`APlan.EditForm`) is bridged
  by the existing name-based caller walk (the `refs` row records the bare method name +
  enclosing form method, so no interface/heritage lookup is needed); **L2** -- the
  proc-variable hook (`PlanEditFormHook := ShowPlanEditor`), invisible to any `refs` query,
  is recovered by a bounded source text-scan of hook registrations plus a dead-end
  continuation that rejoins the interface walk (one hook hop; multi-hop chains stay
  "(no path)"); **L0** -- a stderr guardrail: when forms have callers but cannot trace to
  MAIN (the launch bodies live in COMMON, absent from a CLIENT-only db), forms-csv now emits
  a one-line note "run against the full-tree index" instead of silently printing "(no path)".
  `FORMS_CSV_ALGORITHM` bumped to `4`. All changes are in `DRagLint.FormsMap.pas`;
  navigation for forms already resolved by plain edges is unchanged.

### Fixed
- **forms-csv provenance footer schema version.** The footer read `PRAGMA user_version`
  (which the engine never writes), so a current v13 index always printed `schema v0`,
  misleading a user into thinking the index was stale. It now reads `schema_meta.value`
  (the value migrate actually writes); a v13 index prints `schema v13`.
- **forms-csv header/provenance layout** (bundled from earlier this day): the
  `# forms-csv algorithm v...` provenance line moved from the top to a padded footer so the
  column header is row 1 (spreadsheet-friendly); total line count unchanged.
- **live-lint `unit-name-matches-file` false positive** (bundled): the rule now skips
  `drag-lint-live-*` buffer-snapshot files, so it no longer fires on every unsaved edit in
  the IDE (it was flagging in-flight buffers whose synthetic name never matches the real unit).

## v0.86.0-alpha -- 2026-07-05

IDE robustness pass: the plugin now defaults to the Win64 CLI everywhere, the Structure tab survives CLI
preamble/stderr noise, ANSI/UTF-16 sources index instead of being skipped, and read-only verbs can no longer
mutate the shared index. No index-schema change (still v13).

### Fixed
- **IDE Win64-by-default:** every drag-lint process the IDE plugin spawns now defaults to the Win64 CLI (the
  32-bit BPL is the only 32-bit artifact); one shared resolver replaced ~11 ad-hoc ones that were silently
  running a stale Win32 exe.
- **Structure tab robustness:** the outline JSON is sliced out of any CLI preamble noise and stderr is captured
  on its own pipe, so the Structure tab no longer shows "Code Elements 0"; Diagnostics are now sorted by line.
- **ANSI/UTF-16 source ingest:** valid CP1252 / UTF-16 source files (e.g. a `resourcestring` with (R)/(C) high
  bytes, SOFTWID.PAS class) now transcode to UTF-8 at ingest and INDEX instead of being skipped with an
  encoding error; their string literals become text-searchable.
- **Read-only query verbs:** outline/query/find-unit/surface/context/dump-refs now open the index read-only
  (`PRAGMA query_only`), so a read-looking command can never mutate the shared DB -- this kills the Win32
  trigger-drop side effect (a read verb was dropping the text-search sync triggers) and any DDL-on-read.
  Stale-schema DBs now get an actionable "run drag-lint index ... to migrate" message instead of a field error.

## v0.85.0-alpha -- 2026-07-03

Extract Method: the first refactoring-APPLY transformation with data-flow analysis behind it (the CFG
**liveness** pass this milestone built is reusable for future refactorings). No index-schema change (still v13).

### Added
- `extract-method` CLI verb (`--file --from-line --to-line --name`, `[--dry-run|--apply|--json|--no-backup]`,
  dry-run default) -- extracts a contiguous statement range in a single file into a new routine. v1 scope: value
  in-params + a single `Result` output. Refuses (exit 2, reason on stderr) on: 2+ escaping outputs, a
  conditionally-assigned escaping variable, escaping control flow (`Exit`/`goto`/a `Break`/`Continue` that would
  escape the extracted block), a selection that cuts a statement / crosses nesting / contains same-line
  multi-statements, an unknown parameter type, a name collision, a missing class `private` section, multi-var
  declaration lines for internal locals, and `with`/`asm`/`goto` routines.
- IDE **Ctrl+Alt+M** -- selection -> preview dialog -> apply -> reload, wired the same way as the other refactor
  keybindings. Manual IDE smoke verified 2026-07-05 (after a reload-mechanism fix: deferred `IOTAModule.Refresh`
  replaced `CloseModule`/`OpenModule`, which crashed the IDE when invoked from the active editor's key binding).
- `DRagLint.Analysis.Liveness.pas` -- new reusable analysis unit (`LiveAfterItem`/`LiveBeforeItem` boundary
  queries) built for Extract Method's variable classification (in/out/internal); the general-CFG liveness pass is
  intended to be reused by future refactorings (e.g. Split Variable apply, Inline Variable).

### Fixed
- A latent `VarUsedOutsideRun` no-op found en route while building the liveness pass.
- `drag-lint.dproj` was missing a `DCC_UnitSearchPath` entry, a gap surfaced while wiring the new analysis unit.

### Also since v0.83.0-alpha
- **v0.83.1-alpha** (hotfix, not separately released on GitHub) -- fixed the v13 migration being unreachable on
  any pre-v13 database (see below).
- **v0.84.0-alpha** (not separately released on GitHub) -- forms-csv Navigation column algorithm v3, interleaving
  the landing form's name into the click path (see below).

## v0.84.0-alpha -- 2026-07-03

### Changed
- **forms-csv Navigation column (algorithm v3)** -- the click path now interleaves the landing form's
  name after every button caption and ends with the target form, e.g.
  `frmMAIN -> 'Job List' -> frmJobList -> 'Open Folder' -> frmBlueprint4 -> 'Exit to Control Plan 2'
  -> frmControlPlan2 -> 'Plan' -> Z14slctFrm` -- a tester can now tell WHICH form each button is
  pressed on. Rendering is isolated in one `RenderPath` function for future format changes
  (e.g. tester sentences). Called From column unchanged. CSV provenance header reports `algorithm v3`.

## v0.83.1-alpha -- 2026-07-03

Hotfix: the v13 migration was unreachable on any pre-v13 database.

### Fixed
- **Migration abort on every pre-v13 DB** -- `CREATE INDEX idx_refs_enclosing ON refs(enclosing_symbol_id)` sat in the
  core `SCHEMA_DDL` array, which runs BEFORE the `Migrate()` ALTER that retrofits the column onto old refs tables
  (`CREATE TABLE IF NOT EXISTS` never reshapes an existing table). Result: EVERY command that opens a v12-or-older index
  (`index`, `forms-csv`, `lint-all`, ...) died with `no such column: enclosing_symbol_id` instead of migrating -- old DBs
  could not self-heal. Seen in the wild via the IDE plugin's "Forms CSV" menu on a v12 per-project DB. The index is now
  created only in `Migrate()` after its ALTER (its sole creation site, matching the v9/v11/v12 retrofit pattern), and
  `SCHEMA_DDL` carries an INVARIANT comment forbidding statements that reference retrofitted columns. No schema bump
  (still v13); fresh DBs are byte-identical.
- **Stale forms-csv smoke checks** -- `tests/autotest/run_formsmap.ps1` still encoded pre-v2 output (no provenance
  header line; `frmList` required first in Called From, predating standalone-function call-site detection). Updated to
  the intended v2 behavior; the suite is green again.

### Added
- `tests/autotest/run_migrate_v12.ps1` -- regression harness: builds a v12-shaped index (refs without
  `enclosing_symbol_id`), then asserts `index` and `forms-csv` migrate it transparently (column added, `schema_version`
  stamped 13, `idx_refs_enclosing` created) and exit 0.

## v0.83.0-alpha -- 2026-07-03

Two new OFF-by-default refactoring rules deepening flow + CQS coverage. No index-schema change (still v13); ships as a
full release. Both rules were built and verified on an autonomous fork, then reviewed before merge.

### Added -- rules (all OFF-by-default; opt in via `drag-lint-lint.json` `"enabled"` or `--rule`)
- `split-variable` (category `refactoring`, `info`, **OFF**) -- a local reused for two unrelated purposes: it has >=2
  DISJOINT def-use lifetimes where the earlier range is def+read AND a later whole-var def starts a second range that is
  also read (distinct from `overwrite-before-read`, whose first store is never read). Flow-based (backward liveness +
  forward read-since-def sweep). Restricted to LINEAR routines (bails on any branch/merge) to stay sound without a
  per-path lattice -- conservative, never a false positive. src/ FP=0 (10 genuine findings across 3 files).
- `separate-query-from-modifier` (category `refactoring`, `info`, **OFF**) -- a value-returning function that also mutates
  observable state (Command-Query Separation violation, Fowler). Conservative mutation predicate: a write to a class
  field (`Self.X := ...` or a bare `F`-prefixed identifier that is not a local/param). Only value-returning functions are
  considered (naturally excludes constructors, destructors, setter procedures). Pure-AST, fires once per function at its
  header. Inherently noisy in general (lazy-caching getters, fluent mutators) -> ships OFF. src/ FP=0 (3 genuine findings).

### Notes
- `object-leak` OwnsOracle enhancement (a candidate v0.83 item) was investigated and DEFERRED as an empirical no-op:
  `object-leak`'s "created" flag is purely syntactic (`ExprIsConstructor`), not gated on a type-ownership oracle, so it
  ALREADY catches `TFileStream`/`TMemoryStream`/`TBitmap` leaks. The ON rule was left untouched. Probe table in
  `docs/lint/DEFER-v083-object-leak-ownsoracle.md`.

## v0.82.0-alpha -- 2026-07-02

Reference-index `enclosing_symbol_id` attribution (schema v13) + three new OFF-by-default rules + a coupling-metric
retrofit. Resumes the `-alpha` suffix (the index schema is still evolving); shipped as a full release.

### Index / schema (v13)
- `refs.enclosing_symbol_id` -- every indexed reference is now attributed to the innermost enclosing routine (by
  `impl_start_line..impl_end_line` containment), computed per-file in the indexer. Additive migration
  (`ALTER TABLE refs ADD COLUMN enclosing_symbol_id`), NULL-safe (reads as 0) on un-reindexed DBs.
  **Reindex all DBs once** after upgrading to populate it. New `drag-lint dump-refs <file> --db` diagnostic surfaces
  the attribution (`name_text|start_line|enclosing_symbol_id|enclosing_symbol_name`).

### Added -- rules (all OFF-by-default; opt in via `drag-lint-lint.json` `"enabled"` or `--rule`)
- `feature-envy` (#14, category `refactoring`, `info`, **OFF**) -- a method that references another class's members more
  than its own class's (`maxForeign > own` and `maxForeign >= minAccess`, default 3). Groups the class's `call` refs by
  the new enclosing attribution, then splits own/foreign via a name-based member->declaring-class map (names declared by
  >1 class are skipped). Target-class resolution is name-based (no expression type inference) -> precision is bounded ->
  ships OFF. src/ FP=36 (dominated by RTL name collisions, e.g. a project `Format` method vs `SysUtils.Format`).
- `instability` (#11, category `metrics`, `info`, **OFF**) -- CK instability `I = Ce/(Ca+Ce)`; flags a class when its
  instability percent `>= instability` (default 80) AND `Ca+Ce >= instability-floor` (default 5). Pure integer arithmetic
  on CBO (Ce, efferent) + fan-in (Ca, afferent).
- `interface-object-mixing` (#4 first cut, category `resource-lifetime`, `info`, **OFF**) -- a same-routine dual handle:
  an object local aliased into an interface-typed variable AND manually `Free`d/`FreeAndNil`'d in the same routine -- the
  ARC/manual double-free hazard. Pure-AST, narrow same-routine slice (reuses the `freeandnil-on-interface` type map).
  src/ FP=0.

### Changed -- coupling metrics
- CBO / RFC / fan-in / fan-out now read `enclosing_symbol_id` for exact reference attribution instead of a per-ref
  line-range scan (more precise for nested procedures / overlapping spans, and cheaper). Guardrail: findings are
  byte-identical on a full src/ sanity run. `LCOM4` is unchanged (it is an AST identifier re-walk, not ref-attribution).

### Fixed (v0.81 review carry-overs)
- `default-encoding-io`: a filename string literal that merely contains the text "TEncoding" no longer falsely suppresses
  the finding (string-literal argument nodes are skipped in the encoding scan).
- Exit code is derived from the post-suppression survivor set, so a bare command whose only matches were OFF-by-default
  rules now prints "0 finding(s)" AND exits 0 -- consistently across `lint` / `lint-all` / `lint-project`.

## v0.81.0 -- 2026-07-02

Portability + architecture "tail" rules. All three new rules ship **OFF-by-default** (opt in via
`drag-lint-lint.json` `"enabled"` or `--rule`).

### Added -- portability (category `platform`)
- `default-encoding-io` (#9, `warning`, **OFF**) -- file I/O that uses the default (ANSI/locale) encoding where an
  explicit `TEncoding` should be passed (a Win64/Unicode data-corruption hazard): `TStrings/TStringList.LoadFromFile`/
  `SaveToFile`, `TFile.ReadAllText`/`WriteAllText`/`ReadAllLines`/`AppendAllText`, and `TStreamReader`/`TStreamWriter.Create`
  called with no `TEncoding` argument. Pure-AST (a twin of `insecure-temp-file`). OFF-by-default: src/ FP=65 across 16
  files (dominated by intentional `ReadAllText` on config/project files).

### Added -- architecture coupling metrics (category `metrics`)
- `fan-out` (efferent coupling Ce, `info`, **OFF**) -- a class that depends on more than the threshold of other classes.
  Reuses the CBO computation, so it intentionally mirrors `high-coupling`; it ships OFF-by-default (opt-in) to avoid
  double-firing with the ON `high-coupling` in default output, for users who prefer the fan-in/fan-out framing.
- `fan-in` (afferent coupling Ca, `info`, **OFF**) -- a class referenced by more than the threshold of OTHER classes (a
  widely-depended-on hub whose changes ripple widely). A new whole-project reverse-aggregation over `type_use` references
  (inverts CBO's efferent set, deduped per source, excluding self + transitive ancestors). Default threshold 20 (needs
  field tuning; ships OFF). Name-based like CBO -- a class name shared across units can over-count (documented).

### Deferred (planned for v0.82, needs the indexer/flow work)
- `#4 interface/object mixing`, CK `instability` (`Ce/(Ca+Ce)` -- needs a range-based flag shape), and `feature-envy`
  are deferred to v0.82. feature-envy specifically needs a new `enclosing_symbol_id` on the reference index (references
  currently have no enclosing-method attribution), which will also sharpen CBO/RFC/LCOM and enable method-level
  find-callers.

## v0.80.0 -- 2026-07-02

**First full (non-pre-release) build.** v0.71-v0.79 were `-alpha` pre-releases; v0.80.0 graduates off the
alpha suffix. The project is still pre-1.0 (expect breaking changes until v1.0), but published releases are
now marked as full releases rather than pre-releases.

### Added -- store-backed refactoring signals (category `refactoring`, all OFF-by-default)
- `mutable-global-variable` (Global Data, `info`, **OFF by default**) -- a writable unit-level global `var`
  (generalizes `global-form-variable` to any type, not just form classes). Pure-AST: unit-scope `declVars`
  only, procedure-locals and `const`/typed-const excluded. src/ FP=68 across 27 files (mostly legitimate
  `G`-prefixed singletons) -> OFF; opt in via `"enabled": ["mutable-global-variable"]` or `--rule`.
- `repeated-type-switch` (Replace Conditional with Polymorphism, `info`, **OFF by default**) -- the same
  `case` selector text appearing across **3+ distinct methods** (a polymorphism candidate). Project-wide
  (`lint-all`/`lint-project`); groups normalized selector text across enclosing methods, one finding per
  occurrence, deterministic ordering. Name-based, so unrelated classes sharing a selector name can group
  (a documented false-positive) -> OFF; opt in. src/ FP=4 (all shared param-name collisions).
- `middle-man` (Remove Middle Man, `info`, **OFF by default**) -- a class with 3+ body methods where **more
  than half** are pure one-line delegations to the **same** declared field (`Result := FImpl.X(...)` /
  `FImpl.Y;`). Store-backed per class, reuses the LCOM4 method-body walk; target is restricted to declared
  fields (`Self`/locals/params/globals excluded) to cut noise. Documented false-negatives: only
  single-statement `Result:=`/bare-void bodies, only declared-field targets. src/ FP=0, but facades/wrappers
  are legitimate middle-men -> OFF; opt in.

### Fixed
- `lint-project` now filters its output through the shared config/`ShouldKeep` path (`FinalizeAndOutput`), so
  an OFF-by-default project rule (e.g. `repeated-type-switch`) no longer leaks into a bare `lint-project`
  run. ON-by-default project rules are unaffected. (Side effect: `lint-project --json` is now pretty-printed
  to match `lint-all`; field names/order are unchanged.)

### Changed -- v0.79 review cleanups
- `double-free`: the `warning` (definite) branch now reads "Object X **is** freed twice" while the `info`
  (possible) branch keeps "may be freed twice" -- the two severities no longer share one message string.
- `magic-literal`: numeric literals inside a **compound const initializer** (e.g. `const K = 60*1000;`) are
  now exempt via a bounded, null-safe parent walk (previously only a direct `defaultValue` parent was exempt).
- `not-assigned-interface`: added fixtures exercising the `X as T` deref and multi-hop `X.A.B` chain paths.
- Flow-engine tests: renamed the misleading `TestFreedStateReassignClears` to
  `TestFreedStateReassignThenFreeEndsDangling` and added a genuine reassign-clears test.

### Deferred
- `feature-envy` (Move Function, #14) is **deferred to v0.81**. A scout confirmed the symbol store cannot
  attribute a reference to its enclosing **method** (references have no enclosing-method column, and
  `FindContainingSymbol` keys on the declaration span, not the implementation-body span), so per-method
  cross-class member-access attribution can't be done at an acceptable false-positive rate without
  expression-level type inference. See `docs/lint/MISSING-FEATURES.md` section 14.

## v0.79.0-alpha -- 2026-07-02

### Added -- data-flow (M2) rules
- `not-assigned-interface` (#4 nullability, `warning`, ON) -- an interface-typed local
  **dereferenced** (`X.Method` / `X as T`) on a path where it was never assigned -> a nil-interface
  call (EAccessViolation/EInvalidCast). Reuses the M2 definite-assignment lattice for the interface
  subset that `used-before-assignment` skips; `warning` when unassigned on all paths, `info` on some.
  **Known limitation:** the short-circuit heuristic that keeps `if Supports(X, IFoo) and X.M then`
  quiet also suppresses a deref of any var passed as an argument to an earlier `and`/`or` operand's
  call (not just `out`/`var` params), so a genuine nil-deref guarded that way is a (safe-direction)
  false-negative -- tightening it needs callee parameter-mode resolution (a store).
- `double-free` (#5, `warning`, ON) -- `X.Free` reachable twice on a path with no reassignment and no
  nil-ing between (frees a dangling pointer). New forward `TFreedState` data-flow lattice; a raw
  `X.Free` leaves the var dangling while `FreeAndNil(X)`/`X.DisposeOf` clears it, so `FreeAndNil` then
  `Free` is correctly silent. `warning` when double-freed on all paths, `info` on some. Name-based
  (aliased frees `Y := X; X.Free; Y.Free` are a documented false-negative).

### Added -- Fowler refactoring-catalog signals (new category `refactoring`)
- `message-chain` (Hide Delegate, `hint`, ON, `threshold` default 4) -- a member-access chain
  `a.b.c.d...` longer than the threshold. Qualified type/unit names are excluded structurally.
- `magic-literal` (Replace Magic Literal, `hint`, **OFF by default**) -- an unexplained numeric literal
  (not `0`/`1`/`-1`/`2`, not in a const/enum/case/range/initializer context). Opt in via `"enabled"`.
- `boolean-flag-parameter` (Remove Flag Argument, `hint`, **OFF by default**) -- a `Boolean` parameter
  that drives an `if`/`case`/`while` condition in the body (selects behavior). Skips overrides + Sender handlers.
- `public-writable-field` (Encapsulate Variable, `info`, **OFF by default**) -- a `public` instance field
  of a class (expose via a property). Excludes `published` (DFM components) and records.
- `loop-control-flag` (Replace Control Flag with Break, `hint`, **OFF by default**) -- a `while`/`repeat`
  whose exit is driven by a Boolean flag assigned `True`/`False` in the loop body.

### Changed
- Cleanup: removed an unused dictionary in the LCOM4 metric; grouped the `metrics` catalog block after
  the `project-wide` rules. Added a DIT cycle-guard store fixture.

## v0.78.0-alpha -- 2026-07-02

### Added
- CK class metrics (#6): `deep-inheritance` (DIT), `too-many-children` (NOC),
  `high-coupling` (CBO), `high-response` (RFC), `low-cohesion` (LCOM4). Store-backed,
  project-wide (lint-all / lint-project), ON by default, category `metrics`,
  configurable `threshold` per rule. LCOM shipped as LCOM4 (connected components).
  Known limits: DIT undercounts without the RTL/library index (external parents
  count as one hop); resolution is name-based; CBO is efferent (type-use) only.
  `low-cohesion` defaults high (`threshold` 26, vs 6-50 for its siblings) on
  purpose: OTA/NTA interface-implementer classes and stateless `class function`
  utility/facade classes structurally maximize LCOM4 without being genuine
  god-classes, so a low default is pure noise on idiomatic Delphi -- lower it if
  your codebase does not lean on those idioms.

## v0.77.0-alpha -- 2026-07-02

- feat(lint): `duplicate-code` (#6) -- Type-2 (renamed-identifier tolerant) clone detection, within-file and cross-file (lint-all), via Rabin-Karp maximal-match with coverage-based overlap suppression. `info`, ON by default, `threshold` (min normalized tokens) default 90 (catches a copy-pasted ~12-line routine, ~96 tokens).
- feat(lsp): the IDE (LSP) diagnostic path now surfaces `duplicate-code` and honors an up-tree lint config (`drag-lint-lint.json` / `drag-lint.json`) for rule enable/disable + severity overrides -- previously the LSP ignored all config, so noisy rules could not be silenced in the editor. Syntax errors + compiler findings are always shown.

## v0.76.0-alpha -- 2026-07-01

Closes the last pure-AST loose ends and adds the first cheap store/graph-backed
rules on a new store-fixture test harness.

### Test infrastructure

- **`tests/lint-store/` store-fixture harness** (`run_store_tests.ps1`) -- indexes
  each case directory into a throwaway SQLite store, then runs the store-bearing
  check path (`check-ast --db` per file, or `lint-all --db` for the whole project)
  and compares against an `expected.txt` directive file. This unblocks testing
  store / uses-graph rules that the file-only `lint <file>` harness cannot exercise.

### Added -- security (MISSING-FEATURES #10)

- **`dfm-hardcoded-credential`** (`warning`) -- a credential-named DFM property
  (`Password`, `Pwd`, `Secret`, `ApiKey`, `PrivateKey`, `Passphrase`) assigned a
  non-empty string literal in a form resource. Secrets in a `.dfm` ship in the exe
  and land in source control.
- **`insecure-temp-file`** (`warning`) -- a file read/write API (`SaveToFile`,
  `LoadFromFile`, `WriteAllText`, `TFileStream.Create`, ...) called with a
  hardcoded temp path (`C:\Temp\`, `\Temp\`, `/tmp/`, `\Windows\Temp`). Predictable,
  world-readable location prone to races/symlink attacks.

### Added -- resource / memory (MISSING-FEATURES #5)

- **`abstract-method-instantiation`** (`warning`, store-backed) -- `TFoo.Create`
  where `TFoo` or a class ancestor declares an abstract method (a virtual method
  with no body) that no class in the hierarchy overrides -- instantiating it and
  calling that method raises `EAbstractError` (compiler W1020). Resolves methods +
  ancestors across units via the symbol store.

### Added -- platform / portability (MISSING-FEATURES #9)

- **`nativeint-truncation`** (`warning`) -- a 32-bit cast (`Integer`, `Cardinal`,
  `LongInt`, `LongWord`) of a `NativeInt`/`NativeUInt`/`IntPtr`/`UIntPtr`/`PtrInt`/
  `PtrUInt` value truncates the high 32 bits on Win64. Sibling of
  `win64-pointer-cast` (which fires on true pointer types).

### Added -- architecture (MISSING-FEATURES #11)

- **`circular-uses`** (`warning`, store-backed) -- a strongly-connected component
  of the unit uses-graph (a set of units that transitively use each other). Tarjan
  SCC over the store's uses edges; one finding per cycle, anchored at the
  alphabetically-first unit with the full member list. Distinct from
  `interface-reference-cycle` (interface-section symbol references).

### Added -- style (MISSING-FEATURES #2)

- **`multiple-statements-per-line`** (`hint`, **off by default**) -- two or more
  statements sharing one source line (`a := 1; b := 2;`). One finding per line.
  Opt in via `"enabled"` / `--rule` (pure style; noisy on terse codebases).

### Deferred

- **DIT/CBO** and the rest of the CK metric suite (NOC/RFC/LCOM) are deferred to
  v0.77 so the class-metric rules ship together; a project-only store lacks RTL
  ancestors, which limits DIT signal in isolation.
- **`variant-record-type-punning`**, **`double-free`**, **nullability**, and
  **clone/duplicate-code detection** remain for later (need M2 flow / a dedicated
  clone engine).

## v0.75.0-alpha -- 2026-07-01

### Added -- type-system / casts (MISSING-FEATURES #4)

- **`lossy-cast`** (`info`) -- an Ansi-narrowing cast (`AnsiString`, `AnsiChar`,
  `ShortString`, `RawByteString`) of a Unicode-string operand drops characters
  outside the active code page (compiler W1057).

### Added -- resource / memory (MISSING-FEATURES #5)

- **`create-inside-try`** (`warning`) -- a `try..finally` whose first protected
  statement is `X := TFoo.Create` -- if the constructor raises, the `finally`
  frees an undefined reference. Construct the object before the `try`. Handles
  both paren-less `TFoo.Create` and `TFoo.Create(...)`.

### Added -- complexity / metrics (MISSING-FEATURES #6)

- **`cognitive-complexity`** (`info`, threshold `25`) -- a SonarSource-style
  cognitive-complexity metric: each control-flow structure adds 1 + its nesting
  depth, and each `and`/`or`/`xor` adds 1. It rewards flat code and penalises deep
  nesting (unlike the flat cyclomatic count). Default 25 (cognitive scores higher
  than cyclomatic); configurable via `"thresholds"`.

### Added -- security (MISSING-FEATURES #10)

- **`weak-random-for-security`** (`warning`) -- a security-named variable
  (token/password/secret/salt/nonce/apikey/...) assigned from `System.Random` /
  `RandomRange`, which is not cryptographically secure. Use a CSPRNG for tokens,
  keys, and salts.

## v0.74.0-alpha -- 2026-07-01

### Added -- type-system / casts (MISSING-FEATURES #4)

- **`exhaustive-enum-case`** (`warning`, **OFF by default**) -- a `case` on an
  enum-typed selector that omits some members and has no `else` silently ignores
  them (and any member added to the enum later). Enum members are resolved from a
  same-file map (built from `declEnum`/`declEnumValue`, so it works with no `--db`)
  or, cross-unit, from the symbol store (`skEnum` -> its `skEnumValue` children).
  Bails on a range label (can't expand without ordinals). Ships OFF because a case
  that intentionally handles a subset with no `else` is common; opt in via
  `drag-lint-lint.json` `"enabled": ["exhaustive-enum-case"]` or `--rule` -- built
  for enum-heavy codebases.

### Added -- complexity / metrics (MISSING-FEATURES #6)

- **`unit-too-large`** (`info`, threshold `2000`) -- flags a unit exceeding N
  source lines. Configurable via `"thresholds": { "unit-too-large": N }`.

### Notes

- `exhaustive-enum-case` is the first store-aware lint rule that also works purely
  from a single file's AST (same-file enums) -- so it is exercised by the file-only
  test harness while still resolving cross-unit enums when a store is present.
- Still deferred in #4: lossy Ansi<->Unicode casts and nullability (flow/type
  analysis); in #6: cognitive complexity, the CK suite, and clone detection.

## v0.73.0-alpha -- 2026-07-01

### Added -- control-flow / expression (MISSING-FEATURES #8)

- **`repeated-else-if-condition`** (`warning`) -- the same condition text repeats
  in one `if` / `else if` chain, so the later branch is unreachable. The chain is
  walked from its top via the `else` field, comparing normalised condition text
  case-insensitively.
- **`property-references-itself`** (`warning`) -- a property whose `read`/`write`
  accessor is the property itself, which recurses forever. Detected by counting
  identifiers in the `declProp` that match the property name (excluding the name
  node and the type), so it needs no accessor-field knowledge.

Both pure-AST, on by default, 0 findings over the `src/` sanity sweep. Closes #8's
pure-AST items.

## v0.72.0-alpha -- 2026-07-01

### Added -- resource / memory (MISSING-FEATURES #5)

- **`destructor-without-override`** (`warning`) -- a class-declaration destructor
  that carries no `virtual`/`dynamic`/`override`/`abstract` directive hides the
  inherited virtual `Destroy` (objects leak). Flags the declaration only (a
  `class destructor` and the implementation signature are excluded).

### Added -- complexity / metrics (MISSING-FEATURES #6)

- **`case-with-too-few-branches`** (`hint`, threshold `2`) -- a `case` with fewer
  than N branches reads better as an `if`. Counts `caseCase` arms (an `else` is
  not one). Configurable via `"thresholds": { "case-with-too-few-branches": N }`.
- **`boolean-expression-complexity`** (`info`, threshold `4`) -- a boolean
  expression with more than N `and`/`or`/`xor` operators is hard to read; flagged
  once at the top of the operator chain. Configurable threshold.

### Added -- exceptions (MISSING-FEATURES #7)

- **`exception-constructed-but-not-raised`** (`warning`) -- a bare-statement
  `E...Create(...)` (an exception-looking class constructed as a statement) with
  no `raise` -- a common forgotten-`raise` bug. A raised call is the `raise`
  node's operand, so it is not flagged; an assigned one is not a bare statement.
- **`duplicate-exception-handler`** (`warning`) -- two `on <Class>` handlers for
  the same class in one `try`'s `except` -- the second is unreachable. Scoped to a
  single `try` (nested `try` handlers are its own).

### Notes

- All five are pure-AST, on by default. FP-sanity over `src/` (101 files): four
  produce 0 findings; `boolean-expression-complexity` produces 26, all legitimate
  complex expressions (5-64 operators) at `info` severity with a configurable limit.

## v0.71.0-alpha -- 2026-07-01

### Added -- autofix subsystem (MISSING-FEATURES #12)

- **`drag-lint lint <file> --fix [--apply]`** (and `lint-all`) -- a quick-fix
  engine. Dry-run by default: it prints the edits it *would* make; `--apply`
  writes them, backing each file up to `<file>.bak` first (`--no-backup` to
  skip). Built on a new `tekReplaceInLine` char-range text-edit primitive.
  Seed fixes: **`self-assignment`** (delete the line), **`redundant-parentheses`**
  (strip the outer parens), and **`redundant-cast`** (`TFoo(x)` -> `x`).

### Added -- cast rules (MISSING-FEATURES #4)

- **`redundant-cast`** (`hint`, on by default) -- flags a no-op hard cast
  `TFoo(x)` where `x` is already declared exactly `TFoo` (pure-AST, via a
  per-file type map). T-prefixed class-like target + single-identifier argument
  only, to avoid scalar-cast noise; near-zero false positives. Autofixable.
- **`unsafe-typecast-without-is`** (`warning`, **OFF by default**) -- flags a
  hard cast `TFoo(x)` of an object reference to a *different* class with no
  guarding `x is TFoo`. If `x` is not really a `TFoo` at run time the cast
  crashes or corrupts. Fires only when both target and operand are plausible
  class types (`x` declared `TObject` or a different `T`-class -- a genuine
  down/cross-cast); value/record casts (`TDateTime`/`TColor`/`TRect`...), the
  redundant same-type cast, `TObject` upcasts, and guarded casts are all
  skipped. Ships off because many unguarded casts are provably safe to the
  author (a src sweep found only event-handler `T...(Sender)` casts). Opt in via
  `drag-lint-lint.json` `"enabled": ["unsafe-typecast-without-is"]` or
  `--rule unsafe-typecast-without-is`.

### Added -- dead-code #2 tail (cont.)

- **`function-result-ignored`** (`hint`, **OFF by default**) -- flags a
  bare-statement call (a call used as a statement, result discarded) to a
  same-unit function (a routine declared with a return type). Opt in via
  `drag-lint-lint.json` `"enabled": ["function-result-ignored"]` or
  `--rule function-result-ignored`. It ships off because discarding a function
  result is common and usually intentional in Delphi (builder/adder/runner
  functions), so on real code it is dominated by false positives; a future
  store-backed, effect-aware pass could make it default-on.

### Deferred

- The remaining #4 cast rules (lossy Ansi<->Unicode, exhaustive enum-case,
  nullability) need the symbol store (member sets, exact cross-unit types) and
  cannot be exercised by the file-only lint harness -- deferred to a later
  store-backed pass. More `--fix` quick-fixes for `.scm`-defined rules
  (`redundant-not-not`, `boolean-comparison-true`) await an explicit fix-spec
  payload on the finding (span-surgery from message text is fragile).

## v0.70.0-alpha -- 2026-07-01

### Added (dead-code tail -- MISSING-FEATURES #2)

- **`redundant-parentheses`** (`hint`) -- flags an expression wrapped in
  redundant parentheses: nested `((X))` or a lone term `(X)` / `(1)`. Parens
  around a composite expression (binary, call, dotted access, ...) are kept.
  Const/var initializer and array/record constructor contexts are skipped --
  there a single-element `(x)` is a required constructor, not a redundant paren.
- **`commented-out-code`** (`hint`) -- flags a comment whose entire stripped
  text is a single Delphi statement: an anchored `lhs := rhs;` (bare lvalue
  path) or `idpath(...);`. Compiler directives (`{$...}`) and `///` doc comments
  are skipped; prose that merely quotes `:=` or a call inside a sentence is not
  flagged (that was the dominant false positive, tuned out against a src sanity).

### Changed (plugin -- Lint Options tab)

- Rule search moved onto its own row with a magnifier glyph + `Search` label.
- Profile switching no longer re-spawns `drag-lint rules --json`; it re-renders
  from the cached catalog (the rule set is static across profiles) -- noticeably
  faster.

### Deferred

- `function-result-ignored` (needs symbol-store type resolution; FP-prone as
  pure AST) and `multiple-statements-per-line` remain deferred -- see
  MISSING-FEATURES #2.

## v0.69.0-alpha -- 2026-07-01

### Added (naming -- D3, closes MISSING-FEATURES #1)

- **`reserved-word-casing`** (`info`, **on by default**) -- flags Pascal keyword
  tokens not written in lowercase (`Begin`/`VAR`/`And`). `True`/`False`/`nil` are
  convention-exempt; disable via `"keyword_case": ""`.
- **`hungarian-or-short-identifier`** (`info`, **off by default**) -- flags
  parameter/local names that are overly short (< `min_identifier_len`) or carry a
  Hungarian type prefix. Enable via `"short_identifier_check": true`. Loop counters
  `i`/`j`/`k`/`n`/`x`/`y` exempt.
- New `naming` config keys: `keyword_case`, `min_identifier_len`,
  `hungarian_prefixes`, `short_identifier_check`.

### Added (rule catalog -- D1a)

- **`drag-lint rules [--json] [--category <name>] [--rules-dir <dir>]`** -- a single
  machine-readable catalog of every rule (built-in + external `.scm`) with id,
  category, title, default severity, default-enabled, source, and parameters, plus
  per-category and total counts. New unit `DRagLint.Lint.RuleCatalog` holds the
  built-in registry; `.scm` rules are merged from their sidecar `.json`.

### Added (refactor CLI -- D2a)

- **`drag-lint rename --kind symbol --name <QName> --to <New>`** -- index-driven
  cross-unit rename. Dry-run preview by default; `--json` emits the edit set;
  `--apply` writes (backups on, `--no-backup` to suppress; ANSI/CRLF preserved).
  Refuses to rename to a reserved word or to a name already declared in the same scope.
- **`drag-lint rename --kind param --file <F> --line <L> --col <C> --to <New>`** --
  routine-local rename of a parameter or local variable (the `param-name-prefix`
  autofix). Single-file, AST-driven; syncs the matching forward/interface header;
  conservatively skips shadowing nested routines, qualified members (`exprDot`/`genericDot`),
  and `with` blocks.

### Added (refactor CLI -- D2b)

- **`drag-lint find-unit --name <Symbol> --in <file>`** -- add the unit that
  declares `<Symbol>` to `<file>`'s uses clause (implementation uses preferred).
  Dry-run default; `--json`; `--apply` (backups on, ANSI/CRLF preserved). No-op
  when the unit is already imported.
- **`drag-lint safe-delete --name <QName>`** -- delete a symbol's declaration
  (and implementation body, for a routine) ONLY when it has zero references
  (name-text check); refuses otherwise. Dry-run default; `--json`; `--apply`.
- New unit `DRagLint.Refactor.TextEdit` (range insert/delete applier) backs both.

### Added (IDE -- D1b)

- **"Lint Options" dock tab** (4th tab, next to Structure / Search / Find Usages)
  -- a VCL `TFrame` (`TLintOptionsFrame`) that shells out to `drag-lint rules
  --json` to load the rule catalog, then renders rules grouped by category. Each
  category has a tri-state header checkbox that toggles the whole group; each rule
  gets an individual checkbox plus inline param editors (`TSpinEdit` for int
  params, `TEdit` for string/naming params). A counts header shows `N rules across
  M categories, K enabled`. Reads and writes the active project's
  `drag-lint-lint.json` via the new pure serializer `TLintConfigWriter`
  (`DRagLint.Lint.ConfigWriter`). Every catalog param round-trips to the exact
  config location the linter reads (naming params -> the `naming` block,
  complexity thresholds -> the `thresholds` block, `min_identifier_len` ->
  `naming.min_identifier_len`). The CLI remains the consumer of record; the tab
  only edits the JSON. Completes v0.69 deliverable D1 (D1a shipped the `drag-lint
  rules --json` catalog; D1b is the IDE tab that consumes it).
- **Named profiles** -- the Lint Options tab manages a named-profile combo: profiles
  are stored in `drag-lint-lint.json` under a `profiles` key, each capturing the full
  settings snapshot (enabled/disabled rules, thresholds, naming params). The combo is
  editable (rename, add, delete); switching profiles instantly reloads the panel.
- **`drag-lint lint --profile <name>`** -- CLI flag that loads and applies a named
  profile's complete settings (enable/disable + thresholds + naming) before running,
  previously enable/disable only.
- **Live rule-search box** -- a filter input above the rule list; typing narrows the
  visible rules by id or title substring (case-insensitive, instant).
- New units: `TLintOptionsFrame` (`src\delphi-plugin\DragLint.Plugin.LintOptionsFrame.pas`),
  `TLintConfigWriter` (`src\lint\DRagLint.Lint.ConfigWriter.pas`).
- Note: IDE tab UI is compile-verified; final in-IDE click-test pending.

### Fixed

- The FireDAC `FTS5 probe` diagnostic now writes to stderr instead of stdout, so it
  no longer corrupts `--json` output from store-backed commands.

## v0.68.0-alpha -- 2026-06-30

Naming-convention wave (#1), dead/redundant-code tail (#2), and the final data-flow
item (#3). 12 new rules, all enabled by default. Naming rules are `info`; dead-code
and data-flow rules are `warning`.

### Added (naming conventions -- 7 rules, `info`, `lint <file>`)

All naming rules are config-driven via a new `naming` block in `drag-lint-lint.json`.
Built-in defaults follow common Delphi conventions; the rules are hardened against
frequent real-world patterns (see below). Tune the `naming` block per project.
Disable any individual check by setting its value to `""` (string) or `[]` (array)
in the config, or by listing the rule id under `disabled`.

**New `naming` config block** (shown with defaults):

```json
"naming": {
  "type_prefix":  { "class": "T", "exception": "E", "interface": "I", "pointer": "P" },
  "field_prefix": "F",
  "param_prefix": "",
  "method_case":  "PascalCase",
  "const_case":   ["PascalCase", "UPPER_CASE"],
  "local_case":   "PascalCase"
}
```

- **`type-name-prefix`** -- class type must start with `T`; interface with `I`; pointer
  type with `P`; exception class (ancestry reaches `Exception`) with `E`. The
  exception-class sub-check uses the M1 resolver when a symbol store is present; falls
  back to the `T` rule on the no-store `lint <file>` path (no guessing).
- **`field-name-prefix`** -- class instance field name must start with `F`. Published
  auto-generated DFM component fields on form/frame classes are skipped.
- **`param-name-prefix`** -- routine parameter name must start with the configured
  prefix. `Self` is always skipped. **Disabled by default** (`param_prefix: ""`);
  param-prefix conventions are project-specific (e.g. `"p"` for pFoo-style, `"A"` for
  Embarcadero-style). Set a non-empty prefix to enable.
- **`method-pascalcase`** -- method/routine name must be PascalCase.
- **`const-casing`** -- declared constant or enum member name must match one of
  `const_case` (default: `PascalCase` or `UPPER_CASE`).
- **`local-var-casing`** -- local variable name must be PascalCase and must not carry
  the field or param prefix (`FFoo`/`pFoo` in a local is a naming smell).
- **`unit-name-matches-file`** -- the `unit X;` identifier must equal the file's base
  name (case-insensitive on Windows). One finding per unit.

### Added (dead/redundant-code -- 3 AST rules + 1 data-flow rule, `warning`)

**Per-file (`lint <file>`) path:**

- **`unused-parameter`** -- a parameter never read in the routine body. Guards: skips
  parameters of `override` methods, interface-method implementations, event-handler
  signatures (e.g. `Sender: TObject`), message-method directives, and
  `assembler`/`external` bodies -- all of which must keep the parameter for signature
  compatibility. Also skips `out`/`var` parameters (caller-visible).
- **`identical-then-else`** -- an `if C then S1 else S2` where `S1` and `S2` are
  syntactically identical (normalized subtree text comparison). Flags real copy-paste
  bugs; the two branches always produce the same result regardless of `C`.
- **`referenced-never-set`** -- a `private`/`strict private` class field that has at
  least one read but zero writes anywhere in the declaring unit. The field always holds
  its zero value, making every read return a misleading default. Guards: skips
  `published` fields, form/frame/`TComponent`-streamed classes (DFM/RTTI streaming
  writes them invisibly), and fields initialized in their declaration.

**Store-backed (`lint-all --db` / `lint-project --db`) path:**

- **`unused-private-member`** -- a `private`/`strict private` method, field, const, or
  nested type with zero references in the symbol index. Mirrors `unused-public-symbol`
  but scoped to private visibility (lower false-positive rate -- privates cannot be
  used cross-unit). Guards: skips published fields and RTTI/`{$M+}`-streamed members.
- **`unused-unit-in-uses`** -- a unit in a `uses` clause none of whose exported symbols
  are referenced by the using unit. Conservative guard: skips units plausibly used only
  for operator overloads, class/record helpers, or `initialization`/`finalization`
  side effects; also skips a small allow-list of known side-effect units. Flags only
  when zero referenced symbols are affirmatively found.

### False-positive hardening

The rules include several guards that make them near-zero-FP on real Delphi, VCL, and
DevExpress code:

- **`type-name-prefix` / `field-name-prefix`**: accept the prefix followed by any
  letter, so `TfrmMain` (T + lowercase form convention), `FfID`, and DevExpress component
  types such as `TdxBarManager` / `TcxGrid` (T + lowercase) are recognized -- not flagged.
- **`field-name-prefix`**: auto-generated published DFM component fields on form/frame
  classes (the implicit-first section, any component type including DevExpress controls)
  are skipped entirely; only fields in explicit `private`/`protected`/`public` sections
  are checked.
- **`method-pascalcase` / `local-var-casing`**: short all-caps abbreviations (`OK`,
  `ID`, `GLE`, `FF`, length <= 4) are exempt from the PascalCase requirement.
- **`method-pascalcase`**: methods in a `published` or implicit-first section (form event
  handlers such as `btnOkClick`) are skipped.
- **`unused-parameter`**: VCL/FMX event handlers -- a routine whose first parameter is
  `Sender` -- are skipped entirely (all params are signature-bound); plus the existing
  override / interface / message / asm / external / var / out guards.
- **`unit-name-matches-file`**: basename comparison is path-separator-robust (handles
  both `/` and `\`).
- **`unused-private-member`**: property getter/setter accessors and read/write-clause
  backing fields are excluded -- a property's `read GetX write SetX` accessors are not
  flagged as unused even though the index does not link them via the property clause.

### Known limitations

- **`unused-private-member`**: the index does not track all intra-class private
  method-to-method calls, so a private method called only by another method of the same
  class may still be reported (a residual false positive, shared with
  `unused-public-symbol`).
- **`unused-unit-in-uses`**: near-zero-FP by construction (it only over-credits
  references, so it never flags a genuinely-used unit), but a unit used ONLY for
  operator overloads, class/record helpers, or `initialization`/`finalization` side
  effects without a referenced symbol may be flagged unless it is in the built-in
  side-effect allow-list (which is intentionally small). Expand the allow-list or
  disable per-project if needed.

### Notes

- All 12 rules flow through the v0.66 `FinalizeAndOutput` tail: severity remap,
  `disabled`/`enabled`, `--disable`, `--fail-on`, SARIF output, and baseline all apply
  without per-rule plumbing.
- Naming rules run on the `lint <file>` path. `unused-private-member` and
  `unused-unit-in-uses` run on the `lint-all --db` / `lint-project --db` path.
- Deferred (NON-GOALS for v0.68): `function-result-ignored`, `commented-out-code`,
  `redundant-parentheses`, `multiple-statements-per-line`.
- Harness: 112/112 fixtures green.

## v0.67.0-alpha -- 2026-06-29

Rule-accuracy fixes (false positives reported on real ORM3 code).

### Fixed
- **length-zero-compare** no longer fires on dynamic arrays. The `X = '' / X <> ''`
  suggestion is valid only for strings, so the rule is now type-aware: it fires
  only when the `Length()` argument resolves to a string type (exact via the symbol
  store on `check-ast --db` / `lint-all --db`; the intrinsic-string-type name
  heuristic via the per-file declaration map on the no-store `lint <file>` path).
  `Length(B)` where `B: TBytes` (or any array) is no longer flagged. Reimplemented
  as a built-in (`CheckTypeAware`); the broad `.scm` rule is removed. This also means
  `check-ast` now reports `length-zero-compare` (it previously skipped `.scm` rules).
- **string-equality-comparison** no longer fires on non-string operands on the
  no-store path: `.AsInteger` / `.AsLargeInt` / `.AsFloat` / `.AsBoolean` / `.AsBytes`
  and other non-string `TField` accessors, and enum-valued `.State`, are skipped
  (these are integer/enum comparisons, not case-sensitivity concerns). The precise
  store path was already type-exact; this guards the heuristic `.scm` path.
- Added TDD harness fixtures for both rules (string positive + array/accessor
  negatives) -- both rules were previously untested.

## v0.66.0-alpha -- 2026-06-29

The **M1 type/hierarchy resolver** and the **M2 data-flow / CFG engine** -- two
milestones bundled. M1 makes the existing heuristic rules exact when a symbol index
is present; M2 adds a per-routine control-flow + data-flow engine and seven new
flow-sensitive checks.

### Ergonomics / output (#12)
- `--format sarif`: SARIF 2.1.0 output for `lint`/`lint-all`/`check-ast` (GitHub code-scanning / CI ingestion).
- `--fail-on error|warning|info|none`: severity-gated process exit code.
- `drag-lint-lint.json` config (auto-discovered or `--config`): per-rule `severity` overrides, `disabled`/`enabled` lists, metric `thresholds`, and named `profiles`; `--enable`/`--disable`/`--profile` compose with it. `.scm` rules may ship off-by-default via sidecar `"enabled": false`.
- `--baseline`/`--write-baseline`: line-shift-stable baseline so legacy codebases report only NEW findings.
- All four flow through one shared `FinalizeAndOutput` tail; default (no-flag) behavior is unchanged. `check-ast` additionally gains `// drag-lint:ignore` suppression support.
- `lint-all --json` no longer writes the dated `lint-report-*.txt` file; JSON now goes to stdout only (the dated report file is still written in text mode) and is now pretty-printed (2-space indent), matching `lint --json`. Machine consumers should read stdout.
- Autofix / quick-fixes remain deferred (a milestone of their own).

### Added (M2 -- flow-sensitive analysis engine)
- **Per-routine CFG + monotone data-flow framework** -- new units
  `DRagLint.Analysis.Cfg` (control-flow graph builder), `DRagLint.Analysis.DataFlow`
  (generic `IDataFlowAnalysis<TValue>` + worklist solver), `DRagLint.Analysis.Flow.Lattices`
  (variable table + definite-assignment / liveness / escape analyses), and
  `DRagLint.Diagnostics.FlowChecks` (`TFlowChecker`). Verified by a console engine
  test suite (`tests/flowengine`).
- **7 new flow checks** (definite violation = `warning`, possible = `info`):
  - `used-before-assignment` -- an unmanaged local read before assignment.
  - `function-result-not-set` -- `Result` not assigned on every path.
  - `out-param-not-set` -- an `out` parameter not assigned on every path.
  - `overwrite-before-read` -- a dead store (assignment overwritten before any read).
  - `write-only-local` -- a local assigned but never read.
  - `loop-var-after-loop` -- a `for` control variable read after the loop (undefined).
  - `object-leak` -- a local object created but neither freed nor transferred on some
    path; store-free is conservative, and with an index it refines interprocedurally
    (a leak through a clearly non-owning unit proc surfaces).
- Managed types (`string`, interfaces, `Variant`, dynamic arrays) are skipped for
  definite-assignment (matching the compiler's W1036): a name heuristic without an
  index, **exact** via the M1 resolver when one is present.

### Added (M1 -- type / hierarchy resolver)
- Cross-unit heritage capture + ancestry resolution (`query ancestors`), broad type
  categorisation (`query typecat` -> `ResolveTypeCategory`, chasing `type X = Y`
  aliases), and method virtuality indexing. These make `float-equality-comparison`,
  `freeandnil-on-interface`, `win64-pointer-cast`, `string-equality-comparison`, and
  cross-unit `virtual-method-in-constructor` exact on the store-bearing paths
  (`lint-all`, `check-ast`); the bare `lint <file>` path keeps the heuristics.

### Notes
- Flow checks run on `lint <file>` (heuristic), and on `lint-all` / `check-ast --db`
  with index-backed precision. Existing per-file lint harness stays green.

## v0.65.1-alpha -- 2026-06-29

IDE plugin release: the **R2 background job queue + dock status bar**, plus **clickable
lint findings** in the Messages view -- and one CLI false-positive fix.

### Added (IDE plugin)
- **R2 background job queue** -- reindex / lint-all / forms-csv now run through one
  serialized worker thread, so they no longer collide on the project SQLite DB
  ("database is locked"). `forms-csv` no longer freezes the IDE (it was a synchronous
  UI-thread call). Duplicate enqueues coalesce by key; clean join-on-shutdown.
- **Dock status bar** -- a strip along the bottom of the drag-lint dock window shows the
  running job + live %, queue depth ("N queued"), the last result, and a **Cancel**
  button (clears pending jobs). New units `DragLint.Plugin.JobQueue` +
  `DragLint.Plugin.StatusBar`.
- **Clickable lint findings** -- Run Lint All posts each finding to the IDE **Messages**
  view as a tool message; double-click jumps to `file:line`. Capped at 2000/run so a
  huge project cannot flood the pane (the full list still opens as the report).

### Fixed
- **`float-equality-comparison` no longer fires on a quoted string/char literal operand**
  (e.g. `SS = '+'`, `SS = '-.'`). A quoted literal is never a float, so it now forces
  string context -- this guards against the flat (no-scope) type map mis-resolving a
  same-named variable to a float when another routine declares it `Double`. Regression
  fixture `float-equality-string-fp` (FP silent + a real `i = 0.0` still fires). Harness 79/79.
- Status bar no longer crashes dock creation ("control has no parent window"): layout
  moved out of the constructor into a `Resize` override, so no window handle is forced
  before the panel has a parent.

### Notes
The IDE plugin ships as the Win32 BPL in the repo (`third_party/dll-win32`). The release
zips are the CLI (one FP fix over v0.65.0).

---

## v0.65.0-alpha -- 2026-06-29

CLI-side false-positive fixes and internal tidies. The R2 IDE job queue + dock status
bar (Stream B) are being developed on a separate branch and will land in a later
prerelease after manual IDE testing.

### Fixed

**Project-membership false positives** (from the ORM3 field report,
`LINT-FALSE-POSITIVES-20260628.md` FP-8 / FP-9)
- **FP-8 `unit-not-in-dpr` mis-parsed the `.dpr`/`.dpk` uses clause.** Form-name hints
  (`uMain in 'uMain.pas' {frmMain}`) and compiler directives (`{$IFDEF}` / `{$ENDIF}`)
  were extracted as if they were unit names. The clause is now comment-scrubbed first
  (`{...}`, `(* *)`, `//`, string literals preserved) so only real `Ident` /
  `Ident in 'file.pas'` entries are treated as units. A stray `;` inside a hint can no
  longer truncate the clause.
- **FP-9 `unit-not-in-project` broke on dotted unit names.** `ChangeFileExt` stripped
  `.ViewModel` from `Foo.ViewModel` as if it were a file extension, so a unit registered
  as `Foo.ViewModel.pas` never matched the used `Foo.ViewModel`. Normalization now strips
  only known source extensions (`.pas`/`.dpk`/`.dpr`) and both sides of every comparison
  use the same `NormUnit`.
- **FP-9: `*_SERVER` units are no longer flagged** against a CLIENT/COMMON project --
  they belong to the sibling SERVER project (scope error).

> The bulk of the `unit-not-in-project` volume (third-party `dx*`/`cx*`/EurekaLog units,
> generated `COMMON\OBJECTS\` units) is an index-coverage / search-path-resolution problem,
> deferred to v0.66 as a dedicated project-membership accuracy feature.

**Internal (`CheckSyntaxErrors`)**
- `BuildConditionalRanges` now reuses the once-decoded upper-cased source instead of
  decoding the file again and upper-casing every line.
- The conditional-region spanning check is now per-range, so a file with several separate
  `{$IF}..{$IFEND}` blocks correctly suppresses an error node straddling a middle block
  (previously only the outer first..last hull was tested).

### Internal / tests
- Pure parsing/normalization helpers split into the dependency-free unit
  `DRagLint.Lint.ProjectChecks.Parse` (no SQLite/FireDAC/Core), unit-tested by a new
  `tests\projectchecks\` console harness (21/21).

### Notes
All 78/78 lint fixtures + 21/21 project-checks tests pass.

---

## v0.64.1-alpha -- 2026-06-29

Fix-forward release completing and correcting v0.64.0-alpha (which shipped with several
items unreviewed/incomplete).

### Added / Completed

**IDE plugin**
- **All plugin commands now use the Win64 `drag-lint.exe`** (via a shared `DLExe64`
  resolver preferring `..\dll-win64\`), not just LSP + lint-all. Heavy commands
  (Analyse/References/compile-check/ghost-recover/check-ast/find-usages/symbol-search/
  forms-csv/rename/format/index/etc.) no longer run the 32-bit exe, which OOMed on large
  indexes. Falls back gracefully when the Win64 exe is absent.
- **Run Lint All streams live progress** to the IDE Messages view (completes the
  v0.64.0 "IDE plugin TBD"): `RunCaptureStreaming` reads the child pipe line-by-line and
  posts throttled `lint-all: [i/N] NN% file` updates on the main thread (`TThread.Queue`).

### Fixed

**False positives / rules**
- **Fortification (real guards, replacing v0.64.0's documentation-only stub):**
  - `large-magic-number` now exempts 0/1/-1/2, powers of two (4,8,...,65536), and hex
    literals from firing.
  - `string-equality-comparison` now skips comparisons where an operand is a numeric,
    `nil`, or boolean literal (conservative heuristic pending the v0.65 type resolver).
  - Each backed by a RED->GREEN negative fixture that also asserts the rule still fires.
- **FP-1 `{$IF}/{$IFEND}` cleanup:** hoisted the directive scan (removed a per-error-node
  O(N) source re-decode), removed dead code, fixed an `{$IFEND}` open/close double-match,
  and narrowed the line-1 root-error suppression so a genuine line-1 error still fires.
  The `syntax-error-ifend` fixture now also asserts a genuine error fires (line 17).

### Changed
- `lint-all --quiet` is now documented in `--help`.

### Notes
All 78/78 test fixtures pass. (FP-2..FP-9 from the field false-positive report are
scheduled for v0.65, along with the grep-elimination indexer wishlist.)

---

## v0.64.0-alpha -- 2026-06-28

### Added

**Performance & Visibility**
- **Parse-once optimization** -- Per-file parse cache in `TAstParseCache` so all ~36
  `TAstChecker` methods reuse one `TTSTree` instead of each re-reading and re-parsing
  the file. Expected: materially faster `lint-all` on large projects.
- **Lint-all progress streaming** -- CLI streams per-file progress to stderr; IDE
  plugin reads incrementally and posts throttled progress updates (v0.64 IDE plugin TBD).

**False-positive fixes**
- **FP-1: `{$IF}/{$IFEND}` syntax-error suppression** -- `CheckSyntaxErrors` now
  detects unbalanced conditional-compilation directives and suppresses ERROR/MISSING
  nodes within those regions. This eliminates ~12 false positives in codebases using
  `{$IF}/{$IFEND}` blocks that the tree-sitter grammar cannot fully parse.
- **Fortification audit** -- Documented known false positives in `string-equality-comparison`
  and `nil-comparison` rules pending type-aware guards (v0.19+ milestone). Fixtures added
  to guide future type-resolution integration.

### Notes

All 76/76 test fixtures pass. Harness includes syntax-error-ifend fixture (FP-1 guard test).

---

## v0.63.0-alpha -- 2026-06-28

### Added

Eleven new built-in (`TAstChecker`) lint rules and an IDE menu command. Each rule
ships with a TDD fixture under `tests/lint/` verified by
`tests/lint/run_lint_tests.ps1` (75/75 green). Built-ins are compiled into the
exe (no `.scm`/`.json`); a Win64 rebuild is required to add one.

**Security**
- **`unsafe-shellexecute`** (error) -- `WinExec`/`ShellExecute`/`CreateProcess`
  called with a non-literal command/executable argument (command injection, CWE-78).
- **`path-traversal`** (warning) -- `AssignFile`/`FileOpen`/`CreateFile`/`TFile.Open`
  whose path argument is a string concatenation (CWE-22).

**Bugs / control flow**
- **`loop-executes-at-most-once`** (warning) -- a `for`/`while`/`repeat` whose first
  body statement is `Exit`/`Break`/`raise`.
- **`format-argument-count`** (error) -- `Format('...', [...])` specifier count does
  not match the argument count.
- **`format-specifier-type-mismatch`** (error) -- a literal `Format` argument whose
  type is incompatible with its specifier family.
- **`try-except-swallowed`** (warning) -- a `try..except` whose handler neither
  re-raises nor logs nor calls `Application.HandleException`.
- **`virtual-method-in-constructor`** (warning) -- a constructor that calls a
  `virtual`/`dynamic`/`override` method declared in its own class; the call
  dispatches to a descendant override before that descendant is initialised.

**Resource / lock safety**
- **`dataset-open-without-close`** (warning) -- a dataset opened (`X.Open` /
  `X.Active := True`) without a matching `Close` in a `finally` block.
- **`criticalsection-not-released`** (error) -- `X.Enter`/`X.Acquire` without a
  matching `Leave`/`Release` in a `finally` block.

**Metrics**
- **`too-many-exit-points`** (info) -- a routine with more than 5 `Exit` statements.
- **`cyclomatic-complexity`** (info) -- a routine whose decision-point count exceeds 15.

**IDE**
- **Drag-Lint > Run Lint All (Full Report)** menu command in the wizard BPL --
  spawns `drag-lint lint-all` on the active project in the background, opens the
  report, and posts a summary to the Messages view.

### Notes

- **`virtual-method-in-constructor`** shipped as a pure-AST, same-file check
  (no DB). The original DB-backed design was dropped: the index's `modifiers`
  column records only visibility (`public`/`protected`/...), not
  `virtual`/`dynamic`/`override`, so the attribute is read straight from each
  class's declaration in the file being linted. This covers the common
  same-class case; cross-unit ancestry (calling an inherited virtual declared in
  a base unit) still needs the planned type resolver.

## v0.62.0-alpha -- 2026-06-28

### Added

Nine new pure `.scm` lint rules (no exe rebuild required to add a query rule;
each ships with a TDD fixture under `tests/lint/` verified by
`tests/lint/run_lint_tests.ps1`):

- **`unsafe-string-api`** (warning) -- calls to `StrCopy`/`StrCat`/`StrPCopy`/
  `StrMove`/`StrPos`/`StrLen`, unbounded C-style PChar routines with no length
  guard. Prefer `System.AnsiStrings` equivalents or the string/`TStringHelper` APIs.
- **`deprecated-rtl-function`** (info) -- `OemToAnsi`/`AnsiToOem`/`StrPas`,
  obsolete RTL routines; prefer `TEncoding` / modern string APIs.
- **`sleep-in-vcl`** (warning) -- `Sleep()` on the main thread freezes the VCL
  UI; use `TTimer` for delays or `TThread.Sleep` in a background thread.
- **`constant-condition`** (warning) -- `if True`/`if False`/`while False`, an
  always-constant condition (dead code or logic error). `while True` (event
  loop) is intentionally left alone.
- **`ifthen-both-branches`** (warning) -- `SysUtils.IfThen` evaluates both
  arguments before calling; side effects in either branch always execute. Use a
  real `if`/`then`/`else` when branches have side effects.
- **`sizeof-pointer-assumption`** (warning) -- `SizeOf(Pointer) = 4`/`8` bakes
  in a platform assumption (breaks across Win32/Win64). Guard with
  `{$IFDEF WIN64}` or compare to `SizeOf` of a platform-aware type.
- **`pchar-arithmetic`** (warning) -- `+`/`-` on a PChar-named variable;
  pointer arithmetic is unsafe and platform-specific. Use `PChar[N]` or string APIs.
- **`boolean-result-returned-directly`** (info) -- redundant
  `if Cond then Result := True else Result := False`; write `Result := Cond`
  (or `Result := not Cond`) directly.
- **`concat-in-loop`** (info) -- `S := S + X` self-concatenation is O(n^2);
  accumulate with `TStringList` or use `string.Join`, especially inside loops.

## v0.61.0-alpha -- 2026-06-26

### Added

- **`global-form-variable` lint rule** -- warns on unit-level variables whose
  declared type is a form class (potential memory leak if the form is created
  more than once without cleanup). Fires only when a sibling `.dfm` confirms
  this is a form unit. Detected via built-in AST check; works in live edit mode.
- **`unit-not-in-project` lint rule** -- `lint-project` cross-checks every unit
  used by the indexed project against the platform library DB and the project's
  `.dpr`/`.dproj`. Reports units that are neither a known library unit nor
  formally registered as a project member.
- **`frmGridLayout` popup note** -- `forms-csv` no longer labels `frmGridLayout`
  as "DEAD FORM"; it now shows "popup via TGridMenuPopup (Save/Load Layout)" in
  the Notes column. A `KnownPopupForms` table in `FormsMap.pas` generalises the
  pattern for future popup-only forms.
- **`lint-all` batch command** -- `drag-lint lint-all [--db <idx>] [--project
  <.dproj>] [--disable id,...] [--output <file>]` runs every per-file AST rule
  over all `.pas` files in the project index, then all project-wide rules
  (god-class, unused-public-symbol, interface-reference-cycle, layering, unit
  membership), applies `drag-lint:ignore` suppressions, and writes a consolidated
  report. Files that trigger encoding errors are skipped with a stderr notice.
  Exit 1 if any findings, 0 if none.

## v0.60.0-alpha -- 2026-06-26

### Added

- **Two-DB model** -- CLI consumers (`query`, `lint`, `forms-csv`, `resolve-dbs`)
  now auto-select the correct platform library DB with no `--db` flags needed.
  Platform is detected from the first `.dproj` found in the manifest section that
  covers the current working directory (`<Platform Condition=...>` element); falls
  back to `--platform` flag, then manifest `defaultPlatform`.
- **`index` manifest auto-DB** -- `drag-lint index <path>` without `--db` now
  looks up the manifest section covering `<path>` and uses that section's DB
  (e.g. `index C:\Projects\DB\ORM3\CLIENT` auto-selects
  `C:\Projects\DB\ORM3\drag-lint.sqlite` even when run from a different directory).
- **Plugin platform-aware library DB** -- the IDE plugin's `ResolveActiveIndexDbs`
  now reads `indexes.outDir` from the manifest beside the engine exe and calls
  `IOTAProject.CurrentPlatform` to pick `library-Win64.sqlite` for Win64 projects
  instead of always using `library-Win32.sqlite`.

## v0.59.4-alpha -- 2026-06-24

### Added

- **"Copy All Diagnostics" context menu** -- right-clicking in the Structure
  panel's diagnostic tree now includes a "Copy All Diagnostics" item (below a
  separator). Clicking it copies all diagnostics for the current file to the
  clipboard as plain text, one per line:
  `[sev] (line:col) message  [rule-code]`
  prefixed with the file path. Handy for pasting into bug reports or search.

## v0.59.3-alpha -- 2026-06-24

### Fixed (critical -- reindex FTS5 crash, third pass)

- **Root cause identified**: the Embarcadero SQLite 3.45.3 (64-bit) lacks
  `SQLITE_ENABLE_FTS5`. The v0.59.2 probe correctly detected this and set
  `FFts5Available=False`, but the `DROP TRIGGER` calls that follow need an
  **exclusive WAL lock** -- and the LSP server's concurrently-open connection
  blocks that lock, causing `DROP TRIGGER` to fail silently (swallowed by
  `TryExec`). The FTS5 sync triggers from a prior index run remained alive,
  so every `INSERT INTO string_literals` still fired them and crashed.

  Three-layer fix:

  1. **`PRAGMA busy_timeout = 5000`** (Connect): gives `DROP TRIGGER` up to
     5 seconds to acquire the exclusive lock once the LSP releases its reader,
     instead of failing instantly with `SQLITE_BUSY`.

  2. **`UpsertStringLiteral` / `DeleteStringLiteralsForFile` guard**: when
     `FFts5Available=False`, both methods are silent no-ops. Even if `DROP
     TRIGGER` still fails despite the timeout, the triggers can never fire
     because we never touch `string_literals`. This is the definitive backstop.

  3. **Plugin: stop LSP before indexing** (requires IDE restart to load new
     BPL): `InvokeReindexProject` now stops `GLspClient` on the UI thread
     before spawning the background indexer, eliminating the WAL lock race
     entirely. The LSP is restarted lazily on the next hover/query.

  Side effect: when FTS5 is unavailable the `string_literals` table is not
  updated during reindex (text search returns an informative error). This is
  correct -- without FTS5 the text-search index is unusable regardless.

## v0.59.2-alpha -- 2026-06-24

### Fixed (critical -- reindex FTS5 crash, second pass)

- **FTS5 probe via temp table** -- the v0.59.1 fix used `CREATE VIRTUAL TABLE
  IF NOT EXISTS string_fts USING fts5(...)` to detect fts5 availability, but
  `IF NOT EXISTS` short-circuits silently when `string_fts` already exists in
  the DB from a prior fts5-capable index run. This left `FFts5Available=True`
  while the module was absent, so the sync triggers still fired on every
  `INSERT INTO string_literals` and crashed with the same FATAL error.
  Fix: probe by creating `temp.fts5_probe USING fts5(x)` -- a throw-away temp
  virtual table that is always independent of what tables exist in the main DB.
  If the probe fails, any leftover sync triggers are dropped so INSERTs into
  `string_literals` cannot reach the fts5 module at all.

## v0.59.1-alpha -- 2026-06-24

### Fixed (critical -- reindex FATAL crash)

- **FTS5 graceful degradation** -- reindexing any project crashed with
  `ESQLiteNativeException: no such module: fts5` on the default Embarcadero
  SQLite DLL (which is built without `SQLITE_ENABLE_FTS5`). The v0.58
  text-constant index added FTS5 virtual tables; `Migrate()` ran them inside the
  main transaction, so the first `CREATE VIRTUAL TABLE ... USING fts5` aborted
  the entire migration. Fix: FTS5 DDL is now applied outside the core
  transaction and silently skipped if the fts5 module is absent. All other
  drag-lint features continue to work normally; only `query --text` will report
  "FTS5 not available" on affected SQLite builds.

## v0.59.0-alpha -- 2026-06-24

### Fixed (IDE plugin)

- **Find Usages tab name restored** -- the tab was briefly renamed "Blast Radius"
  in v0.58.0-alpha, which was semantically incorrect. Blast Radius (transitive
  impact analysis, callers of callers, N levels deep) is a separate future feature
  that needs engine work. The current tab shows direct usages and is named
  "Find Usages" again.

### Improved (index diagnostics)

- **Binary DFM detection** -- before parsing, the DFM indexer now detects binary
  (TPF0) DFMs (`$FF` magic byte) and emits a clear advisory message instead of
  a generic "parse contains syntax errors". Fix: save the form as Text DFM in the
  IDE (`File > Save As Text`).
- **Located parse errors** -- when tree-sitter reports syntax errors, both the DFM
  and Delphi 13 parsers now walk the ERROR/MISSING nodes and report each as
  `file(line,col): parse error [TYPE]` (up to 10 per file) instead of a single
  generic string. The reindex report in the IDE now shows exact source locations.
- **Win64 build output excluded** -- `"Win64"` added to the global `exclude` list
  in `drag-lint.json`. Build output dirs (`Win64\Debug\`, `Win64\Release\`, etc.)
  are pruned from all index walks, eliminating stale DCU/EXE content from results.

### Fixed (IDE plugin -- LSP freshness after reindex)

- **LSP restart after reindex** -- after "Reindex This Project" completes, the
  plugin now stops and frees `GLspClient` on the main thread so the next query
  (hover, Find Usages, Search) uses the freshly built index. Previously the LSP
  server kept the old index loaded in memory and queries returned stale data until
  the IDE was restarted.

## v0.58.0-alpha -- 2026-06-23

### Added (text-constant index / query --text)

- `query --text "<phrase>"`: full-text search over indexed string content --
  error messages, DFM captions, SQL exception text, resourcestrings. Searches
  string literals only, never identifiers. Default mode is exact phrase match.
  - `--any-order`: all terms must match in any order (FTS5 implicit AND across tokens).
  - `--substring`: trigram index match; finds the phrase as a substring of a
    literal (e.g. `query --text "password" --substring` catches
    `'Invalid password'` and `'Password mismatch'`).
  - `--source pas|dfm|sql`: restrict to one source kind.
  - `--limit N`: cap results (default 200).
  - `--json`: machine-readable output with `file_path`, `start_line`,
    `start_col`, `source`, `kind`, `owner_name`, `text`, `enclosing` fields.
- **Sources indexed:**
  - Delphi `.pas`: string literals, `const` string constants,
    `resourcestring` declarations, and `Format`-call format strings.
  - DFM `.dfm`: string properties (captions, hints, messages).
  - SQL: `CREATE EXCEPTION` messages -- indexed only from `MS*.sql` files by
    default (migration-script convention). Pass `--no-sql-ms` to index every
    `.sql` file.
- **Engine:** FTS5 with `unicode61` tokenizer (phrase + any-order) and a
  parallel `trigram` FTS5 table (substring). Storage schema v10 adds
  `string_literals` (base table), `string_fts` (phrase/any-order external-
  content FTS5 vtab), and `string_fts_tri` (trigram substring vtab), kept in
  sync via `AFTER INSERT/DELETE` triggers on `string_literals`.
- **Self-diagnostics:** `--selftest-fts5` checks FTS5 availability;
  `--selftest-schema` verifies schema v10 tables and triggers are present.

### Added (IDE plugin)

- IDE plugin: new unified **Search (no grep)** dock tab - one Kind dropdown (Symbol/Text/Usages) + query field + a clickable results grid that jumps to source; Advanced toggle exposes per-kind refinements (kind filter / text mode+source / usages width). Find Usages no longer shows a debug dump on no-results.
- **Blast Radius tab** (renamed from Find Usages) - shows direct usages of a symbol by category (declarations, reads, writes, calls, type-uses, events) and a unit-impact count roll-up; clicking any result jumps to source.
- **Navigation for form units** - clicking a result in any dock tab that refers to a form unit (e.g., `TfrmFoo` in `uMyForm.pas`) now opens the `.pas` code editor directly, not the form designer.
- **Symbol Search tab removal** - folded into the unified Search and Blast Radius tabs; no longer a separate dock tab.

## v0.57.0-alpha -- 2026-06-23

### Fixed (DFM)

- `lint` no longer mis-parses `.dfm` files with the Pascal grammar. The linter
  now selects the tree-sitter grammar by file extension: a `.dfm` is parsed with
  the dedicated DFM grammar (`tree_sitter_dfm`, already used by indexing), so a
  valid form is clean instead of emitting one spurious `parser-error` per Pascal
  set-literal (`[akLeft, akTop, akRight]`, `[]`) and per root `object .. end`.
  A genuinely malformed DFM still surfaces a real `parser-error` from the DFM
  grammar (ERROR/MISSING walk, mirroring `CheckSyntaxErrors`). Only single-file
  `lint <x.dfm>` was affected (folder lint already globbed only `*.pas/*.dpr/*.dpk`)
  -- which is exactly what the on-save hook runs. Reported: every `.dfm` produced
  4-45 false errors; e.g. the 11.5k-line `Blueprint4.dfm` ribbon form went 45 -> 0.

### Tests

- `tests/lint/dfm-valid.dfm` (must be clean) + `tests/lint/dfm-broken.dfm` (must
  flag a real error); `run_lint_tests.ps1` now also globs `*.dfm`. 53/53 pass.

## v0.56.0-alpha -- 2026-06-21

### Added (thread-safety)

- `ui-access-in-thread` (warning): VCL/FMX UI access from a background thread.
  Inside a method named `Execute` whose class (declared in the same file) has a
  base whose name contains `Thread`, it flags strong UI members -- assignment to
  `.Caption`, or calls to `.SetFocus`/`.Repaint`/`.BringToFront` -- that are NOT
  inside a nested anonymous method (a likely `Synchronize`/`Queue` body). Tuned
  for low false positives.

## v0.55.0-alpha -- 2026-06-21

### Added (batch)

- `hardcoded-connection-string` (warning): a string literal with connection-string
  keywords (`Password=`, `User ID=`, `Data Source=`, ...) -- a hardcoded secret (CWE-798).
- `gettickcount-wraparound` (warning): `GetTickCount` wraps after ~49.7 days; use
  `GetTickCount64` for elapsed-time math.
- `hardcoded-ip-address` (info): a string literal that is an IPv4 address.

## v0.54.0-alpha -- 2026-06-21

### Added (architecture)

- `layering-violation` (warning, `lint-project --db --layers <file.json>`):
  config-driven architecture enforcement. Assign units to layers by name globs,
  declare allowed dependencies, and flag forbidden cross-layer `uses` edges.
  Config: `{ "layers":[{"name":"UI","match":["*.UI.*"]},...], "allow":[{"from":"UI","to":["Business"]},...] }`.
  Default-deny among defined layers; units matching no layer are ignored (RTL/3rd-party).
  Pass the config with `--layers`, or place `drag-lint-layers.json` in the working dir.

## v0.53.0-alpha -- 2026-06-21

### Added (batch)

- `uppercase-compare` (warning): `UpperCase(X)`/`LowerCase(X)` compared to a string
  literal -- fragile (silently always-false if the literal's case differs) and slow;
  use `SameText`.
- `outputdebugstring` (info): `OutputDebugString` debug tracing left in code.
- `length-zero-compare` (info): `Length(X) = 0` / `> 0` -- for strings prefer `X = ''`.

### Changed

- `float-equality-comparison` now also flags `TDateTime` / `TDate` / `TTime` operands
  (they are `Double`-backed, so `=` / `<>` is unreliable).

## v0.52.0-alpha -- 2026-06-21

### Added (batch)

- `use-after-free` (warning): use of an object after a raw `X.Free` (dangling
  reference) within the same block, until `X` is reassigned. `FreeAndNil(X)` clears
  tracking. Catches the classic `X.Free; ...; X.Something` crash.
- `win64-pointer-cast` (warning): a 32-bit cast (`Integer`/`Cardinal`/`LongInt`/
  `LongWord`) of a pointer-typed value (`Pointer` / `P...`) -- truncates on Win64;
  use `NativeInt`/`NativeUInt`.
- `hardcoded-absolute-path` (info): a string literal that is an absolute drive path
  (`'C:\...'`) -- breaks on other machines; read from config or compute at runtime.

## v0.51.0-alpha -- 2026-06-21

### Added (project-wide)

- `interface-reference-cycle` (warning, `lint-project --db`): class A holds an
  interface implemented by class B, and B holds an interface implemented by A --
  a mutual strong interface reference that leaks under ARC. Parses every indexed
  source file, maps interface implementors and interface-typed fields, and reports
  each mutual pair. Fix by marking one side's field `[weak]` or `[unsafe]`.

## v0.50.0-alpha -- 2026-06-21

### Added (resource lifetime)

- `unprotected-object-free` (warning): a locally-created object freed without
  try-finally protection -- it leaks if code between creation and `Free` raises.
  Per routine, correlates `X := ...Create...` with a later `X.Free` / `FreeAndNil(X)`
  on the same variable that is NOT inside a `finally` (so destructor field-frees and
  correctly-protected frees are not flagged).

## v0.49.0-alpha -- 2026-06-21

### Added (FireDAC)

- `firedac-open-execsql-mismatch` (warning): `Open` on a data-modifying statement
  (INSERT/UPDATE/DELETE) or `ExecSQL` on a SELECT. Correlates a literal
  `X.SQL.Text := '...'` with a later `X.Open` / `X.ExecSQL` on the same variable,
  in program order -- only fires when the SQL is a recognizable literal.

## v0.48.0-alpha -- 2026-06-21

### Added (more lint rules)

- `not-comparison-precedence` (warning): `not A = B` parses as `(not A) = B`.
- `redundant-not-not` (info): `not not X` double negation.
- `public-field` (info): public data field on a class breaks encapsulation.
- `empty-on-handler` (warning): `on E: ... do ;` empty handler swallows the exception.
- Routine metrics (info, built-in, conservative defaults): `too-many-parameters` (>7),
  `too-many-locals` (>25), `method-too-long` (>120 lines), `deep-nesting` (>5).
- Type-aware (lightweight per-file type map): `float-equality-comparison` (warning):
  `=` / `<>` on `Single`/`Double`/`Extended`/`Real` operands; `freeandnil-on-interface`
  (warning): `FreeAndNil` on an interface-typed variable.
- `locale-sensitive-conversion` (warning): `StrToFloat`/`FloatToStr`/`StrToDate`/... without
  an explicit `TFormatSettings` (locale-dependent cross-machine bug).

### Added (CLI)

- **`--disable id1,id2,...`** on `lint` -- drop those rule ids from the output
  (per-rule control without editing files).

- **Per-line suppression** -- `// drag-lint:ignore` (silence all rules on that
  line) or `// drag-lint:ignore <rule-id> [<rule-id> ...]` (silence specific
  rules). Applies to both `.scm` and built-in rules.
- **`drag-lint lint-project --db <index.sqlite> [--rule <id>] [--json]`** --
  index-wide ("project") lint rules that need the whole symbol/refs graph:
  - `god-class` (info): a class with many methods *and* many fields.
  - `unused-public-symbol` (info): an exported (interface-section) free routine
    with no references/callers anywhere in the index -- possible dead public API.
    (Best for applications; libraries expose API for external callers.)

## v0.47.0-alpha -- 2026-06-21

### Added (lint rule expansion -- 25 new rules)

A research-backed first stage of a real Delphi linter (see
`docs/lint/REPORT-1-delphi-lint-landscape.md` and `REPORT-2-...-implementation-plan.md`).
**20 new external `.scm` rules** (data-driven, hot-loaded from `rules\`) and
**5 new built-in rules** (compiled in; need flow/scope analysis), all TDD-tested
via `tests\lint\run_lint_tests.ps1` (28/28).

- **Exceptions:** `empty-except`, `empty-finally`, `bare-except`,
  `raise-bare-exception`, `reraise-loses-stack`, `raise-in-finally` (built-in),
  `control-flow-in-finally` (built-in).
- **Control flow / dead code:** `empty-conditional`, `empty-loop-body`,
  `empty-case-branch`, `not-in-precedence`, `off-by-one-count`,
  `code-after-exit` (built-in).
- **Expression bugs:** `comparison-same-operands`, `division-by-zero-literal`,
  `nil-comparison`, `self-assignment`, `classname-string-compare`,
  `boolean-comparison-true` (now also `<>`).
- **Resources / clarity:** `redundant-assigned-free`, `with-multiple-items`,
  `inline-assembly`, `assert-call` (now single-arg only),
  `missing-inherited-ctor` / `missing-inherited-dtor` (built-ins).
- **Security:** `sql-injection-concat` (CWE-89), `hardcoded-credential`
  (CWE-798; `var` and `const`).
- Refined `compiler-magic-comments` to also flag `BUG`.

### Added (CLI)

- **`drag-lint lint <file> --rules-dir <path>`** -- point the linter at an
  explicit external-rules folder (CI / IDE / testing).
- `lint` now prints a one-line note to stderr when **0** external `.scm` rules
  are loaded, so a missing `rules\` folder is no longer silent (built-in checks
  still run).

### Packaging

- The release archive now bundles the `rules\` folder next to `drag-lint.exe`
  (required for the `.scm` rules to load). See `INSTALL.md`.

## v0.44.0-alpha -- 2026-06-14

### Added (forms-csv test-helper navigation map)
- **`forms-csv --project <dproj> --db <sqlite> [--out <f.csv>] [--root <TfrmMAIN>]`**
  -- emits a tester-oriented CSV, one row per navigable form (forms/dialogs only;
  data modules and frames excluded via class-ancestry). Columns: `#`, `Unit`,
  `FormName`, `PAS lines`, `Navigation`, `Called From`, `Notes`.
  - **Navigation**: the button/menu captions a tester clicks from the application's
    main form to reach each form, e.g. `frmMAIN -> 'Job List' -> 'Open Folder'`.
    Built by resolving form-construction sites (`TfrmX.Create` incl. named ctors,
    `Application.CreateForm`) to their enclosing routine, mapping that to the owning
    form, and reading the bound control's caption from the `.dfm`. Resolves direct
    handlers, handlers reached indirectly within a form, and `TAction` captions;
    falls back to `(via Routine)` when no captioned control binds the launch
    (keep-the-gap), and `(no path from MAIN)` when unreachable. BFS = shortest path;
    cycle-safe.
  - **Called From**: the distinct forms that directly open this one (with captions).
  - Root form auto-detected from the `.dpr` (last `Application.CreateForm` of a form
    at/before `Application.Run`); override with `--root`. Inventory is restricted to
    the project's own units (skips `*- Copy`/`.bak` backups).
  - Requires a **current** index -- re-index the project if rows show mostly
    `(no path from MAIN)` (stale construction-site line numbers break edge detection).
- **IDE plugin: "Generate Test Helper CSV..."** Tools-menu item -- saves all, runs
  `forms-csv` on the active project, opens the CSV.

## v0.43.0-alpha -- 2026-06-12

### Added (semantic diagnostics + uses cleanup)
- **`check-unit <unit.pas> [--project <dproj>] [--platform win32|win64]
  [--shadow <dir>] [--resolve-uses]`** -- compile ONE unit in full project
  context (deps from DCUs) for real semantic errors (`E2003` etc.) without a
  full build. `--shadow` overlays an unsaved-buffer copy so errors reflect edits
  before save, never touching the file. `--platform` matches the project's
  active config (picks dcc32/dcc64 + that platform's RTL lib; avoids `F2048`).
  `--resolve-uses` annotates undeclared identifiers with the unit to add.
- **`cycles --db <sqlite> [--edges] [--causes]`** -- circular unit dependencies
  (Tarjan SCC over the unit-uses graph). `--edges` lists each cycle's actual
  `A uses B [section]` edges, flags interface edges as move-to-implementation
  candidates and layering inversions (COMMON -> CLIENT/SERVER). `--causes`
  pinpoints the specific symbols in A's interface that reference B (the
  types/vars/methods to move/extract), with line numbers and an honest note
  where the index couldn't resolve a ref. `--plan` emits a followable markdown
  refactoring playbook per cycle (files, symbols with use + declaration line,
  an auto-classified fix -- extract-contract or invert-dependency -- numbered
  steps, and a verify command) that a junior dev or small model can execute.
- **`uses-audit <unit.pas>`** -- index proposal of interface->implementation
  moves + unused units (conservative; project units only).
- **`uses-fix <unit.pas> --project <dproj> [--apply] [--remove-unused]`** --
  compiler-VERIFIED uses-clause cleanup: move interface-only imports down,
  optionally comment out unused units (skips those with init/final sections).
  Each edit is shadow-compiled and kept only if it adds no new error vs the
  baseline; dry-run by default, `--apply` writes after a `.bak`. With no
  `<unit>` target it runs a project-wide dry-run sweep report.

### Known limitation (uses-fix)
- `uses-fix`'s per-unit verify is **best-effort, not a faithful full-build
  check**: a single-unit `dcc` compile can reuse a stale `.dcu` (masking a real
  error) or abort on an RTL dependency (`F1026`), so a move that breaks the full
  build can pass per-unit. A safety guard now rejects edits whose verify compile
  *fatally aborted*, but the `.dcu`-reuse case can still false-pass. **Always do
  a full project build after `--apply`**; treat `cycles`/`uses-audit` as
  advisory. Reliable bulk cleanup needs full-project-build verification.

### Fixed
- **Duplicate file rows on re-index.** Mixed-separator stored paths
  (`C:/root\sub\file.pas`) defeated the `files.path` UNIQUE upsert, so each
  re-index inserted a duplicate row and left stale `unit_uses`/refs. Paths are
  now canonicalised at the store boundary; an incremental re-index is a true
  no-op (`skipped N up-to-date`).

### Added
- **Dedicated dockable Graph window.** The graph is now its own
  `INTACustomDockableForm` ("drag-lint Graph", under View > Tool Windows) rather
  than a tab -- so it can sit open beside the Structure window, both visible at
  once. It hosts the standalone viewer **in-place**: the plugin launches
  `drag_lint_graph.exe --parent-hwnd <thisWindow>`, the viewer renders as a
  child filling the window, and the plugin terminates it on close. Jump-to-source
  still flows through the named-pipe contract. (Viewer side: new `--parent-hwnd`
  embed mode.)
- **Hover: IDE-style Parameters block.** Proc-like hovers now break the
  signature into a `**Parameters:**` list (one `name : type` per line, with
  `const`/`var`/`out` preserved) plus a `**Returns:**` line -- mirroring the
  IDE's parameter insight -- even when the symbol has no doc-comment. Works in
  the LSP popup and `drag-lint hover` (which no longer errors on no-doc
  symbols). Generic types stay intact (top-level split respects `<> () []`).
- **Structure window: right-click navigation menu.** Single/double-click still
  goes to the declaration; the new context menu adds **Go to Implementation
  (body)** -- scans the file for the `TClass.Method` body line -- and **Find
  Usages** (opens the usages view for the symbol). Right-click selects the node
  under the cursor first.

## v0.42.0-alpha -- 2026-06-12

### Added
- **`index --scan-libraries-win`** and **`index --scan-libraries-all`**: build a
  single library index from the IDE's registry Library + Browsing paths.
  `-win` covers Win32 + Win64 (the IDE's native targets, and what `--scan-libraries`
  still aliases to); `-all` enumerates **every** platform subkey under
  `...\BDS\37.0\Library` (Android/iOS/Linux64/OSX/Win64x/...), adding the
  platform-specific `source\rtl\posix`, `source\rtl\ios` and `posix\osx` trees so
  `Posix.*` / `iOSapi.*` / `Macapi.*` / `Androidapi.*` symbols resolve. Both
  deduplicate across HKCU+HKLM and 32/64-bit registry views; `$(Platform)` now
  expands per-platform instead of a hardcoded `Win64`.

### Fixed (compiler hygiene)
- Cleared inline-expansion hints (H2443) by adding `FireDAC.Stan.Param` and
  `System.Generics.Collections` to the units that needed them; removed dead
  locals and the superseded `ParseJsonOutput` method (H2164/H2219/W1050).

## v0.41.0-alpha -- 2026-06-05

### Added
- **AI-usage guide** (`docs/AI-USAGE.md`): copy-paste instructions so an AI
  agent drives drag-lint over CLI or MCP, with the token-saving context-bundle
  workflow.
- **Unit initialization/finalization** are now indexed (kinds `initialization`/
  `finalization`), so structure/section views can show them.
- **Symbol `section`** (interface vs implementation) + member **types**
  captured into signatures; `query` shows `section` + `usable_from_other_units`;
  `resolve-uses` is section-aware (won't suggest implementation-only symbols).

### Changed (token economy)
- **Lean context bundle:** `drag-lint context` now slices only the target
  symbol's body (not the whole parent class). `bench-context` on a real project:
  **~556 vs ~33,762 tokens (~60x)**.
- **`--full-surface` switch** (CLI) / `full_surface` (MCP `get_context_bundle`):
  by default the auto-generated published DFM component fields are stripped from
  a form's class surface; pass the switch to keep them when working on the form.

### Fixed
- Plugin open-in-IDE: only `GotoLine` after `OpenFile` succeeds (was scrolling
  the wrong file).
- Indexer skips `__history` / `.git` / backup dirs in folder scans.

## v0.40.5-alpha -- 2026-05-31

### Added (major)

**SQL-aware drag-lint.** Three new capabilities indexed alongside Delphi
and DFM:

- **Tier 1: Firebird DDL extractor** (`src/parser/DRagLint.Parser.Sql.pas`).
  New `IParser` implementation; the indexer dispatches `.sql` extensions
  to it automatically. New `TSymbolKind` values: `skSqlTable`,
  `skSqlColumn`, `skSqlIndex`, `skSqlTrigger`, `skSqlGenerator`,
  `skSqlProcedure`, `skSqlView`, `skSqlException`, `skSqlDomain`,
  `skSqlConstraint`. SQL columns are stored as children of their table
  (same shape as Delphi fields-of-class). Trigger references emit
  `sql_table_ref` rows. Real-world numbers from Micronite
  `C:\Projects\DB\SQL\` (39 files, 14s):

  ```
  489 sql_table   8012 sql_column   619 sql_trigger
  282 sql_generator   193 sql_domain    90 sql_index
    4 sql_view       395 sql_procedure   8 sql_exception
  ```

- **Tier 2: live Firebird snapshot** (`drag-lint fb-snapshot
  --connection "..." --db <sql.sqlite>`). Connects via FireDAC
  `DriverID=FB`, pulls `RDB$RELATIONS`, `RDB$RELATION_FIELDS`,
  `FIB$FIELDS_INFO`, `FIB$DATASETS_INFO`, `FIB$ENUMVALUES` into
  `fb_relations` / `fb_columns` / `fb_field_info` / `fb_datasets` /
  `fb_enum_values`. Each row stamps `snapshot_at` for drift detection.
  Post-pass cross-links `fb_relations.sql_table_symbol_id` and
  `fb_columns.sql_column_symbol_id` to the Tier 1 DDL symbols by name.
  Each `FIB$*` block is wrapped in try/except, so a permission denial
  or schema mismatch on one optional table doesn't abort the snapshot.
  Verified against `MICRONITEV6A.FDB`: 134 relations / 2273 columns /
  2049 field_info / 129 datasets in 0.5s, 99% cross-link rate for
  relations and 93% for columns.

  Required runtime DLLs (Win32, beside `drag-lint.exe`): `fbclient.dll`
  + `icudt63.dll` + `icuin63.dll` + `icuuc63.dll` + `msvcp140.dll` +
  `vcruntime140.dll` + `zlib1.dll`. Source: `%FIREBIRD%\WOW64\`.

- **Tier 3: Delphi ? SQL ORM linker** (`drag-lint link-orm --db
  <proj.sqlite> --db <sql.sqlite>`). Cross-references Delphi
  classes/interfaces/fields against SQL tables/columns by Delphi/Micronite
  naming convention (T/I/F-prefix strip). New `orm_links` table records
  `(delphi_symbol_id + delphi_db_index, sql_symbol_id + sql_db_index,
  confidence, link_kind, evidence)`. Cross-DB indices track origin DBs.
  Verified against MICRONITE_V4DataModel.Classes.pas + MS*.SQL:
  158 `class_to_table` + 1367 `field_to_column` bindings at
  confidence 1.0.

### Added (storage)

Schema bumped **v5 ? v6** (additive; existing DBs migrate cleanly):

- `fb_relations`, `fb_columns`, `fb_field_info`, `fb_datasets`,
  `fb_enum_values` ? Tier 2 snapshot tables
- `orm_links` ? Tier 3 cross-DB bindings

`TSQLiteSymbolStore.GetConnection: TFDConnection` exposed as a leaf
accessor for utilities (uses-report, fb-snapshot, link-orm) that need
raw table scans. Intentionally **not** on `ISymbolStore` ? calling
code knows it's reaching into the SQLite impl.

### Added (autotest)

Three new SQL-aware checks: `sql_table SAMPLE indexed`,
`sql_generator indexed`, `link-orm command exits 0`. Fixture:
`tests/autotest/fixtures/sample_schema.sql` exercises every Tier 1
DDL kind. Total now **17 PASS** in ~1.5s.

### Notes for the graphing tool

- **Cross-DB symbols**: see `Delphi-RAG-Lint-Graph/docs/cross-db-symbols.md`.
- **SQL symbol contract**: see `Delphi-RAG-Lint-Graph/docs/sql-symbols.md`.

---

## v0.40.2-alpha -- 2026-05-31

### Fixed (critical ? IDE freeze)

User pressed `Tools > drag-lint > Test Connection...` on v0.40.1, the
LSP handshake succeeded (confirmed in the debug log), then the IDE
froze for over 2 minutes and had to be killed.

Root cause: `TDragLintLspClient.Stop` did `CloseHandle(FStdOutRead)`
and then `FReaderThread.WaitFor`. On Windows, closing a pipe handle
does NOT reliably unblock a `ReadFile` running on another thread when
the child process still holds the write end open. The reader thread
sat in `ReadFile` forever, `WaitFor` never returned, and the IDE
froze.

Fix in `Stop`:

1. **`TerminateProcess(FProcessHandle, 0)` first** ? kills the child
   immediately. Its write end of stdout closes, causing our reader's
   `ReadFile` to return `ERROR_BROKEN_PIPE`. Reader exits naturally.
2. Close the pipe handles next.
3. `WaitForSingleObject(ReaderHandle, 2000ms)` with a hard upper
   bound ? `TThread.WaitFor` has no timeout overload, so the raw
   Windows API is the correct primitive here. If the reader still
   hasn't exited in 2s, log it and leak the thread instance (the OS
   will reclaim once the child is fully gone) rather than freezing
   the IDE.
4. Reap the child handle.

Additional belt: **`InvokeTestConnection` now runs Start + Initialize
+ Stop on a `TThread.CreateAnonymousThread`** and posts the report
back via `TThread.Queue`. Even if a future regression makes Stop
slow, the IDE thread is no longer involved.

### Note

The plugin log path now actually matches what the dialogs claim
(v0.40.1 fix). If you saw `C:\TEMP\drag-lint-plugin.log` doesn't
exist after Test Connection on v0.39, that was the bug ? the real
log was at `%LOCALAPPDATA%\Temp\drag-lint-plugin.log`.

---

## v0.40.1-alpha -- 2026-05-31

### Added (diagnostics)

- **Plugin version + BPL build timestamp** on every user-visible
  dialog. The new `PluginBuildTag` function reads
  `GetModuleName(HInstance)` + `FileAge` at runtime and reports
  `drag-lint plugin v0.40.1-alpha (BPL built YYYY-MM-DD HH:MM:SS)`.
  Appears at the top of:
  - Tools > drag-lint root entry (`Execute`)
  - `Test Connection...` report
  - `LSP server failed to start` dialog (with BPL dir + resolved exe)
  - `LSP initialize handshake failed` dialog
  - `Open Plugin Log` when no log exists yet
  Lets you verify at a glance that the IDE is loading the BPL you
  just installed, without having to inspect the file modtime by hand.

### Fixed (logging)

- **Plugin log path mismatch** ? `DebugLog` wrote to
  `TPath.GetTempPath` while the diagnostic dialogs printed
  `GetEnvironmentVariable('TEMP')`. Under Windows TMP/TEMP precedence
  the two can diverge, so users opened the displayed path and found
  no file. Both now resolve via a single `GetPluginLogPath` function
  with a fallback to "alongside the BPL" if the temp dir isn't
  writable.

### Changed (build output)

- `dclDragLintWizard.dproj` now writes `BplOutput` / `DcpOutput` to
  `..\..\third_party\dll-win32\` instead of `..\..\build\v021\`. The
  staged `drag-lint.exe` + tree-sitter DLLs already live there, and
  it's on the standard PATH the project README recommends, so
  installing the package from RAD Studio puts the BPL right next to
  the exe the plugin resolves. The "next to BPL" lookup succeeds the
  moment install finishes.

---

## v0.40.0-alpha -- 2026-05-31

### Fixed (critical -- IDE plugin AVs)

Two access violations made the v0.16-v0.39 plugin essentially unusable on
real projects:

- **AV during editor paint** -- `TOTAEditView.BeginPaint -> System.TObject.GetInterface`
  recursing into `ElisionParser.ApplyElisions`. Root cause:
  `TDragLintEditServicesNotifier.EditorViewActivated` called
  `EditView.AddNotifier(TDragLintEditViewNotifier.Create)` on every focus
  change without tracking the returned index, so each editor view
  accumulated a growing list of duplicate notifier interface refs.
  Re-installing the BPL (or any path that freed an older instance) left
  the IDE iterating a dangling vtable.
- **AV on IDE exit** -- `TCodeIDocModule.AllowSave -> TInterfaceList.Get ->
  System.@IntfCopy`, forcing users to kill RAD Studio instead of closing
  it cleanly. Root cause:
  `TDragLintSaveNotifier` was added to every opened module's notifier
  list (`AModule.AddNotifier(Self)`) without explicit removal before the
  BPL unloaded.

Fix:
- Both notifier classes now track every `AddNotifier` registration in a
  thread-safe `TList<TRegistration>` with a `TMonitor` lock.
- `RegisterSaveNotifierForModule` and `EditorViewActivated` now dedupe
  -- repeated calls for the same module/view are a no-op.
- `UnregisterAllSaveNotifiers` and `UnregisterAllViewNotifiers`
  iterate the tracker, call `RemoveNotifier(Index)` on each, swallow any
  exception from a partially-destroyed module, and clear the list.
- Three teardown paths trigger these:
  1. `ofnFileClosing` in `TDragLintProjectNotifier.FileNotification`
     drops a save-notifier the moment its module closes.
  2. `TDragLintWizard.Destroyed` calls all three unregisters
     (`UnregisterAllSaveNotifiers`, `UnregisterDragLintEditViewNotifier`,
     `UnregisterProjectNotifier`) before the BPL code segment is dropped.
  3. The unit `finalization` blocks call them again as a safety net.

### Fixed (UI freeze)

- **`Tools > drag-lint > Show Inline Info`** previously called
  `Sleep(4000)` on the IDE UI thread to keep its hint window visible,
  freezing the editor. v0.40 keeps a singleton `THintWindow` + `TTimer`
  with `Interval := 4000` so the auto-close runs without blocking.
  Re-invoking before the timer fires tears down the prior hint and
  restarts the timer.

### Note on the LSP handshake failure

Still pending root-cause -- use v0.39's `Test Connection...` menu to
collect the report. v0.40's fixes are orthogonal (notifier lifecycle vs.
subprocess + pipe setup).

---

## v0.39.0-alpha -- 2026-05-29

### Added (plugin diagnostics)

- **`Tools > drag-lint > Test Connection...`** ? runs through the exact
  LSP startup sequence the plugin uses internally and shows a
  human-readable report:
  - BPL path + directory
  - Resolved `drag-lint.exe` candidate (next-to-BPL or PATH fallback)
  - `Start` result (subprocess spawn)
  - `Initialize` result (handshake)
  - Path to the detailed log file
  All without the user having to install/uninstall the package or
  trigger a real hover.

- **`Tools > drag-lint > Open Plugin Log`** ? opens
  `%TEMP%\drag-lint-plugin.log` in the user's default text editor.
  When the log doesn't exist yet (first run before any plugin LSP
  invocation), shows an informational dialog.

### Notes

- The Test Connection report is the fastest path to diagnose the
  "LSP initialize handshake failed" error from v0.21-v0.37. Run it,
  share the report.
- The plugin log is timestamped; previous runs append, so check
  the tail of the file for the most recent attempt.

---

## v0.38.0-alpha -- 2026-05-29

### Added (diagnostics)

- **`%TEMP%\drag-lint-plugin.log`** ? the IDE plugin's LSP client now
  writes a detailed timestamped log of every subprocess event, send,
  receive, and error to a file in the user's temp dir. Created
  automatically on first plugin invocation; appended thereafter.

  When the plugin shows "LSP server failed to start" or "LSP initialize
  handshake failed", the dialog now includes the log file path.

### Fixed

- **`CreateProcessW` cmd-line did not quote the exe path** ? if the BPL
  was installed at a path containing spaces (e.g.
  `C:\Program Files\drag-lint\dclDragLintWizard.bpl`), the cmd line
  `<unquoted exe> lsp` was tokenized by Windows and the process spawn
  succeeded but the args got mangled. Now quotes the exe path
  explicitly.

- **`CREATE_NO_WINDOW` flag added** to `CreateProcessW` so the
  spawned drag-lint subprocess does not pop a console window.

- **`Initialize` request timeout bumped from 5s to 10s** ? the 5s
  timeout was occasionally too short on slow disks / first-run cold
  starts.

### Notes

- The BPL is loaded into RAD Studio's process at IDE startup. To pick
  up the v0.38 BPL changes you must either:
  1. Close RAD Studio entirely, replace
     `dclDragLintWizard.bpl`, and restart, OR
  2. Component ? Install Packages ? uncheck drag-lint ? OK,
     replace the BPL file, then re-check it.
- The `drag-lint.exe` standalone is unchanged behavior from v0.37 ?
  only the BPL plugin gained logging.

---

## v0.37.0-alpha -- 2026-05-29

### Fixed (critical)

- **`drag-lint index` failing on Win32** with `[FireDAC][Phys][SQLite] ERROR: near "ON": syntax error`. The `FQUpsertFile` prepared query used SQLite's UPSERT syntax (`INSERT ... ON CONFLICT(path) DO UPDATE SET ...`) which requires SQLite 3.24+. RAD Studio 13's bundled Win32 FireDAC SQLite library is older than that and rejects the keyword. Win64 was unaffected. Rewrote the query to use `INSERT OR REPLACE INTO files(...)` which is supported in every SQLite version. Behavior unchanged for the indexer (files.id may differ on re-index, but symbols/refs cascade and incremental skip path was already bypassing this query for already-indexed files).

### Notes

- v0.36's dual-arch fix made the Win32 IDE plugin path actually usable; this v0.37 fix makes auto-indexing work in that path. Both fixes are required for a functioning IDE plugin install.
- Win64 standalone CLI users were unaffected by this bug (the Win64 FireDAC SQLite is current enough).

---

## v0.36.0-alpha -- 2026-05-29

### Fixed (critical)

- **Binary architecture mismatch.** Releases through v0.35 shipped
  `drag-lint.exe` (Win32) bundled with `tree-sitter*.dll` (Win64). The
  exe would silently fail to load the DLLs with
  `STATUS_INVALID_IMAGE_FORMAT` (0xC000007B). Any prior install was
  non-functional regardless of CLI vs IDE-plugin use.

### Added (distribution)

- **Dual-architecture release artifacts.** Every binary now ships in
  two matched variants:
  - `drag-lint-v0.36.0-alpha-win32.zip` ? `drag-lint.exe` + 3 DLLs as
    PE32 (Intel i386). **Required for the IDE plugin** since RAD Studio
    13 itself is a 32-bit process; the `dclDragLintWizard.bpl` is also
    Win32 and goes in this bundle.
  - `drag-lint-v0.36.0-alpha-win64.zip` ? same contents as PE32+
    (x86-64). For standalone CLI / LSP / MCP usage where the process
    runs outside any IDE.

- **New build scripts** at `build/`:
  - `build_draglint_win32.bat` / `build_draglint_win64.bat` ?
    msbuild-driven Delphi 13 builds for either platform; output staged
    to `third_party/dll-win32/` or `dll-win64/`.
  - `_buildruntime32.bat` / `_buildruntime64.bat` ? `cl.exe` build of
    `tree-sitter.dll` runtime library with explicit `/MACHINE:X86` or
    `/MACHINE:X64`.
  - `_buildgrammar32_manual.bat` / `_buildgrammar64_manual.bat` ?
    direct `cl.exe` build of `tree-sitter-delphi13.dll` from
    `parser.c + scanner.c`. Replaces the `tree-sitter build` invocation
    because the bundled tree-sitter CLI defaults to x64 and ignores
    `vcvars32.bat` for cross-arch.
  - `_builddfm32_manual.bat` / `_builddfm64_manual.bat` ? same for
    `tree-sitter-dfm.dll`.

### Notes

- The IDE plugin BPL was already Win32 (correct for the IDE). The bug
  was only on the matching tree-sitter DLLs.
- Standalone CLI users who put the Win64 DLLs on PATH and ran the
  Win64 `drag-lint.exe` directly from `src/cli/Win64/Debug/` would
  have a working install; only the `third_party/dll/` bundled folder
  was broken.
- For the IDE plugin, copy the Win32 bundle next to the BPL or onto
  PATH. The Win64 bundle is irrelevant in that context ? the IDE is
  Win32.

---

## v0.35.0-alpha -- 2026-05-29

Final polish version closing the v0.16-v0.35 marathon (20 versions total).

### Added

- **Hover tooltip** (`DragLint.Plugin.HoverTracker`): a `TTimer` polls every
  200ms; when the mouse cursor is stable for >= 600ms, the caret row of the
  active editor view is looked up in the diagnostic cache. If a diagnostic is
  found, `Application.HintWindow.ActivateHint` shows the message near the
  cursor. Caret-based (not pixel-precise); limitation documented.

- **New setting `EnableHoverTooltip`** (default True): persisted in the
  registry; exposed in both Tools > drag-lint > Settings and
  Tools > Options > drag-lint (Hover Tooltip group).

- **3 new lint rules** (total built-in count now 13+):
  - `boolean-comparison-true` (info) -- `X = True` or `X = False`: redundant
    boolean comparison; use the expression directly.
  - `redundant-as-tobject` (info) -- `(X as TObject)`: every Delphi object is
    already a TObject; cast is a no-op.
  - `inherited-bare` (info) -- bare `inherited;` call: verify it invokes the
    intended ancestor method.
  Rules in both `rules/` and `third_party/dll/rules/`.

- **README rewritten** as a comprehensive getting-started guide covering CLI,
  LSP server (Zed / VS Code), MCP server (Claude / Cursor), and RAD Studio
  plugin install paths; full command/tool/rule reference.

- **T61** -- HoverTracker compile smoke (`dcc64 -B T61_hovertracker.dpr`).
- **T62** -- Verify 3 new lint rules fire on `RuleTest.pas` (extended with
  boolean compare, `as TObject`, and bare `inherited` examples).

### Changed

- VERSION bumped to `0.35.0-alpha` in `DRagLint.CLI` and `DRagLint.LSP.Server`.

### Notes

Skipped rules that require data-flow analysis (single-line-if-then,
string-concat-loop, pos-with-substring, freeandnil-missing,
repeat-without-until): tree-sitter query syntax alone is insufficient for
these; deferred to a future session with a flow analysis pass.

---

## v0.34.0-alpha -- 2026-05-29

### Added

- **Workspace mode** (`drag-lint workspace index|status|add`): a
  `.drag-lint-workspace.json` file at a repo root lists multiple projects
  (`path` + optional `scan_dir: true`) and a `shared_db` path. All projects
  index into one shared SQLite, so symbols from PACKAGE, SERVER, CLIENT, and
  COMMON are all queryable together.

  - `workspace index [--config PATH]` -- indexes every listed project into
    the shared DB. Discovers config by walking up from the current directory.
  - `workspace status [--config PATH]` -- lists projects with per-project
    file counts from the shared DB.
  - `workspace add <projfile> [--config PATH]` -- appends a new project entry
    and saves.

- **Plugin workspace detection**: `TDragLintProjectNotifier.SpawnIndexer`
  now walks up from the active `.dproj` directory looking for
  `.drag-lint-workspace.json`. When found and `EnableWorkspaceMode` is True
  (default), it spawns `workspace index --config` instead of a single-project
  index, and uses the shared DB path for the session.

- **New setting `EnableWorkspaceMode`** (default True): available in both
  Tools > drag-lint > Settings and Tools > Options > drag-lint.

- **New module** `DRagLint.Workspace.Config` (`src/workspace/`):
  `TWorkspaceConfig` record, `TWorkspaceConfigIO.LoadFromFile`,
  `SaveToFile`, `FindWorkspaceRoot`.

- **T59** -- workspace config load/save round-trip.
- **T60** -- `drag-lint workspace index` on a 1-project fixture creates
  the shared DB.

---

## v0.33.0-alpha -- 2026-05-29

### Added

- **Find Usages form** (`Ctrl+Alt+F` or `Tools > drag-lint > Find Usages...`):
  InputBox prompts for a symbol name; shells `drag-lint query find-callers
  --name <name> --context 3 --db <db> --format json`; results are grouped by
  file in a `fsStayOnTop` TTreeView form. Double-click on a caller node opens
  the file and navigates the IDE editor to that line.
  New unit: `DragLint.Plugin.UsagesForm`.

- **Symbol Search form** (`Ctrl+Alt+T` or `Tools > drag-lint > Symbol Search...`):
  Modal TForm with a debounced TEdit (300ms); calls `drag-lint query --name
  <text>` as the user types; top-30 results shown in a TListView (qualified
  name | kind | location). Enter on the selected row or double-click navigates
  the IDE editor to that location. ESC closes with no action.
  New unit: `DragLint.Plugin.SymbolSearchForm`.

- **T57** -- UsagesForm compile + public-API smoke test.
- **T58** -- SymbolSearchForm compile + public-API smoke test.

---

## v0.32.0-alpha -- 2026-05-29

### Added

- **Inline code lens** -- `TDragLintCodeLensCache` populates per-file
  symbol caller counts on `EditorViewActivated`. `PaintLine` renders
  dim grey `[N callers]` text next to method declarations. New setting
  `EnableCodeLens` (default True) gates the feature; available in both
  Tools > drag-lint > Settings and Tools > Options > drag-lint.

- **4 new tree-sitter-query lint rules** (shippable subset of planned 6):
  - `compiler-magic-comments` (info) -- flags comments containing
    TODO/FIXME/HACK/XXX.
  - `nested-with` (warning) -- flags nested `with` statements where
    scope ambiguity becomes exponential.
  - `assert-call` (info) -- flags every `Assert()` call; reminder to
    include the descriptive second argument.
  - `case-magic-numbers` (info) -- flags integer literals as case
    branch labels; consider naming the constant.

  Rules not shipped (grammar limitations): `try-without-finally` (no
  `kTry` node target), `result-assignment-after-exit` (requires flow
  analysis). With v0.28 (5 rules), v0.31 (`parser-error`), and v0.32
  (4 rules), drag-lint ships **10 built-in lint rules** plus 3
  programmatic AST checks.

- **New unit** `DragLint.Plugin.CodeLensCache` -- singleton
  `TDragLintCodeLensCache` (get/set/invalidate/populate); registered in
  both `.dpk` and `.dproj`.

- **T55** -- CodeLensCache smoke test (get, invalidate, clear, singleton
  identity).

- **T56** -- v0.32 lint rule pack smoke test (all 4 rules fire on
  `RuleTest.pas`).

---

## v0.31.0-alpha -- 2026-05-29

### Added

- **Compiler-less AST diagnostics** -- `drag-lint check-ast <file>`
  runs without `dcc.exe`. Two programmatic checks via new
  `DRagLint.Diagnostics.AstChecks.TAstChecker`:
  - `unbalanced-begin-end` -- depth-aware lexer counting begin/end
    keywords outside strings/comments; flags mismatches at file end.
  - `undeclared-identifier` -- regex-extracts identifiers (uppercase
    first letter, length > 2) and queries the symbol index; identifiers
    not found AND not in the built-in allowlist are flagged.
    Requires `--db` to be useful. Allowlist shipped in
    `rules/builtin-symbols.txt`.
  Findings flow through the same `publishDiagnostics` path; compatible
  with Zed, VS Code, or any LSP client.

- **`parser-error` rule** (`rules/parser-error.scm` +
  `rules/parser-error.json`) -- catches `ERROR` nodes emitted by the
  tree-sitter grammar for malformed syntax. Works via the existing
  `.scm` rule loader (`TLinter`).

- **MCP `run_ast_checks` tool** (14th in catalog) -- mirrors
  `run_compile_check` shape: `{"target":"path.pas","db":"..."}`.

- **Settings: `ScanLibraries` toggle** -- new checkbox in
  Tools > Options > drag-lint and Tools > drag-lint > Settings.
  When True, the plugin auto-index appends `--scan-libraries` to
  the spawned `drag-lint index` command, pulling in RTL + DevExpress
  + Spring4D + browsing-path libraries. Off by default (heavy;
  ~480k symbols on a typical install).

- **Tools > drag-lint > Run AST Checks** menu entry -- spawns
  `drag-lint check-ast <active-file>` and broadcasts `textDocument/
  didSave` for LSP refresh. Produces findings without a compiler.

---

## v0.30.0-alpha -- 2026-05-29

### Added (IDE integration)

- **Custom Structure form** (`DragLint.Plugin.StructureForm`) -- Tools >
  drag-lint > Show Structure opens a non-modal, stay-on-top TForm with
  a TTreeView populated with two roots:
  - "Diagnostics (N)" -- pulled from the v0.29 diagnostic cache;
    severity prefix + message; double-click jumps editor to line.
  - "Code Elements (M)" -- pulled from a new `TDragLintStructureCache`
    that shells out to `drag-lint surface` per file. Cached per file
    path.
  Refresh button re-pulls both. Form is a separate window rather than
  injecting into the IDE's native Structure pane (sibling-tab
  registration requires custom-window hosting that is too fragile
  across BDS versions; v0.31+ may revisit).

- **Native Tools > Options page** (`DragLint.Plugin.Options` +
  `DragLint.Plugin.OptionsFrame`) -- implements `INTAAddInOptions` so
  drag-lint appears under Tools > Options as a proper IDE-native panel.
  Frame hosts all v0.22-v0.29 settings (drag-lint.exe path, project DB
  template, AutoIndex, AutoReindexOnSave, EnableHover/Completion/
  SignatureHelp/Diagnostics, EnableInlineMarkers + 4 per-severity
  toggles). Save happens on OK click; Cancel discards changes.
  The Tools > drag-lint > Settings... menu shortcut remains and now
  shows the same form in a modal wrapper for users who prefer the menu
  flow.

### Notes

- Structure form is a standalone TForm rather than docked into the
  IDE's Structure pane. Provides the same data with less integration
  risk.
- Options frame and modal SettingsForm now share the same field set;
  v0.31 may unify them into a single TFrame consumed by both contexts.

---

## v0.29.0-alpha -- 2026-05-29

### Added

- **In-editor visual diagnostics** -- LSP `publishDiagnostics` notifications now
  paint directly into the RAD Studio editor via `IOTAEditViewNotifier`:
  - **Gutter dot** (6x6 filled circle) on every diagnostic line, colored by
    max severity on that line.
  - **Wavy underline** (2-pixel sawtooth) over the diagnostic column range,
    one per diagnostic item.
  - **Ctrl+Alt+I** -- displays a `THintWindow` popup with all diagnostic
    messages for the current cursor line.
- **Registry-aware colors** (`DragLint.Plugin.RegistryColors`) -- reads
  `HKCU\Software\Embarcadero\BDS\37.0\Editor\Highlight\` keys (`Syntax Error`,
  `Warning`, `Hint`, `Information`) so markers honor the user's custom IDE color
  theme.
- **Per-severity toggles** -- 5 new settings (`EnableInlineMarkers`,
  `ShowErrorsInline`, `ShowWarningsInline`, `ShowHintsInline`, `ShowInfoInline`)
  exposed in the Settings dialog. Defaults: markers on, Info off.
- **T47** -- smoke test: registry color reader returns non-zero defaults.
- **T48** -- smoke test: diagnostic cache stores and retrieves by file + line
  with case-insensitive path matching.

### Notes

- Mouse-hover tooltip deferred to v0.30; Ctrl+Alt+I is the v0.29 substitute.
- Theme-switch detection is not live; colors are read once at plugin load.
  Restart the IDE after changing editor colors.

---

## v0.28.0-alpha -- 2026-05-28

### Added

- **5 new built-in tree-sitter-query lint rules** under `rules/`. Each rule is
  a `.scm` tree-sitter query + `.json` metadata pair. Loaded automatically at
  startup from `<exedir>/rules/` by the existing v0.3 `TQueryRules` engine.

  | Rule id | Severity | Description |
  |---------|----------|-------------|
  | `goto-statement` | warning | `goto` is a Delphi anti-pattern |
  | `with-statement` | info | `with` makes symbol scope ambiguous |
  | `empty-procedure-body` | info | `begin end` body with no statements |
  | `large-magic-number` | info | Numeric literal not in the common-constants allow-list |
  | `string-equality-comparison` | info | `=` binary expression (fires on all `=`, not just strings -- type-aware precision deferred to v0.19+) |

- **`tests/fixtures/T44_lint_pack.bat`** -- regression test that runs
  `drag-lint lint RuleTest.pas` and asserts all 5 new rules fire.

### Notes

- Rules use predicates shipped in v0.3 (`#eq?`, `#not-eq?`, `#match?`,
  `#not-match?`). The `empty-procedure-body` rule uses `#match?` on the body
  text -- it does not fire when `begin` and `end` are separated by comments.
- The `string-equality-comparison` rule is intentionally over-eager: it fires
  on every `=` binary expression regardless of type. Precise string-only
  detection waits on v0.19+ type-resolution data being plumbed into the lint
  engine.
- The original `writeln-in-source` rule remains as the reference example for
  the `.scm` + `.json` authoring pattern.

---

## v0.27.0-alpha -- 2026-05-29

### Added

- **`drag-lint generate-test --qname X [--framework dunitx|dunit]`** --
  emits a DUnitX (or DUnit) test scaffold for the given symbol.
  Builds `T<Class><Method>Tests` with `[TestFixture]` + `[Test]`
  attributes, HappyPath body instantiates the subject + asserts via
  `Assert.AreEqual`, EdgeCases body has a TODO.

- **`drag-lint format <file> [--yadf-path PATH]`** -- shells to YADF
  (https://github.com/Alexl-git/YADF) for in-place .pas/.dpr/.dpk
  formatting. Auto-detects YADF.exe via `HKCU\Software\YADF\ExePath`
  registry, then `C:\Projects\YADF\Win32\Release\EXE\YADF.exe`
  fallback. 30s timeout.

- **Plugin: Refactor preview form** (`DragLint.Plugin.RefactorForm`)
  replaces the v0.24 two-`InputBox` flow with a proper VCL modal
  dialog. Symbol qname + new name fields, Write .bak checkbox,
  Preview button (runs `drag-lint rename --dry-run` and shows the
  edit list in a memo), Apply button (enabled only after a successful
  preview; confirms via MessageDlg before applying).

- **Plugin Tools menu `Format with YADF`** -- shells `drag-lint format
  "<active-file>"` and shows YADF stdout summary. User saves manually
  before running.

### Notes

- Test stub generation is name-based -- the suggested class instantiation
  doesn't import the unit; you'll need to add the `uses` clause yourself.
- YADF format runs in-place. If the file has unsaved IDE buffer changes,
  YADF formats the on-disk version while the IDE buffer remains stale.
  Future v0.28+ may integrate Save-before-Format.
- Refactor preview dialog still calls drag-lint.exe as a subprocess
  rather than direct interop. Keeps the design-time package small.

---

## v0.26.0-alpha -- 2026-05-29

### Added ? compiler diagnostic integration (replaces Error Insight)

The pipeline that lets the plugin replace RAD Studio's Error Insight with
the real dcc32/dcc64 H/W/E/F output. Four components ship in v0.26:

- **`drag-lint compile-check <target>`** -- runs the appropriate
  compiler against a `.dproj` (msbuild) or `.pas` (dcc64 -Q -B),
  parses every H/W/E/F line, and INSERTS into the v0.8 `compiler_findings`
  table. Output: text summary or `--format json`. Exit codes:
  0 success, 1 errors found, 2 spawn failed.

- **LSP `publishDiagnostics` now merges compiler findings.** When the
  IDE plugin (or any LSP client) saves a file, the editor's diagnostics
  panel includes BOTH our lint findings AND any compiler findings in the
  database for that file. Source tags: `'drag-lint'` for lint,
  `'dcc'` for compiler.

- **MCP `run_compile_check` tool** -- Claude/Cursor/etc. can request
  a compile, get back the structured finding array. Tool 13 in our
  catalog. Args: `{target, msbuild_path?, db?}`.

- **Plugin Tools menu adds two entries**:
  - `Tools > drag-lint > Compile && Diagnose` -- spawns msbuild against
    the active project's .dproj, captures output, persists findings,
    broadcasts `textDocument/didSave` to refresh the LSP diagnostics
    view for every affected file. Shows a summary dialog.
  - `Tools > drag-lint > Import Build Log...` -- TOpenDialog to browse
    for a saved msbuild/dcc output file; parses, persists, broadcasts
    didSave.

### Notes

- Single-file `.pas` compile-checks can fail when cross-unit dependencies
  aren't available. That's expected -- the parser still ingests the
  resulting errors so you see what would need to be fixed.
- `Clear Compiler Findings` Tools menu entry is deferred to v0.27
  to avoid pulling FireDAC into the design-time plugin.
- Refactor preview form (originally v0.25 F1, then v0.26 carry-over)
  is deferred again to v0.27. The InputBox + ShowMessage flow from
  v0.24 still works; v0.27 will give it a proper VCL form.

---

## v0.25.0-alpha -- 2026-05-29

### Added

- **`drag-lint generate-docs --qname X [--format xmldoc|pasdoc]`** --
  generates a doc-comment stub for a symbol. Parses the signature
  (or falls back to reading the declaration line from source when
  the signature field is empty), extracts parameters and return type,
  and emits an XMLDoc `/// <summary>...` block or a PasDoc `{** ... *}`
  block. Pipe stdout into your editor or clipboard.

- **MCP tool `generate_doc_stub`** -- same as the CLI.

- **`drag-lint find-deadcode [--kind K] [--include-private]`** --
  inverse of v0.17 `impact`. Lists symbols with zero callers in the
  index (excluding constructors/destructors and known entry points
  like `Main`, `Register`, `initialization`, `finalization`).
  Output: `<qname>  [<kind>]  <file>:<line>`.

- **MCP tool `find_deadcode`** -- same as the CLI.

### Notes

- Refactor preview form (the originally-planned v0.25 F1) moves to
  v0.26 along with the bigger compiler-diagnostic integration scope.
- Dead-code analysis is name-based (same caveat as v0.24 rename):
  symbols in unrelated classes with the same short name are treated
  as cross-referenced. Precision-perfect mode awaits `refs.symbol_id`
  population (still parked).
- Doc stubs are pure scaffolding -- they emit TODO placeholders for
  the user to fill in. v0.26 may add LLM-assisted prose suggestions
  via the existing context-bundle infrastructure.

---

## v0.24.0-alpha -- 2026-05-29

### Added (Refactoring)

- **`drag-lint rename --qname Foo.TBar.Baz --to NewName`** -- rewrites
  every occurrence of a symbol. Uses the existing index's
  declaration site + `FindCallersByName` results. Edits are sorted
  back-to-front so applying them doesn't shift columns mid-pass.
  Source files are written back as ANSI + CRLF to preserve the
  project's strict-ASCII conventions. A `.bak` backup is written before
  each file mutation unless `--no-backup` is passed. `--dry-run` shows
  the diff without writing. Exit codes: 0 success, 1 not-found,
  2 collision, 3 I/O error.

- **MCP tool `rename_symbol`** -- same as the CLI, callable from
  Claude/Cursor/etc. Args: `{qname, to, dry_run?, db?}`. Returns
  `{edits: [...], files_touched: N, applied: bool}`. Total MCP tool
  count is now 12.

- **Plugin Tools menu `Rename Symbol...`** -- two InputBox prompts
  (qname + new name) and shows the equivalent CLI command. v0.24
  plugin is dry-run only -- full integration (synchronous spawn +
  apply on confirm) moves to v0.25 polish. Keystroke `Ctrl+Alt+R`.

### Notes

- Rename is name-based, not inheritance-aware. Overrides that share
  the same name will be renamed; symbols in unrelated classes with the
  same short name will ALSO be renamed (since `FindCallersByName` is
  name-based, not symbol-id-based). v0.22+ remains parked on
  populating `refs.symbol_id` for precision; once that lands the
  rename can become id-based.
- DFM event-handler bindings (`OnClick = btnOKClick` etc.) are indexed
  as `event-binding` refs in v0.16; the rename catches those too
  because `FindCallersByName` returns them. Saving forms after a
  rename will then sync the .dfm with the .pas.

---

## v0.23.0-alpha -- 2026-05-29

### Added (editor reactivity)

- **Custom completion popup form** (`DragLint.Plugin.CompletionForm`).
  Borderless `fsStayOnTop` TListBox popup replaces `ShowMessage` for
  Show Completion. Parses LSP completion items into glyph-prefixed rows
  (M/f/C/F/v/T/I/U/p/e/R for LSP CompletionItemKind values), Enter or
  double-click inserts via `IOTAEditWriter.Insert`, ESC and deactivate
  close, 30s timer fallback.

- **Custom signatureHelp popup form** (`DragLint.Plugin.SignatureForm`).
  Borderless single-line TLabel popup. Shows full signature with the
  active param index appended as `[arg N]`. ESC/deactivate/30s-timer close.

- **Background reindex on file save** (`DragLint.Plugin.SaveNotifier`).
  `TDragLintSaveNotifier` implements `IOTAModuleNotifier` (NOT
  `IOTAIDENotifier.ofnFileSaved` ? that enum value doesn't exist in
  Delphi 13's ToolsAPI). `AfterSave` per-module; checks the
  `AutoReindexOnSave` setting + extension whitelist (.pas/.dpr/.dpk/.inc/
  .dfm) + cached project DB path, then spawns `drag-lint.exe index <file>
  --db <projdb>` detached. Cache `GLastProjectDb` is set by the existing
  project-open hook.

- **New setting `AutoReindexOnSave`** (REG_DWORD, default 1). Toggle in
  Tools ? drag-lint ? Settings dialog.

### Notes

- True incremental `textDocument/didChange` remains deferred ? we still
  treat on-disk file as source of truth.
- IOTAOptionsForm (proper Tools ? Options integration) still deferred.

---

## v0.22.0-alpha -- 2026-05-29

### Added (IDE polish)

- **Auto-index on project open** (`DragLint.Plugin.ProjectNotifier`). The
  plugin hooks `IOTAIDENotifier.FileNotification`; when a `.dproj` opens,
  it spawns `drag-lint.exe index <projdir> --db <projdir>\.drag-lint.sqlite`
  asynchronously (CreateProcessW with DETACHED_PROCESS) and posts an
  "indexing project..." title message to the IDE Messages pane. Honors the
  AutoIndex toggle (default ON) from settings.

- **Settings persistence + Tools menu dialog** (`DragLint.Plugin.Settings`
  + `DragLint.Plugin.SettingsForm`). Registry-backed config at
  `HKCU\Software\drag-lint\DelphiPlugin` with seven fields: ExePath,
  DbPathTemplate (use `<projdir>` for project dir), AutoIndex, EnableHover,
  EnableCompletion, EnableSignature, EnableDiagnostics. Modal VCL settings
  dialog built programmatically (no .dfm). New menu entry "Settings..."
  under Tools > drag-lint.

- **Keystroke bindings** (`DragLint.Plugin.Keyboard`) via
  `IOTAKeyboardServices.AddKeyboardBinding`:
  - `Ctrl+Alt+H` ? Hover at Cursor
  - `Ctrl+Alt+C` ? Show Completion
  - `Ctrl+Alt+S` ? Show Signature Help
  - `Ctrl+Alt+D` ? Run Diagnostics
  Each handler checks the corresponding Enable* setting before invoking.

- **Custom hover popup form** (`DragLint.Plugin.HoverForm`). Borderless
  `fsStayOnTop` VCL form replaces `ShowMessage` for hover only.
  TMemo content (Consolas 9pt), auto-sized up to 600x400, positioned just
  below the cursor. Auto-closes on ESC, click-outside (deactivation), or
  after 30s.

### Notes

- Completion + signatureHelp still use `ShowMessage` in v0.22; their custom
  popups move to v0.23.
- Incremental `didChange` editor updates and pre-D13 IDE versions remain
  deferred.

---

## v0.21.0-alpha -- 2026-05-28

### Added

- **Delphi IDE plugin (OTAPI design-time package)** ? `src/delphi-plugin/` with
  `dclDragLintWizard.bpl` design-time package for RAD Studio 13 Florence (37.0).
  Registers as a wizard in the IDE's Tools menu with four entries: Hover at Cursor,
  Show Completion, Show Signature Help, Run Diagnostics. Menu invocations are
  modal for v0.21 (no custom popup forms or keystroke bindings ? deferred to v0.22).

- **LSP client (`TDragLintLspClient`)** ? spawns `drag-lint.exe lsp` as a persistent
  subprocess with `Winapi.Windows.CreateProcess` and round-trips JSON-RPC 2.0
  requests over anonymous pipes (`CreatePipe`). Handles `initialize` ? `hover` /
  `completion` / `signatureHelp` ? `shutdown` lifecycle. Implemented in
  `DragLint.Plugin.LspClient` (unit).

- **publishDiagnostics notification routing** ? LSP `textDocument/publishDiagnostics`
  notifications are collected and posted to RAD Studio's Messages pane via
  `IOTAMessageServices.AddToolMessage`. Thread-safe via `TThread.Queue` to marshal
  IDE callbacks from the LSP client's read pump.

### Notes

- **v0.21 is scope-reduced** ? Tools menu invocation only (no keystroke bindings,
  no custom popup forms). Full editor integration with hot-keys and rich popups
  moves to v0.22 pending polish of OTAPI event wiring.
- **LSP client tested standalone** ? `tests/fixtures/T27_lsp_client.dpr` exercises
  the client with real `drag-lint.exe` binary; round-trips initialize + shutdown
  + basic requests verify the pipe protocol and JSON-RPC framing.
- **Requires PATH setup** ? the v0.21 wizard expects `drag-lint.exe` on the system
  PATH; plugin will not launch without it.
- **No schema changes.** All features are read-only over v0.20 symbol tables.

---

## v0.20.0-alpha -- 2026-05-28

### Added

- **LSP `textDocument/completion`** ? member completion after `.` (resolves LHS
  via TTypeAtResolver, enumerates child symbols), identifier completion via
  prefix LIKE match. Trigger characters `[".", "(", ","]`. Returns `CompletionList`
  with `isIncomplete: false`.

- **LSP `textDocument/signatureHelp`** ? parses function/procedure signature,
  computes `activeParameter` from comma count in the call context. Trigger
  characters `["(", ","]`.

- **LSP `textDocument/didOpen` + `textDocument/didSave`** ? triggers lint run;
  results pushed as `textDocument/publishDiagnostics` notifications. Mapped
  severities (Error/Warning/Information/Hint) + source="drag-lint" + rule code.

- **Module: `DRagLint.LSP.Completion`** ? TLspCompletion class for building
  completion and signature items.

- **Storage helpers: `FindSymbolsByPrefix` + `FindAllChildSymbols`** ? query the
  symbol_table for prefix-matched identifiers and child symbols of a given
  parent.

### Notes

- **`didChange` deliberately not wired in v0.20** ? server re-runs lint only on
  `didSave` (file-based, matching the indexer model). v0.21 OTAPI will be the
  path to incremental updates.
- **Completion uses prefix-LIKE** ? no fuzzy matching yet. Defer to v0.21+.
- **Integration verified** ? LoopFBN.pas test confirms 5 lint findings round-trip
  into LSP diagnostics correctly.

---

## v0.19.0-alpha -- 2026-05-28

### Added

- **`drag-lint typeat file:line:col`** ? resolves the identifier at the given
  source position and returns containing symbol (unit, class, method),
  token text, resolved symbol (with qualified name), signature, and documentation.
  Supports dotted access (e.g., `Foo.Bar`) via parent_id lookup against class
  / record / interface parent symbols. Example: `drag-lint typeat Docs.pas:42:15
  --db myproj.sqlite` resolves the symbol at line 42, column 15.

- **MCP: `get_type_at_position` tool** ? same as CLI `typeat` but callable from
  Claude Code, Cursor, or Zed. Arguments: `file` (relative path from repo root),
  `line` (1-based), `col` (1-based), `db` (optional path to SQLite).

- **LSP: textDocument/hover enriched** ? when hovering over an identifier
  reference (not just declaration), hover now includes resolved symbol info
  (qualified name, signature, doc) via the type-at-position resolver.

### Notes

- **Pragmatic scope:** Top-level symbols (units, classes, methods) and dotted
  access against known class/record/interface parent symbols. Unresolved
  positions (e.g., inside `with` statements, generic substitutions, local
  variables) return a clear note rather than an error.
- **Deferred to v0.21 (OTAPI):** Local variable inference, generic type
  substitution, scope-based symbol lookup (e.g., `with TMyClass do Foo` ?
  resolve Foo as a method of TMyClass).

---

## v0.18.0-alpha -- 2026-05-28

### Added

- **`drag-lint context --task "verb qname"`** ? composes v0.16 docs + v0.17
  surface/slice/callers/impact into one AI-ready Markdown/JSON/raw payload.
  Verbs: `modify` (default), `inspect`, `refactor`, `delete`, `extend`.
  Automatically includes class surface, implementation slice, caller context
  (configurable depth), and impact summary (for refactor/delete). Output
  formats: `--format md|json|raw`. Example: `drag-lint context --task "modify
  Foo.TBar.Baz" --caller-context 3 --max-callers 10 --db myproj.sqlite`.

- **`drag-lint bench-context [--n N] [--md]`** ? measures AI token-reduction
  ratio by sampling N random documented symbols from the database. For each
  symbol, computes the bundle token estimate (using chars / 3.7 heuristic) and
  compares against the baseline (full source file char count / 3.7). Reports
  average reduction ratio: "Bundle avg 234 tokens vs Baseline avg 1847 tokens
  = 7.9x reduction". Useful for understanding bundle efficiency on real
  codebases. Token estimate is a heuristic (not BPE); v0.19+ may add real
  tokenization.

- **MCP: `get_context_bundle` tool** ? same as CLI `context` but callable from
  Claude Code, Cursor, or Zed. Arguments: `task` (string), `db` (optional path
  to SQLite), `caller_context` (optional integer, default 3), `max_callers`
  (optional integer, default 5), `format` (optional "md"|"json"|"raw").

### Notes

- **No schema changes.** All features are read-only over v0.16/v0.17 tables.
- **Token heuristic:** Reduction ratio uses simple chars / 3.7 estimate.
  Small single-file fixtures (Docs.pas, ~500 lines) may show ratio < 1 due to
  overhead. Real-project benchmarks (Micronite ORM3 with 795 files) should show
  5-10x reduction. Scaling improves as corpus size increases.
- **TBundleCaller record:** Internal structure introduced. `TContextBundle.Callers`
  array now resolves FilePath at bundle-build time (no lazy lookup).

---

## v0.17.0-alpha -- 2026-05-28

### Added

- **`drag-lint impact --qname X [--depth N]`** ? transitive callers via
  `WITH RECURSIVE` SQLite CTE. Walks the reference graph to depth N (default 3)
  and reports per-depth caller count + distinct unit count. Useful for
  blast-radius analysis: "how many units would a change to this symbol
  impact?" Output format: `Depth 1: 42 callers in 8 units (+42)`.

- **`drag-lint surface --qname TFoo [--include-impl] [--all-visibility]`** ?
  returns the class/interface/record declaration block sliced from the source
  file (interface section only, unless `--include-impl` is set). No method
  bodies, just the interface. `--all-visibility` includes private/protected
  sections; default heuristic skips lines containing the word `private` (naive
  but covers 95% of real codebases). Use case: feed the surface to an AI to
  understand a type's contract without drowning in implementation detail.

- **`drag-lint slice --qname Foo.TBar`** ? returns a minimal multi-chunk
  source extraction: unit header + class declaration + per-method impl bodies
  (~70% smaller than the full unit, optimised for AI context windows). Chunks
  are tagged (`unit-header`, `class-decl`, `impl-method`, `unit-trailer`) so
  callers can reassemble or filter as needed. Impl-end detection is heuristic
  (searches for next `procedure`/`function`/`end.` line); works on standard
  formatting but may over/under-include on unusual layouts.

- **`drag-lint query find-callers --context N`** ? extends the v0.16
  `find-callers` command to include N lines of surrounding source per match.
  Each result row includes the `context_text` field (N lines before + the call
  + N lines after, from the source file). Formats: text (one per line) and
  JSON (nested array). Zero context (default) suppresses the field for
  backward compatibility.

- **MCP: 3 new tools** ?
  - `get_impact` ? same as CLI `impact`, returns transitive callers by depth.
  - `get_surface` ? same as CLI `surface`, returns class interface slice.
  - `get_slice` ? same as CLI `slice`, returns symbol-relevant unit chunks.
  - `find_callers` extended ? new optional `context` arg (integer, default 0);
    when set, each result includes `context_text`.

### Notes

- **No schema changes.** All features are read-only over v0.16's
  `symbols`, `refs`, `files` tables. Existing v4 indexes work as-is.
- **Private-section heuristic:** `surface` uses line-grep for `private` /
  `protected` to filter output. Proper visibility analysis (walking child
  symbols and their `modifiers` column) is deferred to v0.18.
- **Impl-end heuristic:** `slice` detects procedure/function end by finding
  the next `procedure`, `function`, `constructor`, `destructor`, or `end.`
  keyword at the source level. Non-standard indentation or unusual nesting
  may cause over/under-inclusion; use `--verbose` to inspect chunks.

---

## v0.16.0-alpha -- 2026-05-28

### Added

- **`symbol_docs` table (schema v4).** One row per documented symbol:
  `format`, `raw_block`, `summary`, `remarks`, `returns_text`, `params_json`,
  `exceptions_json`, `example_text`, `seealso_json`, `since_text`, `deprecated`
  (INTEGER flag), plus `start_line` / `end_line` for the source range.
  v3 databases are migrated transparently on first open -- no manual steps.

- **`DRagLint.Parser.DocComments` module.** A single-pass comment-region
  scanner (`TDocCommentScanner`) walks every `.pas` file and collects comment
  blocks keyed by line range. A format dispatcher (`TDocCommentParser`)
  selects the right sub-parser and populates a `TParsedDoc` record.
  `DRagLint.Parser.Delphi13` matches regions to symbols by line proximity at
  emit time.

- **XMLDoc support.** Recognises `/// <tag>...</tag>` and `{/** ... */}` blocks.
  10 tag types handled: `summary`, `remarks`, `returns`, `example`, `param`,
  `exception`, `see`, `seealso`, `since`, `deprecated`.

- **PasDoc support.** Recognises `{** ... }` and `(** ... *)` blocks with
  `@tag` prefix notation. Same 10 tags as XMLDoc.

- **Oneline support.** Single `///`, `//1`, or `///1` comment lines above a
  declaration are captured as `oneline` format with the line text as `summary`.

- **Loose comment capture** (opt-in). `{ ... }` and `(* ... *)` blocks
  immediately above a symbol are stored as `loose` format when
  `captureLooseComments: true` is set in `.drag-lint.json`. A noise filter
  (no letters = skip) suppresses divider lines. Off by default.

- **`drag-lint hover --qname X [--format md|plain|json]`.** CLI command
  returning the structured doc for any indexed symbol. Default format is
  `plain` (human-readable); `md` emits Markdown; `json` emits the raw row.

- **`drag-lint query find` extended.** Three new filters:
  - `--doc-tag deprecated` -- symbols marked `@deprecated` / `<deprecated>`.
  - `--doc-tag since` -- symbols with a `@since` / `<since>` annotation.
  - `--doc-contains TEXT` -- full-text search across `summary`, `remarks`,
    `returns_text`, `params_json`, `example_text`.
  - `--no-docs [--kind K] [--public]` -- symbols with no doc comment at all.

- **MCP: 3 new tools.**
  - `get_symbol_doc` -- returns the full structured doc row for a qualified name.
  - `find_by_doc_tag` -- returns all symbols bearing a given tag (`deprecated`
    or `since`).
  - `find_undocumented` -- returns symbols with no doc comment, with optional
    `kind` and `public_only` filters.

- **LSP `textDocument/hover` enriched.** When a symbol has a `symbol_docs`
  row the hover payload now includes summary, parameter table, returns, and
  exceptions in Markdown. Shared with the CLI `hover --format md` renderer.

- **`.drag-lint.json` `docs` section.**
  ```json
  {
    "docs": {
      "captureLooseComments": false,
      "allowBlankLineGap": 1,
      "implPrecedence": "interface"
    }
  }
  ```
  `captureLooseComments` enables the loose-comment path. `allowBlankLineGap`
  (default 1) permits up to N blank lines between a comment block and its
  symbol. `implPrecedence` (default `"interface"`, reserved for future use):
  when both interface and implementation declarations have doc comments,
  selects which side wins. v0.16 always uses interface; set up for v0.17+.

### Notes

- The comment-region scanner respects string literals (odd-quote check) and
  merges adjacent same-kind line comments (`///`) into a single block.
- Schema v3 databases auto-migrate to v4 transparently; no re-index needed
  for schema changes (existing symbols gain docs on next incremental run).

---

## v0.15.0-alpha -- 2026-05-27

### Added
- **`drag-lint export obsidian --open`** -- after writing the notes,
  creates `.obsidian/` in the output dir, registers the folder in
  `%APPDATA%\obsidian\obsidian.json`, and launches
  `obsidian://open?vault=<basename>`. Turns the previous three-step
  flow (export -> drag folder onto Obsidian -> trust vault) into a
  single CLI invocation.

### Fixed
- **Mojibake in Obsidian-export notes.** Source files contained
  literal Unicode em-dashes (`U+2014`), pipe arrows (`U+2192`), and
  ellipses (`U+2026`) interpreted by Delphi 13 as Windows-1252 bytes,
  producing `??"` etc. when written out as UTF-8. All non-ASCII
  characters scrubbed from `.pas` sources per the project's strict-
  ASCII rule. Re-export to refresh existing vaults.

---

## v0.14.0-alpha -- 2026-05-27

### Added
- **`.drag-lint.json`** ? per-project config. Located in cwd or any
  ancestor directory. Loaded before CLI flags; CLI overrides config.
  Recognised keys:
  ```json
  {
    "db": "drag-lint.sqlite",
    "project": "MyApp.dproj",
    "path": "C:/src",
    "rule": "field-by-name-in-loop",
    "watch": { "interval": 5 }
  }
  ```
- Save typing on repeat invocations:
  ```
  cd C:\proj                       # has .drag-lint.json
  drag-lint index                  # uses configured --db and --path
  drag-lint query --name TFoo      # uses configured --db
  ```

### Notes
- Missing or invalid `.drag-lint.json` is silently ignored.
- A small status line "(loaded defaults from <path>)" prints when the
  file was honoured, so you know it took effect.

---

## v0.13.0-alpha ? 2026-05-27

### Added
- **`drag-lint diff --db <old.sqlite> --db <new.sqlite>`** ? compare two
  indexes by `qualified_name`. Reports added, removed, and signature-
  changed symbols. Use case: "what did this PR change in the public
  API?" Build an index before the change, build one after, run diff.
  `--json` for tool integration.

### Example output
```
+ DRagLint.Lint.ProjectChecks.TProjectChecks  [class]
+ DRagLint.Lint.ProjectChecks.TProjectChecks.CheckUnitsInDpr  [method]
+ DRagLint.CLI.TArgs.Watch  [field]
+ DRagLint.CLI.TArgs.Interval  [field]
+ DRagLint.Lint.ProjectChecks  [unit]
Summary: 5 added, 0 removed, 0 changed
```
That diff was the captured drag-lint API delta from v0.7 to v0.13.

---

## v0.12.0-alpha ? 2026-05-27

### Added
- **`drag-lint todos [<path>]`** ? scan `.pas`/`.dpr`/`.dpk`/`.inc` for
  `// TODO`, `// FIXME`, `// HACK`, `// XXX`, `// REVIEW`, `// NOTE`
  comments. Word-boundaried so noise like "fixmessage" doesn't false-
  trip. Skips `//` inside string literals (odd-quote check on the line
  prefix). Optional author tag captured from `// TODO @alex ...` or
  `// TODO Alex: ...` forms ? must start with a letter, so Delphi's
  built-in `// TODO 1 -oAuthor -cCategory : ...` priority digits don't
  consume the slot. `--json` for tool integration.

### Examples

```
drag-lint todos C:\path\to\src
drag-lint todos C:\path\to\src --json | jq '[.[] | select(.keyword=="FIXME")]'
```

Real-world: 68 todos found in the Micronite COMMON folder; 1 in the
drag-lint self-corpus.

---

## v0.11.0-alpha ? 2026-05-27

### Added
- **`drag-lint index --watch [--interval N]`** ? keep the index hot by
  polling the target folder(s) every `N` seconds (default 5). Each tick
  re-walks every resolved file; the existing mtime+sha256 incremental
  skip means unchanged files cost roughly nothing. Self-test on the
  drag-lint corpus: first tick = 0.14s for 16 files / 315 symbols,
  subsequent ticks = 0.02s (all skipped). Combine with `--project` to
  watch every folder pulled in by a .dproj's DCC paths.

### Notes
- Polling, not OS-level filesystem events. Trade-off: simpler, portable,
  no signal-handling subtleties; latency capped at `--interval` seconds.
  A v0.12 candidate is `ReadDirectoryChangesW`-backed watcher for
  sub-second response.
- No schema bump.

---

## v0.10.0-alpha ? 2026-05-27

### Added
- **`drag-lint graph`** ? emit a unit-level dependency graph from the
  index. One node per indexed source file, one edge per (file A
  references symbol defined in file B) pair, edge weight = count of
  references. Two output formats:
  - `--format dot` ? Graphviz, renders via `dot -Tsvg drag-graph.dot -o
    drag-graph.svg` (or pasted into any online Graphviz viewer)
  - `--format mermaid` ? Mermaid syntax, renders inline in
    GitHub/Obsidian/most Markdown viewers without external tools
- `--name <substr>` filter restricts the graph to edges whose source OR
  target path contains the substring. Useful for "show me everything
  depending on or used by the parser layer" ? `--name Parser`.
- `--output <file>` writes the graph to a file instead of stdout.

### Notes
- Edge resolution is name-only: refs are joined to symbols by
  `LOWER(name)` because the indexer leaves `refs.symbol_id` NULL today.
  That means a ref to a generic name like `Create` will fan out to every
  unit defining a `Create`. Still useful as a structural snapshot ? the
  real architectural arrows dominate the small noise. A future iteration
  will resolve `symbol_id` at index time.
- Self-test on drag-lint corpus: `CLI -> Storage.SQLite (48), CLI ->
  Core.Indexer (46), CLI -> Lint.Linter (44), ...` ? matches the real
  hierarchy.

---

## v0.9.0-alpha ? 2026-05-27

### Added ? two project-shaped lint rules

- **`unit-not-in-dpr`** (project-level). Cross-checks the .dproj's
  `<DCCReference Include="..."/>` list against the matching .dpr/.dpk's
  `uses` clause. Emits a warning for every unit listed in the .dproj but
  missing from the program/package source (the dangerous case ? drops out
  of the build on next IDE re-open), and an info-level finding for the
  reverse (compiles via search path today, but IDE doesn't track it).
  Invoked via `drag-lint lint --project <file.dproj>`. Self-test on
  drag-lint itself: 0 findings (clean). Real-world test on a 700-file
  Micronite client: 22 mismatches caught, every one a real "I forgot to
  add this to the dpr" bug.

- **`inline-comment-in-multiline-args`** (file-level, layout heuristic).
  Detects trailing `// ...` comments placed inside multi-line argument
  lists, array/set literals, and record initialisers ? the exact pattern
  that YADF and other Pascal reformatters reflow incorrectly, silently
  destroying the next array element. Tracks paren/bracket depth,
  `{...}` and `(* ... *)` block comments, and `'string'` literals so URL
  fragments inside license headers don't false-trip. Skips closing-paren
  lines (no reflow target). Real-world test on Micronite client: 70 hits
  across array-of-record initialisers in `Blueprint4.ViewModel.pas`.

### Notes
- Project-level lint introduces `--project <file.dproj>` to the lint
  subcommand. File/folder lint and project lint are independent and can
  be combined in one invocation (run together, findings merge).
- No schema bump in v0.9.

---

## v0.8.0-alpha ? 2026-05-27

### Added
- **Type-use references.** The indexer now emits `kind='type_use'` references
  for every `typeref` AST node ? field types, parameter types, function
  return types, class/interface inheritance lists, generic type arguments,
  and qualified type names (`Unit.TFoo`). `find-callers --name ISymbolStore`
  on the drag-lint self-corpus now returns 5 sites (was 1): the interface
  decl, the field decl in the Indexer, the ctor parameter, the LSP field,
  and the concrete `TSQLiteSymbolStore` inheritance line. Total refs across
  the same corpus went 1251 ? 1528 (+277).
- **`drag-lint import-log <logfile>`** ? parse a msbuild/dcc compiler log
  and store findings in a new `compiler_findings` table (schema v3). Cross-
  references each finding to the indexed `files` row when the path matches,
  preserves the raw path otherwise. Accepts three formats:
  - `Foo.pas(45,10): Error E2010: ...`
  - `Foo.pas(45): Hint warning H2077: Value assigned to 'X' never used`
  - `[dcc64 Error] Foo.pas(45,10): E2010 ...`
- **`drag-lint query hints --name <code>`** ? query the compiler-finding
  store. `--name H2077` returns every dead-write the compiler flagged across
  the project, with file/line. `--rule <severity>` filters by severity
  (Fatal/Error/Warning/Hint). Useful answer to "where's the dead code?" ?
  the Delphi compiler already knows; this just stores its answer for
  cross-session querying.

### Notes
- Schema bumped to v3 (`compiler_findings` table + index). v2 indexes are
  upgraded transparently ? existing fuzzy/symbol tables are untouched.

---

## v0.7.0-alpha ? 2026-05-27

### Added
- **LSP position resolution.** `textDocument/definition`,
  `textDocument/references`, and (new) `textDocument/hover` now work on
  the cursor position. Implementation reparses the file under the URI
  with tree-sitter, walks to the smallest named node containing the
  cursor, drills into `genericDot`/`exprDot` to pick the rhs identifier
  if the cursor is on a qualified name, then queries the symbol table by
  that identifier text.
- **Hover** returns a Markdown block with the symbol kind + every
  qualified name matching that bare name + first declaration line.

### Fixed
- `file:///` URI encoding emitted an extra leading slash for absolute
  Windows paths (`file:////C:/...`). Strip the leading slash from the
  encoded path before prepending.

### Verified
- Cursor on `FStore.UpsertSymbol` in `DRagLint.Core.Indexer.pas`:
  - definition ? 2 results: `ISymbolStore.UpsertSymbol` (interface) and
    `TSQLiteSymbolStore.UpsertSymbol` (concrete impl), each with proper
    file URI + range
  - references ? 3 results: the call site + both declarations
- Cursor on `ISymbolStore` in the interface declaration: definition
  returns the interface decl range; references currently returns just
  the declaration because v0.7 refs are call-site-only (not type-use).
  Type-use refs are a v0.8 enhancement.

### Known limitations to flag publicly
- LSP `textDocument/references` only finds call sites today. Type uses
  (`X: ISymbolStore`, class inheritance, parameter types) are NOT
  emitted as refs by the indexer ? they'd need a parser-side
  enhancement. Tracked as v0.8.
- No incremental parse on `textDocument/didChange`. The LSP server uses
  the on-disk index + reparses the cursor's file on each request.
  Re-running `drag-lint index` is sub-second per file thanks to v0.4
  incremental, so editor save + index-on-save covers most cases.

---

## v0.6.0-alpha ? 2026-05-27

### Added
- **`drag-lint lsp`** ? Language Server Protocol stdio server, framed with
  Content-Length headers per spec. `initialize`, `shutdown`, `exit`, and
  `workspace/symbol` work today. `textDocument/definition` and
  `textDocument/references` return empty arrays (placeholders) ? they
  need position-to-token resolution which is a v0.7 item (tree-sitter
  reparse on cursor position).
- **`drag-lint top --by fanin`** ? ranks names by reference count across
  the index. Aggregates refs by name first (fast path), then attaches a
  sample symbol for context. 1.5 s on 473 k-symbol corpora.
- **`drag-lint export enums`** ? emit every `(enum, value)` pair from the
  index. Four formats: `firebird-sql` (CREATE TABLE + INSERTs), `csv`,
  `json` (nested-values), `delphi-const` (paste-ready arrays).
- **`drag-lint export obsidian`** ? write one `.md` per unit with YAML
  frontmatter, full symbol list, and a "Referenced by" section using
  `[[wikilinks]]` so Obsidian's graph view becomes a navigable
  cross-reference map of the codebase.

### Fixed
- **Parser**: multi-segment unit names like `DRagLint.Core.Interfaces`
  were getting truncated to just the first identifier (`DRagLint`).
  `WalkUnit` now takes the full text of the `moduleName` node so the
  qualified path is preserved. **Indexes built before this commit need a
  full re-index** (delete the .sqlite and re-run `drag-lint index`) to
  pick up the correct unit names.

---

## v0.4.0-alpha ? 2026-05-27

### Added
- **MCP stdio server** ? `drag-lint serve --db <file>` speaks JSON-RPC 2.0
  / MCP `2024-11-05` and exposes `find_symbol`, `find_callers`, and `lint`
  as typed tools. Claude Code / Cursor / Zed can wire it via the standard
  `mcpServers` config block. The CLI is still available for token-tight
  use; same engine underneath.
- **Incremental reindex** ? `IndexFile` skips files whose `mtime_unix` AND
  `sha256` are already in the `files` table. Reformatting an entire
  project (e.g. with YADF) and re-running `index` only re-parses the
  files that actually changed. The CLI summary line reports the skip
  count when nonzero.

### Notes
- Documentation external-vendor scrub: README, CHANGELOG, design doc,
  and `rules/README.md` no longer name specific commercial vendors or
  upstream open-source library authors except Delphi/Embarcadero
  themselves. Required attribution (MIT) is preserved in
  `third_party/<repo>/LICENSE`.

---

## v0.3.0-alpha ? 2026-05-27

### Added
- **Persistent trigram index for fuzzy lookup.** Schema bumped to v2 with a
  new `symbol_trigrams` table populated alongside every symbol insert.
  Fuzzy queries on 473k-symbol indexes drop from ~5,500 ms to ~520 ms
  (>10? improvement). Legacy v1 databases are upgraded lazily on first
  fuzzy query.
- **`drag-lint index --scan-libraries`** ? index Delphi Library + Browsing
  paths from the registry (HKCU + HKLM, Win32 + Win64) without needing a
  `.dproj`. Useful as a one-time "library knowledge base" build.
- **Multi-database queries** ? repeat `--db <file.sqlite>` to query across
  several indexes at once. Results are concatenated. Useful for separating
  per-project indexes from a shared `delphi-libs.sqlite`.
- **Tree-sitter query predicates** (`#eq?`, `#not-eq?`, `#match?`,
  `#not-match?`, `#any-of?`, `#not-any-of?`) evaluated by the external
  rule loader. Sample `writeln-in-source.scm` now uses `(#eq? @callee
  "WriteLn")` so it fires only on real `WriteLn` calls.

### Changed
- README + design docs reworded to avoid naming any prior commercial tool.

### Known limitations
- Fuzzy lookup latency target was <500 ms ? we hit ~520 ms on 473k symbols.
  Further wins likely need a daemon (MCP server in v0.4).
- `--scan-libraries` pulls in a wide path set ? a large 3rd-party VCL
  component library alone can take 3 minutes to index. Use `--dry-run`
  first to inspect what will be scanned.

---

## v0.2.0-alpha ? 2026-05-27

### Added
- **Full symbol coverage**: `interface`, `record`, `enum`, `enum_value`,
  `property`, `field` symbols emitted in addition to the v0.1 set
  (`unit`, `class`, `method`, `procedure`, `function`, `constructor`,
  `destructor`).
- **DFM form indexing** (via `tree-sitter-dfm.dll`). `object Name: TClass`
  emits `form` (root) or `component` (nested); event-handler bindings
  (`OnClick = btnOKClick`) emit references that show up in `find-callers`.
- **External lint rule plugins**. `<exedir>\rules\*.scm` query files +
  matching `*.json` metadata loaded at startup and run alongside built-in
  rules.
- **`drag-lint index --project <file.dproj>`** mode. Resolves the .dproj's
  `DCC_UnitSearchPath`, the .dpr's `uses X in 'path'` clauses, and Library
  + Browsing paths from registry (HKCU + HKLM, Win32 + Win64). Expands
  `$(BDS)` macros and deduplicates the result.
- `--dry-run` flag to inspect the resolved folder list without indexing.

### Changed
- `FindCallersByName` no longer hardcodes `kind='call'` ? matches all
  reference kinds including DFM event-bindings.

---

## v0.1.0-alpha ? 2026-05-27

Initial public surface:
- Indexer for `.pas`, `.dpr`, `.dpk` via `tree-sitter-delphi13`
- SQLite store (FireDAC), per-file transactions
- `query --name`, `query --qname` with **fuzzy fallback** (Levenshtein)
- `query find-callers --name <X>` returns deterministic call sites
- Built-in lint rule `field-by-name-in-loop`
- CLI: index / query / lint / --json / --version / --help

Scaled tested on:
- Micronite ORM3 (708 .pas + 86 .dfm + .dpr + .dpk = 795 files) ? 44 169
  symbols, 42 341 references, 8 s
- Delphi RTL+VCL+FMX+Data (1295 files) ? 212 083 symbols, 250 663 references,
  60 s
- Large 3rd-party VCL component library full install (4460 files) ?
  473 756 symbols, 387 668 references, 179 s
