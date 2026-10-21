batch 3 | Sonnet 5.5 | started (session) 
impact-blast-radius-symbol | DONE | intro set + verified
import-build-log | DONE | intro set + verified
info | DONE | intro set + verified
installation | DONE | intro set + verified
library-drift-check | DONE | intro set + verified
link-orm | DONE | intro set + verified
lint-buffer-unsaved | DONE | intro set + verified
lint-rules | DONE | intro set + verified
lint-tree | DONE | intro set + verified
lsp | DONE | intro set + verified (verify retried after transient nonzero exit)
maintenance | DONE | intro set + verified
mcp-server | DONE | intro set + verified (verify retried after transient nonzero exit)
migrate-dbs | DONE | intro set + verified
multi-project-rename | DONE | intro set + verified (verify retried after transient nonzero exit)
open-plugin-log | DONE | intro set + verified
outline | DONE | intro set + verified
pp-profile | DONE | intro set + verified
preprocess-file | DONE | intro set + verified
project-facts | DONE | intro set + verified
purge-locals | DONE | intro set + verified
query-ancestors | DONE | intro set + verified
query-descendants | DONE | intro set + verified
query-find-callers | DONE | intro set + verified
query-type-usage | DONE | intro set + verified
query-typecat | DONE | intro set + verified
query-unit-usage | DONE | intro set + verified
quick-fix-add-unit-for-inline-hint-h2443-at-cursor | DONE | intro set + verified
quick-fix-add-unit-for-undeclared-at-cursor-ctrl-alt-u | DONE | intro set + verified
quick-fix-convert-public-field-to-property-at-cursor | DONE | intro set + verified
reconcile-project-members-dpr-dproj | DONE | intro set + verified
recover-buffer-compile-files | DONE | intro set + verified
register-project | DONE | intro set + verified
rename-symbol | DONE | intro set + verified
lint-project | MISMATCH | intro set; wiki page lint-project.md usage lists 8 --rule values, entry usage and live help list 14 (adds global-only-uses-edge, duplicate-global-decl, uses-global-census, discarded-effect-free-result, query-name-with-effect, assert-with-side-effect)
query-kind-all | MISMATCH | intro set; entry usage/flags describe 'query --name <symbol-name> ... --case-sensitive --exact'; live help and wiki page: 'query --kind <k> --all [--public] [--db] [--json]'
query-name-like | MISMATCH | intro set; entry usage/flags describe 'query --name ... --case-sensitive --exact'; live help: 'query --name-like <substring> [--kind class,interface,...] [--limit N] [--json] --db'
rebuild-index-for-this-project | MISMATCH | intro set; entry usage is 'index <path> ...' (flags lack --project/--rebuild/--recompile/--dry-run); wiki page and live help document 'index --project <file.dproj> [--recompile|--rebuild] [--dry-run] ...'
rescan-this-unit | MISMATCH | intro already present (kept); not verified: same entry usage/flags gap as rebuild-index (index <path> only, no --project)
resolve-uses | MISMATCH | intro set; surface is cli verb resolve-uses but live help has no such verb (only check-unit --resolve-uses); status internal, entry has no flags
NOTE lint-rules | verified; wiki page rules.md says '190 rules' then 'Of the 189, 137 built-in and 53 external' (internal inconsistency, 137+53=190); live count 190/160/23 matches the first line
TOTALS | DONE=33 MISMATCH=6 FAILED=0 | 39 ids + 1 note (lint-rules counted in DONE)
FINISHED 11:30
