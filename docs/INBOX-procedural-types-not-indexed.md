# INBOX: method-pointer / procedural type declarations are not indexed

**Class:** `unsupported` (extractor gap -- a reindex does not fix it)
**Found:** 2026-08-02, while building "Go to definition" in ConvRulesEditor
**Index:** `C:\Projects\.drag-lint\library-Win64.sqlite` (also absent from the whole-tree DB)
**Exe:** `C:\Projects\Delphi-RAG-lint-converter\third_party\dll-win64\drag-lint.exe`

## Reproducing query

```
drag-lint.exe query --name TNotifyEvent --json --db C:\Projects\.drag-lint\library-Win64.sqlite
```

**Expected:** a row `kind=type` (or `proc_type`), `name=TNotifyEvent`,
`qualified_name=System.Classes.TNotifyEvent`,
`file=...\source\rtl\common\System.Classes.pas`, `start_line=200`.

**Actual:** 10 rows, **none named TNotifyEvent**. Every hit is the substring
`ANotifyEvent` (`kind=local_var` / `kind=param`) from `Abcapp.pas` / `cxClasses.pas`.

## The source that failed to index

`C:\Program Files (x86)\Embarcadero\Studio\37.0\source\rtl\common\System.Classes.pas:200`

```pascal
  TNotifyEvent = procedure(Sender: TObject) of object;
```

## Not a stale index, and not out of scope

`System.Classes.pas` **is** indexed -- `file_id=4644` -- and other declarations in
the same file resolve exactly:

| query | result |
|---|---|
| `--name TAlignment` | `enum` `System.Classes.TAlignment` @ `System.Classes.pas:176` OK |
| `--name TThread` | `class` `System.Classes.TThread` @ `System.Classes.pas:1822` OK |
| `--name TNotifyEvent` | nothing |

So the file is covered and the extractor works on it; the *construct* is what is
being dropped.

## Scope of the gap

Direct SQL against the index (`select kind, qualified_name from symbols where name = ?`):

| name | rows |
|---|---|
| `TNotifyEvent` | 0 |
| `TMouseEvent` | 0 |
| `TKeyPressEvent` | 0 |
| `TThreadMethod` | 0 |
| `TGetStrProc` | 0 |
| `TColor` | 2 (`kind=type`, `Vcl.Graphics` + `Spring.Logging`) |
| `TAlignment` | 3 (`enum` x2, `record` x1) |

Plain type aliases ARE extracted (`kind=type`), and there are 41,830 `type` rows
overall -- so this is specific to the *procedural* / *method-pointer* form
(`X = procedure(...)[ of object];`, `X = function(...): T[ of object];`),
not to type aliases in general.

## Why it matters

Every VCL event property is typed with one of these. In ConvRulesEditor's new
"Go to definition of &lt;T&gt;" a user right-clicking `OnClick : TNotifyEvent` gets
"not in the current index set" for a type that is in plain sight in the RTL
source the index already parsed. The editor handles it (it reports the reason
rather than jumping to the wrong symbol), but the answer is wrong-by-omission.

Related second-order effect: because `--name` is a **substring** match, the
absence is not merely an empty result -- the query cheerfully returns
`ANotifyEvent` local variables instead, so any consumer that takes "the first
hit" navigates to an unrelated local in `Abcapp.pas:322`.

## Suggested check

Whatever grammar node covers `procedure_type` / `function_type` on the RHS of a
type declaration is probably not wired into the symbol emitter. Worth confirming
whether the parse tree contains the node at all, or whether it parses and is then
dropped when choosing a `kind`.
