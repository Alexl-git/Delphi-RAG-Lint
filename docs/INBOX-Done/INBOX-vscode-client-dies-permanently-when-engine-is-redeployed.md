> **RETIRED to INBOX-Done/ on 2026-08-15.** DEFECT WHOSE FIX IS SHIPPED and guarded by a green regression runner in the full battery.
>
> Original note follows unchanged.

# INBOX -- redeploying the engine kills the VS Code client permanently

> **FIXED 2026-08-14 (session 19), commit `587546e`.** Reported again by the owner
> the same day ("VS Code still has problem starting our drag-lint") after this
> session's own engine redeploys reproduced it exactly as described below.
>
> All three suggested fixes were taken, and the "same binary as the IDE"
> guarantee was kept:
>
> 1. **`dragLint.restartServer` contributed and registered.** Registered
>    UNCONDITIONALLY and BEFORE the exe-exists check -- registering it on the
>    happy path only would mean the recovery command is absent exactly when it is
>    needed. It builds a FRESH `LanguageClient` rather than calling
>    `client.restart()`, because once the stock policy latches, the failure state
>    lives in the client object and reusing it is what we are recovering from.
> 2. **A bigger restart budget** -- 10 within a 3-minute sliding window, via a
>    custom `errorHandler`. When it IS exhausted the message names the likely
>    cause (a redeploy) and offers the command, instead of the stock "See the
>    output for more information." which, as noted below, blames the wrong thing.
> 3. **NOT the copy-the-exe-to-temp option**, for the reason given below: the
>    "same binary the Delphi IDE loads" guarantee is worth keeping, and a restart
>    command is the cheaper answer. Recorded so nobody re-opens it.
>
> Also closed here, from the sibling report: an empty string in
> `dragLint.databases` produced a trailing bare `--db`, which fatals during
> argument parsing. Now filtered.
>
> Guarded by `tests\autotest\run_vscode_extension_contract.ps1`, which checks
> manifest and code agree on commands in BOTH directions -- a command contributed
> but not registered is worse than none, since it appears in the palette and then
> fails -- that the budget still exceeds the stock 5, and that the installed
> `vscode-languageclient` major is >= 9 (where `CloseAction`/`ErrorAction` are
> reachable from `/node`; verified at `lib/common/api.js:27`, not assumed).
>
> **The "Also noticed" item below is still open**: `C:\Projects\.drag-lint.json`
> still declares the superseded `outDir` / flat `projects` layout. Harmless (the
> server auto-selects from the manifest beside the exe) but misleading, and the
> server still prints it on every startup.

Observed 2026-08-12 06:22, reported from the VS Code "drag-lint" output channel.

## What happened

```
[Error] Client drag-lint: connection to server is erroring. write EPIPE
[Error] Server process exited with code 3.
[Info ] Connection to server got closed. Server will restart.
   ... x5 ...
[Error] The drag-lint server crashed 5 times in the last 3 minutes.
        The server will not be restarted. See the output for more information.
```

## Diagnosis -- not an engine defect

`dragLint.serverPath` defaults to
`C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe`, which is
deliberate: the extension deliberately runs **the same deployed binary the Delphi
IDE loads**, so the two can never disagree about which build answered. The cost of
that choice is that `build\build_draglint_win64.bat` **overwrites the file the
running language server is executing from**. Five rebuild-and-stage cycles inside
three minutes is an ordinary engine-development session, and it is exactly the
condition vscode-languageclient treats as a broken server.

Verified healthy afterwards -- a stock initialize handshake against the same path:

```
drag-lint.exe lsp  <  {"jsonrpc":"2.0","id":1,"method":"initialize",...}
-> exit code 0, Content-Length: 355, full capability set returned
```

So nothing is wrong with the server. The client simply gave up and, per its own
policy, will not try again.

## Why it still matters

1. **There is no way back without reloading the window.** The extension
   contributes NO commands (`contributes.commands` is null), so there is no
   "drag-lint: Restart server". The user's only recovery is
   *Developer: Reload Window*. An engine developer hits this every session.
2. **The error text blames the wrong thing.** "Server process exited with code 3"
   invites debugging an engine crash that did not happen. The real event is "the
   binary was replaced under a running process".

## Suggested fixes (extension side, not engine)

* Contribute a `dragLint.restartServer` command -- one line of recovery instead of
  a window reload. This alone removes most of the pain.
* Consider `errorHandler` with a larger restart budget, or a restart that re-stats
  the exe rather than counting a replaced binary as a crash.
* Optionally: copy the exe to a temp location at spawn time and run that, so a
  redeploy cannot pull the file out from under a live session. Weigh against the
  "same binary as the IDE" guarantee above -- that guarantee is worth keeping, so
  a restart command is the cheaper answer.

## Also noticed while diagnosing

`C:\Projects\.drag-lint.json` (the scan config the server prints on startup as
"loaded defaults from ...") still declares `"outDir": "C:\\Projects\\.drag-lint"`
and a flat `projects` list -- the layout superseded on 2026-08-11/12 by the
per-project `<project>\_D-RAG\<project>.sqlite` home. It is stale. This is the
same class as the deferred "IDE's stale DbPathTemplate is never migrated" item.
It did not cause the crash (the databases setting is empty, so the server
auto-selects from the manifest beside the exe), but it will mislead the next
person who reads it.
