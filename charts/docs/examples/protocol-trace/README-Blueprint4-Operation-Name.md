# Blueprint4 "Operation Name" -- protocol-trace, made by the engine

Generated 2026-09-24 from the frozen clones (extractor 1.19.0 / resolver 1.8.0).
Nothing in any bundle below was written by hand or by a model. Each bundle's
`meta.json` carries the exact `regenerate` command; rerun it, never edit output.

> **Note (2026-10-06):** the chart folders beside this README were generated on 2026-09-24, before feeds-from and
> lands-where followed the runtime re-point. Regenerate them with the commands below to see the current charts.

## What "the Operation Name field" is, in the index

| step | fact | evidence |
|---|---|---|
| grid column | `dxDBGrid1OperationVName : TcxGridDBColumn`, `DataBinding.FieldName = 'Name'` | `CLIENT\Blueprint4.dfm:4533-4534` |
| designer datasource | `Blueprint4_Model.dsrOperation` -- **dangling**: no `Blueprint4_Model` exists in the project | `Blueprint4.dfm:4497` |
| runtime datasource | `DataController.DataSource := FBlueprint_ViewModel.pdsrOperation` | `Blueprint4.pas:2282` (FormShow) |
| dataset | `FMTOperation : TFDMemTable`, table `OPERAT` | `Blueprint4.ViewModel.pas:78`, `:769` |
| no `TField` for `Name` | the view model wraps ID, CMMType, CMMMultiplier, FileName -- not Name | `Blueprint4.ViewModel.pas:257-260` |
| **inbound wire** | `LoadOneTable` sends `cmdTableLoad`, expects `rspData` | `Blueprint4.ViewModel.pas:1123` |
| **outbound wire** | AfterPost -> `DoAfterPostOperation` -> `SendDeltaOperation`: `cmdDelta` out, `rspOK` back | `:639`, `:3948`, `:3960` |

**A dataset column is not a symbol**, so protocol-trace cannot select `Name`
directly. It selects a constant, a wire field or a method. The two METHODS
that put an Operation Name value on the pipe are the honest selections, so the
trace is run on both. (A field-mode trace on `FMTOperation` was considered and
rejected: 120 of its 121 refs are unbound in-class reads, a known engine gap --
`docs\INBOX-in-class-field-reads-unbound.md` -- and that chart would silently
show 1 reference.)

## The bundles in this folder

| folder | question | what it answers |
|---|---|---|
| `protocol-trace-...SendDeltaOperation` | protocol-trace | edits leave as `cmdDelta`, answered by `rspOK` |
| `protocol-trace-...LoadOneTable` | protocol-trace | rows arrive via `cmdTableLoad`, answered by `rspData` |
| `crosses-boundary-...SendDeltaOperation` | crosses-boundary | VERDICT crosses; transport `TPipeClientConnection.ExecuteCommand`; 18 SERVER routines, incl. `TGenericTableRoute.HandleDelta` |
| `crosses-boundary-...LoadOneTable` | crosses-boundary | VERDICT crosses; 17 SERVER routines |
| `feeds-from-frmBlueprint4_dxDBGrid1OperationVName` | feeds-from | column -> dangling designer datasource -> the runtime re-point (`pdsrOperation`, followed since 2026-10-06) -> `FMTOperation` -> `OPERAT.NAME` |
| `lands-where-frmBlueprint4_dxDBGrid1OperationVName` | lands-where | follows the same re-point to `OPERAT.NAME` and on to the server (`TDataService_OPERAT_SERVER`) |

The far side of crosses-boundary is joined by COMMAND NAME across two indexes,
so `rspOK` pulls in every server routine that answers OK -- the chart says so.

## Against the golden (`charts\fixtures\golden-operat-name-roundtrip.md`)

The golden is the stated acceptance target for protocol-trace on exactly this
field: 17 nodes, both directions, 3 guards, the failure edge, and the
client -> pipe -> server -> Firebird crossing. **What the engine produces today
does not meet it:**

| golden requires | produced |
|---|---|
| 17 nodes with file:line | protocol-trace: 2 (nodes 5, 15) + their 4 constants; crosses-boundary adds node 8 among 18 name-joined candidates |
| both directions | yes -- but as two separate charts |
| guards (`FSuppressEvents`, `ChangeCount`, `FConn.Connected`) | none |
| failure edge (`CancelUpdates`) | none |
| grid -> memtable -> `OPERAT.NAME` | yes, since 2026-10-06: feeds-from/lands-where follow the runtime right-hand side (`pdsrOperation`) past the dangling designer datasource. The `round-trip` question draws the whole path as one chart (R5) |

## Where the text and the graphics come from

* **Graphics:** each emitter (`charts\src\Emit-<Question>.ps1`) writes Graphviz
  `graph.dot` from index queries; `dot.exe` lays it out ONCE into `graph.svg`,
  `graph.plain` (geometry from the same run), `graph.png` and `graph.pdf`.
* **Text on the chart:** the focus box's grey rows are the emitter's disclosure
  rows (`Add-DisclosureRow`) -- counts, caveats and engine-risk notes computed
  in that run. Row labels and `:line` numbers are index facts.
* **Text around the chart:** `index.html` is the shell `New-DiagramArtifact.ps1`
  builds around the SVG: the header counts come from the emitter's result
  (the per-question pair, e.g. references/zones), and `meta.json` records every
  count, the index fingerprint (path, size, mtime) and the regenerate command.
  `xref.txt` is the DocInsight `<remarks>` block to paste into the unit.

## Doing this from the IDE

There is no chart command in the IDE plugin today (its only graph surface is
the butterfly Call Graph tab). The working path:

1. **Generate** outside the IDE -- or from a `Tools > Configure Tools` entry that
   runs `pwsh -File <repo>\charts\src\New-DiagramArtifact.ps1 -Question
   protocol-trace -Target <qualified method> -DbPath <clone> -Open`
   (not set up on this machine).
2. **Navigate back:** every row in the SVG is a `draglint://open?file=..&line=..`
   link. Run `charts\src\Register-DragLintProtocol.ps1` once (HKCU, no
   elevation); a click then reaches the plugin's pipe server
   (`DragLint.Plugin.OpenSourceServer.pas`, `\\.\pipe\drag-lint-open-source`)
   and the IDE opens the file at the line.
3. **Reference it in code:** paste `xref.txt` into the routine's doc comment. It
   names a stable path, so regenerating the chart never rewrites the comment.

## Regenerate

```
cd <repo>\charts
.\src\New-DiagramArtifact.ps1 -Question protocol-trace -Target Blueprint4.ViewModel.TBlueprint_ViewModel.SendDeltaOperation -DbPath <abs>\scratch\db\CLIENT-Micronite2027.sqlite -OutRoot <abs>\docs\examples\protocol-trace
.\src\New-DiagramArtifact.ps1 -Question protocol-trace -Target Blueprint4.ViewModel.TBlueprint_ViewModel.LoadOneTable      -DbPath <same> -OutRoot <same>
```

The others: see each bundle's `meta.json` -> `regenerate`.
