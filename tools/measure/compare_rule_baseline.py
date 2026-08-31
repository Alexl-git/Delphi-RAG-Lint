r"""compare_rule_baseline.py -- diff the BEFORE and AFTER rule-count baselines
and check every movement against what the plan PREDICTED.

Phase 4 step 1 of docs/PLAN-MASTER-2026-08-30-reindex-first.md. The extractor
batch ADDS refs, and several already-shipped rules read refs, so their counts
move when the reindex lands. The plan predicts a DIRECTION for each; a rule that
moves the OTHER way is an extractor defect, and this diff is the cheapest
detector available for that.

WHY A SCRIPT AND NOT AN EYEBALL: the interesting failure is a rule that moved
the wrong way by a small amount, or one that vanished entirely. A rule that
stops firing has NO row in the after file, and a missing row reads as
"unchanged" to a human skimming two tables side by side. Absence is checked here
explicitly, from the union of both files' keys.

usage: compare_rule_baseline.py <before.csv> <after.csv>
exit 0 = every movement matches its prediction; 1 = at least one does not.
"""

import csv
import sys
from collections import defaultdict

# The master plan's section 1 table. 'flat' means the rule reads no refs and so
# must not move at all; an unlisted rule is unpredicted and only reported.
PREDICTED = {
    'global-only-uses-edge':   'down',   # fires only when globals are the ONLY link; new refs are new links
    'uses-global-census':      'up',     # counts referenced globals per edge; more refs, bigger numbers
    'unused-public-symbol':    'down',   # a const used only in an array bound looked unreferenced
    'unused-private-member':   'down',   # same mechanism
    'duplicate-global-decl':   'flat',   # symbols only, no refs join
    'with-hides-outer-symbol': 'flat',   # reads symbol surfaces and the AST, not refs
}


def load(path):
    counts, fps = {}, set()
    with open(path, newline='', encoding='ascii', errors='replace') as fh:
        for row in csv.DictReader(fh):
            counts[(row['corpus'], row['rule'])] = int(row['count'])
            fps.add((row['corpus'], row.get('fingerprint', '')))
    return counts, dict(fps)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    before, fp_b = load(sys.argv[1])
    after,  fp_a = load(sys.argv[2])

    print('FINGERPRINTS (the two sides must differ, or the reindex did not land)')
    for corpus in sorted(set(fp_b) | set(fp_a)):
        b, a = fp_b.get(corpus, '?'), fp_a.get(corpus, '?')
        flag = '' if b != a else '   <-- IDENTICAL: this corpus was NOT reindexed'
        print(f'  {corpus:8s} {b}  ->  {a}{flag}')
    print()

    bad = []
    # Union of keys: a rule present on only ONE side is the case a side-by-side
    # read misses, and it is the more alarming one.
    keys = sorted(set(before) | set(after))
    by_corpus = defaultdict(list)
    for k in keys:
        by_corpus[k[0]].append(k)

    for corpus in sorted(by_corpus):
        rows = []
        for key in by_corpus[corpus]:
            rule = key[1]
            b = before.get(key)
            a = after.get(key)
            if b == a:
                continue
            pred = PREDICTED.get(rule)
            if b is None:
                verdict = 'NEW RULE (not in before)'
            elif a is None:
                verdict = 'VANISHED (no row after)'
            else:
                moved = 'up' if a > b else 'down'
                if pred is None:
                    verdict = 'unpredicted'
                elif pred == 'flat':
                    verdict = 'VIOLATION: predicted flat'
                elif pred != moved:
                    verdict = f'VIOLATION: predicted {pred}'
                else:
                    verdict = f'ok ({pred})'
            if verdict.startswith('VIOLATION') or verdict.startswith('VANISHED'):
                bad.append((corpus, rule, b, a, verdict))
            rows.append((rule, b, a, verdict))
        if not rows:
            continue
        print(f'=== {corpus} ===')
        for rule, b, a, verdict in sorted(rows, key=lambda r: r[0]):
            bs = '-' if b is None else str(b)
            as_ = '-' if a is None else str(a)
            print(f'  {rule:34s} {bs:>8s} -> {as_:>8s}   {verdict}')
        print()

    # Every PREDICTED rule that did not move at all is worth naming too: a
    # prediction of "down" that produced no movement is not a violation, but it
    # is evidence the fix did not reach that rule and should be explained.
    print('PREDICTED RULES THAT DID NOT MOVE')
    still = False
    for corpus in sorted(by_corpus):
        for rule, pred in PREDICTED.items():
            key = (corpus, rule)
            if key in before and before.get(key) == after.get(key) and pred != 'flat':
                print(f'  {corpus:8s} {rule:34s} {before[key]} (predicted {pred})')
                still = True
    if not still:
        print('  (none)')
    print()

    if bad:
        print(f'VERDICT: {len(bad)} movement(s) contradict the plan -- STOP and explain each')
        return 1
    print('VERDICT: every movement matches its prediction')
    return 0


if __name__ == '__main__':
    sys.exit(main())
