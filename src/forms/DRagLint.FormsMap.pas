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

/// <summary>True if the source line constructs the given form class:
/// "FormClass.Create" (also matches named ctors like .CreateForFolder) or
/// "CreateForm(FormClass".</summary>
function IsLaunchLine(const ALine, AFormClass: string): Boolean;
begin
  Result :=
    (Pos(AFormClass + '.Create', ALine) > 0) or
    (Pos('CreateForm(' + AFormClass, StringReplace(ALine, ' ', '', [rfReplaceAll])) > 0);
end;

/// <summary>Reads the Caption literal of a control from its .dfm line range
/// (the first "Caption = '...'" before any nested object). Strips '&amp;'
/// accelerators and joins simple multi-line string continuations.</summary>
function ReadCaption(const ADfmPath: string; AStartLine, AEndLine: Integer): string;
var
  Lines: TArray<string>;
  I, P, Q: Integer;
  T: string;
begin
  Result := '';
  if not TFile.Exists(ADfmPath) then Exit;
  Lines := TFile.ReadAllLines(ADfmPath, TEncoding.ANSI);
  for I := AStartLine to AEndLine - 1 do  // skip the object header line itself
  begin
    if (I < 0) or (I >= Length(Lines)) then Continue;
    T := Trim(Lines[I]);
    if (LowerCase(Copy(T, 1, 7)) = 'object ') or
       (LowerCase(Copy(T, 1, 5)) = 'item') then Exit;
    if LowerCase(Copy(T, 1, 9)) = 'caption =' then
    begin
      P := Pos('''', T);
      Q := LastDelimiter('''', T);
      if (P > 0) and (Q > P) then
      begin
        Result := Copy(T, P + 1, Q - P - 1);
        Result := StringReplace(Result, '''''', '''', [rfReplaceAll]);
        Result := StringReplace(Result, '&', '', [rfReplaceAll]);
      end;
      Exit;
    end;
  end;
end;

/// <summary>Finds the control caption bound to event handler ARoutine in form
/// ANode; returns '' if no captioned control directly binds it (Task 5 adds
/// within-form recursion and Action indirection).</summary>
function CaptionForHandler(AStore: TSQLiteSymbolStore; const ANode: TFormNode;
  const ARoutine: string): string;
var
  Q: TFDQuery;
  Line: Integer;
  Sym: TSymbol;
begin
  Result := '';
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := AStore.GetConnection;
    Q.SQL.Text :=
      'SELECT start_line FROM refs ' +
      'WHERE kind = ''event-binding'' AND name_text = :h AND file_id = :fid ' +
      'ORDER BY start_line LIMIT 1';
    Q.ParamByName('h').AsString := ARoutine;
    Q.ParamByName('fid').AsLargeInt := ANode.DfmFileId;
    Q.Open;
    if Q.IsEmpty then Exit;
    Line := Q.FieldByName('start_line').AsInteger;
  finally
    Q.Free;
  end;
  Sym := AStore.FindContainingSymbol(ANode.DfmFileId, Line);
  if Sym.Name = '' then Exit;
  Result := ReadCaption(ANode.DfmPath, Sym.StartLine, Sym.EndLine);
end;

/// <summary>Scans backward from ALaunchLine (1-based) in ALines to find the
/// nearest "procedure/function/constructor ClassName.MethodName" heading and
/// returns ClassName and MethodName. Returns False if not found within 50 lines.
/// Used because implementation method bodies are not separately indexed.</summary>
function FindEnclosingImpl(const ALines: TArray<string>; ALaunchLine: Integer;
  out AOwnerClass, ARoutine: string): Boolean;
var
  I: Integer;
  T, Lc, Rest: string;
  P, Q: Integer;
  Kw: string;
begin
  Result := False;
  AOwnerClass := '';
  ARoutine := '';
  for I := ALaunchLine - 1 downto 0 do
  begin
    if (ALaunchLine - 1 - I) > 50 then Break;
    T := Trim(ALines[I]);
    Lc := LowerCase(T);
    Kw := '';
    if Copy(Lc, 1, 10) = 'procedure ' then Kw := 'procedure'
    else if Copy(Lc, 1, 9) = 'function ' then Kw := 'function'
    else if Copy(Lc, 1, 12) = 'constructor ' then Kw := 'constructor'
    else if Copy(Lc, 1, 11) = 'destructor ' then Kw := 'destructor';
    if Kw = '' then Continue;
    Rest := Copy(T, Length(Kw) + 2, MaxInt);  // skip keyword + space
    // Rest now: "ClassName.MethodName(..." or "MethodName(..." (standalone)
    P := Pos('.', Rest);
    if P = 0 then Continue;  // no dot -> not a qualified class method
    // Extract class name (chars before the dot)
    Q := 1;
    while (Q < P) and CharInSet(Rest[Q], ['A'..'Z','a'..'z','0'..'9','_']) do Inc(Q);
    AOwnerClass := Copy(Rest, 1, Q - 1);
    // Extract method name (chars after the dot, up to first non-ident char)
    P := P + 1;
    Q := P;
    while (Q <= Length(Rest)) and CharInSet(Rest[Q], ['A'..'Z','a'..'z','0'..'9','_']) do Inc(Q);
    ARoutine := Copy(Rest, P, Q - P);
    if (AOwnerClass <> '') and (ARoutine <> '') then
      Exit(True);
  end;
end;

/// <summary>Builds launch edges X -> Y across all forms. For each target form Y,
/// finds construction sites in any .pas, resolves the enclosing routine and its
/// owning form X, and resolves the caption of the control that triggers it.</summary>
function BuildEdges(AStore: TSQLiteSymbolStore; ANodes: TList<TFormNode>;
  AClassToNode: TDictionary<string, TFormNode>): TList<TFormEdge>;
var
  Y: TFormNode;
  Q: TFDQuery;
  PasFileId: Int64;
  LaunchLine: Integer;
  LineText: string;
  Routine, OwnerClass: string;
  XNode: TFormNode;
  Edge: TFormEdge;
  PasLines: TDictionary<Int64, TArray<string>>;
  function FileLines(AFileId: Int64; const APath: string): TArray<string>;
  begin
    if not PasLines.TryGetValue(AFileId, Result) then
    begin
      if TFile.Exists(APath) then
        Result := TFile.ReadAllLines(APath, TEncoding.ANSI)
      else
        Result := [];
      PasLines.Add(AFileId, Result);
    end;
  end;
begin
  Result := TList<TFormEdge>.Create;
  PasLines := TDictionary<Int64, TArray<string>>.Create;
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := AStore.GetConnection;
    for Y in ANodes do
    begin
      Q.Close;
      Q.SQL.Text :=
        'SELECT r.file_id AS fid, r.start_line AS sl, f.path AS p ' +
        'FROM refs r JOIN files f ON f.id = r.file_id ' +
        'WHERE r.name_text = :cls AND f.language LIKE ''delphi%''';
      Q.ParamByName('cls').AsString := Y.FormClass;
      Q.Open;
      while not Q.Eof do
      begin
        PasFileId  := Q.FieldByName('fid').AsLargeInt;
        LaunchLine := Q.FieldByName('sl').AsInteger;
        var Arr := FileLines(PasFileId, Q.FieldByName('p').AsString);
        if (LaunchLine >= 1) and (LaunchLine <= Length(Arr)) then
          LineText := Arr[LaunchLine - 1]
        else
          LineText := '';
        if IsLaunchLine(LineText, Y.FormClass) then
        begin
          if FindEnclosingImpl(Arr, LaunchLine, OwnerClass, Routine) and
             AClassToNode.TryGetValue(OwnerClass, XNode) and
             (OwnerClass <> Y.FormClass) then
          begin
            Edge := Default(TFormEdge);
            Edge.FromClass := OwnerClass;
            Edge.ToClass   := Y.FormClass;
            Edge.Caption   := CaptionForHandler(AStore, XNode, Routine);
            if Edge.Caption = '' then
              Edge.Caption := '(via ' + Routine + ')';
            Result.Add(Edge);
          end;
        end;
        Q.Next;
      end;
    end;
  finally
    Q.Free;
    PasLines.Free;
  end;
end;

/// <summary>BFS shortest navigation path from the root form to AToClass.
/// Returns "RootName -> 'Cap1' -> 'Cap2'" or '' if unreachable.</summary>
function NavPath(AEdges: TList<TFormEdge>; AClassToNode: TDictionary<string, TFormNode>;
  const ARootClass, AToClass: string): string;
type
  TStep = record Cls: string; Path: string; end;
var
  Queue: TQueue<TStep>;
  Visited: TDictionary<string, Boolean>;
  Cur, Nxt: TStep;
  E: TFormEdge;
  RootNode: TFormNode;
begin
  Result := '';
  if SameText(ARootClass, AToClass) then Exit;
  Queue := TQueue<TStep>.Create;
  Visited := TDictionary<string, Boolean>.Create;
  try
    if AClassToNode.TryGetValue(ARootClass, RootNode) then
      Cur.Path := RootNode.FormName
    else
      Cur.Path := ARootClass;
    Cur.Cls := ARootClass;
    Queue.Enqueue(Cur);
    Visited.Add(ARootClass, True);
    while Queue.Count > 0 do
    begin
      Cur := Queue.Dequeue;
      for E in AEdges do
        if SameText(E.FromClass, Cur.Cls) and not Visited.ContainsKey(E.ToClass) then
        begin
          Nxt.Cls := E.ToClass;
          if Copy(E.Caption, 1, 1) = '(' then
            Nxt.Path := Cur.Path + ' -> ' + E.Caption
          else
            Nxt.Path := Cur.Path + ' -> ''' + E.Caption + '''';
          if SameText(E.ToClass, AToClass) then Exit(Nxt.Path);
          Visited.Add(E.ToClass, True);
          Queue.Enqueue(Nxt);
        end;
    end;
  finally
    Queue.Free;
    Visited.Free;
  end;
end;

/// <summary>Determines the root form class: ARootForm if given, else the first
/// Application.CreateForm(T..., ...) in the sibling .dpr whose class is a form
/// node.</summary>
function DetectRoot(const AProjectFile, ARootForm: string;
  AClassToNode: TDictionary<string, TFormNode>): string;
var
  DprPath: string;
  Lines: TArray<string>;
  L, Frag: string;
  P, Q: Integer;
  Cls: string;
begin
  if ARootForm <> '' then Exit(ARootForm);
  Result := '';
  if AProjectFile = '' then Exit;
  DprPath := TPath.ChangeExtension(AProjectFile, '.dpr');
  if not TFile.Exists(DprPath) then Exit;
  Lines := TFile.ReadAllLines(DprPath, TEncoding.ANSI);
  for L in Lines do
  begin
    P := Pos('Application.CreateForm(', L);
    if P = 0 then Continue;
    Frag := Copy(L, P + Length('Application.CreateForm('), MaxInt);
    Q := 1;
    while (Q <= Length(Frag)) and CharInSet(Frag[Q], [' ', #9]) do Inc(Q);
    P := Q;
    while (P <= Length(Frag)) and
          CharInSet(Frag[P], ['A'..'Z','a'..'z','0'..'9','_']) do Inc(P);
    Cls := Copy(Frag, Q, P - Q);
    if AClassToNode.ContainsKey(Cls) then Exit(Cls);
  end;
end;

function GenerateFormsCsv(const ADbPath, AProjectFile, ARootForm: string): string;
var
  Store: TSQLiteSymbolStore;
  Nodes: TList<TFormNode>;
  Sb: TStringBuilder;
  N: TFormNode;
  Idx: Integer;
  ClassToNode: TDictionary<string, TFormNode>;
  Edges: TList<TFormEdge>;
  RootClass: string;
  Nav: string;
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
      ClassToNode := TDictionary<string, TFormNode>.Create;
      for N in Nodes do ClassToNode.AddOrSetValue(N.FormClass, N);
      Edges := BuildEdges(Store, Nodes, ClassToNode);
      try
        RootClass := DetectRoot(AProjectFile, ARootForm, ClassToNode);
        Sb.Append('#,Unit,FormName,PAS lines,Navigation,Called From,Notes').Append(#13#10);
        Idx := 0;
        for N in Nodes do
        begin
          Inc(Idx);
          Nav := '';
          if RootClass <> '' then
          begin
            Nav := NavPath(Edges, ClassToNode, RootClass, N.FormClass);
            if (Nav = '') and not SameText(N.FormClass, RootClass) then
              Nav := '(no path from MAIN)';
          end;
          Sb.Append(Idx).Append(',')
            .Append(CsvField(N.UnitName)).Append(',')
            .Append(CsvField(N.FormName)).Append(',')
            .Append(N.PasLineCount).Append(',')
            .Append(CsvField(Nav)).Append(',')
            .Append(',')   // Called From (Task 6)
            .Append('')    // Notes
            .Append(#13#10);
        end;
        Result := Sb.ToString;
      finally
        Edges.Free;
        ClassToNode.Free;
      end;
    finally
      Nodes.Free;
    end;
  finally
    Sb.Free;
    Store.Free;
  end;
end;

end.
