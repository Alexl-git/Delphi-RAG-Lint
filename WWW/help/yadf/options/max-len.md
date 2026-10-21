---
id: max-len
title: Max line length
summary: Maximum line length in columns. Long lines are reflowed when "Reflow long lines" is on.
group: line-layout
order: 10
default: "180"
ini: MaxLen
cli: --max-len
since: "1.0.0.0"
status: "stable"
---

# Max line length

Sets the column at which YADF starts wrapping a line. A line longer than this
value is broken at the safest available point (after a comma, before an
operator) when [Reflow long lines](reflow-lines.md) is on.

## When it does not apply

Lines that contain a string literal or a `//` line comment may run past the
limit. Breaking inside a literal would change what the program does, so YADF
leaves those lines alone by design.

## Example

With `MaxLen=60` a long call is wrapped:

    Result:= DoSomething(FirstArgument, SecondArgument, ThirdArgument, FourthArgument);

becomes

    Result:= DoSomething(FirstArgument, SecondArgument,
      ThirdArgument, FourthArgument);

## Related

- [Reflow long lines](reflow-lines.md) - switches wrapping on or off.
- [Indent step](indent.md) - width of the continuation indent.
