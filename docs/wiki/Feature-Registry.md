# Feature Registry

The master list of every feature drag-lint ships, as data: one JSON file per
feature under `features\entries\`, two imported families (lint rules from
`drag-lint rules --json`, chart questions from `REPORT_QUESTIONS`), groups and
teams as data, and a generator that writes the pages you are reading the index
of. The registry owns the LIST; the detail page for each feature stays with the
team that shipped it -- the registry only has to know it exists and link to it.

## What it generates (never hand-edit these)

* [Home](Home) -- intro from `features\templates\Home.intro.md`, the status line
  from the source constants, the "Start here" table from entries with `homeOrder`.
* [Features](Features) -- one section per group, a table per section, live rule counts.
* [Feature Index](Feature-Index) -- by surface type: Main menu, Right-click menus,
  Tool windows, CLI verbs, Scripts and tools, Diagrams and charts, Lint rules.
  `tools\build-manual.ps1` keys on these headings.
* [Quick Help](Quick-Help) -- one line per feature with the short help and aliases.
* The `dl:registry` blocks in `README.md` (per-group summary) and `docs\AI-USAGE.md`
  (verb -> feature -> page for agents).
* `features\generated\manifest.json` -- the whole registry expanded, for other tools.

## Registering a feature (every shipped change, however small)

1. `pwsh -File tools\feature-registry.ps1 add -Id <id> -Title "<name>" -Group <group> -Owner <TEAM> -Summary "<one line>" -Intro "<what, when, needs>" -WikiPage <page> -Surface "cli:<verb>[/<sub>] ;; ide-menu:drag-lint > Uses & Dependencies > Call Graph" [-Requires index,...] [-Aliases "..."]`
   -- an unknown group or team is refused unless `-NewGroup` / `-NewTeam` creates it.
   Several surfaces go in one `-Surface` argument separated by ` ;; `.
2. Write or update `docs\wiki\<page>.md` -- you own it.
3. `pwsh -File tools\build-feature-pages.ps1 -Normalise` and commit the regenerated pages,
   blocks and manifest WITH the feature.
4. `pwsh -File tests\autotest\run_feature_registry_guard.ps1` -- it names exactly
   what is missing and prints a JSON skeleton for it.
5. Moving or renaming a menu item? `feature-registry.ps1 blast-radius -MenuPath "drag-lint > Uses & Dependencies"`
   first, then `move-menu -From "<old prefix>" -To "<new prefix>"`, in the same commit
   as the plugin change.

## Other verbs

`update -Id x -Set "field=value ;; field2=value2"`, `find -Text <words>`,
`deprecate -Id x -SupersededBy y`, `normalise` (canonical form), `check`
(the guard's checks A-D on their own), `generate -Check` (the publish gate used by
`tools\publish-wiki.ps1`, `build\pack-lint-release.ps1` and `tools\publish-release.ps1`).

## Script reference

Every flag of the three registry scripts. Each script's own comment header says
the same; the two must agree.

### `tools\feature-registry.ps1 <verb> ...`

| Verb | Flags |
|---|---|
| `add` | `-Id <id> -Title <t> -Group <g> -Owner <TEAM> -Summary <s> -WikiPage <page> -Surface "<spec> ;; <spec>"`; optional `-Intro <i>`, `-Status shipped\|experimental\|planned\|deprecated\|internal`, `-Since <ver>`, `-Audience human\|agent\|both`, `-Requires <tok,...>`, `-Aliases <a,...>`, `-Related <id,...>`, `-Notes <n>`, `-HomeOrder <n>`, `-By <who>` (default: the user name); `-NewGroup -GroupTitle <t> -GroupSummary <s>` registers an unknown group, `-NewTeam -TeamTitle <t> -TeamSummary <s>` an unknown team |
| `update` | `-Id <id> -Set "field=value ;; field2=value2"` -- JSON for arrays and objects (`aliases=["a","b"]`); `field=` with no value removes the field |
| `find` | `-Text <text>` [`-IncludeChildren`: also the lint-rule and chart-question family rows] |
| `blast-radius` | one of `-MenuPath "<node>"`, `-VerbName <verb>`, `-WikiPage <page>`, `-Group <g>`; [`-IncludeChildren`] |
| `move-menu` | `-From "<old prefix>" -To "<new prefix>"` [`-WhatIf`: print, write nothing]; also rewrites `menuPrefix` in `families\chart-questions.json` when the node covers it |
| `deprecate` | `-Id <id>` [`-SupersededBy <id>`] [`-RemovedIn <ver>`] |
| `normalise` | none -- rewrites entries into canonical JSON, `groups.json` / `teams.json` one row per line; families, exemptions and related-projects get CRLF / trailing newline / BOM fixes only |
| `check` | [`-Level WellFormed\|Full`] (default `Full`, which needs the engine exe) |
| `generate` | [`-Check`] [`-OutDir <dir>`] -- the same as `build-feature-pages.ps1` |

Common to every verb: `-Repo <root>` (default: the parent of `tools\`) and `-Json`
(machine output). Surface specs: `cli:<verb>[/<sub>][|<example>]`,
`ide-menu:<full path, every level>` (for example `ide-menu:drag-lint > Uses & Dependencies > Call Graph (Butterfly)...`), `ide-context:<Structure form|Project Manager|Editor>|<caption>`,
`ide-about:<caption>`, `tool-window:<View > Tool Windows > X>`, `shortcut:<keys>`,
`lsp:<method>`, `mcp:<tool>`, `script:<repo path>[|<args>]`, `exe:<name.exe>[|<menu>]`,
`workflow:<repo .md>`. Exit codes: 0 ok, 1 refused / check failed / no hits, 2 usage.

### `tools\build-feature-pages.ps1`

| Flag | Does |
|---|---|
| (none) | regenerate every output; a file is written only when its bytes differ |
| `-Check` | write nothing; exit 1 with a diff head per output that would change (the publish gate) |
| `-OutDir <dir>` | render into another directory (the guard's byte comparison) |
| `-Normalise` | first rewrite every entry and data file into canonical form |
| `-Repo <root>` | repository root (default: the parent of `tools\`) |

Exit codes: 0 nothing changed or everything written; 1 `-Check` found a difference,
or the generator failed.

### `tools\publish-release.ps1 -Version <X.Y.Z-alpha>`

| Flag | Does |
|---|---|
| `-Version <ver>` | required; must equal `DRAGLINT_VERSION`, and `CHANGELOG.md` must have `## v<ver>` |
| `-DryRun` | print the plan with resolved paths and run only steps 0 and 2; nothing is built, published or packed |
| `-SkipBuild` | skip step 1 (the engine build, and the plugin build with it) |
| `-SkipBattery` | skip step 4 |
| `-BuildPlugin` | also build the IDE plugin in step 1 -- OFF by default, because that build writes the BPL into the registered Known Packages path, i.e. it deploys into the live IDE (RAD Studio must be closed) |
| `-Repo <root>` | repository root (default: the parent of `tools\`) |

## Publish order

`tools\publish-release.ps1` runs these in order and stops at the first failure:

0. preflight -- version constant, CHANGELOG heading, deployed engine present
1. build the engine (`build\build_draglint_win64.bat`)
2. `tools\build-feature-pages.ps1 -Check` -- the generated pages are committed
3. `tools\build-manual.ps1` -- exactly once, after the last doc change
4. `tests\run_battery.ps1`
5. `tools\publish-wiki.ps1` (re-runs the `-Check` gate itself)
6. `build\pack-lint-release.ps1 -Version <ver>` -- the deployed Debug engine in
   `third_party\dll-win64` is backed up first and restored byte-identically (sha256)
7. prints the `git tag` and `gh release create` commands, which are still run by hand

The manual is built BEFORE the battery, not after it as the spec's section 12
lists: the battery's `run_manual_freshness_guard.ps1` fails on a manual older than
the wiki, and the manual reads no battery output, so this order still rebuilds it
exactly once.

## What the guard proves, and what it only declares

Verified every battery run: CLI verbs and subcommands against `--help` and the
dispatch chain; IDE captions (menu items, right-click captions, About buttons,
tool windows) by the leaf-caption prefix rule; MCP tools against
`HandleToolsList`; script and workflow paths; wiki pages (exact case); CHANGELOG
versions; the chart catalog against the bundler's `-Question` set, two-way; the
emitter scripts two-way; the generated pages byte-for-byte.

Declared only (listed under "Declared, not harvested" on Quick Help): shortcut
keys, LSP methods, the host of a right-click caption, a menu inside another exe,
procedures. The periodic review exercises those. Submenu NESTING is not verified
in v1 -- that needs the plugin's central menu table (a later plan).

## Files

`features\groups.json`, `teams.json` (data; add through `-NewGroup` / `-NewTeam`),
`exemptions.json` (containers and headers that are not features, each WITH a
reason, asserted two-way), `seed-backlog.json` (seeded entries still owing an
`intro` and `lastVerified`; the guard prints the remaining count per team, the
deadline is the R2 installer release), `families\*.json`, `templates\*.md`,
`schema\entry.schema.json` (the field list and the canonical key order).
