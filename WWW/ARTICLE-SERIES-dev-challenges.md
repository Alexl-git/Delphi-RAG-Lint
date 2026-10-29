# Article series: building drag-lint -- the hard parts, and how they look in the IDE

Owner request via ENGINE, 2026-10-28. Status: OUTLINE ONLY. Screenshots wait for the
staged 1.37.0 exe; publish only after the owner has used 1.37 for a while and says go.
Cross-listed in `docs\BACKLOG-AFTER-1.37.0.md` (ENGINE).

## Series rules (on top of ARTICLE-RULES.md)

* Each article = one real engineering problem -> what we tried -> the root cause -> the
  fix -> what the developer sees in RAD Studio. The IDE walk-through is the spine, not
  an appendix: menu path, the dialog, the result.
* Every number is re-measured on the deployed 1.37 exe, on a named project, the day the
  article is written. ENGINE's figures below are leads, not facts.
* Show a failure honestly (the wrong first attempt) -- that is what makes these readable.
* A new Micronite sentence per article (see ARTICLE-RULES.md "Phrasings already used").
* Series nav: each article links the previous/next by its own URL; one shared eyebrow
  ("Building drag-lint &middot; part N").
* Cadence: 2 a week -> 3 weeks. Order below puts the most visible IDE win first.

## The articles

### 1. Lint three times faster: the rule catalog we paid for on every file
* Hook: single-unit lint in the IDE felt slow; profile said the rules, not the parse.
* Problem: the rule catalog (load + compile + config resolve) was rebuilt PER FILE.
* Fix: build once per run / per engine session; what had to become immutable to share it.
* IDE: `drag-lint > Lint current unit` before/after (timing in the messages pane);
  Structure form refreshing as you type.
* Verify: the "3x" on a named project (cold + warm), file count, exe versions A/B
  (immutable copies -- a build kills a running measurement).
* Ask ENGINE: branch/commit, the profile it came from.

### 2. "Who calls this?" across library boundaries: typing the receiver
* Hook: `find callers` on a method called as `FList.Items[I].Save` -- the receiver type
  lives in a library unit, so a name-only index answers short or wrong.
* Problem: resolving receiver types through RTL/VCL/third-party declarations (platform
  library DB + project DB, never another project's).
* Result lead: 90.9% of receivers typed on Micronite (item 4) -- what the other 9.1% are.
* IDE: Find callers on a member; `context` bundle for "modify X"; hover/type-at.
* Verify: the 90.9% (query + DB + date), the categories of the remainder.

### 3. A dry run proves the plan, never the bytes: atomic autofix groups
* Hook: a fix that previewed perfectly and broke a form at load time.
* Problem: multi-edit fixes (code + .dfm + uses) must apply all-or-nothing; a dry run
  only shows the plan.
* Fix: atomic groups, write-then-verify, compile check; the tests that now WRITE.
* IDE: `Fix it` preview -> apply -> what the verification reports; undo story.
* Verify: number of fixable rules in groups, the exact verification steps shipped.

### 4. Every autofix on by default -- and the safety nets that make that sane
* Hook: "default-ON autofix" sounds reckless; the skips are the feature.
* Content: which fixes, which skips (.dfm-referenced members, unindexed forms, ...),
  how a skip is reported, how to opt out per rule.
* IDE: `Fix all in project` preview on a project with a form; the skip lines.
* Verify: ~112 fixable rules (rules --json `fixable` count), the skip list as shipped.
* Option: merge 3 + 4 into one longer article if either runs thin.

### 5. Two indexers, one SQLite file: a foreign-key failure and BEGIN IMMEDIATE
* Hook: a reindex from the IDE plugin and one from the CLI at the same moment -> a FK
  constraint failure, intermittently.
* Root cause: deferred transactions upgrading read -> write lock mid-flight; the window
  in which another writer's rows go missing. Fix: `BEGIN IMMEDIATE` (+ busy timeout).
* IDE: background reindex after save while the CLI/LSP also runs; what you see now.
* Verify: the repro (two concurrent `index --project`), before/after, the SQLite docs
  quote on deferred vs immediate.
* Least visual of the set -- keep it short, one diagram (lock timeline, inline SVG).

### 6. Untangling circular uses, from the IDE
* NOT a rewrite of `articles/2026-10-23-untangling-circular-uses` -- link it. This one is
  the IDE path: the cycle finding in the messages pane -> plan -> apply -> compile ok.
* Also the release-day item: re-capture the `cycles --plan` sample (wording changed in
  dbc28c1f, ships 1.37.0) in the 10-23 article.
* Verify: shipped "not done" list (C1/C4/C5/C8 per ENGINE), exact menu captions.

## Screenshot list (all from the staged 1.37 exe, RAD Studio 37.0)
1. Messages pane: Lint current unit with timing (before/after needs the old exe too).
2. Find callers result on a library-typed receiver; context bundle view.
3. Fix it preview + apply result; 4. Fix all in project with skip lines.
5. (optional) none -- diagram instead. 6. Cycle finding -> plan -> applied.
Log each in `SCREENSHOT-DEBT.md` until taken.

## Open questions for ENGINE (ask when the 1.37 release note arrives)
* Commits / branches behind items 1-5, and the measurement each number came from.
* Which project the owner is happy to see named in screenshots (Micronite paths?).
