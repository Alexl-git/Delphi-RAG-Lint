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

## Verbs

Every verb takes `--repo <dir>` (default: found above the current directory) and the ones that
read the live surface take `--engine <drag-lint.exe>` (default
`third_party\dll-win64\drag-lint.exe`). `featuregen --help` is the full list.

| Verb | What it does |
|---|---|
| `build` | write the wiki pages, the README / AI-USAGE blocks, `manifest.json` and `cli-reference.md`; `--site` the website set `WWW\help\dl\` and `site-pages.json`; `--all` both; `--check` writes nothing and exits 1 when any output would change |
| `check` | the registry guard: A well-formed, B live -> registry, C registry -> live, D every generated output current, E staleness notes; `--level wellformed` is check A alone |
| `add` | register a feature; an unknown group or team is refused unless `--new-group` / `--new-team` creates it |
| `update` | change fields of one entry (`--set "field=value ;; field2=value2"`) |
| `find`, `blast-radius` | search the registry; list what a menu path, verb, wiki page or group touches |
| `move-menu` | rename a menu prefix everywhere (use `--what-if` first) |
| `deprecate` | mark an entry deprecated, optionally superseded |
| `normalise` | rewrite entries into canonical JSON |
| `import-help` | seed usage / flags / pitfalls of cli entries from the engine `--help`; never overwrites a field, never verifies |
| `audit` | one line per gap: thin entries, stale verification, changed surface |
| `verify` | stamp an entry as verified: date, who, build and a hash of its live surface |

Outputs are 7-bit ASCII with CRLF line ends, written only when the bytes differ, with no
dates in them. A non-ASCII character in a rendered output fails the build and names the
entry and the field.

## Gates

`tools\featuregen-gate.ps1` runs `featuregen build --all --check`; `publish-wiki.ps1`,
`publish-release.ps1` and `pack-lint-release.ps1` call it before they publish or pack.
`tests\autotest\run_feature_registry_guard.ps1` runs `check --level full` and the same
build check in the battery. A missing `featuregen.exe` or engine is a failure that names the
path -- never a pass.

## The self-verify rule

A commit that adds or changes a feature updates ITS OWN entry (usage, flags, steps,
questions, wiki page) and runs `featuregen verify --id <its id>`. Never verify another
team's entry; report it to its owner instead. `verify` records the build version and a hash
of the live surface, so `featuregen audit` reports "surface changed since verified" when the
help line or flags move afterwards.

## This entry

`featuregen` is registered as an `internal` entry owned by CONVERTER (the stream that
built it), so it is not advertised on the website; its surfaces are the exe, its build
script, the gate script and this page.
