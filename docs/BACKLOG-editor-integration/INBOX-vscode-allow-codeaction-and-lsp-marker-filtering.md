# VS Code: "Allow this message" needs a code action AND engine work (DISTANT)

Filed 2026-08-12. Owner ruling: **distant future, not near.** The Delphi IDE is
the surface that matters; this note exists so whoever picks it up does not
rediscover the trap below.

## The trap: a code action alone would not work

The obvious read is "add `textDocument/codeAction`, call `TReviewMarkers`, done."
That ships a feature that visibly does nothing.

`ApplyLineMarkers` -- the ONE filter that honours `dl:ok` -- is called from
exactly one place in the whole tree: `FinalizeAndOutput` in `src/cli/DRagLint.CLI.pas`.
Nothing under `src/lsp/` references it. `TLspCompletion.BuildDiagnostics` applies
only the config filter (`Cfg.ShouldKeep`) and publishes everything else.

So in VS Code today, inserting a marker leaves the squiggle exactly where it was.
The legacy `// drag-lint:ignore` directive is equally unhonoured there.

**This is why the Delphi IDE got it for free and VS Code did not:** the plugin's
lint provider shells out to `drag-lint lint <file>` (`DragLint.Plugin.LiveDiagnostics.pas:221`)
and parses the output, so it goes through `FinalizeAndOutput`. The LSP computes
diagnostics in-process and skips that stage entirely.

## Therefore the work is two pieces, not one

1. **Engine** -- apply marker filtering on the LSP diagnostics path. Not a copy
   of `ApplyLineMarkers`: it should be lifted out of `DRagLint.CLI.pas` into a
   unit both callers use, or the two will drift and the editor will disagree with
   the CLI about what is suppressed. Note it needs the scanned-file list, not just
   the findings, because the unused-marker scan walks whole files.
2. **Protocol** -- `codeActionProvider` in the initialize result, a
   `textDocument/codeAction` handler, one `quickfix` per drag-lint diagnostic.
   The edit must call `drag-lint allow` or `TReviewMarkers.InsertInto`; never
   format a marker a second time.

No `extension.js` change is needed -- `vscode-languageclient` wires codeAction
automatically once the capability is advertised.

## Prior art, already written and reset away

Branch **`salvage/lsp-codeaction-agent`** (commits `042bb2f`, `0971bae`) has a
working skeleton: handler, builder, JSON-RPC framing, 62-line test script. It was
written unsupervised by a resumed episodic-memory agent, committed straight to
`main`, and reset off it. Read it for the framing, but it has three defects:

* it stuffs the entire finding MESSAGE in as the marker reason;
* it validates nothing against the rule catalogue -- syntax errors and compiler
  findings also offer "mark reviewed";
* it hand-rolls `'file:///' + StringReplace(...)` instead of the server's own URI
  convention.

## Line to mark

Whatever builds this must mark the diagnostic's **start line**: `ApplyLineMarkers`
keys suppression on `F.StartLine` (`DRagLint.CLI.pas`), so for a multi-line
finding (duplicate-code, the complexity family) the first line is the only line
ever checked. A marker anywhere else is silently inert.
