---
id: v151-mem-rules
title: Memory and string-pointer lint rules (PChar, raw memory, leaks, byte counts)
summary: "Eight memory lint rules, one widened: PChar of Char or temporaries, @S[1], read-only CreateProcess lines, raw memory over managed types, leaks, chars as bytes"
product: DL
group: linting
order: 30054
since: 1.51.0-alpha
status: shipped
updated: 1.52.0-alpha
---

# Memory and string-pointer lint rules (PChar, raw memory, leaks, byte counts)

Eight memory lint rules, one widened: PChar of Char or temporaries, @S[1], read-only CreateProcess lines, raw memory over managed types, leaks, chars as bytes.

Read this to see what each memory and string-pointer rule reports, which ship ON and what keeps them silent.

## How to run it

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>[,<id>...]] [--disable id,...] [--output|--report <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...] [--library-db none] [--no-budget]
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Eight new rules and one widened rule that read one file's parse tree. Declared types come from the
source; record and interface types declared in another unit are looked up in the project / library
index when one is open (`lint --db`, `lint-all`). Every question that cannot be answered completely
stays silent. Run them with `drag-lint lint <file>` or `drag-lint lint-all --db <project.sqlite> --rule <id>`.

| Rule | Default | Reports |
|---|---|---|
| `char-to-pchar` | ON | `PChar(C)` / `PWideChar(W)` / `PAnsiChar(A)` on a variable declared `Char` / `WideChar` / `AnsiChar`: the character code becomes the address. dcc reports nothing for it |
| `first-char-address` | ON | `@S[1]` / `@S[Low(S)]` on a long string (fails for an empty string). ShortString and static arrays are exempt |
| `pchar-of-temporary` | ON | `PChar` of a concatenation with a literal or of a string-function result (IntToStr, Format, ExtractFilePath ...) that is STORED by an assignment or POSTED (PostMessage family). Passed straight to a synchronous call it is silent |
| `createprocess-readonly-commandline` | ON | The command-line argument of CreateProcess(W) / ..AsUser / ..WithTokenW / ..WithLogonW may be read-only: a literal, a const, `'lit' + X`, a by-value / const string parameter, or a local last assigned one of those without `UniqueString`. The Ansi version is exempt |
| `managed-type-raw-memory` | ON | FillChar / ZeroMemory / FillMemory / Move / CopyMemory / GetMem / FreeMem / ReallocMem on a variable or pointee whose type holds strings, interfaces, variants or dynamic arrays (records and static arrays followed). Silent when the routine calls Initialize / Finalize on it, for methods of the same name (TFile.Move), and for `FillChar(V, SizeOf(V))` over a directly managed V (`wrong-size-memory-op` reports that) |
| `raw-memory-leak` | ON | A local receives memory from GetMem / New / AllocMem / GetMemory / StrAlloc / StrNew and is never released (FreeMem, Dispose, StrDispose, ReallocMem(P, 0), a routine named free / release / close ...) nor handed on (assigned elsewhere, returned, passed to Add / Insert / Create / Set.. ...) |
| `handle-leak` | ON | The same for handles: CreateFile, CreateEvent / Mutex / Semaphore, OpenProcess, CreateFileMapping, LoadLibrary, GetDC, CreateCompatibleDC, GDI objects, OpenSCManager, FindFirstFile, RegOpenKeyEx(.., K), FindFirst(.., SR) against their release call |
| `char-count-as-bytes` | ON | `Length(S)` (+/- n) of a UTF-16 string or `StrLen(P)` of a PChar as the byte count of Move / CopyMemory / CompareMem / FillChar / ReadBuffer / WriteBuffer / Read / Write / BlockRead / ReadFile / WriteFile / GetMem(PChar) whose buffer is S / P. Split from `wrong-size-memory-op`: own label, no autofix (the host's fix is capture-bound); the host keeps its exact shapes |
| `unsafe-string-api` (widened) | ON (host) | Also an `xxxA` Windows API fed `PAnsiChar(AnsiString(S))` of a UTF-16 S: characters outside the code page become `?` |

No autofix: every edit would change behaviour in the defect case (the message carries the fix).

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
