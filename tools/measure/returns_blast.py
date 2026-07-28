"""Blast-radius measurement for the mined <returns> section (Phase 3, Task 4b).

WHY THIS IS COMMITTED. Task 4b's design decision -- suppress the whole
"Observed: ..." enumeration when Result is mutated, rather than invent prose
describing the mutation -- turns on HOW MANY routines that silences. A rule
that suppresses half of all <returns> sections is a different proposition from
one that touches a tenth. The numbers in
docs/INBOX-REPLY-autodoc-returns-2026-07-28.md and in the register come from
here, and the phase has already been bitten once by a measurement whose script
was thrown away (register K18: a "49 of 49" figure that drifted with no way to
re-derive it). Run this instead of trusting the figures.

WHAT IT IS NOT. It is a faithful PORT of src/cli/DRagLint.Hover.Returns.pas
for measuring only -- never a second implementation of record. When the two
disagree the Delphi is right and this file is stale. Cross-check with the
engine itself before believing a number:

    for f in <corpus>/*.pas: drag-lint document --unit $f --db <db>
    ... then count '<returns>...Observed:' plus managed '/// Returns: ' lines.

USAGE (python 3.8+, stdlib only):

    python returns_blast.py blast   <db.sqlite> [<path-prefix-filter>]
    python returns_blast.py anchor  <db.sqlite> [<path-prefix-filter>]
    python returns_blast.py argpass <db.sqlite> [<path-prefix-filter>]
    python returns_blast.py braces  <db.sqlite> [<path-prefix-filter>]

  blast   -- routines emitting >=1 mined case today, how many stop emitting and
             WHICH RULE silenced each one, and how many keep emitting but with
             different text. This is the headline measurement.

             The per-rule split is not cosmetic. Three rules can empty the set
             -- the mutation rule, the incomplete-RHS rule, and nested-scope
             masking -- and this script once counted all three under one
             heading labelled "SUPPRESSED by the mutation rule", which the
             reply doc then repeated. On YADF the MAJORITY of the suppression
             was the multi-line-RHS rule, so the label was wrong about most of
             what it described.
  anchor  -- spans eligible for the LEAD-TOKEN header anchor (impl_start_line
             is not the header line, but the routine keyword is the body's
             first token, or the second after `class`), split by whether the
             header it finds actually HEADS THE SYMBOL IT IS ATTRIBUTED TO.

             This mode exists because the gain/loss table that shipped the
             lead-token anchor structurally could not see its own failure: a
             span that lands inside a DIFFERENT routine and starts emitting
             that routine's return values registers as a GAIN. It is not a
             gain. A row whose anchored header is not this symbol's is a
             REGRESSION and is counted as one here.

             AND IT MUST NOT CLASSIFY WITH THE MECHANISM'S OWN PREDICATE. Its
             first version did, twice over, and both were caught by review:
             (a) `lead_anchor_of` stopped at the first non-routine word, so
             every `class`-led span -- the very form the engine had just been
             extended to handle -- reported ineligible and vanished from every
             count (YADF: 96 reported, 100 real); and (b) its "rows lost" test
             read `none_ != now and not (ok and hit)`, in which the second
             conjunct is IMPLIED FALSE by the first for every non-class span,
             so the line could not fail. A tautology is not a check. The loss
             test now runs TWO criteria, neither of which touches the
             mechanism's code: (i) the index's own impl_start_line map -- does
             any indexed row start its implementation on the line the anchor
             landed on, and is it this symbol? -- which is authoritative but
             silent when that row and its duplicates are all stale, i.e. on
             every one of YADF's eligible spans; and (ii) a regex read of the
             raw source line plus a component comparison, which always speaks.
             It also prints the residual is_qualified_tail cannot see: an
             ACCEPTED unqualified header on a symbol the index calls a
             `method`.
  argpass -- the callees that receive a bare `Result` as an argument, ranked.
             This is the evidence for DECLINING INBOX form 1b: the naive text
             test for "Result passed to a var/out parameter" cannot tell a
             write from a read, and the corpus is dominated by Length/SizeOf.
  braces  -- routines whose mined set changes if `{...}` / `(*...*)` block
             comments are blanked. Evidence for the deferred brace-comment
             defect (register K23), which is about MINING out of a comment.
             NOTE WHAT THIS MODE CANNOT SEE: it compares mine_old against
             mine_old(blanked), so it measures the mining direction only. The
             SUPPRESSION direction -- a comment's Inc(Result) deleting a true
             <returns> -- is invisible to it, and was a separate defect fixed
             in T4b's fix round 1.

Example corpora used by the reply doc:

    python returns_blast.py blast C:\\Projects\\YADF\\YADF.sqlite
    python returns_blast.py blast C:\\Projects\\.drag-lint\\Delphi-RAG-lint.sqlite ^
                                  C:\\Projects\\Delphi-RAG-lint\\src
"""
import collections
import re
import sqlite3
import sys

CAP = 6   # production docs.max_return_cases


# --------------------------------------------------------------------------
# Shared primitives (ports of the Delphi ones).
# --------------------------------------------------------------------------

def is_id_ch(c):
    return c.isalnum() or c == '_'


def strip_line_comment(s):
    p = s.find('//')
    return s[:p] if p >= 0 else s


def parse_return_type(sig):
    """Port of DRagLint.Doc.Facts.ParseReturnType."""
    if not sig:
        return ''
    closep = sig.rfind(')')
    colon = sig.rfind(':')
    if colon > closep and colon >= 0:
        return sig[colon + 1:].strip().rstrip(';').strip()
    return ''


# --------------------------------------------------------------------------
# BEFORE: the miner as it shipped up to 447e812.
# --------------------------------------------------------------------------

def result_rhs_old(line):
    t = strip_line_comment(line).strip()
    low = t.lower()
    scan = 0
    while True:
        p = low.find('result', scan)
        if p < 0:
            return ''
        prev_ok = (p == 0) or not is_id_ch(low[p - 1])
        nxt = p + 6
        next_ok = (nxt >= len(low)) or not is_id_ch(low[nxt])
        if prev_ok and next_ok:
            rest = t[p + 6:].lstrip()
            if rest.startswith(':='):
                rest = rest[2:].strip()
                semi = rest.find(';')
                if semi >= 0:
                    rest = rest[:semi]
                return rest.strip()
        scan = p + 6


def exit_rhs(line):
    t = strip_line_comment(line).strip()
    low = t.lower()
    if not low.startswith('exit'):
        return ''
    if len(low) > 4 and is_id_ch(low[4]):
        return ''
    p = t.find('(')
    if p < 0:
        return ''
    depth = 0
    start = p + 1
    for i in range(p, len(t)):
        if t[i] == '(':
            depth += 1
        elif t[i] == ')':
            depth -= 1
            if depth == 0:
                return t[start:i].strip()
    return ''


def mine_old(body):
    seen, out = set(), []
    for ln in body:
        r = result_rhs_old(ln) or exit_rhs(ln)
        if r and r not in seen:
            seen.add(r)
            out.append(r)
    return out


# --------------------------------------------------------------------------
# AFTER: nested-scope masking, the terminator, the mutation rule.
# --------------------------------------------------------------------------

OPENERS = ('begin', 'case', 'try', 'asm', 'record')
ROUTINE_KW = ('function', 'procedure', 'constructor', 'destructor', 'operator')
STOPWORDS = ('end', 'else', 'until', 'finally', 'except')
TAIL_OPS = ('and', 'or', 'not', 'xor', 'div', 'mod', 'shl', 'shr',
            'in', 'is', 'as', 'to', 'downto')
WORD_RESULT = re.compile(r'(?<![A-Za-z0-9_])result(?![A-Za-z0-9_])', re.I)
INCDEC = re.compile(r'(?<![A-Za-z0-9_])(inc|dec|setlength)\s*\(\s*result\s*[,)]', re.I)


def scan_body(lines):
    """Port of TokenizeBody: (tokens, code_only_lines).

    tokens are (line_idx, col, text_lower, kind, end_col) with strings and all
    three comment forms skipped; code_only_lines is the same text with every
    comment and every string literal replaced by spaces (same line count, same
    columns). ':' is a token so `function: Integer` (a parameterless procedural
    type -- the word after the keyword is its RETURN TYPE) is distinguishable
    from `function Twice(...)` (a named nested routine).
    """
    toks = []
    code = [list(l) for l in lines]
    in_brace = in_paren_star = False
    for li, ln in enumerate(lines):
        i, n = 0, len(ln)
        while i < n:
            c = ln[i]
            if in_brace:
                code[li][i] = ' '
                if c == '}':
                    in_brace = False
                i += 1
                continue
            if in_paren_star:
                code[li][i] = ' '
                if c == '*' and i + 1 < n and ln[i + 1] == ')':
                    code[li][i + 1] = ' '
                    in_paren_star = False
                    i += 2
                    continue
                i += 1
                continue
            if c == '{':
                in_brace = True
                code[li][i] = ' '
                i += 1
                continue
            if c == '(' and i + 1 < n and ln[i + 1] == '*':
                in_paren_star = True
                code[li][i] = code[li][i + 1] = ' '
                i += 2
                continue
            if c == '/' and i + 1 < n and ln[i + 1] == '/':
                for k in range(i, n):
                    code[li][k] = ' '
                break
            if c == "'":
                q = i
                i += 1
                while i < n:
                    if ln[i] == "'":
                        if i + 1 < n and ln[i + 1] == "'":
                            i += 2
                            continue
                        i += 1
                        break
                    i += 1
                for k in range(q, min(i, n)):
                    code[li][k] = ' '
                continue
            if c.isalpha() or c == '_':
                j = i
                while j < n and is_id_ch(ln[j]):
                    j += 1
                toks.append((li, i, ln[i:j].lower(), 'word', j - 1))
                i = j
                continue
            if c in '();:':
                toks.append((li, i, c, 'sym', i))
            i += 1
    return toks, [''.join(l) for l in code]


def tokens_of(lines):
    return scan_body(lines)[0]


def is_lead_keyword(toks, ti):
    """Token ti is the body's LEAD routine keyword: the first token, or the
    keyword of a `class function`, whose `class` token comes first."""
    return ti == 0 or (ti == 1 and toks[0][3] == 'word' and toks[0][2] == 'class')


def header_chain_at(toks, ti, lines):
    """The WHOLE dotted chain the header at token ti declares, lowercased, ''
    if none -- 'tbox.classlag', not 'classlag'.

    Components must be joined by a literal '.' on the same line, so a generic
    header (`function TList<T>.Add`) yields the TYPE name alone and
    is_qualified_tail then declines the anchor. Port of Delphi HeaderChainAt.
    """
    chain = ''
    prev_line = -1
    prev_end = 0
    j = ti + 1
    while j < len(toks):
        li, col, tk, kind, end = toks[j]
        if kind != 'word':
            break
        if prev_line >= 0:
            if li != prev_line or col != prev_end + 2:
                break
            if prev_end + 1 >= len(lines[li]) or lines[li][prev_end + 1] != '.':
                break
            chain += '.' + tk
        else:
            chain = tk
        prev_line, prev_end = li, end
        j += 1
    return chain


def is_qualified_tail(chain, qname):
    """chain is a COMPONENT-WISE tail of qname, case-insensitively.

    'talpha.same' vs 'returns.TBeta.Same' -> False, which is the whole point:
    the last component alone matches and the routines are different. A tail
    rather than a fixed component count, because the unit prefix is itself
    dotted and of unknown length. Port of Delphi IsQualifiedTail.
    """
    if not chain or not qname:
        return False
    c, q = chain.lower(), qname.lower()
    return c == q or q.endswith('.' + c)


def mask_nested(lines, accept, lead_test=is_lead_keyword, mask_ch='\x01'):
    """(masked_source, masked_code_only) -- nested scopes blanked in both.

    The routine's OWN header is accepted on body line 0, OR as the body's LEAD
    token (lead_test: token 0, or the routine keyword of a `class function`)
    WHEN accept(<the dotted chain that header declares>) says so. All three
    parts are load-bearing:

      * without "line 0" every `class function` body is masked;
      * without the lead token a stale span that starts before the header turns
        the whole routine into a nested one and deletes its <returns>;
      * without the NAME CHECK the lead token latches onto whatever routine the
        span happens to head -- 85 of 100 eligible spans on the shipping YADF
        index -- and publishes that routine's return values under this one's
        name. Run `anchor` mode for the split.

    ONE masker, parameterised, rather than a copy per historical variant: the
    three copies this file used to carry were a standing invitation to drift,
    and the variants differ only in `accept` and `lead_test`. See mine_new,
    mine_lastcomp and mine_unchecked. Accepting the first routine keyword
    ANYWHERE is deliberately NOT offered -- a span starting mid-routine has no
    honest reading at all.
    """
    toks, code = scan_body(lines)
    out = [list(l) for l in lines]
    cod = [list(l) for l in code]
    depth = paren = 0
    header_seen = False
    pending = None          # (line, col, paren, named)
    stack = []              # (line, col, depth_outside)
    for ti, (li, col, tk, kind, end) in enumerate(toks):
        if kind == 'sym':
            if tk == '(':
                paren += 1
            elif tk == ')':
                paren -= 1
                if pending and not pending[3] and paren < pending[2]:
                    pending = None
            elif tk == ';':
                if pending and not pending[3] and paren == pending[2]:
                    pending = None
            continue
        if tk in ROUTINE_KW:
            own = li == 0 or (lead_test(toks, ti)
                              and accept(header_chain_at(toks, ti, lines)))
            if not header_seen and own and not stack:
                header_seen = True
                continue
            if stack:
                continue
            nxt = toks[ti + 1] if ti + 1 < len(toks) else None
            named = bool(nxt and nxt[3] == 'word' and nxt[2] != 'of')
            pending = (li, col, paren, named)
            continue
        if tk in OPENERS:
            if pending:
                stack.append((pending[0], pending[1], depth))
                pending = None
            depth += 1
            continue
        if tk == 'end':
            depth -= 1
            if stack and depth <= stack[-1][2]:
                sli, scol, _ = stack.pop()
                for x in range(sli, li + 1):
                    a = scol if x == sli else 0
                    b = (end + 1) if x == li else len(out[x])
                    for k in range(a, min(b, len(out[x]))):
                        out[x][k] = mask_ch
                        cod[x][k] = mask_ch
    return [''.join(l) for l in out], [''.join(l) for l in cod]


def looks_complete(s):
    s = s.rstrip()
    if not s:
        return False
    if s[-1] in '+-*/,=<>@^.:&|':
        return False
    j = len(s)
    while j > 0 and is_id_ch(s[j - 1]):
        j -= 1
    return s[j:].lower() not in TAIL_OPS


def cut_rhs(rest):
    """(text, terminated_on_this_line)."""
    paren = i = 0
    n = len(rest)
    while i < n:
        c = rest[i]
        if c == "'":
            i += 1
            closed = False
            while i < n:
                if rest[i] == "'":
                    if i + 1 < n and rest[i + 1] == "'":
                        i += 2
                        continue
                    i += 1
                    closed = True
                    break
                i += 1
            if not closed:
                return rest, False
            continue
        if c in '([':
            paren += 1
        elif c in ')]':
            paren -= 1
            if paren < 0:
                return rest[:i], True
        elif c == ';' and paren == 0:
            return rest[:i], True
        elif (c.isalpha() or c == '_'):
            j = i
            while j < n and is_id_ch(rest[j]):
                j += 1
            if paren == 0 and rest[i:j].lower() in STOPWORDS:
                return rest[:i], True
            i = j
            continue
        i += 1
    return rest, (paren == 0 and looks_complete(rest))


def result_rhs_new(line, mask_ch='\x01'):
    t = strip_line_comment(line).strip()
    low = t.lower()
    scan = 0
    while True:
        p = low.find('result', scan)
        if p < 0:
            return ''
        prev_ok = (p == 0) or not is_id_ch(low[p - 1])
        nxt = p + 6
        next_ok = (nxt >= len(low)) or not is_id_ch(low[nxt])
        if prev_ok and next_ok:
            rest = t[p + 6:].lstrip()
            if rest.startswith(':='):
                txt, term = cut_rhs(rest[2:].strip())
                if not term or mask_ch in txt:
                    return ''
                return txt.strip()
        scan = p + 6


def mutation_forms(code_only):
    """Asked of the CODE-ONLY view. Suppression deletes documentation, so a
    mutation that exists only inside a comment or a string literal must not
    fire -- `{ old: Inc(Result); }` mutates nothing."""
    tags = set()
    for ln in code_only:
        m = INCDEC.search(ln)
        if m:
            tags.add('setlength' if m.group(1).lower() == 'setlength' else 'incdec')
        r = result_rhs_new(ln)
        if r and WORD_RESULT.search(r):
            tags.add('selfref')
    return tags


def _mine(masked, code):
    tags = mutation_forms(code)
    if tags:
        return [], tags
    seen, out = set(), []
    for ln in masked:
        r = result_rhs_new(ln) or exit_rhs(ln)
        if r and r not in seen:
            seen.add(r)
            out.append(r)
    return out, tags


def mine_new(body, qname=''):
    """THE SHIPPING ENGINE. The lead-token anchor fires only when the dotted
    chain the header declares is a component-wise TAIL of the symbol's
    QUALIFIED name. An empty qname declines the anchor (is_qualified_tail is
    False for it) rather than re-enabling the unchecked form -- which is also
    how option B, 'no lead-token anchor at all', is expressed here."""
    return _mine(*mask_nested(body, lambda ch: is_qualified_tail(ch, qname)))


def mine_lastcomp(body, sym_name=''):
    """The anchor AS IT SHIPPED at 75a4be6: name-checked, but on the LAST
    DOTTED COMPONENT only, so `class function TBeta.Same` accepts
    `class function TAlpha.Same`'s header. Kept so the withdrawal that closed
    that hole stays measurable from this file."""
    low = (sym_name or '').lower()
    return _mine(*mask_nested(
        body, lambda ch: bool(ch) and bool(low) and ch.rsplit('.', 1)[-1] == low))


# --------------------------------------------------------------------------
# Corpus walk.
# --------------------------------------------------------------------------

def routines(db, prefix=None):
    """(qname, name, kind, path, impl_start, impl_end, body_lines) for every
    routine with a return type and an implementation span.

    `name` is the SIMPLE name -- exactly what TSymbol.Name used to be checked
    against -- and `qname` is TSymbol.QualifiedName, which is what the anchor
    is checked against now. `kind` is the indexer's own classification
    ('method', 'function', ...), carried so a caller can ask a question the
    miner cannot: an UNQUALIFIED header cannot declare a method.

    One row PER SYMBOL ROW, not per qualified name: an index can hold several
    rows for one qname (duplicate `files` entries, copies under Test\\), each
    with its own span, and it is the ROW that is stale or not.
    """
    con = sqlite3.connect(db)
    rows = con.execute(
        'SELECT s.qualified_name, s.name, s.kind, s.signature, '
        '       s.impl_start_line, s.impl_end_line, f.path '
        'FROM symbols s JOIN files f ON f.id = s.file_id '
        'WHERE s.impl_start_line > 0 AND s.impl_end_line >= s.impl_start_line').fetchall()
    cache = {}
    for qn, nm, kind, sig, a, b, path in rows:
        if prefix and not path.lower().startswith(prefix.lower()):
            continue
        if parse_return_type(sig) == '':
            continue
        if path not in cache:
            try:
                with open(path, encoding='latin-1') as fh:
                    cache[path] = fh.read().splitlines()
            except OSError:
                cache[path] = []
        src = cache[path]
        if not src:
            continue
        yield qn, nm, kind, path, a, b, src[a - 1: min(b, len(src))]


RAW_HDR = re.compile(
    r'^\s*(?:class\s+)?(?:function|procedure|constructor|destructor|operator)\s+'
    r'([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)', re.I)


def raw_header_names(src_line, qname):
    """(spoke, names_this_symbol) -- read straight off the RAW SOURCE LINE.

    The measurement's second INDEPENDENT criterion, and the one that always
    speaks. It shares no code with header_chain_at, is_lead_keyword or
    is_qualified_tail: a regex over the source text, then a component-by-
    component comparison against the qualified name. A blind spot in the
    mechanism therefore cannot hide inside the test of the mechanism.

    The LOCATION still comes from the anchor -- it has to, since the question
    is "the header IT landed on" -- but the verdict does not.
    """
    m = RAW_HDR.match(src_line)
    if not m:
        return False, False
    parts = [p.lower() for p in m.group(1).split('.')]
    q = [p.lower() for p in (qname or '').split('.')]
    return True, 0 < len(parts) <= len(q) and q[len(q) - len(parts):] == parts


def header_owners(db):
    """(path_lower, absolute_1_based_line) -> set of qualified names the INDEX
    says start their implementation there.

    This is the measurement's INDEPENDENT criterion. Every other test of "is
    the anchored header this routine's?" in this file runs the same predicate
    the engine runs, so it can only ever agree with itself; this one asks the
    indexer, which decided where each routine's implementation begins without
    any knowledge of the anchor rule.
    """
    con = sqlite3.connect(db)
    out = collections.defaultdict(set)
    for qn, a, path in con.execute(
            'SELECT s.qualified_name, s.impl_start_line, f.path '
            'FROM symbols s JOIN files f ON f.id = s.file_id '
            'WHERE s.impl_start_line > 0'):
        out[(path.lower(), a)].add(qn.lower())
    return out


def lead_anchor_of(body, qname):
    """(eligible, header_chain, matches, header_line) for the lead-token anchor.

    eligible is True only when body line 0 is NOT the header -- i.e. when the
    lead-token clause is the sole thing that could accept a header at all.
    header_line is the 0-based body line the anchored header sits on, so a
    caller can ask a question about it that does NOT go through this function's
    own predicate.

    A LEADING `class` IS SKIPPED, NOT A STOP. This loop used to break at the
    first word token that was not a routine keyword, so every `class`-led span
    -- the exact form the engine's IsLeadKeyword was extended to handle --
    reported eligible=False and was invisible to every count below. Executed on
    the shipping YADF index that hid 4 eligible spans (96 reported, 100 real).
    """
    toks, _ = scan_body(body)
    for ti, (li, col, tk, kind, end) in enumerate(toks):
        if kind != 'word':
            continue
        if tk == 'class':
            continue
        if tk in ROUTINE_KW:
            if li == 0 or not is_lead_keyword(toks, ti):
                return False, '', False, -1
            ch = header_chain_at(toks, ti, body)
            return True, ch, is_qualified_tail(ch, qname), li
        break
    return False, '', False, -1


def mine_unchecked(body):
    """The lead-token anchor AS IT SHIPPED at 55bcdaf: accepted on body line 0
    OR at token 0, with no name check and no `class` allowance. Kept only so
    the regression it caused stays measurable from this file; it is NOT the
    engine's behaviour any more."""
    return _mine(*mask_nested(body, lambda ch: True,
                              lead_test=lambda toks, ti: ti == 0))[0][:CAP]


def cmd_anchor(db, prefix=None):
    owners = header_owners(db)
    elig = match = 0
    foreign = []
    gained, regressed = [], []
    lost, wrong_subject, unclaimed, mute, residual = [], [], 0, 0, []
    for qn, nm, kind, path, a, b, body in routines(db, prefix):
        ok, ch, hit, hli = lead_anchor_of(body, qn)
        if ok:
            elig += 1
            if hit:
                match += 1
            else:
                foreign.append((qn, nm, ch, a, b))
            # ---- THE INDEPENDENT TESTS ------------------------------------
            # (i) Who does the INDEX say starts an implementation on the line
            # the anchor landed on? Authoritative when it speaks, but SILENT
            # on a span whose own row is stale and whose duplicate rows are
            # stale too -- which on YADF is every eligible span, so this
            # criterion alone would establish nothing there.
            claim = owners.get((path.lower(), a + hli), set())
            if not claim:
                unclaimed += 1
            elif hit and qn.lower() not in claim:
                wrong_subject.append((qn, a, b, 'index', sorted(claim)))
            elif (not hit) and qn.lower() in claim:
                lost.append((qn, a, b, 'index', ch))
            # (ii) A separate reading of the same header off the RAW SOURCE.
            # Always speaks, and shares no code with the mechanism.
            spoke, names_it = raw_header_names(body[hli], qn)
            if spoke:
                if hit and not names_it:
                    wrong_subject.append((qn, a, b, 'source', [body[hli].strip()]))
                elif (not hit) and names_it:
                    lost.append((qn, a, b, 'source', ch))
            else:
                mute += 1
            # ---- THE RESIDUAL is_qualified_tail CANNOT SEE ----------------
            # An unqualified chain is a tail of every qualified name ending in
            # it, so a plain routine `Same` still anchors a method `T.Same`.
            # The index knows which symbols are methods; the miner does not.
            if hit and '.' not in ch and (kind or '').lower() == 'method':
                residual.append((qn, a, b, ch))
        now = mine_new(body, qn)[0][:CAP]
        # (i) what the anchor buys over having no lead-token anchor at all:
        # mine_new with an empty qname IS that variant, by construction.
        none_ = mine_new(body, '')[0][:CAP]
        if none_ != now:
            gained.append((qn, a, b, none_, now))
        # (ii) what the QUALIFIED-NAME check withdraws from the anchor as it
        # shipped at 75a4be6, which name-checked the last dotted component
        # only. Classified by the INDEPENDENT test above, not by `hit`.
        was = mine_lastcomp(body, nm)[0][:CAP]
        if was != now:
            claim = owners.get((path.lower(), a + hli), set()) if hli >= 0 else set()
            regressed.append((qn, a, b, was, now, bool(claim) and qn.lower() not in claim))
    print('spans eligible for the LEAD-TOKEN anchor          : %d' % elig)
    print('  header IS this symbol (qualified-name tail)     : %d' % match)
    print('  header is ANOTHER routine -- a MIS-ANCHOR       : %d  (%.0f%%)'
          % (len(foreign), 100.0 * len(foreign) / max(1, elig)))
    print('INDEPENDENT of the anchor\'s own predicate. Two criteria, neither of which')
    print('consults header_chain_at / is_lead_keyword / is_qualified_tail:')
    print('  (i) the index\'s own impl_start_line map, (ii) a regex over the raw source.')
    print('  DECLINED spans a criterion says ARE this symbol : %d  <- a real LOSS, must be 0'
          % len(lost))
    print('  ACCEPTED spans a criterion says are ANOTHER     : %d  <- wrong subject, must be 0'
          % len(wrong_subject))
    print('  header line claimed by NO indexed row           : %d  (criterion (i) silent)'
          % unclaimed)
    print('  header line the raw-source regex could not read : %d  (criterion (ii) silent)'
          % mute)
    print('  ACCEPTED on an UNQUALIFIED header for a `method`: %d  <- residual, register K30'
          % len(residual))
    print('vs NO lead-token anchor at all (option B):')
    print('  rows GAINED                                     : %d' % len(gained))
    print('vs the anchor as it shipped at 75a4be6 (LAST COMPONENT only):')
    print('  rows changed                                    : %d' % len(regressed))
    print('     of which WITHDRAWN (index: another symbol)   : %d'
          % sum(1 for r in regressed if r[5]))
    print('     of which not so classified                   : %d'
          % sum(1 for r in regressed if not r[5]))
    print('vs the UNCHECKED anchor as it shipped at 55bcdaf:')
    n_unch = 0
    for qn, nm, kind, path, a, b, body in routines(db, prefix):
        if mine_unchecked(body) != mine_new(body, qn)[0][:CAP]:
            n_unch += 1
    print('  rows changed                                    : %d' % n_unch)
    for qn, a, b, was, now in gained[:12]:
        print('   [gained-vs-B] %s  span=%d..%d\n        was=%s\n        now=%s'
              % (qn, a, b, was, now))
    for qn, a, b, crit, ch in lost[:12]:
        print('   [LOST by %s] %s  span=%d..%d  header=%s' % (crit, qn, a, b, ch or '<none>'))
    for qn, a, b, crit, claim in wrong_subject[:12]:
        print('   [WRONG-SUBJECT by %s] %s  span=%d..%d  says=%s' % (crit, qn, a, b, claim))
    for qn, a, b, ch in residual[:12]:
        print('   [residual K30] %s  span=%d..%d  header=%s' % (qn, a, b, ch))
    for qn, a, b, was, now, isforeign in regressed[:12]:
        print('   [%s] %s  span=%d..%d\n        was=%s\n        now=%s'
              % ('withdrawn' if isforeign else 'CHANGED', qn, a, b, was, now))
    for qn, nm, ch, a, b in foreign[:12]:
        print('   [mis-anchor] %s  span=%d..%d  header=%s' % (qn, a, b, ch or '<none>'))


def cmd_blast(db, prefix=None):
    n_old = n_kept = n_changed = 0
    per_form = collections.Counter()
    examples = []
    for qn, nm, kind, path, a, b, body in routines(db, prefix):
        old = mine_old(body)[:CAP]
        if not old:
            continue
        n_old += 1
        new, tags = mine_new(body, qn)
        new = new[:CAP]
        if new:
            n_kept += 1
            if new != old:
                n_changed += 1
                if len(examples) < 10:
                    examples.append((qn, old, new))
        else:
            per_form['ANY'] += 1
            # WHICH rule silenced it. mine_new returns the mutation tags it
            # found; an empty tag set means the set was emptied by the
            # incomplete-RHS rule or by nested-scope masking instead. Counting
            # both under one "mutation rule" heading mis-attributed the
            # MAJORITY of YADF's suppression.
            per_form['by-mutation' if tags else 'by-rhs-or-mask'] += 1
            for t in tags:
                per_form[t] += 1
    print('routines emitting >=1 mined case TODAY   : %d' % n_old)
    print('  no longer emitting, ANY rule           : %d  (%.1f%%)'
          % (per_form['ANY'], 100.0 * per_form['ANY'] / max(1, n_old)))
    print('     of which by the MUTATION rule       : %d' % per_form['by-mutation'])
    for t in ('selfref', 'setlength', 'incdec'):
        if per_form[t]:
            print('           by form %-10s     : %d' % (t, per_form[t]))
    print('     of which by INCOMPLETE-RHS / MASK   : %d' % per_form['by-rhs-or-mask'])
    print('  still emitting, DIFFERENT text         : %d  (%.1f%%)'
          % (n_changed, 100.0 * n_changed / max(1, n_old)))
    print('  still emitting, text unchanged         : %d' % (n_kept - n_changed))
    for qn, o, n in examples:
        print('   %s\n      old=%s\n      new=%s' % (qn, o, n))


def cmd_argpass(db, prefix=None):
    cnt = collections.Counter()
    for qn, nm, kind, path, a, b, body in routines(db, prefix):
        for ln in body:
            t = strip_line_comment(ln)
            if result_rhs_old(ln):
                continue
            for m in re.finditer(r'(?<![A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_.]*)\s*\(([^()]*)\)', t):
                fn = m.group(1).split('.')[-1]
                if fn.lower() in ('inc', 'dec'):
                    continue
                if any(x.strip().lower() == 'result' for x in m.group(2).split(',')):
                    cnt[fn] += 1
    for k, v in cnt.most_common(40):
        print('%5d  %s' % (v, k))
    print('distinct callees: %d  total sites: %d' % (len(cnt), sum(cnt.values())))


def blank_block_comments(lines):
    out = [list(l) for l in lines]
    in_brace = in_paren_star = False
    for li, ln in enumerate(lines):
        i, n = 0, len(ln)
        while i < n:
            c = ln[i]
            if in_brace:
                out[li][i] = ' '
                if c == '}':
                    in_brace = False
                i += 1
                continue
            if in_paren_star:
                out[li][i] = ' '
                if c == '*' and i + 1 < n and ln[i + 1] == ')':
                    out[li][i + 1] = ' '
                    in_paren_star = False
                    i += 2
                    continue
                i += 1
                continue
            if c == '{':
                in_brace = True
                out[li][i] = ' '
                i += 1
                continue
            if c == '(' and i + 1 < n and ln[i + 1] == '*':
                in_paren_star = True
                out[li][i] = out[li][i + 1] = ' '
                i += 2
                continue
            if c == '/' and i + 1 < n and ln[i + 1] == '/':
                break
            if c == "'":
                i += 1
                while i < n:
                    if ln[i] == "'":
                        if i + 1 < n and ln[i + 1] == "'":
                            i += 2
                            continue
                        i += 1
                        break
                    i += 1
                continue
            i += 1
    return [''.join(l) for l in out]


def cmd_braces(db, prefix=None):
    hits = []
    for qn, nm, kind, path, a, b, body in routines(db, prefix):
        o = mine_old(body)[:CAP]
        n = mine_old(blank_block_comments(body))[:CAP]
        if o != n:
            hits.append((qn, o, n))
    print('routines whose mined set changes when {..} comments are blanked: %d' % len(hits))
    for qn, o, n in hits[:8]:
        print('   %s\n      old=%s\n      new=%s' % (qn, o, n))


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(__doc__)
        raise SystemExit(2)
    MODE = {'blast': cmd_blast, 'anchor': cmd_anchor,
            'argpass': cmd_argpass, 'braces': cmd_braces}
    fn = MODE.get(sys.argv[1])
    if fn is None:
        print(__doc__)
        raise SystemExit(2)
    fn(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
