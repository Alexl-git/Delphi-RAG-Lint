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

const { workspace, window } = require('vscode');
const { LanguageClient, TransportKind } = require('vscode-languageclient/node');
const fs = require('fs');

let client;

function activate(context) {
  const cfg = workspace.getConfiguration('dragLint');
  const exe = cfg.get('serverPath');

  // Fail LOUDLY and specifically. A language client that cannot spawn its
  // server otherwise just produces no hovers, which reads as "the index has
  // nothing" rather than "the binary is missing".
  if (!exe || !fs.existsSync(exe)) {
    window.showErrorMessage(
      `drag-lint: server not found at "${exe}". Set "dragLint.serverPath" to your drag-lint.exe.`
    );
    return;
  }

  // No --db by default. drag-lint resolves databases from the drag-lint.json
  // sitting beside the exe, which is the same manifest the Delphi IDE reads --
  // so VS Code follows the project layout automatically instead of pinning a
  // list here that would rot the next time a project DB is added or renamed.
  const args = ['lsp'];
  for (const db of cfg.get('databases') || []) args.push('--db', db);

  const serverOptions = {
    run:   { command: exe, args, transport: TransportKind.stdio },
    debug: { command: exe, args, transport: TransportKind.stdio }
  };

  const clientOptions = {
    documentSelector: [{ scheme: 'file', language: 'pascal' }],
    outputChannelName: 'drag-lint',
    synchronize: {
      // The index is rebuilt out-of-band; watching the manifest means a
      // reindex that adds a section does not require reloading the window.
      fileEvents: workspace.createFileSystemWatcher('**/drag-lint.json')
    }
  };

  client = new LanguageClient('dragLint', 'drag-lint', serverOptions, clientOptions);
  client.start();
  context.subscriptions.push({ dispose: () => client && client.stop() });
}

function deactivate() {
  return client ? client.stop() : undefined;
}

module.exports = { activate, deactivate };
