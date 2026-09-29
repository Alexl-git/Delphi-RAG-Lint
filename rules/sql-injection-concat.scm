; SQL built by concatenating a string literal that contains a SQL keyword with a
; variable is a classic injection vector (CWE-89). Use a parameterized query
; (ParamByName / FDQuery params) instead of '+' string building.
; Heuristic: a '+' whose left operand is a SQL-looking string literal and whose
; right operand is a bare identifier (a value spliced straight into the SQL).
;
; TIGHTENED 2026-08-10 -- AN IDENTIFIER POSITION HAS NO PARAMETERIZED FORM.
; When the literal ends with an opening identifier quote -- '"' (SQL standard),
; '[' (T-SQL) or a backtick (MySQL) -- what follows is a TABLE OR COLUMN NAME,
; and no database lets you bind one as a parameter:
;
;   QCount.SQL.Text := 'SELECT COUNT(*) FROM "' + T + '"';
;
; The rule's own advice ("use a parameterized query") is impossible there, so
; firing teaches the reader that the rule can be ignored. Both of this rule's
; hits on drag-lint's own source were exactly this shape, iterating the index's
; own table list.
;
; This does NOT weaken the real case: a value spliced into WHERE/VALUES/SET
; follows a comparison, a comma or a space -- never an identifier quote -- so
; every genuine injection shape still fires.
; TIGHTENED AGAIN 2026-08-13 -- ENGLISH PROSE IS NOT SQL.
; A single keyword match fires on ordinary sentences. Measured on DataCopy:
;
;   'DataCopy is ACTIVE and is the only thing transferring files from the
;    FROM folder right now.' + sLineBreak + ...
;
; -- a MessageDlg string, reported as SQL injection because it contains " from ".
; A real injectable statement carries a VERB and a CLAUSE keyword, essentially
; without exception: SELECT..FROM, INSERT..VALUES, UPDATE..SET, DELETE..WHERE.
; So require a leading verb AND a clause keyword, rather than any one word.
; The verb is anchored to the start of the literal (allowing leading whitespace)
; because that is where a statement begins; a sentence that merely mentions
; "update" mid-prose no longer qualifies.
; TIGHTENED A THIRD TIME 2026-09-28 -- A BARE '(' IS NOT A CLAUSE KEYWORD.
; The clause alternation used to accept any '(' so INSERT INTO T(A) VALUES(
; would qualify. But an English plural marker is a '(' too:
;
;   Format('Delete %d unit rule(s) and dismiss %d unit(s)?' + sLineBreak + ...)
;
; -- a MessageDlg confirmation, reported as SQL injection because "Delete"
; is a verb and "rule(s)" holds a paren. The arm is replaced by the keywords it
; stood in for: ' into ' (every INSERT, MERGE INTO) and ' values' with no
; trailing space (so VALUES( still counts). Fixtures:
; tests\lint\sql-injection-concat.pas (13, 14 still fire) and
; tests\lint\sql-injection-concat-prose.pas (must not).
((exprBinary
  lhs: (literalString) @sql
  operator: (kAdd)
  rhs: (identifier)) @warn
  (#match? @sql "(?i)^'\\s*(select|insert|update|delete|merge|with)\\b")
  (#match? @sql "(?i)( from | where | values| set | into | join )")
  (#not-match? @sql "[\"\\[`]\\s*'$"))
