unit DRagLint.Index.Closure;

// Compile-closure resolver: given a .dpr/.dproj, returns the set of
// project-local source files that would actually be compiled -- the member
// units, every unit they pull in transitively via `uses` that resolves to a
// project-local file (NOT under a Delphi Library/Browsing path), plus any
// {$I}/{$INCLUDE} include files encountered along the way.
//
// Loose files sitting in the project folders that nothing references are
// NOT included in the closure.  If an `exclude` glob matches a file that IS
// reached via `uses`, the file is still included in Files but a Warning is
// emitted naming the using unit.
//
// Parsing limitation: `uses` extraction is a pragmatic text scan (regex,
// word-boundary, skip inside block comments/string literals as best-effort).
// It handles dotted unit names (System.SysUtils) but treats them as unresolved
// when no matching file is found on the search path.  Conditional compilation
// ({$IFDEF}) is NOT evaluated -- all branches are scanned, so units mentioned
// in the inactive branch may be enqueued but will simply not resolve to a
// project-local file and will be skipped.

interface

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.Generics.Collections
  , System.RegularExpressions
  ;

type
  /// <summary>Holds the result of a compile-closure walk.</summary>
  TClosureResult = record
    /// <summary>Absolute .pas/.inc paths in the project-local closure, deduped.</summary>
    Files: TArray<string>;
    /// <summary>Human-readable warnings, e.g. excluded-but-in-closure messages.</summary>
    Warnings: TArray<string>;
    /// <summary>The unit name that pulled each Files[i] into the closure.
    /// Parallel to Files: UsedBy[i] is the using-unit for Files[i].
    /// '&lt;project&gt;' for entries seeded directly from the .dpr/.dproj member list.
    /// Existing callers need not change -- they simply ignore this field.</summary>
    UsedBy: TArray<string>;
  end;

  /// <summary>Resolves the compile closure of a Delphi .dpr or .dproj project.</summary>
  TClosureResolver = class
    strict private
      FLibraryRoots: TArray<string>;

      // ---- unit-file resolution helpers ----------------------------------------

      // Return True if AFile is rooted under any library root (case-insensitive).
      function IsLibraryFile(const AFile: string): Boolean;

      // Search ASearchPaths for <AUnitName>.pas (case-insensitive first-file-wins).
      // Returns the full absolute path, or '' if not found.
      function FindUnitFile(const AUnitName: string; const ASearchPaths: TArray<string>): string;

      // Search ASearchPaths + the dir of AFromFile for AIncName (as-given, then
      // relative to each search path).  Returns absolute path or ''.
      function FindIncFile(const AIncName, AFromDir: string; const ASearchPaths: TArray<string>): string;

      // ---- .dpr/.dproj parsing --------------------------------------------------

      // Parse the .dpr `uses` clause: fill AUnitNames (name) + AUnitFiles
      // (the `in 'path'` specifier when given, or '' when not).
      // Both lists are parallel (same index).
      procedure ParseDprUses(const AContent, ABaseDir: string; AUnitNames, AUnitFiles: TStringList);

      // Return the `<DCCReference Include="...">` file paths from a .dproj.
      procedure ParseDprojRefs(const AContent, ABaseDir: string; AFiles: TStringList);

      // Read search paths from the .dproj's DCC_UnitSearchPath tags.
      procedure ParseDprojSearchPaths(const AContent, ABaseDir: string; APaths: TStringList);

      // ---- source text scanning ------------------------------------------------

      // Strip block comments { } and (* *) and string literals from AText so
      // that `uses`/`{$I}` scanning does not pick up identifiers inside them.
      // Does NOT strip // comments (they end at EOL, and our regex won't cross
      // lines for uses-identifiers anyway).
      function StripCommentsAndStrings(const AText: string): string;

      // Scan AText for uses-clause identifiers (both interface and implementation
      // sections).  Returns a list of dotted unit names.
      function ExtractUses(const AText: string): TArray<string>;

      // Scan AText for {$I filename} / {$INCLUDE filename} directives.
      function ExtractIncludes(const AText: string): TArray<string>;

    public
      /// <summary>
      /// Create a resolver that treats files under ALibraryRoots as library
      /// (excluded from the closure).
      /// Pass TProjectResolver.ResolveLibraryPaths as ALibraryRoots.
      /// </summary>
      constructor Create(const ALibraryRoots: TArray<string>);

      /// <summary>
      /// Resolve the compile closure of a .dpr or .dproj project.
      /// Returns the set of project-local .pas/.inc files that get compiled:
      /// the project member units + transitive project-local uses + {$I} files.
      /// Files under any ALibraryRoot are silently excluded and not recursed.
      /// A file that is reached via uses AND matches an AExclude glob pattern is
      /// still added to Files but also produces a Warning entry.
      /// </summary>
      /// <param name="AProjectFile">Absolute or relative path to the .dpr or .dproj.</param>
      /// <param name="AExclude">Glob patterns for "stale" files (still included in
      /// closure but warned). Pass [] for no exclusion warnings.</param>
      /// <returns>TClosureResult with deduped Files list and Warnings.</returns>
      function Resolve(const AProjectFile: string; const AExclude: TArray<string>): TClosureResult;
  end;

implementation

uses
  DRagLint.Index.Glob
  ;

{ ---- TClosureResolver ------------------------------------------------------- }

constructor TClosureResolver.Create(const ALibraryRoots: TArray<string>);
begin
  inherited Create;
  FLibraryRoots:= ALibraryRoots;
end;

function TClosureResolver.IsLibraryFile(const AFile: string): Boolean;
var
  NormFile: string;
  NormRoot: string;
  Root    : string;
begin
  NormFile:= LowerCase(StringReplace(AFile, '/', '\', [rfReplaceAll]));
  for Root in FLibraryRoots do
  begin
    NormRoot:= LowerCase(StringReplace(Root, '/', '\', [rfReplaceAll]));
    if not NormRoot.EndsWith('\') then NormRoot:= NormRoot + '\';
    if NormFile.StartsWith(NormRoot) then Exit(True);
  end;
  Result:= False;
end;

function TClosureResolver.FindUnitFile(const AUnitName: string; const ASearchPaths: TArray<string>): string;
var
  Dir      : string;
  Candidate: string;
  FileName : string;
begin
  // Dotted names like System.SysUtils become System.SysUtils.pas
  FileName:= AUnitName + '.pas';
  for Dir in ASearchPaths do
  begin
    Candidate:= TPath.Combine(Dir, FileName);
    if TFile.Exists(Candidate) then Exit(TPath.GetFullPath(Candidate));
  end;
  Result:= '';
end;

function TClosureResolver.FindIncFile(const AIncName, AFromDir: string; const ASearchPaths: TArray<string>): string;
var
  Dir      : string;
  Candidate: string;
begin
  // Try relative to the including file's directory first
  Candidate:= TPath.Combine(AFromDir, AIncName);
  if TFile.Exists(Candidate) then Exit(TPath.GetFullPath(Candidate));
  // Then try each search path
  for Dir in ASearchPaths do
  begin
    Candidate:= TPath.Combine(Dir, AIncName);
    if TFile.Exists(Candidate) then Exit(TPath.GetFullPath(Candidate));
  end;
  Result:= '';
end;

procedure TClosureResolver.ParseDprUses(const AContent, ABaseDir: string; AUnitNames, AUnitFiles: TStringList);
// Parse:  uses  unitname [in 'file.pas'] [, ...] ;
// Also handles the program/library's own `uses` clause which may span lines.
// We look for the FIRST `uses` block (the program uses) and also any
// subsequent ones (though .dpr files typically have only one).
const
  // Matches: <unitname> [in '<path>']  (dotted names, spaces OK around 'in')
  PAT_ITEM = '([A-Za-z_][A-Za-z0-9_.]*)\s*(?:in\s*''([^'']*)''\s*)?';
var
  UsesPos  : Integer         ;
  SemiPos  : Integer         ;
  UsesBlock: string          ;
  Stripped : string          ;
  ItemPat  : string          ;
  Matches  : TMatchCollection;
  M        : TMatch          ;
  UName    : string          ;
  UFile    : string          ;
  I        : Integer         ;
  Len      : Integer         ;
  InBrace  : Boolean         ;
  SB       : TStringBuilder  ;
begin
  // Find `uses` keyword (word-boundary, case-insensitive)
  var Re:= TRegEx.Create('\buses\b', [roIgnoreCase]);
  var UsesMatch:= Re.Match(AContent);
  if not UsesMatch.Success then Exit;

  UsesPos:= UsesMatch.Index + UsesMatch.Length - 1; // 1-based, end of 'uses'
  // Find the closing semicolon of the uses block
  SemiPos:= Pos(';', AContent, UsesPos);
  if SemiPos = 0 then Exit;

  UsesBlock:= Copy(AContent, UsesPos + 1, SemiPos - UsesPos - 1);

  // Strip {$IFDEF}/{$ENDIF}/{form-comment} braces so PAT_ITEM only sees real
  // unit names.  Real .dpr uses blocks can contain:
  //   {$IFDEF EurekaLog}  ... {$ENDIF EurekaLog}
  //   UnitName in 'file.pas' {FormName: TFormClass}
  // Without stripping, PAT_ITEM would match identifiers inside the braces
  // (IFDEF, EurekaLog, FormName, etc.) as spurious unit names, and on some
  // inputs the Delphi regex engine raises ERegularExpressionError when
  // accessing optional group 2 for those spurious matches.
  SB:= TStringBuilder.Create(Length(UsesBlock));
  try
    I:= 1;
    Len:= Length(UsesBlock);
    InBrace:= False;
    while I <= Len do
    begin
      if InBrace then
      begin
        if UsesBlock[I] = '}' then InBrace:= False;
        SB.Append(' ');
      end
      else
      begin
        if UsesBlock[I] = '{' then
        begin
          InBrace:= True;
          SB.Append(' ');
        end
        else SB.Append(UsesBlock[I]);
      end;
      Inc(I);
    end; // while
    Stripped:= SB.ToString;
  finally
    SB.Free;
  end; // try

  ItemPat:= PAT_ITEM;
  Matches:= TRegEx.Matches(Stripped, ItemPat, [roIgnoreCase]);
  for M in Matches do
  begin
    UName:= M.Groups[1].Value.Trim;
    if SameText(UName, '') then Continue;
    // Skip keywords that regex might catch
    if SameText(UName, 'in') then Continue;

    UFile:= '';
    // Guard: PAT_ITEM has 2 capture groups; access group 2 only when present.
    if (M.Groups.Count > 2) and M.Groups[2].Success then
    begin
      UFile:= M.Groups[2].Value.Trim;
      if (UFile <> '') and (not TPath.IsPathRooted(UFile)) then UFile:= TPath.GetFullPath(TPath.Combine(ABaseDir, UFile));
    end;

    AUnitNames.Add(UName);
    AUnitFiles.Add(UFile);
  end; // for
end; // procedure

procedure TClosureResolver.ParseDprojRefs(const AContent, ABaseDir: string; AFiles: TStringList);
// Matches: <DCCReference Include="some\path.pas"/>
var
  Pat     : string          ;
  Matches : TMatchCollection;
  M       : TMatch          ;
  RefPath : string          ;
  Resolved: string          ;
begin
  Pat:= '<DCCReference\s+Include="([^"]+\.pas)"';
  Matches:= TRegEx.Matches(AContent, Pat, [roIgnoreCase]);
  for M in Matches do
  begin
    RefPath:= M.Groups[1].Value;
    if not TPath.IsPathRooted(RefPath) then Resolved:= TPath.GetFullPath(TPath.Combine(ABaseDir, RefPath))
    else Resolved:= TPath.GetFullPath(RefPath);
    AFiles.Add(Resolved);
  end;
end;

procedure TClosureResolver.ParseDprojSearchPaths(const AContent, ABaseDir: string; APaths: TStringList);
var
  Pat     : string          ;
  Matches : TMatchCollection;
  M       : TMatch          ;
  RawList : string          ;
  P       : string          ;
  Resolved: string          ;
  Parts   : TArray<string>  ;
begin
  Pat:= '<DCC_UnitSearchPath>(.*?)</DCC_UnitSearchPath>';
  Matches:= TRegEx.Matches(AContent, Pat, [roIgnoreCase, roSingleLine]);
  for M in Matches do
  begin
    RawList:= M.Groups[1].Value;
    Parts:= RawList.Split([';']);
    for P in Parts do
    begin
      Resolved:= P.Trim;
      if Resolved = '' then Continue;
      // Minimal macro expansion: $(BDS) is a library path, skip it
      if Pos('$(', Resolved) > 0 then Continue;
      if not TPath.IsPathRooted(Resolved) then Resolved:= TPath.GetFullPath(TPath.Combine(ABaseDir, Resolved));
      if TDirectory.Exists(Resolved) then APaths.Add(Resolved);
    end;
  end;
end; // procedure

function TClosureResolver.StripCommentsAndStrings(const AText: string): string;
// Replace block comment content with spaces (preserving length so positions
// are not disturbed) and string literal content with spaces.
// This is a best-effort pass; nested comments are not valid Pascal so we
// don't handle them.
var
  I       : Integer       ;
  Len     : Integer       ;
  C       : Char          ;
  InBrace : Boolean       ; // { } comment vs (* *) comment
  InParen : Boolean       ;
  InString: Boolean       ;
  SB      : TStringBuilder;
begin
  SB:= TStringBuilder.Create(Length(AText));
  try
    I:= 1;
    Len:= Length(AText);
    InBrace := False;
    InParen := False;
    InString:= False;
    while I <= Len do
    begin
      C:= AText[I];
      if InString then
      begin
        if C = '''' then
        begin
          // Doubled quote inside string is escaped
          if (I < Len) and (AText[I + 1] = '''') then
          begin
            SB.Append('  ');
            Inc(I, 2);
            Continue;
          end;
          InString:= False;
          SB.Append(' ');
        end
        else SB.Append(' ');
        Inc(I);
        Continue;
      end; // if
      if InBrace then
      begin
        if C = '}' then
        begin
          InBrace:= False;
          SB.Append(' ');
        end
        else SB.Append(' ');
        Inc(I);
        Continue;
      end;
      if InParen then
      begin
        if (C = '*') and (I < Len) and (AText[I + 1] = ')') then
        begin
          InParen:= False;
          SB.Append('  ');
          Inc(I, 2);
          Continue;
        end
        else SB.Append(' ');
        Inc(I);
        Continue;
      end;
      // Not inside any comment or string
      if C = '''' then
      begin
        InString:= True;
        SB.Append(' ');
        Inc(I);
        Continue;
      end;
      if C = '{' then
      begin
        // Check for {$I ...} or {$INCLUDE ...} -- these are DIRECTIVES, not
        // comments, and should NOT be stripped here.  We will pick them up in
        // ExtractIncludes separately on the ORIGINAL text.
        // However to avoid regex picking up words inside ordinary {..} comments
        // we still blank them out in the uses-scan output.
        InBrace:= True;
        SB.Append(' ');
        Inc(I);
        Continue;
      end;
      if (C = '(') and (I < Len) and (AText[I + 1] = '*') then
      begin
        InParen:= True;
        SB.Append('  ');
        Inc(I, 2);
        Continue;
      end;
      // // line comment: skip to end of line
      if (C = '/') and (I < Len) and (AText[I + 1] = '/') then
      begin
        while (I <= Len) and (AText[I] <> #10) do
        begin
          SB.Append(' ');
          Inc(I);
        end;
        Continue;
      end;
      SB.Append(C);
      Inc(I);
    end; // while
    Result:= SB.ToString;
  finally
    SB.Free;
  end; // try
end; // function

function TClosureResolver.ExtractUses(const AText: string): TArray<string>;
// Scan stripped text for ALL `uses` clauses (interface + implementation).
// Each clause: `uses <name> [, <name>]* ;`
// We collect every dotted-identifier list between `uses` and `;`.
var
  Stripped : string          ;
  Clause   : string          ;
  Token    : string          ;
  ReUses   : TRegEx          ;
  ReIdent  : TRegEx          ;
  UsesMatch: TMatch          ;
  Pos      : Integer         ;
  SemiPos  : Integer         ;
  ClauseEnd: Integer         ;
  Matches  : TMatchCollection;
  M        : TMatch          ;
  List     : TList<string>   ;
begin
  Stripped:= StripCommentsAndStrings(AText);
  List:= TList<string>.Create;
  try
    ReUses := TRegEx.Create('\buses\b'               , [roIgnoreCase]);
    ReIdent:= TRegEx.Create('[A-Za-z_][A-Za-z0-9_.]*', [            ]);

    UsesMatch:= ReUses.Match(Stripped);
    while UsesMatch.Success do
    begin
      Pos:= UsesMatch.Index + UsesMatch.Length; // 1-based char after 'uses'
      SemiPos:= System.Pos(';', Stripped, Pos);
      if SemiPos = 0 then Break;

      ClauseEnd:= SemiPos - Pos;
      Clause:= Copy(Stripped, Pos, ClauseEnd);

      Matches:= ReIdent.Matches(Clause);
      for M in Matches do
      begin
        Token:= M.Value;
        // Skip `in` keyword (appears after unit name in .dpr-style files
        // scanned here -- though that style is usually only in the .dpr itself)
        if SameText(Token, 'in') then Continue;
        List.Add(Token);
      end;

      // Advance past this semicolon
      UsesMatch:= ReUses.Match(Stripped, SemiPos);
    end; // while

    Result:= List.ToArray;
  finally
    List.Free;
  end; // try
end; // function

function TClosureResolver.ExtractIncludes(const AText: string): TArray<string>;
// Scan the ORIGINAL text (not stripped) for {$I name} and {$INCLUDE name}.
// The directive is inside braces so is a special compiler-directive form.
// Recognises both:   {$I filename}   and   {$INCLUDE filename}
var
  Re     : TRegEx          ;
  Matches: TMatchCollection;
  M      : TMatch          ;
  List   : TList<string>   ;
begin
  List:= TList<string>.Create;
  try
    Re:= TRegEx.Create( '\{\$(?:I|INCLUDE)\s+([^\}\s]+)\s*\}', [roIgnoreCase]);
    Matches:= Re.Matches(AText);
    for M in Matches do
      if M.Groups[1].Success then List.Add(M.Groups[1].Value.Trim);
    Result:= List.ToArray;
  finally
    List.Free;
  end;
end;

function TClosureResolver.Resolve(const AProjectFile: string; const AExclude: TArray<string>): TClosureResult;
type
  // Queue entry: unit name + resolved file (may be '' = not yet resolved)
  TWorkItem = record
    UnitName : string; // may be '' for inc files enqueued directly
    FilePath : string; // absolute resolved path (may be '' if resolution pending)
    UsingUnit: string; // unit that pulled this in (for warning message)
  end;
var
  ProjectAbs : string                      ;
  BaseDir    : string                      ;
  Ext        : string                      ;
  Content    : string                      ;
  SearchPaths: TStringList                 ; // ordered search-path list
  Visited    : TDictionary<string, Boolean>; // lowercase abs-path -> True
  Files      : TList<string>               ;
  Warnings   : TList<string>               ;
  UsedByList : TList<string>               ; // parallel to Files; using-unit per entry
  Queue      : TQueue<TWorkItem>           ;

  UnitNames    : TStringList;
  UnitFilePaths: TStringList;
  DprojRefFiles: TStringList;

  SearchArr   : TArray<string>;
  Item        : TWorkItem     ;
  ResolvedFile: string        ;
  UnitDir     : string        ;
  SubUses     : TArray<string>;
  SubIncs     : TArray<string>;
  IncFile     : string        ;
  SubName     : string        ;
  Wi          : TWorkItem     ;
  BaseName    : string        ;

  procedure EnqueueFile(const AAbsPath, AUsingUnit: string);
  var
    LKey: string   ;
    W2  : TWorkItem;
  begin
    LKey:= LowerCase(AAbsPath);
    if Visited.ContainsKey(LKey) then Exit;
    Visited.Add(LKey, True);
    Files     .Add(AAbsPath  );
    UsedByList.Add(AUsingUnit);
    W2.UnitName := '';
    W2.FilePath := AAbsPath;
    W2.UsingUnit:= AUsingUnit;
    Queue.Enqueue(W2);
    // Exclude-but-in-closure warning
    if TGlob.MatchesAny(TPath.GetFileName(AAbsPath), AExclude) then
      Warnings.Add('WARN: ' + AAbsPath + ' is in the compile closure (used by ' + AUsingUnit + ') but matches an exclude pattern');
  end;

begin
  ProjectAbs:= TPath.GetFullPath(AProjectFile);
  if not TFile.Exists(ProjectAbs) then raise Exception.CreateFmt('Project file not found: %s', [ProjectAbs]);

  BaseDir:= TPath.GetDirectoryName(ProjectAbs);
  Ext:= LowerCase(TPath.GetExtension(ProjectAbs));

  Files     := TList<string>.Create;
  Warnings  := TList<string>.Create;
  UsedByList:= TList<string>.Create;
  Visited:= TDictionary<string, Boolean>.Create;
  Queue:= TQueue<TWorkItem>.Create;
  SearchPaths:= TStringList.Create;
  SearchPaths.CaseSensitive:= False;

  UnitNames    := TStringList.Create;
  UnitFilePaths:= TStringList.Create;
  DprojRefFiles:= TStringList.Create;
  try
    // --- Step 1: build search paths -------------------------------------------
    // Always include the project base directory first
    SearchPaths.Add(BaseDir);

    Content:= TFile.ReadAllText(ProjectAbs);

    if Ext = '.dproj' then
    begin
      ParseDprojSearchPaths(Content, BaseDir, SearchPaths);
      // Also try to find the sibling .dpr
      var DprPath:= TPath.ChangeExtension(ProjectAbs, '.dpr');
      if TFile.Exists(DprPath) then
      begin
        var DprContent:= TFile.ReadAllText(DprPath);
        ParseDprUses(DprContent, BaseDir, UnitNames, UnitFilePaths);
      end;
      // Seed from DCCReference entries
      ParseDprojRefs(Content, BaseDir, DprojRefFiles);
    end
    else // .dpr  (or .dpk)
    begin
      ParseDprUses(Content, BaseDir, UnitNames, UnitFilePaths);
    end;

    SearchArr:= SearchPaths.ToStringArray;

    // --- Step 2: seed the worklist -------------------------------------------
    // .dproj: seed from DCCReference paths
    for var F in DprojRefFiles do
    begin
      if TFile.Exists(F) and not IsLibraryFile(F) then
      begin
        Wi.UnitName:= TPath.GetFileNameWithoutExtension(F);
        Wi.FilePath := F;
        Wi.UsingUnit:= '<project>';
        EnqueueFile(F, '<project>');
      end;
    end;

    // .dpr / sibling .dpr for .dproj: seed from parsed uses clause
    for var I:= 0 to UnitNames.Count - 1 do
    begin
      var UN:= UnitNames    [I];
      var UF:= UnitFilePaths[I];
      ResolvedFile:= '';

      if UF <> '' then
      begin
        // `in 'path'` specifier: use that path directly
        if TFile.Exists(UF) then ResolvedFile:= UF;
      end;

      if ResolvedFile = '' then ResolvedFile:= FindUnitFile(UN, SearchArr);

      if (ResolvedFile <> '') and not IsLibraryFile(ResolvedFile) then
      begin
        Wi.UnitName := UN;
        Wi.FilePath := ResolvedFile;
        Wi.UsingUnit:= '<project>';
        // EnqueueFile handles dedup + warning
        EnqueueFile(ResolvedFile, '<project>');
      end;
    end; // for

    // --- Step 3: BFS ---------------------------------------------------------
    while Queue.Count > 0 do
    begin
      Item:= Queue.Dequeue;

      if Item.FilePath = '' then Continue;
      if not TFile.Exists(Item.FilePath) then Continue;

      var FileExt:= LowerCase(TPath.GetExtension(Item.FilePath));
      if FileExt = '.inc' then Continue; // don't recurse into .inc for uses, just leave it in Files

      UnitDir:= TPath.GetDirectoryName(Item.FilePath);
      var UnitContent:= TFile.ReadAllText(Item.FilePath);

      // (a) Recurse into `uses` references
      SubUses:= ExtractUses(UnitContent);
      for SubName in SubUses do
      begin
        if SubName = '' then Continue;
        ResolvedFile:= FindUnitFile(SubName, SearchArr);
        // Also try relative to the unit's own directory (not always on path)
        if (ResolvedFile = '') and TFile.Exists(TPath.Combine(UnitDir, SubName + '.pas')) then ResolvedFile:= TPath.GetFullPath( TPath.Combine(UnitDir, SubName + '.pas'));

        if (ResolvedFile <> '') and not IsLibraryFile(ResolvedFile) then
        begin
          // Determine the "using unit" name for warnings
          BaseName:= TPath.GetFileNameWithoutExtension(Item.FilePath);
          EnqueueFile(ResolvedFile, BaseName);
        end;
      end;

      // (b) {$I}/{$INCLUDE} files -- add but don't recurse for uses
      SubIncs:= ExtractIncludes(UnitContent);
      for IncFile in SubIncs do
      begin
        ResolvedFile:= FindIncFile(IncFile, UnitDir, SearchArr);
        if (ResolvedFile <> '') and not IsLibraryFile(ResolvedFile) then
        begin
          BaseName:= TPath.GetFileNameWithoutExtension(Item.FilePath);
          EnqueueFile(ResolvedFile, BaseName);
        end;
      end;
    end; // while

    Result.Files   := Files     .ToArray;
    Result.Warnings:= Warnings  .ToArray;
    Result.UsedBy  := UsedByList.ToArray;
  finally
    DprojRefFiles.Free;
    UnitFilePaths.Free;
    UnitNames.Free;
    SearchPaths.Free;
    Queue.Free;
    Visited.Free;
    Warnings.Free;
    UsedByList.Free;
    Files.Free;
  end; // try
end; // begin

end.
