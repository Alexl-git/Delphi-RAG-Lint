unit DRagLint.FormsMap;

/// <summary>Builds a per-form tester CSV for a project (algorithm v6): how a
/// tester reaches each form from the application's root form -- the menu /
/// ribbon / tab path, the control, its handler, the routine that opens the form,
/// modality and a confidence. Edges come from the index first (refs to the form
/// class/instance + resolved call_edges walked up to a .dfm-bound handler), with
/// the v5 text scan as the fallback; control locations come from the .dfm tree
/// (DRagLint.FormsMap.Dfm).</summary>
/// <remarks>Engine only. The CLI command forms-csv and the IDE menu item are thin
/// wrappers. Not thread-safe; single-shot per call.</remarks>

interface

uses
  System.SysUtils
  , System.Classes
  , System.StrUtils
  , System.Generics.Collections
  , System.Generics.Defaults
  , System.IOUtils
  , Data.DB
  , FireDAC .Comp   .Client
  , FireDAC .Stan   .Param
  , DRagLint.Core   .Model
  , DRagLint.Storage.SQLite
  , DRagLint.Lint   .ProjectChecks.Parse
  ;

type
  /// <summary>One navigable form (a .dfm root that descends from a form base).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.FormsMap.pas), DRagLint.FormsMap.BuildEdges (DRagLint.FormsMap.pas), DRagLint.FormsMap.BuildEdges.BuildHookMap (DRagLint.FormsMap.pas), DRagLint.FormsMap.BuildEdges.ProcessSite (DRagLint.FormsMap.pas), DRagLint.FormsMap.LoadInventory (DRagLint.FormsMap.pas) (+9 more)</para>
  /// <para>Used in units: DRagLint.FormsMap</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TFormNode = record
    FormClass   : string ; // e.g. TfrmMAIN (the form symbol's signature)
    FormName    : string ; // e.g. frmMAIN  (the design-time Name)
    UnitName    : string ; // e.g. uMain    (paired .pas basename, no extension)
    PasPath     : string ; // full path to the paired .pas
    DfmPath     : string ; // full path to the .dfm
    DfmFileId   : Int64  ; // files.id of the .dfm in the index
    PasLineCount: Integer; // line count of the .pas
  end;

  /// <summary>A launch edge: form FromClass opens form ToClass; Caption is the
  /// resolved control caption to press, or '(via Routine)' when no captioned
  /// control binds the launching routine.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.FormsMap.pas), DRagLint.FormsMap.BuildEdges (DRagLint.FormsMap.pas), DRagLint.FormsMap.BuildEdges.TryAddEdge (DRagLint.FormsMap.pas), DRagLint.FormsMap.DetectRoot (DRagLint.FormsMap.pas), DRagLint.FormsMap.TNavBuilder.AddTextEdges (DRagLint.FormsMap.pas) (+2 more)</para>
  /// <para>Used in units: DRagLint.FormsMap</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TFormEdge = record
    FromClass: string;
    ToClass  : string;
    Caption  : string;
    Handler  : string; // v6: routine in FromClass that starts the chain (bare name)
    OpenedBy : string; // v6: Owner.Routine / Unit.Routine holding the Create/Show line
    Modal    : string; // v6: Yes / No / ? read from the launch line
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
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoFormsCsv (DRagLint.CLI.pas), DRagLint.FormsMap.GenerateFormsCsv/3 (DRagLint.FormsMap.pas)</para>
/// <para>Calls: DRagLint.FormsMap.GenerateFormsCsv/3</para>
/// <para>Returns: GenerateFormsCsv([ADbPath], AProjectFile, ARootForm)</para>
/// <para>Overload 1 of 2</para>
/// <para>Recursive</para>
/// <para>Pure</para>
/// <para>Directives: overload</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function GenerateFormsCsv(const ADbPath, AProjectFile, ARootForm: string): string; overload;

/// <summary>Generates the forms navigation-map CSV. ADbPaths[0] is the project
/// index (drives which forms are enumerated + PAS-line counts); ADbPaths[1..] are
/// additional indexes searched ONLY to resolve callers/landings whose call site
/// lives in another DB (e.g. COMMON). A form with no caller in ANY store is
/// reported unresolved with 'no caller found'.</summary>
/// <param name="ADbPaths">1+ SQLite index paths; [0] authoritative, rest search-scope.</param>
/// <param name="AProjectFile">Project (.dpr/.dproj) whose units scope the inventory.</param>
/// <param name="ARootForm">Root form class (e.g. TfrmMAIN); '' = auto-detect.</param>
/// <returns>ANSI CSV text incl. the FORMS_CSV_ALGORITHM provenance footer.</returns>
/// <exception cref="Exception">If ADbPaths is empty, the index cannot be opened,
/// or no root can be resolved.</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: DRagLint.FormsMap.GenerateFormsCsvCore, DRagLint.Storage.SQLite.TSQLiteSymbolStore.Create</para>
/// <para>Returns: GenerateFormsCsvCore(Primary, Extras, AProjectFile, ARootForm, ADbPaths[0])</para>
/// <para>Overload 2 of 2</para>
/// <para>Pure</para>
/// <para>Directives: overload</para>
/// <seealso cref="DRagLint.FormsMap.GenerateFormsCsvCore"/>
/// <seealso cref="DRagLint.Storage.SQLite.TSQLiteSymbolStore.Create"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function GenerateFormsCsv(const ADbPaths: TArray<string>; const AProjectFile, ARootForm: string): string; overload;

implementation

uses
  System.RegularExpressions
  , DRagLint.FormsMap.Dfm
  ;

/// <summary>Reads a .pas file as lines with comment content blanked out, for
/// the raw-text scans in this unit. Element i is line i of TFile.ReadAllLines
/// by construction, so a caller may index it with a line number from the symbol
/// index. On any count disagreement it fails OPEN to the raw unscrubbed lines:
/// losing the scrubbing costs a wrong caption, shifting a line costs a wrong
/// line number in every row.</summary>
/// <param name="APath">Path to the .pas file.</param>
/// <returns>Lines with comments blanked; raw lines if the counts disagree;
/// empty if the file does not exist.</returns>
/// <remarks>Not a general-purpose reader -- StripPasCommentsKeepLayout keeps
/// string-literal content, which the launch/show scans want and a directive
/// scan would not (it blanks {$R} too, since a directive is a brace comment).
/// </remarks>
function ReadPasLinesScrubbed(const APath: string): TArray<string>;
var
  Raw       : TArray<string>;
  Scrubbed  : string        ;
  ScrubLines: TArray<string>;
  I         : Integer       ;
begin
  Result:= [];
  if not TFile.Exists(APath) then Exit;

  // ReadAllLines' count is authoritative: it is what every OTHER read in this
  // unit produces, and what the line numbers in the index are relative to.
  Raw:= TFile.ReadAllLines(APath, TEncoding.ANSI);

  // Layout-preserving: StripPasCommentsKeepLayout starts from Result := ASrc
  // and only overwrites non-EOL characters with spaces, so the scrubbed text
  // is byte-parallel to the raw text and line i maps to line i.
  Scrubbed:= StripPasCommentsKeepLayout(TFile.ReadAllText(APath, TEncoding.ANSI));

  // Split on LF ONLY, and KEEP empty elements, then drop the CR.
  //
  // Both halves of that are load-bearing, and getting either wrong disables
  // this function silently rather than loudly:
  //   - splitting on [#10, #13] treats a CRLF pair as TWO separators, so every
  //     line boundary yields a spurious empty element between them;
  //   - TStringSplitOptions.ExcludeEmpty then deletes those AND every genuine
  //     blank line, so ScrubLines can never reach Raw's count on any file that
  //     has a blank line in it -- i.e. every real file. The fallback below
  //     would fire every time and the scrubbing would never once be applied,
  //     while the unit test suite kept passing because the result is exactly
  //     the raw text the caller used to read anyway.
  ScrubLines:= Scrubbed.Split([#10]);
  for I:= 0 to High(ScrubLines) do
    if ScrubLines[I].EndsWith(#13) then
      ScrubLines[I]:= Copy(ScrubLines[I], 1, Length(ScrubLines[I]) - 1);

  // A trailing newline leaves one empty element that ReadAllLines does not
  // report; truncating to Raw's count absorbs exactly that, and makes the two
  // indexings identical by construction rather than by argument.
  if Length(ScrubLines) >= Length(Raw) then
  begin
    SetLength(ScrubLines, Length(Raw));
    Result:= ScrubLines;
  end
  else
    Result:= Raw; // fail OPEN -- never shift a reported line number
end;

const
  // v5: the raw-text scans in this unit (caller lookup, launch/show
  // confirmation, hook map) now read comment-scrubbed lines, so edges whose
  // caption used to be resolved from a commented-out call site change.
  // v6: index-first edges (refs + call_edges) with the text scan as fallback, a
  // .dfm-tree location per control (menu / bar / ribbon / tab path), and the
  // tester columns (Click, Handler, Opened by, Modal, Confidence ...).
  FORMS_CSV_ALGORITHM = '6'; // bump when the edge or path algorithm changes

type
  TKnownPopupEntry = record Name: string; Note: string; end;

const
  KnownPopupForms: array[0..0] of TKnownPopupEntry = (
    (Name: 'frmgridlayout'; Note: 'popup via TGridMenuPopup (Save/Load Layout)')
  );

/// <summary>Reads the immediate ancestor class name from a .pas class
/// declaration at the given 1-based line (handles "T = class(TAncestor)").</summary>
function ReadAncestor(const APasPath: string; AStartLine: Integer): string;
var
  Lines: TArray<string>;
  Buf  : string        ;
  I    : Integer       ;
  P    : Integer       ;
  Q    : Integer       ;
begin
  Result:= '';
  if not TFile.Exists(APasPath) then Exit;
  Lines:= TFile.ReadAllLines(APasPath, TEncoding.ANSI);
  Buf:= '';
  for I:= AStartLine - 1 to Length(Lines) - 1 do
  begin
    Buf:= Buf + ' ' + Lines[I];
    if Pos(')', Buf) > 0 then Break;
    if (Pos('class', LowerCase(Buf)) > 0) and (Pos('(', Buf) = 0) and (Pos(';', Buf) > 0) then Exit;
    if I > AStartLine + 3 then Break;
  end;
  P:= Pos('(', Buf);
  if P = 0 then Exit;
  Q:= P + 1;
  while (Q <= Length(Buf)) and CharInSet(Buf[Q], [' ', #9]) do Inc(Q);
  P:= Q;
  while (P <= Length(Buf)) and (CharInSet(Buf[P], ['A'..'Z','a'..'z','0'..'9','_'])) do Inc(P);
  Result:= Copy(Buf, Q, P - Q);
end; // function

/// <summary>Classifies a form-root class as a navigable form (True) or a data
/// module / frame (False) by walking project-class ancestry; VCL bases terminate
/// the walk.</summary>
function IsNavigableForm(AStore: TSQLiteSymbolStore; const AFormClass: string): Boolean;
var
  Q        : TFDQuery;
  Cls      : string  ;
  Anc      : string  ;
  Path     : string  ;
  StartLine: Integer ;
  Hops     : Integer ;
begin
  Cls := AFormClass;
  Hops:= 0;
  while (Cls <> '') and (Hops < 16) do
  begin
    Inc(Hops);
    if SameText(Cls, 'TDataModule') or SameText(Cls, 'TFrame'     ) or SameText(Cls, 'TCustomFrame'     ) then Exit(False);
    if SameText(Cls, 'TForm'      ) or SameText(Cls, 'TCustomForm') or SameText(Cls, 'TfrmMicroniteBase') then Exit(True );
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= AStore.GetConnection;
      Q.SQL.Text:= 'SELECT f.path AS p, s.start_line AS sl FROM symbols s ' + 'JOIN files f ON f.id = s.file_id ' + 'WHERE s.kind = ''class'' AND s.name = :n LIMIT 1';
      Q.ParamByName('n').AsString:= Cls;
      Q.Open;
      if Q.IsEmpty then Break;
      Path     := Q.FieldByName('p' ).AsString;
      StartLine:= Q.FieldByName('sl').AsInteger;
    finally
      Q.Free;
    end;
    Anc:= ReadAncestor(Path, StartLine);
    if Anc = '' then Break;
    Cls:= Anc;
  end; // while
  Result:= True;
end; // function

/// <summary>Returns True if the path matches a known backup-file pattern:
/// case-insensitive contains ' - copy' or '-copy', or ends with .bak/.bck/.old/.orig.</summary>
function IsBackupPath(const APath: string): Boolean;
var
  Lc: string;
begin
  Lc:= LowerCase(APath);
  Result:= (Pos(' - copy', Lc) > 0) or (Pos('-copy', Lc) > 0) or (Copy(Lc, Length(Lc) - 3, 4) = '.bak') or (Copy(Lc, Length(Lc) - 3, 4) = '.bck') or
  (Copy(Lc, Length(Lc) - 3, 4) = '.old') or (Copy(Lc, Length(Lc) - 4, 5) = '.orig');
end;

/// <summary>Reads lowercased unit basenames from the uses clause of the sibling
/// .dpr file. Returns an empty array if AProjectFile is '' or the .dpr is absent.
/// Used to restrict inventory to real project units (skips backup/generated
/// files that happen to be in the indexed directory).</summary>
/// <param name="AProjectFile">Path to the .dproj; the .dpr is derived by
/// changing the extension.</param>
/// <returns>Lowercased basenames without extension, e.g. 'udemomain'.</returns>
function LoadProjectUnits(const AProjectFile: string): TArray<string>;
var
  DprPath: string     ;
  Content: string     ;
  P      : Integer    ;
  Q      : Integer    ;
  Name   : string     ;
  List   : TStringList;
begin
  Result:= [];
  if AProjectFile = '' then Exit;
  DprPath:= TPath.ChangeExtension(AProjectFile, '.dpr');
  if not TFile.Exists(DprPath) then Exit;
  Content:= TFile.ReadAllText(DprPath, TEncoding.ANSI);
  List:= TStringList.Create;
  try
    P:= 1;
    while P <= Length(Content) do
    begin
      Q:= PosEx('''', Content, P);
      if Q = 0 then Break;
      // Find the closing quote
      var R:= PosEx('''', Content, Q + 1);
      if R = 0 then Break;
      // Extract the text between single quotes
      var Token:= Copy(Content, Q + 1, R - Q - 1);
      // We want entries like 'uDemoMain.pas' - ends with .pas
      if SameText(Copy(Token, Length(Token) - 3, 4), '.pas') then
      begin
        Name:= LowerCase(TPath.GetFileNameWithoutExtension(Token));
        if Name <> '' then List.Add(Name);
      end;
      P:= R + 1;
    end; // while
    Result:= List.ToStringArray;
  finally
    List.Free;
  end; // try
end; // function

/// <summary>Loads every navigable form from the index (kind='form'), pairing the
/// .dfm with its same-basename .pas and counting the .pas lines. Skips backup
/// files and, when AProjectUnits is non-empty, units not listed in the project.</summary>
/// <param name="AStore">The SQLite symbol store.</param>
/// <param name="AProjectUnits">Lowercased unit basenames from LoadProjectUnits;
/// empty array means no project filter (only backup exclusion applies).</param>
function LoadInventory(AStore: TSQLiteSymbolStore; const AProjectUnits: TArray<string>): TList<TFormNode>;
var
  Q        : TFDQuery ;
  Node     : TFormNode;
  UnitLc   : string   ;
  InProject: Boolean  ;
  I        : Integer  ;
begin
  Result:= TList<TFormNode>.Create;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= AStore.GetConnection;
    Q.SQL.Text:= 'SELECT s.name AS nm, s.signature AS cls, s.file_id AS fid, f.path AS p ' + 'FROM symbols s JOIN files f ON f.id = s.file_id ' +
    'WHERE s.kind = ''form'' ORDER BY s.name';
    Q.Open;
    while not Q.Eof do
    begin
      Node:= Default(TFormNode);
      Node.FormName := Q.FieldByName('nm' ).AsString;
      Node.FormClass:= Q.FieldByName('cls').AsString;
      Node.DfmFileId:= Q.FieldByName('fid').AsLargeInt;
      Node.DfmPath  := Q.FieldByName('p'  ).AsString;
      Node.PasPath:= TPath.ChangeExtension(Node.DfmPath, '.pas');
      Node.UnitName:= TPath.GetFileNameWithoutExtension(Node.PasPath);
      Q.Next; // advance before any Continue so we do not loop forever
      // (a) backup filter: skip paths / unit names matching backup patterns
      if IsBackupPath(Node.DfmPath) or IsBackupPath(Node.PasPath) or IsBackupPath(Node.UnitName) then Continue;
      // (b) project-unit filter: when a project list is available, skip forms
      // whose unit is not in it
      if Length(AProjectUnits) > 0 then
      begin
        UnitLc:= LowerCase(Node.UnitName);
        InProject:= False;
        for I:= 0 to Length(AProjectUnits) - 1 do
          if AProjectUnits[I] = UnitLc then
          begin
            InProject:= True;
            Break;
          end;
        if not InProject then Continue;
      end;
      if TFile.Exists(Node.PasPath) then Node.PasLineCount:= Length(TFile.ReadAllLines(Node.PasPath, TEncoding.ANSI))
      else Node.PasLineCount:= 0;
      if IsNavigableForm(AStore, Node.FormClass) then Result.Add(Node);
    end; // while
  finally
    Q.Free;
  end; // try
end; // function

/// <summary>RFC 4180 field escaping (quote when needed, double embedded quotes).</summary>
function CsvField(const S: string): string;
begin
  if (Pos(',', S) > 0) or (Pos('"', S) > 0) or (Pos(#10, S) > 0) then Result:= '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"'
  else Result:= S;
end;

/// <summary>True if the source line constructs the given form class:
/// "FormClass.Create" (also matches named ctors like .CreateForFolder) or
/// "CreateForm(FormClass".</summary>
function IsLaunchLine(const ALine, AFormClass: string): Boolean;
begin
  Result:= (Pos(AFormClass + '.Create', ALine) > 0) or (Pos('CreateForm(' + AFormClass, StringReplace(ALine, ' ', '', [rfReplaceAll])) > 0);
end;

/// <summary>True if ALine shows a global singleton form instance via its design-time
/// instance name: formName.Show* (covers .ShowModal, .Show) or formName.Execute.</summary>
function IsShowLine(const ALine, AFormName: string): Boolean;
begin
  Result:= (Pos(AFormName + '.Show'   , ALine) > 0) or
           (Pos(AFormName + '.Execute', ALine) > 0);
end;

/// <summary>True when ALine calls a plain .Show (not .ShowModal, .ShowHint,
/// .Showing ...): '.show' followed by a non-identifier character or the end.</summary>
function HasShowCall(const ALine: string): Boolean;
const
  SHOW_TOKEN = '.show';
var
  Lc   : string ;
  P    : Integer;
  After: Integer;
begin
  Lc:= LowerCase(ALine);
  P:= Pos(SHOW_TOKEN, Lc);
  while P > 0 do
  begin
    After:= P + Length(SHOW_TOKEN);
    if (After > Length(Lc)) or not CharInSet(Lc[After], ['a'..'z', '0'..'9', '_']) then Exit(True);
    P:= PosEx(SHOW_TOKEN, Lc, P + 1);
  end;
  Result:= False;
end;

/// <summary>Modality read from launch text: 'Yes' when it calls ShowModal,
/// 'No' when it calls a plain Show, '?' otherwise (Execute, or a Create whose
/// Show happens elsewhere).</summary>
function LineModal(const ALine: string): string;
begin
  if ContainsText(ALine, 'ShowModal') then Result:= 'Yes'
  else if HasShowCall(ALine) then Result:= 'No'
  else Result:= '?';
end;

/// <summary>Reads the Caption literal of a control from its .dfm line range
/// (the first "Caption = '...'" before any nested object). Strips '&amp;'
/// accelerators and joins simple multi-line string continuations.</summary>
function ReadCaption(const ADfmPath: string; AStartLine, AEndLine: Integer): string;
var
  Lines: TArray<string>;
  I    : Integer       ;
  P    : Integer       ;
  Q    : Integer       ;
  T    : string        ;
begin
  Result:= '';
  if not TFile.Exists(ADfmPath) then Exit;
  Lines:= TFile.ReadAllLines(ADfmPath, TEncoding.ANSI);
  for I:= AStartLine to AEndLine - 1 do // skip the object header line itself
  begin
    if (I < 0) or (I >= Length(Lines)) then Continue;
    T:= Trim(Lines[I]);
    if (SameText(Copy(T, 1, 7), 'object ')) or (SameText(Copy(T, 1, 5), 'item')) then Exit;
    if SameText(Copy(T, 1, 9), 'caption =') then
    begin
      P:= Pos          ('''', T);
      Q:= LastDelimiter('''', T);
      if (P > 0) and (Q > P) then
      begin
        Result:= Copy(T, P + 1, Q - P - 1);
        Result:= StringReplace(Result, '''''', '''', [rfReplaceAll]);
        Result:= StringReplace(Result, '&'   , ''  , [rfReplaceAll]);
      end;
      Exit;
    end;
  end; // for
end; // function

/// <summary>Scans backward from ALaunchLine (1-based) in ALines to find the
/// nearest "procedure/function/constructor ClassName.MethodName" heading and
/// returns ClassName and MethodName. Returns False if not found within 50 lines.
/// Used because implementation method bodies are not separately indexed.</summary>
function FindEnclosingImpl(const ALines: TArray<string>; ALaunchLine: Integer; out AOwnerClass, ARoutine: string): Boolean;
var
  I   : Integer;
  T   : string ;
  Lc  : string ;
  Rest: string ;
  P   : Integer;
  Q   : Integer;
  Kw  : string ;
begin
  Result     := False;
  AOwnerClass:= '';
  ARoutine   := '';
  for I:= ALaunchLine - 1 downto 0 do
  begin
    if (ALaunchLine - 1 - I) > 100 then Break;
    T:= Trim(ALines[I]);
    Lc:= LowerCase(T);
    Kw:= '';
    if Copy(Lc, 1, 10)      = 'procedure ' then Kw:= 'procedure'
    else if Copy(Lc, 1, 9 ) = 'function '    then Kw:= 'function'
    else if Copy(Lc, 1, 12) = 'constructor ' then Kw:= 'constructor'
    else if Copy(Lc, 1, 11) = 'destructor ' then Kw:= 'destructor';
    if Kw                   = '' then Continue;
    Rest:= Copy(T, Length(Kw) + 2, MaxInt); // skip keyword + space
    // Rest now: "ClassName.MethodName(..." or "MethodName(..." (standalone)
    P:= Pos('.', Rest);
    if P = 0 then
    begin
      // Standalone function/procedure -- no class prefix. Return empty owner
      // class so ProcessSite can handle factory/hook patterns without marking
      // the target form DEAD (instead of silently skipping the call site).
      Q:= 1;
      while (Q <= Length(Rest)) and CharInSet(Rest[Q], ['A'..'Z','a'..'z','0'..'9','_']) do Inc(Q);
      ARoutine:= Copy(Rest, 1, Q - 1);
      if ARoutine <> '' then begin AOwnerClass:= ''; Exit(True); end;
      Continue;
    end;
    // Extract class name (chars before the dot)
    Q:= 1;
    while (Q < P) and CharInSet(Rest[Q], ['A'..'Z','a'..'z','0'..'9','_']) do Inc(Q);
    AOwnerClass:= Copy(Rest, 1, Q - 1);
    // Extract method name (chars after the dot, up to first non-ident char)
    P:= P + 1;
    Q:= P;
    while (Q <= Length(Rest)) and CharInSet(Rest[Q], ['A'..'Z','a'..'z','0'..'9','_']) do Inc(Q);
    ARoutine:= Copy(Rest, P, Q - P);
    if (AOwnerClass <> '') and (ARoutine <> '') then Exit(True);
  end; // for
end; // function

/// <summary>Reads "Action = X" within a control's .dfm line range; '' if none.</summary>
function ReadActionRef(const ADfmPath: string; AStartLine, AEndLine: Integer): string;
var
  Lines: TArray<string>;
  I    : Integer       ;
  P    : Integer       ;
  T    : string        ;
begin
  Result:= '';
  if not TFile.Exists(ADfmPath) then Exit;
  Lines:= TFile.ReadAllLines(ADfmPath, TEncoding.ANSI);
  for I:= AStartLine to AEndLine - 1 do
  begin
    if (I < 0) or (I >= Length(Lines)) then Continue;
    T:= Trim(Lines[I]);
    if SameText(Copy(T, 1, 7), 'object ') then Exit;
    if SameText(Copy(T, 1, 8), 'action =') then
    begin
      P:= Pos('=', T);
      Result:= Trim(Copy(T, P + 1, MaxInt));
      Exit;
    end;
  end;
end; // function

/// <summary>Finds a component symbol by name within a .dfm file.</summary>
function FindComponent(AStore: TSQLiteSymbolStore; ADfmFileId: Int64; const AName: string): TSymbol;
var
  Q: TFDQuery;
begin
  Result:= Default(TSymbol);
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= AStore.GetConnection;
    Q.SQL.Text:= 'SELECT * FROM symbols WHERE kind = ''component'' AND name = :n ' + 'AND file_id = :fid LIMIT 1';
    Q.ParamByName('n'  ).AsString  := AName;
    Q.ParamByName('fid').AsLargeInt:= ADfmFileId;
    Q.Open;
    if not Q.IsEmpty then Result:= AStore.GetSymbolById(Q.FieldByName('id').AsLargeInt);
  finally
    Q.Free;
  end;
end; // function

/// <summary>Resolves the caption a tester presses in form ANode to invoke the
/// launching routine ARoutine: direct event-binding, Action-linked caption, or by
/// walking callers of ARoutine within the same form. '' if none found.</summary>
function CaptionForHandler(AStore: TSQLiteSymbolStore; const ANode: TFormNode; const ARoutine: string; AVisited: TDictionary<string, Boolean>): string;
var
  Q            : TFDQuery      ;
  Line         : Integer       ;
  Ctrl         : TSymbol       ;
  ActSym       : TSymbol       ;
  ActName      : string        ;
  Cap          : string        ;
  Lines        : TArray<string>;
  LineIdx      : Integer       ;
  OwnerClass   : string        ;
  CallerRoutine: string        ;
begin
  Result:= '';
  if AVisited.ContainsKey(ARoutine) then Exit;
  AVisited.Add(ARoutine, True);

  // (1) direct event-binding in this form's dfm
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= AStore.GetConnection;
    Q.SQL.Text:= 'SELECT start_line FROM refs ' + 'WHERE kind = ''event-binding'' AND name_text = :h AND file_id = :fid ' + 'ORDER BY start_line LIMIT 1';
    Q.ParamByName('h').AsString:= ARoutine;
    Q.ParamByName('fid').AsLargeInt:= ANode.DfmFileId;
    Q.Open;
    if not Q.IsEmpty then
    begin
      Line:= Q.FieldByName('start_line').AsInteger;
      Ctrl:= AStore.FindContainingSymbol(ANode.DfmFileId, Line);
      if Ctrl.Name <> '' then
      begin
        Cap:= ReadCaption(ANode.DfmPath, Ctrl.StartLine, Ctrl.EndLine);
        if Cap <> '' then
        begin
          Q.Free;
          Q:= nil;
          Exit(Cap);
        end;
        // (2) control bound via Action: read "Action = X", resolve X's caption.
        ActName:= ReadActionRef(ANode.DfmPath, Ctrl.StartLine, Ctrl.EndLine);
        if ActName <> '' then
        begin
          ActSym:= FindComponent(AStore, ANode.DfmFileId, ActName);
          if ActSym.Name <> '' then
          begin
            Cap:= ReadCaption(ANode.DfmPath, ActSym.StartLine, ActSym.EndLine);
            if Cap <> '' then
            begin
              Q.Free;
              Q:= nil;
              Exit(Cap);
            end;
          end;
        end;
      end; // if
    end; // if
  finally
    Q.Free;
  end; // try

  // (3) walk callers of ARoutine WITHIN this form's own .pas.
  // Implementation method bodies are NOT indexed as symbols (method symbols are
  // single-line at their declaration). Reuse FindEnclosingImpl text-scan over
  // the form's own .pas lines to find callers.
  Lines:= ReadPasLinesScrubbed(ANode.PasPath);
  for LineIdx:= 0 to Length(Lines) - 1 do
  begin
    if Pos(ARoutine, Lines[LineIdx]) = 0 then Continue;
    OwnerClass   := '';
    CallerRoutine:= '';
    if FindEnclosingImpl(Lines, LineIdx + 1, OwnerClass, CallerRoutine) and SameText(OwnerClass, ANode.FormClass) and not SameText(CallerRoutine, ARoutine) then
    begin
      Cap:= CaptionForHandler(AStore, ANode, CallerRoutine, AVisited);
      if Cap <> '' then Exit(Cap);
    end;
  end;
end; // function

/// <summary>Runs the bare-name caller `refs` query for ARoutine against the
/// primary store PLUS every store in AExtraStores, appending (file_id, start_line,
/// path) rows from each. Multi-DB scope: a call site may live in a different index
/// (e.g. COMMON) than the form being resolved. Rows are NOT deduped here -- the
/// caller's AVisited set already prevents re-walking the same (owner.routine).</summary>
/// <param name="APrimary">The project store (owns form enumeration); queried first.</param>
/// <param name="AExtraStores">Additional caller-search-scope stores; may be empty.</param>
/// <param name="ARoutine">Bare method name to match on refs.name_text.</param>
/// <returns>All matching ref rows across the stores.</returns>
type
  TCallerRefRow = record FileId: Int64; StartLine: Integer; Path: string; Store: TSQLiteSymbolStore; end;

function QueryNameCallerRows(APrimary: TSQLiteSymbolStore;
  const AExtraStores: TArray<TSQLiteSymbolStore>; const ARoutine: string): TArray<TCallerRefRow>;
var
  Stores: TArray<TSQLiteSymbolStore>;
  St    : TSQLiteSymbolStore;
  Q     : TFDQuery;
  Rows  : TList<TCallerRefRow>;
  Row   : TCallerRefRow;
begin
  Rows:= TList<TCallerRefRow>.Create;
  try
    Stores:= [APrimary];
    for St in AExtraStores do Stores:= Stores + [St];
    for St in Stores do
    begin
      if St = nil then Continue;
      Q:= TFDQuery.Create(nil);
      try
        Q.Connection:= St.GetConnection;
        Q.SQL.Text:=
          'SELECT r.file_id AS fid, r.start_line AS sl, f.path AS p ' +
          'FROM refs r JOIN files f ON f.id = r.file_id ' +
          'WHERE r.name_text = :rout AND f.language LIKE ''delphi%''';
        Q.ParamByName('rout').AsString:= ARoutine;
        Q.Open;
        while not Q.Eof do
        begin
          Row.FileId   := Q.FieldByName('fid').AsLargeInt;
          Row.StartLine:= Q.FieldByName('sl' ).AsInteger;
          Row.Path     := Q.FieldByName('p'  ).AsString;
          Row.Store    := St;
          Rows.Add(Row);
          Q.Next;
        end;
      finally
        Q.Free;
      end;
    end;
    Result:= Rows.ToArray;
  finally
    Rows.Free;
  end;
end;

/// <summary>Recursively walks the call graph upward from (AOwnerClass, ARoutine)
/// to find the nearest ancestor call site that lies within a navigable form.
/// Cycle-safe via AVisited keyed as 'OwnerClass.Routine' -- no depth cap; the
/// visited set is the only termination guard.
/// On success sets AFormClass to the form class and AFormRoutine to the method
/// within that form that initiates the chain; returns True.</summary>
/// <remarks>False positives are possible when method names are non-unique across
/// the codebase; accepted trade-off for unlimited-depth traversal without full
/// type inference.
/// v4 Layer 1 (interface-method dispatch) needs NO extra code here: the caller
/// query below matches by bare method NAME with no owner-class filter, so a call
/// site that dispatches through an interface reference (APlan.EditForm, where the
/// launch body lives in the concrete C.EditForm) is already found -- the concrete
/// method and every interface call site share the same name_text, and the call
/// site's enclosing_symbol_id resolves to the calling form. See the query comment
/// below and docs/superpowers/specs/2026-07-05-forms-csv-v4-hook-and-interface-navigation-design.md
/// section D1 (branch (a) diagnosis).</remarks>
function FindNearestFormCaller(
  AStore       : TSQLiteSymbolStore;
  const AOwnerClass, ARoutine: string;
  AClassToNode : TDictionary<string, TFormNode>;
  APasLines    : TDictionary<string, TArray<string>>;
  AVisited     : TDictionary<string, Boolean>;
  const AExtraStores: TArray<TSQLiteSymbolStore>;
  out AFormClass  : string;
  out AFormRoutine: string
): Boolean;
var
  Key : string             ;
  Rows: TArray<TCallerRefRow>;
  R   : TCallerRefRow      ;
  Arr : TArray<string>     ;
  COwner: string           ;
  CRout : string           ;
begin
  Result      := False;
  AFormClass  := '';
  AFormRoutine:= '';
  Key:= AOwnerClass + '.' + ARoutine;
  if AVisited.ContainsKey(Key) then Exit;
  AVisited.Add(Key, True);
  { Name-only caller query: match by bare method name_text, NOT by receiver
    type or owner class. This is what makes the v4 Layer 1 interface-method
    bridge work with no extra machinery: when the launch body lives in a
    concrete C.M (e.g. TDirectPlan4.EditThing constructs the editor form) but
    the call site dispatches through an interface reference (APlan.EditThing in
    the calling form), the interface call site is indexed as a plain 'EditThing'
    ref whose enclosing_symbol_id resolves to the calling form's method. Because
    this query keys on name_text alone, that interface-dispatch call site is
    already returned here -- no HeritageInterfaces / type_ancestors lookup is
    needed (would be dead code; YAGNI). The same holds for the Layer 2 hook
    continuation (Task 3): once the hook edge is synthesized, the fan-in lands
    on THookPlan4.EditThing and this same name walk carries it up to the form.
    (Trade-off: name-only matching can over-match a same-named method on an
    unrelated class -- the accepted false-positive noted in <remarks> above;
    a receiver-type index (spec D5.1) would tighten it if that ever bites.)
    Multi-DB: QueryNameCallerRows fans this same query out across AExtraStores
    too, so a call site living in a different index (e.g. COMMON) is found. }
  Rows:= QueryNameCallerRows(AStore, AExtraStores, ARoutine);
  for R in Rows do
  begin
    if not APasLines.TryGetValue(R.Path, Arr) then
    begin
      Arr:= ReadPasLinesScrubbed(R.Path);
      APasLines.Add(R.Path, Arr);
    end;
    COwner:= '';
    CRout := '';
    if (R.StartLine >= 1) and (R.StartLine <= Length(Arr)) and
       FindEnclosingImpl(Arr, R.StartLine, COwner, CRout) and
       (COwner <> '') and (CRout <> '') then
    begin
      if AClassToNode.ContainsKey(COwner) then
      begin
        AFormClass  := COwner;
        AFormRoutine:= CRout;
        Exit(True);
      end
      else if FindNearestFormCaller(AStore, COwner, CRout, AClassToNode,
                                    APasLines, AVisited, AExtraStores,
                                    AFormClass, AFormRoutine) then
        Exit(True);
    end;
  end; // for
end; // function

/// <summary>v4 Layer 2 hook continuation. When the fan-in dead-ends on a
/// standalone form-launching routine R whose only reference is a proc-variable
/// registration (AHookField := R, invisible to refs -- see spec D2), this
/// resumes the walk from the hook field's INVOCATION sites. It finds every
/// 'call' ref to AHookField (e.g. ThingHook() inside THookPlan4.EditThing),
/// takes each call's enclosing class.method via FindEnclosingImpl, and hands it
/// to FindNearestFormCaller so the SAME name-based interface bridge (Task 2)
/// carries it up to a navigable form (frmRoot4.btnPlanClick). Returns the first
/// form ancestor found. AVisited is shared with the caller's walk so the 1->many
/// hook fan-in cannot loop; a hook field seen once is not re-expanded.</summary>
/// <remarks>Detection of the AHookField binding is a text-scan built in
/// BuildEdges (HandlerToHook); this function consumes the resolved field name and
/// only issues indexed refs queries. v4 bridges ONE hook hop (spec Out of scope).</remarks>
function FindFormViaHook(
  AStore       : TSQLiteSymbolStore;
  const AHookField: string;
  AClassToNode : TDictionary<string, TFormNode>;
  APasLines    : TDictionary<string, TArray<string>>;
  AVisited     : TDictionary<string, Boolean>;
  const AExtraStores: TArray<TSQLiteSymbolStore>;
  out AFormClass  : string;
  out AFormRoutine: string
): Boolean;
var
  Stores: TArray<TSQLiteSymbolStore>;
  St    : TSQLiteSymbolStore;
  Q     : TFDQuery      ;
  SL    : Integer       ;
  Path  : string        ;
  Arr   : TArray<string>;
  COwner: string        ;
  CRout : string        ;
  HKey  : string        ;
begin
  Result      := False;
  AFormClass  := '';
  AFormRoutine:= '';
  if AHookField = '' then Exit;
  HKey:= '(hook)' + AHookField; // distinct namespace from OwnerClass.Routine keys
  if AVisited.ContainsKey(HKey) then Exit;
  AVisited.Add(HKey, True);
  { Invocation sites of the hook field: the proc-variable is CALLED here
    (ThingHook() inside THookPlan4.EditThing). Unlike the registration line,
    the invocation IS indexed as a plain 'call' ref (verified via dump-refs:
    name=ThingHook kind=call enc=THookPlan4.EditThing). Its enclosing routine
    rejoins the Task-2 name-based interface walk back to the calling form.
    Multi-DB: this query (unlike QueryNameCallerRows) also filters on the
    call-site ref kind, so it fans out across AStore + AExtraStores itself
    rather than reusing the helper. v(ADP3 T3i review round 4): the kind is NOT
    named as a literal here -- it is whatever CallSiteRefKindSql emits, see
    REF_KIND_CALL in DRagLint.Core.Model. }
  Stores:= [AStore];
  for St in AExtraStores do Stores:= Stores + [St];
  for St in Stores do
  begin
    if St = nil then Continue;
    Q:= TFDQuery.Create(nil);
    try
      Q.Connection:= St.GetConnection;
      Q.SQL.Text:=
        'SELECT r.file_id AS fid, r.start_line AS sl, f.path AS p ' +
        'FROM refs r JOIN files f ON f.id = r.file_id ' +
        // v(ADP3 T3i review round 2): CallSiteRefKindSql, not a literal. This asks
        // the same "what kind is a call" question REF_KIND_CALL exists to own, and
        // it was correct only because the value happened to be unchanged.
        'WHERE r.name_text = :h AND ' + CallSiteRefKindSql('r') +
        ' AND f.language LIKE ''delphi%''';
      Q.ParamByName('h').AsString:= AHookField;
      Q.Open;
      while not Q.Eof do
      begin
        SL  := Q.FieldByName('sl' ).AsInteger;
        Path:= Q.FieldByName('p'  ).AsString;
        if not APasLines.TryGetValue(Path, Arr) then
        begin
          Arr:= ReadPasLinesScrubbed(Path);
          APasLines.Add(Path, Arr);
        end;
        COwner:= '';
        CRout := '';
        if (SL >= 1) and (SL <= Length(Arr)) and
           FindEnclosingImpl(Arr, SL, COwner, CRout) and
           (COwner <> '') and (CRout <> '') then
        begin
          if AClassToNode.ContainsKey(COwner) then
          begin
            AFormClass  := COwner;
            AFormRoutine:= CRout;
            Exit(True);
          end
          else if FindNearestFormCaller(AStore, COwner, CRout, AClassToNode,
                                        APasLines, AVisited, AExtraStores,
                                        AFormClass, AFormRoutine) then
            Exit(True);
        end;
        Q.Next;
      end; // while
    finally
      Q.Free;
    end;
  end; // for St
end; // function

/// <summary>Builds launch edges X -> Y across all forms using two passes:
/// (1) construction-site refs by class name (TClass.Create / CreateForm); and
/// (2) singleton show-site refs by instance name (formName.ShowModal/.Execute).
/// When the immediate launch site is in a non-form class, recursively walks the
/// call graph upward (unlimited depth, cycle-safe via visited set) until a
/// navigable form ancestor is found. Duplicate (From, To, Caption) triples are
/// suppressed.</summary>
function BuildEdges(AStore: TSQLiteSymbolStore; ANodes: TList<TFormNode>; AClassToNode: TDictionary<string, TFormNode>; const AExtraStores: TArray<TSQLiteSymbolStore>): TList<TFormEdge>;
var
  Y         : TFormNode                          ;
  Q         : TFDQuery                           ;
  PasLines  : TDictionary<string, TArray<string>>;
  SeenEdges : TStringList                        ;
  St        : TSQLiteSymbolStore                 ;
  Stores    : TArray<TSQLiteSymbolStore>         ;
  { v4 Layer 2: routine-name-lowercased -> hook-field-name. Populated once by
    BuildHookMap from a text-scan (proc-var registrations are invisible to refs;
    see spec D2). Consulted only when a standalone launcher dead-ends. }
  HandlerToHook: TDictionary<string, string>    ;

  function FileLines(AFileId: Int64; const APath: string): TArray<string>;
  begin
    if not PasLines.TryGetValue(APath, Result) then
    begin
      Result:= ReadPasLinesScrubbed(APath);
      PasLines.Add(APath, Result);
    end;
  end;

  /// <summary>v4 Layer 2 pre-pass. Scans every indexed delphi .pas ONCE and
  /// records proc-variable hook registrations of shape "H := R" (optionally
  /// "Unit.H := R"), where R is a KNOWN form-launching routine, into
  /// HandlerToHook (R-lowercased -> H). The launcher set is derived in the same
  /// scan: a routine is a launcher iff a line in its body constructs one of the
  /// project's form classes (IsLaunchLine) -- exactly the launchers the main
  /// passes resolve. Strictness (simple-identifier LHS/RHS, ':=' assignment,
  /// launcher-only RHS) keeps the scan from synthesizing edges for ordinary
  /// assignments: the existing hook-free formsmap fixture yields an empty map.</summary>
  procedure BuildHookMap;
  var
    Launchers: TDictionary<string, Boolean>;
    Paths    : TStringList                 ;
    QF       : TFDQuery                     ;
    PIdx     : Integer                      ;
    Lines    : TArray<string>              ;
    LIdx     : Integer                      ;
    T        : string                      ;
    OC, Rout : string                      ;
    N        : TFormNode                   ;
    Launches : Boolean                     ;

    { True if the trimmed line assigns a bare (optionally single-dot-qualified)
      identifier LHS the value of a bare identifier RHS: "<lhs> := <rhs>" with an
      optional trailing ';'. Returns the LHS field (last dotted segment) and RHS
      identifier. Rejects anything with call parens, operators, or extra tokens. }
    function ParseHookAssign(const ALine: string; out AField, ARhs: string): Boolean;
    var
      S, L, R: string;
      P      : Integer;
      I      : Integer;
      DotP   : Integer;

      function IsIdent(const V: string): Boolean;
      var K: Integer;
      begin
        Result:= V <> '';
        for K:= 1 to Length(V) do
          if not CharInSet(V[K], ['A'..'Z','a'..'z','0'..'9','_']) then Exit(False);
      end;

    begin
      Result:= False; AField:= ''; ARhs:= '';
      S:= Trim(ALine);
      P:= Pos(':=', S);
      if P = 0 then Exit;
      L:= Trim(Copy(S, 1, P - 1));
      R:= Trim(Copy(S, P + 2, MaxInt));
      // strip a single trailing ';' (and any trailing spaces) from the RHS
      if (R <> '') and (R[Length(R)] = ';') then R:= Trim(Copy(R, 1, Length(R) - 1));
      // strip a single leading '@' so the address-of idiom ":= @Routine" matches
      // the same as the bare ":= Routine" form (both bind the same launcher name).
      if (R <> '') and (R[1] = '@') then R:= Trim(Copy(R, 2, MaxInt));
      // RHS must be a single bare identifier (the launcher routine, address-of)
      if not IsIdent(R) then Exit;
      // LHS: bare identifier, or exactly one qualifier "Unit.Field" -- take Field
      DotP:= 0;
      for I:= 1 to Length(L) do
        if L[I] = '.' then
        begin
          if DotP <> 0 then Exit; // more than one dot -> not a simple hook field
          DotP:= I;
        end
        else if not CharInSet(L[I], ['A'..'Z','a'..'z','0'..'9','_']) then
          Exit; // any other char (space, paren, index) -> reject
      if DotP > 0 then AField:= Copy(L, DotP + 1, MaxInt)
      else AField:= L;
      if not IsIdent(AField) then Exit;
      ARhs:= R;
      Result:= True;
    end;

  begin
    Launchers:= TDictionary<string, Boolean>.Create;
    Paths    := TStringList.Create;
    try
      // Collect distinct delphi .pas paths (+ their file ids for line caching).
      QF:= TFDQuery.Create(nil);
      try
        QF.Connection:= AStore.GetConnection;
        QF.SQL.Text:=
          'SELECT DISTINCT f.id AS fid, f.path AS p FROM files f ' +
          'WHERE f.language LIKE ''delphi%''';
        QF.Open;
        while not QF.Eof do
        begin
          Paths.AddObject(QF.FieldByName('p').AsString,
                          TObject(NativeInt(QF.FieldByName('fid').AsLargeInt)));
          QF.Next;
        end;
      finally
        QF.Free;
      end;

      // Pass A: derive the launcher-routine set (a routine whose body constructs
      // one of the project's form classes).
      for PIdx:= 0 to Paths.Count - 1 do
      begin
        Lines:= FileLines(Int64(NativeInt(Paths.Objects[PIdx])), Paths[PIdx]);
        for LIdx:= 0 to Length(Lines) - 1 do
        begin
          Launches:= False;
          for N in ANodes do
            if IsLaunchLine(Lines[LIdx], N.FormClass) then begin Launches:= True; Break; end;
          if not Launches then Continue;
          OC:= ''; Rout:= '';
          if FindEnclosingImpl(Lines, LIdx + 1, OC, Rout) and (Rout <> '') then
            Launchers.AddOrSetValue(LowerCase(Rout), True);
        end;
      end;

      // Pass B: record H := R registrations whose RHS R is a known launcher.
      for PIdx:= 0 to Paths.Count - 1 do
      begin
        Lines:= FileLines(Int64(NativeInt(Paths.Objects[PIdx])), Paths[PIdx]);
        for LIdx:= 0 to Length(Lines) - 1 do
        begin
          T:= Lines[LIdx];
          if Pos(':=', T) = 0 then Continue;
          if ParseHookAssign(T, OC, Rout) then // OC=field, Rout=rhs routine
            if Launchers.ContainsKey(LowerCase(Rout)) then
              HandlerToHook.AddOrSetValue(LowerCase(Rout), OC);
        end;
      end;
    finally
      Launchers.Free;
      Paths.Free;
    end;
  end;

  procedure TryAddEdge(const AFrom, ATo, ACaption, AHandler, AOpenedBy, AModal: string);
  var EKey: string; E: TFormEdge;
  begin
    EKey:= AFrom + #1 + ATo + #1 + ACaption + #1 + AHandler;
    if SeenEdges.IndexOf(EKey) >= 0 then Exit;
    SeenEdges.Add(EKey);
    E:= Default(TFormEdge);
    E.FromClass:= AFrom;
    E.ToClass  := ATo;
    E.Caption  := ACaption;
    E.Handler  := AHandler;
    E.OpenedBy := AOpenedBy;
    E.Modal    := AModal;
    Result.Add(E);
  end;

  /// <summary>Resolves and records one launch edge from a single ref row.
  /// AIsShowSite = True uses IsShowLine (instance-name show pattern);
  /// False uses IsLaunchLine (class-name construction pattern).
  /// When the enclosing class is not a form, calls FindNearestFormCaller to
  /// walk the call graph upward until a form ancestor is found.</summary>
  procedure ProcessSite(APasFileId: Int64; ALaunchLine: Integer; const APath: string;
    const ATargetClass, ATargetName: string; AIsShowSite: Boolean);
  var
    Arr     : TArray<string>;
    OC, Rout: string        ;
    Cap     : string        ;
    FormCls : string        ;
    FormRout: string        ;
    XN      : TFormNode     ;
    Opener  : string        ;
    Modal   : string        ;
  begin
    Arr:= FileLines(APasFileId, APath);
    if (ALaunchLine < 1) or (ALaunchLine > Length(Arr)) then Exit;
    if AIsShowSite then
    begin
      if not IsShowLine(Arr[ALaunchLine - 1], ATargetName) then Exit;
    end
    else
    begin
      if not IsLaunchLine(Arr[ALaunchLine - 1], ATargetClass) then Exit;
    end;
    if not FindEnclosingImpl(Arr, ALaunchLine, OC, Rout) then Exit;
    if SameText(OC, ATargetClass) then Exit; // self-launch
    // v6: who holds the launch line, and whether it is modal, for the tester columns.
    if OC <> '' then Opener:= OC + '.' + Rout
    else Opener:= TPath.GetFileNameWithoutExtension(APath) + '.' + Rout;
    Modal:= LineModal(Arr[ALaunchLine - 1]);
    if OC = '' then
    begin
      // Call site is inside a standalone function (no class owner).
      // Try upward graph walk to find a form ancestor; if none, record the
      // unit.function as a synthetic caller so the form is not labelled DEAD
      // (it is reachable via factory/hook, just not statically traceable).
      FormCls := '';
      FormRout:= '';
      var Vis2s:= TDictionary<string, Boolean>.Create;
      try
        var Hooked:= False;
        var HookField:= '';
        if not (FindNearestFormCaller(AStore, '', Rout, AClassToNode, PasLines, Vis2s,
                                      AExtraStores, FormCls, FormRout) and
                AClassToNode.TryGetValue(FormCls, XN)) then
          // v4 Layer 2: the direct fan-in dead-ended. If Rout is a hook handler
          // (registered as HookField := Rout, invisible to refs), resume from the
          // hook field's invocation sites -- which rejoin the interface walk to a
          // form. Reuse the SAME visited set so the fan-in cannot loop.
          if HandlerToHook.TryGetValue(LowerCase(Rout), HookField) then
            Hooked:= FindFormViaHook(AStore, HookField, AClassToNode, PasLines,
                                     Vis2s, AExtraStores, FormCls, FormRout) and
                     AClassToNode.TryGetValue(FormCls, XN)
          else
            Hooked:= False
        else
          Hooked:= True; // direct walk already reached a form

        if Hooked then
        begin
          var Vis3s:= TDictionary<string, Boolean>.Create;
          try
            Cap:= CaptionForHandler(AStore, XN, FormRout, Vis3s);
          finally
            Vis3s.Free;
          end;
          if Cap = '' then Cap:= '(via ' + Rout + ')';
          TryAddEdge(FormCls, ATargetClass, Cap, FormRout, Opener, Modal);
        end
        else
          TryAddEdge(Opener, ATargetClass, '(via hook)', Rout, Opener, Modal);
      finally
        Vis2s.Free;
      end;
      Exit;
    end;
    if AClassToNode.TryGetValue(OC, XN) then
    begin
      // Direct form launcher - resolve caption from DFM event binding
      var Vis1:= TDictionary<string, Boolean>.Create;
      try
        Cap:= CaptionForHandler(AStore, XN, Rout, Vis1);
      finally
        Vis1.Free;
      end;
      if Cap = '' then Cap:= '(via ' + Rout + ')';
      TryAddEdge(OC, ATargetClass, Cap, Rout, Opener, Modal);
    end
    else
    begin
      // Non-form launcher: walk the call graph upward to find the ancestor form
      FormCls := '';
      FormRout:= '';
      var Vis2:= TDictionary<string, Boolean>.Create;
      try
        if FindNearestFormCaller(AStore, OC, Rout, AClassToNode, PasLines, Vis2,
                                 AExtraStores, FormCls, FormRout) and
           AClassToNode.TryGetValue(FormCls, XN) then
        begin
          var Vis3:= TDictionary<string, Boolean>.Create;
          try
            Cap:= CaptionForHandler(AStore, XN, FormRout, Vis3);
          finally
            Vis3.Free;
          end;
          if Cap = '' then Cap:= '(via ' + Rout + ')';
          TryAddEdge(FormCls, ATargetClass, Cap, FormRout, Opener, Modal);
        end;
      finally
        Vis2.Free;
      end;
    end;
  end;

begin
  Result       := TList<TFormEdge>.Create;
  PasLines     := TDictionary<string, TArray<string>>.Create;
  SeenEdges    := TStringList.Create;
  HandlerToHook:= TDictionary<string, string>.Create;
  SeenEdges.Sorted    := True;
  SeenEdges.Duplicates:= dupIgnore;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= AStore.GetConnection;
    // v4 Layer 2: text-scan proc-var hook registrations BEFORE the launch passes
    // so any launcher dead-end can consult HandlerToHook. Empty for hook-free
    // projects (the map stays empty and the branch below is a no-op).
    BuildHookMap;
    // Fan Pass 1/2 across the primary store plus every extra store (mirrors the
    // hook-invocation loop above): with AExtraStores empty this is exactly
    // [AStore], one iteration, so single-DB behavior is unchanged.
    Stores:= [AStore];
    for St in AExtraStores do Stores:= Stores + [St];
    for Y in ANodes do
    begin
      for St in Stores do
      begin
        if St = nil then Continue;
        Q.Connection:= St.GetConnection;

        // Pass 1: construction sites -- refs by class name (TClass.Create / CreateForm)
        Q.Close;
        Q.SQL.Text:=
          'SELECT r.file_id AS fid, r.start_line AS sl, f.path AS p ' +
          'FROM refs r JOIN files f ON f.id = r.file_id ' +
          'WHERE r.name_text = :cls AND f.language LIKE ''delphi%''';
        Q.ParamByName('cls').AsString:= Y.FormClass;
        Q.Open;
        while not Q.Eof do
        begin
          ProcessSite(Q.FieldByName('fid').AsLargeInt,
                      Q.FieldByName('sl' ).AsInteger,
                      Q.FieldByName('p'  ).AsString,
                      Y.FormClass, Y.FormName, False);
          Q.Next;
        end; // while

        // Pass 2: singleton show sites -- refs by instance name (.ShowModal / .Execute)
        Q.Close;
        Q.SQL.Text:=
          'SELECT r.file_id AS fid, r.start_line AS sl, f.path AS p ' +
          'FROM refs r JOIN files f ON f.id = r.file_id ' +
          'WHERE r.name_text = :nm AND f.language LIKE ''delphi%''';
        Q.ParamByName('nm').AsString:= Y.FormName;
        Q.Open;
        while not Q.Eof do
        begin
          ProcessSite(Q.FieldByName('fid').AsLargeInt,
                      Q.FieldByName('sl' ).AsInteger,
                      Q.FieldByName('p'  ).AsString,
                      Y.FormClass, Y.FormName, True);
          Q.Next;
        end; // while
      end; // for St
    end; // for Y
  finally
    Q.Free;
    PasLines.Free;
    SeenEdges.Free;
    HandlerToHook.Free;
  end; // try
end; // function

/// <summary>Determines the root form class from the sibling .dpr: scans lines
/// in order, remembers the last Application.CreateForm(Tclass) whose class is a
/// form node, and stops at the first line containing Application.Run. Returns
/// the last remembered form-node class, which for a typical .dpr like
/// "CreateForm(TdmStyles,...); CreateForm(TfrmMAIN,...); Application.Run;"
/// yields TfrmMAIN and ignores bootstrap procedures that precede the main block.
/// Fallback when no match: the form node with the highest out-degree in AEdges
/// (the navigation hub).</summary>
/// <param name="AProjectFile">Path to the .dproj; .dpr is derived from it.</param>
/// <param name="ARootForm">Explicit override; returned unchanged if non-empty.</param>
/// <param name="AClassToNode">Form-class to node lookup for membership test.</param>
/// <param name="AEdges">All launch edges; used for the out-degree fallback.</param>
/// <returns>The detected root class name, or '' if none can be resolved.</returns>
function DetectRoot(const AProjectFile, ARootForm: string; AClassToNode: TDictionary<string, TFormNode>; AEdges: TList<TFormEdge>): string;
var
  DprPath : string                      ;
  Lines   : TArray<string>              ;
  L       : string                      ;
  Frag    : string                      ;
  StartPos: Integer                     ;
  FragEnd : Integer                     ;
  Cls     : string                      ;
  Best    : string                      ;
  OutDeg  : TDictionary<string, Integer>;
  E       : TFormEdge                   ;
  MaxDeg  : Integer                     ;
  Deg     : Integer                     ;
  Pair    : TPair<string, Integer>      ;
begin
  if ARootForm <> '' then Exit(ARootForm);
  Result:= '';
  if AProjectFile = '' then Exit;
  DprPath:= TPath.ChangeExtension(AProjectFile, '.dpr');
  if not TFile.Exists(DprPath) then Exit;
  Lines:= TFile.ReadAllLines(DprPath, TEncoding.ANSI);
  Best:= '';
  for L in Lines do
  begin
    // Determine scan limit: if this line also contains Application.Run, only
    // consider CreateForm calls that appear BEFORE the Application.Run position.
    var RunPos:= Pos('Application.Run', L);
    var ScanLimit:= Length(L);
    var IsRunLine:= RunPos > 0;
    if IsRunLine then ScanLimit:= RunPos - 1;
    // Scan all Application.CreateForm( occurrences on this line up to ScanLimit.
    StartPos:= 1;
    while True do
    begin
      StartPos:= PosEx('Application.CreateForm(', L, StartPos);
      if (StartPos = 0) or (StartPos > ScanLimit) then Break;
      // Advance StartPos past the matched keyword so the next iteration
      // continues after this occurrence.
      StartPos:= StartPos + Length('Application.CreateForm(');
      // Extract the class name token immediately after the opening paren.
      Frag:= Copy(L, StartPos, MaxInt);
      FragEnd:= 1;
      while (FragEnd <= Length(Frag)) and CharInSet(Frag[FragEnd], [' ', #9]) do Inc(FragEnd);
      var TokenEnd:= FragEnd;
      while (TokenEnd <= Length(Frag)) and CharInSet(Frag[TokenEnd], ['A'..'Z','a'..'z','0'..'9','_']) do Inc(TokenEnd);
      Cls:= Copy(Frag, FragEnd, TokenEnd - FragEnd);
      if AClassToNode.ContainsKey(Cls) then Best:= Cls; // remember last form-node CreateForm before Run
    end; // while
    // After scanning CreateForms on this line: if it contains Application.Run, stop.
    if IsRunLine then
    begin
      Result:= Best;
      Exit;
    end;
  end; // for
  // Application.Run line not found: return whatever we collected.
  if Best <> '' then
  begin
    Result:= Best;
    Exit;
  end;
  // Out-degree fallback: pick the form node that launches the most other forms.
  OutDeg:= TDictionary<string, Integer>.Create;
  try
    for E in AEdges do
      if AClassToNode.ContainsKey(E.FromClass) then
      begin
        if OutDeg.ContainsKey(E.FromClass) then OutDeg[E.FromClass]:= OutDeg[E.FromClass] + 1
        else OutDeg.Add(E.FromClass, 1);
      end;
    MaxDeg:= -1;
    Best:= '';
    for Pair in OutDeg do
    begin
      Deg:= Pair.Value;
      if Deg > MaxDeg then
      begin
        MaxDeg:= Deg;
        Best:= Pair.Key;
      end;
    end;
    Result:= Best;
  finally
    OutDeg.Free;
  end; // try
end; // function

const
  FORMS_CALLER_MAX_DEPTH = 6; // call_edges hops walked up from a launch routine
  FORMS_ALSO_MAX         = 3; // other ways listed in Notes before the count says the rest
  METHOD_INDEX           = 'index';
  METHOD_TEXT            = 'text scan';
  CONF_TRACED            = 'traced';
  CONF_HANDLER_ONLY      = 'handler-only';
  CONF_UNRESOLVED        = 'unresolved';

type
  /// <summary>v6: one way into a form as found by the index pass or the text
  /// scan. Ways is empty when the handler is known but no control fires it.</summary>
  TNavEdge = record
    FromClass: string; // launching form class; 'Unit.Routine' for a synthetic text edge
    ToClass  : string;
    Handler  : string; // bare routine name in FromClass that starts the chain
    OpenedBy : string; // Owner.Routine / Unit.Routine holding the Create/Show
    Modal    : string; // Yes / No / ?
    Method   : string; // METHOD_INDEX / METHOD_TEXT
    Hint     : string; // "Before you start"
    Note     : string;
    Ways     : TArray<TNavWay>;
  end;

  /// <summary>v6: a routine symbol with what the report needs from it.</summary>
  TRoutineInfo = record
    Id           : Int64  ;
    Name         : string ;
    Owner        : string ; // class name; '' for a standalone routine
    UnitName     : string ;
    Path         : string ;
    IsClassMethod: Boolean;
    StartLine    : Integer;
    ImplStart    : Integer;
    ImplEnd      : Integer;
  end;

  /// <summary>v6 edge builder: index-first (refs + call_edges + the .dfm tree),
  /// text-scan edges merged in afterwards as a fallback. Every edge records the
  /// method that found it.</summary>
  TNavBuilder = class  // dl:ok high-response@f32a -- RFC is the index queries and caches one report needs (routines, callers, .dfm trees, scrubbed lines); they share the caches, and splitting would hand the same calls to a second class
  private
    FStores     : TArray<TSQLiteSymbolStore>;
    FNodes      : TList<TFormNode>;
    FClassToNode: TDictionary<string, TFormNode>;
    FTrees      : TObjectDictionary<string, TFormDfmTree>;
    FLines      : TDictionary<string, TArray<string>>;
    FRoutines   : TDictionary<string, TRoutineInfo>;
    FEdgeKeys   : TDictionary<string, Boolean>;
    FEdges      : TList<TNavEdge>;
    function TreeFor(const AFormClass: string): TFormDfmTree;
    function LinesOf(const APath: string): TArray<string>;
    function Routine(AStore: TSQLiteSymbolStore; AId: Int64): TRoutineInfo;
    function FindMethod(AStore: TSQLiteSymbolStore; const AOwner, AName: string): TRoutineInfo;
    function CallerIds(AStore: TSQLiteSymbolStore; AId: Int64): TArray<Int64>;
    function ActionInvokerIds(AStore: TSQLiteSymbolStore; const AOwner, AAction: string): TArray<Int64>;
    function Body(const AInfo: TRoutineInfo): TArray<string>;
    function BodyModal(const AInfo: TRoutineInfo): string;
    function IsFormField(AStore: TSQLiteSymbolStore; const AFormClass, AName: string): Boolean;
    function SelectionHint(AStore: TSQLiteSymbolStore; const AFormClass: string; const AInfos: array of TRoutineInfo): string;
    procedure AddEdge(const AEdge: TNavEdge);
    procedure TraceLaunch(AStore: TSQLiteSymbolStore; const AY: TFormNode; const AL: TRoutineInfo; const AModal: string);
    procedure IndexPassFor(AStore: TSQLiteSymbolStore; const AY: TFormNode);
  public
    constructor Create(const AStores: TArray<TSQLiteSymbolStore>; ANodes: TList<TFormNode>; AClassToNode: TDictionary<string, TFormNode>);
    destructor Destroy; override;
    procedure RunIndexPass;
    procedure AddTextEdges(ATextEdges: TList<TFormEdge>);
    procedure AddTextEdge(const T: TFormEdge);
    property Edges: TList<TNavEdge> read FEdges;
  end;

/// <summary>True when the first (best-ranked) way is something a tester can
/// press; ways are sorted so controls come before actions and automatic events.</summary>
function HasControl(const AWays: TArray<TNavWay>): Boolean;
begin
  Result:= (Length(AWays) > 0) and AWays[0].IsControl;
end;

function RoutineDisplay(const AInfo: TRoutineInfo): string;
begin
  if AInfo.Owner <> '' then Result:= AInfo.Owner + '.' + AInfo.Name
  else Result:= AInfo.UnitName + '.' + AInfo.Name;
end;

/// <summary>The identifier right after "AClass." on ALine ('' when absent),
/// e.g. ShowForRegion in "TfrmOcr.ShowForRegion(R)".</summary>
function MemberAfter(const ALine, AClass: string): string;
var
  P: Integer;
  Q: Integer;
begin
  Result:= '';
  P:= Pos(LowerCase(AClass) + '.', LowerCase(ALine));
  if P = 0 then Exit;
  P:= P + Length(AClass) + 1;
  Q:= P;
  while (Q <= Length(ALine)) and CharInSet(ALine[Q], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(Q);
  Result:= Copy(ALine, P, Q - P);
end;

constructor TNavBuilder.Create(const AStores: TArray<TSQLiteSymbolStore>; ANodes: TList<TFormNode>; AClassToNode: TDictionary<string, TFormNode>);
begin
  inherited Create;
  FStores     := AStores;
  FNodes      := ANodes;
  FClassToNode:= AClassToNode;
  FTrees      := TObjectDictionary<string, TFormDfmTree>.Create([doOwnsValues]);
  FLines      := TDictionary<string, TArray<string>>.Create;
  FRoutines   := TDictionary<string, TRoutineInfo>.Create;
  FEdgeKeys   := TDictionary<string, Boolean>.Create;
  FEdges      := TList<TNavEdge>.Create;
end;

destructor TNavBuilder.Destroy;
begin
  FEdges.Free;
  FEdgeKeys.Free;
  FRoutines.Free;
  FLines.Free;
  FTrees.Free;
  inherited Destroy;
end;

function TNavBuilder.TreeFor(const AFormClass: string): TFormDfmTree;
var
  N: TFormNode;
begin
  if FTrees.TryGetValue(LowerCase(AFormClass), Result) then Exit;
  Result:= TFormDfmTree.Create;
  FTrees.Add(LowerCase(AFormClass), Result);
  if FClassToNode.TryGetValue(AFormClass, N) then Result.LoadFromFile(N.DfmPath);
end;

function TNavBuilder.LinesOf(const APath: string): TArray<string>;
begin
  if not FLines.TryGetValue(APath, Result) then
  begin
    Result:= ReadPasLinesScrubbed(APath);
    FLines.Add(APath, Result);
  end;
end;

function TNavBuilder.Routine(AStore: TSQLiteSymbolStore; AId: Int64): TRoutineInfo;
var
  Key: string  ;
  Q  : TFDQuery;
  PK : string  ;
begin
  Key:= IntToHex(NativeInt(AStore)) + ':' + IntToStr(AId);
  if FRoutines.TryGetValue(Key, Result) then Exit;
  Result:= Default(TRoutineInfo);
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= AStore.GetConnection;
    Q.SQL.Text:=
      'SELECT s.name AS nm, s.modifiers AS md, s.signature AS sg, s.start_line AS sl, ' +
      's.impl_start_line AS isl, s.impl_end_line AS iel, f.path AS p, pa.name AS pn, pa.kind AS pk ' +
      'FROM symbols s JOIN files f ON f.id = s.file_id LEFT JOIN symbols pa ON pa.id = s.parent_id ' +
      'WHERE s.id = :id';
    Q.ParamByName('id').AsLargeInt:= AId;
    Q.Open;
    if not Q.IsEmpty then
    begin
      Result.Id       := AId;
      Result.Name     := Q.FieldByName('nm' ).AsString;
      Result.Path     := Q.FieldByName('p'  ).AsString;
      Result.UnitName := TPath.GetFileNameWithoutExtension(Result.Path);
      Result.StartLine:= Q.FieldByName('sl' ).AsInteger;
      Result.ImplStart:= Q.FieldByName('isl').AsInteger;
      Result.ImplEnd  := Q.FieldByName('iel').AsInteger;
      PK:= Q.FieldByName('pk').AsString;
      if SameText(PK, 'class') or SameText(PK, 'record') then Result.Owner:= Q.FieldByName('pn').AsString;
      Result.IsClassMethod:= ContainsText(Q.FieldByName('md').AsString, 'class') or StartsText('class ', Q.FieldByName('sg').AsString);
    end;
  finally
    Q.Free;
  end;
  FRoutines.Add(Key, Result);
end;

function TNavBuilder.FindMethod(AStore: TSQLiteSymbolStore; const AOwner, AName: string): TRoutineInfo;
var
  Q: TFDQuery;
begin
  Result:= Default(TRoutineInfo);
  if AName = '' then Exit;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= AStore.GetConnection;
    Q.SQL.Text:=
      'SELECT s.id AS id FROM symbols s JOIN symbols pa ON pa.id = s.parent_id ' +
      'WHERE pa.kind = ''class'' AND pa.name = :o AND s.name = :n LIMIT 1';
    Q.ParamByName('o').AsString:= AOwner;
    Q.ParamByName('n').AsString:= AName;
    Q.Open;
    if not Q.IsEmpty then Result:= Routine(AStore, Q.FieldByName('id').AsLargeInt);
  finally
    Q.Free;
  end;
end;

function TNavBuilder.CallerIds(AStore: TSQLiteSymbolStore; AId: Int64): TArray<Int64>;
var
  Q  : TFDQuery;
  Fld: TField  ;
begin
  Result:= [];
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= AStore.GetConnection;
    Q.SQL.Text:=
      'SELECT DISTINCT r.enclosing_symbol_id AS e FROM call_edges ce ' +
      'JOIN refs r ON r.id = ce.ref_id ' +
      'WHERE ce.target_symbol_id = :t AND r.enclosing_symbol_id IS NOT NULL';
    Q.ParamByName('t').AsLargeInt:= AId;
    Q.Open;
    Fld:= Q.FieldByName('e');
    while not Q.Eof do
    begin
      Result:= Result + [Fld.AsLargeInt];
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

/// <summary>Routines of AOwner that mention action AAction -- in practice
/// "actX.Execute" from a grid double-click or key handler. They stand in for
/// callers of the action's OnExecute handler, which call_edges cannot show.</summary>
function TNavBuilder.ActionInvokerIds(AStore: TSQLiteSymbolStore; const AOwner, AAction: string): TArray<Int64>;
var
  Q  : TFDQuery;
  Fld: TField  ;
begin
  Result:= [];
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= AStore.GetConnection;
    Q.SQL.Text:=
      'SELECT DISTINCT r.enclosing_symbol_id AS e FROM refs r ' +
      'JOIN symbols e ON e.id = r.enclosing_symbol_id JOIN symbols pa ON pa.id = e.parent_id ' +
      'WHERE r.name_text = :a AND pa.kind = ''class'' AND pa.name = :o';
    Q.ParamByName('a').AsString:= AAction;
    Q.ParamByName('o').AsString:= AOwner;
    Q.Open;
    Fld:= Q.FieldByName('e');
    while not Q.Eof do
    begin
      Result:= Result + [Fld.AsLargeInt];
      Q.Next;
    end;
  finally
    Q.Free;
  end;
end;

function TNavBuilder.Body(const AInfo: TRoutineInfo): TArray<string>;
var
  Lines: TArray<string>;
  First: Integer;
  Last : Integer;
begin
  Result:= [];
  if AInfo.Path = '' then Exit;
  Lines:= LinesOf(AInfo.Path);
  if AInfo.ImplStart > 0 then
  begin
    First:= AInfo.ImplStart;
    Last := AInfo.ImplEnd;
  end
  else
  begin
    First:= AInfo.StartLine;
    Last := AInfo.StartLine;
  end;
  if First < 1 then First:= 1;
  if Last > Length(Lines) then Last:= Length(Lines);
  if Last >= First then Result:= Copy(Lines, First - 1, Last - First + 1);
end;

function TNavBuilder.BodyModal(const AInfo: TRoutineInfo): string;
var
  L      : string ;
  SawShow: Boolean;
begin
  SawShow:= False;
  for L in Body(AInfo) do
  begin
    if ContainsText(L, 'ShowModal') then Exit('Yes');
    if HasShowCall(L) then SawShow:= True;
  end;
  if SawShow then Result:= 'No'
  else Result:= '?';
end;

function TNavBuilder.IsFormField(AStore: TSQLiteSymbolStore; const AFormClass, AName: string): Boolean;
var
  Q: TFDQuery;
begin
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= AStore.GetConnection;
    Q.SQL.Text:=
      'SELECT 1 FROM symbols s JOIN symbols pa ON pa.id = s.parent_id ' +
      'WHERE pa.kind = ''class'' AND pa.name = :c AND s.name = :n AND s.kind = ''field'' LIMIT 1';
    Q.ParamByName('c').AsString:= AFormClass;
    Q.ParamByName('n').AsString:= AName;
    Q.Open;
    Result:= not Q.IsEmpty;
  finally
    Q.Free;
  end;
end;

function TNavBuilder.SelectionHint(AStore: TSQLiteSymbolStore; const AFormClass: string; const AInfos: array of TRoutineInfo): string;
var
  Info  : TRoutineInfo;
  L     : string;
  M     : TMatch;
  Member: string;
  N     : TFormNode;
  What  : string;
begin
  Result:= '';
  if not FClassToNode.TryGetValue(AFormClass, N) then Exit;
  // Only a member read on a FIELD of the launching form counts: that is state the
  // tester must have set up on that form. A local or a data-module dataset is
  // not something we can name honestly, so it yields no hint.
  for Info in AInfos do
    for L in Body(Info) do
      for M in TRegEx.Matches(L, '\b([A-Za-z_][A-Za-z0-9_]*)\.(FieldByName|FieldValues|Fields|SelectedRows|Selected|ItemIndex|FocusedRecord|FocusedRow|FocusedNode|DataController|Controller)\b') do
        if IsFormField(AStore, AFormClass, M.Groups[1].Value) then
        begin
          Member:= M.Groups[2].Value;
          if SameText(Member, 'ItemIndex') or SameText(Member, 'Selected') then What:= 'an item'
          else What:= 'a row';
          Exit(N.FormName + ': select ' + What + ' in ' + M.Groups[1].Value + ' first (the handler reads ' + M.Groups[1].Value + '.' + Member + ')');
        end;
end;

procedure TNavBuilder.AddEdge(const AEdge: TNavEdge);
var
  Key: string;
begin
  Key:= LowerCase(AEdge.FromClass + #1 + AEdge.ToClass + #1 + AEdge.Handler);
  if FEdgeKeys.ContainsKey(Key) then Exit;
  FEdgeKeys.Add(Key, True);
  FEdges.Add(AEdge);
end;

procedure TNavBuilder.TraceLaunch(AStore: TSQLiteSymbolStore; const AY: TFormNode; const AL: TRoutineInfo; const AModal: string);
type
  TItem = record Id: Int64; Depth: Integer; end;
var
  Queue    : TQueue<TItem>;
  Visited  : TDictionary<Int64, Boolean>;
  Cur      : TItem;
  Nxt      : TItem;
  S        : TRoutineInfo;
  Cand     : TRoutineInfo;
  CandWays : TArray<TNavWay>;
  HaveCand : Boolean;
  W        : TNavWay;
  Traced   : Boolean;
  Ways     : TArray<TNavWay>;
  E        : TNavEdge;
  C        : Int64;

  function MakeEdge(const AH: TRoutineInfo; const AWays: TArray<TNavWay>): TNavEdge;
  begin
    Result:= Default(TNavEdge);
    Result.FromClass:= AH.Owner;
    Result.ToClass  := AY.FormClass;
    Result.Handler  := AH.Name;
    Result.OpenedBy := RoutineDisplay(AL);
    Result.Modal    := AModal;
    Result.Method   := METHOD_INDEX;
    Result.Ways     := AWays;
    if SameText(AL.Owner, AH.Owner) and (AL.Id <> AH.Id) then Result.Hint:= SelectionHint(AStore, AH.Owner, [AH, AL])
    else Result.Hint:= SelectionHint(AStore, AH.Owner, [AH]);
  end;

begin
  Queue  := TQueue<TItem>.Create;
  Visited:= TDictionary<Int64, Boolean>.Create;
  try
    HaveCand:= False;
    Traced  := False;
    Cand    := Default(TRoutineInfo);
    CandWays:= [];
    Cur.Id:= AL.Id;
    Cur.Depth:= 0;
    Queue.Enqueue(Cur);
    Visited.Add(AL.Id, True);
    while Queue.Count > 0 do
    begin
      Cur:= Queue.Dequeue;
      S:= Routine(AStore, Cur.Id);
      if (S.Owner <> '') and not SameText(S.Owner, AY.FormClass) and FClassToNode.ContainsKey(S.Owner) then
      begin
        Ways:= TreeFor(S.Owner).WaysForHandler(S.Name);
        if HasControl(Ways) then
        begin
          AddEdge(MakeEdge(S, Ways));
          Traced:= True;
          Continue; // a bound handler is where the tester starts; look no higher
        end;
        if not HaveCand then
        begin
          Cand    := S;
          CandWays:= Ways;
          HaveCand:= True;
        end;
        // An action no control displays is usually run from code (actX.Execute
        // in a grid double-click); those routines are its real callers.
        for W in Ways do
          if not W.IsControl and ContainsText(W.CtrlClass, 'Action') then
            for C in ActionInvokerIds(AStore, S.Owner, W.CompName) do
              if not Visited.ContainsKey(C) then
              begin
                Visited.Add(C, True);
                Nxt.Id   := C;
                Nxt.Depth:= Cur.Depth + 1;
                Queue.Enqueue(Nxt);
              end;
      end;
      if Cur.Depth >= FORMS_CALLER_MAX_DEPTH then Continue;
      for C in CallerIds(AStore, Cur.Id) do
        if not Visited.ContainsKey(C) then
        begin
          Visited.Add(C, True);
          Nxt.Id   := C;
          Nxt.Depth:= Cur.Depth + 1;
          Queue.Enqueue(Nxt);
        end;
    end; // while
    if not Traced and HaveCand then
    begin
      E:= MakeEdge(Cand, CandWays);
      if Length(CandWays) = 0 then
        E.Note:= Cand.Name + ' is not bound to any control in ' + ExtractFileName(TPath.ChangeExtension(Cand.Path, '.dfm')) + ' (assigned in code?)';
      AddEdge(E);
    end;
  finally
    Visited.Free;
    Queue.Free;
  end;
end;

procedure TNavBuilder.IndexPassFor(AStore: TSQLiteSymbolStore; const AY: TFormNode);
var
  Q      : TFDQuery;
  FldE   : TField  ;
  FldL   : TField  ;
  FldP   : TField  ;
  L      : TRoutineInfo;
  CM     : TRoutineInfo;
  Lines  : TArray<string>;
  Line   : string ;
  SL     : Integer;
  Modal  : string ;
  Member : string ;
  Seen   : TDictionary<Int64, Boolean>;
  Sites  : TList<TPair<TRoutineInfo, string>>;
  Site   : TPair<TRoutineInfo, string>;
begin
  Seen := TDictionary<Int64, Boolean>.Create;
  Sites:= TList<TPair<TRoutineInfo, string>>.Create;
  Q:= TFDQuery.Create(nil);
  try
    Q.Connection:= AStore.GetConnection;
    // Every ref to the form's class or instance name inside a routine body. The
    // ref itself only says "mentions"; the line text below decides "launches".
    Q.SQL.Text:=
      'SELECT DISTINCT r.enclosing_symbol_id AS e, r.start_line AS sl, f.path AS p ' +
      'FROM refs r JOIN files f ON f.id = r.file_id ' +
      'WHERE r.name_text IN (:cls, :nm) AND r.enclosing_symbol_id IS NOT NULL ' +
      'AND f.language LIKE ''delphi%'' ORDER BY f.path, r.start_line';
    Q.ParamByName('cls').AsString:= AY.FormClass;
    Q.ParamByName('nm' ).AsString:= AY.FormName;
    Q.Open;
    FldE:= Q.FieldByName('e');
    FldL:= Q.FieldByName('sl');
    FldP:= Q.FieldByName('p');
    while not Q.Eof do
    begin
      L := Routine(AStore, FldE.AsLargeInt);
      SL:= FldL.AsInteger;
      Lines:= LinesOf(FldP.AsString);
      Q.Next;
      if (L.Id = 0) or SameText(L.Owner, AY.FormClass) or Seen.ContainsKey(L.Id) then Continue;
      if (SL < 1) or (SL > Length(Lines)) then Continue;
      Line:= Lines[SL - 1];
      // TfrmX.ShowForRegion(...): a method of the target called through the
      // class name, i.e. a class method that opens it -- its body decides
      // modality. Checked before the show test, which would substring-match
      // "frmX.Show" inside "TfrmX.ShowForRegion". Constructors (Create*) are
      // launches by the caller and fall through to IsLaunchLine.
      Member:= MemberAfter(Line, AY.FormClass);
      CM:= Default(TRoutineInfo);
      if (Member <> '') and not StartsText('Create', Member) then CM:= FindMethod(AStore, AY.FormClass, Member);
      if CM.Id <> 0 then Modal:= BodyModal(CM)
      else if IsLaunchLine(Line, AY.FormClass) or IsShowLine(Line, AY.FormName) then Modal:= BodyModal(L)
      else Continue;
      Seen.Add(L.Id, True);
      Sites.Add(TPair<TRoutineInfo, string>.Create(L, Modal));
    end;
  finally
    Q.Free;
  end;
  try
    for Site in Sites do TraceLaunch(AStore, AY, Site.Key, Site.Value);
  finally
    Sites.Free;
    Seen.Free;
  end;
end;

procedure TNavBuilder.RunIndexPass;
var
  Y : TFormNode;
  St: TSQLiteSymbolStore;
begin
  for Y in FNodes do
    for St in FStores do
      if St <> nil then IndexPassFor(St, Y);
end;

procedure TNavBuilder.AddTextEdges(ATextEdges: TList<TFormEdge>);
var
  T      : TFormEdge;
  X      : TNavEdge;
  Covered: TDictionary<string, Boolean>;
begin
  // Fallback only: a From -> To pair the index already explains keeps the
  // index's answer, and a form "opening itself" is not a way in.
  Covered:= TDictionary<string, Boolean>.Create;
  try
    for X in FEdges do Covered.AddOrSetValue(LowerCase(X.FromClass + #1 + X.ToClass), True);
    for T in ATextEdges do
    begin
      if SameText(T.FromClass, T.ToClass) or Covered.ContainsKey(LowerCase(T.FromClass + #1 + T.ToClass)) then Continue;
      AddTextEdge(T);
    end;
  finally
    Covered.Free;
  end;
end;

/// <summary>Converts one v5 text-scan edge into a v6 edge, locating its
/// control in the source form's .dfm by handler, then by the v5 caption.</summary>
procedure TNavBuilder.AddTextEdge(const T: TFormEdge);
var
  E: TNavEdge;
begin
  E:= Default(TNavEdge);
  E.FromClass:= T.FromClass;
  E.ToClass  := T.ToClass;
  E.Handler  := T.Handler;
  E.OpenedBy := T.OpenedBy;
  E.Modal    := T.Modal;
  E.Method   := METHOD_TEXT;
  if FClassToNode.ContainsKey(T.FromClass) then
  begin
    E.Ways:= TreeFor(T.FromClass).WaysForHandler(T.Handler);
    // The v5 caption walk may have found the control through an in-form
    // helper the index has no call edge for; locate that control by caption.
    if (Length(E.Ways) = 0) and (Copy(T.Caption, 1, 1) <> '(') then
      E.Ways:= TreeFor(T.FromClass).WaysForCaption(T.Caption);
    if Length(E.Ways) = 0 then E.Note:= T.Handler + ' is not bound to any control in its form (assigned in code?)';
  end
  else
    E.Note:= 'launched by ' + T.FromClass + '; no form caller found';
  AddEdge(E);
end;

/// <summary>RFC 4180 cell that Excel never reads as a formula or a number:
/// non-empty text is always quoted.</summary>
function CsvText(const S: string): string;
begin
  if S = '' then Result:= ''
  else Result:= '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"';
end;

/// <summary>Shortest chain of edge indexes from ARoot to ATarget, over edges
/// whose source is a form; ATracedOnly restricts it to edges with a control.
/// Empty when unreachable.</summary>
function FindNavPath(AEdges: TList<TNavEdge>; AClassToNode: TDictionary<string, TFormNode>; const ARoot, ATarget: string; ATracedOnly: Boolean): TArray<Integer>;
var
  Queue : TQueue<string>;
  Via   : TDictionary<string, Integer>; // lower(class) -> edge index that reached it
  Cur   : string;
  I     : Integer;
  E     : TNavEdge;
  Walk  : string;
begin
  Result:= [];
  if (ARoot = '') or SameText(ARoot, ATarget) then Exit;
  Queue:= TQueue<string>.Create;
  Via  := TDictionary<string, Integer>.Create;
  try
    Via.Add(LowerCase(ARoot), -1);
    Queue.Enqueue(ARoot);
    while Queue.Count > 0 do
    begin
      Cur:= Queue.Dequeue;
      for I:= 0 to AEdges.Count - 1 do
      begin
        E:= AEdges[I];
        if not SameText(E.FromClass, Cur) or Via.ContainsKey(LowerCase(E.ToClass)) then Continue;
        if not AClassToNode.ContainsKey(E.FromClass) then Continue;
        if ATracedOnly and not HasControl(E.Ways) then Continue;
        Via.Add(LowerCase(E.ToClass), I);
        if SameText(E.ToClass, ATarget) then
        begin
          Walk:= ATarget;
          while Via[LowerCase(Walk)] >= 0 do
          begin
            Result:= [Via[LowerCase(Walk)]] + Result;
            Walk:= AEdges[Via[LowerCase(Walk)]].FromClass;
          end;
          Exit;
        end;
        Queue.Enqueue(E.ToClass);
      end;
    end;
  finally
    Via.Free;
    Queue.Free;
  end;
end;

/// <summary>Text for a hop no control fires. A form-lifecycle handler opens the
/// target by itself when its own form opens, which a tester can act on.</summary>
function NoControlText(const AEdge: TNavEdge; AClassToNode: TDictionary<string, TFormNode>): string;
var
  N: TFormNode;
begin
  if (SameText(AEdge.Handler, 'FormCreate') or SameText(AEdge.Handler, 'FormShow') or SameText(AEdge.Handler, 'FormActivate')) and
     AClassToNode.TryGetValue(AEdge.FromClass, N) then
    Result:= '(opens automatically when ' + N.FormName + ' opens: ' + AEdge.Handler + ')'
  else
    Result:= '(no control: ' + AEdge.FromClass + '.' + AEdge.Handler + ')';
end;

/// <summary>Tester-facing text for one hop; AFirst omits the "in frmX:" prefix
/// because the first hop always happens on the root form.</summary>
function HopText(const AEdge: TNavEdge; AClassToNode: TDictionary<string, TFormNode>; AFirst: Boolean): string;
var
  N: TFormNode;
begin
  if Length(AEdge.Ways) > 0 then Result:= AEdge.Ways[0].Location
  else Result:= NoControlText(AEdge, AClassToNode);
  if not AFirst then
  begin
    if AClassToNode.TryGetValue(AEdge.FromClass, N) then Result:= 'in ' + N.FormName + ': ' + Result
    else Result:= 'in ' + AEdge.FromClass + ': ' + Result;
  end;
end;

/// <summary>Shared body of GenerateFormsCsv, operating on already-constructed
/// stores. APrimary is project-scoped (form enumeration + PAS lines); AExtras
/// are searched only when resolving callers. Caller owns lifetime of both
/// APrimary and AExtras (this function never constructs/frees a store).</summary>
function GenerateFormsCsvCore(APrimary: TSQLiteSymbolStore; const AExtras: TArray<TSQLiteSymbolStore>; const AProjectFile, ARootForm, APrimaryDbPath: string): string;
var
  Nodes      : TList<TFormNode>              ;
  Sb         : TStringBuilder                ;
  N          : TFormNode                     ;
  Idx        : Integer                       ;
  ClassToNode: TDictionary<string, TFormNode>;
  TextEdges  : TList<TFormEdge>              ;
  Builder    : TNavBuilder                   ;
  RootClass  : string                        ;
  RootName   : string                        ;
  ProjUnits  : TArray<string>                ;
  Stores     : TArray<TSQLiteSymbolStore>    ;
  St         : TSQLiteSymbolStore            ;
  Path       : TArray<Integer>               ;
  Conf       : string                        ;
  How        : string                        ;
  Notes      : string                        ;
  E          : TNavEdge                      ;
  HasEdge    : Boolean                       ;
  I          : Integer                       ;
  W          : TNavWay                       ;
  WayKeys    : TStringList                   ;
  Also       : TStringList                   ;
  Desc       : string                        ;
  ShownKey   : string                        ;
  RootNode   : TFormNode                     ;
  FromNode   : TFormNode                     ;
  Handler    : string                        ;
  OtherWays  : Integer                       ;
  Parts      : TArray<string>                ;
  AlsoShown  : TArray<string>                ;
begin
  Sb:= TStringBuilder.Create;
  try
    APrimary.Migrate;
    ProjUnits:= LoadProjectUnits(AProjectFile);
    Nodes:= LoadInventory(APrimary, ProjUnits);
    try
      Nodes.Sort(TComparer<TFormNode>.Construct( function(const L, R: TFormNode): Integer begin Result:= CompareText(L.FormName, R.FormName); end));
      ClassToNode:= TDictionary<string, TFormNode>.Create;
      for N in Nodes do ClassToNode.AddOrSetValue(N.FormClass, N);
      TextEdges:= BuildEdges(APrimary, Nodes, ClassToNode, AExtras);
      Stores:= [APrimary];
      for St in AExtras do Stores:= Stores + [St];
      Builder:= TNavBuilder.Create(Stores, Nodes, ClassToNode);
      WayKeys:= TStringList.Create;
      Also   := TStringList.Create;
      try
        // v6: index-first edges, then the v5 text scan merged in as a fallback
        // (AddEdge keeps the first edge per From/To/Handler, so index wins).
        Builder.RunIndexPass;
        Builder.AddTextEdges(TextEdges);
        RootClass:= DetectRoot(AProjectFile, ARootForm, ClassToNode, TextEdges);
        if ClassToNode.TryGetValue(RootClass, RootNode) then RootName:= RootNode.FormName
        else RootName:= RootClass;
        { Schema version lives in schema_meta (written at migrate), NOT in
          PRAGMA user_version (which the engine never writes -> always 0).
          Mirror IsSchemaCurrent's query; a missing table/row falls back to 0. }
        var SchemaVer:= 0;
        var Qver:= TFDQuery.Create(nil);
        try
          Qver.Connection:= APrimary.GetConnection;
          Qver.SQL.Text  := 'SELECT value FROM schema_meta WHERE key = ''schema_version'' LIMIT 1';
          try
            Qver.Open;
            if not Qver.IsEmpty then SchemaVer:= StrToIntDef(Qver.Fields[0].AsString, 0);
          except
            SchemaVer:= 0; // pre-schema_meta db
          end;
        finally
          Qver.Free;
        end;
        Sb.Append('#,Form,Unit,How to open,Click,Control type,Handler,Opened by,Modal,Before you start,Other ways in,Confidence,Tester result,Notes').Append(#13#10);
        Idx:= 0;
        { v4 Layer 0 (spec D0) db-scope guardrail counter: forms with a known
          caller that could not be walked back to the root. }
        var UnresolvedWithCaller:= 0;
        for N in Nodes do
        begin
          Inc(Idx);
          E:= Default(TNavEdge);
          HasEdge:= False;
          Notes:= '';
          OtherWays:= 0;
          if SameText(N.FormClass, RootClass) then
          begin
            How := 'Main form (opens at startup)';
            Conf:= CONF_TRACED;
          end
          else
          begin
            Conf:= CONF_TRACED;
            Path:= FindNavPath(Builder.Edges, ClassToNode, RootClass, N.FormClass, True);
            if Length(Path) = 0 then
            begin
              Conf:= CONF_HANDLER_ONLY;
              Path:= FindNavPath(Builder.Edges, ClassToNode, RootClass, N.FormClass, False);
            end;
            if Length(Path) > 0 then
            begin
              SetLength(Parts, Length(Path));
              for I:= 0 to High(Path) do Parts[I]:= HopText(Builder.Edges[Path[I]], ClassToNode, I = 0);
              How:= string.Join(' -> ', Parts);
              E:= Builder.Edges[Path[High(Path)]];
              HasEdge:= True;
            end
            else
            begin
              Conf:= CONF_UNRESOLVED;
              if RootName <> '' then How:= '(no path from ' + RootName + ')'
              else How:= '(no root form detected)';
              // Best known way in, even though it does not connect to the root:
              // a form source with a control first, then any form source, then any.
              for I:= 0 to Builder.Edges.Count - 1 do
                if SameText(Builder.Edges[I].ToClass, N.FormClass) and ClassToNode.ContainsKey(Builder.Edges[I].FromClass) and (Length(Builder.Edges[I].Ways) > 0) then
                begin
                  E      := Builder.Edges[I];
                  HasEdge:= True;
                  Break;
                end;
              if not HasEdge then
                for I:= 0 to Builder.Edges.Count - 1 do
                  if SameText(Builder.Edges[I].ToClass, N.FormClass) then
                  begin
                    E      := Builder.Edges[I];
                    HasEdge:= True;
                    Break;
                  end;
              if HasEdge then
              begin
                Inc(UnresolvedWithCaller);
                if ClassToNode.ContainsKey(E.FromClass) then How:= How + ' ' + HopText(E, ClassToNode, False);
              end;
            end;
          end;

          if HasEdge then
          begin
            // Every distinct way into this form: one per control, or one per
            // handler when no control fires it.
            WayKeys.Clear;
            Also.Clear;
            if Length(E.Ways) > 0 then ShownKey:= LowerCase(E.FromClass + #1 + E.Ways[0].Location)
            else ShownKey:= LowerCase(E.FromClass + #1 + '#' + E.Handler);
            for I:= 0 to Builder.Edges.Count - 1 do
            begin
              if not SameText(Builder.Edges[I].ToClass, N.FormClass) then Continue;
              if not ClassToNode.TryGetValue(Builder.Edges[I].FromClass, FromNode) then Continue;
              if Length(Builder.Edges[I].Ways) = 0 then
              begin
                Desc:= LowerCase(Builder.Edges[I].FromClass + #1 + '#' + Builder.Edges[I].Handler);
                if WayKeys.IndexOf(Desc) < 0 then
                begin
                  WayKeys.Add(Desc);
                  if Desc <> ShownKey then Also.Add('in ' + FromNode.FormName + ': ' + NoControlText(Builder.Edges[I], ClassToNode));
                end;
              end
              else
                for W in Builder.Edges[I].Ways do
                begin
                  Desc:= LowerCase(Builder.Edges[I].FromClass + #1 + W.Location);
                  if WayKeys.IndexOf(Desc) >= 0 then Continue;
                  WayKeys.Add(Desc);
                  if Desc = ShownKey then Continue;
                  if SameText(Builder.Edges[I].FromClass, E.FromClass) then Also.Add(W.Location)
                  else Also.Add('in ' + FromNode.FormName + ': ' + W.Location);
                end;
            end;
            OtherWays:= Also.Count;
            Parts:= ['found by: ' + E.Method];
            if E.Note <> '' then Parts:= Parts + [E.Note];
            if Also.Count > 0 then
            begin
              // Up to FORMS_ALSO_MAX listed; the rest only counted.
              AlsoShown:= Copy(Also.ToStringArray, 0, FORMS_ALSO_MAX);
              if Also.Count > FORMS_ALSO_MAX then AlsoShown:= AlsoShown + [Format('(+%d more)', [Also.Count - FORMS_ALSO_MAX])];
              Parts:= Parts + ['also: ' + string.Join(' | ', AlsoShown)];
            end;
            Notes:= string.Join('; ', Parts);
          end
          else if Conf = CONF_UNRESOLVED then
          begin
            for var KP in KnownPopupForms do
              if KP.Name = LowerCase(N.FormName) then
              begin
                Notes:= KP.Note;
                Break;
              end;
            if Notes = '' then Notes:= 'no caller found (index or text scan)';
          end;

          if HasEdge and ClassToNode.ContainsKey(E.FromClass) then Handler:= E.FromClass + '.' + E.Handler
          else Handler:= E.Handler;
          Sb.Append(Idx).Append(',')
            .Append(CsvText(N.FormName)).Append(',')
            .Append(CsvText(N.UnitName)).Append(',')
            .Append(CsvText(How)).Append(',');
          if HasEdge and HasControl(E.Ways) then
            Sb.Append(CsvText(E.Ways[0].Click)).Append(',').Append(CsvText(E.Ways[0].CtrlClass)).Append(',')
          else
            Sb.Append(',,');
          Sb.Append(CsvText(Handler)).Append(',')
            .Append(CsvText(E.OpenedBy)).Append(',')
            .Append(CsvText(E.Modal)).Append(',')
            .Append(CsvText(E.Hint)).Append(',')
            .Append(OtherWays).Append(',')
            .Append(CsvText(Conf)).Append(',')
            .Append(',') // Tester result: left blank for the tester
            .Append(CsvText(Notes))
            .Append(#13#10);
        end; // for
        { v4 Layer 0 (spec D0) guardrail: announce, on stderr only, when forms
          have an indexed caller that could not be walked back to the root --
          usually a db-scope problem (the launch bodies live in a unit outside
          this db, e.g. COMMON missing from a CLIENT-only index). stderr-only:
          this does NOT alter any CSV cell. }
        if UnresolvedWithCaller > 0 then
          Writeln(ErrOutput, Format('forms-csv: %d form(s) with callers could not be traced to MAIN -- db may not include COMMON (interface-dispatch launch bodies); run against the full-tree index', [UnresolvedWithCaller]));
        { Metadata footer: 13 leading commas put the '#' cell in the 14th (Notes)
          column, out of the numbered-row column so it never reads as a data row. }
        Sb.Append(',,,,,,,,,,,,,')
          .Append(CsvText('# forms-csv algorithm v' + FORMS_CSV_ALGORITHM +
                  ' | db: ' + APrimaryDbPath +
                  ' | schema v' + IntToStr(SchemaVer) +
                  ' | ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now)))
          .Append(#13#10);
        Result:= Sb.ToString;
      finally
        Also.Free;
        WayKeys.Free;
        Builder.Free;
        TextEdges.Free;
        ClassToNode.Free;
      end; // try
    finally
      Nodes.Free;
    end; // try
  finally
    Sb.Free;
  end; // try
end; // function

/// <summary>Generates the forms navigation-map CSV. ADbPaths[0] is the project
/// index (drives which forms are enumerated + PAS-line counts); ADbPaths[1..] are
/// additional indexes searched ONLY to resolve callers/landings whose call site
/// lives in another DB (e.g. COMMON). A form with no caller in ANY store is
/// reported unresolved with 'no caller found'.</summary>
/// <param name="ADbPaths">1+ SQLite index paths; [0] authoritative, rest search-scope.</param>
/// <param name="AProjectFile">Project (.dpr/.dproj) whose units scope the inventory.</param>
/// <param name="ARootForm">Root form class (e.g. TfrmMAIN); '' = auto-detect.</param>
/// <returns>ANSI CSV text incl. the FORMS_CSV_ALGORITHM provenance footer.</returns>
function GenerateFormsCsv(const ADbPaths: TArray<string>; const AProjectFile, ARootForm: string): string;
var
  Primary: TSQLiteSymbolStore;
  Extras : TArray<TSQLiteSymbolStore>;
  I      : Integer;
begin
  if Length(ADbPaths) = 0 then raise Exception.Create('forms-csv: no DB paths');
  Primary:= TSQLiteSymbolStore.Create(ADbPaths[0]);
  try
    SetLength(Extras, 0);
    for I:= 1 to High(ADbPaths) do
      Extras:= Extras + [TSQLiteSymbolStore.Create(ADbPaths[I])];
    try
      Result:= GenerateFormsCsvCore(Primary, Extras, AProjectFile, ARootForm, ADbPaths[0]);
    finally
      for var St in Extras do St.Free;
    end;
  finally
    Primary.Free;
  end;
end;

function GenerateFormsCsv(const ADbPath, AProjectFile, ARootForm: string): string;
begin
  Result:= GenerateFormsCsv([ADbPath], AProjectFile, ARootForm);
end;

end.
