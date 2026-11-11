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
STATUS: REFRESHED (MEASURED 2026-11-11: fresh index of the lane wt, 1.50.0-alpha engine, `cycles --hub --format text`).
- 2-unit group lsp.proxy.merge / lsp.proxy: identical to the article (in 16 refs / out 55 refs; hub lsp.proxy.merge in 1 impl, out 1 intf; zero-ref 0 of 2; spoke surfaces 11 and 10 symbols).
- 5-unit doc group, hub draglint.doc.regions: in 3 impl edges 28 refs (same); out 2 edges (1 impl, 1 intf) **157 refs (article: 153)**; zero-ref edges **0 of 8 (article: 0 of 7)**. The article text must change 153 to 157 and 7 to 8 edges (the source grew since 2026-11-09). Raw: lanes152MSscratchhub-run.log.

## Product intro 1.50
Staged: lanes\152\MS\staged\www-drafts\product-intro-dl-1.50.0-alpha.txt (WWW\ is the website team's; no edit here).
