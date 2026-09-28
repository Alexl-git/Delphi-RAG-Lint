<!-- dl:spec status=draft authored=2026-09-23 author=AI -->
# Form A grammar design -- the .dlgraph script for drag-lint diagram questions

Status: DRAFT for owner review. Spec only; no implementation code.

## CORRECTION NOTICE -- read before trusting section 7 or the verb table

This spec was drafted against the golden fixture as it stood on 2026-09-23
MORNING, which was **internally inconsistent**: its `END TRACE` line declared
33 steps / 12 guards / 4 crossings while its Form A block actually contained
11 numbered steps, 7 guards and 2 crossings. Only the READ half had been
migrated to the numbered form; the write half was still the original prose
draft. **Drafting this spec is what exposed that** -- see OQ-1 and OQ-2 below,
which were written as open questions and turned out to be a defect report.

The fixture has since been rewritten as a complete 33-step trace and now
verifies against its own declaration: 33 steps numbered contiguously 1..33 with
no duplicates, 12 guards, 4 crossings, 30 anchors, 7-bit ASCII, CRLF, no bare
LF.

What that means for this document:

| part | status after the fixture correction |
|---|---|
| Sections 1, 2 (lexical, layout, indentation, trivia) | **Stands.** Derived from structure, not from the defective counts. |
| Section 3 (EBNF) | **Stands structurally.** The `verb` production as drafted is superseded by the regenerated 27-verb set in section 7. |
| Section 4 (model) | **Stands.** |
| Section 5 (35 EARS criteria) | **Stands as patterns.** Criteria quoting a COUNT or a LINE NUMBER must take their values from section 7: the block is lines 40..138 with 30 anchors, not 40..123 with 29. |
| Section 6 (open questions) | **OQ-1, OQ-2, OQ-3 and OQ-4 are RESOLVED by the correction** -- counts recompute, numbering is contiguous from [01], `CROSSES` carries structured `FROM`/`TO`/`OVER`/`WITH`, and `TIERS` is present. The rest stand. |
| Section 7 (verification walk) | **RE-RUN 2026-09-23 and PASSING.** Now executable: `charts\src\Test-FormA.ps1`, 99/99 lines classified, counts recomputed, verb set regenerated, and proven to FAIL on five mutations. |

The gate named in the original draft has been cleared: the verb set is
regenerated and the walk has been re-run against the corrected block, by a
checker that is demonstrated to fail as well as to pass. What remains open is
the ten unresolved questions in section 6, which are owner decisions, not
defects.

Inputs consulted (nothing else):

* `charts\fixtures\golden-operat-name-roundtrip.md` -- the golden fixture,
  whose FORM A block is the acceptance target.
* `docs\BACKLOG-diagram-question-catalogue.md` -- the 24 questions, branch
  policy, rendering decisions, engine answers.
* `charts\src\Emit-Butterfly.ps1` -- working prototype emitting Graphviz
  clusters with clickable rows from engine JSON.

## 0. Decisions inherited (not relitigated here)

1. The Form A script is the AUTHORITY and is the only thing stored in a
   `.dlgraph` bundle. Dot/Graphviz and Mermaid are DERIVED and may be lossy.
   The node/edge record set (fixture FORM C) is an in-memory structure only.
2. The script must read as documentation (pasteable into a DocInsight
   `<remarks>` block unchanged) AND parse deterministically with no AI.
3. Provenance granularity is the STEP, never the enclosing routine. A step may
   carry two anchors when it is genuinely two statements.
4. GUARDs are first-class with an OTHERWISE outcome; an emitter must never
   drop them.
5. CROSS (process boundary) is first-class: from-process, to-process,
   transport, payload.
6. Every edge is `[certain]` or `[inferred]`; inferred renders dashed.
7. Strict 7-bit ASCII, CRLF. No Unicode.

Measured facts that shaped the design: the fixture is CRLF throughout, has no
tabs, no bytes above 0x7E and no trailing whitespace. Internal spacing between
verb and operand is hand-aligned and NOT uniform. Conclusion: the fixture is not
in a machine-canonical layout, so byte-identical round trip is specified through
a trivia-preserving parse (2.8), and canonical layout is a separate emitter mode.

## 1. Overview of the surface

```
TRACE <name>
  TITLE  "<string>"
  INDEX  <ref> + <ref> + ...
  TIERS  <tier> -> <tier> -> ...

<SECTION>                               -- WRITE READ RESPONSE or a tier name
  [<n>] [<actor>] [<subject>] [<VERB> <operand>] [ONLY WHEN <cond>]
        [[inferred]] [@path:line] [-- note]
    GUARD <condition> [@path:line] [OTHERWISE <outcome> [@path:line]] [-- note]
    ON <outcome>
    BOUND VIA | ONTO | AT | SOURCED FROM | CONTRACT   <text> [@path:line]
    CROSSES <boundary>
      FROM <proc>  TO <proc>  OVER <transport>  WITH <payload>

END TRACE  <n> steps, <n> guards, <n> crossings, <n> unresolved.
<epilogue: verbatim, unparsed>
```

Nesting is by indentation (semantic, 2.7). A numbered step `[n]` carries a
gutter that does not take part in indentation; the text after it does.

## 2. Lexical structure

### 2.1 Character set and line endings

* Allowed bytes: 0x20-0x7E, 0x0D, 0x0A. Any other byte (including TAB and
  anything >= 0x80) is `E-CHARSET` at its 1-based line and column.
* Line terminator is exactly CRLF. A bare LF, a bare CR, or a final line
  without CRLF is `E-EOL`.
* Lines and columns are 1-based; a column is a byte offset, equal to a
  character offset because the alphabet is ASCII.

### 2.2 Tokens

A physical line splits into tokens on runs of spaces. Classes, tried in order:

| class | rule |
|---|---|
| `string` | `"` ... `"` on one line; `""` is a literal quote (Pascal style, so Windows paths need no escaping); may contain spaces, `--`, `[`, `@`; unterminated is `E-STRING` |
| `comment` | a token BEGINNING `--` at a token boundary outside a string; runs to end of line |
| `anchor` | a token beginning `@`: `@` path `:` line-no, split at the LAST colon; tail must be a decimal integer >= 1 else `E-ANCHOR`; path opaque. `@` INSIDE a token (`Micronite2027@2026-09-22`) is not an anchor |
| `gutter` | `[` digits `]` as the FIRST token at column 1, followed by spaces |
| `certainty` | exactly `[certain]` or `[inferred]` |
| `bracket-error` | any other token starting `[` outside a string is `E-BRACKET` |
| `word` | any other run of printable non-space characters |

Two sub-shapes are recognised where the grammar asks: `qualified-name` =
identifier { `.` identifier }, identifier = `[A-Za-z_][A-Za-z0-9_]*`; and
`typed-name` = qualified-name `:` qualified-name (three tokens).

### 2.3 Keywords are recognised by POSITION, case-sensitively

The fixture contains `OPERAT.NAME`, `UTF-8`, `BLOBS`, `WHERE`,
`FIB$DATASETS_INFO`, `EXISTS`, `MATCHES`, `IS` in OPERAND positions. So: a
token is a keyword only if spelled exactly upper case AND appearing where that
keyword class is expected. Lower-case spellings are never keywords (`logs` is
text; `LOGS` is a verb).

| class | members | position |
|---|---|---|
| structural | `TRACE` `TITLE` `INDEX` `TIERS` `END` | head of a logical line |
| section names | `WRITE` `READ` `RESPONSE` + every tier name | alone at column 1 |
| tier / actor | `USER` `CLIENT` `SERVER` `DATABASE` (default set; `TIERS` may declare others) | head of a step line followed by more tokens; also operands of `FROM`/`TO` in a crossing |
| item heads | `GUARD` `ON` `CROSSES` | head of a logical line |
| facet heads | `BOUND VIA` `ONTO` `AT` `SOURCED FROM` `CONTRACT` `FROM` `TO` `OVER` `WITH` | head of a logical line (two-word heads matched longest-first) |
| verbs (closed, versioned) | see the note below -- REGENERATE against the corrected fixture | head of a step line, or right after an actor or subject |
| reserved anywhere | `OTHERWISE` `ONLY` `WHEN` and connectives `TO` `FROM` `VIA` `AS` `AT` `OVER` `INTO` `ONTO` `AND` `WITH` `->` | any position outside strings, comments, anchors |

An all-upper-case token in head position in none of the tables is
`E-UNKNOWN-HEAD` (fail loudly; the verb set is closed and versioned, OQ-6). A
mixed-case or lower-case head token is a `subject` and must be a
qualified-name.

**Verb set, INCOMPLETE pending regeneration.** Drafted from the pre-correction
fixture: `EDITS` `FIRES` `CALLS` `SERIALIZES` `PREFIXES` `SENDS` `RECEIVES`
`ROUTES` `SPLITS` `EXTRACTS` `LOOKS UP` `LOADS` `APPLIES` `BINDS` `RUNS`
`WRITES` `BROADCASTS` `SETS` `LOGS` `BUILDS` `READS` `ADDS` `VALIDATES`
`OPENS` `NOTIFIES`. The corrected fixture additionally uses `DESERIALIZES`
`ATTACHES` `SELECTS` `COUNTS` `RECORDS`. Regenerate before implementing.

### 2.4 Trivia lines

An empty line, an all-space line, or a line whose first token is a comment is
TRIVIA: no semantic content, no effect on indentation, retained verbatim for
round trip.

### 2.5 Continuation lines

A non-trivia physical line JOINS the preceding logical line when ALL hold:
it has no gutter; its first token is an `anchor` or the keyword `OTHERWISE`;
and its column exceeds the effective column of the line it continues.
Otherwise it starts a new logical line. If condition 3 fails: `E-CONTINUATION`.
An `OTHERWISE` continuation after a non-GUARD is `E-ORPHAN-OTHERWISE`. The
CRLF and leading spaces become inter-token trivia, so the join is lossless.

### 2.6 Effective column and the gutter

The EFFECTIVE COLUMN of a logical line is the column of its first token AFTER
the optional gutter and following spaces. The gutter is a margin annotation and
never participates in nesting. This is what lets numbered and unnumbered forms
share one indentation rule, and lets a canonical emitter number nested steps
without losing nesting.

### 2.7 Indentation is SEMANTIC

Justification: the fixture expresses call nesting ONLY by indentation, with no
closing keyword and no bracket; DocInsight `<remarks>` and Markdown fences both
preserve leading spaces; a paste that loses indentation then fails loudly
(`E-DEDENT`) rather than silently flattening a call tree into a list; and a
single Python-style stack keeps the parse deterministic.

Rules (logical lines only; trivia skipped):

* Stack of open columns starts `[1]`.
* Column > top: push, emit `INDENT`; the line is a CHILD of the previous
  logical line at the old top. Indent WIDTH is free; only order matters. The
  canonical emitter uses 2.
* Column == top: no token, except the statement rule below.
* Column < top: pop and emit `DEDENT` until top == column; if no open column
  equals it, `E-DEDENT`.
* Column 1 holds exactly: section names, `END TRACE`, and the `TRACE` header.
  Anything else at column 1 is `E-COLUMN-ONE`. Header attributes must be
  indented under `TRACE`.
* STATEMENT RULE: a SEQUENCE (run of sibling logical lines at one column under
  one parent) is NUMBERED if its first line carries a gutter. Inside a numbered
  sequence, a line at the sequence column WITHOUT a gutter does not start a new
  item; it is an additional STATEMENT of the preceding step (`STMT`). That is
  how a step carries two anchors. A statement line must begin with a verb
  (`E-STMT-HEAD`) and its preceding item must be a step (`E-STMT-TARGET`). In
  an unnumbered sequence an equal-column line is simply the next sibling.
* Gutter numbers must be strictly increasing over the whole script
  (`E-STEP-ORDER`).

### 2.8 Trivia preservation and the two emitter modes

The parse produces a concrete-syntax layer: every token carries its leading
whitespace, every physical line its trailing spaces, and trivia lines and the
epilogue are stored verbatim.

* PRESERVING emit: concatenate tokens with trivia; output is byte-identical to
  input for any accepted script. Used when a `.dlgraph` is loaded and saved
  unchanged.
* CANONICAL emit: ignore trivia and lay out from the model -- 2-space indent per
  level, single space between tokens, gutter then one space, annotation column
  padded so the first of `[inferred]`, `@anchor`, inline `OTHERWISE`, `-- note`
  starts at a fixed column with at least two spaces before it; if the preceding
  text already reaches that column the anchor moves to a continuation line. A
  guard's `OTHERWISE` goes on a continuation line aligned with the condition
  unless the guard has no anchor and the outcome fits inline. Canonical output
  is idempotent.

## 3. Grammar

ISO-14977 EBNF. Pseudo-terminals in capitals (`NEWLINE`, `INDENT`, `DEDENT`,
`STMT`, `GUTTER`, `EOF`) come from the layout pass of section 2.

```
script        = header , { section } , end-line , [ epilogue ] , EOF ;

header        = "TRACE" , trace-name , [ comment ] , NEWLINE ,
                INDENT , header-attr , { header-attr } , DEDENT ;
trace-name    = qualified-name ;
header-attr   = title-attr | index-attr | tiers-attr ;
title-attr    = "TITLE" , string , [ comment ] , NEWLINE ;
index-attr    = "INDEX" , index-ref , { "+" , index-ref } ,
                [ "AS" , "OF" , date ] , [ comment ] , NEWLINE ;
index-ref     = identifier , [ "@" , date ] ;
date          = digit , digit , digit , digit , "-" ,
                digit , digit , "-" , digit , digit ;
tiers-attr    = "TIERS" , tier-name , { "->" , tier-name } ,
                [ comment ] , NEWLINE ;
tier-name     = "USER" | "CLIENT" | "SERVER" | "DATABASE" | declared-tier ;

section       = section-name , [ comment ] , NEWLINE ,
                [ INDENT , sequence , DEDENT ] ;
section-name  = "WRITE" | "READ" | "RESPONSE" | tier-name ;

sequence      = item , { item } ;
item          = step | guard | branch | facet | crossing ;

step          = [ GUTTER ] , step-line , NEWLINE ,
                { STMT , statement , NEWLINE } ,
                [ INDENT , sequence , DEDENT ] ;
step-line     = [ actor ] , step-core , [ inline-guard ] ,
                [ certainty ] , [ anchor ] , [ comment ] ;
step-core     = subject , [ verb , [ operand ] ]
              | verb , [ operand ] ;
statement     = verb , [ operand ] , [ inline-guard ] ,
                [ certainty ] , [ anchor ] , [ comment ] ;
actor         = tier-name ;
subject       = qualified-name ;
inline-guard  = "ONLY" , "WHEN" , text ;
certainty     = "[certain]" | "[inferred]" ;

guard         = "GUARD" , text , [ anchor ] , [ otherwise ] ,
                [ comment ] , NEWLINE ;
otherwise     = "OTHERWISE" , text , [ anchor ] ;

branch        = "ON" , word , [ comment ] , NEWLINE ,
                [ INDENT , sequence , DEDENT ] ;

facet         = facet-head , [ text ] , [ anchor ] , [ comment ] , NEWLINE ;
facet-head    = "BOUND" , "VIA" | "ONTO" | "AT"
              | "SOURCED" , "FROM" | "CONTRACT" ;

crossing      = "CROSSES" , text , [ anchor ] , [ comment ] , NEWLINE ,
                [ INDENT , { crossing-field } , DEDENT ] ;
crossing-field= ( "FROM" | "TO" | "OVER" | "WITH" | "CONTRACT" ) ,
                text , [ anchor ] , [ comment ] , NEWLINE ;

operand       = text ;
text          = [ phrase ] , { connective , phrase } ;
phrase        = word , { word } ;
word          = typed-name | qualified-name | string | plain-word ;
typed-name    = qualified-name , ":" , qualified-name ;
connective    = "TO" | "FROM" | "VIA" | "AS" | "AT" | "OVER"
              | "INTO" | "ONTO" | "AND" | "WITH" | "->" ;

end-line      = "END" , "TRACE" , count , steps-word , "," ,
                count , guards-word , "," , count , crossings-word , "," ,
                count , "unresolved" , "." , [ comment ] , NEWLINE ;
steps-word    = "steps" | "step" ;
guards-word   = "guards" | "guard" ;
crossings-word= "crossings" | "crossing" ;
count         = digit , { digit } ;
epilogue      = { any-physical-line } ;

anchor        = "@" , path , ":" , line-no ;
string        = '"' , { string-char | '""' } , '"' ;
comment       = "--" , { printable } ;
qualified-name= identifier , { "." , identifier } ;
identifier    = ( letter | "_" ) , { letter | digit | "_" } ;
```

A `text` ends at the first token that is an anchor, a certainty marker, a
comment, `OTHERWISE`, `ONLY`, or end of logical line. Reserved-anywhere words
cannot appear inside a `phrase`; quote them to use as data (OQ-8).

## 4. Model (in-memory, never authored)

* `Trace` { name, title, indexRefs[], tiers[], sections[],
  counts{steps,guards,crossings,unresolved}, epilogue }
* `Section` { name, items[] }
* `Step` { number?, actor?, subject?, statements[] (verb?, operand,
  inlineGuard?, certainty, anchor?, note?), children[] }
* `Guard` { condition, anchor?, otherwise{outcome, anchor?}?, note? }
* `Branch` { outcome, items[] }
* `Facet` { head, text, anchor?, note? }
* `Crossing` { boundary, from?, to?, transport?, payload?, contract?, anchor?, note? }

Every anchor is stored on the node of the logical line it was written on
(decision 3). A node may have zero anchors; rendering of unanchored rows is
OQ-7.

Derived edges: sequence (item i -> i+1), containment (parent -> first child),
guard exit (guard -> its OTHERWISE outcome, rendered as a row), boundary (the
sequence edge into a `Crossing`), and certainty (an `[inferred]` marker marks
the sequence edge INTO that item; renderers draw it dashed).

The butterfly prototype needs, per row: qname, file, line; per unit a cluster
keyed on the file-name stem; per row a `PORT` and an
`HREF="draglint://open?file=<escaped>&line=<n>"`. Every anchored node supplies
exactly those, so the prototype's dot is expressible from this model. The one
thing it needs that the grammar does not yet name is a section vocabulary for
callers/focus/callees (OQ-6).

## 5. Acceptance criteria (EARS)

Each is checkable by exactly one test. Patterns: U ubiquitous, E event-driven,
S state-driven, X unwanted, O optional. **Counts and line numbers below are
from the PRE-correction fixture and must be re-derived** (see the correction
notice); the criteria themselves stand.

| id | pat | criterion | test |
|---|---|---|---|
| AC-01 | U | THE parser SHALL accept the fixture block and return a model with zero errors. | T-golden-parses |
| AC-02 | U | THE parser SHALL recognise keywords only when spelled upper case AND in a keyword position, treating every other token as text. | T-keyword-position |
| AC-03 | U | THE layout pass SHALL treat indentation as semantic, so a deeper line is a child of the line above and an equal line is its sibling. | T-indent-nesting |
| AC-04 | U | THE parser SHALL record every anchor as (path, line) exactly as written. | T-anchor-list |
| AC-05 | U | THE model SHALL attach each anchor to the node of the logical line it was written on and never to an enclosing node. | T-anchor-attachment |
| AC-06 | U | THE model SHALL allow one step to carry more than one anchor through statement lines. | T-two-statements |
| AC-07 | U | THE model SHALL represent every GUARD line as a guard node with its condition text. | T-guard-nodes |
| AC-08 | U | THE model SHALL record a guard's OTHERWISE outcome when written and null when absent. | T-guard-otherwise |
| AC-09 | E | WHEN a physical line without a gutter begins with `OTHERWISE` or an anchor and is deeper than the preceding logical line THE layout pass SHALL join it to that logical line. | T-continuation-join |
| AC-10 | U | THE model SHALL represent `CROSSES` as a crossing node with from, to, transport and payload filled from `FROM`/`TO`/`OVER`/`WITH` fields and null when absent. | T-crossing-fields |
| AC-11 | U | THE model SHALL set certainty to certain on every item without a marker and to inferred on an item marked `[inferred]`. | T-certainty |
| AC-12 | E | WHEN the dot emitter renders the sequence edge into an inferred item THE emitter SHALL write `style=dashed` on that edge and on no certain edge. | T-dot-dashed |
| AC-13 | U | THE parser SHALL store a trailing `--` comment as the note of the node on that logical line. | T-comment-note |
| AC-14 | E | WHEN `--` occurs inside a string literal THE lexer SHALL keep it as string content and emit no note. | T-comment-in-string |
| AC-15 | U | THE preserving emitter SHALL reproduce the input bytes exactly, CRLF included. | T-roundtrip-bytes |
| AC-16 | U | THE canonical emitter SHALL be idempotent. | T-canonical-idempotent |
| AC-17 | U | THE canonical emitter SHALL preserve the model, ignoring trivia. | T-canonical-model |
| AC-18 | U | THE emitters SHALL write only bytes 0x20-0x7E, 0x0D, 0x0A and terminate every line, including the last, with CRLF. | T-output-bytes |
| AC-19 | U | THE parser SHALL parse the END TRACE line into four integers in the fixed order steps, guards, crossings, unresolved. | T-end-counts |
| AC-20 | U | THE parser SHALL parse INDEX as a `+`-separated list and SHALL recognise `@` as an anchor only at a token boundary. | T-index-refs |
| AC-21 | U | THE parser SHALL treat every line after END TRACE as an opaque epilogue preserved verbatim, contributing no nodes. | T-epilogue |
| AC-22 | U | THE parser SHALL record an actor on a step when its head token is a tier name followed by further tokens. | T-actor-prefix |
| AC-23 | U | THE parser SHALL treat `ONLY WHEN <text>` on a step as an inline guard with condition text and null outcome. | T-inline-guard |
| AC-24 | U | THE parser SHALL treat facet-head lines as facets of the enclosing step, not as steps. | T-facets |
| AC-25 | S | WHILE the enclosing sequence is numbered THE layout pass SHALL treat an unnumbered line at the sequence column as a statement of the preceding step, and in an unnumbered sequence as a sibling item. | T-statement-rule |
| AC-26 | E | WHEN a section name appears alone at column 1 THE parser SHALL close every open item and start a new section. | T-sections |
| AC-27 | E | WHEN the dot emitter renders an anchored node THE emitter SHALL write an HREF of the form `draglint://open?file=<escaped path>&line=<n>` on that row. | T-dot-href |
| AC-28 | E | WHEN the dot emitter groups rows THE emitter SHALL key the cluster by the file-name stem of the row's anchor path. | T-dot-units |
| AC-29 | X | IF the input contains a byte outside 0x20-0x7E/0x0D/0x0A, or a terminator that is not CRLF, THEN THE parser SHALL fail with `E-CHARSET` or `E-EOL` naming the 1-based line and column of the first offending byte. | T-err-bytes |
| AC-30 | X | IF a logical line dedents to a column that is not an open ancestor column THEN THE parser SHALL fail with `E-DEDENT` naming line and column. | T-err-dedent |
| AC-31 | X | IF the head token is all upper case and in no keyword table, or `OTHERWISE` appears without a GUARD, THEN THE parser SHALL fail with `E-UNKNOWN-HEAD` or `E-ORPHAN-OTHERWISE` naming line and column. | T-err-head |
| AC-32 | X | IF an anchor's tail after its last colon is not a positive integer, or a string is unterminated at end of line, THEN THE parser SHALL fail with `E-ANCHOR` or `E-STRING` naming line and column. | T-err-tokens |
| AC-33 | X | IF END TRACE is missing, or a gutter number is not greater than every earlier gutter number, THEN THE parser SHALL fail with `E-NO-END` or `E-STEP-ORDER`. | T-err-structure |
| AC-34 | X | IF any error is raised THEN THE parser SHALL return no model at all and a non-zero exit code -- never a partial parse. | T-err-no-partial |
| AC-35 | O | WHERE strict-counts validation is enabled THE validator SHALL fail with `E-COUNTS` naming written and recomputed values when the END TRACE counts differ from the model's counts. | T-strict-counts |

Count: 35 (U 22, E 6, S 1, X 5, O 1).

**AC-35 is the criterion that found the defect.** Written as an optional
validation, it immediately failed the golden fixture, which is how the
inconsistent counts surfaced. It should be ON by default, not optional --
proposed as an amendment for owner review.

## 6. Open questions

* **OQ-1 END TRACE counts -- RESOLVED.** The counts were not recomputable
  because the fixture was half-migrated, not because the rule was unclear. The
  corrected fixture recomputes exactly: 33 / 12 / 4 / 0. Counts are declarative
  and a validator recomputes and fails on mismatch (AC-35, now proposed as
  default-on).
* **OQ-2 Numbering -- RESOLVED.** Numbering is contiguous from `[01]` across the
  whole script. The parser accepts unnumbered input; the emitter always numbers.
* **OQ-3 CROSSES structure -- RESOLVED.** `CROSSES` now carries indented
  `FROM` / `TO` / `OVER` / `WITH` / `CONTRACT` fields rather than burying them
  in a comment. Grammar updated (section 3).
* **OQ-4 TIERS -- RESOLVED.** Present in the corrected fixture as
  `TIERS client -> pipe -> server -> database`. Optional, default set
  {USER, CLIENT, SERVER, DATABASE}.
* **OQ-5 OTHERWISE optional?** Decision 4 says guards carry an OTHERWISE, but
  some guards omit it. Options: (a) optional, absence means the rest of the
  sequence is skipped; (b) required; (c) grammar optional, machine emitter
  always writes it when the engine knows the else-branch. Recommendation: (c).
* **OQ-6 Section vocabulary for the other 23 questions.** The five section names
  come from `protocol-trace`; the butterfly prototype needs CALLERS / FOCUS /
  CALLEES. Recommendation: closed set plus a registry table in this spec,
  version-bumped, so `E-UNKNOWN-HEAD` stays a hard error.
* **OQ-7 Unanchored items, and what "unresolved" means.** Many items have no
  anchor. Recommendation: render in the unit of the nearest anchored ancestor,
  without an HREF. Separately, "0 unresolved" has no construct; the branch
  policy's "say where it stopped" suggests a first-class `UNRESOLVED <text>`
  item. Not added without a decision.
* **OQ-8 Escaping names that collide with keywords or connectives** (a method
  named `AT`, a column named `TO`). Recommendation: a string literal is accepted
  in subject and phrase position as an escaped name.
* **OQ-9 Epilogue after END TRACE.** Recommendation: keep for the fixture;
  the canonical emitter never writes one.
* **OQ-10 Column in anchors.** `ask --at file:line:col` uses a column; anchors
  carry line only. Recommendation: v1 line only; an optional `:col` can be added
  later by bumping the split rule to "last two colons".
* **OQ-11 Path prefix.** Is `CLIENT\` a project tag or a directory, and may tier
  be inferred from it? Recommendation: the path is opaque to the grammar; the
  emitter writes the index-relative path; resolution belongs to the
  `draglint://open` handler.
* **OQ-12 Anchor on an OTHERWISE outcome.** Grammar allows it; the fixture never
  uses it. Keep or drop.
* **OQ-13 CRLF strictness vs git.** `E-EOL` on a bare LF means a checkout with
  `autocrlf=input` breaks every `.dlgraph`. Recommendation: a `.gitattributes`
  entry `*.dlgraph -text` so bytes are never rewritten.
* **OQ-14 Guard scope is non-syntactic.** In the nested form a guard is a
  sibling preceding the guarded steps; in the numbered form it is a child of the
  step it guards. The model records position and parent only. Confirm no scope
  rule is wanted in the grammar.

## 7. Verification walk -- RE-RUN 2026-09-23, PASSING

The walk is no longer done by eye. `charts\src\Test-FormA.ps1` implements the
lexical and layout rules of sections 2.1-2.7 far enough to classify every line,
regenerate the verb set and recompute the counts. It is the executable form of
AC-01, AC-29, AC-33 and AC-35.

```
Form A verification walk -- golden-operat-name-roundtrip.md
  block            : lines 40..138 (99 lines)
  classified       : 99/99
  steps/guards/xing: 33 / 12 / 4
  anchors          : 30
  bytes            : 0 non-ascii, 0 bare LF
  PASS
```

**Every line of the corrected block classifies under the grammar.** No line
required a rule the grammar does not have.

### The checker is proven to fail, not merely to pass

A guard that has only ever passed is evidence of nothing. Five mutations of the
golden, each caught with the right code:

| mutation | result |
|---|---|
| `33 steps` -> `34 steps` | `E-COUNTS` steps: declared 34, recomputed 33 |
| `12 guards` -> `11 guards` | `E-COUNTS` guards: declared 11, recomputed 12 |
| a TAB inserted | `E-CHARSET` 1 byte outside 0x20-0x7E/CR/LF |
| a bare LF introduced | `E-EOL` 1 bare LF |
| step `[29]` renumbered `[19]` | `E-STEP-ORDER` step [19] does not exceed [28] |
| unmodified golden (control) | PASS, exit 0 |

### Verb set, REGENERATED from the corrected fixture (27)

```
ADDS  APPLIES  ATTACHES  BINDS  BROADCASTS  BUILDS  CALLS  COUNTS
DESERIALIZES  EDITS  EXTRACTS  FIRES  LOADS  LOGS  NOTIFIES  OPENS
PREFIXES  READS  RECEIVES  ROUTES  RUNS  SENDS  SERIALIZES  SETS
SPLITS  VALIDATES  WRITES
```

`EDITS` was restored on 2026-09-28 (round-trip Task 7). The checker read the
actor word of a numbered line (`[01] USER EDITS ...`, `[47] SERVER ROUTES ...`)
as a section header, because a numbered line starts at column 1, so the verb
behind an actor was never collected -- and anything behind an actor word passed
unclassified. The set printed 26 until then.

This supersedes the drafted list in section 2.3. Differences worth noting:
`DESERIALIZES`, `ATTACHES`, `SELECTS`, `COUNTS` and `RECORDS` were missing from
the draft; `LOOKS UP` is no longer used (the corrected fixture expresses it as
`LOADS` with `VIA` / `FROM` facets); and `SELECTS` and `RECORDS` classify as
FACET heads rather than verbs, which is why the regenerated set is 27 and not
29. Facet heads are deliberately kept out of the verb set so `E-UNKNOWN-HEAD`
stays meaningful.

### Two defects the re-run found -- both in the CHECKER, not the grammar

1. A subject-only step line (`FMTOperation.CommitUpdates @...:279`) failed to
   classify because the checker took the trailing anchor as the verb. The
   grammar already allows it -- `step-core` alternative 1 is `subject , [ verb ,
   [ operand ] ]`. Fixed by dropping annotation tokens before head analysis,
   which is what section 3 already says (`text` ends at the first anchor).
2. Facet heads were being counted as verbs, inflating the regenerated set.

Neither required a grammar change, which is the result this walk was looking
for.
