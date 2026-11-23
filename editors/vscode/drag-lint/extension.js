'use strict';

// drag-lint VS Code client.
//
// Deliberately plain JavaScript, not TypeScript: this repo has no Node build
// step and adding one would mean the extension could go stale against a
// compiled artifact nobody rebuilds. What is on disk is what runs.
//
// The server is `drag-lint lsp` over stdio, which needed NO engine changes --
// it was already a stock stdio LSP server, verified by an initialize handshake
// advertising hover, definition, references, workspaceSymbol, completion and
// signatureHelp.

const { workspace, window, commands, languages, ConfigurationTarget, StatusBarAlignment, ThemeColor, Uri, Position, Range, Hover, MarkdownString } = require('vscode');
const { LanguageClient, TransportKind, CloseAction, ErrorAction, RevealOutputChannelOn } = require('vscode-languageclient/node');
const { execFile } = require('child_process');
const fs = require('fs');
const path = require('path');
const radcolors = require('./lib/radcolors');
const dlctx = require('./lib/context');
const plannedstop = require('./lib/plannedstop');
const restartguard = require('./lib/restartguard');
const serverargs = require('./lib/serverargs');
const delphilsp = require('./lib/delphilsp');
const enginestale = require('./lib/enginestale');
const exceptionfacts = require('./lib/exceptionfacts');
const deferredhover = require('./lib/deferredhover');
const disablerule = require('./lib/disablerule');
const projectsettings = require('./lib/projectsettings');

// Set once in activate(). restartServer() and updateEngineNow() both need the
// extension context to locate the private engine copy, and neither is called
// with one.
let extContext;
let engineLog;

let client;
// 1.52 VSRESTART: open while WE stop the client on purpose (restart / engine-copy update), so the
// old connection's teardown errors are not logged as faults. See lib/plannedstop.js.
const stopGate = plannedstop.createGate();
let clientChannel;
const STOP_TIMEOUT_MS = 2000;
const PLANNED_STOP_GRACE_MS = restartguard.graceMs(STOP_TIMEOUT_MS);
const restartState = restartguard.createRestartState(stopGate);
const graceGate = restartguard.createGraceGate(stopGate, setTimeout, clearTimeout);
// Held so a restart can dispose the previous one. The LanguageClient does NOT
// take ownership of a watcher handed to it via synchronize.fileEvents, so
// building a fresh client per restart -- which is what the restart command does
// -- would otherwise leak one file-system watcher per invocation.
let manifestWatcher;
// Source-file watcher: sends workspace/didChangeWatchedFiles (OS change notifications) so the server
// re-lints files edited on disk by another tool and
// clears Problems entries of files removed without ever being closed (e.g. a removed worktree).
let sourceWatcher;

// Redeploying the engine REPLACES THE FILE A RUNNING SERVER IS EXECUTING FROM.
// Since v1.4 the server runs a PRIVATE COPY (see mirrorEngine below), so the
// ordinary case -- restaging the deployed engine while VS Code is open -- no
// longer touches this process at all. The budget below still matters for
// engineUpdate=off, for an explicit dragLint.serverPath aimed at the deployed
// binary, and for "Update Engine Copy Now", which replaces the copy on purpose.
// vscode-languageclient's stock policy is 5 crashes in 3 minutes
// -> stop for good, and five restage cycles in three minutes is an ordinary
// engine-development afternoon. The result was a language server that stayed
// dead with no recovery short of reloading the window.
//
// So: a larger budget over a longer window, and when the budget IS exhausted,
// say what to do about it instead of the stock "See the output for more
// information."
const RESTART_BUDGET = 10;
const RESTART_WINDOW_MS = 3 * 60 * 1000;
let restartTimes = [];

function makeErrorHandler() {
  return plannedstop.wrapErrorHandler(makeBudgetErrorHandler(), stopGate, { Continue: ErrorAction.Continue, DoNotRestart: CloseAction.DoNotRestart });
}

// Stops the running client on purpose. The gate stays open for a short grace period after stop()
// resolves because the child's exit and the last write errors can still arrive just after it.
async function stopClientPlanned() {
  if (!client) return;
  const old = client;
  client = undefined;
  graceGate.open();
  try { await old.stop(STOP_TIMEOUT_MS); } catch (e) { /* already gone, or the stop timed out: the client ends the old server itself */ }
  // Dispose so the old client's server-registered commands (draglint.showCallers ...) are gone
  // before the new client registers them again.
  try { old.dispose(); } catch (e) { /* already disposed */ }
  graceGate.closeLater(PLANNED_STOP_GRACE_MS);
}

function makeBudgetErrorHandler() {
  return {
    error(error, message, count) {
      // A write error is what a replaced-binary EPIPE looks like. Keep going;
      // closed() below is what actually decides whether to give up.
      if (count && count > 5) return { action: ErrorAction.Shutdown };
      return { action: ErrorAction.Continue };
    },
    closed() {
      const now = Date.now();
      restartTimes = restartTimes.filter((t) => now - t < RESTART_WINDOW_MS);
      restartTimes.push(now);
      if (restartTimes.length <= RESTART_BUDGET) {
        return { action: CloseAction.Restart };
      }
      window.showWarningMessage(
        'drag-lint: the language server stopped repeatedly and will not be restarted automatically. ' +
          'If you just redeployed the engine, run "drag-lint: Restart Language Server".',
        'Restart now'
      ).then((pick) => {
        if (pick === 'Restart now') commands.executeCommand('dragLint.restartServer');
      });
      return { action: CloseAction.DoNotRestart };
    }
  };
}

// ---------------------------------------------------------------------------
// THE PRIVATE ENGINE COPY
//
// WHY IT EXISTS
//   A running process holds an execute lock on its own image. This extension's
//   language server IS drag-lint.exe, so while VS Code is open it locks that
//   binary -- and until v1.4 the binary it locked was the DEPLOYED one, shared
//   with the Delphi IDE. The consequence was not subtle: build_draglint_win64
//   compiled fine and then died with "ERROR: failed to stage ... drag-lint.exe",
//   so a VS Code window nobody was even using blocked engine development. VS
//   Code respawns the server within a second of it being killed, so killing it
//   was not a workaround either -- that just loses the race again.
//
// WHY A COPY RATHER THAN A LOCK-FREE LAUNCH
//   Windows has no "run this exe without locking it". Copy-then-run is the
//   mechanism, and it buys the property actually wanted here: the two editors
//   are DECOUPLED. The Delphi IDE keeps running the freshly deployed engine --
//   it is the one that must stay current -- while VS Code runs a snapshot
//   refreshed only at activation.
//
// STALE ON PURPOSE
//   Refreshing only at activation means a long-lived VS Code window can sit
//   several builds behind. That is the DESIGN, not a shortcoming: an engine
//   under active development should not be swapped underneath a live session,
//   and the owner explicitly does not need VS Code current. The command
//   "drag-lint: Update Engine Copy Now" is the escape hatch for the rare
//   occasion it matters.
//
// IT FAILS SOFT, DELIBERATELY
//   A second VS Code window running its own server holds the COPY, so a refresh
//   can fail in exactly the way the original problem did. When it does, the
//   existing copy keeps working and the reason is logged. The alternative --
//   refusing to start because the engine could not be updated -- would trade a
//   slightly stale hover for no hovers at all.
// ---------------------------------------------------------------------------

// What the language server actually needs beside it. NOT the whole deployed
// folder: the BPL, ConvRulesEditor, drag_lint_graph and the .exp/.lib link
// leftovers are ~60 MB the server never touches. drag-lint.json IS needed -- it
// is the database manifest, read from beside the exe, and every path in it is
// absolute, so a relocated copy resolves to exactly the same databases.
const ENGINE_FILES = [
  'drag-lint.json',
  'tree-sitter.dll',
  'tree-sitter-delphi13.dll',
  'tree-sitter-dfm.dll'
];
const ENGINE_DIRS = ['rules'];

function cfg() {
  return workspace.getConfiguration('dragLint');
}

function log(msg) {
  if (engineLog) engineLog.appendLine('[' + new Date().toISOString() + '] ' + msg);
}

function engineRootDir() {
  return path.join(extContext.globalStorageUri.fsPath, 'engine');
}

// ONE DIRECTORY PER BUILD, and that is the whole fix for the multi-window
// collision.
//
// The old layout put the copy at engine\drag-lint.exe -- one path, rewritten in
// place on every new build. With two or more windows open that rewrite is an
// EBUSY against a sibling window's running language server, the copy is
// abandoned, and (because the stamp file was cleared first) the copy is left
// looking permanently stale without ever being able to catch up. Measured on
// this machine 2026-09-07: the copy was 1.9.0-alpha from five days and two
// releases earlier, its .engine-stamp was gone, and the three lsp --stdio
// children had all started in the same second -- the signature of exactly that
// race, with nothing on screen saying so. `Update Engine Copy Now` could not
// fix it either: it stops only THIS window's client.
//
// A new build now lands in a directory NOTHING holds, so the copy cannot
// collide. Each window keeps running the directory it started from until it
// exits, and old directories are pruned by whichever window activates next.
// The cost is transient, not per-window: two builds' worth of disk until the
// old servers exit, rather than a copy per window.
function dirNameForStamp(stamp) {
  // stampOf yields 'mtimeMs:size'; ':' is illegal in a Windows path component.
  return 'b' + String(stamp).replace(/[^0-9A-Za-z]+/g, '-');
}

function privateEngineDir(stamp) {
  if (!stamp) return engineRootDir();
  return path.join(engineRootDir(), dirNameForStamp(stamp));
}

// Best effort by design. A directory a SIBLING WINDOW is still running from
// cannot be removed, and that EBUSY is the expected case, not an error -- the
// window that activates after that server exits will get it. Also clears the
// LEGACY flat layout (files sitting directly in engine\), which is why this
// does not filter to directories.
function pruneOldEngineDirs(keepDir) {
  const root = engineRootDir();
  let entries = [];
  try { entries = fs.readdirSync(root, { withFileTypes: true }); } catch (e) { return; }
  for (const entry of entries) {
    const p = path.join(root, entry.name);
    if (keepDir && path.resolve(p) === path.resolve(keepDir)) continue;
    try { fs.rmSync(p, { recursive: true, force: true }); } catch (e) { /* still held */ }
  }
}

// The most recently written copy of `exeName` under any build directory, or ''.
// Used only as a fallback when a fresh copy fails outright: running a slightly
// old copy beats refusing to start.
function newestEngineExe(exeName) {
  const root = engineRootDir();
  let best = '';
  let bestT = -1;
  let entries = [];
  try { entries = fs.readdirSync(root, { withFileTypes: true }); } catch (e) { return ''; }
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const p = path.join(root, entry.name, exeName);
    try {
      const st = fs.statSync(p);
      if (st.mtimeMs > bestT) { bestT = st.mtimeMs; best = p; }
    } catch (e) { /* not a build dir */ }
  }
  return best;
}

// mtime+size, not a content hash: this runs on every activation, and hashing
// 33 MB to answer "is this the same build" would be paid every time to learn
// what two cheap stat fields already say.
function stampOf(file) {
  const st = fs.statSync(file);
  return String(Math.floor(st.mtimeMs)) + ':' + String(st.size);
}

function copyTree(src, dst) {
  fs.mkdirSync(dst, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, entry.name);
    const d = path.join(dst, entry.name);
    if (entry.isDirectory()) copyTree(s, d);
    else fs.copyFileSync(s, d);
  }
}

// Returns { exe, refreshed, reason }. `exe` is '' only when there is nothing
// runnable at all.
function mirrorEngine(force) {
  const source = (cfg().get('engineSource') || '').trim();
  if (!source || !fs.existsSync(source)) {
    return { exe: '', refreshed: false, reason: 'engine source not found at "' + source + '"' };
  }
  const srcDir = path.dirname(source);
  const exeName = path.basename(source);

  let want = '';
  try { want = stampOf(source); } catch (e) { want = ''; }
  if (!want) return { exe: '', refreshed: false, reason: 'could not stat the engine source' };

  const dstDir = privateEngineDir(want);
  const dstExe = path.join(dstDir, exeName);

  // The DIRECTORY NAME IS THE STAMP, so "have we already copied this build" is
  // a path test and no stamp file is needed.
  //
  // But EXISTENCE IS NOT SUFFICIENCY, and this repo has been bitten by exactly
  // that: a rules\ directory that existed and was EMPTY answered every question
  // wrongly and silently. A half-written directory under a build's own name
  // would be permanently believed. So the copy is assembled in a TEMP directory
  // and renamed into place -- a directory under the real name is complete by
  // construction, and an interrupted copy leaves only a .tmp- sibling that the
  // next prune removes.
  if (!force && fs.existsSync(dstExe)) {
    pruneOldEngineDirs(dstDir);
    return { exe: dstExe, refreshed: false, reason: 'already current' };
  }

  const tmpDir = dstDir + '.tmp-' + process.pid + '-' + Date.now();
  try {
    // Reaching here with the directory already present means either force, or a
    // directory that exists WITHOUT the exe -- which a published directory
    // never is, so it was damaged from outside. Both cases want it gone before
    // the rename, and if a live server holds it the rename below fails and the
    // existing copy is adopted, which is this same build anyway.
    try { fs.rmSync(dstDir, { recursive: true, force: true }); } catch (e) { /* held */ }

    fs.mkdirSync(tmpDir, { recursive: true });
    fs.copyFileSync(source, path.join(tmpDir, exeName));
    for (const f of ENGINE_FILES) {
      const s = path.join(srcDir, f);
      if (fs.existsSync(s)) fs.copyFileSync(s, path.join(tmpDir, f));
    }
    for (const d of ENGINE_DIRS) {
      const s = path.join(srcDir, d);
      if (!fs.existsSync(s)) continue;
      // No remove-first dance any more: the temp directory starts empty, so a
      // rule deleted upstream cannot linger by construction rather than by a
      // step somebody has to remember.
      copyTree(s, path.join(tmpDir, d));
    }

    try {
      fs.renameSync(tmpDir, dstDir);
    } catch (e) {
      // Another window published this same build first (or still holds the
      // directory from a force). Its content is this build by construction, so
      // adopt it rather than fight for the name.
      try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch (e2) { /* best effort */ }
      if (fs.existsSync(dstExe)) {
        pruneOldEngineDirs(dstDir);
        return { exe: dstExe, refreshed: false, reason: 'another window published this build first' };
      }
      throw e;
    }

    pruneOldEngineDirs(dstDir);
    return { exe: dstExe, refreshed: true, reason: '' };
  } catch (e) {
    const why = (e && e.message) || String(e);
    try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch (e2) { /* best effort */ }
    // Running a slightly older copy beats refusing to start -- and unlike the
    // old layout, an older copy is still on disk under its own name instead of
    // having been overwritten halfway.
    const fallback = newestEngineExe(exeName);
    if (fallback) {
      return { exe: fallback, refreshed: false, reason: 'keeping an existing copy: ' + why };
    }
    return { exe: '', refreshed: false, reason: why };
  }
}

function resolveExe() {
  const override = (cfg().get('serverPath') || '').trim();
  if (override) {
    log('dragLint.serverPath is set, running it as-is with no private copy: ' + override);
    return override;
  }
  const source = (cfg().get('engineSource') || '').trim();
  const mode = cfg().get('engineUpdate') || 'onActivate';
  if (mode === 'off') {
    log('engineUpdate=off -- running the deployed engine directly. This session WILL lock ' + source);
    return source;
  }
  // 'manual' and 'onActivate' differ only in whether a STALE copy is refreshed
  // now; both still create the copy the first time, because there is nothing to
  // run otherwise.
  const res = mirrorEngine(false);
  if (res.reason) log('engine copy: ' + res.reason);
  if (res.refreshed) log('engine copy refreshed from ' + source);
  if (!res.exe) {
    // Nothing was ever copied AND the copy failed. Running the source directly
    // re-introduces the lock, but a blocked build is a better failure than a
    // language server that will not start -- and it is logged, not silent.
    log('engine copy unavailable; falling back to the deployed engine (this session WILL lock it)');
    return source;
  }
  return res.exe;
}

const updateEngineNow = restartguard.coalesce(updateEngineNowImpl, 10000);
async function updateEngineNowImpl() {
  if (!extContext) return;
  // The running server holds the copy, so it has to stop before the file can be
  // replaced. Same lock this whole mechanism is about, one level in.
  await stopClientPlanned();
  const res = mirrorEngine(true);
  if (!res.exe) {
    window.showErrorMessage('drag-lint: could not update the engine copy -- ' + res.reason);
  } else if (res.refreshed) {
    window.showInformationMessage('drag-lint: engine copy updated.');
  } else {
    window.showInformationMessage('drag-lint: engine copy left unchanged (' + res.reason + ').');
  }
  log('manual update: exe=' + res.exe + ' refreshed=' + res.refreshed + ' ' + res.reason);
  await restartServer();
}

// One Output channel for every client this window ever builds (the wrapper's dispose is a no-op).
function sharedClientChannel() {
  if (!clientChannel) {
    clientChannel = plannedstop.wrapChannel(window.createOutputChannel('drag-lint'), stopGate);
  }
  return clientChannel;
}

// v152 BK-VSHOVER (B32): the deferred hover's one slot (see lib/deferredhover.js),
// shared by the LSP hover middleware (first step) and the companion provider
// (second step). serverExe = the engine the client runs, for `rules disable`.
const hoverSlot = deferredhover.createSlot();
let serverExe = '';
let lastCtx;

function makeClient(exe) {
  serverExe = exe;
  // No --db by default. drag-lint resolves databases from the drag-lint.json
  // sitting beside the exe, which is the same manifest the Delphi IDE reads --
  // so VS Code follows the project layout automatically instead of pinning a
  // list here that would rot the next time a project DB is added or renamed.
  //
  // The filter is load-bearing, not defensive tidying: an EMPTY STRING in
  // dragLint.databases used to push '--db' followed by an argument Windows
  // quoting drops, producing a trailing bare `--db`. That fatals in argument
  // parsing before the first store opens -- exit 3, and (until the engine fix
  // of 2026-08-14) with the explanation written to stdout, i.e. straight into
  // the JSON-RPC stream, so the client saw only `write EPIPE`. One stray blank
  // row in a settings array was enough to make the server look broken.
  const dbs = (workspace.getConfiguration('dragLint').get('databases') || [])
    .filter((db) => typeof db === 'string' && db.trim() !== '');
  // dragLint.fullRules is ON unless the user saved false (see lib/serverargs.js):
  // the server then publishes the same rule set as the Delphi IDE panel, at the
  // cost of one out-of-process lint per save (budget 8 s, measured 2.2-3.0 s on a large unit).
  const fullRules = workspace.getConfiguration('dragLint').get('fullRules');
  // dragLint.delphiLsp (1.6.8): ON runs `lsp --proxy` + the dragLint.delphiLspMerge flags in front of DelphiLSP.
  const delphiLsp = workspace.getConfiguration('dragLint').get('delphiLsp');
  const merge = workspace.getConfiguration('dragLint').get('delphiLspMerge');
  const args = serverargs.buildArgs(dbs, fullRules, delphiLsp, merge);
  log('server args: ' + args.join(' ') + (fullRules === false ? ' (full rules switched OFF by dragLint.fullRules)' : '') + (delphiLsp === true ? ' (DelphiLSP proxy ON by dragLint.delphiLsp)' : ''));

  const serverOptions = {
    run: { command: exe, args, transport: TransportKind.stdio },
    debug: { command: exe, args, transport: TransportKind.stdio }
  };

  if (manifestWatcher) {
    manifestWatcher.dispose();
    manifestWatcher = undefined;
  }
  // The index is rebuilt out-of-band; watching the manifest means a reindex that
  // adds a section does not require reloading the window.
  manifestWatcher = workspace.createFileSystemWatcher('**/drag-lint.json');
  if (sourceWatcher) sourceWatcher.dispose();
  sourceWatcher = workspace.createFileSystemWatcher('**/*.{pas,dpr,dpk,inc,dfm}');

  const clientOptions = {
    documentSelector: [{ scheme: 'file', language: 'pascal' }],
    outputChannel: sharedClientChannel(),
    revealOutputChannelOn: RevealOutputChannelOn.Never,
    errorHandler: makeErrorHandler(),
    initializationOptions: dlctx.initOptions((k) => workspace.getConfiguration('dragLint').get(k)),
    synchronize: { configurationSection: 'dragLint', fileEvents: [manifestWatcher, sourceWatcher] },
    middleware: {
      // Only a stopped client's traffic is dropped; this client's own start replays the open
      // documents through here and must reach the new server (`c` is assigned below).
      didOpen: restartState.wrap((document, next) => next(document), () => client === c),
      didClose: restartState.wrap((document, next) => next(document), () => client === c),
      // Wave 149 LX (spec P1): the exception lens runs draglint.exceptionFacts; the server
      // answers the routine's raise / handler sites and this shows them in a quick pick.
      executeCommand: async (command, args, next) => {
        const result = await next(command, args);
        if (exceptionfacts.isExceptionFactsCommand(command)) await showExceptionFacts(result);
        return result;
      },
      // v152 BK-VSHOVER (B32): announce the position, then ask. A 1.52 engine answers
      // the FAST markdown (placeholder where the slow facts go), shown at once; the
      // companion provider (registerDeferredHoverCompanion) asks again for the rest.
      // An older engine answers whole and the companion adds nothing.
      provideHover: async (document, position, token, next) => {
        const uri = document.uri.toString();
        const k = deferredhover.key(uri, position.line, position.character);
        hoverSlot.reset(k);
        if (client) client.sendNotification(deferredhover.DEFER_METHOD, { textDocument: { uri }, position: { line: position.line, character: position.character } });
        let hover;
        try {
          hover = await next(document, position, token);
        } catch (e) {
          hoverSlot.settle(k, null);
          throw e;
        }
        const text = deferredhover.hoverText(hover);
        if (!hover || !deferredhover.isPartial(text)) {
          hoverSlot.settle(k, null);
          return hover;
        }
        const shown = deferredhover.fastPart(text);
        hoverSlot.settle(k, { shown });
        return new Hover(new MarkdownString(shown), hover.range);
      }
    }
  };

  const c = new LanguageClient('dragLint', 'drag-lint', serverOptions, clientOptions);
  // Tolerant: a server without this notification just leaves the status bar at
  // "context unknown".
  c.onNotification('draglint/context', (ctx) => showContext(ctx));
  return c;
}

// The exception lens click (wave 149 LX): a quick pick of the sites, then a jump to the
// one picked. An empty answer (no sites, or lsp --no-exception-facts) says so.
async function showExceptionFacts(rows) {
  const items = exceptionfacts.toPickItems(rows);
  if (items.length === 0) {
    window.showInformationMessage(exceptionfacts.emptyMessage());
    return;
  }
  const pick = await window.showQuickPick(items, { placeHolder: 'drag-lint: raise and handler sites', matchOnDescription: true, matchOnDetail: true });
  if (!pick) return;
  const t = exceptionfacts.targetOf(pick);
  const pos = new Position(t.line, t.character);
  await window.showTextDocument(Uri.parse(t.uri), { selection: new Range(pos, pos) });
}
// "Refresh Problems": re-lints, from disk, every file that currently carries a drag-lint
// diagnostic. The cheap way back from stale Problems entries (no server restart, no window
// reload). Sends the custom notification draglint/refreshDiagnostics; the server bounds it.
async function refreshProblems() {
  if (!client) {
    window.showWarningMessage('drag-lint: the language server is not running. Use "Restart Language Server".');
    return;
  }
  const uris = [];
  for (const [uri, diags] of languages.getDiagnostics()) {
    if (uri.scheme === 'file' && diags.some((d) => /^(drag-lint|dcc)/.test(String(d.source || '')))) {
      uris.push(uri.toString());
    }
  }
  if (uris.length === 0) {
    window.setStatusBarMessage('drag-lint: no drag-lint problems to refresh', 3000);
    return;
  }
  await client.sendNotification('draglint/refreshDiagnostics', { uris });
  window.setStatusBarMessage(`drag-lint: refreshing ${uris.length} file(s)`, 3000);
}

// dragLint.delphiLsp: DelphiLSP learns its project only from a workspace/didChangeConfiguration
// carrying the settings of the IDE's <Project>.delphilsp.json (measured headless 2026-11-20: without
// it DelphiLSP publishes nothing and hover is null). Pushed once after every (re)start.
let lastDelphiLspFile = '';
async function pushDelphiLspConfig(c, onlyIfChanged) {
  const cfg = workspace.getConfiguration('dragLint');
  if (cfg.get('delphiLsp') !== true || !c) return;
  let file = '';
  try {
    const found = (await workspace.findFiles('**/*.delphilsp.json', '**/{node_modules,.git,.claude,worktrees}/**', 50)).map((u) => u.fsPath);
    const ed = window.activeTextEditor;
    const active = ed && ed.document && ed.document.uri.scheme === 'file' ? ed.document.uri.fsPath : '';
    const folder = active ? workspace.getWorkspaceFolder(ed.document.uri) : (workspace.workspaceFolders || [])[0];
    file = delphilsp.pick(cfg.get('delphiLspConfig') || '', found, active, folder ? folder.uri.fsPath : '', undefined, lastDelphiLspFile);
  } catch (e) { log('delphilsp.json search failed: ' + e); }
  if (onlyIfChanged && (!file || file === lastDelphiLspFile)) return;
  const params = file ? delphilsp.loadParams(file) : null;
  if (!params) {
    log('DelphiLSP config missing or unreadable: ' + (file || '(none found)'));
    window.showWarningMessage(delphilsp.MISSING_WARNING);
    return;
  }
  log('DelphiLSP config: ' + file);
  lastDelphiLspFile = file;
  c.sendNotification('workspace/didChangeConfiguration', params);
}

async function restartServer() {
  const exe = resolveExe();
  if (!exe || !fs.existsSync(exe)) {
    window.showErrorMessage(
      `drag-lint: server not found at "${exe}". Set "dragLint.serverPath" to your drag-lint.exe.`
    );
    return;
  }
  // Build a FRESH client rather than calling client.restart(). Once the stock
  // policy has latched, the failure state lives in the client object, and the
  // whole point of this command is to be the way back from that.
  // A server that is already gone cannot be stopped cleanly, which is precisely the case this
  // command exists for; stopClientPlanned swallows that.
  await stopClientPlanned();
  restartTimes = [];
  restartState.starting = true;
  try {
    client = makeClient(exe);
    await client.start();
    await pushDelphiLspConfig(client);
  } finally {
    restartState.starting = false;
  }
  window.setStatusBarMessage('drag-lint: language server restarted', 3000);
}

/*
  --- IDE colour matching -------------------------------------------------

  Two ways to get the RAD Studio scheme, because they answer different wants
  and neither subsumes the other:

    applyRadStudioColours()  writes editor.tokenColorCustomizations into the
                             user's settings. Applies INSTANTLY with no reload,
                             and because every scope our grammar emits ends in
                             '.pascal' it recolours Pascal files ONLY -- the
                             user keeps their own VS Code theme everywhere else.
                             It cannot set the editor background, which is
                             global in VS Code and has no per-language form.

    generateThemeFile()      rewrites the contributed colour theme, which DOES
                             carry the background and is the full IDE look. It
                             recolours every language and needs a window reload,
                             since VS Code reads a theme file once.

  Both call the same buildTheme()/buildTokenRules() in lib/radcolors.js, so the
  two paths cannot disagree about a colour.
*/

// Ours are exactly the rules whose every scope ends in '.pascal'. Identifying
// them by shape rather than by a marker means a user who hand-edits the list
// keeps their own rules through a re-apply, and we never accumulate duplicates.
function isOurRule(rule) {
  const scopes = Array.isArray(rule && rule.scope) ? rule.scope
    : (typeof (rule && rule.scope) === 'string' ? [rule.scope] : []);
  return scopes.length > 0 && scopes.every((s) => String(s).endsWith('.pascal'));
}

async function applyRadStudioColours() {
  let scheme;
  try {
    scheme = radcolors.readScheme(cfg().get('colors.bdsVersion') || 'auto');
  } catch (e) {
    window.showErrorMessage('drag-lint: ' + e.message);
    return;
  }

  const rules = radcolors.buildTokenRules(scheme);
  const conf = workspace.getConfiguration();
  const current = conf.get('editor.tokenColorCustomizations') || {};
  const kept = (current.textMateRules || []).filter((r) => !isOurRule(r));

  await conf.update(
    'editor.tokenColorCustomizations',
    Object.assign({}, current, { textMateRules: kept.concat(rules) }),
    ConfigurationTarget.Global
  );

  log(`applied ${rules.length} token rule(s) from ${scheme.key}`);
  window.showInformationMessage(
    `drag-lint: applied ${rules.length} colour rule(s) from RAD Studio ${scheme.version} to Pascal files.`
  );
}

async function generateThemeFile() {
  let scheme;
  try {
    scheme = radcolors.readScheme(cfg().get('colors.bdsVersion') || 'auto');
  } catch (e) {
    window.showErrorMessage('drag-lint: ' + e.message);
    return;
  }

  const out = path.join(extContext.extensionPath, 'themes', 'delphi-ide.color-theme.json');
  try {
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.writeFileSync(out, radcolors.serializeJson(radcolors.buildTheme(scheme)), 'utf8');
  } catch (e) {
    // The extension directory is read-only under some managed installs. Say so
    // instead of leaving the user to wonder why the colours did not change.
    window.showErrorMessage(
      `drag-lint: could not write ${out} (${e.message}). Use "Apply RAD Studio Colours" instead -- it writes to your settings, not the extension.`
    );
    return;
  }

  log('regenerated theme from ' + scheme.key);
  const pick = await window.showInformationMessage(
    `drag-lint: regenerated the "Delphi IDE" theme from RAD Studio ${scheme.version}. VS Code reads a theme file once, so this needs a reload.`,
    'Reload Window'
  );
  if (pick === 'Reload Window') commands.executeCommand('workbench.action.reloadWindow');
}

/*
  --- project / platform context -------------------------------------------
  Settings draglint.project / platform / config are sent as initializationOptions
  and via workspace/didChangeConfiguration. The commands also push the choice
  immediately with workspace/executeCommand 'draglint.setContext'. The server
  answers with a 'draglint/context' notification, shown in the status bar.
*/
let ctxStatus;
let ctxWarned = false;

// Show the item only while a Delphi file is active (dlctx.isDelphiLanguage).
function updateContextVisibility() {
  if (!ctxStatus) return;
  const ed = window.activeTextEditor;
  if (ed && !dlctx.isDelphiLanguage(ed.document.languageId)) ctxStatus.hide();
  else ctxStatus.show();
}

function showContext(ctx) {
  lastCtx = ctx;
  if (!ctxStatus) return;
  const f = dlctx.formatStatus(ctx);
  ctxStatus.text = f.text;
  ctxStatus.tooltip = f.tooltip;
  ctxStatus.backgroundColor = f.warning ? new ThemeColor('statusBarItem.warningBackground') : undefined;
  updateContextVisibility();
}

async function applyContext(patch) {
  const conf = workspace.getConfiguration('dragLint');
  for (const k of Object.keys(patch)) {
    await conf.update(k, patch[k], workspace.workspaceFolders ? ConfigurationTarget.Workspace : ConfigurationTarget.Global);
  }
  const now = dlctx.initOptions((k) => (k in patch ? patch[k] : conf.get(k)));
  try {
    if (!client) throw new Error('language server not running');
    await client.sendRequest('workspace/executeCommand', { command: 'draglint.setContext', arguments: [now] });
  } catch (e) {
    if (!ctxWarned) {
      ctxWarned = true;
      window.showWarningMessage('drag-lint: server did not accept draglint.setContext (' + e.message + '). The setting is saved; it applies on the next server restart.');
    }
  }
}

async function selectPlatform() {
  const cur = workspace.getConfiguration('dragLint').get('platform') || '';
  const items = dlctx.PLATFORMS.map((p) => ({ label: p === '' ? '(project default)' : p, value: p, description: p === cur ? 'current' : '' }));
  const pick = await window.showQuickPick(items, { placeHolder: 'drag-lint: select target platform' });
  if (pick) await applyContext({ platform: pick.value });
}

// "Project Settings...": a QuickPick UI over the engine's `settings list|set|unset --json` verb
// (v153 SETTINGS-VSCODE). The extension never touches the settings files; secrets show masked.
async function projectSettings() {
  const project = projectsettings.projectFrom(lastCtx && lastCtx.project, workspace.getConfiguration('dragLint').get('project'));
  if (!project) { window.showWarningMessage('drag-lint: no project -- run "drag-lint: Select Project" first.'); return; }
  if (!serverExe || !fs.existsSync(serverExe)) { window.showErrorMessage('drag-lint: engine not found; set "dragLint.serverPath".'); return; }
  const run = (argv) => new Promise((resolve) => execFile(serverExe, argv, { cwd: path.dirname(project), windowsHide: true, timeout: 60000 },
    (err, so, se) => resolve({ out: String(so || '') + (so ? '' : String(se || '')), code: err ? (typeof err.code === 'number' ? err.code : 2) : 0 })));
  const listed = projectsettings.parseList((await run(['settings', 'list', '--project', project, '--json'])).out);
  if (listed.error) { window.showErrorMessage('drag-lint: ' + listed.error); return; }
  const pick = await window.showQuickPick(listed.rows.map((r) => ({ label: projectsettings.rowLabel(r), description: projectsettings.sourceText(r), detail: r.description, row: r })),
    { placeHolder: 'drag-lint project settings for ' + path.basename(project) });
  if (!pick || !pick.row.settable) return;
  const row = pick.row;
  let value;
  const choices = projectsettings.choicesFor(row);
  if (choices) { value = await window.showQuickPick(choices); } else { value = await window.showInputBox({ value: projectsettings.currentText(row), prompt: row.description, ignoreFocusOut: true, password: /secret|token|password/i.test(row.key) }); }
  if (value === undefined) return;
  let local = false;
  if (projectsettings.needsScopeQuestion(row)) {
    const s = await window.showQuickPick(['This project (shared, committed)', 'This machine only (local file)']);
    if (s === undefined) return;
    local = s.startsWith('This machine');
  }
  const argv = value === projectsettings.RESET ? projectsettings.buildUnsetArgs({ key: row.key, local, project })
    : projectsettings.buildSetArgs({ key: row.key, value, local, project });
  // key + scope only: a value may be a secret and the log is a plain-text output channel
  log('project settings: ' + argv[1] + ' ' + row.key + (local ? ' (local)' : ''));
  const { out, code } = await run(argv);
  const r = projectsettings.describeResult(out, code);
  if (!r.ok) { window.showErrorMessage('drag-lint: ' + r.message); return; }
  window.showInformationMessage('drag-lint: ' + r.message);
  if (projectsettings.affectsLint(row.key)) await refreshProblems();
}

async function selectProject() {
  const items = [{ label: '$(file) Browse for .dproj / .dpr...', browse: true }, { label: '(auto-detect)', value: '' }];
  try {
    const found = await workspace.findFiles('**/*.dlcontext.json', '**/node_modules/**', 50);
    for (const u of found) items.push({ label: path.basename(u.fsPath), description: u.fsPath, value: u.fsPath });
  } catch (e) { /* no workspace: browse only */ }
  const pick = await window.showQuickPick(items, { placeHolder: 'drag-lint: select project' });
  if (!pick) return;
  let value = pick.value;
  if (pick.browse) {
    const sel = await window.showOpenDialog({ canSelectMany: false, filters: { 'Delphi project': ['dproj', 'dpr'] } });
    if (!sel || !sel.length) return;
    value = sel[0].fsPath;
  }
  await applyContext({ project: value });
}

// v152 BK-VSHOVER (B32): the second half of the deferred hover. VS Code renders each
// provider's part as it resolves, so this provider waits for the LSP middleware's
// first step at the same position and, when that was partial, asks the same
// position again (the engine's cancellable WHOLE answer) and shows only what the
// fast part did not. Moving away cancels the token -> $/cancelRequest -> the engine
// abandons the work. Registered before the client starts.
function registerDeferredHoverCompanion(context) {
  context.subscriptions.push(languages.registerHoverProvider({ scheme: 'file', language: 'pascal' }, {
    async provideHover(document, position, token) {
      // VS Code calls both providers in one synchronous pass; yield once so the
      // middleware has opened this position's slot before we wait on it.
      await new Promise((r) => setTimeout(r, 0));
      const k = deferredhover.key(document.uri.toString(), position.line, position.character);
      const first = await hoverSlot.wait(k, deferredhover.FIRST_STEP_WAIT_MS, () => token.isCancellationRequested);
      if (!first || !client || token.isCancellationRequested) return null;
      let res;
      try {
        res = await client.sendRequest('textDocument/hover', client.code2ProtocolConverter.asTextDocumentPositionParams(document, position), token);
      } catch (e) {
        return null; // RequestCancelled: the user moved on
      }
      const rest = deferredhover.remainder(first.shown, deferredhover.hoverText(res));
      return rest ? new Hover(new MarkdownString(rest)) : null;
    }
  }));
}

// v152 BK-VSHOVER (B43, DISRULE H1): the engine's "drag-lint: disable <rule> in this
// unit / project..." code action carries this command. Ask the reason, run
// `drag-lint rules disable`, show the answer, re-lint the files with findings.
async function disableRule(...args) {
  const req = disablerule.fromCommandArgs(args);
  if (!req) {
    window.showWarningMessage('drag-lint: "Disable rule" is run from a drag-lint finding\'s quick fix (light bulb).');
    return;
  }
  const where = req.scope === 'line' ? 'on this line' : 'in this ' + req.scope;
  const reason = await window.showInputBox({
    prompt: `drag-lint: why does ${req.rule} not apply ${where}? (saved with the override, with today's date)`,
    placeHolder: 'reason (required)',
    ignoreFocusOut: true,
    validateInput: (v) => disablerule.reasonProblem(v, req.scope) || null
  });
  if (reason === undefined) return;
  if (!serverExe || !fs.existsSync(serverExe)) {
    window.showErrorMessage('drag-lint: engine not found; set "dragLint.serverPath".');
    return;
  }
  const project = lastCtx && lastCtx.project ? String(lastCtx.project) : '';
  const argv = disablerule.buildArgs(Object.assign({}, req, { reason, project: /\.dproj$/i.test(project) ? project : '' }));
  log('disable rule: ' + argv.join(' '));
  const { out, code } = await new Promise((resolve) => {
    execFile(serverExe, argv, { cwd: path.dirname(req.file), windowsHide: true, timeout: 60000 }, (err, so, se) => {
      resolve({ out: String(so || '') + String(se || ''), code: err ? (typeof err.code === 'number' ? err.code : 2) : 0 });
    });
  });
  const r = disablerule.describeResult(out, code);
  if (!r.ok) {
    window.showErrorMessage('drag-lint: ' + r.message);
    return;
  }
  window.showInformationMessage('drag-lint: ' + r.message);
  await refreshProblems();
}

// DEC-14: opt-in staleness notice (dragLint.engineStaleNoticeMinutes, 0 = off).
// Says a newer deployed engine exists; the user decides. Never restarts.
let staleTimer;
let staleLastNotified = '';
function startStaleNotice(context) {
  const minutes = Number(cfg().get('engineStaleNoticeMinutes')) || 0;
  const source = (cfg().get('engineSource') || '').trim();
  if (minutes <= 0 || !source) return;
  if ((cfg().get('serverPath') || '').trim() || cfg().get('engineUpdate') === 'off') return;
  let running = '';
  try { running = stampOf(source); } catch (e) { return; }
  staleTimer = setInterval(() => {
    let now = '';
    try { now = stampOf(source); } catch (e) { return; }
    if (!enginestale.shouldNotify(running, now, staleLastNotified)) return;
    staleLastNotified = now;
    window.showInformationMessage(
      'drag-lint: a newer engine is deployed than the one this window runs.',
      'Update engine copy now'
    ).then((pick) => {
      if (pick) commands.executeCommand('dragLint.updateEngine');
    });
  }, Math.max(1, minutes) * 60 * 1000);
  context.subscriptions.push({ dispose: () => clearInterval(staleTimer) });
}
function activate(context) {
  extContext = context;
  // Its own channel, not the client's: this logs BEFORE the client exists, and
  // "which binary am I actually running" is the first question asked whenever
  // VS Code and the Delphi IDE disagree about an answer.
  engineLog = window.createOutputChannel('drag-lint (engine)');
  context.subscriptions.push(engineLog);

  ctxStatus = window.createStatusBarItem(StatusBarAlignment.Left, 50);
  ctxStatus.command = 'dragLint.selectPlatform';
  context.subscriptions.push(ctxStatus);
  showContext(undefined);
  context.subscriptions.push(window.onDidChangeActiveTextEditor(updateContextVisibility));
  // dragLint.delphiLsp: follow the active unit's project (no server restart).
  context.subscriptions.push(window.onDidChangeActiveTextEditor((ed) => {
    if (ed && ed.document && ed.document.languageId === 'pascal') pushDelphiLspConfig(client, true);
  }));
  context.subscriptions.push(commands.registerCommand('dragLint.selectPlatform', selectPlatform));
  context.subscriptions.push(commands.registerCommand('dragLint.selectProject', selectProject));
  context.subscriptions.push(commands.registerCommand('dragLint.projectSettings', projectSettings));

  const exe = resolveExe();
  log('language server exe: ' + exe);

  // Register the command FIRST and unconditionally. If the exe is missing at
  // activation, the user fixes the path and needs a way to start the server
  // without reloading the window -- registering only on the happy path would
  // mean the recovery command is absent exactly when it is needed.
  context.subscriptions.push(commands.registerCommand('dragLint.restartServer', restartServer));
  // A running server keeps the argv it was started with, so flipping the switch
  // must restart it or the setting would appear to do nothing until a reload.
  context.subscriptions.push(workspace.onDidChangeConfiguration((e) => {
    if (e.affectsConfiguration('dragLint.fullRules') || e.affectsConfiguration('dragLint.delphiLsp') ||
        e.affectsConfiguration('dragLint.delphiLspMerge') || e.affectsConfiguration('dragLint.delphiLspConfig')) restartServer();
    // synchronize.configurationSection forwards every other dragLint change as a
    // didChangeConfiguration WITHOUT the DelphiLSP settings; re-push them so the proxied
    // DelphiLSP never loses its project (no-op unless dragLint.delphiLsp is on).
    else if (e.affectsConfiguration('dragLint')) setTimeout(() => pushDelphiLspConfig(client), 500);
  }));
  context.subscriptions.push(commands.registerCommand('dragLint.updateEngine', updateEngineNow));
  context.subscriptions.push(commands.registerCommand('dragLint.refreshProblems', refreshProblems));
  // "Fix with drag-lint": both commands ask the LSP server for its own code actions (Fix: <rule>,
  // kind quickfix, and the whole-file fix, kind source.fixAll.drag-lint) and apply the first one.
  // Registered before the exe check, like the others: they are no-ops until a server answers.
  context.subscriptions.push(commands.registerCommand('dragLint.fixFinding', () =>
    commands.executeCommand('editor.action.codeAction', { kind: 'quickfix', apply: 'first' })));
  context.subscriptions.push(commands.registerCommand('dragLint.fixAllInFile', () =>
    commands.executeCommand('editor.action.codeAction', { kind: 'source.fixAll.drag-lint', apply: 'first' })));
  // Colour commands are registered before the exe check too: they read the
  // registry and touch no engine, so they must keep working on a machine where
  // the server path is wrong.
  context.subscriptions.push(commands.registerCommand('dragLint.applyRadStudioColours', applyRadStudioColours));
  context.subscriptions.push(commands.registerCommand('dragLint.generateTheme', generateThemeFile));
  // v152 BK-VSHOVER: the disable-rule code action's command (B43) and the deferred
  // hover's second step (B32). The companion is registered BEFORE the client starts:
  // VS Code orders hover parts newest provider first, so the LSP's fast part shows
  // above the companion's remainder.
  context.subscriptions.push(commands.registerCommand(disablerule.COMMAND, disableRule));
  registerDeferredHoverCompanion(context);

  // Fail LOUDLY and specifically. A language client that cannot spawn its
  // server otherwise just produces no hovers, which reads as "the index has
  // nothing" rather than "the binary is missing".
  if (!exe || !fs.existsSync(exe)) {
    window.showErrorMessage(
      `drag-lint: server not found at "${exe}". Set "dragLint.serverPath" to your drag-lint.exe.`
    );
    return;
  }

  client = makeClient(exe);
  client.start().then(() => pushDelphiLspConfig(client), () => {});
  startStaleNotice(context);
  context.subscriptions.push({
    dispose: () => {
      if (manifestWatcher) manifestWatcher.dispose();
      if (sourceWatcher) sourceWatcher.dispose();
      return client && client.stop();
    }
  });
}

function deactivate() {
  if (sourceWatcher) {
    sourceWatcher.dispose();
    sourceWatcher = undefined;
  }
  if (manifestWatcher) {
    manifestWatcher.dispose();
    manifestWatcher = undefined;
  }
  return client ? client.stop() : undefined;
}

module.exports = { activate, deactivate };

// Test hook. The engine-copy logic is the part with real failure modes -- a
// half-finished copy, a locked destination, a rule deleted upstream -- and none
// of them are reachable through activate() without a live VS Code. Exported so
// tests\vscode\ can drive it directly with a stubbed `vscode` module; nothing
// in the extension itself reads this.
module.exports.__test = {
  mirrorEngine,
  resolveExe,
  privateEngineDir,
  engineRootDir,
  pruneOldEngineDirs,
  newestEngineExe,
  setContext(ctx, channel) { extContext = ctx; engineLog = channel; }
};
