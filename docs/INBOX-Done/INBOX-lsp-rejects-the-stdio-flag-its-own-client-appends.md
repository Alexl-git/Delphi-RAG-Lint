> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21).** FIXED 2026-08-16 (8d911f9): ParseArgs accepts --stdio (and --clientProcessId) as no-ops. Verified -- `lsp --stdio` no longer prints "Unknown argument". --node-ipc/--pipe/--socket stay REJECTED on purpose: this server cannot speak them and silently ignoring a transport would hang the client instead of failing it.

# INBOX: the VS Code client cannot start the server -- `lsp` rejects `--stdio`

_Filed 2026-08-16 (session 21). Reported live by the owner from the VS Code
"drag-lint" output channel. NOT yet fixed -- deferred by owner ("file this,
we'll deal with this later")._

## Symptom

Every server start fails, five times, then vscode-languageclient latches its
circuit breaker:

```
(loaded defaults from c:\Projects\.drag-lint.json)
FATAL: Exception: Unknown argument: --stdio
[Error] Server process exited with code 3.
[Error] Client drag-lint: connection to server is erroring. write EPIPE
[Error] Server initialization failed. Message: write EPIPE  Code: -32099
[Error] The drag-lint server crashed 5 times in the last 3 minutes.
        The server will not be restarted.
```

`write EPIPE` and the `Client is not running and can't be stopped. It's current
state is: starting` stack are **downstream noise** -- the client is writing the
`initialize` request into a process that has already exited. The one load-bearing
line is `Unknown argument: --stdio`.

## Reproduced byte-for-byte on the shipped exe

```
PS> echo "" | third_party\dll-win64\drag-lint.exe lsp --stdio
(loaded defaults from C:\Projects\.drag-lint.json)
FATAL: Exception: Unknown argument: --stdio
EXIT=3
```

Exe stamp: 2026-08-16 01:08. Without `--stdio` the same exe starts and speaks
LSP normally, so the server itself is healthy.

## Root cause

**The client library appends the flag; the extension never writes it.**

[extension.js:87-92](editors/vscode/drag-lint/extension.js#L87-L92) builds
`const args = ['lsp']` (plus any `--db`) and then declares:

```js
run:   { command: exe, args, transport: TransportKind.stdio },
debug: { command: exe, args, transport: TransportKind.stdio }
```

`vscode-languageclient/lib/node/main.js:287-289` turns that declaration into an
argv entry:

```js
else if (transport === TransportKind.stdio) {
    args.push('--stdio');
}
```

So the exe is always launched as `drag-lint lsp --stdio`. The CLI's shared
`ParseArgs` ends with a strict catch-all,
[DRagLint.CLI.pas:1075](src/cli/DRagLint.CLI.pas#L1075):

```pascal
else raise Exception.CreateFmt('Unknown argument: %s', [A]);
```

`--stdio` matches no handler, so the process dies during arg parsing -- before
`Args.Command = 'lsp'` is ever dispatched at
[DRagLint.CLI.pas:17970](src/cli/DRagLint.CLI.pas#L17970).

## This has been broken since the client was written

`git log -S "'--stdio'" --all -- src/` returns **nothing**: no commit in this
repo has ever added, removed, or touched a `--stdio` handler. The extension was
added 2026-08-11 (`c92cb1d`) already carrying `transport: TransportKind.stdio`,
and the installed `drag-lint-1.2.2` and the repo's `1.3.0` source carry the same
two lines. **The VS Code language client has therefore never completed a start.**

What changed is only the *visibility*. `587546e` ("a fatal wrote its only
diagnostic INTO the JSON-RPC stream") moved the catch-all `Writeln` off stdout,
so the fatal now reaches the output channel instead of being injected into the
wire as a corrupt frame. That fix worked exactly as intended -- it did not cause
this, it **uncovered** it. The earlier bug destroyed the message that explains
this one, which is why a two-week-old defect is only being read today.

Note the contrast with the Delphi IDE plugin, which launches the same server with
`--parent-pid <n>` (a flag `ParseArgs` *does* know) and no transport flag -- which
is why the in-IDE LSP path never hit this.

## Fix -- two candidates, decide which is the contract

1. **Accept and ignore `--stdio` in `ParseArgs`** (one `else if` beside
   `--parent-pid`). stdio is the only transport the server implements, so the
   flag is a truthful no-op. Fixes every already-installed extension build
   without republishing, and matches how most LSP servers behave.
2. **Drop `transport: TransportKind.stdio` from `serverOptions`** in
   `extension.js`. For an `Executable`, omitting `transport` already gives
   stdio pipes without the flag. Cleaner, but requires shipping a new `.vsix`
   and leaves the exe brittle against any client that does pass the flag.

Recommendation: **do 1, and consider 2 as well.** 1 alone restores the installed
client; the two together mean neither side depends on the other's convention.

Whatever is chosen, the guard must be a **positive control**, not just "the
fatal is gone": drive a real `initialize`/`shutdown` handshake through
`drag-lint lsp --stdio` and assert a `Content-Length` frame comes back with
server capabilities -- a test that only asserts exit code 0 would pass against a
server that parsed the flag and then did nothing.

## Also worth checking while in here

- Any *other* flag a stock LSP client may append that `ParseArgs` would reject
  the same way: `--node-ipc`, `--pipe=<name>`, `--socket=<port>`,
  `--clientProcessId=<n>`. `--clientProcessId` in particular is appended by some
  clients unconditionally. The strict catch-all turns each into the same fatal.
- The installed extension is **1.2.2** while the repo source is **1.3.0** -- the
  owner's VS Code is a version behind whatever `editors/vscode/drag-lint/` now
  contains. Confirm which one is meant to be deployed before testing a fix.
