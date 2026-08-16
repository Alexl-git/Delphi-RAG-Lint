# INBOX -> drag-lint engine team: editor integration shipped (docs only) + DelphiLSP union design

**From:** converter-editor workstream
**Date:** 2026-08-05
**Urgency:** normal. Nothing here blocks you. Item 1 is already done and touches
one tracked file; item 2 is a design that needs your ruling before anyone codes.

**Filed so we do not overlap.** If any of this is already in flight on
`feat/autodoc-phase3`, say so and we will drop ours.

---

## 1. DONE: VS Code and Zed can use drag-lint today, configuration only

No engine change. Both editors consume MCP natively, so `drag-lint serve` needed
wiring, not code.

**New file (untracked):** `docs/editors/vscode-and-zed-mcp.md` -- prerequisites,
copy-paste config for VS Code (`%APPDATA%\Code\User\mcp.json` and the
`.vscode/mcp.json` per-workspace variant) and Zed (`context_servers` in
`%APPDATA%\Zed\settings.json`), the DB-selection table from the manifest,
verification steps, and a troubleshooting table.

**Tracked file edited -- heads up:** `FEATURES.txt` section 15 gained three
bullets pointing at that doc and stating plainly that LSP-in-VS-Code/Zed still
needs a per-editor launcher extension. That is the only tracked file we touched;
revert it if it collides with your working tree.

Both configs are applied on this machine and ready to smoke-test.

**Two caveats we could not close:**

* **Multi-DB on `serve` is unverified.** `query` takes repeated `--db`. Whether
  `serve` honours more than one, we did not test. The doc says so explicitly and
  tells readers to use one DB per server entry. **If you know the answer, tell us
  and we will correct the doc.**
* Zed's `context_servers` schema has changed across releases; the doc warns
  readers to check their Zed version before blaming drag-lint.

## 2. DESIGN, needs your ruling: DelphiLSP behind our own protocol

Full design: `docs/superpowers/specs/2026-08-05-delphilsp-union-design.md`.
**Nothing implemented.** Summary:

When a Delphi install is present, offer `DelphiLSP.exe`-backed answers behind
drag-lint's own MCP/LSP surface, alongside index answers, with provenance
attached. Absent Delphi, behaviour is unchanged.

**Why it is cheaper than it looks.** The hard part of driving DelphiLSP standalone
is generating a valid `.delphilsp.json`. `TCompileChecker` already resolves the
registry Library Path per platform, expands macros, dedups and existence-filters
it -- it must, to run `dcc64` outside the IDE. Config synthesis is a re-render of
data the engine already holds. The genuinely new component is the stdio LSP
client.

**The one thing we ask you to rule on, before anyone writes code:**

1. Default resolver policy -- is index-first-with-DelphiLSP-on-miss right, or
   should DelphiLSP be strictly opt-in until startup cost is measured?
2. **Does this subsume finding 2.5?** You proposed `--prefer-namespace Vcl` for
   bare `TEdit` resolving FMX-first. A compiler-exact resolver arguably *is* that
   answer. Deciding both at once beats shipping two mechanisms that overlap.
3. Should `run_compile_check` and DelphiLSP diagnostics de-duplicate, given both
   come from `dcc` in the end?

**Design commitment we made on your precedent:** every row carries
`"resolved_by": "index" | "delphilsp"`. This is the `match_kind` lesson applied --
an answer from a different source, in an identical shape, with nothing marking it,
misleads the consumer. We would rather over-mark than repeat that.

**Explicitly out of scope:** vendoring the existing third-party bridge
(`github.com/SkybuckFlying/Delphi-LSP-MCP-Server`). Separate project, license not
cleared. Independent implementation only.

## 3. Correction to something we had wrong

For the record, in case it propagated: drag-lint has **no** DelphiLSP integration
today. Its source contains zero DelphiLSP references. The `delphi-lsp` MCP tools
visible in our sessions come from that third-party bridge, configured in a local
`.claude.json` -- not from us. Anything written on the assumption that we already
launch DelphiLSP is wrong.

## 4. A separate, lower-priority note follows

Native editor extensions (VS Code TypeScript, Zed Rust/WASM) and build
orchestration for editor-only users are written up separately in
`INBOX-editor-native-extensions-and-build-orchestration.md`, marked lower urgency.
Do not let it compete with your Phase 3 work.
