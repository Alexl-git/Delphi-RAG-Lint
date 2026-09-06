# Three Ways to Read Delphi

**A raw lexer, DelphiAST, and tree-sitter-delphi13 are not three grades of the same tool.**
They are three different answers to one question: *what should happen when the source
doesn't fit?* That answer, far more than raw capability, decides which one your tool
should be built on.

> A designed, illustrated version of this article is published here:
> **https://claude.ai/code/artifact/ef71f169-780a-42bb-8666-38bae93d66a3**

Delphi 13 Florence / RAD Studio 37.0. Figures are corpus measurements cross-checked
against `dcc32`, not synthetic benchmarks.

---

## 1. What each one actually hands you

Every Delphi tool that reads source code sits on one of three foundations. They differ
in what they produce, but the consequential difference is what they *discard* — and how
loudly they fail when the input contains something they weren't taught.

| | **Raw lexer** | **DelphiAST** | **Tree-sitter + pp** |
|---|---|---|---|
| **Output** | Flat token list, source order | Tree of `TSyntaxNode` | Full CST, every token a node |
| **Keeps** | Every byte — comments, whitespace, directives | Meaning and nesting | Structure *and* exact spans |
| **Discards** | All structure | Layout, most trivia | Nothing positional |
| **On bad input** | Nothing happens — there is no "bad input" | Raises; the normal return path yields nothing | Localises damage into `ERROR` nodes and continues |

---

## 2. Three pipelines, three failure surfaces

```
LEXER        source bytes -> TmwPasLex -> token stream

DELPHIAST    source bytes -> TmwPasLex -> TmwSimplePasPar -> TSyntaxNode tree
                                                         \-> exception, 0 nodes

TREE-SITTER  source bytes -> preprocessor -> pure grammar -> CST + ERROR nodes
```

DelphiAST's failure surface is unit-sized and terminal; tree-sitter's is node-sized and
survivable; the lexer has none, because it never makes a claim that could be wrong.

That last point is worth dwelling on. **A lexer cannot be wrong about grammar because it
never asserts any.** This is simultaneously its greatest strength and the reason it
cannot answer most interesting questions.

---

## 3. Where they genuinely differ

| Dimension | Raw lexer | DelphiAST | Tree-sitter + pp |
|---|---|---|---|
| **Behaviour on an unknown construct** | **Unaffected.** Unknown syntax is still just tokens. | **Total loss.** Raises `ESyntaxTreeException`; the return value is nothing. A partial tree survives only on the exception object, and few callers look. | **Localised.** Damage confined to `ERROR` nodes; the rest still parses. |
| **Byte-exact round trip** | **Guaranteed.** Every byte is in some token. | **Impossible.** Trivia and layout abstracted away by design. | **Yes, raw** — but see the preprocessor caveat. |
| **Structural questions** | **You build it.** Only by writing your own parser on top. | **Native.** Precisely what it exists to answer. | **Native**, plus a query language over the tree. |
| **Incremental re-parse on edit** | Cheap anyway — re-lexing is fast enough. | **None.** Full re-parse of the unit on every change. | **Designed in.** Re-parses only the edited subtree. |
| **Conditional compilation** | Visible, unresolved. You see all branches, decide nothing. | Single view, resolved against one define set. | An explicit, swappable stage. |
| **Measured coverage on Delphi 13** | n/a — tokenising cannot fail on well-formed text. | Unpublished; gaps surface as user reports. | **100.000%** on deduplicated valid files; **99.82%** across all rows. |
| **Cost to embed** | Two units. Pure Object Pascal, no runtime. | A handful of units. Pure Object Pascal. | Native library + generated parser; the preprocessor is a second component. |
| **Grammar maintenance** | Add a keyword — usually just new token kinds. | Hand-edit the recursive-descent parser. | Grammar plus conflicts; changes can cascade through GLR tables. |
| **Name resolution, types, scoping** | None. | Partial — structure only, no cross-unit resolution. | None. A CST is syntax; semantics are a layer above. |

---

## 4. Conditional compilation is the real dividing line

Most comparisons of Pascal parsers stop at grammar coverage. In practice the thing that
decides architecture is `{$IFDEF}`, because Delphi's preprocessor can split the source
*mid-expression*:

```pascal
LSASL := {$IFDEF HAS_GENERICS_TList}LSASLList.Items[i]{$ELSE}LSASLList.Strings[i]{$ENDIF};
```

Neither branch is a complete statement. A parser that treats the directive block as one
opaque unit sees a hole exactly where it needs an expression.

There are three viable responses, and each layer takes a different one.

### Read through it in the scanner

The tree-sitter-delphi13 grammar uses a **"THEN-wins"** external scanner: the `{$IFDEF}`
branch flows out as *ordinary tokens*, the `{$ELSE}` branch is swallowed as one opaque
tail, and the directive markers themselves are emitted as whitespace-like extras. The
parser sees the line above as simply `LSASLList.Items[i]` with two invisible markers
around it. Self-contained, no external stage — and worth **98.6%** on its own.

### Resolve it before parsing

The alternative is to make preprocessing an explicit first pass: expand `{$I}` include
chains, evaluate `{$IF defined()}` expressions against a define profile, and emit
resolved text. The grammar downstream is then *simpler*, because it can drop
preprocessor tokens entirely. That is the `preprocessor -> pure` pipeline, and it is what
reaches **100.000%** on valid Delphi 13.

> **The measured result.** Splitting preprocessing from parsing was worth more than five
> percentage points over the best single-pass approach — a larger gain than any
> individual grammar fix. The pattern generalises to any language with cpp-style
> conditional compilation.

### Don't resolve it at all

The lexer's answer is to hand you the directives as tokens and let you decide. For a
formatter this is not a limitation but the entire requirement: a formatter must preserve
*both* branches, because it is rewriting the file for a compiler that will resolve them
later.

### The trade-off that is easy to miss

| Consideration | Raw -> full grammar | Preprocessor -> pure grammar |
|---|---|---|
| **Corpus pass rate** | ~98.2% | ~99.3%, and higher on later grammars |
| **Symbol coverage across `{$IFDEF}`** | **All branches.** Every platform's symbols land in the index. | **Active branch only.** More accurate per configuration, but narrower. |
| **Span fidelity to the original file** | **1:1.** Offsets map straight back to source. | **Needs a source map.** Dropped branches change file length. |
| **Per-file cost** | In-process — one library call. | An extra pass; expensive if it spawns a subprocess per file. |

For a cross-platform symbol index, "all branches" may be a *feature* worth more than the
extra percentage point — you want `WIN32` and `POSIX` symbols both findable. For a linter
that must report accurate line numbers on the code as actually compiled, the source map
is non-negotiable. These are genuinely different products, and the honest answer is that
they can coexist as two modes.

---

## 5. When to reach for each

### Case study: a formatter should not use a parser

[YADF](https://github.com/Alexl-git/YADF), a Delphi source formatter, links exactly two
units from the DelphiAST distribution: `SimpleParser.Lexer.pas` and
`SimpleParser.Lexer.Types.pas`. It never touches `TPasSyntaxTreeBuilder`. The drive loop
is the whole interface:

```pascal
Lex := TmwPasLex.Create;
while Lex.TokenID <> ptNull do
begin
  T.Kind := Lex.TokenID;
  ...
  Lex.Next;
end;
```

On top of that sits a 332-line token layer and a 6,400-line layout engine that builds its
own bracket-and-block grouping. That sounds like duplicated effort until you consider the
requirement: a formatter must round-trip *every* byte, must preserve both arms of an
`{$IFDEF}`, and must never refuse to format a file because of an unfamiliar construct. An
AST throws all three away in its first step.

The payoff is concrete. When a parser bug was reported against DelphiAST — a generic
constructor with a defaulted generic-typed parameter,
`constructor Create(AFinProc: TProc<T> = nil)`, causing the unit to parse to zero nodes —
the formatter was structurally immune. It doesn't link the parser. Round-trip
verification on that exact construct passes byte-for-byte.

### Case study: an indexer must survive the code it cannot read

A symbol index over a large codebase has an unavoidable property: **some files will not
parse.** Vendored third-party sources, work in progress, generated code, files targeting
an older compiler. The question is what happens to those files.

With an all-or-nothing parser, an unparseable file contributes *nothing* — and worse,
does so silently. That is exactly the failure mode reported against DelphiAST: units
matching a common generic pattern parsed to zero nodes and were quietly dropped, leaving
whole libraries unsearchable with no error surfaced to the user. An index that silently
omits things is worse than one that is simply incomplete, because you cannot tell the
difference between "no results" and "not indexed."

Tree-sitter's error recovery changes the economics. A file with one unrecognised
construct still yields every symbol outside it. Combined with incremental re-parsing,
this is also what makes editor integration viable: you cannot re-parse a 9,000-line unit
on every keystroke, but you can re-parse the subtree the user just edited.

### Case study: where a hand-written AST still wins

None of the above makes DelphiAST a bad choice. It occupies a real niche, and two
properties keep it there.

First, it is **pure Object Pascal**. It compiles into your executable with no native
library, no build-time code generation, no C toolchain, no deployment story beyond adding
units to a `.dpr`. For an IDE expert, a build-step tool, or anything that must ship as a
single exe, that is worth a great deal.

Second, its output is an **abstract** tree, not a concrete one. A CST faithfully contains
every semicolon and every comma; when you are walking it looking for method declarations,
that fidelity is noise you must filter. DelphiAST hands you a tree already shaped like
the questions you want to ask.

The condition is that **you control the input.** For one-shot analysis of a codebase you
own — generating documentation, extracting a class model, a migration script over your
own units — a hard failure on an unexpected construct is a perfectly acceptable, even
desirable, contract: it tells you loudly that your assumptions broke. It is when the
input is arbitrary and the failure is silent that the model stops working.

---

## 6. The honest weaknesses

### The lexer makes you build a parser eventually

Every non-trivial lexer-based tool reinvents structure. YADF's 6,400-line layout engine
*is* a parser — a specialised, error-tolerant, layout-preserving one. If your tool needs
to know that a given `<` opens a generic parameter list rather than being a less-than
operator, the lexer will not tell you, and resolving it correctly is genuinely hard.
Choose this layer when byte fidelity is the requirement, not because it looks simpler.

### DelphiAST's failure mode is the whole file

The severity here is easy to underestimate. It is not that a hard-to-parse construct
produces a slightly wrong node — it is that a single unfamiliar token anywhere in a unit
costs you the entire unit. Combined with a language that gains syntax every release, and
with the fact that most embedding tools catch the exception and move on, this yields
silent, spreading blind spots.

There is a partial mitigation worth knowing about: `ESyntaxTreeException` carries the tree
built so far on its `SyntaxTree` property, so a caller who catches *that specific class*
can recover everything parsed before the failure point rather than nothing. Almost nobody
does — the common shape is `on E: Exception`, which throws that salvage away. If you build
on DelphiAST, catch the specific class, keep the partial tree, and above all **count** your
parse failures. A blind spot you can measure is an inconvenience; one you cannot is a
correctness bug in every answer the tool gives.

### Tree-sitter gives you syntax, and stops there

A CST is not a semantic model. It will not resolve `TFoo` to a declaration in another
unit, will not tell you a type, will not track scopes. That layer is yours to build, and
it is usually larger than the parsing work it sits on. There are two further costs:
`ERROR` nodes can mask real problems if you don't measure them, and grammar changes can
cascade unpredictably through GLR conflict tables — a fix that looks local can cost
thousands of files. It also brings a native library into a Delphi build, which is a real
deployment consideration.

### And the preprocessor adds a stage that can lie

Resolving `{$IFDEF}` before parsing is measurably the best route to coverage, but it
introduces a translation between what the parser saw and what is on disk. Every offset the
tool reports must be mapped back. Skip the source map and you get a tool that is more
accurate about syntax while being wrong about *where* — the worst combination for anything
that reports diagnostics to a human.

---

## 7. Choosing: four questions, in order

The questions are ordered deliberately: the first one that gets a hard answer settles the
choice, because it constrains the others.

**Q1 — Must your output reproduce the input byte-for-byte?**
If yes — formatter, rewriter, refactoring tool that edits in place — take the **lexer**
and stop. No AST will preserve what you need, and a CST will make you reconstruct trivia
you could have simply kept.

**Q2 — Is the input arbitrary code you do not control?**
If yes — an indexer, a linter run across vendored sources, editor tooling — you need error
recovery, so take **tree-sitter**. An all-or-nothing parser will silently drop files, and
you will not find out.

**Q3 — Does it need to keep up with a human typing?**
If yes, incremental re-parsing is not optional and only **tree-sitter** offers it. Full
re-parse per keystroke does not scale past small units.

**Q4 — Otherwise: do you own the input, and must this ship as one executable?**
Then **DelphiAST** is the pragmatic choice. Pure Pascal, an already-abstract tree, no
native dependency — and a loud failure on unexpected syntax is a reasonable contract when
the code is yours.

---

## 8. The layered answer

Framing this as a three-way choice is a simplification that mature tools abandon. The
layers compose, and the interesting systems use more than one.

A formatter reads through the **lexer** for fidelity, but may consult a **tree-sitter**
parse to answer a structural question it cannot decide from tokens — is this `<` a generic
bracket? — without ever letting the tree touch its output. An indexer parses with
**tree-sitter** for coverage while keeping a **preprocessor** stage switchable, so it can
offer both all-branch symbol coverage and per-configuration accuracy as separate modes. A
code generator that owns its inputs can happily use **DelphiAST** for a clean semantic tree
while the linter beside it uses something more forgiving.

The failure to avoid is picking the most capable layer by default. **A parser is not a
better lexer** — it is a lexer that has thrown away the things a formatter needs, in
exchange for answering questions a formatter never asks. Decide what your tool must do when
the source doesn't fit, and the layer follows.

---

## See also

- [tree-sitter-delphi13](https://github.com/Alexl-git/tree-sitter-delphi13) — the grammar and preprocessor pipeline described above
- [YADF](https://github.com/Alexl-git/YADF) — the lexer-only formatter used as a case study
- [DelphiAST](https://github.com/RomanYankovsky/DelphiAST) — Roman Yankovsky's parser, source of the lexer both projects build on

*Figures cited from the tree-sitter-delphi13 corpus reports (v1.2.2) and measured line
counts in the DelphiAST and YADF sources.*
