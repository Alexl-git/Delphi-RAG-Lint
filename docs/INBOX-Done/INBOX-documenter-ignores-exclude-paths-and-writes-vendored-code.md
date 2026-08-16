> **RETIRED to INBOX-Done/ on 2026-08-15.** DEFECT WHOSE FIX IS SHIPPED and guarded by a green regression runner in the full battery.
>
> Original note follows unchanged.

# INBOX -- the documenter honours `ownRoots` but IGNORES `exclude_paths`

**Found:** 2026-08-14 (session 19 startup), in drag-lint's OWN working tree.
**Severity:** high -- it rewrites vendored upstream source under a command aimed
at the repo's own code, and the repo has an explicit written decision that this
code is "not ours to restyle".

## Symptom

Session 18's autodoc pass over drag-lint's own source left **2,300 uncommitted
inserted lines** in vendored tree-sitter bindings:

```
 M third_party/delphi-tree-sitter/TreeSitter.Query.pas   +318
 M third_party/delphi-tree-sitter/TreeSitter.pas         +1034
 M third_party/delphi-tree-sitter/TreeSitterLib.pas      +948
```

All of it generated `<remarks>` / `drag-lint:auto` blocks, largely `Used by:`
lists on one-line type aliases:

```pascal
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: declaration (TreeSitter.pas), TreeSitter.TTSNodeHelper.Symbol ...
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TSFieldId = TreeSitterLib.TSFieldId;
```

Reverted at session 19 start (`git checkout -- third_party/delphi-tree-sitter/`).
Note the earlier commit `24d1111` "Add autodoc to tree-sitter bindings" means
some blocks are already at HEAD -- the revert drops only the new growth, it does
not clean the pre-existing ones.

## Root cause -- ownership is TWO settings and only ONE is threaded

drag-lint's own project declares an own-root of the **repo root**, on purpose:

`src\cli\_D-RAG\drag-lint-project.json`
```json
{ "ownRoots": ["..\\.."] }
```

with the comment *"Vendored code inside the repo is handled by `exclude_paths`
in `drag-lint-lint.json`, not here."*

`drag-lint-lint.json`
```json
{ "exclude_paths": ["*\\third_party\\*"] }
```

So for THIS repo the vendored-code exclusion lives entirely in `exclude_paths`,
and `exclude_paths` is a **lint-only** concept -- `TOwnRoots` is what the
documenter was taught about. The documenter's ownership gate therefore passes
`third_party\**` (it is inside an own root) and writes to it.

**Verified, not inferred.** `drag-lint query find-callers --name IsPathExcluded`
returns exactly ONE physical call site in the whole repo --
`DRagLint.CLI.pas:10091`, inside `lint-all`'s file loop -- and the two filters
sit on ADJACENT LINES there:

```pascal
  if Cfg.IsPathExcluded(PasPath) then begin Inc(ExcludedCount); Continue; end;
  if (not AArgs.LintThirdParty) and (not Own.IsOurs(PasPath)) then
    begin SkippedThird:= SkippedThird + [PasPath]; Continue; end;
```

`Own.IsOurs` was propagated to the writers; its neighbour was not. Any other
consumer of ownership reads half the policy.

This is the *fourth* incarnation of the same shape recorded in
`INBOX-document-project-ignores-ownroots-and-writes-into-third-party.md`, whose
own closing lesson was **"the ownership fix was applied per COMMAND"**. The
generalisation it did not make: the ownership fix was also applied per
**SETTING**. Two configuration files express "not my code" and the writer reads
one of them.

## Why it matters beyond the churn

* Every future upstream tree-sitter sync becomes a conflict, which is the exact
  reason `exclude_paths` was added (see that file's `_comment`: 134 of 2,765
  findings, 95 of them `method-pascalcase` on C binding names such as
  `ts_query_cursor_new`).
* The blocks are INDEXED, so facts get computed from generated text and fed back
  -- the same feedback loop already recorded in
  `INBOX-calls-list-harvests-english-words-from-prose.md`.
* It is self-restoring: with the blocks reverted the doc-drift checker will call
  them stale and the next `document` run writes them straight back. A revert is
  not a fix.

## Fix

1. The documenter's ownership gate must consult **both** `ownRoots` and the lint
   config's `exclude_paths`, i.e. one shared "is this file ours to write?"
   predicate used by every writer entry point -- not two independent filters.
   Candidate seam: wherever `TOwnRoots` is consulted on the `document` /
   `lint-all --fix` paths (`TDocBatch.DocumentProject`,
   `TDocLintRules.FixEditsForDocDrift`).
2. Cheap interim guard: a test that runs the documenter over this repo and
   asserts **zero** planned edits under `third_party\`.
3. Consider whether `exclude_paths` should be promoted out of `drag-lint-lint.json`
   into `drag-lint-project.json` beside `ownRoots`, so "what is mine" is one
   declaration with one loader. That is the structural fix; (1) is the tactical one.

## Reproduce

```
git -C C:\Projects\Delphi-RAG-lint status --porcelain third_party/
drag-lint document --project src\cli\<proj>.dproj --db src\cli\_D-RAG\drag-lint.sqlite --dry-run
```

Expect: planned edits under `third_party\delphi-tree-sitter\`, on a repo whose
lint config excludes exactly that directory.
