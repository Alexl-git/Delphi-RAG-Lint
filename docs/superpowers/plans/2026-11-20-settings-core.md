# Plan: SETTINGS-CORE (1.53.0, W3) -- store unit + `settings` verb + lint read side

Spec: `docs\superpowers\specs\2026-11-20-settings-store-design.md` (read sections 3-8 first; criteria
ids S1-S14, L1-L5 below refer to it). Model: sonnet. Lane rules: v1522\COMMON-BRIEF.md + v1523\PLAN.md
section 1. No extractor/resolver/DRAGLINT_VERSION bump. Encoding: every .pas/.dpr/.ps1 7-bit ASCII
CRLF -- the Write tool emits LF, normalise with `[IO.File]::WriteAllText` after each write.

## File fence (hard)

| file | action |
|---|---|
| `src\project\DRagLint.Project.Settings.pas` | CREATE -- the store (spec D10; NOT src\config) |
| `src\cli\DRagLint.CLI.Settings.pas` | CREATE -- the verb |
| `src\lint\DRagLint.Lint.Config.pas` | MODIFY -- one method `ApplyProjectSettings` |
| `src\cli\drag-lint.dpr`, `src\cli\drag-lint.dproj` | MODIFY -- add the two new units (DCCReference + uses) |
| `src\cli\DRagLint.CLI.pas` | HUB COMMIT only (task 5), <= 30 lines |
| `tests\autotest\run_v153_SETTINGS.ps1` | CREATE -- S1-S14 |
| `tests\autotest\run_v153_SETTINGS_LINT.ps1` + `tests\autotest\fixtures\v153-SETTINGS\**` | CREATE -- L1-L5 |
| `features\entries\project-settings.json`, `docs\wiki\project-settings.md` | CREATE via featuregen add + hand-written wiki |

Anything else = stop and ask the controller.

## Task 0 -- confirm the fence with the index (5 min)

```
$dl = <lane engine copy>\drag-lint.exe ; $db = <INT DB copy of src\cli\_D-RAG\drag-lint.sqlite>
& $dl query --text "drag-lint-project.json" --substring --db $db      # 5 readers, spec section 1
& $dl query --name LoadLintConfig --db $db                             # CLI.pas, ~11550
& $dl query --name AnchorDirForDb --db $db                             # Project.OwnRoots
& $dl query --name TArgs --db $db                                      # CLI.pas record; find InFile, ProjectFromConfig, DbPath
```
Note in REPORT whether DbPath also has a "from defaults file" flag (like `ProjectFromConfig`).

## Task 1 -- RED guard for the verb (S1-S14)

Create `tests\autotest\run_v153_SETTINGS.ps1`, shape of `run_v152_DISRULE.ps1` (param `-Exe`,
default `src\cli\Win64\Debug\drag-lint.exe`; temp work dir `dl-v153-settings-<guid8>`; `Check name cond`
counters; exit = fail count; SKIP exit 0 when the exe is missing). Fixture built in the script:
`P\App.dproj` (one-line dummy), `P\_D-RAG\` (empty dir), `P\src\u.pas` (any unit), `Q\` with no `_D-RAG`.
Every engine call via a helper `Run([string[]]$argv) -> @{out; code}` (2>&1, `$LASTEXITCODE`).

Checks (one per criterion; byte checks via `[IO.File]::ReadAllBytes`):
- S1 `settings get lint.profile --project P\App.dproj` -> out '' (empty line) code 0; `get taint.envSource` -> `true`.
- S2 `settings set lint.profile strict --project ...` -> code 0; file exists; `ConvertFrom-Json` `.lint.profile -eq 'strict'`.
- S3 also `set lint.profile fast --local` -> `get` = `fast`; `list --json` row lint.profile `.source -eq 'local'`.
- S4 pre-write project file with `_comment` (array), `ownRoots` `["..\\.."]`, `zzUnknown: 1` in that order; `set taint.envSource false`; then: the three keys still present AND in that order (index of their names in the text), no byte > 127, every LF preceded by CR, `\/` not present, `list --json` `.unknown[0].key -eq 'zzUnknown'`.
- S5 `set no.such.key 1` and `unset no.such.key` -> code 2; both files' bytes identical to before (compare arrays).
- S6 `set taint.envSource maybe`, `set lint.profile ([char]0xE9)`, `set ownRoots '[]'` -> each code 2, bytes unchanged.
- S7 write `[1,2]` into the local file -> `list`, `get lint.profile`, `set lint.profile x --local`, `unset lint.profile --local` -> each code 2, output names the file; local bytes unchanged. Restore.
- S8 `set ownRoots '["src"]' --local` -> 2.
- S9 project file gets `"popupForms":[{"form":"TF","note":"n"}]`; `set popupForms x` -> 2; `get popupForms` -> code 0, output contains `"TF"`.
- S10 `set lint.profile strict` twice -> second code 1, `LastWriteTimeUtc` unchanged (sleep 1100 ms between).
- S11 `unset lint.profile` (project) with lint only holding profile -> `.lint` absent from the parsed file.
- S12 `get lint.profile --db P\_D-RAG\x.sqlite` (file need not exist) and `--in P\src\u.pas` -> both return the project value.
- S13 `get lint.profile --in Q\a.pas` with CWD = a temp dir without `_D-RAG` above it -> 2, output matches `no project`.
- S14 first `set ... --local` on a new local file -> output matches `ignore`; second set -> does not.
Also: `settings` with no sub-verb and `settings bogus` -> 2 (usage).

Run it against the INT engine: every check fails (unknown verb, exit 2/3) -> that is the RED. Record the counts.

## Task 2 -- the store unit `DRagLint.Project.Settings`

Public surface (DocInsight `///` on every public item; `<remarks>` state: not thread-safe, one
instance per call, caller frees):

```pascal
type
  ESettingsError = class(Exception);   // message is user-facing; the CLI maps it to exit 2
  TSettingKind   = (skBool, skString, skPath, skPathList, skObject, skObjectList);
  TSettingSource = (ssDefault, ssProject, ssLocal);
  TSettingDef = record
    Key, Description, Flag, DefaultJson: string;
    Kind: TSettingKind;
    LocalAllowed, Settable: Boolean;
  end;
  TSettingValue = record
    Def: TSettingDef;
    ValueJson: string;          // compact JSON of the effective value (the default when unset)
    Source: TSettingSource;
  end;
  TProjectSettings = class
  public
    class function Catalog: TArray<TSettingDef>; static;
    class function FindDef(const pKey: string; out pDef: TSettingDef): Boolean; static;
    /// spec section 5: project folder, walk-up from pInFile, AnchorDirForDb(pDb), walk-up from pCwd; '' = none
    class function ResolveAnchor(const pProject, pInFile, pDb, pCwd: string): string; static;
    constructor Create(const pAnchor: string);   // reads both files; raises ESettingsError on malformed
    destructor Destroy; override;
    function Get(const pKey: string): TSettingValue;                  // raises on unknown key
    function List: TArray<TSettingValue>;                             // catalog order
    function UnknownKeys: TArray<string>;                             // 'project:<key>' / 'local:<key>'
    function SetValue(const pKey, pText: string; pLocal: Boolean): Boolean;  // False = already that value
    function Unset(const pKey: string; pLocal: Boolean): Boolean;            // False = absent
    function AsBool(const pKey: string): Boolean;
    function AsString(const pKey: string): string;
    property Anchor: string; property ProjectFile: string; property LocalFile: string;
    property LocalFileCreated: Boolean;   // True after a SetValue created the local file (S14 note)
  end;
```

Implementation notes (all inside the unit):
- Catalog = a `const` array literal of the 9 keys in spec section 4, in that order. Descriptions <= 100 chars, ASCII. `DefaultJson`: `ownRoots` `'[]'` with description "(project folder when unset)", `reportsDir` `'""'` ("(anchor\drag-lint-reports when unset)"), `lint.config` `'""'`, `lint.profile` `'""'`, `taint.envSource` `'true'`, objects `'[]'`/`'{}'`.
- Files: `TPath.Combine(TPath.Combine(Anchor, DRAG_HOME_DIR), 'drag-lint-project.json')` and `...local.json`. Missing file = empty object. Parse with `TJSONObject.ParseJSONValue`; nil or not TJSONObject -> `ESettingsError.CreateFmt('%s: not a JSON object', [file])`. Keep both parsed roots for the instance lifetime; free in Destroy.
- Dotted path lookup: split on '.', walk TJSONObject children; a missing link = absent.
- Effective value: local (if `LocalAllowed`) > project > default. Note: a local value of a non-local key is IGNORED by Get (and listed under UnknownKeys as `local:<key>`), so a hand-edited local file cannot sneak past D7.
- Parse a value by kind: bool `SameText` true/false else raise; string/path: raise when any char > #126 or < #32; pathlist: starts with '[' -> parse JSON array of strings, else split on ',' and Trim; empty list for `ownRoots` -> raise with the TOwnRoots.Load wording ("empty ownRoots ... would report a clean project"); skObject/skObjectList -> raise "not settable: edit <file>".
- Write: compare new compact JSON with stored compact JSON -> equal = return False, no write. Otherwise set (creating intermediate objects), serialise, write `<file>.tmp` then `TFile.Delete(file)` + `TFile.Move(tmp, file)` (or `RenameFile` replacing) -- ASCII encoding, `TEncoding.ASCII`. Create `_D-RAG` with `ForceDirectories` only when the anchor came from --project or --db (the CLI passes a flag; for --in/CWD the dir exists by definition).
- Unset: remove the leaf pair; then remove each parent object that became empty (S11). Root `{}` is written as `{}` + CRLF.
- Serialiser: private `procedure WriteJson(const pV: TJSONValue; pIndent: Integer; pSb: TStringBuilder)` -- object `{` CRLF, `"key": value` per pair joined with `,` CRLF, 2-space indent per level, `}`; arrays of scalars on ONE line `["a", "b"]`, arrays holding objects one element per line; strings escaped: `"` -> `\"`, `\` -> `\\`, control chars -> `\u00XX`; NEVER escape `/`; numbers via `TJSONNumber.ToString`; bool/null literal. File ends with CRLF.
- UnknownKeys: top-level names that are neither a catalog key, nor the first segment of a dotted catalog key (`lint`, `taint`), nor `_comment`; and second-level names under `lint`/`taint` not in the catalog.

## Task 3 -- the verb `DRagLint.CLI.Settings`

```pascal
/// spec section 6; pTail = the positional words after the sub-verb plus '--local' (from TArgs.SettingsTail)
function RunSettingsVerb(const pSub: string; const pTail: TArray<string>;
  const pProject, pDb, pInFile: string; pJson: Boolean): Integer;
```
- Sub-verbs `list`, `get`, `set`, `unset`; anything else / missing / wrong word count -> usage on stderr, 2.
- Anchor = `TProjectSettings.ResolveAnchor(pProject, pInFile, pDb, GetCurrentDir)`; '' -> "drag-lint settings: no project: pass --project <.dproj>" exit 2.
- `ESettingsError` -> message on stderr (and `"error"` in --json), exit 2. SetValue/Unset False -> exit 1 with "unchanged" / "not set in <file>".
- Text and --json shapes exactly as spec section 6. JSON built with TJSONObject and `.ToJSON` is fine for stdout.
- S14 note line after a set that created the local file: `drag-lint settings: created <file> -- add _D-RAG/*.local.json to your ignore file`.
- Lint-clean: run `lint <unit> --enable magic-literal,multiple-statements-per-line,commented-out-code` on both new units; 0 on changed lines or `dl:ok` with a reason.

## Task 4 -- lint read side in `DRagLint.Lint.Config`

Add to `TLintConfig` (public, DocInsight; no new uses -- keeps the IDE BPL free of the store):
```pascal
/// <summary>Applies the per-project settings the lint path reads (spec section 7).</summary>
/// <param name="pTaintEnvSource">taint.envSource; False appends a taint "disable" of getenvironmentvariable.</param>
procedure ApplyProjectSettings(pTaintEnvSource: Boolean);
```
Body: `if not pTaintEnvSource then TaintJson:= TaintJson + ['{"disable":["getenvironmentvariable"]}'];`
(TTaintRules.LoadConfig appends `disable` lists -- TaintRules.pas ~781 -- so this is a union.)

## Task 5 -- hub commit to `DRagLint.CLI.pas` (separate commit, <= 30 lines)

1. `TArgs`: add `SettingsTail: TArray<string>;` (1 line).
2. ParseArgs sub-verb list (~line 1002): add `'settings'` to the `MatchText` array.
3. ParseArgs loop, a new arm placed BEFORE the positional-Path arm (~line 1801):
   `else if (Result.Command = 'settings') and ((A = '--local') or not A.StartsWith('--')) then Result.SettingsTail:= Result.SettingsTail + [A]`
4. Dispatch (~line 29598, beside `repo`):
   `else if Args.Command = 'settings' then Result:= RunSettingsVerb(Args.SubCommand, Args.SettingsTail, IfThen(Args.ProjectFromConfig, '', Args.ProjectPath), Args.DbPath, Args.InFile, Args.AsJson or SameText(Args.Format, 'json')) { 1.53 SETTINGS-CORE: DRagLint.CLI.Settings }`
   (if Task 0 found a DbPath-from-defaults flag, blank it the same way: a defaults-file value is not "this project").
5. `LoadLintConfig` (~11555): right after `Path:= AArgs.ConfigPath;`:
   ```pascal
   { 1.53 SETTINGS: lint.config / lint.profile / taint.envSource from <anchor>\_D-RAG\drag-lint-project(.local).json }
   var SetAnchor:= TProjectSettings.ResolveAnchor(AArgs.ProjectPath, IfThen(AArgs.StandInFor <> '', AArgs.StandInFor, IfThen(AArgs.Path <> '', AArgs.Path, AArgs.InFile)), AArgs.DbPath, '');
   var Settings:= LoadSettingsOrWarn(SetAnchor);   // in DRagLint.CLI.Settings: nil + one stderr warning on ESettingsError (L5)
   try
     if (Path = '') and (Settings <> nil) and (Settings.AsString('lint.config') <> '') then Path:= TPath.Combine(SetAnchor, Settings.AsString('lint.config'));
     var Profile:= if (AArgs.Profile = '') and (Settings <> nil) then Settings.AsString('lint.profile') else AArgs.Profile;
     ... existing chain unchanged, then Result:= TLintConfig.Load(Path, Profile) (replacing AArgs.Profile there) ...
     if Settings <> nil then Result.ApplyProjectSettings(Settings.AsBool('taint.envSource'));
   finally Settings.Free; end;
   ```
   The `try/finally` must wrap through the existing `Result:= TLintConfig.Load(...)` and its
   compliance-profile check; keep every existing line. `TPath.Combine` with an absolute second
   argument returns it unchanged (absolute `lint.config` works).
   Check `IsComplianceProfile(AArgs.Profile)` right below: switch it to the resolved `Profile`.
6. `uses`: `DRagLint.CLI.Settings`, `DRagLint.Project.Settings` (implementation section).
Count the lines (`git diff --stat`); over 30 = split nothing, report it.

## Task 6 -- RED guard for the lint side (L1-L5)

`tests\autotest\run_v153_SETTINGS_LINT.ps1` + fixture `tests\autotest\fixtures\v153-SETTINGS\`:
- `proj\App.dproj` (dummy) + `proj\_D-RAG\` + `proj\uEnv.pas`: a unit where `GetEnvironmentVariable('X')` flows into a sink taken from `rules\taint-sinks.json` (pick one the shipped rules fire on; FIRST confirm with `lint proj\uEnv.pas` that a taint finding appears -- that is the positive control; if none fires, pick another sink and say which).
- `proj\drag-lint-lint.json` = `{"enabled":["magic-literal"]}` and `proj\alt-lint.json` = `{"disabled":["magic-literal"]}`, `proj\uMagic.pas` with one magic literal.
- Copy the fixture to a temp dir per run; index it with the lane engine (`index <dir> --db <tmp>\_D-RAG\fx.sqlite` is fine HERE: a throwaway fixture DB).
Checks:
- L1 `settings set lint.config alt-lint.json` -> `lint uMagic.pas --project App.dproj` has NO magic-literal; with `--config drag-lint-lint.json` it HAS one.
- L2 config with `"profiles":{"quiet":{"disabled":["magic-literal"]}}`; `set lint.profile quiet` -> none; `--profile other-or-empty-profile` positive control as the spec says (use a second profile `loud` enabling it).
- L3 `set taint.envSource false` -> the taint finding in uEnv is gone; `unset taint.envSource` -> back.
- L4 no settings files -> `lint --json` output for both units equals a capture taken before any settings existed (compare the sorted finding list rule+line).
- L5 project settings file = `{` -> stderr has one line naming the file; findings equal L4.
RED on the INT engine: L1-L3 fail (settings ignored / verb unknown); L4/L5 pass (that is expected, say so).

## Task 7 -- build, GREEN, lint, docs

1. Build in the worktree: `build\build_draglint_win64.bat -NoStage` -> log; `BUILD_EXITCODE=0`, no `[dcc] Error`.
2. Run both guards with `-Exe <worktree>\src\cli\Win64\Debug\drag-lint.exe` -> all pass. Also re-run
   `run_v152_DISRULE.ps1`, `run_compliance_profile.ps1`, `run_taint_rules.ps1`, `run_encoding_guard.ps1`
   (lint-config regressions) with the same `-Exe`.
3. Lint: reindex a COPY of the project DB with the lane engine, then `lint` on the 3 changed/new units
   + `lint-all --db <copy>` with `--enable magic-literal,multiple-statements-per-line,commented-out-code`;
   report counts on changed lines.
4. Registry: `featuregen add --id project-settings --title "Project settings" --group maintenance --owner ENGINE --summary "Per-project settings store: drag-lint settings list|get|set|unset over _D-RAG\drag-lint-project.json and a local overlay" --intro "<1-2 sentences>" --wiki-page project-settings --surface "cli:settings ..."`; one `cli` surface per sub-verb using `sub` (`list`, `get`, `set`, `unset`), usage lines exactly as spec section 6, flags `--project`, `--db`, `--in`, `--local`, `--json`. Then `featuregen normalise`, `featuregen verify --id project-settings --by ENGINE`. NO `featuregen build --all` (INT does it).
5. Wiki `docs\wiki\project-settings.md`: the key table (spec section 4), precedence, the four sub-verbs with one example each, the local-file ignore note, "1.53.1: IDE menu, local overlay for reportsDir/fieldRepository".
6. Commits (pathspec only): (a) store + verb + Lint.Config + dpr/dproj + guards + fixture; (b) HUB commit CLI.pas alone; (c) registry entry + wiki.
7. REPORT.md: SHAs, RED/GREEN counts per guard, lint counts, R2 finding (does the LSP path see lint.config?), CHANGELOG line, hub line count.
