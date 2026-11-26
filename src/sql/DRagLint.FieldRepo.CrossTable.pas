unit DRagLint.FieldRepo.CrossTable;

{ drag-lint 1.55 -- lane XTABLE slice X1: inputs of a field that come from other tables (design
  docs\superpowers\specs\2026-11-26-cross-table-fields-design.md sections 2.2 and 2.4). Pure functions: no
  repository connection, no I/O; the caller hands the bodies and the input aliases in. }

interface

uses
  System.SysUtils;

type
  /// <summary>One DL_FIELD_INPUTS row: an input alias of a field and the path it follows (design 2.2).</summary>
  TFrFieldInput = record
    /// <summary>Home table of the field (T1).</summary>
    TableName: string;
    /// <summary>The field whose body uses the alias.</summary>
    FieldName: string;
    /// <summary>'' = the default binding; `FORM.DATASET` = an override for one dataset.</summary>
    Binding: string;
    /// <summary>The name used in `{{ALIAS.FIELD}}`.</summary>
    Alias: string;
    /// <summary>Relation names from the home table, separated by REPO_PATH_SEPARATOR; '' = the home table itself.</summary>
    Path: string;
    /// <summary>The table at the end of Path.</summary>
    TargetTable: string;
  end;

  /// <summary>One field a selected field needs, with the path that reaches its table from the selected field's home
  /// table ('' = the home table).</summary>
  TFrNeed = record
    /// <summary>Relation names from the home table, separated by REPO_PATH_SEPARATOR.</summary>
    Path: string;
    /// <summary>The table the field belongs to.</summary>
    TableName: string;
    /// <summary>The needed field, as the body wrote it.</summary>
    FieldName: string;
  end;

  /// <summary>Returns the CALC_BODY of a field, '' when it has none.</summary>
  TFrBodyFunc = reference to function(const pTable, pField: string): string;
  /// <summary>Returns the input aliases of a field's DEFAULT binding.</summary>
  TFrInputsFunc = reference to function(const pTable, pField: string): TArray<TFrFieldInput>;

/// <summary>Concatenates two input paths (design 2.4: a parent's own inputs are reached through the path to the
/// parent, then the parent's path).</summary>
/// <param name="pFirst">Path from the home table; '' = the home table.</param>
/// <param name="pSecond">Path that starts where pFirst ends; '' = no further step.</param>
/// <returns>`pFirst>pSecond`, or the one that is not empty.</returns>
function JoinInputPath(const pFirst, pSecond: string): string;  // dl:ok unused-public-symbol@3517 -- REVIEWED 2026-11-26 XTABLE: public API of the X1 rule unit, called by tests\fieldrepo\CrossTableTests.dpr (outside this index) and by later slices (X3 read-dfm, the 1.56 dialog)

/// <summary>The relation names of an input path.</summary>
/// <param name="pPath">A DL_FIELD_INPUTS.PATH value.</param>
/// <returns>The names in order, blanks trimmed; an empty array for ''.</returns>
function SplitInputPath(const pPath: string): TArray<string>;

/// <summary>The alias names of a list of input rows, in order.</summary>
/// <param name="pInputs">Input rows of one field and binding.</param>
/// <returns>One alias per row.</returns>
function InputAliases(const pInputs: TArray<TFrFieldInput>): TArray<string>;  // dl:ok unused-public-symbol@56c8 -- REVIEWED 2026-11-26 XTABLE: public API of the X1 rule unit, called by tests\fieldrepo\CrossTableTests.dpr (outside this index) and by later slices (X3 read-dfm, the 1.56 dialog)

/// <summary>Every field a field needs, transitively, own and foreign (design 2.4, rule N7): selecting it brings
/// these too.</summary>
/// <param name="pTable">Home table of the selected field.</param>
/// <param name="pField">The selected field.</param>
/// <param name="pBodyOf">Body of any field; a field without a body needs nothing.</param>
/// <param name="pInputsOf">Default-binding input aliases of any field.</param>
/// <returns>Distinct needs (path + table + field, case-insensitive) in depth-first order of discovery; the selected
/// field itself is not in it.</returns>
/// <exception cref="EFrKindError">A body has a malformed macro; EFrAliasError when it names an alias its field does not
/// declare.</exception>
/// <remarks>A parent's calc field brings its own inputs with the paths concatenated, so a need's path may be longer
/// than any searched path. Cycle guard over (table, field) on the current chain: A.X -> B.Y -> A.X stops at the second
/// A.X, which is still listed once.</remarks>
function CrossTableClosure(const pTable, pField: string; const pBodyOf: TFrBodyFunc;  // dl:ok unused-public-symbol@1fdd -- REVIEWED 2026-11-26 XTABLE: public API of the X1 rule unit, called by tests\fieldrepo\CrossTableTests.dpr (outside this index) and by later slices (X3 read-dfm, the 1.56 dialog)
  const pInputsOf: TFrInputsFunc): TArray<TFrNeed>;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  DRagLint.FieldRepo.Schema,
  DRagLint.FieldRepo.Kinds;

function JoinInputPath(const pFirst, pSecond: string): string;
begin
  if pFirst = '' then
    Result := pSecond
  else if pSecond = '' then
    Result := pFirst
  else
    Result := pFirst + REPO_PATH_SEPARATOR + pSecond;
end;

function SplitInputPath(const pPath: string): TArray<string>;
var
  VPart: string;
begin
  Result := nil;
  for VPart in pPath.Split([REPO_PATH_SEPARATOR]) do
    if Trim(VPart) <> '' then
      Result := Result + [Trim(VPart)];
end;

function InputAliases(const pInputs: TArray<TFrFieldInput>): TArray<string>;
var
  VInput: TFrFieldInput;
begin
  Result := nil;
  for VInput in pInputs do
    Result := Result + [VInput.Alias];
end;

function FieldKey(const pTable, pField: string): string;
begin
  Result := UpperCase(pTable) + '.' + UpperCase(pField);
end;

function CrossTableClosure(const pTable, pField: string; const pBodyOf: TFrBodyFunc;
  const pInputsOf: TFrInputsFunc): TArray<TFrNeed>;
var
  VSeen: TDictionary<string, Boolean>;
  VChain: TList<string>;
  VNeeds: TList<TFrNeed>;

  procedure Visit(const pPath, pHome, pName: string);
  var
    VBody, VSeenKey: string;
    VRows: TArray<TFrFieldInput>;
    VRow: TFrFieldInput;
    VInput: TFrInput;
    VNeed: TFrNeed;
  begin
    VBody := pBodyOf(pHome, pName);
    if VBody = '' then
      Exit;
    VRows := pInputsOf(pHome, pName);
    VChain.Add(FieldKey(pHome, pName));
    try
      for VInput in CalcInputs(VBody, pName, InputAliases(VRows)) do
      begin
        VNeed.Path := pPath;
        VNeed.TableName := pHome;
        VNeed.FieldName := VInput.Field;
        if VInput.Alias <> '' then
          for VRow in VRows do
            if SameText(VRow.Alias, VInput.Alias) then
            begin
              VNeed.Path := JoinInputPath(pPath, VRow.Path);
              VNeed.TableName := VRow.TargetTable;
              Break;
            end;
        if (VNeed.Path = '') and SameText(FieldKey(VNeed.TableName, VNeed.FieldName), FieldKey(pTable, pField)) then
          Continue;
        VSeenKey := UpperCase(VNeed.Path) + '|' + FieldKey(VNeed.TableName, VNeed.FieldName);
        if VSeen.ContainsKey(VSeenKey) then
          Continue;
        VSeen.Add(VSeenKey, True);
        VNeeds.Add(VNeed);
        if VChain.IndexOf(FieldKey(VNeed.TableName, VNeed.FieldName)) < 0 then
          Visit(VNeed.Path, VNeed.TableName, VNeed.FieldName);
      end;
    finally
      VChain.Delete(VChain.Count - 1);
    end;
  end;

begin
  VSeen := TDictionary<string, Boolean>.Create;
  VChain := TList<string>.Create;
  VNeeds := TList<TFrNeed>.Create;
  try
    Visit('', pTable, pField);
    Result := VNeeds.ToArray;
  finally
    VNeeds.Free;
    VChain.Free;
    VSeen.Free;
  end;
end;

end.
