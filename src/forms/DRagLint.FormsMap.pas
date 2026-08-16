unit DRagLint.FormsMap;

/// <summary>Builds a per-form navigation-map CSV for a project: how a tester
/// reaches each form from the application's root form, plus which forms launch
/// it. Reuses the drag-lint index (form/component symbols + event-binding refs +
/// construction refs) and reads caption literals from .dfm line ranges.</summary>
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
  /// Used by: DRagLint.FormsMap.LoadInventory (DRagLint.FormsMap.pas), DRagLint.FormsMap.BuildEdges (DRagLint.FormsMap.pas), DRagLint.FormsMap.NavPath (DRagLint.FormsMap.pas), DRagLint.FormsMap.CalledFrom (DRagLint.FormsMap.pas), DRagLint.FormsMap.GenerateFormsCsvCore (DRagLint.FormsMap.pas)
  /// Used in units: DRagLint.FormsMap
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
  /// Used by: DRagLint.FormsMap.BuildEdges.TryAddEdge (DRagLint.FormsMap.pas), DRagLint.FormsMap.BuildEdges (DRagLint.FormsMap.pas), DRagLint.FormsMap.NavPath (DRagLint.FormsMap.pas), DRagLint.FormsMap.DetectRoot (DRagLint.FormsMap.pas), DRagLint.FormsMap.CalledFrom (DRagLint.FormsMap.pas)
  /// Used in units: DRagLint.FormsMap
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TFormEdge = record
    FromClass: string;
    ToClass  : string;
    Caption  : string;
  end;

/// <summary>Lists distinct parent forms that directly launch AToClass, each as its
/// form Name with the resolved caption in parentheses; ';'-separated. Caption is
/// omitted when the edge caption is a '(via ...)' gap marker.</summary>
/// <param name="AEdges">All launch edges built by BuildEdges.</param>
/// <param name="AClassToNode">Class-name to TFormNode lookup.</param>
/// <param name="AToClass">The form class whose callers we want.</param>
/// <returns>Semicolon-separated list, e.g. "frmList (Edit Item)" or "".</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.FormsMap.GenerateFormsCsvCore (DRagLint.FormsMap.pas)
/// Calls: Copy, SameText
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function CalledFrom(AEdges: TList<TFormEdge>; AClassToNode: TDictionary<string, TFormNode>; const AToClass: string): string;

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
/// Called from: DRagLint.FormsMap.GenerateFormsCsv/3 (DRagLint.FormsMap.pas), DRagLint.CLI.DoFormsCsv (DRagLint.CLI.pas)
/// Calls: DRagLint.FormsMap.GenerateFormsCsv/3
/// Returns: GenerateFormsCsv([ADbPath], AProjectFile, ARootForm)
/// Overload 1 of 2
/// Recursive
/// Pure
/// <!-- drag-lint:auto END -->
/// </remarks>
function GenerateFormsCsv(const ADbPath, AProjectFile, ARootForm: string): string; overload;

/// <summary>Generates the forms navigation-map CSV. ADbPaths[0] is the project
/// index (drives which forms are enumerated + PAS-line counts); ADbPaths[1..] are
/// additional indexes searched ONLY to resolve callers/landings whose call site
/// lives in another DB (e.g. COMMON). A form with no caller in ANY store is DEAD.</summary>
/// <param name="ADbPaths">1+ SQLite index paths; [0] authoritative, rest search-scope.</param>
/// <param name="AProjectFile">Project (.dpr/.dproj) whose units scope the inventory.</param>
/// <param name="ARootForm">Root form class (e.g. TfrmMAIN); '' = auto-detect.</param>
/// <returns>ANSI CSV text incl. the FORMS_CSV_ALGORITHM provenance footer.</returns>
/// <exception cref="Exception">If ADbPaths is empty, the index cannot be opened,
/// or no root can be resolved.</exception>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Calls: DRagLint.FormsMap.GenerateFormsCsvCore, DRagLint.Storage.SQLite.TSQLiteSymbolStore.Create
/// Returns: GenerateFormsCsvCore(Primary, Extras, AProjectFile, ARootForm, ADbPaths[0])
/// Overload 2 of 2
/// Pure
/// <seealso cref="DRagLint.FormsMap.GenerateFormsCsvCore"/>
/// <seealso cref="DRagLint.Storage.SQLite.TSQLiteSymbolStore.Create"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function GenerateFormsCsv(const ADbPaths: TArray<string>; const AProjectFile, ARootForm: string): string; overload;

implementation

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
  FORMS_CSV_ALGORITHM = '5'; // bump when BuildEdges / NavPath algorithm changes

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

  procedure TryAddEdge(const AFrom, ATo, ACaption: string);
  var EKey: string; E: TFormEdge;
  begin
    EKey:= AFrom + #1 + ATo + #1 + ACaption;
    if SeenEdges.IndexOf(EKey) >= 0 then Exit;
    SeenEdges.Add(EKey);
    E:= Default(TFormEdge);
    E.FromClass:= AFrom;
    E.ToClass  := ATo;
    E.Caption  := ACaption;
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
          TryAddEdge(FormCls, ATargetClass, Cap);
        end
        else
          TryAddEdge(TPath.GetFileNameWithoutExtension(APath) + '.' + Rout,
                     ATargetClass, '(via hook)');
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
      TryAddEdge(OC, ATargetClass, Cap);
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
          TryAddEdge(FormCls, ATargetClass, Cap);
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

type
  /// <summary>One navigation hop: the button caption (or synthetic '(via X)'
  /// marker) and the FormName of the form the click lands on.</summary>
  THop = record
    Caption    : string;
    LandingName: string;
  end;

/// <summary>Renders the root form name plus hops into the Navigation cell text.
/// v3 (interleaved): every caption is followed by the landing form's name, e.g.
/// frmMAIN -> 'Job List' -> frmJobList -> ... -> Z14slctFrm. Quoted captions keep
/// quotes; synthetic '(...)' captions render unquoted. This is the SOLE place hop
/// data becomes text -- change future path formats here only.</summary>
function RenderPath(const ARootName: string; const AHops: TArray<THop>): string;
var
  H: THop;
begin
  Result:= ARootName;
  for H in AHops do
  begin
    if Copy(H.Caption, 1, 1) = '(' then Result:= Result + ' -> ' + H.Caption
    else Result:= Result + ' -> ''' + H.Caption + '''';
    Result:= Result + ' -> ' + H.LandingName;
  end; // for
end; // function

/// <summary>BFS shortest navigation path from the root form to AToClass.
/// Returns "RootName -> 'Cap1' -> frmNext -> 'Cap2' -> frmDest" or '' if unreachable.</summary>
function NavPath(AEdges: TList<TFormEdge>; AClassToNode: TDictionary<string, TFormNode>; const ARootClass, AToClass: string): string;
type
  TStep = record Cls: string; Hops: TArray<THop>; end;
var
  Queue   : TQueue<TStep>               ;
  Visited : TDictionary<string, Boolean>;
  Cur     : TStep                       ;
  Nxt     : TStep                       ;
  E       : TFormEdge                   ;
  RootNode: TFormNode                   ;
  RootName: string                      ;
  ToNode  : TFormNode                   ;
  Hop     : THop                        ;
begin
  Result:= '';
  if SameText(ARootClass, AToClass) then Exit;
  Queue:= TQueue<TStep>.Create;
  Visited:= TDictionary<string, Boolean>.Create;
  try
    if AClassToNode.TryGetValue(ARootClass, RootNode) then RootName:= RootNode.FormName
    else RootName:= ARootClass;
    Cur.Cls := ARootClass;
    Cur.Hops:= nil;
    Queue.Enqueue(Cur);
    Visited.Add(ARootClass, True);
    while Queue.Count > 0 do
    begin
      Cur:= Queue.Dequeue;
      for E in AEdges do
        if SameText(E.FromClass, Cur.Cls) and not Visited.ContainsKey(E.ToClass) then
        begin
          Hop.Caption:= E.Caption;
          if AClassToNode.TryGetValue(E.ToClass, ToNode) then Hop.LandingName:= ToNode.FormName
          else Hop.LandingName:= E.ToClass; // defensive: edges target inventory nodes today
          Nxt.Cls := E.ToClass;
          Nxt.Hops:= Cur.Hops + [Hop]; // fresh array per branch -- no aliasing
          if SameText(E.ToClass, AToClass) then Exit(RenderPath(RootName, Nxt.Hops));
          Visited.Add(E.ToClass, True);
          Queue.Enqueue(Nxt);
        end;
    end; // while
  finally
    Queue.Free;
    Visited.Free;
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

function CalledFrom(AEdges: TList<TFormEdge>; AClassToNode: TDictionary<string, TFormNode>; const AToClass: string): string;
var
  E         : TFormEdge  ;
  Seen      : TStringList;
  ParentNode: TFormNode  ;
  Item      : string     ;
begin
  Result:= '';
  Seen:= TStringList.Create;
  try
    Seen.Sorted    := True;
    Seen.Duplicates:= dupIgnore;
    for E in AEdges do
      if SameText(E.ToClass, AToClass) then
      begin
        if AClassToNode.TryGetValue(E.FromClass, ParentNode) then Item:= ParentNode.FormName
        else Item:= E.FromClass;
        if Copy(E.Caption, 1, 1) <> '(' then Item:= Item + ' (' + E.Caption + ')';
        if Seen.IndexOf(Item) < 0 then
        begin
          Seen.Add(Item);
          if Result <> '' then Result:= Result + '; ';
          Result:= Result + Item;
        end;
      end;
  finally
    Seen.Free;
  end; // try
end; // function

/// <summary>Shared body of GenerateFormsCsv, operating on already-constructed
/// stores. APrimary is project-scoped (form enumeration + PAS lines); AExtras
/// are searched only when BuildEdges resolves callers. Caller owns lifetime of
/// both APrimary and AExtras (this function never constructs/frees a store).</summary>
function GenerateFormsCsvCore(APrimary: TSQLiteSymbolStore; const AExtras: TArray<TSQLiteSymbolStore>; const AProjectFile, ARootForm, APrimaryDbPath: string): string;
var
  Nodes      : TList<TFormNode>              ;
  Sb         : TStringBuilder                ;
  N          : TFormNode                     ;
  Idx        : Integer                       ;
  ClassToNode: TDictionary<string, TFormNode>;
  Edges      : TList<TFormEdge>              ;
  RootClass  : string                        ;
  Nav        : string                        ;
  ProjUnits  : TArray<string>                ;
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
      Edges:= BuildEdges(APrimary, Nodes, ClassToNode, AExtras);
      try
        RootClass:= DetectRoot(AProjectFile, ARootForm, ClassToNode, Edges);
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
        Sb.Append('#,Unit,FormName,PAS lines,Navigation,Called From,Notes').Append(#13#10);
        Idx:= 0;
        { v4 Layer 0 (spec D0) db-scope guardrail counter. Counts forms that ended
          '(no path from MAIN)' yet have a NON-EMPTY Called From: a known caller
          routine IS indexed but its upward chain to MAIN is severed -- the
          signature of an interface-dispatch launch body whose bridge to MAIN
          lives outside the scanned db (e.g. COMMON absent from a CLIENT-only db).
          Forms with EMPTY Called From are genuine dead forms (no callers at all)
          and are deliberately NOT counted. }
        var UnresolvedWithCaller:= 0;
        for N in Nodes do
        begin
          Inc(Idx);
          Nav:= '';
          if RootClass <> '' then
          begin
            Nav:= NavPath(Edges, ClassToNode, RootClass, N.FormClass);
            if (Nav = '') and not SameText(N.FormClass, RootClass) then Nav:= '(no path from MAIN)';
          end;
          var CF:= CalledFrom(Edges, ClassToNode, N.FormClass);
          if (Nav = '(no path from MAIN)') and (CF <> '') then Inc(UnresolvedWithCaller);
          var Notes:= '';
          if (Nav = '(no path from MAIN)') and (CF = '') then
          begin
            var PopupNote:= '';
            var FormNameLower:= LowerCase(N.FormName);
            for var KP in KnownPopupForms do
              if KP.Name = FormNameLower then begin PopupNote:= KP.Note; Break; end;
            if PopupNote <> '' then Notes:= PopupNote
            else Notes:= 'DEAD FORM - no callers found';
          end;
          Sb.Append(Idx).Append(',').Append(CsvField(N.UnitName)).Append(',').Append(CsvField(N.FormName)).Append(',').Append(N.PasLineCount).Append(',')
            .Append(CsvField(Nav)).Append(',').Append(CsvField(CF)).Append(',').Append(CsvField(Notes))
            .Append(#13#10);
        end; // for
        { v4 Layer 0 (spec D0) guardrail: announce, on stderr only, when forms
          have an indexed caller that could not be walked back to MAIN -- almost
          always a db-scope problem (the interface-dispatch launch bodies live in
          a unit outside this db, e.g. COMMON missing from a CLIENT-only index).
          A scope gap thus announces itself instead of silently printing
          '(no path)'. stderr-only: this does NOT alter any CSV cell. }
        if UnresolvedWithCaller > 0 then
          Writeln(ErrOutput, Format('forms-csv: %d form(s) with callers could not be traced to MAIN -- db may not include COMMON (interface-dispatch launch bodies); run against the full-tree index', [UnresolvedWithCaller]));
        { Metadata footer: the algorithm/db/schema/timestamp line moved from the
          top to the bottom so the column header is row 1 (spreadsheet-friendly).
          6 leading commas push the '#' cell into the 7th (Notes) column, out of
          the numbered-row column so it never looks like a data row. CsvField the
          whole line since APrimaryDbPath may contain characters worth quoting. }
        Sb.Append(',,,,,,')
          .Append(CsvField('# forms-csv algorithm v' + FORMS_CSV_ALGORITHM +
                  ' | db: ' + APrimaryDbPath +
                  ' | schema v' + IntToStr(SchemaVer) +
                  ' | ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Now)))
          .Append(#13#10);
        Result:= Sb.ToString;
      finally
        Edges.Free;
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
/// lives in another DB (e.g. COMMON). A form with no caller in ANY store is DEAD.</summary>
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
