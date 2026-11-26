unit DRagLint.FieldRepo.DfmReadLinks;

{ drag-lint 1.55 -- lane XTABLE slice X3: the literal dataset links of a form unit (design
  docs\superpowers\specs\2026-11-26-cross-table-fields-design.md section 3.1): kbmMemTable `T.AttachTable(S...)` and the
  FireDAC copies `T.CloneCursor(S...)`, `T.CopyDataSet(S...)`, `T.CopyData(S)`, `T.AppendData(S)`, `T.Data := S.Data`, plus
  the field writes that make a copied field no copy any more. Pure: text in, records out; comments and strings are blanked
  first, so a comment inside the argument list is skipped. Arrays, locals, parameters and FindComponent are not followed: the receiver
  and the source must be a name, `Self.name` or `module.name`. }

interface

uses
  DRagLint.FieldRepo.DfmRead;

type
  /// <summary>How a dataset gets the rows of another one (design 3.1).</summary>
  TDfmrLinkKind = (dlkAttachedTo, dlkAttachTable, dlkCloneCursor, dlkCopyDataSet, dlkCopyData, dlkAppendData, dlkData);

  /// <summary>One link target -> source.</summary>
  TDfmrLink = record
    /// <summary>The call, the assignment or the DFM property.</summary>
    Kind: TDfmrLinkKind;
    /// <summary>The receiving dataset as written, `Self.` removed (`memA`, `dm.memA`).</summary>
    Target: string;
    /// <summary>The source dataset as written, `Self.` removed.</summary>
    Source: string;
    /// <summary>1-based line in the unit; 0 for the DFM property.</summary>
    Line: Integer;
  end;

/// <summary>The name a link kind has in reports: AttachedTo, AttachTable, CloneCursor, CopyDataSet, CopyData,
/// AppendData, Data.</summary>
/// <param name="pKind">The kind.</param>
/// <returns>The name.</returns>
function DfmrLinkKindName(pKind: TDfmrLinkKind): string;

/// <summary>True for the kinds that copy rows once (CopyDataSet, CopyData, AppendData, Data): a field written after
/// the copy is no copy (design 3.1); AttachedTo, AttachTable and CloneCursor share the source's data.</summary>
/// <param name="pKind">The kind.</param>
/// <returns>True for a copy.</returns>
function DfmrLinkIsCopy(pKind: TDfmrLinkKind): Boolean;

/// <summary>Every literal link call and `Data :=` assignment of a unit (design 3.1, "FireDAC copy sources").</summary>
/// <param name="pText">Unit source.</param>
/// <returns>The links in text order. A receiver or source that is an array element, a call result or a chain of more
/// than one qualifier is not a link.</returns>
function ReadCodeLinks(const pText: string): TArray<TDfmrLink>;

/// <summary>The fields of a dataset the unit writes: `D.FieldByName('F').X :=`, `D.FieldValues['F'] :=`,
/// `D['F'] :=` and `FieldComponent.X :=` (design 3.1: a copy keeps its origin only for the fields not written).</summary>
/// <param name="pText">Unit source.</param>
/// <param name="pDataset">Dataset component name.</param>
/// <param name="pFields">Its persistent fields: Name = component name, Value = FieldName.</param>
/// <returns>Name = upper-case FieldName, Value = the 1-based line of the first write, as text.</returns>
function ReadFieldWrites(const pText, pDataset: string; const pFields: TArray<TDfmrPair>): TArray<TDfmrPair>;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.RegularExpressions,
  DRagLint.FieldRepo.HandlersRegions;

const
  KIND_NAMES: array[TDfmrLinkKind] of string = ('AttachedTo', 'AttachTable', 'CloneCursor', 'CopyDataSet', 'CopyData',
    'AppendData', 'Data');
  SELF_PREFIX = 'Self.';
  { receiver [qualifier.]name, then the method, then the first argument [qualifier.]name followed by , or ) }
  PAT_CALL = '(?<![\w\].\[)])(?:(\w+)\s*\.\s*)?(\w+)\s*\.\s*(AttachTable|CloneCursor|CopyDataSet|CopyData|AppendData)' +
    '\s*\(\s*(?:(\w+)\s*\.\s*)?(\w+)\s*[,)]';
  PAT_DATA = '(?<![\w\].\[)])(?:(\w+)\s*\.\s*)?(\w+)\s*\.\s*Data\s*:=\s*(?:(\w+)\s*\.\s*)?(\w+)\s*\.\s*Data\s*;';
  GROUP_RECV_Q = 1;
  GROUP_RECV = 2;
  GROUP_METHOD = 3;
  GROUP_DATA_SRC_Q = 3;
  GROUP_DATA_SRC = 4;
  GROUP_SRC_Q = 4;
  GROUP_SRC = 5;

function DfmrLinkKindName(pKind: TDfmrLinkKind): string;
begin
  Result := KIND_NAMES[pKind];
end;

function DfmrLinkIsCopy(pKind: TDfmrLinkKind): Boolean;
begin
  Result := pKind in [dlkCopyDataSet, dlkCopyData, dlkAppendData, dlkData];
end;

function LineAt(const pText: string; pPos: Integer): Integer;
var
  VI: Integer;
begin
  Result := 1;
  for VI := 1 to pPos - 1 do
    if pText[VI] = #10 then
      Inc(Result);
end;

{ `q.name` or `name`; `Self.` is dropped. }
function Qualified(const pQualifier, pName: string): string;
begin
  Result := if (pQualifier = '') or SameText(pQualifier, Copy(SELF_PREFIX, 1, Length(SELF_PREFIX) - 1)) then pName
    else pQualifier + '.' + pName;
end;

function ReadCodeLinks(const pText: string): TArray<TDfmrLink>;
var
  VCode: string;
  VMatch: TMatch;
  VLink: TDfmrLink;
  VKind: TDfmrLinkKind;
begin
  Result := nil;
  VCode := ScanPascal(pText).Code;
  for VMatch in TRegEx.Matches(VCode, PAT_CALL, [roIgnoreCase]) do
  begin
    VLink.Kind := dlkAttachTable;
    for VKind := Low(TDfmrLinkKind) to High(TDfmrLinkKind) do
      if SameText(KIND_NAMES[VKind], VMatch.Groups[GROUP_METHOD].Value) then
        VLink.Kind := VKind;
    VLink.Target := Qualified(VMatch.Groups[GROUP_RECV_Q].Value, VMatch.Groups[GROUP_RECV].Value);
    VLink.Source := Qualified(VMatch.Groups[GROUP_SRC_Q].Value, VMatch.Groups[GROUP_SRC].Value);
    VLink.Line := LineAt(VCode, VMatch.Index);
    Result := Result + [VLink];
  end;
  for VMatch in TRegEx.Matches(VCode, PAT_DATA, [roIgnoreCase]) do
  begin
    VLink.Kind := dlkData;
    VLink.Target := Qualified(VMatch.Groups[GROUP_RECV_Q].Value, VMatch.Groups[GROUP_RECV].Value);
    VLink.Source := Qualified(VMatch.Groups[GROUP_DATA_SRC_Q].Value, VMatch.Groups[GROUP_DATA_SRC].Value);
    VLink.Line := LineAt(VCode, VMatch.Index);
    Result := Result + [VLink];
  end;
end;

procedure AddWrite(var pOut: TArray<TDfmrPair>; const pField: string; pLine: Integer);
var
  VPair: TDfmrPair;
begin
  for VPair in pOut do
    if SameText(VPair.Name, pField) then
      Exit;
  VPair.Name := UpperCase(pField);
  VPair.Value := IntToStr(pLine);
  pOut := pOut + [VPair];
end;

{ The text of a string literal argument (the original text at the blanked offsets), quotes removed. }
function LiteralAt(const pText: string; pPos, pLen: Integer): string;
begin
  Result := Trim(Copy(pText, pPos, pLen));
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
    Result := Copy(Result, 2, Length(Result) - 2)
  else
    Result := '';
end;

function ReadFieldWrites(const pText, pDataset: string; const pFields: TArray<TDfmrPair>): TArray<TDfmrPair>;
const
  ASSIGN = '\s*:=';
var
  VCode, VName: string;
  VMatch: TMatch;
  VField: TDfmrPair;
  VDs: string;
begin
  Result := nil;
  if pDataset = '' then
    Exit;
  VCode := ScanPascal(pText).Code;
  VDs := '(?<![\w.])(?:Self\s*\.\s*)?' + TRegEx.Escape(pDataset) + '\s*';
  for VMatch in TRegEx.Matches(VCode, VDs + '\.\s*FieldByName\s*\(([^()]*)\)\s*\.\s*\w+' + ASSIGN, [roIgnoreCase]) do
  begin
    VName := LiteralAt(pText, VMatch.Groups[1].Index, VMatch.Groups[1].Length);
    if VName <> '' then
      AddWrite(Result, VName, LineAt(VCode, VMatch.Index));
  end;
  for VMatch in TRegEx.Matches(VCode, VDs + '(?:\.\s*FieldValues\s*)?\[([^\[\]]*)\]' + ASSIGN, [roIgnoreCase]) do
  begin
    VName := LiteralAt(pText, VMatch.Groups[1].Index, VMatch.Groups[1].Length);
    if VName <> '' then
      AddWrite(Result, VName, LineAt(VCode, VMatch.Index));
  end;
  if Length(pFields) = 0 then
    Exit;
  for VMatch in TRegEx.Matches(VCode, '(?<![\w.])(?:Self\s*\.\s*)?(\w+)\s*\.\s*\w+' + ASSIGN) do
    for VField in pFields do
      if SameText(VField.Name, VMatch.Groups[1].Value) then
        AddWrite(Result, VField.Value, LineAt(VCode, VMatch.Index));
end;

end.
