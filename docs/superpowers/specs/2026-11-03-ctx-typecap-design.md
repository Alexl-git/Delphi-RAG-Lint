# CTX-TYPECAP -- `context` on a whole type caps its method bodies

Backlog row CTX-TYPECAP (docs\BACKLOG-2026-11-01.md); owner ruling 2026-11-01 20:25:
"context on a whole type: method bodies up to ~20k tokens, the rest as signatures +
line ranges". Lane 141-ctx. No extractor change (query-time only).

## The defect, measured (engine 1.40 at 47e175cc)

`context --task "modify TSQLiteSymbolStore"` = 981,509 bytes, `Token count
(estimated): 262214`:

| section | est. tokens |
|---|---|
| Class surface (members + their docs) | 47,237 |
| Impl slice: class-decl chunk | 67,519 |
| Impl slice: 204 impl-method chunks | 149,652 (max 13,180, median 375) |
| everything else | ~830 |

The class-decl chunk is the declaration text a second time (the surface already
lists it). A small type (`TContextBundler`, 12,631 tokens) is fine as it is.

## The rule

1. **Scope.** Only a TYPE target (class, record, interface) whose slice is
   assembled from impl-method chunks. A member target (one method) is never cut:
   its body is the thing the task named.
2. **Budget.** `--max-body-tokens N`, default **20000**; `0` = uncapped (today's
   bundle, byte-identical). The budget counts ONLY `impl-method` chunks, with the
   same estimator as the bundle header (`EstimateTokens`). Doc, surface, callers,
   wiki and the omitted list itself do not count toward N (they still count toward
   the header's token estimate, which stays honest).
3. **When the cap engages.** Only when the impl-method total exceeds N. Below it
   nothing changes -- small types render exactly as before.
4. **Which bodies win** (ranked, then greedily packed):
   1. a method named as a FOCUS word after the type name
      (`modify TSQLiteSymbolStore GetSymbolSlice`) -- ALWAYS kept, even past N.
      The CLI hands Build everything after the verb as the qname, so today that
      phrase answers "No symbol matched"; Build now resolves the FIRST word and
      treats the remaining words as focus names (a qname never contains a space,
      so no phrase that resolves today changes meaning);
   2. more in-type callers first: how many OTHER method bodies of the type
      mention the method's leaf name as an identifier (textual, case-insensitive;
      overloads share a count) -- the type's central helpers;
   3. smaller body first (more bodies fit);
   4. source order.
   Packing walks the ranked list and keeps a body if it still fits the remaining
   budget; a body that does not fit is skipped and the walk continues (a smaller
   later body may fit). Kept bodies are emitted in SOURCE order.
5. **The rest = signatures + line ranges.** Every omitted body is listed as its
   header line + `L<start>-<end>` + its token estimate, under
   `## Omitted bodies`, with the unit's file named once and the standard cap note
   `-- N omitted by cap C; rerun with --max-body-tokens 0`.
6. **The class-decl chunk** is dropped while the cap is engaged AND the bundle
   has a class surface (it duplicates it); it is listed among the omitted entries
   as the declaration's line range. With no surface (`--no-surface`) it stays.
   unit-header / unit-trailer chunks (a few tokens) stay.
7. **Formats.** markdown: the section above. json: additive keys `body_cap`,
   `bodies_total`, `bodies_omitted`, `body_tokens_total`, `body_tokens_shown`,
   `omitted_bodies:[{kind,signature,start_line,end_line,tokens}]` (after the
   existing keys, present only when the cap engaged; nothing existing moves). raw: one `// omitted: <sig>  (L a-b)` line per
   omitted body.
8. **Not `--full-surface`.** That flag is the DFM/doc-lines switch for the class
   surface; it does not lift the body cap (two independent knobs).
9. **Callers of Build** (MCP `get_context_bundle`, bench-context) get the default
   cap through the defaulted parameter.

## Not decided here (owner)

The class surface of a type target keeps its members' docs (GAP-CONTEXT 1.40
ruling), so the capped TSQLiteSymbolStore bundle is surface (~47k) + bodies
(<= 20k) + omitted list. Stripping surface doc lines under the cap would cut it
further; left for the owner because it reverses a 1.40 ruling.

## Tests

`tests\autotest\run_context_type_body_cap.ps1` (fixture type with sized bodies):
the cap engages, the task-named body survives, an in-type-called helper beats a
bigger uncalled one, the omitted list carries header + line range, the class-decl
chunk is dropped, `--max-body-tokens 0` restores every body, a member target and a
small type are unchanged (positive controls), json carries the keys.
