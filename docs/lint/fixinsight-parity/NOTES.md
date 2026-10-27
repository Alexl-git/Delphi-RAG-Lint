# FixInsight -> drag-lint parity, measured 2026-10-27 (WEBSITE, www-84)

Research for a "moving from FixInsight" article. HELD (owner via ENGINE, 2026-10-27): no
rule/feature articles until the release that ships the Clippy wave + the 32-rule triage +
compliance labels. Re-run both fixtures on THAT release before writing.

## Sources

* FixInsight EOL: TMS blog post 2026-09-22 (https://www.tmssoftware.com/site/blog.asp?post=2520):
  sales end immediately, no further releases or compatibility updates, licenses stay valid,
  no alternative recommended; TMS will "evaluate" an open-source request.
* Rule list: TMS FixInsight PDF manual, February 2020
  (https://download.tmssoftware.com/Download/Manuals/TMS%20FixInsight.pdf): 47 ids --
  W501-W536 (31 lines, W529 printed twice: raise-object and duplicate GUID), C101-C111, O801-O805.
  Suppression `//FI:W508`, `//FI:ignore` on line 1, `{$IFNDEF _FIXINSIGHT_}`. CLI
  `FixInsightCL --project= --defines= --libpath= --unitscopes= --xml --csv --settings=x.ficfg`.
* drag-lint side: deployed 1.36.0-alpha, 195 rules / 16 categories.

## Measured (`drag-lint lint FiParity.pas --json --enable exhaustive-enum-case,interface-object-mixing`)

Fires on the fixture: W501 empty-except, W502 empty-finally, W503 self-assignment, W504
missing-inherited-dtor, W506 empty-conditional, W508 overwrite-before-read, W509
code-after-exit, W510 comparison-same-operands, W511 create-inside-try, W512
repeated-else-if-condition, W513 format-argument-count, W514 off-by-one-count, W519
empty-procedure-body, W520 not-in-precedence, W521 function-result-not-set, W522
destructor-without-override, W525 missing-inherited-ctor, W529 reraise-loses-stack, W531
freeandnil-on-interface, W535 exhaustive-enum-case (OFF by default), O804 unused-parameter,
C102 too-many-parameters, C104 type-name-prefix, C107 field-name-prefix, C108 nested-with,
C109 boolean-comparison-true. (26)

Partial (gaps filed `docs\INBOX-fixinsight-parity-gaps.md`): W505 empty THEN (only the stray
`;` shape), W507 identical branches (only single assignments; not begin..end, not calls).

Rule exists, not exercised by the fixture: C101 method-too-long (threshold 250), C103
too-many-locals (25), C105/C106/C111 (type-name-prefix params I/P/E). O802/O803 would be
project-wide unused-symbol rules in lint-all -- NOT measured.

No equivalent seen: W515 suspicious Free (wrong object freed; redundant-assigned-free fired on
a different shape), W517, W523, W524, W526, W527 (getter reads its own property;
property-references-itself did not fire), W528, W530 dup GUID, W534 (interface-object-mixing
did not fire on a pass-to-const-param), W536 (survey gap #17), O801, O805, C110.

Migration facts verified: `drag-lint allow <file> --fix-line L --fix-rule R [--apply]` writes
`// dl:ok <rule>@<hash>`, hashed over the code line (refuses a comment/blank line);
`lint` exits 1 when it has findings; lint-all `--format sarif`, `--baseline`.
