'use strict';

// Drives the VS Code extension's private-engine-copy logic WITHOUT VS Code.
//
// Why a harness rather than a manual click-through: the failure modes that
// matter here -- a copy interrupted halfway, a destination locked by a second
// window, a rule file deleted upstream that lingers in the copy for ever --
// are all invisible in the happy path and none of them are reachable through
// activate() without a live editor. They ARE reachable through mirrorEngine(),
// which the extension exports for exactly this.
//
// The `vscode` module is stubbed: only workspace.getConfiguration and
// window.createOutputChannel are touched by the code under test.
//
// Prints one line per assertion, "PASS <name>" / "FAIL <name>: <detail>", and
// exits non-zero on any failure. run_vscode_engine_copy.ps1 renders that.

const fs = require('fs');
const os = require('os');
const path = require('path');
const Module = require('module');

// --- config the stub will serve --------------------------------------------
let settings = {};

const vscodeStub = {
  workspace: {
    getConfiguration() {
      return { get: (k) => settings[k] };
    }
  },
  window: {
    createOutputChannel() { return { appendLine() {}, dispose() {} }; },
    showErrorMessage() {}, showInformationMessage() {}, showWarningMessage() { return Promise.resolve(); },
    setStatusBarMessage() {}
  },
  commands: { registerCommand() { return { dispose() {} }; }, executeCommand() {} }
};

const langClientStub = {
  LanguageClient: function () { this.start = () => Promise.resolve(); this.stop = () => Promise.resolve(); },
  TransportKind: { stdio: 'stdio' },
  CloseAction: { Restart: 1, DoNotRestart: 2 },
  ErrorAction: { Continue: 1, Shutdown: 2 }
};

const origLoad = Module._load;
Module._load = function (request, parent, isMain) {
  if (request === 'vscode') return vscodeStub;
  if (request === 'vscode-languageclient/node') return langClientStub;
  return origLoad.apply(this, arguments);
};

const extPath = path.resolve(__dirname, '..', '..', 'editors', 'vscode', 'drag-lint', 'extension.js');
const ext = require(extPath);
const T = ext.__test;

let failed = false;
function check(name, ok, detail) {
  if (ok) { console.log('PASS ' + name); }
  else { console.log('FAIL ' + name + (detail ? ': ' + detail : '')); failed = true; }
}

// --- a fake deployed engine folder -----------------------------------------
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'draglint-enginecopy-'));
const srcDir = path.join(root, 'dll-win64');
const storeDir = path.join(root, 'globalStorage');
fs.mkdirSync(srcDir, { recursive: true });
fs.mkdirSync(path.join(srcDir, 'rules'), { recursive: true });
fs.mkdirSync(storeDir, { recursive: true });

const srcExe = path.join(srcDir, 'drag-lint.exe');
fs.writeFileSync(srcExe, 'BUILD-1');
fs.writeFileSync(path.join(srcDir, 'drag-lint.json'), '{"indexes":[]}');
fs.writeFileSync(path.join(srcDir, 'tree-sitter.dll'), 'ts');
fs.writeFileSync(path.join(srcDir, 'tree-sitter-delphi13.dll'), 'ts13');
fs.writeFileSync(path.join(srcDir, 'tree-sitter-dfm.dll'), 'tsdfm');
fs.writeFileSync(path.join(srcDir, 'rules', 'a.scm'), 'rule-a');
fs.writeFileSync(path.join(srcDir, 'rules', 'b.scm'), 'rule-b');
// Deliberately present and deliberately NOT mirrored: ~60 MB in real life.
fs.writeFileSync(path.join(srcDir, 'drag_lint_graph.exe'), 'graph');
fs.writeFileSync(path.join(srcDir, 'dclDragLintWizard.bpl'), 'bpl');

T.setContext({ globalStorageUri: { fsPath: storeDir } }, null);
settings = { engineSource: srcExe, engineUpdate: 'onActivate', serverPath: '' };

const dstDir = T.privateEngineDir();
const dstExe = path.join(dstDir, 'drag-lint.exe');

// --- 1: POSITIVE CONTROL ----------------------------------------------------
let r = T.mirrorEngine(false);
check('first mirror reports refreshed', r.refreshed === true, r.reason);
check('the copy exists and is NOT the source path', r.exe === dstExe && fs.existsSync(dstExe), r.exe);
check('the copied exe has the source content', fs.readFileSync(dstExe, 'utf8') === 'BUILD-1');
check('the DB manifest came along (it is read from beside the exe)',
      fs.existsSync(path.join(dstDir, 'drag-lint.json')));
check('the tree-sitter runtimes came along',
      fs.existsSync(path.join(dstDir, 'tree-sitter.dll')) &&
      fs.existsSync(path.join(dstDir, 'tree-sitter-delphi13.dll')) &&
      fs.existsSync(path.join(dstDir, 'tree-sitter-dfm.dll')));
check('the rules tree came along', fs.existsSync(path.join(dstDir, 'rules', 'a.scm')));
// NEGATIVE CONTROL on the file list: "copy everything" would also pass every
// assertion above, and would drag ~60 MB the language server never opens.
check('the BPL and graph exe were NOT copied',
      !fs.existsSync(path.join(dstDir, 'drag_lint_graph.exe')) &&
      !fs.existsSync(path.join(dstDir, 'dclDragLintWizard.bpl')));

// --- 2: it does not re-copy an unchanged engine -----------------------------
r = T.mirrorEngine(false);
check('an unchanged source is not re-copied', r.refreshed === false && r.reason === 'already current', r.reason);

// --- 3: a new build IS picked up --------------------------------------------
fs.writeFileSync(srcExe, 'BUILD-2-LONGER');
r = T.mirrorEngine(false);
check('a changed source is copied', r.refreshed === true, r.reason);
check('and the copy now has the new content', fs.readFileSync(dstExe, 'utf8') === 'BUILD-2-LONGER');

// --- 4: a rule deleted upstream must not linger -----------------------------
fs.unlinkSync(path.join(srcDir, 'rules', 'b.scm'));
fs.writeFileSync(srcExe, 'BUILD-3');
T.mirrorEngine(false);
check('a rule deleted upstream disappears from the copy',
      !fs.existsSync(path.join(dstDir, 'rules', 'b.scm')),
      'a copy that only ever adds would lint by rules the engine no longer ships');
check('and the surviving rule is still there', fs.existsSync(path.join(dstDir, 'rules', 'a.scm')));

// --- 5: force ---------------------------------------------------------------
r = T.mirrorEngine(true);
check('force re-copies even when current', r.refreshed === true, r.reason);

// --- 6: a half-finished copy REPAIRS itself ---------------------------------
// The stamp is written last and cleared first precisely so this cannot wedge.
// Simulate the interrupted state: stamp says current, exe is gone.
fs.unlinkSync(dstExe);
r = T.mirrorEngine(false);
check('a missing exe under a current stamp is repaired, not skipped',
      r.refreshed === true && fs.existsSync(dstExe), r.reason);

// --- 7: a missing source is reported, not silently tolerated ----------------
settings = { engineSource: path.join(srcDir, 'no-such.exe'), engineUpdate: 'onActivate', serverPath: '' };
r = T.mirrorEngine(false);
check('a missing engine source yields no exe and says why',
      r.exe === '' && /not found/.test(r.reason || ''), r.reason);

// --- 8: resolveExe routing --------------------------------------------------
settings = { engineSource: srcExe, engineUpdate: 'onActivate', serverPath: '' };
check('resolveExe returns the COPY by default -- this is the whole point',
      T.resolveExe() === dstExe, T.resolveExe());

settings = { engineSource: srcExe, engineUpdate: 'off', serverPath: '' };
check('engineUpdate=off runs the deployed engine directly', T.resolveExe() === srcExe, T.resolveExe());

const override = path.join(srcDir, 'custom.exe');
fs.writeFileSync(override, 'custom');
settings = { engineSource: srcExe, engineUpdate: 'onActivate', serverPath: override };
check('an explicit serverPath overrides everything and makes no copy',
      T.resolveExe() === override, T.resolveExe());

try { fs.rmSync(root, { recursive: true, force: true }); } catch (e) { /* temp dir */ }

console.log(failed ? 'HARNESS: FAIL' : 'HARNESS: PASS');
process.exit(failed ? 1 : 0);
