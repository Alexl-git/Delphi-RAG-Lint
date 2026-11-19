# Compiler messages in drag-lint

drag-lint tracks and passes through every message the Delphi compiler (dcc) reports: errors, warnings and hints,
under their own codes (H2164, W1036, E2003 ...). The severity comes from the code letter (H = hint, W = warning,
E / F = error), because msbuild prints "Hint warning H2219" with a misleading severity word.

## Where the messages come from and where they show up

| Step | What happens |
|---|---|
| Collecting | `index --project X.dproj --recompile`, `refresh-findings --project X.dproj [--full]` (stale units only, a full build from two stale units on; `--full` forces it), the MCP tool `run_compile_check` (a .pas or .dproj, stores into the DB when `db` is given) and the IDE actions Full Compile Sweep and Compile Buffer. Every H / W / E / F line is stored in the project DB table `compiler_findings`. |
| Reading | `drag-lint query hints --db <db> [--name <code>] [--rule <severity>]` lists the stored messages. |
| Editor | The drag-lint LSP server publishes the stored messages with `source: "dcc"` and the compiler code, next to its own findings. In front of DelphiLSP, `lsp --proxy --merge-diagnostics` appends the lint findings to DelphiLSP's own `publishDiagnostics` (fail open: on any error DelphiLSP's bytes are forwarded unchanged). See `lsp-proxy-merge`. |
| Fixes keyed to a code | The IDE quick fix for H2443 (inline routine whose unit is not in scope) adds the unit; `uses-fix` verifies a uses cleanup with the compiler. |
| Compile gate | `lint --fix --apply --project X.dproj` builds before and after the write (default since 1.51), keeps every message of build 1, rolls back on an error in build 2 and reports the warnings and hints the fix added. See `lint-fix-compile-gate`. |

A compiler message is data from the build. It exists only after a build, and only for what the build compiled.

## Rules that overlap a compiler message stay rules

A drag-lint rule that covers the same ground as a compiler message is not dropped: it is our own analysis, it
runs without a build (on one file, on an unsaved buffer, in an editor without dcc) and it goes further where noted.
The compiler message stays available beside it. Only where the compiler's message and a would-be new rule were
exactly the same construct was the rule refused (next section).

What each rule does beyond the compiler message. Only claims checked against the rule's source are listed; where
the detection is the same, the table says so.

| Rule | Related message | Where the rule goes beyond it |
|---|---|---|
| `unused-local` | H2164 variable declared but never used | Same detection (a name that occurs only at its declaration), and it prints the H2164 text. The difference is availability: no build is needed, and `--fix` can remove the variable. |
| `write-only-local` | H2077 value assigned never used | Data-flow based: a local assigned and read nowhere, captured locals excluded. Its sibling `dead-store-before-out-arg` (OFF by default) uses a liveness solve to find stores overwritten through an out argument before any read. |
| `used-before-assignment` | W1036 variable might not have been initialized | Path-sensitive must / may analysis over the control-flow graph: a definite use is an error, a possible one a warning, and a guard that looks like a witness flag is reported as POSSIBLE with the flag named. Related: `not-assigned-interface` (interface dereferences), `by-value-arg-before-assignment`. |
| `function-result-not-set` | W1035 return value might be undefined | Same must / may analysis: "never assigned" is a warning, "not on every path" an info. Paths that end in `raise`, `Halt` or `Abort` are left out, and Try-named functions are exempt. The sibling `out-param-not-set` applies the same analysis to out parameters. |
| `hides-ancestor-virtual` | W1010 method hides virtual method of base type | Looks at ancestors in the same file and, through the index, in other units. The new id `component-create-without-override` was refused as an exact duplicate (below). |
| `unused-private-member` | H2219 private symbol declared but never used | Project-wide, from the index's reference table (fields with no reads and no writes), including references from other units. |
| `deprecated-rtl-function` | W1000 symbol is deprecated | Not an attribute check: it matches a curated list of obsolete RTL routines by pattern, with a `--fix` for some of them. |

## Refused as exact duplicates, and the conditional one

| Candidate | Verdict |
|---|---|
| `implicit-package-import` | Refused as a rule: exactly dcc W1033, and it needs the unit list of binary .dcp packages that no source index has. Covered by the pass-through. |
| `component-create-without-override` | Refused as a new id: exactly dcc W1010 and already `hides-ancestor-virtual`; the component lane adds a fixture that proves the existing rule covers `constructor Create(AOwner: TComponent)` without override. |
| `debug-display-placeholder` | Not a compiler message (dcc never checks a DebuggerDisplay template). Built in 1.52 (lane BK-ATTRRULES) on the attributes index fact, default OFF: [v152-attrrules](v152-attrrules). |
| `noreturn-returns` (W1080, lane OO) | Conditional: the lane compiles its RED fixture with dcc first; if dcc already reports the construct (W1080), it is a compiler message and is not added as a rule. |

The rule of thumb: a NEW rule is not added when dcc reports that exact construct; an EXISTING rule is never removed
because dcc also reports it.

## Quick reference
```
drag-lint refresh-findings --project <X.dproj> [--db <db>] [--full] [--json]
drag-lint query hints --db <db> [--name <code>] [--rule <severity>]
drag-lint lsp --proxy --merge-diagnostics
```
