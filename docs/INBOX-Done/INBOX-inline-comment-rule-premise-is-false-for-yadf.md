> **RETIRED to INBOX-Done/ on 2026-08-16 (session 21).** RETIRED 2026-08-16 as MOOT. Measured: inline-comment-in-multiline-args fires 0 times on YADF (1 on DataCopy), so the noise the note objects to does not exist. Re-file if the objection is to the rule existing at all rather than to its cost on YADF.

# `inline-comment-in-multiline-args` names a hazard YADF does not have

Owner raised this 2026-08-13: *"YADF is not supposed to reflow anything into a
line with a // comment. If it does it might be a bug."* Tested. The owner is
right, and the rule's own message is the thing that is wrong.

## The rule's claim

    inline-comment-in-multiline-args (warning, category "structure")
    "// comment inside multi-line argument/array list - reformatters
     (YADF, etc.) may reflow the next element into this comment.
     Move the comment above the line or to its own line."

## The measurement

Fixture, formatted with `YADF.exe --stdout` (Win32 Release, 2026-06-02):

    procedure Setup;
    begin
      Call(A, B,  // note
        C, D);
      Other(A,
        B, C);
      Arr := [1, 2,  // why these
        3, 4];
    end;

Output:

    procedure Setup;
    begin
      Call(A, B, // note
        C, D);
      Other(A, B, C);          <-- JOINED
      Arr:= [1, 2, // why these
        3, 4];
    end;

`Other(...)` is the control: no comment, and YADF joined it onto one line, which
is exactly the reflow the rule is worried about. The two constructs that DO carry
a trailing `//` were left split. **YADF suppresses the join precisely because of
the comment.** A longer multi-line argument list with a trailing comment was also
tested separately and came back byte-equivalent apart from whitespace
normalisation.

So the guard the rule assumes is missing is in fact implemented.

## What this means

1. **The message is misleading.** It names YADF as the example of the hazard, and
   YADF is the one reformatter demonstrably proven here not to have it.
2. **The rule may still be defensible generically** -- "some other reformatter
   might" -- but that is a much weaker claim than the one it makes, and it is
   unverified against any actual tool. A `warning`-severity rule asserting a
   hazard that its own named example does not have is a false-positive generator.
3. It fired 8 times on YADF purely because `drag-lint allow` had written `dl:ok`
   markers into multi-line argument lists. That specific self-inflicted case is
   already fixed (the rule now skips a comment that is entirely a review marker),
   but that fix does not touch the premise.

## Options, for an owner ruling

* **Demote to `info`/OFF-by-default** and rewrite the message to stop naming a
  tool that handles it, e.g. "a reformatter that joins argument lists would
  comment out everything after this point -- verify yours does not."
* **Delete it.** If no reformatter in use has the hazard, the rule is measuring
  nothing.
* **Keep it, and name the actual tool** that does reflow this way, once one is
  identified. That would make it a real rule again.

## Caveats on the measurement

* The exe tested is the 2026-06-02 Release build, not a fresh build of current
  source. If YADF's join logic changed since, retest.
* Only `//` line comments were tested. `{ }` and `(* *)` inside a multi-line
  argument list are untested and could behave differently -- the rule's scanner
  tracks all three (`InParenStarCmt`, `InCmt`), so the premise should be checked
  for those before any of the options above is acted on.
