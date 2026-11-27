unit DRagLint.FieldRepo.WikiGen;

{ drag-lint 1.56 -- lane WIKIGEN: generated concept pages (one page per table, a section per field), written only by
  `repo gen-wiki` (DRagLint.CLI.RepoWiki). Spec: three-place search / caption concepts design, section 2.9 (CC-3).
  Reads the live repository and, when there is one, the project index (concept_texts / concept_links) for the
  "where shown / edited / used" sections. Rendering is pure and deterministic: sorted, no time stamp, 7-bit ASCII
  (a non-ASCII character is written as an HTML numeric entity), CRLF. }

interface

uses
  FireDAC.Comp.Client;

type
  /// <summary>The section a project link is listed under on a field's page.</summary>
  TWikiLinkGroup = (wlgShown, wlgEdited, wlgCode, wlgByName);

  /// <summary>One "where" row of a field: a grid column, an edit control, a persistent field or a code site.</summary>
  TWikiLink = record
    /// <summary>The section this row belongs to.</summary>
    Group: TWikiLinkGroup;
    /// <summary>Human text of the row, e.g. `grid column colName in TfrmMain`.</summary>
    Text: string;
    /// <summary>File name only (no folder), so a page does not carry a machine path.</summary>
    FileName: string;
    /// <summary>1-based line; 0 = unknown.</summary>
    Line: Integer;
  end;

  /// <summary>One repository field with everything its section prints.</summary>
  TWikiField = record
    /// <summary>Repository table, upper case as stored.</summary>
    TableName: string;
    /// <summary>Repository field name as stored.</summary>
    FieldName: string;
    /// <summary>DISPLAY_LABEL; '' when none (the section heading then falls back to the field name).</summary>
    Caption: string;
    /// <summary>VAR_TYPE, else FIELD_AS_TYPE.</summary>
    TypeText: string;
    /// <summary>data, calculated, lookup, internal calculated, aggregate or graphical.</summary>
    Kind: string;
    /// <summary>DOC_SUMMARY without the untouched default.</summary>
    Summary: string;
    /// <summary>DOC_REMARKS without the untouched default.</summary>
    Remarks: string;
    /// <summary>DOCUMENTATION.</summary>
    Documentation: string;
    /// <summary>NOTES (schema 5) when the repository has the column.</summary>
    Notes: string;
    /// <summary>Other caption-class texts of the project (DFM DisplayLabel / grid caption) that differ from Caption.</summary>
    AlsoShownAs: TArray<string>;
    /// <summary>Project rows, sorted by group, file, line; empty without a project index.</summary>
    Links: TArray<TWikiLink>;
    /// <summary>How many repository tables have a field of this name (the by-name-only candidateTables).</summary>
    CandidateTables: Integer;
  end;

  /// <summary>One repository table: its description and its fields sorted by name.</summary>
  TWikiTable = record
    /// <summary>Table name.</summary>
    Name: string;
    /// <summary>DL_DATASETS_INFO.DESCRIPTION of the dataset whose UPDATE_TABLE_NAME is this table; '' when none.</summary>
    Description: string;
    /// <summary>Fields sorted by upper-cased name.</summary>
    Fields: TArray<TWikiField>;
  end;

  /// <summary>One generated page.</summary>
  TWikiPage = record
    /// <summary>File name, no folder: `TABLE.md` or `TABLE.FIELD.md`.</summary>
    FileName: string;
    /// <summary>Complete 7-bit ASCII text, CRLF line ends.</summary>
    Text: string;
  end;

const
  /// <summary>First line of every generated page; `repo gen-wiki` recognises its own pages by this prefix (stale pages).</summary>
  WIKI_PAGE_MARK = '<!-- dl:wikigen ';
  /// <summary>By-name-only rows are printed only when at most this many repository tables have the field name.</summary>
  WIKI_BYNAME_ROW_CAP = 5;

/// <summary>Reads the repository into table / field records (no project data).</summary>
/// <param name="pRepo">Open repository connection (read only is enough).</param>
/// <param name="pOnly">Upper-case table names to keep; empty = all tables.</param>
/// <returns>Tables sorted by name; CandidateTables is counted over ALL repository tables, before the filter.</returns>
/// <remarks>Optional columns (NOTES, DOMAIN_NAME) are used when the repository has them.</remarks>
function LoadWikiTables(pRepo: TFDConnection; const pOnly: TArray<string>): TArray<TWikiTable>;

/// <summary>True when the project index has the concept tables.</summary>
/// <param name="pProject">Open project index connection.</param>
/// <returns>True when the concept tables exist.</returns>
function WikiProjectHasConcepts(pProject: TFDConnection): Boolean;

/// <summary>Reads the stored hash and copy time of the repository copy in a project index.</summary>
/// <param name="pProject">Open project index connection.</param>
/// <param name="pSha">Receives repo_copy.repo_sha256.</param>
/// <param name="pCopiedAt">Receives repo_copy.copied_at_unix.</param>
/// <returns>False when there is no repo_copy row.</returns>
function WikiRepoCopyState(pProject: TFDConnection; out pSha: string; out pCopiedAt: Int64): Boolean;

/// <summary>Fills AlsoShownAs and Links of every field from the project index.</summary>
/// <param name="pProject">Open project index connection with the concept tables.</param>
/// <param name="pTables">Tables from LoadWikiTables; updated in place.</param>
procedure AttachWikiProject(pProject: TFDConnection; var pTables: TArray<TWikiTable>);

/// <summary>Renders the pages.</summary>
/// <param name="pTables">Tables, as filled.</param>
/// <param name="pPerField">False: one page per table. True: one page per field and the table page is an index.</param>
/// <returns>Pages in a stable order (table page, then its field pages).</returns>
function BuildWikiPages(const pTables: TArray<TWikiTable>; pPerField: Boolean): TArray<TWikiPage>;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  Data.DB,
  DRagLint.FieldRepo.Schema;  // dl:ok uses-global-census@7cd7 -- the named constants are the whole contract this unit draws; the unit pair travels together

const
  CRLF = #13#10;
  ASCII_MAX = 126;
  DEFAULT_SUMMARY = 'Summary here';
  DEFAULT_REMARKS = 'Remarks here';
  KIND_CALC = 2;
  KIND_LOOKUP = 3;
  KIND_INTERNAL = 4;
  KIND_AGGREGATE = 5;
  KIND_GRAPHICAL = 10;
  CONF_BYNAME = 'by-name-only';
  CONCEPT_TABLES_NEEDED = 3;
  GROUP_TITLES: array[TWikiLinkGroup] of string = ('Shown in', 'Edited in', 'Used by code', 'By name only');

function WikiAscii(const pText: string): string;
var
  VCh: Char;
  VB: TStringBuilder;
begin
  VB := TStringBuilder.Create;
  try
    for VCh in pText do
      if Ord(VCh) > ASCII_MAX then
        VB.Append('&#').Append(Ord(VCh)).Append(';')
      else
        VB.Append(VCh);
    Result := VB.ToString;
  finally
    VB.Free;
  end;
end;

{ Trims and collapses every run of white space (incl. line breaks) to one blank. }
function OneLine(const pText: string): string;
var
  VCh: Char;
  VB: TStringBuilder;
  VGap: Boolean;
begin
  VB := TStringBuilder.Create;
  try
    VGap := False;
    for VCh in pText do
      if (VCh <= ' ') then
        VGap := VB.Length > 0
      else
      begin
        if VGap then VB.Append(' ');
        VGap := False;
        VB.Append(VCh);
      end;
    Result := VB.ToString;
  finally
    VB.Free;
  end;
end;

{ Prose: line ends become CRLF, outer white space is trimmed. }
function Prose(const pText: string): string;
begin
  Result := Trim(pText).Replace(#13#10, #10).Replace(#13, #10).Replace(#10, CRLF);
end;

function Fld(pQuery: TFDQuery; const pName: string): string;
var
  VField: TField;
begin
  VField := pQuery.FindField(pName);
  Result := '';
  if (VField <> nil) and not VField.IsNull then Result := VField.AsString;
end;

function FldInt(pQuery: TFDQuery; const pName: string; pDefault: Integer): Integer;
var
  VField: TField;
begin
  VField := pQuery.FindField(pName);
  Result := pDefault;
  if (VField <> nil) and not VField.IsNull then
    Result := if VField.DataType = ftBoolean then Ord(VField.AsBoolean) else VField.AsInteger;
end;

function KindText(pQuery: TFDQuery): string;
begin
  case FldInt(pQuery, 'FIELD_KIND', 1) of
    KIND_CALC: Result := 'calculated';
    KIND_LOOKUP: Result := 'lookup';
    KIND_INTERNAL: Result := 'internal calculated';
    KIND_AGGREGATE: Result := 'aggregate';
    KIND_GRAPHICAL: Result := 'graphical';
  else
    if FldInt(pQuery, 'ISLOOKUP', 0) <> 0 then Result := 'lookup'
    else if FldInt(pQuery, 'ISCALCULATED', 0) <> 0 then Result := 'calculated'
    else Result := 'data';
  end;
end;

function SkipDefault(const pText, pDefault: string): string;
begin
  Result := Trim(pText);
  if SameText(Result, pDefault) then Result := '';
end;

function CompareUpper(const pLeft, pRight: string): Integer;
begin
  Result := CompareStr(UpperCase(pLeft), UpperCase(pRight));
end;

procedure ReadDescriptions(pRepo: TFDConnection; pTables: TDictionary<string, TWikiTable>);
var
  VQuery: TFDQuery;
  VTable: TWikiTable;
begin
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pRepo;
    VQuery.SQL.Text := 'SELECT UPDATE_TABLE_NAME, DESCRIPTION FROM DL_DATASETS_INFO ORDER BY DS_ID';
    VQuery.Open;
    while not VQuery.Eof do
    begin
      if pTables.TryGetValue(UpperCase(Trim(Fld(VQuery, 'UPDATE_TABLE_NAME'))), VTable) and (VTable.Description = '') then
      begin
        VTable.Description := OneLine(Fld(VQuery, 'DESCRIPTION'));
        pTables.AddOrSetValue(UpperCase(VTable.Name), VTable);
      end;
      VQuery.Next;
    end;
  finally
    VQuery.Free;
  end;
end;

function LoadWikiTables(pRepo: TFDConnection; const pOnly: TArray<string>): TArray<TWikiTable>;
var
  VQuery: TFDQuery;
  VMap: TDictionary<string, TWikiTable>;
  VFields: TDictionary<string, TList<TWikiField>>;
  VNames: TDictionary<string, Integer>;
  VList: TList<TWikiField>;
  VField: TWikiField;
  VTable: TWikiTable;
  VKey, VOnly: string;
  VKeep: Boolean;
  VOut: TList<TWikiTable>;
  I, VCount: Integer;
begin
  VMap := TDictionary<string, TWikiTable>.Create;
  VFields := TDictionary<string, TList<TWikiField>>.Create;
  VNames := TDictionary<string, Integer>.Create;
  VOut := TList<TWikiTable>.Create;
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pRepo;
    VQuery.SQL.Text := 'SELECT * FROM DL_FIELDS_INFO';
    VQuery.Open;
    while not VQuery.Eof do
    begin
      VField := Default(TWikiField);
      VField.TableName := Trim(Fld(VQuery, 'TABLE_NAME'));
      VField.FieldName := Trim(Fld(VQuery, 'FIELD_NAME'));
      VField.Caption := OneLine(Fld(VQuery, 'DISPLAY_LABEL'));
      VField.TypeText := OneLine(Fld(VQuery, 'VAR_TYPE'));
      if VField.TypeText = '' then VField.TypeText := OneLine(Fld(VQuery, 'FIELD_AS_TYPE'));
      VField.Kind := KindText(VQuery);
      VField.Summary := SkipDefault(Fld(VQuery, 'DOC_SUMMARY'), DEFAULT_SUMMARY);
      VField.Remarks := SkipDefault(Fld(VQuery, 'DOC_REMARKS'), DEFAULT_REMARKS);
      VField.Documentation := Trim(Fld(VQuery, 'DOCUMENTATION'));
      VField.Notes := Trim(Fld(VQuery, REPO_COL_NOTES));
      VKey := UpperCase(VField.TableName);
      if not VMap.ContainsKey(VKey) then
      begin
        VTable := Default(TWikiTable);
        VTable.Name := VField.TableName;
        VMap.Add(VKey, VTable);
        VFields.Add(VKey, TList<TWikiField>.Create);
      end;
      VFields[VKey].Add(VField);
      VKey := UpperCase(VField.FieldName);
      VCount := 0;
      VNames.TryGetValue(VKey, VCount);
      VNames.AddOrSetValue(VKey, VCount + 1);
      VQuery.Next;
    end;
    VQuery.Close;
    ReadDescriptions(pRepo, VMap);
    for VKey in VMap.Keys do
    begin
      VKeep := Length(pOnly) = 0;
      for VOnly in pOnly do
        if SameText(VOnly, VKey) then VKeep := True;
      if not VKeep then Continue;
      VTable := VMap[VKey];
      VList := VFields[VKey];
      VList.Sort(TComparer<TWikiField>.Construct(
        function(const pLeft, pRight: TWikiField): Integer
        begin
          Result := CompareUpper(pLeft.FieldName, pRight.FieldName);
        end));
      VTable.Fields := VList.ToArray;
      for I := 0 to High(VTable.Fields) do
        VTable.Fields[I].CandidateTables := VNames[UpperCase(VTable.Fields[I].FieldName)];
      VOut.Add(VTable);
    end;
    VOut.Sort(TComparer<TWikiTable>.Construct(
      function(const pLeft, pRight: TWikiTable): Integer
      begin
        Result := CompareUpper(pLeft.Name, pRight.Name);
      end));
    Result := VOut.ToArray;
  finally
    VQuery.Free;
    for VList in VFields.Values do VList.Free;
    VOut.Free;
    VNames.Free;
    VFields.Free;
    VMap.Free;
  end;
end;

function ScalarInt(pConn: TFDConnection; const pSql: string): Integer;
var
  VQuery: TFDQuery;
begin
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pConn;
    VQuery.SQL.Text := pSql;
    VQuery.Open;
    Result := VQuery.Fields[0].AsInteger;
  finally
    VQuery.Free;
  end;
end;

function WikiProjectHasConcepts(pProject: TFDConnection): Boolean;
begin
  Result := ScalarInt(pProject, 'SELECT COUNT(*) FROM sqlite_master WHERE type = ''table'' AND name IN '
    + '(''repo_copy'', ''concept_texts'', ''concept_links'')') = CONCEPT_TABLES_NEEDED;
end;

function WikiRepoCopyState(pProject: TFDConnection; out pSha: string; out pCopiedAt: Int64): Boolean;
var
  VQuery: TFDQuery;
begin
  pSha := '';
  pCopiedAt := 0;
  VQuery := TFDQuery.Create(nil);
  try
    VQuery.Connection := pProject;
    VQuery.SQL.Text := 'SELECT repo_sha256, copied_at_unix FROM repo_copy WHERE id = 1';
    VQuery.Open;
    Result := not VQuery.Eof;
    if Result then
    begin
      pSha := VQuery.FieldByName('repo_sha256').AsString;
      pCopiedAt := VQuery.FieldByName('copied_at_unix').AsLargeInt;
    end;
  finally
    VQuery.Free;
  end;
end;

function LinkText(const pKind, pComponent, pForm, pDataset, pEnclosing: string): string;
var
  VWhere: string;
begin
  VWhere := '';
  if pForm <> '' then VWhere := ' in ' + pForm;
  if pKind = 'grid-column' then Result := 'grid column ' + pComponent + VWhere
  else if pKind = 'edit-control' then Result := 'edit control ' + pComponent + VWhere
  else if pKind = 'persistent-field' then Result := 'persistent field ' + pComponent + VWhere
  else
  begin
    Result := 'code';
    if pEnclosing <> '' then Result := Result + ' ' + pEnclosing;
  end;
  if (pDataset <> '') and (pKind <> 'code') then Result := Result + ' (dataset ' + pDataset + ')';
end;

function GroupOf(const pKind, pConfidence: string): TWikiLinkGroup;
begin
  if pConfidence = CONF_BYNAME then Result := wlgByName
  else if pKind = 'grid-column' then Result := wlgShown
  else if (pKind = 'edit-control') or (pKind = 'persistent-field') then Result := wlgEdited
  else Result := wlgCode;
end;

function CompareLink(const pLeft, pRight: TWikiLink): Integer;
begin
  Result := Ord(pLeft.Group) - Ord(pRight.Group);
  if Result = 0 then Result := CompareStr(UpperCase(pLeft.FileName), UpperCase(pRight.FileName));
  if Result = 0 then Result := pLeft.Line - pRight.Line;
  if Result = 0 then Result := CompareStr(pLeft.Text, pRight.Text);
end;

function ReadLinks(pProject: TFDConnection; const pTable, pField: string; pByName: Boolean): TArray<TWikiLink>;
const
  SQL_HEAD = 'SELECT l.link_kind, l.confidence, l.form_name, l.component_name, l.dataset_name, l.line, '
    + 'f.path, s.name AS encl FROM concept_links l LEFT JOIN files f ON f.id = l.file_id '
    + 'LEFT JOIN symbols s ON s.id = l.enclosing_symbol_id WHERE ';
var
  VQuery: TFDQuery;
  VList: TList<TWikiLink>;
  VLink: TWikiLink;
  VKind, VForm: string;
begin
  VQuery := TFDQuery.Create(nil);
  VList := TList<TWikiLink>.Create;
  try
    VQuery.Connection := pProject;
    if pByName then
    begin
      VQuery.SQL.Text := SQL_HEAD + 'l.field_name = :f AND l.confidence = ''by-name-only''';
      VQuery.ParamByName('f').AsString := pField;
    end
    else
    begin
      VQuery.SQL.Text := SQL_HEAD + 'l.table_name = :t AND l.field_name = :f AND l.confidence <> ''by-name-only''';
      VQuery.ParamByName('t').AsString := pTable;
      VQuery.ParamByName('f').AsString := pField;
    end;
    VQuery.Open;
    while not VQuery.Eof do
    begin
      VKind := Fld(VQuery, 'link_kind');
      VForm := Fld(VQuery, 'form_name');
      VLink.Group := GroupOf(VKind, Fld(VQuery, 'confidence'));
      VLink.Text := LinkText(VKind, Fld(VQuery, 'component_name'), VForm, Fld(VQuery, 'dataset_name'), Fld(VQuery, 'encl'));
      VLink.FileName := ExtractFileName(StringReplace(Fld(VQuery, 'path'), '/', '\', [rfReplaceAll]));
      VLink.Line := FldInt(VQuery, 'line', 0);
      VList.Add(VLink);
      if (VForm <> '') and not pByName and (VKind <> 'code') and (VLink.Group <> wlgShown) then
      begin
        VLink.Group := wlgShown;
        VLink.Text := 'form ' + VForm;
        VLink.Line := 0;
        VList.Add(VLink);
      end;
      VQuery.Next;
    end;
    Result := VList.ToArray;
  finally
    VList.Free;
    VQuery.Free;
  end;
end;

function ReadAlsoShown(pProject: TFDConnection; const pTable, pField, pCaption: string): TArray<string>;
var
  VQuery: TFDQuery;
  VList: TList<string>;
  VText: string;
begin
  VQuery := TFDQuery.Create(nil);
  VList := TList<string>.Create;
  try
    VQuery.Connection := pProject;
    VQuery.SQL.Text := 'SELECT DISTINCT text FROM concept_texts WHERE table_name = :t AND field_name = :f '
      + 'AND text_kind IN (''display-label'', ''grid-caption'') ORDER BY text';
    VQuery.ParamByName('t').AsString := pTable;
    VQuery.ParamByName('f').AsString := pField;
    VQuery.Open;
    while not VQuery.Eof do
    begin
      VText := OneLine(VQuery.Fields[0].AsString);
      if (VText <> '') and not SameText(VText, pCaption) and not VList.Contains(VText) then VList.Add(VText);
      VQuery.Next;
    end;
    VList.Sort(TComparer<string>.Construct(
      function(const pLeft, pRight: string): Integer
      begin
        Result := CompareUpper(pLeft, pRight);
      end));
    Result := VList.ToArray;
  finally
    VList.Free;
    VQuery.Free;
  end;
end;

procedure AttachWikiProject(pProject: TFDConnection; var pTables: TArray<TWikiTable>);
var
  I, J, K: Integer;
  VLinks: TList<TWikiLink>;
begin
  VLinks := TList<TWikiLink>.Create;
  try
    for I := 0 to High(pTables) do
      for J := 0 to High(pTables[I].Fields) do
      begin
        VLinks.Clear;
        VLinks.AddRange(ReadLinks(pProject, pTables[I].Name, pTables[I].Fields[J].FieldName, False));
        VLinks.AddRange(ReadLinks(pProject, pTables[I].Name, pTables[I].Fields[J].FieldName, True));
        VLinks.Sort(TComparer<TWikiLink>.Construct(
          function(const pLeft, pRight: TWikiLink): Integer
          begin
            Result := CompareLink(pLeft, pRight);
          end));
        for K := VLinks.Count - 1 downto 1 do
          if CompareLink(VLinks[K], VLinks[K - 1]) = 0 then VLinks.Delete(K);
        pTables[I].Fields[J].Links := VLinks.ToArray;
        pTables[I].Fields[J].AlsoShownAs := ReadAlsoShown(pProject, pTables[I].Name, pTables[I].Fields[J].FieldName,  // dl:ok query-in-loop@1360 -- REVIEWED LINTFIX-B 2026-11-27: one lookup per repository field of a wiki run; a set query would need the per-field caption match done in SQL
          pTables[I].Fields[J].Caption);
      end;
  finally
    VLinks.Free;
  end;
end;

{ ---- rendering ---- }

function Heading(const pField: TWikiField): string;
begin
  Result := if pField.Caption <> '' then pField.Caption else pField.FieldName;
end;

function AnchorOf(const pField: TWikiField): string;
begin
  Result := LowerCase(pField.FieldName);
end;

{ The dl:wiki block of one section, in the authoring format of docs\wiki\Wiki-Blocks-Authoring.md, inside an HTML
  comment (assumption W-1: the 1.55 wiki verb reads `///` comment lines of Pascal sources only, so a block in a
  Markdown file is a marker for a reader that copies it, not read by `wiki` today). }
function JoinAliases(pList: TStringList): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to pList.Count - 1 do
    Result := Result + (if I > 0 then ', ' else '') + pList[I];
end;

procedure AddWikiBlock(pOut: TStringBuilder; const pField: TWikiField);
var
  VAliases: TStringList;
  VText: string;
begin
  VAliases := TStringList.Create;
  try
    VAliases.CaseSensitive := False;
    VAliases.Duplicates := dupIgnore;
    VAliases.Sorted := True;
    for VText in pField.AlsoShownAs do VAliases.Add(VText);
    VAliases.Add(pField.TableName + '.' + pField.FieldName);
    pOut.Append('<!--').Append(CRLF);
    pOut.Append('/// dl:wiki ').Append(Heading(pField)).Append(CRLF);
    pOut.Append('/// Aliases: ').Append(JoinAliases(VAliases)).Append(CRLF);
    pOut.Append('-->').Append(CRLF);
  finally
    VAliases.Free;
  end;
end;

procedure AddProse(pOut: TStringBuilder; const pLabel, pText: string);
begin
  if pText = '' then Exit;
  pOut.Append('**').Append(pLabel).Append('**').Append(CRLF).Append(CRLF).Append(Prose(pText)).Append(CRLF).Append(CRLF);
end;

procedure AddLinkGroup(pOut: TStringBuilder; const pField: TWikiField; pGroup: TWikiLinkGroup; pLevel: string);
var
  VLink: TWikiLink;
  VCount: Integer;
  VRows: TStringBuilder;
begin
  VCount := 0;
  VRows := TStringBuilder.Create;
  try
    for VLink in pField.Links do
      if VLink.Group = pGroup then
      begin
        Inc(VCount);
        VRows.Append('- ').Append(VLink.Text);
        if VLink.FileName <> '' then
        begin
          VRows.Append(' (').Append(VLink.FileName);
          if VLink.Line > 0 then VRows.Append(':').Append(VLink.Line);
          VRows.Append(')');
        end;
        VRows.Append(CRLF);
      end;
    if VCount = 0 then Exit;
    pOut.Append(pLevel).Append(' ').Append(GROUP_TITLES[pGroup]).Append(CRLF).Append(CRLF);
    if (pGroup = wlgByName) and (pField.CandidateTables > WIKI_BYNAME_ROW_CAP) then
      pOut.Append(VCount).Append(' name matches in ').Append(pField.CandidateTables).Append(' tables; rows not listed').Append(CRLF)
    else
      pOut.Append(VRows.ToString);
    pOut.Append(CRLF);
  finally
    VRows.Free;
  end;
end;

procedure AddFieldSection(pOut: TStringBuilder; const pField: TWikiField; pLevel: string);
var
  VAlso: string;
  VGroup: TWikiLinkGroup;
begin
  pOut.Append('<a id="').Append(AnchorOf(pField)).Append('"></a>').Append(CRLF);
  pOut.Append(pLevel).Append(' ').Append(Heading(pField)).Append(CRLF).Append(CRLF);
  if pField.Caption <> '' then pOut.Append('- Caption: ').Append(pField.Caption).Append(CRLF);
  if Length(pField.AlsoShownAs) > 0 then
  begin
    pOut.Append('- Also shown as: ');
    for VAlso in pField.AlsoShownAs do
    begin
      if VAlso <> pField.AlsoShownAs[0] then pOut.Append('; ');
      pOut.Append(VAlso);
    end;
    pOut.Append(CRLF);
  end;
  pOut.Append('- Table: ').Append(pField.TableName).Append(CRLF);
  pOut.Append('- Field: ').Append(pField.FieldName).Append(CRLF);
  if pField.TypeText <> '' then pOut.Append('- Type: ').Append(pField.TypeText).Append(CRLF);
  pOut.Append('- Kind: ').Append(pField.Kind).Append(CRLF).Append(CRLF);
  AddProse(pOut, 'Summary', pField.Summary);
  AddProse(pOut, 'Remarks', pField.Remarks);
  AddProse(pOut, 'Documentation', pField.Documentation);
  AddProse(pOut, 'Notes', pField.Notes);
  for VGroup := Low(TWikiLinkGroup) to High(TWikiLinkGroup) do
    AddLinkGroup(pOut, pField, VGroup, pLevel + '#');
  AddWikiBlock(pOut, pField);
  pOut.Append(CRLF);
end;

procedure AddTableHead(pOut: TStringBuilder; const pTable: TWikiTable);
begin
  pOut.Append(WIKI_PAGE_MARK).Append('table ').Append(pTable.Name).Append(' -->').Append(CRLF);
  pOut.Append('# ').Append(pTable.Name).Append(CRLF).Append(CRLF);
  if pTable.Description <> '' then pOut.Append(pTable.Description).Append(CRLF).Append(CRLF);
end;

function TablePage(const pTable: TWikiTable; pPerField: Boolean): TWikiPage;
var
  VB: TStringBuilder;
  VField: TWikiField;
begin
  VB := TStringBuilder.Create;
  try
    AddTableHead(VB, pTable);
    if pPerField then
    begin
      VB.Append('## Fields').Append(CRLF).Append(CRLF);
      for VField in pTable.Fields do
        VB.Append('- [').Append(Heading(VField)).Append('](').Append(pTable.Name).Append('.').Append(VField.FieldName)
          .Append('.md) (').Append(VField.FieldName).Append(')').Append(CRLF);
    end
    else
      for VField in pTable.Fields do
        AddFieldSection(VB, VField, '##');
    Result.FileName := pTable.Name + '.md';
    Result.Text := WikiAscii(VB.ToString);
  finally
    VB.Free;
  end;
end;

function FieldPage(const pTable: TWikiTable; const pField: TWikiField): TWikiPage;
var
  VB: TStringBuilder;
begin
  VB := TStringBuilder.Create;
  try
    VB.Append(WIKI_PAGE_MARK).Append('field ').Append(pTable.Name).Append('.').Append(pField.FieldName).Append(' -->')
      .Append(CRLF);
    VB.Append('[').Append(pTable.Name).Append('](').Append(pTable.Name).Append('.md)').Append(CRLF).Append(CRLF);
    AddFieldSection(VB, pField, '#');
    Result.FileName := pTable.Name + '.' + pField.FieldName + '.md';
    Result.Text := WikiAscii(VB.ToString);
  finally
    VB.Free;
  end;
end;

function BuildWikiPages(const pTables: TArray<TWikiTable>; pPerField: Boolean): TArray<TWikiPage>;
var
  VList: TList<TWikiPage>;
  VTable: TWikiTable;
  VField: TWikiField;
begin
  VList := TList<TWikiPage>.Create;
  try
    for VTable in pTables do
    begin
      VList.Add(TablePage(VTable, pPerField));
      if pPerField then
        for VField in VTable.Fields do
          VList.Add(FieldPage(VTable, VField));
    end;
    Result := VList.ToArray;
  finally
    VList.Free;
  end;
end;

end.
