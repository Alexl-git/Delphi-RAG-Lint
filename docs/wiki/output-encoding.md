# output-encoding

Chooses the bytes drag-lint writes to **stdout and stderr**, on every verb.
Owner ruling 2026-10-26: Unicode output is allowed by a user option; the
**default stays 7-bit ASCII**.

## The modes

| Value | Bytes on the pipe | Non-ASCII text |
|---|---|---|
| `ascii` (default) | 7-bit ASCII | each UTF-16 code unit as `\uXXXX`, lower-case hex; outside the BMP, its surrogate pair (U+1F600 is `\ud83d\ude00`) |
| `utf8` | UTF-8, no BOM | raw |
| `utf16` | UTF-16LE, no BOM | raw |

```
drag-lint sql --query "select path from files" --db <db> --json                        # ascii
drag-lint sql --query "select path from files" --db <db> --json --output-encoding utf8
```

Or once, for every run under a folder, in `.drag-lint.json`:

```json
{ "outputEncoding": "utf8" }
```

The command line wins over the file. Any other value is an argument error
(exit 3). `utf-8` and `utf-16` are accepted spellings.

## Why ascii is safe to parse

Inside `--json` the `\uXXXX` form **is** the JSON string escape, and a literal
backslash is already written `\\`, so any JSON reader recovers the exact text
-- whatever code page the reader decodes the bytes with. In text output the
same escape is used; it is reversible unless the original text itself held a
backslash, `u` and four hex digits. Use `utf8` when a text consumer needs the
exact characters.

Output that is plain ASCII is byte-for-byte what it was before this option
existed, so the readers that decode the engine with the ANSI code page (the IDE
plugin, the convrules editor) and the one that decodes UTF-8 (the language
server's `lint --json` child) all read it unchanged.

## What it covers

* `Output` and `ErrOutput` of every verb, including progress and banner lines.
* `index --all --jobs N` passes the mode to its child processes, which write to
  the same pipe.
* The LSP control channel's stderr lines.

Not covered: generated source (a
converted `.pas` / `.dfm` keeps the encoding the converter chooses), and the
LSP / MCP JSON-RPC transport, which is UTF-8 by protocol.

## Non-ANSI paths in the index

Before 2026-10-26 a path character outside the ANSI code page was stored as `?`
-- the index writers bound text with FireDAC's ANSI `AsString`. Every string
parameter is now bound as UTF-16, so `C:\src\caf\u00e9_\u0434\Unit1.pas` (written
here in the ascii escape) is stored and answered intact.

Guard: `tests\autotest\run_output_encoding.ps1`.

## Files a verb writes, and the lossy-output warning

`--output` files and reports follow `--output-encoding` exactly like stdout: ascii writes `\uXXXX`,
utf8 / utf16 write raw bytes, never a BOM. When an ascii run turns non-ASCII characters into
escapes it prints one stderr warning with the count and the two ways to switch
(`--output-encoding utf8`, or `"outputEncoding": "utf8"` in `.drag-lint.json`). A JSON file written
with `--output` also gets a leading `"lossy_output": N`; stdout JSON does not (it streams before the
total is known). A pure-ASCII run prints no warning.
