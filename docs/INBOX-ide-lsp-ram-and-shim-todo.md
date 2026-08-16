> # 2026-08-16 (session 22): §1.1's ask is DONE. TODOs 3 and 4 remain IDE-blocked.
>
> **Done:** §1.1 said the capability finding was *"worth folding into section 4.4
> of the union design as a hard argument"*. Folded in. Section 4.4 had actually
> been WRONG -- it listed `references` as one of four *overlapping* request kinds
> to arbitrate between, when the measured handshake shows DelphiLSP does not
> advertise `referencesProvider` at all. It is now three overlapping kinds
> (hover / definition / completion), with `textDocument/references` and
> `workspace/symbol` documented as index-only: nothing to merge, no fallback to
> consult.
>
> **Verified:** all four `tools\lsp-diag\*.ps1` scripts exist and parse cleanly
> (arm / collect / disarm / watch). Checked by parsing only -- deliberately NOT
> executed, since `arm` mutates the registry and User environment. This matters
> because TODO 2b gets ONE shot at the next IDE start, and a capture script that
> fails then wastes the whole opportunity.
>
> **Still blocked, correctly:** TODO 3 (design-time package RAM audit) needs a
> running IDE by construction. TODO 4 (superset shim) is gated on 2b's error
> text, which needs an IDE start. Neither is startable here; nothing about them
> changed.

# INBOX: IDE LSP / RAM investigation -- deferred TODOs 3 and 4

**Date:** 2026-08-09
**Status:** items 1 and 2 DONE this session; items 3 and 4 BLOCKED on the IDE being startable.
**Related:** `docs/superpowers/specs/2026-08-05-delphilsp-union-design.md` (the union design this feeds)
**Hard constraint:** the 64-bit IDE is NOT an option. Paradox/BDE controls are 32-bit only and are
needed until the BDE -> FireDAC conversion completes. Everything below assumes the 32-bit IDE.

---

## 1. What was established (measured, not assumed)

| Question | Answer | Evidence |
|---|---|---|
| Does DelphiLSP consume 32-bit IDE address space? | **No.** Separate process tree (supervisor + `Agent0` + `Agent1`). | 39 processes observed with `bds.exe` not running |
| Would removing it free IDE RAM? | **No -- ~zero.** Only the client `IDELSP370.bpl` (771 KB) is in-process. | PE/PID inspection |
| Is `bin64\DelphiLSP.exe` self-sufficient? | **Yes.** `bin64` ships its own `dcc32370.dll` + `dcc64370.dll`. | directory listing |
| Is there a registry setting to point the IDE at a different LSP server? | **No.** Sweep of `HKCU\...\BDS\37.0` found no server-path override. | registry recursion |
| How does the IDE choose the server? | `delphicoreide370.bpl` embeds `DelphiLSP.exe` and `DelphiLSPLog`; **zero** `bin64` strings in EITHER the 32-bit or 64-bit copy -> path composed at runtime relative to the module. | UTF-16 string extraction |
| Do the 32-bit and 64-bit servers differ at the protocol level? | **No -- byte-identical.** Both return the same 423-byte `initialize` result. | direct stdio probe, `tools/lsp-diag/` |

### 1.1 DelphiLSP's actual advertised capabilities

Captured from a live `initialize` handshake (identical for x86 and x64):

```
textDocumentSync: 1
definitionProvider, declarationProvider, implementationProvider,
documentSymbolProvider, hoverProvider
completionProvider    { resolveProvider, triggers: . ( < [ }
signatureHelpProvider { triggers: ( , < }
publishDiagnostics    { tagSupport: [1,2] }
```

**Notably absent: `referencesProvider`, `workspaceSymbolProvider`, `renameProvider`.**

This matters for the union design. drag-lint's LSP server
(`src/lsp/DRagLint.LSP.Server.pas`) *does* implement `textDocument/references` and
`workspace/symbol`. So the union is not merely "index answers faster" -- drag-lint
fills capability holes DelphiLSP does not implement at all. Worth folding into
section 4.4 of the union design as a hard argument: for those two methods there is
nothing to merge and no ambiguity to resolve, drag-lint is the only provider.

### 1.2 Why the 64-bit-server-under-32-bit-IDE failure is still unexplained

The transport cannot be the cause: LSP is JSON-RPC over stdio, the servers are
byte-identical at `initialize`, and pipes are bitness-agnostic. So the fault is in
the IDE's own launch/config path, not the protocol. **The exact error text has not
been captured yet** -- that is TODO 2b below and it gates TODO 4.

---

## 2. Done this session

* Removed the `delphi-lsp` MCP registration from **6 configs** + 1 stale permission:
  `~/.claude.json`, `~/.claude/settings.json` (permission), `~/.gemini/antigravity/mcp_config.json`,
  Cline's `cline_mcp_settings.json`, and `.GEMINI/settings.json` in `C:\Projects`,
  `C:\Projects\DataCopy`, `C:\Projects\DB\ORM3`.
  Backups: `<file>.bak-delphi-lsp-removal` next to each original.
* Reaped the orphans: **183.5 MB private / 276.9 MB working set** reclaimed
  (36 processes: 13 `DelphiLSPMCPServer.exe` + their `DelphiLSP.exe` children).
* Built `tools/lsp-diag/` -- arm / collect / disarm scripts to capture the 64-bit error
  on the next IDE start.

### 2b. TODO -- capture the 64-bit error (do this at the next IDE start)

```
tools\lsp-diag\arm-lsp-diagnostic.ps1       # BEFORE starting the IDE
  ... start RAD Studio 13 (32-bit) FRESH from the Start Menu, reproduce ...
tools\lsp-diag\collect-lsp-diagnostic.ps1   # gathers logs + environment
tools\lsp-diag\disarm-lsp-diagnostic.ps1    # restores prior settings
```

`arm` sets `DelphiLSPLog=7` (User scope -- the env var `delphicoreide370.bpl` reads to
derive `-LogModes`) and flips `CodeInsightUse64BitBinary=True`. It records prior state
to `diag-state.json` so `disarm` restores exactly. The IDE must be launched fresh so it
inherits the environment variable.

---

## 3. TODO -- design-time package RAM audit  (BLOCKED: needs a running IDE)

**Why this is the real lever.** With the 64-bit IDE ruled out by BDE, the 32-bit
address space is fixed and precious. Code Insight is *not* what is consuming it --
the heavy half already left the process in 10.4.2. Loaded design-time packages are.
The install has **305 BPLs** in `bin64` and a comparable set in `bin`; DevExpress's
design-time set alone typically dwarfs everything LSP-related.

**Method:**
1. Start the IDE normally, load a representative project, let it settle.
2. Enumerate loaded modules in `bds.exe` and their committed sizes:
   `Get-Process bds | Select-Object -ExpandProperty Modules` -> rank by `ModuleMemorySize`.
3. Cross-reference against `HKCU\Software\Embarcadero\BDS\37.0\Known Packages` and
   `Known IDE Packages` to map each BPL to a removable feature.
4. Produce a ranked "cost vs. do-you-use-it" table.
5. Disable the unused ones; re-measure to confirm the saving is real.

**Expected output:** a ranked table and a concrete disable list. This is ordinary
supported configuration -- no unsupported hacking, no risk to the toolchain.

**Do NOT skip step 5.** Unloading a package that something silently depends on shows up
as a missing-component error when opening a form, not at IDE start.

---

## 4. TODO -- superset shim  (BLOCKED: needs 2b's error text first)

**Do not start this until 2b is captured.** The whole design rests on knowing *why*
the IDE fails with the 64-bit server. If it turns out to be a config/handshake
mismatch, a relay reproduces the identical failure, because it forwards the same bytes.

**Mechanism** (the only hook that exists -- there is no setting):

```
bin\DelphiLSP.exe       ->  32-bit shim (drag-lint relay)
bin\DelphiLSP.real.exe  ->  renamed original
```

**Shape -- superset proxy, nothing less:**
1. Forward every request to the real DelphiLSP (optionally the 64-bit one, which is the
   point: this is also the 64-bit escape hatch for a 32-bit IDE).
2. Answer from the drag-lint index the things DelphiLSP does not implement --
   `textDocument/references`, `workspace/symbol` (see 1.1).
3. Merge into `publishDiagnostics` alongside lint findings, carrying `resolved_by`
   provenance per the union design section 4.4.

**Functionality impact:**

| Design | Result |
|---|---|
| Superset proxy (forward everything, add index results) | **No loss.** The only acceptable shape. |
| Pure drag-lint, DelphiLSP removed | Loses Error Insight, type-exact completion, overload/generic resolution, inline-var inference. Not acceptable. |

**It must advertise at least the capability set in 1.1**, or the IDE silently drops
features. Capture the real server's `initialize` result and pass it through rather than
hand-authoring it.

**Risks -- all still live:**
* Modifying `Program Files`; every RAD Studio patch/reinstall reverts it.
* Wholly unsupported by Embarcadero.
* A protocol mismatch kills Code Insight, and the failure mode is quiet.
* Crash/restart handling must be solid or the editor degrades with no obvious cause.

**RAM note:** this makes memory *worse*, not better -- shim plus real server. Justify it
by 64-bit escape and merged results only. Never by RAM.
