<!-- dl:backlog status=open last-measured=2026-09-22 -->
# charts\ -- staging area for the Archify-parity diagram work

Everything for the typed diagram IR, the emitters and the HTML/Graphviz
rendering loop is developed HERE first, and moves into the main tree
(`src\report\`, `src\cli\`, `tests\autotest\`) only when it earns its place.

Opened 2026-09-22 in worktree `C:\Projects\Delphi-RAG-lint-wt\archify-ir`
(branch `feat/archify-ir`, based on `main` at `4ccd1779`).

## Why a staging subfolder

The engine queue (bookmarks, shared-unit prefixes, project-facts, interface
dispatch, the exception fact) keeps moving on `main` in parallel. New files in
`charts\` can never conflict with it. The single real conflict point is
`src\cli\DRagLint.CLI.pas` -- so the CLI verb is added LAST, as one contiguous
block, when the rest is proven.

## Layout

```
charts\
  README.md            this file
  src\                 Delphi units under development (move to src\report\ later)
  shell\               the HTML/Mermaid shell and its assets
  fixtures\            small hand-written IR / dot samples for tests
  scratch\             throwaway output -- never committed
```

## Graphviz -- present and verified 2026-09-22

* `C:\Projects\GraphWiz\Graphviz-16.1.0-win64\bin\dot.exe` -- version 16.1.0
  (20260904.0139). Parent folder is **GraphWiz**, product folder **Graphviz**.
* Supported outputs include `json`, `json0`, `xdot_json`, `svg`, `plain`.
* **Use `-Tjson` for LAYOUT, not `-Tsvg`.** The viewer needs hit-testing;
  coordinates give it, an opaque SVG does not. This was already decided in
  `docs\BACKLOG-archify-parity.md` ("Interactivity forks the renderer").
* We never PARSE dot -- dot is Graphviz's INPUT. We emit it and read back JSON.
* Bundling it later is a dependency + EPL-1.0 review; for now it is a local tool
  invoked by path.

## The rendering loop being built

```
index  ->  typed diagram IR  ->  dot  ->  dot -Tjson  ->  coordinates
                             \->  mermaid  ->  HTML shell  ->  browser
```

The viewer half already exists and is NOT built here:
`C:\Projects\Delphi-RAG-Lint-Graph` (standalone Win32/Win64 exe, named-pipe
open-source contract to the IDE, `TPaintBox`/`TCanvas` today).

## Order (from docs\PLAN-archify-ir-workstream.md)

0. HTML shell around the EXISTING `graph --format mermaid` -- hours, ship first.
1. Typed diagram IR + validator -- 1-2 weeks, the keystone, deserves a spec.
2. Emitter: architecture -- 2-3 d.
3. Emitter: sequence (from `callgraph --direction callees`) -- 2-3 d.
4. Renderer: Mermaid in the HTML shell -- 2-3 d (borrow; do not hand-roll SVG).
5. `compare` (before/delta/after) -- 3-5 d.

Excluded on purpose: prose-to-diagram authoring and the `guide` verb. Every node
and edge must be a fact with a file and a line.

## House rules that apply here too

* PowerShell only, never Bash. Wait by BLOCKING, never polling.
* Engine by path: `..\third_party\dll-win64\drag-lint.exe` (1.16.0-alpha seeded
  2026-09-22 until the first local build).
* Self-index only as
  `index --project src\cli\drag-lint.dproj --db src\cli\_D-RAG\drag-lint.sqlite`.
* Strict 7-bit ASCII, CRLF, no BOM in every `.pas` / `.ps1` / `.bat`.
* `scratch\` is throwaway; nothing there is ever committed.
* Commit by explicit pathspec. Never push.
