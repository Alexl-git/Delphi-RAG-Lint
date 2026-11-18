---
id: v151-sty-rules
title: Style, loop and ordering rules
summary: Eleven style and loop lint rules (begin/end, if-chains, SetLength and repaint in loops, loop bounds, method order); five are on by default
product: DL
group: linting
order: 30058
since: 1.51.0-alpha
status: shipped
updated: 1.51.1-alpha
---

# Style, loop and ordering rules

Eleven style and loop lint rules (begin/end, if-chains, SetLength and repaint in loops, loop bounds, method order); five are on by default.

Read this when you want lint to flag loop and layout habits that cost time or hide bugs. Run `drag-lint lint <unit.pas>` or `lint-all`; the style rules (missing-begin-end, redundant-begin-end, prefer-case, string-if-chain, method-order, processmessages-in-handler) are off by default and are switched on with `--rule <id>` or the enabled list of the lint config. boolean-assign-if has a safe autofix.

## How to run it

```text
drag-lint lint <path> [--profile <name>] [--target-compiler <ver|auto>] [--rule <id>|help] [--disable id1,id2] [--rules-dir <dir>] [--json] [--labels] [--no-preprocess] [--library-db <lib.sqlite>] [--build-config <name>] [--no-budget]
```

Full flag list: [lint in the CLI reference](../cli.md#lint).

## Where to click

No IDE surface: this feature runs from the CLI (see How to run it).

## Details

Eleven lint rules read bracketing, if-chains, loop bodies and method order. They run from
`lint <unit.pas>` and `lint-all`. Five are on by default; the six that state a house style
are off and are chosen with `--rule <id>` or the `enabled` list of the lint config.

### On by default
* **setlength-in-loop** -- `SetLength(A, Length(A) + 1)` inside a for / while / repeat /
  for-in loop copies the whole array on every pass. Size the array once, or grow it in
  larger steps. Reported at the call.
* **processmessages-in-loop** -- `Application.ProcessMessages` inside a loop lets other
  handlers, including the running one, execute mid-loop.
* **missing-begin-update** -- `.Items.Add`, `.Lines.Add`, `.Nodes.Add` (and Strings, Insert,
  Append, AddObject) in a loop repaints the control per item. Skipped when the routine
  already calls `BeginUpdate` or `DisableControls` before the loop.
* **boolean-assign-if** -- `if C then V := True else V := False` (and the negated form) for a
  variable other than `Result` (that spelling is `boolean-result-returned-directly`). Autofix:
  `V := C;` or `V := not (C);`. The edit is behaviour-preserving: the condition is evaluated
  once before and after, and exactly one assignment of a Boolean value happens.
* **loop-off-by-one** -- for-loop bounds one past the valid range: `to High(X) + 1`,
  `to X.Count + 1`, `Low(X) to Length(X)`, and counting down from the count
  (`X.Count downto 0`, `Length(X) downto 0`). The companion `off-by-one-count` covers
  `0 to X.Count`. `Length(S) downto 1` over a string is correct and is not reported.

### Off by default
* **missing-begin-end** -- the body of if / else / for / while / for-in / with is a single
  statement without begin..end. An `else if` link, and a body that is itself begin, try,
  case or asm, are accepted.
* **redundant-begin-end** -- begin..end around one statement in those positions. A then-branch
  of an if..else whose lone statement is itself an if / loop is left alone (dangling else).
* **prefer-case** -- three or more links of an if / else-if chain compare the same plain name
  with ordinal-looking constants. String literals are left to string-if-chain.
* **string-if-chain** -- three or more links compare the same plain name with string literals.
* **method-order** -- method bodies of a class in the implementation section are not in the
  order of the class declaration (one finding per class, at the first body out of place).
  Overloads are paired by occurrence; nested types and a class without a body are skipped.
* **processmessages-in-handler** -- `Application.ProcessMessages` in a routine with a
  `Sender: TObject` parameter and no loop keyword before the call.

### Limits
The chain rules look at chains of at least three links (a longer chain is reported once, at
its head). `method-order` and `processmessages-in-handler` read the source text, not the
parse tree. The measured sample counts per rule are in the REPORT of lane STY.

---

[All features](../index.md) | [CLI reference](../cli.md) | [IDE menus](../ide.md)
