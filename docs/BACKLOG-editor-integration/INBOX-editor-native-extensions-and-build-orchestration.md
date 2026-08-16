# INBOX -> drag-lint engine team: native editor extensions + build orchestration

**From:** converter-editor workstream
**Date:** 2026-08-05
**Urgency:** LOW -- deliberately filed separately from
`INBOX-editor-integration-and-delphilsp-union.md` so it does not compete with
Phase 3. Nothing here is blocking, nothing is started, and none of it should
displace work you already have queued.

**Why file it at all:** to stake the ground so we do not both start it. If you
want any of this, say so and it is yours.

---

## Context

MCP wiring for VS Code and Zed is done (see the companion note) -- configuration
only. What remains for a user who lives in VS Code or Zed and **never opens RAD
Studio** is two things: an LSP launcher per editor, and a build story.

## 1. Native LSP extensions

`drag-lint lsp --db <db>` already implements 12 methods (`initialize`,
`shutdown`, `textDocument/` `hover`, `definition`, `references`, `completion`,
`signatureHelp`, `didOpen`, `didChange`, `didSave`, `publishDiagnostics`,
`workspace/symbol`), with lint findings and `dcc` compiler findings merged into
diagnostics. It is exercised today by the RAD Studio design-time plugin.

Neither editor can launch a bare LSP binary from settings. Each needs a launcher:

| Target | Shape | Notes |
|---|---|---|
| VS Code | TypeScript extension wrapping `vscode-languageclient` | Spawn the exe, bind to Pascal file types, surface the DB path as a setting |
| Zed | Rust/WASM Zed extension registering a language server | Same binary; Zed's extension API is the unfamiliar part |

**No engine work in either.** This is packaging. The realistic risk is not
difficulty but maintenance: two more published artifacts to version alongside the
engine, in two languages the project otherwise does not use. `FEATURES.txt` says
"Pure Object Pascal at runtime - no Python, Node, or Rust" -- these extensions
would be the first exception, even though the runtime stays Pascal. Worth deciding
deliberately rather than drifting into it.

## 2. Build orchestration -- honest value assessment

We looked at this because DDK (`Snowcaloid.delphi-devkit`, a VS Code extension
whose whole premise is orchestrating your local Delphi install) makes it look like
table stakes. Splitting the question by audience flips the answer:

| Audience | Value |
|---|---|
| **Us / anyone with the IDE open** | **Low.** The IDE compiles. The `delphi-build` recipe covers scripted builds. Multi-version profiles (Delphi 2007 -> 13) are worth ~zero here -- one install. |
| **Editor-only users** | **It is the entire product.** Without a build story they cannot work at all. |

**We already have roughly 80% of the thin version.**
`src/diagnostics/DRagLint.Diagnostics.CompileCheck.pas` (`TCompileChecker`)
already: spawns msbuild for `.dproj` and `dcc64` for `.pas`/`.dpr`/`.dpk`;
resolves `rsvars.bat`; picks `dcc32`/`dcc64` by platform; reads the IDE global
Library Path from the registry per platform, expands macros, dedups and
existence-filters it, injects via `DCC_UnitSearchPath`; writes a `dcc64.cfg` to
dodge the ~8 KB command-line limit; parses H/W/E/F into structured findings;
supports full rebuild; and stores findings in `compiler_findings` for
`publishDiagnostics` merging. Exposed via CLI, MCP (`run_compile_check`) and the
IDE plugin.

**What is genuinely missing for editor-only users:**

* multi-version compiler profiles and switching (we assume one install)
* `.groupproj` handling (we parse `.dproj` for `index`/`lint`, not build groups)
* editor-native task/problem-matcher integration, so errors are clickable
* formatter integration

**Verdict:** multi-version profiles are DDK's moat and rebuilding them for
ourselves is waste. But if we ever publish for editor-only users, the thin version
is mostly already written and the gap is smaller than it looks. Recommend: do
nothing now; revisit only if editor-only adoption actually materialises.

**Constraint that applies to any version of this:** Windows only, and a licensed
non-Community Delphi -- Community Edition forbids command-line compilation. DDK
carries the identical limitation, so it is the market's constraint, not ours.

## 3. If this is done autonomously (e.g. over a weekend)

Flagging what is and is not safe unattended, since that was raised:

**Safe unattended** -- deterministic, verifiable without a live GUI:

* VS Code extension scaffolding, `package.json`, activation events, settings schema
* Zed extension scaffolding
* Docs for both
* A headless smoke test that spawns `drag-lint lsp` and drives an `initialize`
  handshake over stdio, asserting the capability set -- no editor required

**NOT safe unattended** -- needs a human at a live editor:

* Confirming completion/hover/definition actually render in each editor
* Anything touching the RAD Studio IDE or its packages
* Any full library reindex (destructive; a killed run leaves a partial DB that
  still answers queries)

The honest split is that the scaffolding and the headless handshake test are real,
checkable work; "the extension works" is a claim only a human at the editor can
make. An autonomous run should stop at the former and say so plainly rather than
report success it cannot verify.
