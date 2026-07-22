unit sql;

// Fixture for Auto-Document Phase 2 Task 7 (SQL tables touched fact -- see
// DRagLint.Doc.SymbolFacts.AnalyzeSqlTables/ExtractSqlTables). TSqlRunner's
// methods exercise the extractor's documented rules:
//   * SyncOne -- the task brief's OWN example: a plain SELECT...FROM (read)
//     and a plain UPDATE (write) as two independent string-literal
//     assignments in the same body. Expected: 'SQL: reads OPTRLIST; writes
//     PDF_SCAN'.
//   * RunJoinConcat -- the SAME kind of SELECT built from THREE adjacent
//     '+'-concatenated literals (proves the concatenation-merge rule: no
//     single fragment on its own both starts with SELECT AND names a
//     FROM/JOIN table -- only the merged whole does), with a JOIN for a
//     second read table and a bare one-letter alias on each (proves
//     alias-stripping). Expected reads: OPTRLIST, SCANQUEUE (sorted).
//   * MultiFromList -- 'FROM A, B' comma-list, no JOIN, no alias. Expected
//     reads: CLIENT, VENDOR (sorted).
//   * InsertAndDelete -- INSERT INTO (write) + DELETE FROM (write) in one
//     body; the INSERT literal also carries an embedded escaped quote
//     (Pascal '''''' -> ''), proving the literal decode step. Expected
//     writes: SCAN_LOG, TEMP_ROWS (sorted); no reads.
//   * DynamicQuery -- 'SELECT * FROM ' concatenated with FTableName (a
//     FIELD reference, not a literal) -- the whole run must be classified
//     DYNAMIC and dropped entirely (never a guessed table). This method
//     DOES get a managed block (the Reads: FTableName fact fires), but it
//     must carry NO 'SQL:' line at all.
//   * NoSql -- plain arithmetic, no string literals, no field touch --
//     expected: NO managed block at all (no fact of any kind).
//
// ORDERING NOTE: NoSql is declared/implemented FIRST, not last. This works
// around a PRE-EXISTING, unrelated 'document --apply' merge-engine bug
// (confirmed via a from-scratch repro using ONLY Task 4's Reads/Writes
// fields fact -- no SQL involved at all, so it predates this task and is
// out of this task's scope to fix): a declaration's managed block
// regenerates fine on a 2nd apply when the NEXT declaration ALSO carries a
// block (fact->fact) or when nothing follows it at all (fact->end), but
// COLLAPSES to a bare empty '<summary></summary>' stub on a 2nd apply when
// the declaration immediately AFTER it has NO block of its own (fact->no-
// fact). Every method here except NoSql carries a fact once Task 7 is
// implemented, so placing the one fact-LESS method first (no-fact->fact,
// fact->fact, ..., fact->end) avoids the one adjacency shape that triggers
// it, keeping this test's own idempotency check meaningful.

interface

type
  TSqlRunner = class
  private
    FTableName: string;
  public
    procedure NoSql;
    procedure SyncOne;
    procedure RunJoinConcat;
    procedure MultiFromList;
    procedure InsertAndDelete;
    procedure DynamicQuery;
  end;

implementation

procedure TSqlRunner.NoSql;
var
  X: Integer;
begin
  X := 1 + 2;
end;

procedure TSqlRunner.SyncOne;
var
  SelSql, UpdSql: string;
begin
  SelSql := 'SELECT * FROM OPTRLIST WHERE ID = 1';
  UpdSql := 'UPDATE PDF_SCAN SET STATUS = 1 WHERE ID = 1';
end;

procedure TSqlRunner.RunJoinConcat;
var
  Sql: string;
begin
  Sql := 'SELECT o.ID, q.STATUS ' +
    'FROM OPTRLIST o ' +
    'JOIN SCANQUEUE q ON q.OPT_ID = o.ID';
end;

procedure TSqlRunner.MultiFromList;
var
  Sql: string;
begin
  Sql := 'SELECT * FROM VENDOR, CLIENT WHERE ACTIVE = 1';
end;

procedure TSqlRunner.InsertAndDelete;
var
  Sql1, Sql2: string;
begin
  Sql1 := 'INSERT INTO SCAN_LOG (ID, MSG) VALUES (1, ''x'')';
  Sql2 := 'DELETE FROM TEMP_ROWS WHERE ID = 1';
end;

procedure TSqlRunner.DynamicQuery;
var
  Sql: string;
begin
  Sql := 'SELECT * FROM ' + FTableName;
end;

end.
