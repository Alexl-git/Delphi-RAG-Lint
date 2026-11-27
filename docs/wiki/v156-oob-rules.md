# Class and literal hygiene rules (lane OO-B, 1.56)

Four checks (the first two read the project index). `field-could-be-local` and `repeated-string-literal` are OFF by default: name
them with `--rule` or enable them in the lint config. variant-in-loop is OFF too; dunitx-attribute-hygiene is ON.

```
drag-lint lint <unit.pas> --rule field-could-be-local --db <project.sqlite>
drag-lint lint-all --db <project.sqlite> --rule repeated-string-literal
```

## field-could-be-local (hint, bug-patterns, OFF)

A `private` or `strict private` field of a class that is used inside ONE routine of its own unit and is written before it
is first read there. The value never outlives the call, so a local variable does the same job and removes hidden state.
Reported at the field declaration.

Silent when the rule cannot prove that: the field is used in a second routine; a use sits outside any routine (a property
accessor, `initialization`); the first use is a read (a cache: `if FX = 0 then FX := ...`); the field carries an attribute;
the routine contains an anonymous method; another class of the unit reaches the field through a qualified name; the field
is published, public or protected. Not judged: a write on one branch followed by a read after the branch (the rule
looks at source order only).

## repeated-string-literal (hint, project-wide, OFF)

The same string literal of 9 or more characters typed at 5 or more sites of the project. One finding per text, at its first
site (file path order, then line), naming the count. Only plain literals count: constants, resource strings and format
strings are other kinds. Units whose file name contains `test` are neither counted nor reported. Needs the project index
(`lint-all`).

## dunitx-attribute-hygiene (warning, bug-patterns, ON)

Silent without an index. Reports three things on a class carrying `[TestFixture]`:

1. The fixture has no `[Test]`, `[TestCase]` or `[TestCaseSource]` method. A published method, a method named `Test*`,
   or any ancestor other than TObject suppresses it. Reported on the `[TestFixture]` line.
2. `[Ignore]` or `[Ignore('')]` on the fixture or one of its methods (no reason).
3. `[Setup]`, `[TearDown]`, `[SetupFixture]` or `[TearDownFixture]` on two methods of one fixture, reported on the later one.

## variant-in-loop (hint, refactoring, OFF)

No index needed. Reports an assignment inside a for, for-in, while or repeat loop whose right side does `+ - * / div mod`
on a direct operand declared Variant or OleVariant (late-bound calls). Parameters, locals, inline vars and the function
Result count. Fields and globals are not proven, so they stay silent.

## When field-could-be-local stays silent (1.56 FP-1)

Measured on three real projects, the first version reported fields that are state, not temporaries. The rule is now silent when:

* the field is never read at all (a write-only field: a generated name holder, an interface kept alive) -- `could be a local` says nothing useful there;
* its first write in the method is conditional (inside `if` / a loop / `case`, or a `begin..end` of one): the field keeps a value across calls;
* the first write reads the field on the same line (`F := F + [X]`: an accumulator);
* the file holds a same-name reference the index could not bind (it may be a use elsewhere).

The cost is recall: a field first written inside a loop or `try` block that really is a temporary is no longer reported.
