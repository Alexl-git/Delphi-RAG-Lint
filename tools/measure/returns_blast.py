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


def mask_nested(lines, mask_ch='\x01'):
    """(masked_source, masked_code_only) -- nested scopes blanked in both.

    The routine's OWN header is accepted on body line 0 OR as the body's first
    token. Both halves are load-bearing: without "line 0" every `class
    function` body is masked (the `class` token comes first); without "first
    token" a span that lags the tree by one line turns the whole routine into a
    nested one. Accepting the first routine keyword ANYWHERE is deliberately
    NOT done -- it also re-reads spans that start inside the previous routine.
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
            if not header_seen and (li == 0 or ti == 0) and not stack:
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


def mine_new(body):
    masked, code = mask_nested(body)
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


# --------------------------------------------------------------------------
# Corpus walk.
# --------------------------------------------------------------------------

def routines(db, prefix=None):
    """(qname, path, impl_start, impl_end, body_lines) for every routine with a
    return type and an implementation span."""
    con = sqlite3.connect(db)
    rows = con.execute(
        'SELECT s.qualified_name, s.signature, s.impl_start_line, s.impl_end_line, f.path '
        'FROM symbols s JOIN files f ON f.id = s.file_id '
        'WHERE s.impl_start_line > 0 AND s.impl_end_line >= s.impl_start_line').fetchall()
    cache = {}
    for qn, sig, a, b, path in rows:
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
        yield qn, path, a, b, src[a - 1: min(b, len(src))]


def cmd_blast(db, prefix=None):
    n_old = n_kept = n_changed = 0
    per_form = collections.Counter()
    examples = []
    for qn, path, a, b, body in routines(db, prefix):
        old = mine_old(body)[:CAP]
        if not old:
            continue
        n_old += 1
        new, tags = mine_new(body)
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
    for qn, path, a, b, body in routines(db, prefix):
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
    for qn, path, a, b, body in routines(db, prefix):
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
    MODE = {'blast': cmd_blast, 'argpass': cmd_argpass, 'braces': cmd_braces}
    fn = MODE.get(sys.argv[1])
    if fn is None:
        print(__doc__)
        raise SystemExit(2)
    fn(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
