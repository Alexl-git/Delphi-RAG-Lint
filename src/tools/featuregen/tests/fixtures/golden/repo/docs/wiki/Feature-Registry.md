# Feature Registry

The master list of every feature drag-lint ships, as data: one JSON file per
feature under `features\entries\`, two imported families (lint rules from
`drag-lint rules --json`, chart questions from `REPORT_QUESTIONS`), groups and
teams as data, and a generator (`featuregen`) that writes the pages you are reading the index
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

The tool is `featuregen.exe` (see [featuregen](featuregen); it replaced the PowerShell
scripts `feature-registry.ps1` and `build-feature-pages.ps1`).

1. `featuregen add --id <id> --title "<name>" --group <group> --owner <TEAM> --summary "<one line>" --intro "<what, when, needs>" --wiki-page <page> --surface "cli:<verb>[/<sub>] ;; ide-menu:drag-lint > Uses & Dependencies > Call Graph" [--requires index,...] [--aliases "..."]`
   -- an unknown group or team is refused unless `--new-group` / `--new-team` creates it.
   Several surfaces go in one `--surface` argument separated by ` ;; `.
2. Write or update `docs\wiki\<page>.md` -- you own it.
3. `featuregen normalise`, then `featuregen build --all`, and commit the regenerated pages,
   blocks, manifest, `cli-reference.md` and website set WITH the feature.
4. `featuregen verify --id <id>` once the entry matches what you shipped -- your own entries only.
5. `pwsh -File tests\autotest\run_feature_registry_guard.ps1` -- it names exactly
   what is missing and prints a JSON skeleton for it.
6. Moving or renaming a menu item? `featuregen blast-radius --menu-path "drag-lint > Uses & Dependencies"`
   first, then `featuregen move-menu --from "<old prefix>" --to "<new prefix>"`, in the same commit
   as the plugin change.

## Other verbs

`update --id x --set "field=value ;; field2=value2"`, `find --text <words>`,
`deprecate --id x --superseded-by y`, `normalise` (canonical form), `check`
(the guard's checks A-E), `build --all --check` (the publish gate, reached through
`tools\featuregen-gate.ps1` from `tools\publish-wiki.ps1`, `build\pack-lint-release.ps1`
and `tools\publish-release.ps1`), `import-help`, `audit`, `verify`.

## Script reference

The flags of `featuregen` are on its [own page](featuregen) and in `featuregen --help`.
Surface specs: `cli:<verb>[/<sub>][|<example>]`,
`ide-menu:<full path, every level>` (for example `ide-menu:drag-lint > Uses & Dependencies > Call Graph (Butterfly)...`), `ide-context:<Structure form|Project Manager|Editor>|<caption>`,
`ide-about:<caption>`, `tool-window:<View > Tool Windows > X>`, `shortcut:<keys>`,
`lsp:<method>`, `mcp:<tool>`, `script:<repo path>[|<args>]`, `exe:<name.exe>[|<menu>]`,
`workflow:<repo .md>`. Exit codes: 0 ok, 1 refused / check failed / no hits, 2 usage.
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
2. `tools\featuregen-gate.ps1` (`featuregen build --all --check`) -- the generated pages are committed
3. `tools\build-manual.ps1` -- exactly once, after the last doc change
4. `tests\run_battery.ps1`
5. `tools\publish-wiki.ps1` (re-runs the featuregen gate itself)
6. `installer\Build-Installer.ps1` -- the Inno Setup installer is the release package;
   no zip archives are built (the deployed engine is not touched)
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

**Dialog buttons are not features, and need no exemption.** A caption assigned
to a variable declared or created as a `TButton`, `TBitBtn` or `TSpeedButton` in
the menu sources (`Go To` in the definition picker, `Fix` on an About-window
diagnose row, `Cancel`, `OK`) is harvested apart from the menu items, so check B
never asks for it. The split is by the SOURCE CONSTRUCT, not by the word: a menu
item captioned `OK` is still a menu caption and still fails B until it is
registered (the guard has a control for exactly that). Check C still accepts a
dialog button as live for an `ide-about` surface. `exemptions.json` is for
containers and headers only; the guard fails if it carries a dialog button.
Limitation: receivers are matched by variable NAME across the menu units, so a
button and a menu item sharing one variable name would both count as buttons.

## Files

`features\groups.json`, `teams.json` (data; add through `--new-group` / `--new-team`),
`exemptions.json` (containers and headers that are not features, each WITH a
reason, asserted two-way), `seed-backlog.json` (seeded entries still owing an
`intro` and `lastVerified`; the guard prints the remaining count per team, the
deadline is the R2 installer release), `families\*.json`, `templates\*.md`,
`schema\entry.schema.json` (the field list and the canonical key order).
