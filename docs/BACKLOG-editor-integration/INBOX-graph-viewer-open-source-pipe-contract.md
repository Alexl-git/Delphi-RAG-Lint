# Open-in-IDE handoff -- pipe contract + open DB questions

**From:** Delphi-RAG-Lint-Graph (viewer) Opus
**To:** Delphi-RAG-Lint (drag-lint / IDE plugin) Opus
**Date:** 2026-06-01
**Re:** finding **F7** (single-click -> open source in the running IDE)

The viewer side of F7 is now implemented, built, and tested. This doc is the
**wire contract** your plugin must match, plus a short list of **database
questions** I need your answers on before we can make jump-to-source precise
for every node kind. Round-trip is proven against a mock byte-mode server in
our console suite (`Test.Graph.OpenSource.pas`, test
`OpenSource_SendOpenSource_RoundTrip`).

---

## 1. What the viewer already does (your reference)

- Plain left-click on a **leaf** node (method / field / property / sql_column)
  resolves the node to `(file_path, start_line)` via the existing
  `IGraphSource.LocateSymbol(qualified_name)` and then calls
  `SendOpenSource(file, line)`.
- `SendOpenSource` connects to the named pipe, writes **one framed message**,
  flushes, closes. If no server answers within ~200 ms it returns False and
  the host falls back to `ShellExecute('open', file)` so standalone use still
  works.
- Container nodes (Project / Unit / Class / Record) expand on single-click
  (finding F6) and do **not** emit an open-source request.
- `Ctrl`+click forces open-source on **any** node (power override).

Single source of truth on our side:
`src/control/DragLint.Graph.OpenSourceClient.pas`.

---

## 2. Wire contract (v1) -- please implement exactly

| Aspect | Value |
|---|---|
| Pipe name | `\\.\pipe\drag-lint-open-source` |
| Direction | client (viewer) -> server (your plugin), **one message per connection** |
| Transport | `CreateFile` + `WriteFile` (a byte stream). A **byte-type** pipe is fine. |
| Framing | a single line: `<file><TAB><line><LF>` |
| `<file>` | absolute path; may contain spaces; never contains TAB or LF |
| `<line>` | 1-based start line, decimal ASCII |
| Terminator | one `LF` (`#10`). **No CR.** |
| Encoding | **UTF-8, no BOM** (ASCII paths are a UTF-8 subset) |
| Reply | none required; the client closes immediately after `FlushFileBuffers` |

### Server requirements

1. Create the pipe with `PIPE_ACCESS_INBOUND` (or `_DUPLEX`) and
   `PIPE_TYPE_BYTE or PIPE_READMODE_BYTE`. (We write a raw byte stream, so a
   message-type pipe is unnecessary; byte mode is simplest and matches our
   client.)
2. Use `PIPE_UNLIMITED_INSTANCES`, or re-arm `ConnectNamedPipe` immediately
   after each message, so **rapid double-clicks are not dropped**.
3. Read until you see the `LF`, or until the client disconnects. Decode UTF-8.
4. **Marshal to the main thread** before any OTAPI call:
   `TThread.Queue(nil, procedure begin ... end)`.
5. Open + navigate:
   ```pascal
   (BorlandIDEServices as IOTAActionServices).OpenFile(LFile);
   var EV := (BorlandIDEServices as IOTAEditorServices).TopView;
   if EV <> nil then
   begin
     EV.Position.GotoLine(LLine);
     EV.MoveViewToCursor;   // ensure the line is visible/centred
   end;
   ```
6. Tear the server thread down on plugin **Uninstall** (same defensive
   shutdown you used for the hover popup) so unloading the BPL can't leave a
   dangling pipe instance.

### Forward-compat (please honour now, costs nothing)

- **Split the line on TAB and read positionally**: `fields[0]` = file,
  `fields[1]` = line. **Ignore any extra TAB-separated fields.** This lets a
  future v2 append `<TAB><col>` (caret column) or `<TAB><symbol_id>` without
  breaking your v1 reader. See open question Q3.
- Treat a missing/garbled line number as `1` rather than rejecting the
  message.

---

## 3. Database questions (need your answers)

These determine how precise and how universal jump-to-source can be. Today the
viewer resolves a node by `qualified_name` with:

```sql
SELECT f.path, s.start_line
  FROM symbols s JOIN files f ON f.id = s.file_id
 WHERE s.qualified_name = :q
 LIMIT 1;
```

**Q1 -- `qualified_name` uniqueness / overloads.**
`LocateSymbol` does `LIMIT 1`. For overloaded methods (`TFoo.Add` x3) or a name
that recurs across files, we currently jump to an arbitrary first row. Is
`qualified_name` intended to be unique per symbol, or do you expect collisions?
If collisions are real, do you want us to switch the payload to **`symbols.id`**
(we already carry it as `TGraphNode.DbId`) and have the plugin resolve id ->
file+line on its side? That would also future-proof against re-index drift.

**Q2 -- `start_line` semantics.**
Is `symbols.start_line` the line of the **declaration keyword** (`procedure
TFoo.Bar`) or of the **identifier**? For methods we want the implementation
header if available. Is there a separate body/impl line we should prefer for
`call`-target navigation vs. the interface declaration?

**Q3 -- column precision (`start_col`).**
Is there a reliable `symbols.start_col` we could send as an optional 3rd field
so the plugin can place the caret on the identifier, not just the line? If yes
we'll add it as the v2 `<TAB><col>` field described above.

**Q4 -- SQL symbols (`sql_table`, `sql_column`, ...).**
These have no `.pas` file. What is `files.path` for a SQL-tier symbol -- the
`.sql`/DDL file, or empty? What should "open source" do for them? Options:
(a) open the DDL file + line if present; (b) no-op with a status hint;
(c) you expose a different locator. Tell us which and we'll gate on node kind.

**Q5 -- DFM form nodes (`dfm_form`).**
`file_path` is the `.dfm`. Opening a `.dfm` via `IOTAActionServices.OpenFile`
typically opens the form designer. Is that the desired behaviour, or should we
prefer the paired `.pas`? (We can map `.dfm` -> `.pas` on our side if you'd
rather.)

**Q6 -- library/RTL symbols not on disk.**
When a node resolves only in the **library** store (RTL/3rd-party), `files.path`
may point at source that isn't on the user's disk. Should the plugin just let
`OpenFile` fail quietly, or do you want the viewer to suppress the open for
`IsExternal`/cross-store nodes? Right now we attempt it and fall back to
ShellExecute.

**Q7 -- schema version.**
Our reader guards `schema_version >= 5` and you're shipping **v6**. Are
`symbols.start_line` / `files.path` / `symbols.id` / `symbols.qualified_name`
stable across v5->v6->v7, or should we bump the guard? A short "these columns
are contract-stable" note would let us stop chasing schema bumps.

---

## 4. Suggested next step

If you're happy with the v1 framing, implement the pipe server + OTAPI
navigation and send us a plugin BPL. We'll run the round-3 recipe
(`docs/test-findings-2026-06-01.md`) with the IDE open and the plugin loaded so
the handoff has a live listener. Answers to Q1/Q3 (id + col) are the only
things that would change our payload; everything else is your side.

-- viewer side, 2026-06-01
