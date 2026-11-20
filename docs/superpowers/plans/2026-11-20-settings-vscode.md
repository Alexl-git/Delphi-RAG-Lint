# Plan: SETTINGS-VSCODE (1.53.0, W4) -- "drag-lint: Project Settings..." over the CLI

Spec: `docs\superpowers\specs\2026-11-20-settings-store-design.md` (sections 6 and 8, criteria V1-V6).
Depends on SETTINGS-CORE merged into lane/v153-int (the `settings` verb and its `--json` shapes).
Model: sonnet. Pattern to copy: the disable-rule code action -- `editors\vscode\drag-lint\lib\disablerule.js`
(pure helpers, no `vscode` import), `test\disablerule.test.js` (plain `node` + `assert`),
`extension.js` `disableRule` (~line 780, execFile of `serverExe`). Do not bump the extension version
(INT does; package.json `version` stays).

## File fence (hard)

| file | action |
|---|---|
| `editors\vscode\drag-lint\lib\projectsettings.js` | CREATE -- pure helpers |
| `editors\vscode\drag-lint\test\projectsettings.test.js` | CREATE -- node test (V1-V4 pure parts) |
| `editors\vscode\drag-lint\extension.js` | MODIFY -- one async function + one registerCommand line + require |
| `editors\vscode\drag-lint\package.json` | MODIFY -- `contributes.commands` entry (+ `commandPalette` if the file has a menu list for palette commands) |
| `tests\autotest\run_v153_SETTINGS_VSCODE.ps1` | CREATE -- argv from the lib against the real engine |
| `features\entries\project-settings.json` | MODIFY -- add a surface (see Task 5) |
| `docs\wiki\project-settings.md` | MODIFY -- a "VS Code" section |

## Task 1 -- RED: the node test

`test\projectsettings.test.js` requires `../lib/projectsettings.js` (missing -> the test throws = RED).
Assertions:
- `parseList(stdout)` on a captured `settings list --json` string (paste a literal object with two rows:
  `lint.profile` string local-allowed source `local`, `popupForms` objectList not settable) returns
  `{anchor, rows:[...], error:''}`; on non-JSON input returns `{rows:[], error:<the raw text trimmed>}`.
- `rowLabel(row)` -> `'lint.profile = "fast"'`-style label with `description` = `row.source`
  (`'(default)'` for `default`); a non-settable row's label ends with `'  (read-only)'`.
- `choicesFor(row)`: bool -> `['true','false','reset to default']`; string/path/pathList -> `null`
  (meaning: input box); not settable -> `[]`.
- `needsScopeQuestion(row)` = `row.local === true && row.settable === true`.
- `buildSetArgs({key, value, local, project})` -> `['settings','set',key,value,'--project',project,'--json']`
  plus `'--local'` before `--json` when local; `buildUnsetArgs` same with `unset` and no value.
- `describeResult(stdout, code)` -> `{ok, message}`: code 0 or 1 -> ok true, message = parsed `.message`
  or the trimmed text; code 2 -> ok false, message = parsed `.error`/`.message` or the text.
- `affectsLint(key)` = key starts with `lint.` or `taint.`.
- `projectFrom(ctxProject, configured)` -> the first of the two that ends in `.dproj` (case-insensitive), else ''.
Run: `node editors\vscode\drag-lint\test\projectsettings.test.js` -> fails (module not found). Record it.

## Task 2 -- GREEN: `lib\projectsettings.js`

CommonJS, `'use strict'`, header comment naming the spec, exports exactly the functions above. No `vscode`
import (the test runs in plain node). Run the test -> passes; also run every other `test\*.test.js`
(`Get-ChildItem editors\vscode\drag-lint\test\*.test.js | % { node $_.FullName }`) -> all pass.

## Task 3 -- the command in `extension.js`

```js
const projectsettings = require('./lib/projectsettings');
async function projectSettings() {
  const project = projectsettings.projectFrom(lastCtx && lastCtx.project, workspace.getConfiguration('dragLint').get('project'));
  if (!project) { window.showWarningMessage('drag-lint: no project -- run "drag-lint: Select project" first.'); return; }   // V6
  if (!serverExe || !fs.existsSync(serverExe)) { window.showErrorMessage('drag-lint: engine not found; set "dragLint.serverPath".'); return; }
  const run = (argv) => new Promise((resolve) => execFile(serverExe, argv, { cwd: path.dirname(project), windowsHide: true, timeout: 60000 },
    (err, so, se) => resolve({ out: String(so || '') + String(se || ''), code: err ? (typeof err.code === 'number' ? err.code : 2) : 0 })));
  const listed = projectsettings.parseList((await run(['settings', 'list', '--project', project, '--json'])).out);   // V1
  if (listed.error) { window.showErrorMessage('drag-lint: ' + listed.error); return; }
  const pick = await window.showQuickPick(listed.rows.map((r) => ({ label: projectsettings.rowLabel(r), description: r.source, detail: r.description, row: r })),
    { placeHolder: 'drag-lint project settings for ' + path.basename(project) });
  if (!pick || !pick.row.settable) return;                                                                       // I3-equivalent: read-only rows do nothing
  const row = pick.row;
  let value; const choices = projectsettings.choicesFor(row);                                                    // V2
  if (choices) { value = await window.showQuickPick(choices); } else { value = await window.showInputBox({ value: projectsettings.currentText(row), prompt: row.description, ignoreFocusOut: true }); }
  if (value === undefined) return;
  let local = false;
  if (projectsettings.needsScopeQuestion(row)) {                                                                  // V3
    const s = await window.showQuickPick(['This project (shared, committed)', 'This machine only (local file)']);
    if (s === undefined) return; local = s.startsWith('This machine');
  }
  const argv = value === 'reset to default' ? projectsettings.buildUnsetArgs({ key: row.key, local, project })
                                            : projectsettings.buildSetArgs({ key: row.key, value, local, project });
  log('project settings: ' + argv.join(' '));
  const { out, code } = await run(argv);
  const r = projectsettings.describeResult(out, code);                                                            // V4
  if (!r.ok) { window.showErrorMessage('drag-lint: ' + r.message); return; }
  window.showInformationMessage('drag-lint: ' + r.message);
  if (projectsettings.affectsLint(row.key)) await refreshProblems();                                              // V5
}
```
Add `currentText(row)` to the lib (+ one assertion): string -> the unquoted value; pathList -> comma-joined.
Register: `context.subscriptions.push(commands.registerCommand('dragLint.projectSettings', projectSettings));`
next to `dragLint.selectProject` (~line 858). Use the names `extension.js` already imports
(`window`, `workspace`, `commands`, `execFile`, `fs`, `path`, `log`, `lastCtx`, `serverExe`) -- check each
exists with that name before relying on it; adapt, do not add new globals.
`package.json` `contributes.commands`: `{"command": "dragLint.projectSettings", "title": "Project Settings...", "category": "drag-lint"}`.

## Task 4 -- e2e guard `run_v153_SETTINGS_VSCODE.ps1`

Param `-Exe` (default `src\cli\Win64\Debug\drag-lint.exe`). Temp fixture `P\App.dproj` + `P\_D-RAG\`.
Uses `node -e` to call the lib and print the argv as JSON (shape of `run_v152_BK-VSHOVER.ps1` ~line 106),
then runs that argv with `& $Exe @argv`:
- E1 `buildSetArgs({key:'lint.profile',value:'strict',local:false,project})` -> exit 0, `settings get lint.profile` = `strict`.
- E2 same with `local:true` -> the local file exists, `list --json` source `local`.
- E3 `buildUnsetArgs` local -> exit 0; again -> exit 1 and `describeResult` gives ok=true.
- E4 `buildSetArgs` for `taint.envSource` value `maybe` -> exit 2, `describeResult` ok=false and message non-empty.
- E5 `parseList` on the real `settings list --json` output -> 9 rows, keys equal the spec section 4 list in order.
- N1 every `test\*.test.js` passes under node.
- C1 `package.json` declares `dragLint.projectSettings` and `extension.js` registers it (text match on both).
RED: before Task 2/3 the node calls fail -> record. GREEN after.

## Task 5 -- registry, wiki, vsix

- featuregen has no `vscode` surface type (spec R1). Add a `workflow` surface to `project-settings`
  (`--surface "workflow:docs\wiki\project-settings.md"` via the featuregen edit path the CLI offers; if the
  entry has an `steps`/usage field for workflows, list: Command Palette > "drag-lint: Project Settings..." >
  pick key > pick value > pick scope). Run `featuregen normalise` and `featuregen verify --id project-settings --by ENGINE`.
  If featuregen rejects it, record the error in REPORT and leave the entry unchanged.
- Wiki: a "VS Code" section with the click path above.
- Build the vsix: `node editors\vscode\drag-lint\scripts\package.js` -> a .vsix appears; do NOT install it
  (deploy is the INT's job). Run `tests\autotest\run_vscode_extension_contract.ps1` and report its result.
- Commits (pathspec): (a) lib + test + extension.js + package.json + guard; (b) registry + wiki.
- REPORT.md: SHAs, node + guard RED/GREEN counts, vsix path and size, CHANGELOG line.
