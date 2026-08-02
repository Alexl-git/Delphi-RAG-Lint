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

## 2026-08-02 Session: Analysis and Approach

**Analysis Done:**
1. Confirmed T7 HarvestInterfaceComment now harvests `//` comments adjacent-above declarations
2. Identified that `//` explanatory comments in fixtures are being converted to `<summary>` tags
3. Determined that DEFAULT_CFG is likely the 20th function now rendering (had no doc comment, now gets summary from harvested comment)
4. Found that file encoding had issues when attempting edits (literal `r`n sequences appearing)

**Clear Next Steps for returns.pas:**
1. Update test runner:
   - Line ~477: Change count check from 19 to 20
   - Update header comments (NINETEEN -> TWENTY)
2. Update fixture control list:
   - Add DefaultCfg to the CONTROL list
   - Explain that with T7 harvesting, DefaultCfg now has a summary so renders instead of being omitted

**Clear Next Steps for preserve_tags.pas:**
1. Identify all procedures with descriptive `//` comments adjacent-above declarations
2. Add blank line(s) before the `///` doc comments to break adjacency
3. Rationale: Keep explanatory comments but prevent them from being harvested as summaries

**Known Issues:**
- File encoding problems when using Edit tool (appeared as literal `r`n in output)
- Suggest using direct git edits or PowerShell to avoid encoding issues
- Index spans show 0..0 after fixture modifications (needs reindex)
