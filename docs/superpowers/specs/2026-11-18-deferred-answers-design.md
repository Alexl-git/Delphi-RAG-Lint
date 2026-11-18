# Deferred slow answers (ruling B9c) -- design

Lane v152 ASYNC, 2026-11-17. Status: implemented for the RAD Studio dwell hover (LSP `draglint/hoverBundle`).
Runner: `tests\autotest\run_v152_ASYNC_hover.ps1`.

## The ask

Any slow on-demand answer a user is WAITING for returns the fast parts at once with a `computing...`
placeholder, fills the slow part in later, and CANCELS it when the user moves on. Batch callers
(autodoc, lint-all, MCP, CLI) keep the whole answer in one reply.

## Which answers are slow -- measured on CLIENT

`scratch\measure.ps1` (lane folder): 120 hovers on a COPY of the CLIENT index (60 declarations,
60 resolved call sites, deterministic sample), `DRAGLINT_HOVER_TIMING=1` printing one stderr line
per section. Milliseconds:

| section | p50 | p95 | max |
|---|---|---|---|
| select (symbol at the cursor) | 17 | 104 | 167 |
| Phase-2 facts (markdown) | 56 | 371 | 742 |
| Raises: lines | 1 | 4 | 19 |
| markdown total (incl. facts) | 133 | 497 | 895 |
| model assembly (incl. facts AGAIN) | 52 | 313 | 8322 |
| resolved callers | 50 | 2667 | 3687 |
| by-name callers | 32 | 3380 | 5188 |
| WHOLE reply (before) | 376 | 6453 | 9497 |

The slow sections are the callers (p95 2.7 s + 3.4 s) and the Phase-2 facts (p95 0.37 s, built
twice per popup before this lane). Symbol selection, doc, signature, returns are fast.

After the change (`scratch\measure2.ps1`, same 120 positions, announced two-step):

| reply | p50 | p95 | max |
|---|---|---|---|
| FAST first step (popup with `computing...`) | 76 | 211 | 7376 |
| WHOLE second step | 169 | 5426 | 9537 |
| markdown (incl. facts, built once now) | 55 | 210 | 853 |

All 120 first replies were deferred. The two first-step outliers (1591 ms, 7376 ms) are both
INTERFACE methods (`IMicObject.Writer`, `ImcPLANLIST.SetPTYPE`): `AssembleHover` always computes
the "Implemented by:" line (`ImplementingMethodsOf`), even without facts, and an interface method
with hundreds of implementors costs seconds. Deferring it needs an `AssembleHover` switch in
`DRagLint.Query.HoverModel` (HBHOVER's file): HANDOVER, not in this lane.

## Protocol (D1 "announce + ask twice")

1. The client sends the notification `draglint/deferHover {textDocument, position}`.
2. The next `draglint/hoverBundle` at that position is the FAST step: no Phase-2 facts, no Raises:,
   no callers; the facts list holds the one line `computing...`; `result.deferred =
   {placeholder, pending: [facts, exceptions, callers]}`; empty caller arrays.
3. The client asks the same position again: the WHOLE bundle. It is cancellable: the server
   yields between sections (and in the slow ones) and answers `-32800 RequestCancelled` -- no
   result -- once the client announced another position or sent `$/cancelRequest` for its id.
4. Anything unannounced is answered whole, as before: the menu hover, `textDocument/hover`
   (VS Code), MCP, CLI. An engine before 1.52 ignores the notification and answers step 2 whole,
   so an old engine and a new plugin (or the reverse) still work.

Why two requests rather than a server push: the request and its reply parser live in
`DragLint.Plugin.Editor` (outside the lane); a second ordinary request reuses both unchanged.

## Decisions

* **D2 single-threaded.** No worker thread: FireDAC connections are per thread and the library DB
  is 3 GB. Cancellation is cooperative at section checkpoints (`YieldToPendingRequests`), so its
  latency is one section; the runner measures it under 300 ms.
* **D3 VS Code and MCP stay synchronous in 1.52** (PLAN D13). An agent is a batch caller.
* **D4 `$/cancelRequest`** was a server no-op; it now abandons only a deferred second step.
* **D5 (new, proved by reasoning on the client code).** Only an announcement or `$/cancelRequest`
  abandons a running second step -- an UNANNOUNCED hover elsewhere does not. The plugin cancels
  its own request before it announces the next position, so the `-32800` reaches a dropped
  callback. The menu hover says nothing about the dwell, whose callback is still live, and
  `ParseHoverBundleReply` latches ANY error reply as "engine without hoverBundle" for the whole
  session. Runner check T5.
* **D6 one facts build per popup.** `ComputeHoverAt` keeps the `TDocFacts` and Raises: lines it
  built for the markdown (`THoverComputation.FactsReady`), and the bundle's model reuses them
  (`AssembleHover(.., AWithFacts=False)` + the same formatters) instead of building both again.

## Plugin (DragLint.Plugin.HoverTracker)

* The dwell sends `deferHover`, then the bundle request (same write queue, so in order).
* A partial answer (a fact line equal to the placeholder) is shown at once and NOT cached; the
  same position is asked again. The whole answer replaces the partial popup in place while it is
  up (the user may be reading it, pointer on the popup), else through the usual show-gate.
* Every tick: a second step whose popup was closed AND whose token the pointer left is cancelled.

## Limits

* A `didChange` queued during a second step stops further yields (existing rule: once anything is
  deferred nothing later is served early), so that step runs to its end. Hovering without edits
  sends no `didChange`.
* The injected slow section (`DRAGLINT_TEST_HOVER_SLOW_MS`) is a test switch, sliced at 20 ms.
