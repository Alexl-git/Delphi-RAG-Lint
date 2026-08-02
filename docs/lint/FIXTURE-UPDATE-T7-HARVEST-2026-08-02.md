# Fixture Updates for T7 Comment Harvesting (2026-08-02)

## Summary

T7 now legitimately harvests `//` comments positioned directly above declarations into managed `<summary>` tags. Some test fixtures had explanatory comments in those positions, causing test expectations to change.

## Action Required

### `run_doc_p3_preserve_tags.ps1` Fixture (`preserve_tags.pas`)

**Issue**: Several test procedures had descriptive comments directly above their declarations. T7 now harvests these comments into `<summary>` tags.

**Approach**: Rather than weaken assertions (which guard real defects), move/separate these comments so they're not adjacent-above declarations. Current fix adds blank lines to break adjacency.

**Procedures affected**:
- `BareDeprecatedOnly` - comment guards dispatch-sniff behavior
- `AllCapsDeprecatedTag` - comment guards case-insensitive tag recognition
- And 4+ others with test-case explanations

### `run_doc_p3_returns.ps1` Fixture (`returns.pas`)

**Issue**: The control list counts exactly **19** `Observed:` lines. With T7 harvesting comments, one routine that previously didn't emit a block (no hand-written doc, T3's omit-when-empty) now emits one because its comment became a `<summary>`, allowing its `<returns>` to render.

**Fix**: Update count from **19 to 20** in the test runner (line ~477).

**Rationale**: This is a genuine count update, not just an increment. The routine acquiring a summary is legitimate (comment harvest), and the 20th line should be re-derived from first principles (identify which routine + why it now renders), not just the NINETEEN list incremented.

## Fixture Comments: Philosophy

These fixtures explain what each test case isolates or guards. The explanatory comments are PART of the fixture's value. Moving them (rather than weakening assertions) preserves:
- The actual test intent (catch specific defects)
- The fixture's self-documenting nature
- The precision of the guards (no false negatives)

Blank-line separation or comment relocation achieves this without compromising the test.
