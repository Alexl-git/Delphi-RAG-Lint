# tools\grammar -- the grammar gate's instruments

Three small C programs that load two builds of a tree-sitter grammar DLL side by side and
compare what they do to real source. They are what the grammar lanes (147 GP, 148 GX, 148 G7,
149 GR) used to prove "0 newly failing files, every changed tree explained" for
`tree-sitter-delphi13` releases; committed here so the next lane does not rebuild them from a
scratch folder.

| Tool | What it does | Output |
|---|---|---|
| `tsdiff oldDll newDll symbol list.txt out.tsv` | parses every file of the list with both DLLs, compares the trees node by node | one row per file: `path  oldErr  newErr  ?  regions`; a region = `row:oldType>newType:dExprIf:dIfElse`; stdout `files= missing= oldFail= newFail= treeDiff=` |
| `tserr oldDll newDll symbol list.txt out.tsv [dump]` | ERROR node count, MISSING count and bytes under the outermost ERROR nodes, old vs new | `path  oErr  nErr  oMiss  nMiss  oBytes  nBytes`; with a 6th argument every outermost ERROR (rows, bytes) is printed to stdout, prefixed `1` (old) / `2` (new) |
| `tsparse dll symbol file [fromRow toRow]` | S-expression dump of one file's tree with row:column spans and leaf text, optionally restricted to a row range | stdout, last line `ERRORS_IN_RANGE=n` |
| `tsblank run dll symbol list.txt out.tsv` | parses every file twice with ONE DLL: as is, and with every comment blanked to same-length spaces (line breaks kept, `{$..}` / `(*$..*)` directives never blanked); compares ERROR / MISSING counts and the comment-free trees | one row per file: `path oErr bErr oMiss bMiss oBytes bBytes oHas bHas treeSame class firstErr` (class = clean / comment / ifdef / gap / mixed / worse); stdout `files= oFail= bFail= newlyClean= improved= same= worse= treeDiffClean=` |
| `tsblank blank in.pas out.pas` / `tsblank comments in.pas` | writes the blanked copy (byte length identical) / prints the comment side table `start end row col kind text` | file / stdout TSV |

`run_tsblank_selfcheck.ps1 -Tsblank <exe> [-PositiveControl]` checks the blanker's properties on
`fixtures\blank\sample.pas` (same length, line breaks and directives in place, strings untouched,
every comment gone); `-PositiveControl` feeds the unblanked file and must FAIL. Wave 150 lane W1
measured mode (a) comment blanking with it (lanes\150\W1\REPORT.md).

`symbol` is the language entry point: `tree_sitter_delphi13` (root grammar) or
`tree_sitter_delphi13_pure`. `list.txt` holds one absolute path per line (CRLF or LF).

## Build

```
tools\grammar\build-grammar-tools.bat [grammar-checkout] [out-dir]
```

`cl.exe` x64 through `build\_vsenv.bat`; the tree-sitter runtime (`lib.c`) comes from the
grammar checkout's `node_modules\tree-sitter\vendor\tree-sitter\lib` (default checkout
`C:\Projects\tree-sitter-delphi13`). Output defaults to `tools\grammar\bin\` (gitignored).
From a lane: pass the lane's scratch folder as `out-dir`; never build into the main tree.

## The gate (what a grammar lane runs)

1. Build the BASE DLLs (x64 root + pure) from the released `src\` before editing `grammar.js`.
2. `tree-sitter test` on the OLD `src\` with the NEW corpus files: the new cases must fail (RED).
3. `tree-sitter generate` (root and `pure\`; HEAVY, minutes), then `cl` x64 and x86 DLLs.
4. `tree-sitter test` root and pure: only the documented pp_block failures remain.
5. `tsdiff base new` over the positive-control files, the 533-file sample and the 8286-file
   corpus, both grammars: `newFail` rows with `oldErr=0 newErr=1` must be 0.
6. `tserr` over every changed file: a changed tree is explained when the file fails on both
   grammars (an error-recovery shift) or is one of the fixes.

`gate-grammar.ps1` runs steps 3-6 for one grammar worktree; see its header. The gate reads
DLLs only -- it never touches `third_party\` or the deployed engine.
