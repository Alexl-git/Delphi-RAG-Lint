unit DRagLint.FieldRepo.DfmReadSelection;

{ drag-lint 1.54 -- lane TT-DFMREAD: the per-dataset field selection rules (design
  2026-11-22-field-repository-v2-design.md section 4.4). The selection itself lives in the DFM (its persistent
  fields); this unit is the pure rule the field-selection dialog uses. No repository, no I/O. }

interface

uses
  System.SysUtils,
  DRagLint.FieldRepo.Kinds;

type
  /// <summary>Raised by ExpandSelection for a field the table does not have (rule S5).</summary>
  EFrSelectionError = class(Exception);

  /// <summary>One field of the table as the selection rules see it.</summary>
  TFrSelectionField = record
    /// <summary>FIELD_NAME.</summary>
    Name: string;
    /// <summary>Field kind; calc, internal-calc and aggregate fields pull their dependencies in.</summary>
    Kind: TFrFieldKind;
    /// <summary>Lookup only: SOURCEKEY, the key field in the same table; '' otherwise.</summary>
    SourceKey: string;
    /// <summary>CALC_BODY; '' for a field without one.</summary>
    Body: string;
  end;

/// <summary>Adds to a selection every field the selected fields depend on.</summary>
/// <param name="pSelected">Selected field names (case-insensitive; duplicates allowed).</param>
/// <param name="pAllFieldsOfTable">Every field of the table.</param>
/// <returns>The expanded selection in the order of pAllFieldsOfTable, spelled as there, without duplicates.</returns>
/// <exception cref="EFrSelectionError">A selected field, or a field a selected body names, is not in the table.</exception>
/// <exception cref="EFrKindError">A selected body has a malformed macro.</exception>
/// <remarks>S1: a calc / internal-calc / aggregate field adds its CalcDependencies transitively (a cycle ends, it is
/// not an error here); a lookup field adds its SOURCEKEY. S2: the result always contains pSelected, so unselecting a
/// field removes nothing else. S3: expanding an expanded selection gives the same selection. Pure.</remarks>
function ExpandSelection(const pSelected: TArray<string>;
  const pAllFieldsOfTable: TArray<TFrSelectionField>): TArray<string>;

implementation

uses
  System.Generics.Collections;

function IndexOfField(const pFields: TArray<TFrSelectionField>; const pName: string): Integer;
var
  VI: Integer;
begin
  Result := -1;
  for VI := 0 to High(pFields) do
    if SameText(pFields[VI].Name, pName) then
      Exit(VI);
end;

function DependenciesOf(const pField: TFrSelectionField): TArray<string>;
begin
  Result := nil;
  if FrKindHasBody(pField.Kind) then
    Result := CalcDependencies(pField.Body, pField.Name)
  else if (pField.Kind = frkLookup) and (pField.SourceKey <> '') then
    Result := [pField.SourceKey];
end;

function ExpandSelection(const pSelected: TArray<string>;
  const pAllFieldsOfTable: TArray<TFrSelectionField>): TArray<string>;
var
  VTodo: TStack<string>;
  VIn: TArray<Boolean>;
  VName, VDep: string;
  VIdx: Integer;
begin
  Result := nil;
  SetLength(VIn, Length(pAllFieldsOfTable));
  VTodo := TStack<string>.Create;
  try
    for VName in pSelected do
      VTodo.Push(VName);
    while VTodo.Count > 0 do
    begin
      VName := VTodo.Pop;
      VIdx := IndexOfField(pAllFieldsOfTable, VName);
      if VIdx < 0 then
        raise EFrSelectionError.CreateFmt('unknown field: %s', [VName]);
      if VIn[VIdx] then
        Continue;
      VIn[VIdx] := True;
      for VDep in DependenciesOf(pAllFieldsOfTable[VIdx]) do
        VTodo.Push(VDep);
    end;
  finally
    VTodo.Free;
  end;
  for VIdx := 0 to High(VIn) do
    if VIn[VIdx] then
      Result := Result + [pAllFieldsOfTable[VIdx].Name];
end;

end.
