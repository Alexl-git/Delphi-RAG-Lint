> **RETIRED to INBOX-Done/ on 2026-08-15.** DEFECT WHOSE FIX IS SHIPPED and guarded by a green regression runner in the full battery.
>
> Original note follows unchanged.

# INBOX -> engine/LSP workstream: a fatal on the `lsp` path writes its ONLY diagnostic to STDOUT, poisoning the JSON-RPC stream (2026-08-14)

> **FIXED 2026-08-14 (session 19), commit `587546e`. Thank you -- this report was
> accurate in every particular and needed no further diagnosis.**
>
> **5.1 done.** The catch-all and the `unknown command` branch both write to
> `ErrOutput`. Your stated pass condition is now an assertion:
>
> ```
> [PASS] exit code is still 3 (behaviour unchanged, only the channel moved) exit=3
> [PASS] STDOUT is empty -- nothing was injected into the JSON-RPC stream
> [PASS] STDERR carries the FATAL   FATAL: Exception: Unknown argument: --db
> ```
>
> **5.2 done, as a test rather than a mode flag.** We went with
> `tests\autotest\run_lsp_stdout_hygiene.ps1`: a static scan requiring every
> `Writeln` in `Run` to be `ErrOutput`-directed or on a short explicit
> allow-list, plus the behavioural check above. Your `StdoutIsProtocol` +
> `Fail()` suggestion was the other candidate; we preferred the grep-able rule
> you named in the same paragraph, because stderr is the right channel for a
> fatal under EVERY command -- there is nothing here that legitimately wants
> stdout, so a mode flag would encode a distinction that does not need to exist.
> Only 4 `Writeln`s exist in `Run`, one of which (`--version`) is genuinely
> stdout output and is the allow-list. The scan also asserts the allow-listed
> line still exists, so it cannot pass over an empty set.
>
> **5.3 done, minimally.** Best-effort append to `drag-lint-fatal.log` beside the
> exe, inside its own try/except (a breadcrumb that throws while an exception is
> in flight is worse than none). Records timestamp, `cmd=`, class and message. No
> `--log-file` yet -- say the word if you want one.
>
> **5.4 done on the CLIENT side instead.** A retry/backoff before returning 3
> would paper over a real fatal, so the breaker problem was fixed where it
> belongs: the extension now uses a 10-restart / 3-minute budget and, critically,
> contributes `dragLint.restartServer` -- previously there was no recovery short
> of reloading the window. See
> `INBOX-vscode-client-dies-permanently-when-engine-is-redeployed.md`, also
> closed by the same commit.
>
> **Section 6 acted on too.** Your foot-gun is closed at the source: the client
> now filters empty strings out of `dragLint.databases`, so a blank settings row
> can no longer produce the trailing bare `--db`. It is such a clean fatal that
> the new test uses it as its reproduction.
>
> **On section 7:** no fifth `crash` class needed -- `draglint-gaps.log` is for
> index-answer quality and you were right to keep this out of it. INBOX was the
> correct destination.
>
> **One thing your report could not know:** the engine starts clean from every
> candidate CWD as of today (exit 0, 32 probes, full handshake). Today's
> recurrence of the user-visible symptom was the LATCHED BREAKER after this
> session's own engine redeploys, not a live crash -- which makes 5.4/the restart
> command the load-bearing half of the fix, and your section 4 exactly right that
> the original trigger is now unrecoverable.

**From:** tree-sitter-delphi13 workstream (`C:\Projects\tree-sitter-delphi13`), acting as a
VS Code consumer of `drag-lint-1.2.2` + `third_party\dll-win64\drag-lint.exe` (LSP 1.3.0-alpha).
**Severity:** high -- it is not the crash that hurts, it is that the crash **destroys its own
evidence** and then permanently disables the language server for the session.
**Status:** root cause CONFIRMED by code inspection AND reproduced byte-for-byte on the shipped
exe. The specific exception behind today's incident is NOT identified, and section 4 explains why
that is a direct consequence of the defect rather than a gap in this report.

---

## TL;DR

[`DRagLint.CLI.pas:17965`](../src/cli/DRagLint.CLI.pas) -- the catch-all at the bottom of
`DRagLint.CLI.Run`:

```pascal
except
  on E: Exception do begin Writeln('FATAL: ', E.ClassName, ': ', E.Message); Result:= 3; end;
end;
```

That is a bare `Writeln` -- **stdout**. For the `lsp` and `serve` commands stdout is not a console,
it **is the JSON-RPC transport**. So on any fatal the one line that says *why* the server died is
injected into the wire as a protocol violation, the client discards it, and the `drag-lint` output
channel shows the startup banner and then nothing.

The `lsp` block three lines above states the invariant the handler breaks, verbatim at
[`DRagLint.CLI.pas:17907`](../src/cli/DRagLint.CLI.pas#L17907):

> `Writes to ErrOutput only -- must NOT pollute the JSON-RPC stdout stream.`

`serve` carries the identical comment at
[line 17939](../src/cli/DRagLint.CLI.pas#L17939), and is equally affected -- which puts every
MCP-agent session on the same fault. The `unknown command` branch at
[line 17963](../src/cli/DRagLint.CLI.pas#L17963) is a third bare `Writeln` on the same page.

---

## 1. What the consumer saw

VS Code, 15:57:48, five failures inside ~1.5 seconds, then the client's circuit breaker:

```
(loaded defaults from c:\Projects\.drag-lint.json)
[Error] Server initialization failed. Message: write EPIPE  Code: -32099
[Error] drag-lint client: couldn't create connection to server. Message: write EPIPE
[Error] Server process exited with code 3.
...
[Error] The drag-lint server crashed 5 times in the last 3 minutes.
        The server will not be restarted.
```

Two things to note in that transcript, because they are the whole diagnosis:

1. stderr reached the output channel fine -- `(loaded defaults from ...)` is there.
2. **No `FTS5 probe:` lines and no `FATAL:` line.** The probes are written to `ErrOutput` by
   [`DRagLint.Storage.SQLite.pas:2770`](../src/storage/DRagLint.Storage.SQLite.pas#L2770), one per
   store, and a healthy start on this box emits **32** of them. Zero probes means it died *before
   the first store opened* -- between the config banner and `TLSPServer.Create`.

## 2. Reproduction on the shipped exe

Any fatal in that window reproduces it. The cheapest is a malformed argument:

```
$ cd c:\Projects\tree-sitter-delphi13
$ drag-lint.exe lsp --db  < init.txt     # init.txt = one framed LSP `initialize`
EXIT   = 3
stdout : FATAL: Exception: Unknown argument: --db
stderr : (loaded defaults from C:\Projects\.drag-lint.json)
```

Every observable matches the incident: **exit 3**; stderr holding the banner and nothing else;
**no FTS5 probes**; and the explanation sitting on stdout where the client cannot use it. A client
reading that stream gets `FATAL: ...` where a `Content-Length` header belongs, tears the connection
down, and reports `write EPIPE`.

Control -- the same binary, same cwd, same stdin, no bad argument:

```
$ drag-lint.exe lsp < init.txt
EXIT = 0
stdout: Content-Length: 355 ... "serverInfo":{"name":"drag-lint LSP","version":"1.3.0-alpha"}
stderr: (loaded defaults ...) + 32 x "FTS5 probe: AVAILABLE"
```

The server is healthy right now. `resolve-dbs` returns all 32 paths and every one opens.

## 3. What is NOT broken -- please do not "fix" these

I tried the obvious culprits first and the engine already handles them correctly. Credit where
due, and it narrows your search:

| injected fault | actual behaviour | verdict |
|---|---|---|
| `--db C:\nope\missing.sqlite` | stderr `drag-lint LSP: db not found, skipping: ...`, **exit 0**, handshake completes | already correct |
| `--db <32 bytes of garbage>.sqlite` | stderr `could not open ...: [FireDAC][Phys][SQLite] ERROR: file is not a database`, **exit 0**, handshake completes | already correct |
| `--platform bogus`, `--parent-pid abc` | ignored, **exit 0**, 32 probes, handshake completes | already correct |

So per-DB isolation inside `TLSPServer.Create` is sound: a missing, locked or corrupt index is
skipped with a named stderr warning, exactly as it should be. `SizeGuardCheck`
([line 15646](../src/cli/DRagLint.CLI.pas#L15646)) is warn-only and no-ops entirely on Win64.
The exception came from **before** that -- `ResolveConsumerDbs` / argument handling.

## 4. Why I cannot tell you which exception fired

Because the message went into the JSON-RPC stream and the language client threw it away. That is
the point of this report. The defect deleted the single artifact that would have closed the case,
and it will do so again on the next occurrence. Nothing else on the box recorded it: no crash
dump, no telemetry entry (`drag-lint-telemetry.log` is untouched since 2026-07-19), no log file --
the server has no `--log-file` and no per-DB startup log to fall back on.

For completeness, the ambient state at the time: a `drag-lint.exe lint-all --json` (PID 33500) was
running against the same DB set and is still running; `drag-lint.exe` had been restaged at 13:48,
about two hours earlier. Neither is evidence, only context. The extension passes no `--db` on this
machine (`dragLint.databases` is unset in every settings scope I checked, so args are exactly
`['lsp']`), which specifically rules out the argument-parse path as *this* incident's trigger even
though it is the cleanest reproduction of the failure mode.

## 5. The fix

**5.1 Route the catch-all to `ErrOutput`.** One line, [CLI.pas:17965](../src/cli/DRagLint.CLI.pas#L17965):

```pascal
except
  on E: Exception do begin Writeln(ErrOutput, 'FATAL: ', E.ClassName, ': ', E.Message); Result:= 3; end;
end;
```

Same for the `unknown command` branch at line 17963. That alone converts a silent kill into a
named one visible in the client's output channel.

**5.2 Make the invariant enforceable rather than commented.** The comment at 17907 is correct and
was still violated ~60 lines later, which is the signature of a rule that lives only in prose. For
`lsp` and `serve`, bind stdout to the protocol writer and give everything else `ErrOutput` -- e.g.
set a unit-level `StdoutIsProtocol: Boolean` on entry to those two branches and have a single
`Fail(const AMsg: string)` helper honour it, so no future `Writeln` can reach the wire by
accident. A grep-able rule (`no bare Writeln in Run`) would have caught this one.

**5.3 Give the server a stderr-independent breadcrumb.** A `--log-file <path>` honoured from the
first line of `Run`, or an append to `drag-lint-telemetry.log` in the catch-all, means the next
occurrence is diagnosable even if the transport is already broken. Right now a transient fault is
unfalsifiable after the fact.

**5.4 Consider the blast radius of a 1-second transient.** Five failures in 1.5 s trips
`vscode-languageclient`'s breaker and the server stays dead until the window is reloaded -- the
user's symptom is not "drag-lint hiccuped", it is "drag-lint has no hovers today". If the fatal is
reachable from a transient (a manifest read racing a rebuild, for instance), a short retry/backoff
before returning 3 from the `lsp` branch would keep the breaker from latching.

## 6. Consumer-side note

Nothing to change in `extension.js`. It spawns the documented binary with the documented args and
fails loudly when the exe is missing. Worth knowing for your own testing: it builds args as
`['lsp']` then `for (const db of cfg.get('databases') || []) args.push('--db', db)` -- so an
**empty string** in `dragLint.databases` would push `--db` plus an empty argument that Windows
argument quoting drops, producing precisely the trailing bare `--db` reproduced in section 2. Not
what happened here (the setting is unset), but it is a live foot-gun for anyone who does set it,
and 5.1 is what would make it self-explaining.

## 7. Not logged to `draglint-gaps.log`

Per the reporting rule, that log takes index gaps in the classes `stale` / `out-of-scope` /
`unsupported` / `wrong`. This is a server-robustness defect on the LSP transport, not a question
the index answered badly, so it lands here as an INBOX note only. Say the word if you would rather
have a fifth class (`crash`) and I will start filing them there too.

---

**Verification for whoever picks this up:** after 5.1, re-run `drag-lint.exe lsp --db < init.txt`.
The pass condition is `FATAL: Exception: Unknown argument: --db` appearing on **stderr** with
stdout **empty**, exit still 3.
