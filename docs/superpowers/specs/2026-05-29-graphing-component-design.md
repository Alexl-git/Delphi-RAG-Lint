# Graphing Component (Parked Design)

**Date:** 2026-05-29
**Status:** Parked design — pending user go-ahead (post v0.40 LSP-completion work)
**Intended Versions:** v0.41 (HTTP dashboard) + v0.42 (TDragLintGraphControl)

## 1. Goal

Build a visual graph component for drag-lint that's both:
- A *standalone* interactive dashboard reachable via `drag-lint serve --http :8080`
- A *reusable* Delphi VCL control (`TDragLintGraphControl`) any Delphi app can drop into a TForm
- A *standalone* viewer `drag-lint-graph.exe` for non-Delphi consumers

All three use the same internal HTML/JS rendering layer (Cytoscape.js or vis-network) but expose it via different shells.

The motivation: match the visual UX of `Lum1104/Understand-Anything` without their LLM dependency, polyglot scope, or privacy compromises. Native Delphi integration + zero outbound + reusable control = three differentiators they can't match.

## 2. Architecture

```
+---------------------------------------------------+
|  drag-lint.exe                                    |
|                                                   |
|  +-----------------+    +----------------------+  |
|  | serve --http    |    | graph-html resources |  |
|  | :8080           +--->| (HTML + Cytoscape.js |  |
|  |                 |    | + d3, embedded as    |  |
|  +-------^---------+    | string consts)       |  |
|          |              +----------------------+  |
|          |                                        |
|  SQLite index (symbols, refs, files, docs, etc.)  |
+----------|----------------------------------------+
           |
           v
+----------+----------------------------------------+
|  Web browser (any) at http://localhost:8080       |
|   - Pages: Graph, Diagnostics, Callers, Docs      |
|   - Cytoscape.js force-directed layout            |
|   - Click handlers POST back to /api/event        |
+---------------------------------------------------+

       +----- alternative front door ------+
       v                                   v
+-----------------+              +------------------+
| drag-lint-graph |              | TDragLintGraph   |
| .exe            |              | Control (VCL)    |
|                 |              |                  |
| TForm hosting   |              | TWinControl with |
| TDragLintGraph  |              | TEdgeBrowser     |
| Control         |              | child            |
+-----------------+              +------------------+
```

## 3. Front-end stack

**Choice: Cytoscape.js (preferred) or vis-network**

| Lib | Size | Force layout | Custom styling | Event API | Verdict |
|---|---|---|---|---|---|
| Cytoscape.js | ~200 KB | Yes (cose-bilkent extension) | Excellent CSS-like selectors | Rich (tap/dblclick/right-click) | **Pick this** |
| vis-network | ~150 KB | Yes (Barnes-Hut) | Per-node styling | Click + drag | Solid alternative |
| sigma.js | ~80 KB | Limited | Programmatic | Sparse | Too thin |
| d3-force | ~30 KB | Yes | DIY everything | DIY | Too much glue |

Bundle Cytoscape.js + its layout extension as a single `assets/graph.html` resource. Embed in the drag-lint binary as a string constant via `{$R}` directive on a generated `.rc` file, OR ship as a sibling file `assets/graph.html` loaded at runtime.

## 4. HTTP API (`drag-lint serve --http :PORT`)

| Endpoint | Returns | Notes |
|---|---|---|
| `GET /` | The dashboard HTML | All pages SPA-routed client-side |
| `GET /api/graph/symbols?file=X` | JSON nodes + edges for file X | `{nodes: [{id, label, kind, ...}], edges: [{src, dst, kind}]}` |
| `GET /api/graph/project` | Whole-project unit graph | Aggregated by unit |
| `GET /api/diagnostics?file=X` | Lint + compiler findings | Same shape as LSP publishDiagnostics |
| `GET /api/callers?qname=X` | Caller list with file:line | From `find-callers` |
| `GET /api/doc?qname=X` | Structured doc record | From `get_symbol_doc` |
| `POST /api/event` | Acknowledges UI events | For analytics / future server-side actions |

Implemented via Indy `TIdHTTPServer` (FireDAC's HTTP server is heavier than needed).

## 5. JavaScript ↔ Delphi message protocol

Inside `graph.html`, click handlers POST JSON to `/api/event`:

```javascript
cy.on('tap', 'node', function(evt) {
  const node = evt.target;
  fetch('/api/event', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({
      type: 'node-click',
      nodeId: node.id(),
      symbolKind: node.data('kind'),
      modifiers: { ctrl: evt.originalEvent.ctrlKey, shift: evt.originalEvent.shiftKey }
    })
  });
});
```

In `TDragLintGraphControl` (VCL embedded):
- Use `TEdgeBrowser.OnWebMessageReceived` for in-process messages (faster than HTTP round-trip)
- Same JSON shape, just `window.chrome.webview.postMessage(JSON.stringify(...))` from the JS side

## 6. TDragLintGraphControl (VCL component)

```pascal
unit DragLint.Graph.Control;

interface

uses
  System.Classes, System.SysUtils, System.JSON,
  Vcl.Controls, Vcl.Edge,
  Winapi.WebView2;

type
  TGraphNodeClickEvent = procedure(Sender: TObject;
    const ANodeId, ASymbolKind: string;
    ACtrl, AShift: Boolean) of object;

  TGraphEdgeClickEvent = procedure(Sender: TObject;
    const ASrc, ADst, AKind: string) of object;

  TDragLintGraphControl = class(TWinControl)
  strict private
    FBrowser:      TEdgeBrowser;
    FOnNodeClick:  TGraphNodeClickEvent;
    FOnEdgeClick:  TGraphEdgeClickEvent;
    FOnReady:      TNotifyEvent;
    FDataPending:  string;  // queued LoadGraph call before browser ready
    procedure HandleNavigationCompleted(Sender: TCustomEdgeBrowser;
      IsSuccess: Boolean; WebErrorStatus: COREWEBVIEW2_WEB_ERROR_STATUS);
    procedure HandleWebMessageReceived(Sender: TCustomEdgeBrowser;
      Args: TCoreWebView2WebMessageReceivedEventArgs);
    procedure InitializeBrowser;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadGraph(const ANodes, AEdges: TJSONArray); overload;
    procedure LoadGraph(const ANodesJsonStr, AEdgesJsonStr: string); overload;
    procedure HighlightNode(const ANodeId: string);
    procedure FitToWindow;
    procedure ExportPng(const APath: string);
  published
    property OnNodeClick: TGraphNodeClickEvent
      read FOnNodeClick write FOnNodeClick;
    property OnEdgeClick: TGraphEdgeClickEvent
      read FOnEdgeClick write FOnEdgeClick;
    property OnReady: TNotifyEvent read FOnReady write FOnReady;
    property Align;
    property AlignWithMargins;
    property Anchors;
    // ... standard TWinControl properties ...
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('drag-lint', [TDragLintGraphControl]);
end;
```

The HTML template is embedded as a resource string. When `Create` runs, the browser's `NavigateToString` loads it. JavaScript posts back through `window.chrome.webview.postMessage`, which fires `OnWebMessageReceived`, which parses JSON and dispatches the typed event.

Two-line example app:

```pascal
GraphCtrl.LoadGraph(MyNodes, MyEdges);
GraphCtrl.OnNodeClick := procedure(Sender: TObject;
  const NodeId, Kind: string; Ctrl, Shift: Boolean)
begin
  ShowMessage('Clicked ' + NodeId);
end;
```

## 7. drag-lint-graph.exe (standalone viewer)

`src/cli/drag-lint-graph.dpr` — a tiny TForm hosting `TDragLintGraphControl` set to `alClient`. Reads graph data from `--data <path.json>` or stdin (JSON). The form is just:

```pascal
program drag_lint_graph;
{$APPTYPE GUI}
uses Vcl.Forms, MainForm in 'MainForm.pas' {Form1};
begin
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
```

Where `MainForm` parses `ParamStr` for `--data`, loads the JSON, calls `LoadGraph`.

## 8. Integration into drag-lint Delphi IDE plugin

Two new menu entries:
- `Tools → drag-lint → Open Web Dashboard` — spawns `drag-lint serve --http :8088` in background + `ShellExecute('open', 'http://localhost:8088')`
- `Tools → drag-lint → Show Project Graph` — opens a dockable form with `TDragLintGraphControl` filling client area, calls `LoadGraph` with project data

## 9. Distribution

**Standalone package for non-Delphi users:**

```
drag-lint-graph-v0.42.0-alpha-win32.zip:
  drag-lint-graph.exe
  drag-lint.exe              (for index/data backend)
  tree-sitter.dll
  tree-sitter-delphi13.dll
  tree-sitter-dfm.dll
  assets/graph.html          (Cytoscape.js bundled)
  README.md
```

**Delphi component for app integrators:**

Add to existing repo under `src/graph/` as a Delphi package (`DragLintGraphPkg.dpk`). Documented usage:

```pascal
uses DragLint.Graph.Control;
// drop a TDragLintGraphControl on your form, call LoadGraph
```

## 10. Engineering scope

- v0.41 dashboard (HTTP + HTML/JS): ~1.5 sessions (6 hours)
- v0.42 VCL control + standalone exe: ~1.5 sessions (6 hours)
- Total: ~3 sessions for both

Each ships its own GitHub release + tag.

## 11. Open design questions (for user decision before kickoff)

1. Cytoscape.js vs vis-network — recommend Cytoscape.js for richer styling
2. Embed HTML/JS as resource string vs ship as sibling file `assets/graph.html` — recommend embed for single-file distribution
3. Whether to also support Chromium-via-CEF4Delphi as fallback for users without WebView2 — recommend deferring; WebView2 is on Win10/11 by default since 2022
4. Whether the standalone EXE should also embed an HTTP server, or just load file directly — recommend file-load for the EXE (no port conflicts)

## 12. After-design checklist (for future implementer)

- [ ] WebView2 runtime presence check on plugin startup; show install hint if missing
- [ ] Localhost-only HTTP binding for security (`127.0.0.1` not `0.0.0.0`)
- [ ] CSRF token for `POST /api/event` (paranoid, low cost)
- [ ] Test on a Micronite-scale graph (~44k nodes) — verify Cytoscape cose-bilkent doesn't OOM the browser
- [ ] Auto-fit on first paint
- [ ] Keyboard shortcuts for fit / search / pan
- [ ] Dark mode (read from IDE theme via OTAPI for the embedded case)
