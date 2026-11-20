# Per-project settings store -- design (spec)

Status: DRAFT for controller review (lane SPEC-SETTINGS, v1523 run, 2026-11-20, unattended).
Backlog: SETTINGS-STORE (v1522\BACKLOG-TRIAGE.md). Owner ruling 2026-11-19 Q1: "per-project
settings STORE + MENU (IDE + VS Code)". Binding defaults: v1523\OWNER-QUESTIONS.md Q6 (storage,
precedence) and Q7 (slices). Plans:
`docs\superpowers\plans\2026-11-20-settings-core.md` (1.53.0, W3 SETTINGS-CORE),
`docs\superpowers\plans\2026-11-20-settings-vscode.md` (1.53.0, W4 SETTINGS-VSCODE),
`docs\superpowers\plans\2026-11-20-settings-ide-menu.md` (1.53.1).

## 1. Problem

Per-project drag-lint state is spread over files nobody can see or edit from a menu:

| file | keys today | reader (unit) | writer |
|---|---|---|---|
| `<proj>\_D-RAG\drag-lint-project.json` | `ownRoots`, `excludeRoots` | `DRagLint.Project.OwnRoots.TOwnRoots.Load` | hand only |
| same | `reportsDir` | `DRagLint.Charts.Snapshot.ReadReportsDirKey` | hand only |
| same | `fieldRepository` | `DRagLint.CLI.Repo.ProjectConfigRepo` | hand only |
| same | `popupForms` (array of `{form, note}`) | `DRagLint.FormsMap.LoadPopupForms` | hand only |
| same | `checkInit.callees.<name>` = `reads`/`sets` | `DRagLint.Query.HappensBefore.LoadCalleeAnswers` | hand only |
| `<proj>\drag-lint-lint.json` or `<proj>\_D-RAG\drag-lint-lint.json` | lint rules, profiles, `taint`, `rule_overrides`, ... | `TLintConfig.Load` via `DRagLint.CLI.LoadLintConfig` (discovery chain CLI.pas ~11555) | `rules disable/enable` (CLI.RuleScope), IDE Lint Options (Lint.ConfigWriter) |
| HKCU `Software\drag-lint\DelphiPlugin` | IDE behaviour (`TDragLintSettings`) | `DragLint.Plugin.Settings` | IDE Options page |
| VS Code `settings.json` | `dragLint.*` (engine path, project, platform, config, ...) | `extension.js` | VS Code Settings UI |

There is no command that answers "what is this project's setting X, and where does it come
from", no writer for `drag-lint-project.json`, no per-user (uncommitted) override, and the
owner's motivating case -- "this project's environment is operator-set, do not treat
`GetEnvironmentVariable` as a taint source" -- is only reachable by hand-editing
`"taint": {"disable": ["getenvironmentvariable"]}` into a lint config.

## 2. Scope

IN (this spec): a typed key catalog over `drag-lint-project.json` plus a user-local overlay; the
CLI verb `settings list|get|set|unset`; three NEW keys read by the lint path; a VS Code command
over the CLI; an IDE Project Manager menu over the same store (1.53.1); moving the five existing
readers onto the store so the local overlay reaches them (1.53.1).

OUT: IDE behaviour settings (registry, per user, not per project) and VS Code `dragLint.*`
settings stay where they are. Lint-rule content (`enabled`, `disabled`, profiles, `taint`
lists, `rule_overrides`) stays in `drag-lint-lint.json`, edited by `rules disable/enable` and
the IDE Lint Options page -- the store holds project-level POINTERS and switches, never a second
copy of a lint list. The engine manifest `drag-lint.json` (and `C:\Projects\.drag-lint.json`
defaults) are machine/tree-level and out of scope.

## 3. Decisions (made unattended, controller reviews)

| # | decision | why |
|---|---|---|
| D1 | Storage = `<anchor>\_D-RAG\drag-lint-project.json` (shared, committed) + `<anchor>\_D-RAG\drag-lint-project.local.json` (this machine, not committed). | Q6 default a. The project file already exists and already has five readers; one anchor convention. |
| D2 | Precedence, most specific first: CLI flag > local file > project file > built-in default. | Q6 default a. |
| D3 | Keys are a closed CATALOG (name, type, default, local-allowed, settable, flag, consumer). `set`/`unset` of a key not in the catalog = exit 2. Unknown keys found in a file are listed as `unknown` and always preserved on write. | A typo must not silently create a dead key (same reasoning as `ApplyV152Keys`: an ignored setting looks like a feature that ignores its config). Files are hand-edited today and carry `_comment`. |
| D4 | Dotted key names address nested objects: `lint.profile` is `{"lint": {"profile": ...}}`. Existing top-level keys keep their names (`ownRoots`, `reportsDir`, ...). | Existing files stay valid byte-for-byte; no migration. |
| D5 | NEW keys in 1.53.0: `lint.config` (path), `lint.profile` (string), `taint.envSource` (bool). Nothing else new. | Each maps to a real, asked-for behaviour: `lint.config`/`lint.profile` = the project-level answer to `--config`/`--profile` (today every caller must pass them); `taint.envSource` = owner Q1 case. |
| D6 | `taint.envSource = false` APPENDS `{"disable": ["getenvironmentvariable"]}` to the effective taint config (union). The store can switch the source OFF; it cannot switch ON a source a lint config disabled. | `TTaintRules.LoadConfig` already appends `disable` lists (TaintRules.pas:781); union is monotonic and needs no conflict rule. |
| D7 | 1.53.0: the existing keys (`ownRoots`, `excludeRoots`, `reportsDir`, `fieldRepository`) are `local-allowed = false`; `set --local` on them = exit 2 naming 1.53.1. 1.53.1 moves their readers onto the store and flips `reportsDir` and `fieldRepository` to local-allowed. `ownRoots`/`excludeRoots` stay project-only for good (they define what the PROJECT is; a per-machine difference would make two developers' lint-all disagree). | The 1.53.0 fence does not include those readers; a local value they do not read would be a lie. |
| D8 | `popupForms` and `checkInit` are catalog entries with `settable = false` (object-valued): `list`/`get` show them, `set`/`unset` = exit 2 "edit the file". | Their shape is a list of records; a key=value CLI is the wrong editor. The IDE/VS Code UIs show them read-only. |
| D9 | Writes: parse -> change one key -> serialise with 2-space indent, CRLF, 7-bit ASCII, key order preserved, written via temp file + rename. A file that does not parse is NEVER written (exit 2). A value containing a non-ASCII character = exit 2. `unset` that leaves an empty nested object removes it; `unset` that leaves the file `{}` deletes nothing and writes `{}` (the file stays). | Same file rules as the sources; never destroy a hand-edited file we cannot read. |
| D10 | The store unit is pure RTL (System.JSON, System.IOUtils) + `DRagLint.Core.Model` (for `DRAG_HOME_DIR`) + `DRagLint.Project.OwnRoots` (for `AnchorDirForDb`). It lives at `src\project\DRagLint.Project.Settings.pas` beside `OwnRoots`, NOT `src\config\` as PLAN W3 wrote. | `src\config\` holds the drag-lint-config.exe GUI sources (Config.*.pas, its own .dpr); the store must be linkable by the CLI, the LSP and the IDE BPL, like `DRagLint.Lint.ConfigWriter` is today. |
| D11 | The IDE (1.53.1) links the store unit directly (no engine child process), as `DragLint.Plugin.LintOptionsFrame` links `DRagLint.Lint.ConfigWriter`. VS Code goes through the CLI (`settings ... --json`), as `disableRule` goes through `rules disable`. | Same code, two hosts; VS Code cannot link Pascal. |
| D12 | The engine never edits `.gitignore`. `settings set --local` prints one note line when the target file is new: "add `_D-RAG/*.local.json` to your ignore file". | The engine does not own the user's VCS. (This repo's `.gitignore` has `*.local` but not `*.local.json`.) |

## 4. Key catalog (1.53.0)

| key | type | built-in default | local | settable | CLI flag | consumer |
|---|---|---|---|---|---|---|
| `ownRoots` | path[] | (project folder) | no | yes | -- | OwnRoots.Load |
| `excludeRoots` | path[] | [] | no | yes | -- | OwnRoots.Load |
| `reportsDir` | path | `<anchor>\drag-lint-reports` | no (1.53.1: yes) | yes | -- | Charts.Snapshot |
| `fieldRepository` | path | (none) | no (1.53.1: yes) | yes | `--repo` | CLI.Repo |
| `popupForms` | object[] | [] | no | no | -- | FormsMap |
| `checkInit` | object | {} | no | no | -- | Query.HappensBefore |
| `lint.config` | path | (discovery chain) | yes | yes | `--config` | CLI.LoadLintConfig |
| `lint.profile` | string | "" (no profile) | yes | yes | `--profile` | CLI.LoadLintConfig |
| `taint.envSource` | bool | true | yes | yes | -- | TLintConfig (taint) |

Types: `bool` accepts `true`/`false` (case-insensitive) on the CLI and stores a JSON bool;
`string` and `path` store a JSON string (a path is stored as given; relative paths are relative
to the anchor folder, as `ownRoots` entries already are); `path[]` accepts a JSON array text
(`["..\\.."]`) or a comma-separated list and stores a JSON array of strings; an empty
`ownRoots` is refused (exit 2) with the same message `TOwnRoots.Load` gives.

## 5. Anchor (which project)

Resolved once per call, first hit wins:
1. `--project <x.dproj|.dpr|.dpk>` -> the project file's folder;
2. `--in <file>` (alias `--file`) -> walk up from the file's folder to the drive root; the first
   folder that contains a `_D-RAG` directory;
3. `--db <db>` -> `AnchorDirForDb` (the folder above `_D-RAG`);
4. the current directory, same walk-up (`settings` verb only; the lint read side has no CWD step).
No anchor = exit 2 "no project: pass --project <.dproj>". The anchor need not have a
`drag-lint-project.json` yet (`set` creates it; `_D-RAG` must exist for 3/4, is created for 1/2).

## 6. CLI surface

```
drag-lint settings list  [--project <p> | --db <db> | --in <file>] [--json]
drag-lint settings get   <key> [--project <p> | --db <db> | --in <file>] [--json]
drag-lint settings set   <key> <value> [--local] [--project <p> | --db <db> | --in <file>] [--json]
drag-lint settings unset <key> [--local] [--project <p> | --db <db> | --in <file>] [--json]
```
Exit codes (as `rules disable`): 0 done; 1 nothing to do (`set` to the value already stored in
that file, `unset` of a key absent from that file); 2 usage error, unknown key, bad value,
not settable, not local-allowed, malformed file, no anchor.

Text output: `list` prints one line per catalog key, `key = value  (source)`, source one of
`local`, `project`, `default`; then `unknown: <key> (<file>)` lines. `get` prints the effective
value alone (bool lower-case, arrays/objects as compact JSON, default shown as its value).
`set`/`unset` print one line naming the file written.

`--json` shapes (one object, stdout):
```
list: {"anchor": "...", "projectFile": "...", "projectFileExists": true,
       "localFile": "...", "localFileExists": false,
       "settings": [{"key": "lint.profile", "type": "string", "value": "strict",
                     "source": "local", "default": "", "local": true, "settable": true,
                     "flag": "--profile", "description": "..."}],
       "unknown": [{"key": "foo", "file": "project"}],
       "error": ""}
get:  one element of "settings" above.
set / unset: {"ok": true, "key": "...", "file": "...", "value": <json>, "message": "..."}
```

## 7. Lint read side (1.53.0)

`LoadLintConfig` (CLI.pas) gains two steps; the order of the existing chain is unchanged:
- after `--config` and BEFORE beside-the-.dproj discovery: if `lint.config` resolves (local >
  project) for the run's anchor, that path (relative to the anchor) is the config;
- if `--profile` was not given, `lint.profile` (local > project) is the profile;
- after `TLintConfig.Load`, `TLintConfig.ApplyProjectSettings` appends the env-source disable
  when `taint.envSource` resolves to `false`.
The anchor for the lint run is the first of: `--project` folder, the walk-up from the linted file
(`--stand-in-for` real path first), `--db` -- the section 5 order without its CWD step. A
settings file that does not parse is reported as ONE stderr warning line and ignored by the lint
run (the lint itself proceeds; `settings` verbs exit 2 on it, S7). The LSP's own discovery
(`DRagLint.LSP.Completion.DiscoverLintConfig`) is NOT changed in 1.53.0 (risk R2).

## 8. Acceptance criteria (EARS; each = one failing test first)

Store / CLI (SETTINGS-CORE):
- S1 WHEN `settings get <key>` runs on a project with no settings files THE engine SHALL print the catalog default and exit 0.
- S2 WHEN `settings set lint.profile strict --project P` runs THE engine SHALL write `{"lint": {"profile": "strict"}}` into `P\_D-RAG\drag-lint-project.json`, creating the file, and exit 0.
- S3 WHEN a key is set in both files THE `get` SHALL return the local value and `list --json` SHALL report `"source": "local"`.
- S4 WHEN `set` writes a file that already holds `_comment`, `ownRoots` and an unknown key THE engine SHALL keep all three, in their order, and the file SHALL be 7-bit ASCII with CRLF line endings.
- S5 IF the key is not in the catalog THEN `set` and `unset` SHALL exit 2 and leave both files byte-identical.
- S6 IF the value does not parse for the key's type (bool `maybe`, non-ASCII text, empty `ownRoots`) THEN `set` SHALL exit 2 and write nothing.
- S7 IF the target file is not valid JSON or its root is not an object THEN `list`, `get`, `set` and `unset` SHALL exit 2 naming the file, and `set`/`unset` SHALL NOT write it.
- S8 IF `--local` is passed for a key whose `local` is false THEN `set` SHALL exit 2.
- S9 IF the key is not settable (`popupForms`, `checkInit`) THEN `set` and `unset` SHALL exit 2, and `get` SHALL print the stored JSON.
- S10 WHEN `set` is given the value already stored in that file THE engine SHALL exit 1 and not rewrite the file (mtime unchanged).
- S11 WHEN `unset` removes the last key of a nested object THE engine SHALL remove the empty object too.
- S12 WHEN `--db <dir>\_D-RAG\x.sqlite` is the only anchor THE engine SHALL use `<dir>` as the anchor; WHEN only `--in <file>` is given THE engine SHALL walk up to the first folder holding `_D-RAG`.
- S13 IF no anchor resolves THEN every sub-verb SHALL exit 2 with "no project".
- S14 WHEN `settings set --local` creates the local file THE engine SHALL print the ignore-file note once.

Lint read side (SETTINGS-CORE):
- L1 WHERE `lint.config` names a config file and no `--config` is passed THE lint run SHALL use that file even when a `drag-lint-lint.json` sits beside the .dproj (positive control: with `--config` given, `--config` wins).
- L2 WHERE `lint.profile` is set and `--profile` is not passed THE lint run SHALL apply that profile (positive control: `--profile other` wins).
- L3 WHILE `taint.envSource` is false THE taint rules SHALL NOT report a `GetEnvironmentVariable`-sourced finding (positive control: the same fixture with the key unset reports it).
- L5 IF the settings file is malformed THEN the lint run SHALL print one warning line naming it and produce the same findings as with no settings file.
- L4 WHEN no settings file exists THE lint result SHALL be identical to the 1.52.3 result on the same fixture (no-op guarantee).

VS Code (SETTINGS-VSCODE):
- V1 WHEN the user runs "drag-lint: Project Settings..." THE extension SHALL run `settings list --project <P> --json` and show one QuickPick row per catalog key with value and source.
- V2 WHEN a settable bool row is picked THE extension SHALL offer `true`, `false`, `reset to default`; a string/path row SHALL open an input box prefilled with the current value.
- V3 WHERE the key is local-allowed THE extension SHALL ask "this project (shared)" or "this machine only" and pass `--local` for the second.
- V4 WHEN the engine exits 0 or 1 THE extension SHALL show its message as information; WHEN it exits 2 THE extension SHALL show it as an error and change nothing else.
- V5 WHEN a `lint.*` or `taint.*` key changed THE extension SHALL refresh problems.
- V6 IF no .dproj is known (no server context, no `dragLint.project`) THEN the command SHALL say so and run nothing.

IDE (1.53.1):
- I1 WHEN the user right-clicks a project in the Project Manager and chooses "drag-lint: Project Settings..." THE IDE SHALL open a dialog listing every catalog key with value, source and description.
- I2 WHEN the user edits a settable key and presses OK THE IDE SHALL write it through the store unit with the chosen scope, and the file SHALL equal what `settings set` writes for the same change (byte-identical).
- I3 Non-settable keys SHALL be shown read-only.
- R1 (1.53.1 readers) WHEN `reportsDir` or `fieldRepository` is set in the local file THE snapshot folder / repository path SHALL follow the local value.

## 9. Slices (Q7)

| release | lane | content | plan |
|---|---|---|---|
| 1.52.3 | SPEC-SETTINGS | this spec + 3 plans | -- |
| 1.53.0 | SETTINGS-CORE (W3) | store unit, `settings` verb, lint read side, registry entry `project-settings` (status shipped), wiki | plans\2026-11-20-settings-core.md |
| 1.53.0 | SETTINGS-VSCODE (W4) | command + pure lib + node test + e2e guard; registry surface | plans\2026-11-20-settings-vscode.md |
| 1.53.1 | SETTINGS-IDE + SETTINGS-READERS | Project Manager menu + dialog; five readers onto the store; D7 flip | plans\2026-11-20-settings-ide-menu.md |

## 10. Risks

- R1 Registry: featuregen has no `vscode` surface type (FeatureGen.Check.pas:284-295 lists cli, ide-menu, ide-context, ide-about, tool-window, shortcut, lsp, mcp, script, exe, workflow). PLAN W4 says "entry surface vscode:". The VS Code plan uses a `workflow` surface (doc = the wiki page) unless the INT adds a `vscode` type; adding one is a featuregen change outside both lanes.
- R2 The LSP's live per-file diagnostics discover the lint config themselves (LSP.Completion DiscoverLintConfig) and spawn `lint <file>` children; the child goes through `LoadLintConfig`, so L1-L3 reach the child run, but any LSP-internal use of the discovered path does not see `lint.config`. To be checked by SETTINGS-CORE (report, do not fix outside the fence).
- R3 RTL `TJSONValue.ToJSON`/`Format` escapes `/` and its indentation is not a contract, so the plan writes a small hand serialiser (object/array/string/number/bool/null, 2-space indent, CRLF); S4 pins its bytes.
- R4 Hub commit size: `settings` needs the sub-verb list entry, one ParseArgs arm (positional key/value + `--local`), one dispatch line and two LoadLintConfig calls -- about 12 lines, inside the 30-line hub limit.
- R5 A differing owner answer to Q6/Q7 invalidates SETTINGS-CORE (PLAN section 7 item 8); all keys are additive, so nothing on disk needs undoing.
- R6 No extractor/resolver bump: the store touches no extraction. `DRAGLINT_VERSION` is bumped by the INT only.
