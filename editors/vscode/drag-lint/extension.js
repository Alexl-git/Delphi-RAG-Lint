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

const { workspace, window, commands } = require('vscode');
const { LanguageClient, TransportKind, CloseAction, ErrorAction } = require('vscode-languageclient/node');
const fs = require('fs');
const path = require('path');

// Set once in activate(). restartServer() and updateEngineNow() both need the
// extension context to locate the private engine copy, and neither is called
// with one.
let extContext;
let engineLog;

let client;
// Held so a restart can dispose the previous one. The LanguageClient does NOT
// take ownership of a watcher handed to it via synchronize.fileEvents, so
// building a fresh client per restart -- which is what the restart command does
// -- would otherwise leak one file-system watcher per invocation.
let manifestWatcher;

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

function privateEngineDir() {
  return path.join(extContext.globalStorageUri.fsPath, 'engine');
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
  const dstDir = privateEngineDir();
  const dstExe = path.join(dstDir, path.basename(source));
  const stampFile = path.join(dstDir, '.engine-stamp');

  let want = '';
  try { want = stampOf(source); } catch (e) { want = ''; }
  let have = '';
  try { have = fs.readFileSync(stampFile, 'utf8').trim(); } catch (e) { have = ''; }

  if (!force && want && want === have && fs.existsSync(dstExe)) {
    return { exe: dstExe, refreshed: false, reason: 'already current' };
  }

  try {
    fs.mkdirSync(dstDir, { recursive: true });
    // The stamp is cleared FIRST. If the copy dies halfway -- exe replaced,
    // rules half-written -- a stamp still claiming "current" would make every
    // later activation skip the repair and run a mismatched engine for ever.
    try { fs.unlinkSync(stampFile); } catch (e) { /* absent is fine */ }

    fs.copyFileSync(source, dstExe);
    for (const f of ENGINE_FILES) {
      const s = path.join(srcDir, f);
      if (fs.existsSync(s)) fs.copyFileSync(s, path.join(dstDir, f));
    }
    for (const d of ENGINE_DIRS) {
      const s = path.join(srcDir, d);
      if (!fs.existsSync(s)) continue;
      // Removed first: a rule deleted upstream would otherwise linger here for
      // ever, and the copy would lint by rules the engine no longer ships.
      try { fs.rmSync(path.join(dstDir, d), { recursive: true, force: true }); } catch (e) { /* best effort */ }
      copyTree(s, path.join(dstDir, d));
    }
    if (want) fs.writeFileSync(stampFile, want, 'utf8');
    return { exe: dstExe, refreshed: true, reason: '' };
  } catch (e) {
    const why = (e && e.message) || String(e);
    // EBUSY/EPERM here is another VS Code window holding the copy. Keeping the
    // one already on disk is strictly better than failing to start.
    if (fs.existsSync(dstExe)) {
      return { exe: dstExe, refreshed: false, reason: 'keeping the existing copy: ' + why };
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

async function updateEngineNow() {
  if (!extContext) return;
  // The running server holds the copy, so it has to stop before the file can be
  // replaced. Same lock this whole mechanism is about, one level in.
  if (client) {
    try { await client.stop(); } catch (e) { /* already gone */ }
    client = undefined;
  }
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

function makeClient(exe) {
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
  const args = ['lsp'];
  for (const db of dbs) args.push('--db', db);

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

  const clientOptions = {
    documentSelector: [{ scheme: 'file', language: 'pascal' }],
    outputChannelName: 'drag-lint',
    errorHandler: makeErrorHandler(),
    synchronize: { fileEvents: manifestWatcher }
  };

  return new LanguageClient('dragLint', 'drag-lint', serverOptions, clientOptions);
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
  if (client) {
    try {
      await client.stop();
    } catch (e) {
      // A server that is already gone cannot be stopped cleanly, which is
      // precisely the case this command exists for.
    }
    client = undefined;
  }
  restartTimes = [];
  client = makeClient(exe);
  await client.start();
  window.setStatusBarMessage('drag-lint: language server restarted', 3000);
}

function activate(context) {
  extContext = context;
  // Its own channel, not the client's: this logs BEFORE the client exists, and
  // "which binary am I actually running" is the first question asked whenever
  // VS Code and the Delphi IDE disagree about an answer.
  engineLog = window.createOutputChannel('drag-lint (engine)');
  context.subscriptions.push(engineLog);

  const exe = resolveExe();
  log('language server exe: ' + exe);

  // Register the command FIRST and unconditionally. If the exe is missing at
  // activation, the user fixes the path and needs a way to start the server
  // without reloading the window -- registering only on the happy path would
  // mean the recovery command is absent exactly when it is needed.
  context.subscriptions.push(commands.registerCommand('dragLint.restartServer', restartServer));
  context.subscriptions.push(commands.registerCommand('dragLint.updateEngine', updateEngineNow));

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
  client.start();
  context.subscriptions.push({
    dispose: () => {
      if (manifestWatcher) manifestWatcher.dispose();
      return client && client.stop();
    }
  });
}

function deactivate() {
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
// testsscode\ can drive it directly with a stubbed `vscode` module; nothing
// in the extension itself reads this.
module.exports.__test = {
  mirrorEngine,
  resolveExe,
  privateEngineDir,
  setContext(ctx, channel) { extContext = ctx; engineLog = channel; }
};
