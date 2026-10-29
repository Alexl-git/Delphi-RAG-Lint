# HANDOFF 2026-10-28 -- LSP: context (LSP-1) HPS lanes running

Session lsp-52. ENGINE = delphi-rag-lint-65 (merges; 1.38.0 line after the 1.37.0 freeze).
Spec (shared by all lanes, amended 1b): `C:\TEMP\claude\lanes\lsp-context\SPEC.md`.
Owner rulings: D1 (LSP answers like the IDE: project DB + that platform's library only); owner
2026-10-28: per-project `<Base>.dlcontext.json` + `drag-lint project-context` verb + `dl-project-setup.exe`;
central settings `%LOCALAPPDATA%\drag-lint\context-defaults.json` (plugin writes, ENGINE later; LSP owns
format + reader); HPS approved. Placeholders: unknown platform -> startup --platform else Win64 + notice;
target with no library DB -> refuse + notice. Pending owner Q: LSP auto re-resolve a marked DB (default: no).

## Lanes (worktrees under .claude\worktrees\, base gaps/stage2 b401aade; nothing merged/pushed)
| Lane | Branch | State 2026-10-28 |
|---|---|---|
| CORE (Opus) | fix/lsp-context (+ clear-diags merged in) | running; also owns lf-lsp (library-first plan sec 2/5/6: per-project library + incomplete notice behind ProjectDbIncompleteReason stub); client contract: initOptions {project,platform,config}, section 'dragLint', executeCommand draglint.setContext args [{..}], notification draglint/context {project,platform,config,source,notice}, project may be a .dlcontext.json |
| CLIENT (sonnet) | fix/lsp-client-context | DONE 6e30cd5c; handed to ENGINE (merge before CORE) |
| IFCONST (sonnet) | fix/lsp-if-sourceconst | 00be8321 (ConfigureLspLint calls InstallPPUnitSource; guard RED->GREEN 5/5); follow-up running: CRLF of guard, proxy_preprocess FAIL (is it ours? test on parent build), per_file_defines result |
| GUARDS (Opus) | fix/lsp-guards-main | running (LSP-3 failing guards) |
| CTXFILE (sonnet) | feat/project-context-file | 6bef79fa handed to ENGINE (unit e3ff196b; verb flag --output, --out alias; DragLintLocalDataDir shared fn); follow-up running: per-verb help text, docs-sync/flag-verb baseline compare. featuregen verify project-context pending (ENGINE on main). Parser gap 'Platform' record field reported to ENGINE |
| SETUP (sonnet) | feat/dl-project-setup | ceeb25c2 handed to ENGINE; follow-up running: switch to CTXFILE unit (merge 6bef79fa). Non-Windows built-ins: ENGINE gaps/ext-plat in 1.37, then drop SETUP's own lists |
Also handed earlier: fix/lsp-clear-diags-on-close f719c702 + 6cc58823 (pushed to origin).

Owner ruling (late 2026-10-28): LSP auto re-indexes a DB marked needs-re-resolve, in the BACKGROUND,
as a separate engine process (one per DB, writer slot via RSV rules), "re-index in progress" notice,
re-open stores + republish on exit, no retry loop; spawn behind a stub-able seam. Sent to CORE.
ORM3 projects are Win64 only.

## State at checkpoint (91% context)
- HANDED to ENGINE (1.38 line): CLIENT 6e30cd5c; IFCONST 00be8321 (merge with GUARDS: proxy_preprocess
  guard needs a warm-up -- the first LSP lint now resolves the library DB, ~2.7 s); CTXFILE 6bef79fa;
  SETUP 52449565 (contains CTXFILE; merge CTXFILE first). ENGINE: featuregen verify project-context at INT2;
  gaps/ext-plat (non-Windows built-ins) and gaps/ext-dirword ('Platform' field parse) go into 1.37.
- STILL RUNNING at checkpoint: CORE (fix/lsp-context; told to merge CTXFILE e3ff196b; background
  re-index ruling; client contract), GUARDS (fix/lsp-guards-main; + proxy_preprocess warm-up).
  CTXFILE follow-up DONE: help OK (full help like ide-release), docs-sync 29 rule-count + flag-verb
  "+--rule" failures identical on base b401aade -- not ours. Final stays 6bef79fa.
- Pending from ENGINE: lf-marker schema + readiness API names (-> CORE), D0 target_compiler unit/record,
  ext-plat function name (-> SETUP drops its own non-Windows lists).

GUARDS DONE + handed: e348fefc (tests: wait for replies) + 27984767 (ResolveLibraryDb perf bug, 22.9 s -> 2.0 s
lint setup; ENGINE takes it into 1.37 via gaps/stage3). CORE DONE + handed: fix/lsp-context 97b17c4a (merge after CLIENT/CTXFILE/GUARDS). ALL 6 LANES DONE.
CORE follow-ups (next LSP session, 1.38): RunFullRulesLint + ShowCallers still use all startup stores
(cross-project); reindex child inherits handles (stdio pipes?); no featuregen entry for project context;
proxy mode: no auto-reindex/notices; switch marker key to LIBRARY_RESOLVE_STATE_META_KEY and use
TLibraryReadiness after lf-marker/lf-ready merge. The reboot step now only needs: no running LSP lanes.
Marker schema (sent to CORE): schema_meta.library_resolve_state (LIBRARY_RESOLVE_STATE_META_KEY, Core.Versions.pas),
JSON {state pending|bound, platform, library, reason, ...}; readiness ProbeLibraryReadiness/TLibraryReadiness in
DRagLint.CLI.LibraryReady.pas; branches gaps/lf-marker cb98fe76, gaps/lf-ready (1.38).
At /clear (95%): CORE and GUARDS still running their own bg runs, unreported. Reboot plan (ENGINE):
owner reboots before the 1.37 re-parse (~2-4 h from ~15:00); on "PREPARE-REBOOT" WIP-commit both
lanes, stop bg jobs, reply READY-FOR-REBOOT. Lane briefs: no sleep-5 loops, one waiter per file.

## Next actions
1. As each lane reports: verify (ASCII/CRLF, guard RED/GREEN, lint counts), hand the branch to ENGINE.
2. Forward ENGINE's marker schema + readiness API names (lf-ready / lf-marker) to CORE; D0 target_compiler unit/record to CTXFILE/CORE.
3. When CTXFILE's unit commit lands: tell CORE and SETUP to merge it.
4. Subagents do not survive /clear: if this session was cleared, inspect the branches above and finish inside the existing worktrees.

READY-FOR-REBOOT (2026-10-28, after /clear): all 7 LSP lane worktrees clean (no uncommitted edits), no lane processes or bg jobs running; nothing to WIP-commit. Next LSP session: CORE follow-ups listed above (1.38).
