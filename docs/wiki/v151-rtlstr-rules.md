# RTL string and path rules (v151 lane RTL-STR)

Seven lint rules for mistakes in the everyday string, path and conversion routines of the RTL. All of them are
external tree-sitter rules (`rules\<id>.scm` + `.json`), so they need no engine change, show up in
`drag-lint rules --json`, and are switched with `--rule <id>`, `--disable <id>` or `"enabled"` in the config.

| Rule | Category | Default | What it finds |
|---|---|---|---|
| `pos-arguments-swapped` | bug-patterns | see the report | `Pos`, `PosEx`, `AnsiPos`, `StartsText/-Str`, `EndsText/-Str` (also the Ansi spellings) with a string literal as the text to search and a variable as the searched part, e.g. `Pos(Zeile, ';')`. A one-character literal always fires; a longer literal only when the first argument is a declared string (`Pos(Ch, 'aeiou')` stays quiet). |
| `delimited-text-without-strict` | bug-patterns | see the report | `List.Delimiter := ...` followed by `List.DelimitedText := ...` in one routine that never mentions `StrictDelimiter`: the list then also splits at blanks. The finding sits on the routine. |
| `global-formatsettings-modified` | bug-patterns | see the report | Assignment to the process-wide `FormatSettings.<field>` or to a deprecated global format variable (`DecimalSeparator`, `ShortDateFormat`, ...). Use a local `TFormatSettings`. |
| `path-concat-without-delimiter` | bug-patterns | see the report | A folder from `ExtractFileDir`, `ExcludeTrailingPathDelimiter` or a `TPath.Get...Path` folder joined with `+` to a literal that does not start with a delimiter, directly or through a local assigned earlier. |
| `filename-compare-case` | bug-patterns | see the report | `=` / `<>` where one side is the result of `ExtractFileName`, `ExtractFilePath`, `ExtractFileDir`, `ExtractFileExt`, `ExpandFileName` or a `TPath.Get...` name routine. Comparison with `''` is exempt. |
| `unchecked-conversion` | bug-patterns | OFF | `StrToInt`, `StrToInt64`, `StrToFloat`, `StrToCurr`, `StrToDate`, `StrToDateTime`, `StrToTime` with one argument that is a control's `.Text`, a `Cells[..]` / `Lines[..]` / `Strings[..]` entry or `ParamStr(..)`, outside any `try`. Opt-in because legacy form code validates elsewhere. |
| `string-index-base` | bug-patterns | see the report | `Copy`/`Delete` with the literal index `0`, `Insert(.., .., 0)`, and `Pos(..)` compared with `-1` (Pos returns 0 for "not found"). Complements `constant-index-out-of-range`, which covers `S[0]`. |

No rule has an autofix: each cure changes what the code does in the defective case, so the message names the cure
and the call site decides.

## Examples

```pascal
if Pos(Zeile, ';') > 0 then ...           // pos-arguments-swapped: searches Zeile inside ';'
Teile.Delimiter := ';';
Teile.DelimitedText := Zeile;              // delimited-text-without-strict: blanks split too
FormatSettings.DecimalSeparator := '.';    // global-formatsettings-modified
Datei := ExtractFileDir(P) + 'export.csv'; // path-concat-without-delimiter
if ExtractFileName(F) = 'Config.ini' then  // filename-compare-case
Menge := StrToInt(edtMenge.Text);          // unchecked-conversion (opt-in)
S2 := Copy(S, 0, 3);                       // string-index-base
```

Fixtures: `tests\lint\<rule-id>.pas` with a sibling `.expected`.
