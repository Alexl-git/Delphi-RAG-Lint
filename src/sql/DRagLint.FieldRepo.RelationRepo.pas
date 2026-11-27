unit DRagLint.FieldRepo.RelationRepo;

{ drag-lint 1.55 -- lane XTABLE slice X2: loads the relation graph of design
  docs\superpowers\specs\2026-11-26-cross-table-fields-design.md section 3.2 from a field repository's schema facts
  (DL_CONSTRAINTS, DL_CONSTRAINT_COLUMNS) and, on schema 4, its DL_RELATIONS rows. Read-only. }

interface

uses
  FireDAC.Comp.Client,
  DRagLint.FieldRepo.RelationGraph;

/// <summary>Builds the relation graph of a repository (design 3.2): (a) every FK whose REF_CONSTRAINT is a PK /
/// UNIQUE of the referenced table; (b) on schema 4, DL_RELATIONS rows of SOURCE FORM / HAND whose PARENT_KEY is a
/// PK / UNIQUE of the parent on exactly the parent columns. A DL_RELATIONS row of SOURCE FK renames its FK edge and
/// carries IS_DEFAULT (ruling XQ6: FORM relations are edges only once stored, i.e. confirmed).</summary>
/// <param name="pRepo">An open repository connection, schema 2 or later.</param>
/// <param name="pSkipped">Receives one line per relation that is not an edge, with the reason.</param>
/// <returns>A new graph; the caller frees it.</returns>
/// <remarks>A relation whose parent side has no key is never an edge (rows would multiply). Read-only.</remarks>
function LoadRelationGraph(pRepo: TFDConnection; out pSkipped: TArray<string>): TFrRelationGraph;

type
  /// <summary>A PK / UNIQUE constraint of the schema facts: the proof that a parent row is ONE row (design 3.2).</summary>
  TFrTableKey = record
    /// <summary>Table the key belongs to, as stored.</summary>
    TableName: string;
    /// <summary>Constraint name, as stored.</summary>
    ConstraintName: string;
    /// <summary>Key columns in position order.</summary>
    Columns: TArray<string>;
  end;

/// <summary>Every PK / UNIQUE constraint of the repository's schema facts (DL_CONSTRAINTS, DL_CONSTRAINT_COLUMNS);
/// read-dfm uses them to offer a FORM relation for a join that ends on a parent key without an FK (ruling XQ6).</summary>
/// <param name="pRepo">An open repository connection, schema 2 or later.</param>
/// <returns>The keys ordered by constraint name; empty without schema facts.</returns>
function LoadTableKeys(pRepo: TFDConnection): TArray<TFrTableKey>;

/// <summary>The names of the stored DL_RELATIONS rows (design 2.3: an FK step gets its row when a binding first uses
/// it).</summary>
/// <param name="pRepo">An open repository connection.</param>
/// <returns>Upper-case relation names; empty below schema 4.</returns>
function LoadStoredRelationNames(pRepo: TFDConnection): TArray<string>;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Data.DB,
  FireDAC.Stan.Param,
  DRagLint.FieldRepo.Schema;

const
  SCHEMA_WITH_RELATIONS = 4;
  KIND_FK = 'FK';
  SOURCE_FK = 'FK';
  SQL_KEYS =
    'SELECT C."CONSTRAINT_NAME", C."TABLE_NAME" FROM "DL_CONSTRAINTS" C WHERE C."KIND" IN (''PK'', ''UNIQUE'')';
  SQL_KEYS_ORDERED = SQL_KEYS + ' ORDER BY C."CONSTRAINT_NAME"';
  SQL_COLUMNS =
    'SELECT "CONSTRAINT_NAME", "COLUMN_NAME" FROM "DL_CONSTRAINT_COLUMNS" ORDER BY "CONSTRAINT_NAME", "POSITION"';
  SQL_FKS =
    'SELECT "CONSTRAINT_NAME", "TABLE_NAME", "REF_TABLE", "REF_CONSTRAINT" FROM "DL_CONSTRAINTS" ' +
    'WHERE "KIND" = ''' + KIND_FK + ''' ORDER BY "CONSTRAINT_NAME"';
  SQL_RELATIONS =
    'SELECT "RELATION_NAME", "CHILD_TABLE", "PARENT_TABLE", "SOURCE", "CONSTRAINT_NAME", "PARENT_KEY", "IS_DEFAULT" ' +
    'FROM "DL_RELATIONS" ORDER BY "RELATION_NAME"';
  SQL_RELATION_COLUMNS =
    'SELECT "RELATION_NAME", "CHILD_COLUMN", "PARENT_COLUMN" FROM "DL_RELATION_COLUMNS" ' +
    'ORDER BY "RELATION_NAME", "POSITION"';

type
  TFrRelationRow = record
    Name, Child, Parent, Source, Constraint_, ParentKey: string;
    IsDefault: Boolean;
  end;

function SameColumnSet(const pLeft, pRight: TArray<string>): Boolean;
var
  VLeft, VRight: TArray<string>;
begin
  VLeft := Copy(pLeft);
  VRight := Copy(pRight);
  TArray.Sort<string>(VLeft, TIStringComparer.Ordinal);
  TArray.Sort<string>(VRight, TIStringComparer.Ordinal);
  Result := (Length(VLeft) > 0) and SameText(string.Join(',', VLeft), string.Join(',', VRight));
end;

function ColumnsOf(pMap: TDictionary<string, TArray<string>>; const pKey: string): TArray<string>;
begin
  if not pMap.TryGetValue(UpperCase(pKey), Result) then
    Result := nil;
end;

procedure AppendColumn(pMap: TDictionary<string, TArray<string>>; const pKey, pColumn: string);
begin
  pMap.AddOrSetValue(UpperCase(pKey), ColumnsOf(pMap, pKey) + [pColumn]);
end;

procedure ReadColumns(pRepo: TFDConnection; pColumns: TDictionary<string, TArray<string>>);
var
  VQuery: TFDQuery;
begin
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pRepo;
    VQuery.Open(SQL_COLUMNS);
    while not VQuery.Eof do
    begin
      AppendColumn(pColumns, VQuery.Fields[0].AsString, VQuery.Fields[1].AsString);
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

procedure ReadKeys(pRepo: TFDConnection; pKeys: TDictionary<string, string>);
var
  VQuery: TFDQuery;
begin
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pRepo;
    VQuery.Open(SQL_KEYS);
    while not VQuery.Eof do
    begin
      pKeys.AddOrSetValue(UpperCase(VQuery.Fields[0].AsString), UpperCase(VQuery.Fields[1].AsString));
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

function ReadRelations(pRepo: TFDConnection): TArray<TFrRelationRow>;
var
  VQuery: TFDQuery;
  VRow: TFrRelationRow;
begin
  Result := nil;
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pRepo;
    VQuery.Open(SQL_RELATIONS);
    while not VQuery.Eof do
    begin
      VRow.Name := VQuery.Fields[0].AsString;
      VRow.Child := VQuery.Fields[1].AsString;
      VRow.Parent := VQuery.Fields[2].AsString;
      VRow.Source := UpperCase(VQuery.Fields[3].AsString);
      VRow.Constraint_ := VQuery.Fields[4].AsString;
      VRow.ParentKey := VQuery.Fields[5].AsString;
      VRow.IsDefault := VQuery.Fields[6].AsBoolean;
      Result := Result + [VRow];
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

procedure ReadRelationColumns(pRepo: TFDConnection; pChild, pParent: TDictionary<string, TArray<string>>);
var
  VQuery: TFDQuery;
begin
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pRepo;
    VQuery.Open(SQL_RELATION_COLUMNS);
    while not VQuery.Eof do
    begin
      AppendColumn(pChild, VQuery.Fields[0].AsString, VQuery.Fields[1].AsString);
      AppendColumn(pParent, VQuery.Fields[0].AsString, VQuery.Fields[2].AsString);
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

function LoadRelationGraph(pRepo: TFDConnection; out pSkipped: TArray<string>): TFrRelationGraph;
var
  VColumns, VRelChild, VRelParent: TDictionary<string, TArray<string>>;
  VKeys: TDictionary<string, string>;
  VFkRows: TDictionary<string, TFrRelationRow>;
  VRows: TArray<TFrRelationRow>;
  VRow, VFkRow: TFrRelationRow;
  VRel: TFrRelation;
  VQuery: TFDQuery;
  VRefKey, VKeyTable: string;
begin
  pSkipped := nil;
  Result := TFrRelationGraph.Create;
  VColumns := TDictionary<string, TArray<string>>.Create;
  VRelChild := TDictionary<string, TArray<string>>.Create;
  VRelParent := TDictionary<string, TArray<string>>.Create;
  VKeys := TDictionary<string, string>.Create;
  VFkRows := TDictionary<string, TFrRelationRow>.Create;
  VQuery := TFDQuery.Create(nil);
  try
  try
    ReadColumns(pRepo, VColumns);
    ReadKeys(pRepo, VKeys);
    VRows := nil;
    if RepoSchemaVersion(pRepo) >= SCHEMA_WITH_RELATIONS then
    begin
      VRows := ReadRelations(pRepo);
      ReadRelationColumns(pRepo, VRelChild, VRelParent);
      for VRow in VRows do
        if (VRow.Source = SOURCE_FK) and (VRow.Constraint_ <> '') and
          not VFkRows.ContainsKey(UpperCase(VRow.Constraint_)) then
          VFkRows.Add(UpperCase(VRow.Constraint_), VRow);
    end;
    VQuery.Connection := pRepo;
    VQuery.Open(SQL_FKS);
    while not VQuery.Eof do
    begin
      VRel := Default(TFrRelation);
      VRel.Name := VQuery.Fields[0].AsString;
      VRel.ConstraintName := VRel.Name;
      VRel.ChildTable := VQuery.Fields[1].AsString;
      VRel.ParentTable := VQuery.Fields[2].AsString;
      VRel.Source := SOURCE_FK;
      VRefKey := UpperCase(VQuery.Fields[3].AsString);
      if VKeys.TryGetValue(VRefKey, VKeyTable) and SameText(VKeyTable, VRel.ParentTable) then
        VRel.ParentKey := VQuery.Fields[3].AsString;
      VRel.ChildColumns := ColumnsOf(VColumns, VRel.Name);
      VRel.ParentColumns := ColumnsOf(VColumns, VRefKey);
      if VFkRows.TryGetValue(UpperCase(VRel.Name), VFkRow) then
      begin
        VRel.Name := VFkRow.Name;
        VRel.IsDefault := VFkRow.IsDefault;
      end;
      if VRel.ParentKey = '' then
        pSkipped := pSkipped + [VRel.Name + ': ' + VRel.ParentTable + ' has no PK / UNIQUE ' +
          VQuery.Fields[3].AsString + ' (not an edge)']
      else if not Result.AddRelation(VRel) then
        pSkipped := pSkipped + [VRel.Name + ': child and parent columns do not pair (not an edge)'];
      VQuery.Next;
    end;
    for VRow in VRows do
    begin
      if VRow.Source = SOURCE_FK then
        Continue;
      VRel := Default(TFrRelation);
      VRel.Name := VRow.Name;
      VRel.ChildTable := VRow.Child;
      VRel.ParentTable := VRow.Parent;
      VRel.Source := VRow.Source;
      VRel.IsDefault := VRow.IsDefault;
      VRel.ChildColumns := ColumnsOf(VRelChild, VRow.Name);
      VRel.ParentColumns := ColumnsOf(VRelParent, VRow.Name);
      if VKeys.TryGetValue(UpperCase(VRow.ParentKey), VKeyTable) and SameText(VKeyTable, VRow.Parent) and
        SameColumnSet(VRel.ParentColumns, ColumnsOf(VColumns, VRow.ParentKey)) then
        VRel.ParentKey := VRow.ParentKey;
      if VRel.ParentKey = '' then
        pSkipped := pSkipped + [VRel.Name + ': ' + VRel.ParentTable + ' columns are not the key ' + VRow.ParentKey +
          ' (not an edge)']
      else if not Result.AddRelation(VRel) then
        pSkipped := pSkipped + [VRel.Name + ': child and parent columns do not pair (not an edge)'];
    end;
  except
    Result.Free;
    raise;
  end;
  finally
    VQuery.Free;
    VFkRows.Free;
    VKeys.Free;
    VRelParent.Free;
    VRelChild.Free;
    VColumns.Free;
  end;
end;

function LoadTableKeys(pRepo: TFDConnection): TArray<TFrTableKey>;
var
  VColumns: TDictionary<string, TArray<string>>;
  VQuery: TFDQuery;
  VKey: TFrTableKey;
begin
  Result := nil;
  VColumns := TDictionary<string, TArray<string>>.Create;
  VQuery := TFDQuery.Create(nil);
  try
    ReadColumns(pRepo, VColumns);
    VQuery.Connection := pRepo;
    VQuery.Open(SQL_KEYS_ORDERED);
    while not VQuery.Eof do
    begin
      VKey.ConstraintName := VQuery.Fields[0].AsString;
      VKey.TableName := VQuery.Fields[1].AsString;
      VKey.Columns := ColumnsOf(VColumns, VKey.ConstraintName);
      Result := Result + [VKey];
      VQuery.Next;
    end;
  finally
    VQuery.Free;
    VColumns.Free;
  end;
end;

function LoadStoredRelationNames(pRepo: TFDConnection): TArray<string>;
var
  VRow: TFrRelationRow;
begin
  Result := nil;
  if RepoSchemaVersion(pRepo) < SCHEMA_WITH_RELATIONS then
    Exit;
  for VRow in ReadRelations(pRepo) do
    Result := Result + [UpperCase(VRow.Name)];
end;

end.
