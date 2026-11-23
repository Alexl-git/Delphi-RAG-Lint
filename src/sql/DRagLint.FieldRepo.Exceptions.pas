unit DRagLint.FieldRepo.Exceptions;

{ drag-lint 1.53 -- lane FR-MODEL: the DL_EXCEPTIONS table (design 2026-11-22-field-repository-v2-design.md
  section 4.5). The schema lint (lane FR-LINT) loads the rows once and asks IsExcepted per finding. }

interface

uses
  FireDAC.Comp.Client;

type
  /// <summary>One DL_EXCEPTIONS row.</summary>
  TFrException = record
    /// <summary>Lint rule id or '*'.</summary>
    RuleId: string;
    /// <summary>`&lt;unit&gt;.&lt;component&gt;`; '' = any dataset.</summary>
    DatasetKey: string;
    /// <summary>Repository table; '' = any table.</summary>
    TableName: string;
    /// <summary>Field name; '' = the whole table.</summary>
    FieldName: string;
    /// <summary>Property, e.g. DisplayWidth; '' = any property.</summary>
    Prop: string;
    /// <summary>Why the finding is accepted (required, like a dl:ok reason).</summary>
    Reason: string;
  end;

  /// <summary>The coordinates of one lint finding that an exception row may silence.</summary>
  TFrFinding = record
    /// <summary>Rule that fired.</summary>
    RuleId: string;
    /// <summary>Dataset the finding is about; '' when none.</summary>
    DatasetKey: string;
    /// <summary>Repository table; '' when none.</summary>
    TableName: string;
    /// <summary>Field name; '' when none.</summary>
    FieldName: string;
    /// <summary>Property; '' when none.</summary>
    Prop: string;
  end;

/// <summary>Loads every DL_EXCEPTIONS row.</summary>
/// <param name="pConn">Open repository connection; a schema-1 file has no such table.</param>
/// <returns>The rows ordered by key; empty for a schema-1 repository.</returns>
function LoadExceptions(pConn: TFDConnection): TArray<TFrException>;

/// <summary>Is a finding silenced by an exception row?</summary>
/// <param name="pExceptions">The rows from LoadExceptions.</param>
/// <param name="pFinding">The finding's coordinates.</param>
/// <returns>True when EVERY non-empty key column of some row matches the finding (case-insensitively).
/// An empty key column is a wildcard; RULE_ID '*' matches every rule.</returns>
/// <remarks>Pure; no I/O. A row naming a property does not silence a finding without that property.</remarks>
function IsExcepted(const pExceptions: TArray<TFrException>; const pFinding: TFrFinding): Boolean;

implementation

uses
  System.SysUtils,
  DRagLint.FieldRepo.Schema;

const
  WILDCARD_RULE = '*';

function KeyMatches(const pRowValue, pFindingValue: string): Boolean;
begin
  Result := (pRowValue = '') or SameText(pRowValue, pFindingValue);
end;

function RowMatchesTarget(const pRow: TFrException; const pFinding: TFrFinding): Boolean;
begin
  Result := KeyMatches(pRow.DatasetKey, pFinding.DatasetKey)
    and KeyMatches(pRow.TableName, pFinding.TableName)
    and KeyMatches(pRow.FieldName, pFinding.FieldName)
    and KeyMatches(pRow.Prop, pFinding.Prop);
end;

function LoadExceptions(pConn: TFDConnection): TArray<TFrException>;
var
  VQuery: TFDQuery;
  VRow: TFrException;
begin
  Result := nil;
  if RepoSchemaVersion(pConn) < 2 then
    Exit;
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pConn;
    VQuery.Open('SELECT "RULE_ID", "DATASET_KEY", "TABLE_NAME", "FIELD_NAME", "PROP", "REASON" ' +  // dl:ok path-traversal@652f -- REVIEWED 2026-11-23: SQL text, not a path -- TFDQuery.Open of a constant SELECT, no variable part
      'FROM "DL_EXCEPTIONS" ORDER BY "RULE_ID", "DATASET_KEY", "TABLE_NAME", "FIELD_NAME", "PROP"');
    while not VQuery.Eof do
    begin
      VRow.RuleId := VQuery.Fields[0].AsString;
      VRow.DatasetKey := VQuery.Fields[1].AsString;
      VRow.TableName := VQuery.Fields[2].AsString;
      VRow.FieldName := VQuery.Fields[3].AsString;
      VRow.Prop := VQuery.Fields[4].AsString;
      VRow.Reason := VQuery.Fields[5].AsString;
      Result := Result + [VRow];
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

function IsExcepted(const pExceptions: TArray<TFrException>; const pFinding: TFrFinding): Boolean;
var
  VRow: TFrException;
begin
  Result := False;
  for VRow in pExceptions do
    if ((VRow.RuleId = WILDCARD_RULE) or KeyMatches(VRow.RuleId, pFinding.RuleId))
      and RowMatchesTarget(VRow, pFinding) then
      Exit(True);
end;

end.
