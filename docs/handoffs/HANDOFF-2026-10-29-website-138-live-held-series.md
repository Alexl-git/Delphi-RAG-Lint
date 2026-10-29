# HANDOFF 2026-10-29 -- WEBSITE: 1.38.0-alpha set LIVE; FixInsight + series held

Session: www-84 (cwd `C:\Projects\Delphi-RAG-lint\WWW`). Resumes
`HANDOFF-2026-10-27-website-publicity-release-day-next.md` (now `closed`).

## Status

* LIVE 2026-10-29 (owner "verify and publish"), commit "feat(www): 1.38.0-alpha articles + facts"
  (on origin/main):
  * NEW `articles/2026-10-29-add-the-missing-uses-unit` and `2026-10-29-what-the-index-saved-you`
    (ENGINE drafts; every command re-run on deployed 1.38.0-alpha, no number changed; the second
    moved from 2026-10-30). Not re-measured in the gain article: the 0.8x scratch-fixture figure and
    "15 tokens per row".
  * `2026-10-23-untangling-circular-uses`: all samples re-captured on 1.38 (new cycles --plan wording).
  * `site.json` dl facts 290 rules / 18 categories / 111 fixable (= rules with fixable:true; same
    definition as the old 23) + `asOf` fact; `products/dl` tile uses {{fact:asOf}} and dropped
    "some only when you opt in" (no fixable rule is opt-in on 1.38).
* OWNER RULE (2026-10-29): every article that shows numbers carries "as of <date>, <version>" in the
  byline (dated = not wrong later). Done on all 5 articles; older two carry their measure dates
  (three-ways 2026-10-19 / tree-sitter-delphi13 v1.2.2; menu-drift 2026-10-24). On a release that
  changes counts, update `site.json` facts AND `asOf` together.
* Earlier this session: survey + checklist committed; FPC ruling (memory
  `project_fpc_lazarus_decision.md`); Monday pop-up task removed (Outlook only); FixInsight parity
  research `docs\lint\fixinsight-parity\` (+ INBOX `docs\INBOX-fixinsight-parity-gaps.md`, ignored);
  series outline `WWW\ARTICLE-SERIES-dev-challenges.md`; `stats\daily-report.ps1` fixed ("0 repos"
  on a gh TLS timeout -> retries, UNAVAILABLE/UNKNOWN, snapshot kept). That file is git-ignored.

## Resume point -- first action

1. Tell the CURRENT ENGINE session (ListAgents; old pipes were stale) that the 1.38 set is live and
   the asOf rule, so its release-day drafts carry the stamp.
2. Ask the owner the two open questions (below), then wait for the next release note / owner go.

## Not done yet

* Owner questions: (a) Micronite paths in IDE screenshots, or a demo project? (b) keep a tracked
  copy of `stats\daily-report.ps1` (e.g. next to `~/.claude/scheduled`)?
* `publish.ps1`: the FTPS session drops after ~40 uploads ("Session has unexpectedly closed" in
  CreateDirectory); 5 runs needed (it resumes). Add reconnect + retry inside the script.
* `build.ps1:101` copies `assets` into `_site` without clearing: two overlapping builds fail.
* HELD until owner go after the 1.37/1.38 hands-on period: FixInsight migration article (re-run
  `docs\lint\fixinsight-parity\*.pas` on the release first); dev-challenges series (6 parts).
* Weekly duty: `WWW\PUBLICITY-WEEKLY.md` (2 articles/week, reposts, stars, site health).
* Backlog: build check that site.json facts equal `rules --json` summary.

## Gotchas

* Untracked `WWW\dl\`, `WWW\yadf\`, `WWW\_premerge-dl-sample-2026-10-20\`,
  `WWW\help\dl\features\index-build-config.md` are NOT WEBSITE's -- leave them.
* `publish.ps1` builds from the working tree: never publish while another team has unreleased
  generated help in `WWW\help\`.
* The autonomy guard refuses `git branch -d`; owner deletes `feat/www-base`, `fix/www-minors`
  (both merged).
