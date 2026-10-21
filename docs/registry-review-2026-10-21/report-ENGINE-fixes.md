ENGINE fixes | sonnet | 2026-10-21
query-kind-all | DONE | entry usage/flags/help set to live query --kind <k> --all [--public]; verified
query-name-like | DONE | entry usage/flags set to live query --name-like ...; verified
rebuild-index-for-this-project | DONE | usage/flags = index --project ... [--recompile|--rebuild] [--dry-run] [--watch]; verified
rescan-this-unit | DONE | same index --project usage/flags; verified
lint-project | DONE | wiki usage lists all 14 --rule values; verified
drag-lint-options | DONE | wiki 190 rules / 23 fixable / 160 default / 16 categories (also rules.md "Of the 189" -> 190); verified
ghost-check | DONE | wiki usage gains --in-place; verified
full-compile-sweep | DONE | wiki usage [--db <db>], text says optional, defaults to project DB; verified
context | DONE | wiki usage gains --max-callers/--context/--full-surface (not verified, not requested)
compile-check | DONE | wiki usage gains [--project <X.dproj>] (not verified)
document-all | DONE | wiki usage gains --migrate-pure (not verified)
resolve-uses | NEEDS-DECISION | HIDDEN verb exists: live esolve-uses prints "Usage: drag-lint resolve-uses --name <Symbol> [--in <file.pas>] [--kind K] [--json] [--db ...]" (finds defining units, ranks which to add to uses); parsed in src\cli\DRagLint.CLI.pas (~6428), absent from --help; find-unit is the documented equivalent. Entry notes say it is internal; not verified/deprecated.
FINISHED