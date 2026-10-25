# HANDOFF 2026-10-24 -- LSP stream: group-4 cleanup (run in parallel lanes after /clear)

Owner is PRESENT (not an autonomous run). The LSP stream itself is COMPLETE on local main
(`HANDOFF-2026-10-24-lsp-stream-closeout.md`). This handoff is a NEW, small follow-up: the deferred review
minors ("group 4"), run as 3 parallel subagent lanes, each in its own worktree, merged to LOCAL main.

## Authority / where things are
- Ledger with every deferred minor and why: `.superpowers\sdd\2026-10-23-lsp\progress.md` (gitignored, local).
- Briefs/reports/reviews of the original tasks: `.superpowers\sdd\2026-10-23-lsp\briefs\task-<id>-*.md`.
- Standing backlog (local only, gitignored since fc54b176): `LSP\LSP-BACKLOG.md`.
- Owner's live-IDE checklist (Sun/Mon): `docs\PLAN-lsp-live-ide-checklist-2026-10-26.md` (gitignored). NOT part of this run.
- Main at handoff time: fc54b176 (374 ahead of origin; never push).

## The plan -- 3 lanes, by file (no two lanes edit the same unit)

Create each worktree from current main: `git worktree add C:\Projects\Delphi-RAG-lint-wt\lsp-g4<x> -b lsp/g4<x> main`.
Each builder builds its OWN engine in its worktree (rsvars + msbuild Win64 Debug `src\cli\drag-lint.dproj`; copy
`third_party\dll-win64\tree-sitter*.dll` into `src\cli\Win64\Debug\`; stage `rules\` with `robocopy /MIR` into a CLEAN
`src\cli\Win64\Debug\rules` -- NEVER xcopy into an existing rules dir, it nests and double-loads every rule).

### Lane P -- proxy (`src\lsp\DRagLint.LSP.Proxy.pas`, `...Proxy.Merge.pas`, `src\cli\DRagLint.CLI.pas`) -- model: session (concurrency)
P1. `$/cancelRequest` for an id the proxy ANSWERED ITSELF (A5 answerer: references, workspace/symbol) is still
    forwarded to DelphiLSP -- drop it (or answer nothing) when the id was consumed; guard case.
P2. `--trace` can record `P>C` before `C>P` for an answered request (reply queued / written inline before
    `TraceFrame('C>P')`) -- trace the C>P frame first; guard asserts order.
P3. Every `didChange` body is fully JSON-parsed just to mark the URI dirty (A1) -- extract the uri cheaply
    (bounded scan) and parse only when needed; keep the A1 guard green; measure before/after on a big change.
P4. A bad `--merge-budget-ms` value (non-number / negative) silently falls back to 300 (CLI.pas ~1567) -- exit 3
    with a message naming the flag, like `--delphi-lsp-bits`; registry help line unchanged.

### Lane S -- server features (`src\lsp\DRagLint.LSP.Feature.*.pas`, `...Server.pas`, `...Completion.pas`, `...SyntaxTree.pas`) -- model: sonnet (well-scoped)
S1. ExecuteCommand `draglint.showCallers` row count can differ from the codeLens number (dedup across stores vs
    per-symbol sum, ExecuteCommand.pas ~92 vs Server.pas ComputeCallerCounts) -- make them agree; guard case
    with a routine in two stores.
S2. codeLens order follows dictionary enumeration, not source order -- sort by line.
S3. inlayHint walks the whole tree on every viewport request (InlayHint.pas ~277) -- skip subtrees outside the range.
S4. inlayHint does not strip `const [ref] pA` (attribute after a modifier, InlayHint.pas ~123-132).
S5. SemanticTokens CodeMask works line by line and misses continuation lines of `{ }` / `(* *)` multi-line comments.
S6. documentSymbol reads the file on DISK, not the open buffer (TLiveDocuments) -- use the live buffer when open.
S7. Rename refuses on a line with a non-ASCII char before the name (IdentifierAtPosition takes a tree-sitter BYTE
    column, B3 passes UTF-16) -- convert UTF-16 -> UTF-8 byte column; guard case with a non-ASCII comment.
S8. S0 M1: exception isolation around feature dispatch -- one feature raising must answer the request with an
    error (-32603) and leave the server alive; needs a test-only raising feature (registered only under a test env var).

### Lane T -- tests only (`tests\autotest\*.ps1`, fixtures) -- model: sonnet
T1. `run_lsp_full_rules_guard.ps1`: timeout + bad-JSON cases need a way to substitute the child exe -- add a
    TEST-ONLY env override for the child path in Server.pas? NO: that is lane S's file. Instead coordinate: lane T
    writes the guard cases against an env var name agreed here: `DRAGLINT_FULLRULES_CHILD_EXE`; lane S adds the
    env read in Server.pas RunFullRulesLint (one line, documented as test-only). Merge S before T.
T2. Strict pre-C1 proof: build engine at 57088ad3 in a scratch worktree, run the full-rules guard with
    `-BaselineExe <that exe>` once; record the result in the ledger (no code change unless it fails).
T3. `run_lsp_impl_decl_guard.ps1` fails under Windows PowerShell 5 at a Test-Path (passes under pwsh) -- make it
    run under both, or assert pwsh in its header like the other LSP guards (check which the battery uses).
T4. implementation/declaration coverage: interface descendant, bodiless (abstract) descendant, forward-declared
    class (`ForwardLine` branch).
T5. hover merge / C3: a multi-overload hover case (facts block appears only when exactly one symbol).

### Not LSP code (route, do not fix here)
- Single-file `lint` vs `lint-all` disagree on `circular-uses` for Proxy.pas/Merge.pas -> lint-engine gap:
  file `docs\INBOX-lint-circular-uses-single-file.md` for ENGINE (repro: lint Proxy.pas vs lint-all).
- Ephemeral-index cost (`docs\INBOX-lsp-ephemeral-index-cost.md`) stays ENGINE's.

## Process (same as the stream)
For each lane: implementer (model per lane) -> review (sonnet for sonnet lanes, session model for lane P; the
reviewer is `analyst`/`general-purpose` and CANNOT write files, so it returns the verdict in its reply) -> fix round
-> merge to LOCAL main with `git commit -F <msgfile>` for merge commits -> on main run `run_encoding_guard.ps1`,
`run_docs_sync_guard.ps1` (known reds = stale deployed exe until ENGINE deploys) and every `run_lsp_*` /
`run_lsp_proxy_*` guard with a main-built engine -> announce the merge to `delphi-rag-lint-5e` (ENGINE) and
`convrules-editor-2d` (CONVERTER). No new flag is planned, so no featuregen build; if one appears, ask both teams first.
Merge order: S, then P, then T (T1 depends on S's env var).

## Gotchas (each cost time in the stream)
- Lint with `--enable magic-literal,multiple-statements-per-line,commented-out-code,review-marker-stale,review-marker-unused`
  and `--db <wt>\src\cli\_D-RAG\drag-lint.sqlite` (reindex first) -- without review-marker-stale, stale dl:ok slip through.
- A dl:ok must sit on the exact line the finding anchors to (e.g. circular-uses anchors at `unit` line 1).
- Never a raw newline inside a PowerShell regex literal (CRLF checkout on main vs LF in worktrees) -- use `\r\n`.
- Wiki/docs: any `<...>` outside backticks fails `featuregen check` D.
- Never capture a record variable (e.g. `Args`) in an anonymous method in the routine that assigns it from a
  raising call -- the stdout-hygiene breadcrumb bug (596fa797).
- `git status` "M" with an empty `git diff` = line-ending noise; `git worktree remove` then needs `--force`.
- PowerShell: never pass a commit message as a here-string positional (it becomes a pathspec); use `-F <file>`.
- A merge in the main tree can fail transiently ("stash failed") when another team runs git at the same moment: retry.

## First action after /clear
Read this file, then `git -C C:\Projects\Delphi-RAG-lint log --oneline -3` (re-check main), create the 3 worktrees,
and dispatch lanes S, P, T in parallel (one message, three Agent calls).