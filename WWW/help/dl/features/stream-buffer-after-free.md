---
id: stream-buffer-after-free
title: Stream buffer used after free (lint rule)
summary: "Lint rule, OFF by default: a pointer into a memory stream buffer is used after the stream was freed"
product: DL
group: linting
order: 30031
since: 1.42.0-alpha
status: shipped
updated: 1.42.0-alpha
---

# Stream buffer used after free (lint rule)

Lint rule, OFF by default: a pointer into a memory stream buffer is used after the stream was freed.

Read this to see which pointer and free shapes stream-buffer-after-free follows, and why a TBytes copy of S.Bytes stays silent. Works per file, with or without an index.

## How to run it

```text
drag-lint lint-all [--profile <name>] [--target-compiler <ver|auto>] [--db <file.sqlite>] [--project <.dproj>] [--build-config <name>] [--rule <id>] [--disable id,...] [--output <report.txt>] [--json] [--labels] [--quiet] [--lint-third-party] [--no-preprocess] [--shared-db <db> ...]
```

Example:

```text
drag-lint lint-all --db <project.sqlite> --rule stream-buffer-after-free
```

Full flag list: [lint-all in the CLI reference](../cli.md#lint-all).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

A pointer into a memory stream's buffer is used after the stream was freed. The memory went with the stream, so the pointer dangles. OFF by default.

```pascal
S := TMemoryStream.Create;
try
  P := S.Memory;
finally
  S.Free;
end;
Consume(P); // finding
```

### Running it
```text
drag-lint lint <file> --rule stream-buffer-after-free
drag-lint lint-all --db <project.sqlite> --rule stream-buffer-after-free
```
To keep it on, add it to `"enabled"` in `drag-lint-lint.json`.

### What it recognises
- The stream: a local typed `TMemoryStream`, `TBytesStream`, `TStringStream`, `TCustomMemoryStream` or `TResourceStream`, or a class the index knows descends from `TCustomMemoryStream`.
- The pointer: a local typed `Pointer` or `P<Name>`, or an inline `var`, assigned `S.Memory`, `@S.Bytes[n]` or `Pointer(S.Bytes)`, through casts and pointer arithmetic.
- The free: `S.Free`, `S.Destroy` or `FreeAndNil(S)`, in the routine's main line or a `finally`.

### What stays silent
- A `TBytes` copy of `S.Bytes`. A dynamic array is reference-counted, so it outlives the stream. This is why the old "dangling TBytes" candidate became a rule about pointers.
- A free inside `if`, `case`, a loop, `with` or `except`: it may not have run when the use is reached.
- A pointer assigned again between the free and the use.
- A field or a parameter: the rule follows locals only.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
