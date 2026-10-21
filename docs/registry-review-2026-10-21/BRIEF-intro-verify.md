# Brief: intro + verify for ENGINE registry entries (2026-10-21)

Repo: C:\Projects\Delphi-RAG-lint. featuregen: `.\src\tools\featuregen\featuregen.exe` (run from repo root; `--help` lists verbs).
Entries: `features\entries\<id>.json`. Wiki pages: `docs\wiki\<wikiPage>.md`.

For EACH id in your batch list (`docs\registry-review-2026-10-21\ENGINE-batchN-ids.txt`):
1. Skip it if the entry already has `intro` AND `verified` (restart-safe) or its owner is not ENGINE (never touch or verify another team's entry).
2. Read the entry and its wiki page. Check the facts against the LIVE engine: `third_party\dll-win64\drag-lint.exe --help` (full path) and, for a cli verb, the verb's own help. Never use bare `drag-lint`.
3. Write an `intro`: 1-3 sentences, max 600 chars, plain ASCII, no PowerShell mention, for a user who has never seen the feature: say WHEN to use it and what they get, in the style of `features\entries\compare.json` ("Read this when ..."). Facts only from the page, the entry or the live help; if unsure, leave it out.
   Set it with: `featuregen update --id <id> --set "intro=<text>"` (quote carefully; a double quote inside the text breaks it - avoid them).
4. If the entry's usage/flags/summary disagree with the live engine or the wiki page, do NOT guess a fix: skip verify, record it in the report as MISMATCH with what differs.
5. Otherwise `featuregen verify --id <id> --by ENGINE`.

Do NOT run `build`, `normalise`, any git command, or edit anything outside `features\entries\<your ids>.json` and your report. The lead builds and commits once at the end.

REPORT (required, write it as you go - append after every ~5 entries so a stop loses nothing):
`docs\registry-review-2026-10-21\report-ENGINE-batchN.md`, first line `batch N | agent model | started <time>`, then one line per id:
`<id> | DONE | intro set + verified` or `<id> | SKIPPED | already complete` or `<id> | MISMATCH | <what differs>` or `<id> | FAILED | <error>`.
End with a totals line and `FINISHED <time>`. Final reply to the lead: totals plus the MISMATCH/FAILED ids only, under 150 words.
