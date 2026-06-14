unit DRagLint.FormsMap;

/// <summary>Builds a per-form navigation-map CSV for a project: how a tester
/// reaches each form from the application's root form, plus which forms launch
/// it. Reuses the drag-lint index (form/component symbols + event-binding refs +
/// construction refs) and reads caption literals from .dfm line ranges.</summary>
/// <remarks>Engine only. The CLI command forms-csv and the IDE menu item are thin
/// wrappers. Not thread-safe; single-shot per call.</remarks>

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.IOUtils,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  DRagLint.Core.Model,
  DRagLint.Storage.SQLite;

type
  /// <summary>One navigable form (a .dfm root that descends from a form base).</summary>
  TFormNode = record
    FormClass:    string;   // e.g. TfrmMAIN (the form symbol's signature)
    FormName:     string;   // e.g. frmMAIN  (the design-time Name)
    UnitName:     string;   // e.g. uMain    (paired .pas basename, no extension)
    PasPath:      string;   // full path to the paired .pas
    DfmPath:      string;   // full path to the .dfm
    DfmFileId:    Int64;    // files.id of the .dfm in the index
    PasLineCount: Integer;  // line count of the .pas
  end;

  /// <summary>A launch edge: form FromClass opens form ToClass; Caption is the
  /// resolved control caption to press, or '(via Routine)' when no captioned
  /// control binds the launching routine.</summary>
  TFormEdge = record
    FromClass: string;
    ToClass:   string;
    Caption:   string;
  end;

  /// <summary>Generates the navigation-map CSV text.</summary>
  /// <param name="ADbPath">Path to the project's drag-lint index (sqlite).</param>
  /// <param name="AProjectFile">Path to the .dproj (used to find the .dpr for root
  /// detection). May be '' if ARootForm is supplied.</param>
  /// <param name="ARootForm">Root form class (e.g. TfrmMAIN). '' = auto-detect from
  /// the .dpr.</param>
  /// <returns>The full CSV text (RFC 4180 dialect, CRLF rows).</returns>
  /// <exception cref="Exception">If the index cannot be opened or no root can be
  /// resolved.</exception>
  function GenerateFormsCsv(const ADbPath, AProjectFile, ARootForm: string): string;

implementation

/// <summary>Reads the immediate ancestor class name from a .pas class
/// declaration at the given 1-based line (handles "T = class(TAncestor)").</summary>
function ReadAncestor(const APasPath: string; AStartLine: Integer): string;
var
  Lines: TArray<string>;
  Buf: string;
  I, P, Q: Integer;
begin
  Result := '';
  if not TFile.Exists(APasPath) then Exit;
  Lines := TFile.ReadAllLines(APasPath, TEncoding.ANSI);
  Buf := '';
  for I := AStartLine - 1 to Length(Lines) - 1 do
  begin
    Buf := Buf + ' ' + Lines[I];
    if Pos(')', Buf) > 0 then Break;
    if (Pos('class', LowerCase(Buf)) > 0) and (Pos('(', Buf) = 0) and
       (Pos(';', Buf) > 0) then Exit;
    if I > AStartLine + 3 then Break;
  end;
  P := Pos('(', Buf);
  if P = 0 then Exit;
  Q := P + 1;
  while (Q <= Length(Buf)) and CharInSet(Buf[Q], [' ', #9]) do Inc(Q);
  P := Q;
  while (P <= Length(Buf)) and
        (CharInSet(Buf[P], ['A'..'Z','a'..'z','0'..'9','_'])) do Inc(P);
  Result := Copy(Buf, Q, P - Q);
end;

/// <summary>Classifies a form-root class as a navigable form (True) or a data
/// module / frame (False) by walking project-class ancestry; VCL bases terminate
/// the walk.</summary>
function IsNavigableForm(AStore: TSQLiteSymbolStore; const AFormClass: string): Boolean;
var
  Q: TFDQuery;
  Cls, Anc: string;
  Path: string;
  StartLine: Integer;
  Hops: Integer;
begin
  Cls := AFormClass;
  Hops := 0;
  while (Cls <> '') and (Hops < 16) do
  begin
    Inc(Hops);
    if SameText(Cls, 'TDataModule') or SameText(Cls, 'TFrame') or
       SameText(Cls, 'TCustomFrame') then Exit(False);
    if SameText(Cls, 'TForm') or SameText(Cls, 'TCustomForm') or
       SameText(Cls, 'TfrmMicroniteBase') then Exit(True);
    Q := TFDQuery.Create(nil);
    try
      Q.Connection := AStore.GetConnection;
      Q.SQL.Text :=
        'SELECT f.path AS p, s.start_line AS sl FROM symbols s ' +
        'JOIN files f ON f.id = s.file_id ' +
        'WHERE s.kind = ''class'' AND s.name = :n LIMIT 1';
      Q.ParamByName('n').AsString := Cls;
      Q.Open;
      if Q.IsEmpty then Break;
      Path := Q.FieldByName('p').AsString;
      StartLine := Q.FieldByName('sl').AsInteger;
    finally
      Q.Free;
    end;
    Anc := ReadAncestor(Path, StartLine);
    if Anc = '' then Break;
    Cls := Anc;
  end;
  Result := True;
end;

/// <summary>Loads every navigable form from the index (kind='form'), pairing the
/// .dfm with its same-basename .pas and counting the .pas lines.</summary>
function LoadInventory(AStore: TSQLiteSymbolStore): TList<TFormNode>;
var
  Q: TFDQuery;
  Node: TFormNode;
begin
  Result := TList<TFormNode>.Create;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := AStore.GetConnection;
    Q.SQL.Text :=
      'SELECT s.name AS nm, s.signature AS cls, s.file_id AS fid, f.path AS p ' +
      'FROM symbols s JOIN files f ON f.id = s.file_id ' +
      'WHERE s.kind = ''form'' ORDER BY s.name';
    Q.Open;
    while not Q.Eof do
    begin
      Node := Default(TFormNode);
      Node.FormName  := Q.FieldByName('nm').AsString;
      Node.FormClass := Q.FieldByName('cls').AsString;
      Node.DfmFileId := Q.FieldByName('fid').AsLargeInt;
      Node.DfmPath   := Q.FieldByName('p').AsString;
      Node.PasPath   := TPath.ChangeExtension(Node.DfmPath, '.pas');
      Node.UnitName  := TPath.GetFileNameWithoutExtension(Node.PasPath);
      if TFile.Exists(Node.PasPath) then
        Node.PasLineCount := Length(TFile.ReadAllLines(Node.PasPath, TEncoding.ANSI))
      else
        Node.PasLineCount := 0;
      if IsNavigableForm(AStore, Node.FormClass) then
        Result.Add(Node);
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

/// <summary>RFC 4180 field escaping (quote when needed, double embedded quotes).</summary>
function CsvField(const S: string): string;
begin
  if (Pos(',', S) > 0) or (Pos('"', S) > 0) or (Pos(#10, S) > 0) then
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := S;
end;

function GenerateFormsCsv(const ADbPath, AProjectFile, ARootForm: string): string;
var
  Store: TSQLiteSymbolStore;
  Nodes: TList<TFormNode>;
  Sb: TStringBuilder;
  N: TFormNode;
  Idx: Integer;
begin
  Store := TSQLiteSymbolStore.Create(ADbPath);
  Sb := TStringBuilder.Create;
  try
    Store.Migrate;
    Nodes := LoadInventory(Store);
    try
      Nodes.Sort(TComparer<TFormNode>.Construct(
        function(const L, R: TFormNode): Integer
        begin
          Result := CompareText(L.FormName, R.FormName);
        end));
      Sb.Append('#,Unit,FormName,PAS lines,Navigation,Called From,Notes').Append(#13#10);
      Idx := 0;
      for N in Nodes do
      begin
        Inc(Idx);
        Sb.Append(Idx).Append(',')
          .Append(CsvField(N.UnitName)).Append(',')
          .Append(CsvField(N.FormName)).Append(',')
          .Append(N.PasLineCount).Append(',')
          .Append(',')
          .Append(',')
          .Append('')
          .Append(#13#10);
      end;
      Result := Sb.ToString;
    finally
      Nodes.Free;
    end;
  finally
    Sb.Free;
    Store.Free;
  end;
end;

end.
