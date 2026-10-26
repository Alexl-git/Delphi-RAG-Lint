# CLI flag aliases -- the policy

Owner ruling 2026-10-25 (W6-flagmap, "make ALL aliases uniform"). Supersedes the
alias half of ENG-6 (2026-09-22/23, `docs\INBOX-Done\INBOX-output-flag-canonicalisation.md`):
`--out` keeps working exactly as ENG-6 promised; what changes is that it, and every
other alias, is now shown the same way.

## What an alias is

An **alias** is a second spelling of ONE option: the parser accepts both in the same
branch (`(A = '--output') or (A = '--out')`) and sets the same `TArgs` field. Two
flags that set the same field in different branches, or a flag and a positional
argument, are NOT aliases. A flag that is accepted but does nothing (`--use-ignore`)
is not an alias either; it is a documented no-op on its verb's line.

Each alias group has exactly one **canonical** spelling. Today's table:

| Canonical | Alias(es) | Why the alias exists |
|---|---|---|
| `--force-reparse` | `--no-skip` | the first spelling of the re-parse switch |
| `--help` | `-h`, `-?` | the short tokens every CLI user tries first |
| `--in` | `--file` | one input-file option (`TArgs.InFile`); `--in` is the spelling the `ask` verb's own parser accepts, so it is the one that works on every verb |
| `--output` | `--out` | ENG-6 back-compat |
| `--scan-libraries-win` | `--scan-libraries` | the spelling before `--scan-libraries-all` existed |

## The rules

1. **One source of truth:** `features\flag-aliases.json` (canonical, aliases, reason).
   It must list exactly the parser's alias groups -- no more, no fewer.
2. **Verb lines name the canonical spelling only.** Every `--help` line -- verb lines,
   their notes, COMMON QUESTIONS -- every registry cli surface (`usage`, `help`,
   `flags[].name`) and every registry question command names the canonical flag.
   No `--output|--out`, no "(alias --out)" inline.
3. **Aliases are listed once, in generated places only:**
   * `drag-lint --help`, section `Flag aliases:` (after the verb reference), one row
     per canonical flag: `  --output                also: --out`;
   * the CLI reference pages (`WWW\help\dl\cli.md`, `features\generated\cli-reference.md`),
     section "Flag aliases";
   * `docs\AI-USAGE.md` and `README.md`, the `dl:registry flag-aliases` blocks.
   All of them are rendered by featuregen from the table; never hand-edit them.
4. **An alias is permanent and silent at run time.** It is accepted wherever its
   canonical flag is, means exactly the same, and is never warned about. Scripts that
   use one keep working.
5. **Prose docs** (README, wiki pages) write the canonical spelling in examples. An
   existing prose mention of an alias is not wrong -- it still works -- but new text
   uses the canonical one.
6. **Adding an alias** is a change to the parser AND the table in the same commit, with
   a reason; `featuregen build --all` then regenerates the three listings. Removing one
   is a breaking change and needs an owner ruling.
7. **Not an alias, so not in the table:** flags of an undocumented verb, pre-dispatch
   self-test switches and the other `$FlagUndocumentedOnPurpose` classes of
   `run_docs_sync_guard.ps1` check 9. Its old class (b) "back-compat alias" is retired:
   every alias is now printed in the `Flag aliases:` section, so none is undocumented.

## Guards

* `tests\autotest\run_flag_verb_map.ps1` -- the table equals the parser's alias groups
  (two-way); no `--help` line outside the alias rows names an alias; every alias is
  listed under its canonical flag; the per-verb gap counts an OPTION, so a verb that
  reads `TArgs.Output` and names `--output` is documented (planted controls prove an
  undocumented NON-alias flag is still counted after the fold).
* `featuregen check` (A) -- the table is well-formed (no spelling twice, no alias that
  is also a canonical) and no registry cli surface or question names an alias.
* `run_feature_registry_guard.ps1` / `featuregen check` (D) -- the generated listings
  are current; `run_docs_sync_guard.ps1` F5 needs README to name every banner flag,
  aliases included, which its `flag-aliases` block does.

## Scope

The `drag-lint` CLI. Repo tools (`featuregen`, `drag-lint-switch`) keep their own flags
and are outside this table.
