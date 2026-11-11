# WEBSITE numbers on the deployed 1.50.0-alpha exe (wave 152, lane MS)

Engine: `drag-lint --version` = drag-lint 1.50.0-alpha (lanes\152\MS\engine, the deployed set). Date 2026-11-11.

## Rule counts (MEASURED)
`drag-lint rules --json`, parsed from the raw JSON (object with keys `rules`, `summary`, `target_compiler`; the counts
come from the `rules` array, not from `summary`): **315 rules, 18 categories, 110 fixable, 262 default-on**.
Per category: bug-patterns 88, project-wide 49, security 22, refactoring 20, dead-code 19, resource-lifetime 16, naming 14,
complexity 13, other 12, data-flow 12, structure 12, platform 10, metrics 8, documentation 5, review-markers 5, modernize 4,
firedac 3, policy 3. Same as 1.49 and 1.48 (315 / 18 / 110): the planner's figure is confirmed.

## cycles --hub numbers of the 149 article
The article (lanes\149\www-drafts\2026-11-10-which-unit-is-the-hub-of-this-cycle.html) quotes `cycles --hub` on drag-lint's own
index (2-unit group draglint.lsp.proxy.merge / draglint.lsp.proxy; 5-unit group draglint.doc.*; refs 16 / 55 / 28 / 153).
STATUS: NOT REFRESHED. A scratch index of the wt (325 files) needs ~6 min CPU (over the 2 min LIGHT limit, box BUSY); the run I
started was stopped before the refs stage and `cycles --hub` on it printed `0 refs` on every edge: that output is NOT a
measurement and is discarded. The group SHAPE did come out the same (same two groups, same hubs, same in/out edge counts
3 impl + 0 intf in, 1 impl + 1 intf out; 1 impl in, 1 intf out), i.e. structure unchanged, ref counts unproven.
Finisher: staged\hub-index.ps1 (re-index, assert refs != 0, print the report) -> compare against the article.

## Product intro 1.50
Staged: lanes\152\MS\staged\www-drafts\product-intro-dl-1.50.0-alpha.txt (WWW\ is the website team's; no edit here).
