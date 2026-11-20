# Text rules (`bidi-control`, `invisible-char`, `control-char`, `todo-comment`, `file-header`, `hardcoded-string`)

Rules that read the raw text of a unit (and its sibling `.dfm`), not the parse tree. The three character rules look at the bytes before any decoding.

## Running it
```
drag-lint lint <unit.pas> --db <project.sqlite>
drag-lint lint-all --db <project.sqlite> --rule bidi-control
drag-lint lint <unit.pas> --db <project.sqlite> --enable todo-comment,file-header,hardcoded-string
```

## What it reports
| rule | default | fires on |
|---|---|---|
| `bidi-control` | ON | a bidirectional control character (U+061C, U+200E/F, U+202A-202E, U+2066-2069) in the `.pas` or the text `.dfm`: the code can read differently from how it compiles |
| `invisible-char` | ON | a zero-width or invisible character (soft hyphen, U+200B-200D, U+2060-2064, a second U+FEFF, Hangul fillers) |
| `control-char` | ON | a control character (NUL, U+0001-U+001F except TAB / LF / FF / CR, U+007F-U+009F), a Ctrl-Z that is not the last byte, or an invalid UTF-8 byte in a file that starts with a UTF-8 byte order mark |
| `todo-comment` | OFF | a comment whose text starts with `TODO` or `FIXME` (`//`, `{ }`, `(* *)`, IDE form `{ TODO 1 -oOwner : text }`) |
| `file-header` | OFF | a unit that does not start with the lines of `drag-lint-header.txt` |
| `hardcoded-string` | OFF | a string literal with words for people (two or more words, a space) inside a statement body |

## What it does not report
- Binary `.dfm` files (stream signature `TPF0`) and UTF-16 NULs (the BOM tells the encoding).
- High bytes in a file without a BOM: that is legacy ANSI, not corruption.
- `hardcoded-string`: constants, resourcestrings, `uses ... in` paths, SQL text, paths, markup, format-only strings, strings compared with `=` / `<>`, and arguments of `Assert`, `OutputDebugString`, `Log*`, `Trace*`, `Debug*`. Since 1.52.2 also: logger calls (`CodeSite*`, and any call on a receiver named `Log`, `*Log`, `Logger*`, `CodeSite`, e.g. `FLog.Info(...)`), INI / registry key calls (`ReadString`, `WriteString`, `ReadInteger`, `WriteInteger`, `ReadBool`, `WriteBool`, `ReadSection*`, `EraseSection`, `DeleteKey`, `ValueExists`, `OpenKey` and the other typed `Read*` / `Write*` pairs), option-table calls (`MakeOpt*`, `AddOpt*`, `RegisterOption*`, `DefineOption*`, `NewOpt*`), and every literal of a statement that joins pieces with `+` and holds a SQL piece (one starting `select`, `from`, `where`, ...). Plain literals in UI calls (`ShowMessage`, `Caption:=`, `raise Exception.Create`) still fire.
- `file-header`: no template file means no finding.

## Configuration
`file-header` reads `drag-lint-header.txt`, searched from the unit's folder upwards (10 levels). Trailing blanks on a line are ignored; the file must start with the template lines.

## Fixing it
No autofix: removing a character from a string literal changes the program, and the other rules are advisory. Delete the character in an editor that shows it, or move the text into a resourcestring.
