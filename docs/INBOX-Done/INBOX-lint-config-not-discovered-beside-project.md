> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21).** FIXED 2026-08-16 (8d911f9): LoadLintConfig now discovers drag-lint-lint.json beside the .dproj, then in its _D-RAG folder, then the CWD. Verified -- the synthetic project A/B that previously ignored the file now honours it.

# INBOX -- `lint-all --project` does not discover `drag-lint-lint.json` beside the project

**Found:** 2026-08-12, while applying the owner ruling "commented-out-code -- disable (config only)" to YADF.
**Class:** wrong (the tool answers, but ignores a config it should have found)

## Repro

```
# with the config sitting next to the .dproj:
C:\Projects\YADF\drag-lint-lint.json   ->  { "disabled": ["commented-out-code"] }

drag-lint lint-all --project C:\Projects\YADF\YADF.dproj --db ...\YADF.sqlite
  -> commented-out-code still reported (2 findings)

drag-lint lint-all --project ... --db ... --config C:\Projects\YADF\drag-lint-lint.json
  -> 0 findings          <-- the config is honoured, it is simply never FOUND
```

## Why this is wrong now

Config discovery is CWD-only (`LoadLintConfig`: `--config`, else `drag-lint-lint.json`
in the current directory). That made sense when a run was "cd to the project, lint".
It does not survive the 2026-08-11/12 move to project-scoped everything: a project's
index lives in `<project>\_D-RAG\`, its lint ownership lives in
`<project>\_D-RAG\drag-lint-project.json`, and `--project <path>` is now the normal
way to invoke lint-all from anywhere. The lint config is the one piece of per-project
configuration that still cannot live with the project.

Consequence: a per-project rule ruling is silently a no-op unless every future
invocation remembers `--config`. Silent, because nothing reports that a config file
was found-and-ignored or not-found -- the run just uses defaults and exits 0.

Note the LSP already does the right thing: `DRagLint.LSP.Completion.DiscoverLintConfig`
walks UP from the file's directory and accepts `drag-lint-lint.json` or
`drag-lint.json`. So the editor and the CLI disagree about which rules are enabled
for the same project -- the CLI is the one that is wrong.

## Suggested fix

When `--project <file>` (or `--in <file>`) is given and `--config` is not, discover
the lint config by walking up from the PROJECT FILE's directory, reusing the LSP's
`DiscoverLintConfig` rather than writing a second discovery. Keep CWD as the
fallback so existing invocations do not change. Emit the resolved config path in the
banner -- a config that was looked for and not found should be visible, not silent.

Also worth folding in: accept `<project>\_D-RAG\drag-lint-lint.json`, so all
per-project drag-lint state sits in the one hidden folder.
