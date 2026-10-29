# featuregen

`featuregen.exe` owns the feature registry (`features\`) and generates every page that is
built from it. It replaced the PowerShell scripts `tools\feature-registry.ps1`,
`tools\build-feature-pages.ps1` and `tools\FeatureRegistry.psm1` at the cut-over (the
outputs it writes are byte-identical to what those scripts wrote; the golden files under
`src\tools\featuregen\tests\fixtures\golden` are the proof). It is a developer tool: it
needs a repository clone, and it is never part of a release package -- the payload guard
(`tests\autotest\run_release_pack_payload_guard.ps1`) fails if `pack-lint-release.ps1`
ever names it.

Source: `src\tools\featuregen\`. Build: `build\_build_featuregen_local.bat` (Win64; the exe
is `src\tools\featuregen\featuregen.exe`, gitignored). Tests: `build\_build_featuregen_tests_local.bat`
then `src\tools\featuregen\tests\FeatureGenTests.exe`, or `tests\autotest\run_featuregen_tests.ps1`.

Tests read the live engine from the environment variable `FEATUREGEN_TEST_ENGINE` (fallback: the main-tree\n`drag-lint.exe`) and keep their scratch files in a per-run folder under the temp directory.\n\nLint: featuregen has no `.dproj`; its index is a directory index. After an edit run\n`drag-lint.exe index src\tools\featuregen --db src\tools\featuregen\_D-RAG\featuregen.sqlite` and\n`drag-lint.exe lint-all --db src\tools\featuregen\_D-RAG\featuregen.sqlite --enable magic-literal,multiple-statements-per-line,commented-out-code`\n(expected: 0 findings; `drag-lint-lint.json` beside the sources holds the naming setting).\n\n## Verbs

Every verb takes `--repo <dir>` (default: found above the current directory) and the ones that
read the live surface take `--engine <drag-lint.exe>` (default
`third_party\dll-win64\drag-lint.exe`). `featuregen --help` is the full list. `featuregen` is not on PATH: call `src\tools\featuregen\featuregen.exe` from the repo root.

| Verb | What it does |
|---|---|
| `build` | write the wiki pages, the README / AI-USAGE blocks, `manifest.json` and `cli-reference.md`; `--site` the website set `WWW\help\dl\` and `site-pages.json` (each `index.json` row: id, title, summary, group, order, since, file, then `menus` = the ide-menu paths, `context` = the ide-context surfaces as `Host > Caption`, `verb` = the first cli verb, `""` when none); `--all` both; `--check` writes nothing and exits 1 when any output would change |
| `check` | the registry guard: A well-formed, B live -> registry, C registry -> live, D every generated output current, E staleness notes; `--level wellformed` is check A alone. B and C compare the FULL `ide-menu` path with the code-built menu tree the engine's `menu-tree --format json` reads (`src\delphi-plugin\dclDragLintWizard.dproj` + its `_D-RAG` index, kept current by `prepare_battery.ps1`): a moved item fails C (`moved -- now at <path>`), an unregistered item fails B with its full path, submenus / headers / separators are never "unregistered" and an exemption for one of them is reported as redundant; a dynamic caption is a note, never a guess. An engine without `menu-tree` (older than 1.33.0) falls back to the flat caption harvest and the leaf-only comparison; a stale or missing plugin index is a B finding that names the `index` command |
| `add` | register a feature; an unknown group or team is refused unless `--new-group` / `--new-team` creates it |
| `update` | change fields of one entry (`--set "field=value ;; field2=value2"`) |
| `find`, `blast-radius` | search the registry; list what a menu path, verb, wiki page or group touches |
| `move-menu` | rename a menu prefix everywhere (use `--what-if` first) |
| `deprecate` | mark an entry deprecated, optionally superseded |
| `normalise` | rewrite entries into canonical JSON |
| `import-help` | seed usage / flags / pitfalls of cli entries from the engine `--help`; never overwrites a field, never verifies; `--blocks` freezes each verb's help lines into its entry (`help`, `helpOrder`; see below), `--dry-run` previews |
| `audit` | one line per gap: thin entries, stale verification, changed surface; `no-access` = a shipped or experimental entry with no IDE surface (ide-menu, ide-context, ide-about, tool-window) and no `access` review |
| `review-access` | record that an entry with no IDE surface was reviewed: `--id a,b --access cli-only\|repo-tooling\|standalone-app --by <TEAM>` sets `access` and `accessReviewed {date, by}`; every id is checked before the first write |
| `verify` | stamp an entry as verified: `--id <id> --by <TEAM>` records date, who, build and a hash of its live surface |

Outputs are 7-bit ASCII with CRLF line ends, written only when the bytes differ, with no
dates in them. A non-ASCII character in a rendered output fails the build and names the
entry and the field.

## Gates

`tools\featuregen-gate.ps1` runs `featuregen build --all --check`; `publish-wiki.ps1`,
`publish-release.ps1` and `pack-lint-release.ps1` call it before they publish or pack.
`tests\autotest\run_feature_registry_guard.ps1` runs `check --level full` and the same
build check in the battery. A missing `featuregen.exe` or engine is a failure that names the
path -- never a pass.

## Docs-drift checks (C1-C4)

`check --level full` also judges the PROSE a reader sees -- each entry's text and its wiki page --
against the product, so a renamed flag, a moved log or a promise that shipped cannot sit on a
page unnoticed (lane ki-docscheck; found by the ki-help pass: `-OutRoot` for `--out-root`, a log
path without `logs\`, "Planned" for a shipped verb). They live in `FeatureGen.DocsCheck.pas` and
run from `CheckProse`, because that routine already walks every entry text and wiki page beside
the harvested engine `--help`. Findings print as `C: C<n> <id>: ...`.

| Check | Rule |
|---|---|
| C1 | A `--flag` written in a backtick span or fenced line that starts `drag-lint <verb>` must be on that verb's `--help` block (usage line plus its continuation lines) or be a global flag (a `--flag` line outside every verb block). A span that opens a table row or list item with `--flag` is judged against the cli verbs of its page's entries. `--help` and `--version` always pass; a verb the help does not list is check B's business. |
| C2 | A quoted `%LOCALAPPDATA%` / `%APPDATA%` / `%TEMP%` / `%USERPROFILE%` / `%PROGRAMDATA%` path must occur in the product sources (every source file except `docs`, `WWW`, `features`, `third_party` and any `tests` / `fixtures` folder). The part after the variable is searched, cut at the first `<placeholder>` or `*`; comments count, because a documented path in the code is the contract. |
| C3 | "Planned", "until then", "not yet" or "coming" (whole words, any case) in the prose of an entry whose status is `shipped`. |
| C4 | A NOTE, never a failure: `docs-stale:` lists shipped entries verified before the newest commit that touched their verb's source (the unit named after the verb, e.g. `DRagLint.Charts.Ask.pas` for `ask`, or `sources` in `docs-check.json`). Needs `git` on PATH and a git checkout. |

Waiving an intentional example: a row in `features\docs-check.json`,
`{ "check": "C1", "where": "<entry id, or wiki page stem for page text>", "token": "--flag", "why": "<reason>" }`
(token: the flag, the path as written, or the phrase in lower case). A row with no `why` is a
failure; a row that matches nothing is a note (`docs-check: allow row ... matched nothing`), so
fixed pages shed their rows. The same file's `"sources": { "<entry id>": [ "src/...", ... ] }`
replaces C4's naming convention for that entry. Tests: `Docs.C1` - `Docs.C4` and `Docs.E2E` in
`FeatureGenTests.dpr`, each with a stale fixture that must fail and a clean control that must pass.
## The self-verify rule

A commit that adds or changes a feature updates ITS OWN entry (usage, flags, steps,
questions, wiki page) and runs `featuregen verify --id <its id> --by <TEAM>`. Never verify another
team's entry; report it to its owner instead. `verify` records the build version and a hash
of the live surface, so `featuregen audit` reports "surface changed since verified" when the
help line or flags move afterwards.

## The `--help` verb reference (P7)

The verb reference of `drag-lint --help` (everything under `Usage:`) is generated from the registry,
not typed into the CLI source. Each `cli` surface may carry two fields:

* `help` -- the verbatim help lines of that verb (usage line, flag lines, notes), as an array of strings;
* `helpOrder` -- its position in the reference (1 = first block under `Usage:`).

`featuregen build --all` renders them into `src\cli\DRagLint.CLI.HelpText.pas` (`WriteVerbReference`, one
`Writeln` per line, literals split under the compiler's 1023-character limit). The COMMON QUESTIONS banner and
the trailer (Databases, Defaults, ...) stay hand-written in `DRagLint.CLI.pas`. The generated unit is never
edited by hand; the generator marks `WriteVerbReference` with a reviewed `method-too-long` marker because its
length follows the verb count.

Seeding: `featuregen import-help --blocks` reads the live `--help`, claims each usage line for one entry (an entry
whose id is the verb, or `verb-sub`, wins over a feature entry that merely runs the verb; a usage line already
claimed gives the second entry NO block) and writes `help` / `helpOrder`. It forgets earlier blocks first, so it
is repeatable. Only public entries (not `internal` / `planned` / removed) take blocks. Guard:
`FeatureGenTests` pins the claim order, and the frozen fixture
`src\tools\featuregen\tests\fixtures\help-verb-reference-1.33.0.txt` is checked by Help.FrozenBannerPreserved: every line of it must still appear, in order, in featuregen's own verb-reference render (insertions are allowed; no exe is read).

## Entries with no IDE surface (ccess)

A shipped or experimental entry that no IDE menu, context menu, About button or tool window reaches must say WHY, so a missing menu is a decision and not an oversight. eaturegen review-access sets two optional entry fields: ccess (cli-only = a verb only, epo-tooling = a script or gate run from a clone, standalone-app = a separate program with its own UI) and ccessReviewed {date, by}. udit reports 
o-access until one is set. An entry that gets an IDE surface later drops the field.

## Verbs that take no flags (noFlags)

`audit` reports `no-flags` for a cli surface that lists no flags. A verb that genuinely takes none (`ghost-recover`, `selftest`, `contrast-selftest`) says so with the optional entry-level field `noFlags: true` (boolean, in `entry.schema.json`); `audit` then skips `no-flags` for that entry. Any other entry with no flags still gets `no-flags`. The marker is the entry owner's claim: remove it when the verb gains a flag.

## This entry

`featuregen` is registered as an `internal` entry owned by CONVERTER (the stream that
built it), so it is not advertised on the website; its surfaces are the exe, its build
script, the gate script and this page.
