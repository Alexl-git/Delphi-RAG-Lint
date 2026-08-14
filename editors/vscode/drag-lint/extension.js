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

let client;

// Redeploying the engine REPLACES THE FILE A RUNNING SERVER IS EXECUTING FROM.
// dragLint.serverPath deliberately points at the same deployed binary the
// Delphi IDE loads (see the setting's description -- that guarantee is worth
// keeping), so `build\build_draglint_win64.bat` pulls the exe out from under a
// live session. vscode-languageclient's stock policy is 5 crashes in 3 minutes
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

function resolveExe() {
  return workspace.getConfiguration('dragLint').get('serverPath');
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

  const clientOptions = {
    documentSelector: [{ scheme: 'file', language: 'pascal' }],
    outputChannelName: 'drag-lint',
    errorHandler: makeErrorHandler(),
    synchronize: {
      // The index is rebuilt out-of-band; watching the manifest means a
      // reindex that adds a section does not require reloading the window.
      fileEvents: workspace.createFileSystemWatcher('**/drag-lint.json')
    }
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
  const exe = resolveExe();

  // Register the command FIRST and unconditionally. If the exe is missing at
  // activation, the user fixes the path and needs a way to start the server
  // without reloading the window -- registering only on the happy path would
  // mean the recovery command is absent exactly when it is needed.
  context.subscriptions.push(commands.registerCommand('dragLint.restartServer', restartServer));

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
  context.subscriptions.push({ dispose: () => client && client.stop() });
}

function deactivate() {
  return client ? client.stop() : undefined;
}

module.exports = { activate, deactivate };
