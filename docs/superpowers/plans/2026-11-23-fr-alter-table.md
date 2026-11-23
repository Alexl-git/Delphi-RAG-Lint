# Field Repository v2 -- per-table ALTER (1.54, lane TT-ALTER)

Spec: `docs\superpowers\specs\2026-11-22-field-repository-v2-design.md` sections 1-5 and the "Per-table ALTER" bullet of
section 9. Owner answer FU-2: on-demand change of one table; refused changes are detected, not discovered.

Safety: no write outside Firebird databases the tests create (embedded engine, private copy, `Providers = Engine13`, so
no server can be reached). `repo alter-table` is a dry run without `--apply`.

## Measured Firebird 4.0.6 behaviour (embedded, scratch database; pinned by AlterTests section F)

| Statement | Firebird does | Plan |
|---|---|---|
| VARCHAR(20) -> VARCHAR(5) | refuses | BLOCKED `refused-shrink`; safe path |
| VARCHAR -> INTEGER, BIGINT -> INTEGER, DOUBLE -> FLOAT | refuses | BLOCKED; safe path |
| NUMERIC(18,2) -> NUMERIC(18,1), TIMESTAMP -> DATE | ACCEPTS and loses data | BLOCKED `lossy`; safe path with loss pre-scan |
| ADD c_NEW, then UPDATE c_NEW in the SAME transaction | refuses: column unknown | the safe path cannot be one transaction |
| DROP c + c_NEW TO c + POSITION in one transaction | works | the swap is one transaction |
| a failing statement / failing COMMIT in a DDL transaction | the earlier DDL is gone after ROLLBACK | direct changes = one transaction |
| ADD ... NOT NULL without default on a non-empty table | refuses at COMMIT | pre-check `rows` |
| SET NOT NULL with NULLs present | refuses at COMMIT | pre-check `nulls` |

So atomicity is claimed PER GROUP only: direct group (one transaction); each safe change (ADD tx, UPDATE tx, verify + swap
tx, compensated by DROP c_NEW when a later step fails); order group. The outcome names each group's state.

## Units

| Unit | Content |
|---|---|
| `DRagLint.FieldRepo.DbProvider` | schema fact records, `IFrDbDialect` (SQL text, pure), `IFrDbProvider` (connection) |
| `DRagLint.FieldRepo.DbProviderFb` | Firebird dialect + FireDAC provider |
| `DRagLint.FieldRepo.Alter` | pure diff engine: repository facts x live facts -> ordered `TFrAlterPlan` |
| `DRagLint.FieldRepo.AlterFacts` | repository side of one table |
| `DRagLint.FieldRepo.AlterApply` | pre-checks (ticket), grouped apply, compensation, verify |
| `DRagLint.FieldRepo.AlterReport` | text / JSON |
| `DRagLint.FieldRepo.SchemaHook`, `.SchemaHookMicronite` | replaceable hook, generic + Micronite |
| `DRagLint.CLI.RepoAlter` | the verb |

## Tasks

1. Types + stub engine, `tests\fieldrepo\AlterTests.dpr` RED. 2. Engine GREEN (every BLOCKED reason + its positive
control). 3. Provider + apply against a scratch embedded database, mid-sequence failure tests. 4. CLI + hub commit +
`run_repo_cli_alter.ps1` (RED on the 1.53 engine). 5. Registry entry, wiki, lint.

## Decisions (record)

* D1 rename has no repository evidence (the name is the identity): explicit `--rename OLD=NEW` only.
* D2 the repository holds no column position: reorder only from `--order A,B,..` (listed first, the rest keep their order).
* D3 DROP COLUMN, DROP NOT NULL and safe-path changes are UNCHECKED; only `--select` takes them.
* D4 `--select` without `--apply` stays a dry run (differs from refresh-schema on purpose).
* D5 a repository NULL_FLAG of 0 is weak evidence: refresh-schema stores the DOMAIN flag only (RDB$FIELDS), not the
  column's own NOT NULL. Hence DROP NOT NULL is offered unchecked, and never for a primary key column.
* D6 a column without DOMAIN_NAME in the repository never loses its live domain (BLOCKED `domain`).
* D7 STRING_SIZE and CHAR_LENGTH must agree (BLOCKED `repo-inconsistent`): two facts, no winner.
* D8 direct type changes are a whitelist (char growth, SMALLINT -> INTEGER -> BIGINT -> INT128 at equal scale,
  FLOAT -> DOUBLE); everything else is blocked or safe path even where Firebird would accept it.
* D9 the safe path's UPDATE fires triggers: active UPDATE triggers block it.
* D10 `OpenMode`, `CreateDatabase`, `DropDatabase` and connection definitions in `--connection` are refused
  (FireDAC could create or drop a database).
