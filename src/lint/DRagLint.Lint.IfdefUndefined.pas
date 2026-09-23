unit DRagLint.Lint.IfdefUndefined;

// Rule ifdef-undefined-symbol: an {$IFDEF X}, {$IFNDEF X}, or a defined(X)
// inside {$IF} / {$ELSEIF}, where X is defined NOWHERE any build of the project
// could see it. The branch is then dead (or, for IFNDEF, unconditional) in
// every build -- usually a typo such as EUREKALGO for EUREKALOG.
//
// WHY THIS UNIT IS NOT UNDER src\preprocess. The extractor-version guard
// (tests\autotest\run_extractor_version_guard.ps1) hashes every unit under
// src\preprocess, and a hash change forces an extractor bump -- a full re-parse
// of every index. This rule changes no extraction, so it lives in the lint
// layer and only CALLS the preprocess lexer and PlatformBuiltins, read-only.
//
// WHAT "DEFINED SOMEWHERE" MEANS (each clause is a negative control in
// tests\autotest\run_ifdef_undefined_symbol.ps1):
//   1. a compiler-predefined conditional for ANY target platform -- see
//      IsCompilerPredefined for the list and where it comes from;
//   2. any DCC_Define of ANY PropertyGroup of the .dproj -- the UNION over
//      every config x every platform (Base, Base_<P>, Cfg_N, Cfg_N_<P>, and
//      custom configs), because a symbol set by one build is not dead code;
//   3. a {$DEFINE X} ANYWHERE in the unit or in the {$I} files it includes,
//      transitively -- anywhere, not only earlier, so the include-guard idiom
//      (IFNDEF X, then DEFINE X) is silent;
//   4. the user's "ifdef_allow" list in drag-lint-lint.json -- for defines set
//      in third-party .inc files the project never includes directly.
//
// DELIBERATELY NOT counted: a {$DEFINE} in ANOTHER unit of the closure, or in
// the .dpr. The compiler scopes a $DEFINE to the module that contains it, so
// such a define never reaches this unit and the branch here really is dead.
//
// CONSERVATIVE EXITS (no finding rather than a guess):
//   * no .dproj known -> the caller does not run the rule at all;
//   * a {$I} include that cannot be found beside the unit, beside the .dproj
//     or on the .dproj's literal (macro-free) include/search paths -> the whole
//     file is skipped, because the missing file might define anything.
//
// Encoding note: this unit writes directive text only inside // comments and
// string constants, never inside a brace comment.

interface

uses
  System.SysUtils,
  DRagLint.Core.Model;

const
  /// <summary>The rule id reported by TIfdefUndefinedCheck.</summary>
  IFDEF_UNDEFINED_RULE_ID = 'ifdef-undefined-symbol';

type
  /// <summary>Finds conditional-compilation tests of symbols that no build of
  /// the owning project defines.</summary>
  /// <remarks>Stateless; every method is a static class function and safe to
  /// call from any thread. Reads files, never writes them.</remarks>
  TIfdefUndefinedCheck = class
  public
    /// <summary>The union of every DCC_Define in every PropertyGroup of a
    /// .dproj -- all configs, all platforms -- lowercased and deduplicated, with
    /// MSBuild property references such as the DCC_Define recursion token
    /// dropped.</summary>
    /// <param name="ADprojPath">The project file. Missing or unreadable yields
    /// an empty array; it never raises.</param>
    /// <returns>Lowercased symbol names, in first-seen order.</returns>
    class function DprojDefineUnion(const ADprojPath: string): TArray<string>; static;

    /// <summary>True when ASymbol is a conditional the Delphi compiler (or the
    /// RAD Studio build targets) defines by itself for SOME target platform,
    /// so no .dproj or $DEFINE is needed for it to be live.</summary>
    /// <param name="ASymbol">The symbol, any case.</param>
    /// <returns>True for VER followed by digits, any CPU-prefixed name, the
    /// named platform/feature conditionals, and PlatformBuiltins of Win32 and
    /// Win64. DEBUG and RELEASE are NOT predefined -- the IDE templates put them
    /// in DCC_Define -- and return False.</returns>
    class function IsCompilerPredefined(const ASymbol: string): Boolean; static;

    /// <summary>Checks each file for conditional tests of symbols that are
    /// defined nowhere, under the definition in the unit header.</summary>
    /// <param name="AFiles">Source files to check (.pas, .dpr, .dpk, .inc).
    /// Unreadable files are skipped.</param>
    /// <param name="ADprojPath">The owning project's .dproj. Must name an
    /// existing file: with no project the rule cannot know the build's defines,
    /// so an empty or missing path returns no findings.</param>
    /// <param name="AAllow">Extra symbols to treat as defined (the ifdef_allow
    /// config list); compared case-insensitively.</param>
    /// <param name="AExtraIncludeDirs">Directories searched for {$I} files
    /// after the file's own folder -- for a file analysed from a temporary
    /// snapshot, pass the real file's folder.</param>
    /// <returns>One warning per undefined symbol per directive, anchored at the
    /// directive's line; the message names the symbol and, when one is within
    /// edit distance 2, the nearest defined symbol.</returns>
    class function CheckFiles(const AFiles: TArray<string>; const ADprojPath: string;
      const AAllow: TArray<string>;
      const AExtraIncludeDirs: TArray<string> = nil): TArray<TLintFinding>; static;
  end;

implementation

uses
  System.Classes,
  System.Math,
  System.StrUtils,
  System.IOUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  DRagLint.Preprocess.Types,
  DRagLint.Preprocess.Lexer,
  DRagLint.Preprocess.Profile;

const
  // Include nesting deeper than this is treated as unresolvable (a cycle guard
  // on top of the visited set).
  MAX_INCLUDE_DEPTH = 16;
  // Largest edit distance for which a "did you mean" suggestion is offered.
  MAX_SUGGEST_DISTANCE = 2;
  // Shortest symbol a suggestion is offered for: at distance 2 a three-letter
  // name is "near" half the define list.
  MIN_SUGGEST_LENGTH = 4;
  // Prefixes of the two predefined families matched by pattern (lowercase).
  VER_PREFIX = 'ver';
  CPU_PREFIX = 'cpu';
  // The line-feed byte a directive's column is counted back to.
  LF_BYTE = 10;

  // Compiler-predefined conditionals, from the "Predefined Conditionals" table
  // of the RAD Studio docwiki page "Conditional compilation (Delphi)"
  // (docwiki.embarcadero.com/RADStudio/en/Conditional_compilation_(Delphi)).
  // Union over every platform: a symbol live on ANY target is not dead code.
  // VER<nnn> and CPU* are matched by pattern in IsCompilerPredefined instead.
  // FRAMEWORK_VCL / FRAMEWORK_FMX are set by the build from <FrameworkType>.
  PREDEFINED: array[0..40] of string = (
    'dcc', 'conditionalexpressions', 'unicode', 'nativecode', 'console',
    'mswindows', 'win32', 'win64',
    'macos', 'macos32', 'macos64', 'osx', 'osx32', 'osx64',
    'ios', 'ios32', 'ios64', 'iossimulator',
    'android', 'android32', 'android64',
    'linux', 'linux32', 'linux64', 'posix', 'posix32', 'posix64',
    'assembler', 'autorefcount', 'nextgen', 'weakref', 'weakinstref',
    'weakintfref', 'externallinker', 'elf', 'pic', 'underscoreimportname',
    'align_stack', 'pc_mapped_exceptions', 'framework_vcl', 'framework_fmx');

type
  // Symbol set: lowercased key -> the spelling first seen (for suggestions).
  TSymbolSet = TDictionary<string, string>;

function IsIdentStart(AChar: Char): Boolean;
begin
  Result:= CharInSet(AChar, ['A'..'Z', 'a'..'z', '_']);
end;

function IsIdentChar(AChar: Char): Boolean;
begin
  Result:= CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

// The leading identifier of a directive argument ('' when there is none).
// Delphi ignores anything after the symbol in IFDEF / IFNDEF / DEFINE.
function LeadingIdent(const AArgs: string): string;
var
  Len: Integer;
begin
  Result:= '';
  if (AArgs = '') or not IsIdentStart(AArgs[1]) then Exit;
  Len:= 1;
  while (Len < Length(AArgs)) and IsIdentChar(AArgs[Len + 1]) do Inc(Len);
  Result:= Copy(AArgs, 1, Len);
end;

// Levenshtein distance, case-insensitive.
function EditDistance(const A, B: string): Integer;
var
  Prev, Cur: TArray<Integer>;
  I, J     : Integer;
  Cost     : Integer;
  LA, LB   : string;
begin
  LA:= LowerCase(A);
  LB:= LowerCase(B);
  SetLength(Prev, Length(LB) + 1);
  SetLength(Cur , Length(LB) + 1);
  for J:= 0 to High(Prev) do
    Prev[J]:= J;
  for I:= 1 to Length(LA) do
  begin
    Cur[0]:= I;
    for J:= 1 to Length(LB) do
    begin
      Cost:= if LA[I] = LB[J] then 0 else 1;
      Cur[J]:= Min(Min(Prev[J] + 1, Cur[J - 1] + 1), Prev[J - 1] + Cost);
    end;
    Prev:= Copy(Cur);
  end;
  Result:= Prev[Length(LB)];
end;

// Reads a text file, or returns False when it cannot be read (missing, locked,
// or not decodable). Never raises.
function TryReadSource(const APath: string; out AText: string): Boolean;
begin
  Result:= True;
  AText:= '';
  try
    AText:= TFile.ReadAllText(APath);
  except
    on E: EInOutError     do Result:= False;
    on E: EStreamError    do Result:= False;
    on E: EEncodingError  do Result:= False;
  end;
end;

// Every DCC_Define symbol of the .dproj as SPELLED there, keyed lowercase
// (first spelling wins). Every DCC_Define in the file counts, whatever
// PropertyGroup condition guards it: that is exactly "every config x every
// platform".
procedure CollectDprojDefines(const ADprojPath: string; ASet: TSymbolSet;
  AOrder: TList<string>);
var
  Content: string;
  M      : TMatch;
  Part   : string;
  Sym    : string;
begin
  if (ADprojPath = '') or not TryReadSource(ADprojPath, Content) then Exit;
  M:= TRegEx.Match(Content, '<DCC_Define>(.*?)</DCC_Define>', [roIgnoreCase, roSingleLine]);
  while M.Success do
  begin
    for Part in M.Groups[1].Value.Split([';']) do
    begin
      Sym:= Trim(Part);
      // Drop blanks and MSBuild property references such as the recursion token.
      if (Sym = '') or StartsStr('$(', Sym) then Continue;
      if not ASet.ContainsKey(LowerCase(Sym)) then
      begin
        ASet.Add(LowerCase(Sym), Sym);
        if AOrder <> nil then AOrder.Add(LowerCase(Sym));
      end;
    end;
    M:= M.NextMatch;
  end;
end;

class function TIfdefUndefinedCheck.DprojDefineUnion(const ADprojPath: string): TArray<string>;
var
  SymSet: TSymbolSet;
  Order : TList<string>;
begin
  SymSet:= TSymbolSet.Create;
  Order := TList<string>.Create;
  try
    CollectDprojDefines(ADprojPath, SymSet, Order);
    Result:= Order.ToArray;
  finally
    Order.Free;
    SymSet.Free;
  end;
end;

// VER<nnn>: every compiler version. A test of an OLD version is deliberate
// backward-compatibility code, not a typo. ASym is lowercase.
function IsVersionSymbol(const ASym: string): Boolean;
var
  I: Integer;
begin
  Result:= StartsStr(VER_PREFIX, ASym) and (Length(ASym) > Length(VER_PREFIX));
  for I:= Length(VER_PREFIX) + 1 to Length(ASym) do
    Result:= Result and CharInSet(ASym[I], ['0'..'9']);
end;

function InList(const ASym: string; const AList: array of string): Boolean;
var
  Name: string;
begin
  Result:= False;
  for Name in AList do
    if Name = ASym then Exit(True);
end;

class function TIfdefUndefinedCheck.IsCompilerPredefined(const ASymbol: string): Boolean;
var
  Sym: string;
begin
  Sym:= LowerCase(ASymbol);
  // CPU*: CPUX86, CPUX64, CPU32BITS, CPU64BITS, CPUARM, CPUARM64, CPU386, ...
  // The PlatformBuiltins lists are the indexer's own, so this rule can never
  // disagree with the define profile the preprocessor uses.
  if Sym = '' then Exit(False);
  if IsVersionSymbol(Sym) or StartsStr(CPU_PREFIX, Sym) then Exit(True);
  Result:= InList(Sym, PREDEFINED) or InList(Sym, PlatformBuiltins('Win32'))
    or InList(Sym, PlatformBuiltins('Win64'));
end;

// Include and unit search directories the .dproj names LITERALLY. An entry that
// uses an MSBuild macro cannot be expanded here and is dropped; a relative
// entry is resolved against the .dproj's folder.
function DprojSearchDirs(const ADprojPath: string): TArray<string>;
var
  Content: string;
  ProjDir: string;
  M      : TMatch;
  Part   : string;
  Dir    : string;
begin
  ProjDir:= ExtractFilePath(ExpandFileName(ADprojPath));
  Result:= [ProjDir];
  if not TryReadSource(ADprojPath, Content) then Exit;
  M:= TRegEx.Match(Content, '<(DCC_IncludePath|DCC_UnitSearchPath)>(.*?)</\1>',
    [roIgnoreCase, roSingleLine]);
  while M.Success do
  begin
    for Part in M.Groups[2].Value.Split([';']) do
    begin
      Dir:= Trim(Part);
      if (Dir = '') or (Pos('$(', Dir) > 0) then Continue;
      if TPath.IsRelativePath(Dir) then Dir:= TPath.Combine(ProjDir, Dir);
      Result:= Result + [ExpandFileName(Dir)];
    end;
    M:= M.NextMatch;
  end;
end;

// The file an {$I} argument names, or '' when it cannot be found. Quotes are
// stripped; a name with no extension also tries '.inc' and '.pas', as dcc does.
function ResolveInclude(const AArgs, AOwnDir: string;
  const ASearchDirs: TArray<string>): string;
var
  Name : string;
  Dir  : string;
  Cand : string;
  Names: TArray<string>;
  Dirs : TArray<string>;
begin
  Result:= '';
  Name:= Trim(AArgs);
  if (Length(Name) >= 2) and (Name[1] = '''') then
    Name:= Copy(Name, 2, Length(Name) - 2);
  if Name = '' then Exit;
  Names:= [Name];
  if ExtractFileExt(Name) = '' then Names:= Names + [Name + '.inc', Name + '.pas'];
  Dirs:= [AOwnDir] + ASearchDirs;
  for Dir in Dirs do
    for Cand in Names do
      if TFile.Exists(TPath.Combine(Dir, Cand)) then
        Exit(ExpandFileName(TPath.Combine(Dir, Cand)));
end;

// One conditional test found in the unit being checked.
type
  TSymbolTest = record
    Symbol: string;
    Line  : Integer; // 1-based
    Col   : Integer; // 1-based
  end;

// A directive's 1-based column: bytes since the last LF before it. The source
// is ASCII by house rule, so a byte offset is a character offset here.
function DirectiveCol(const ABytes: TBytes; ASrcStart: Integer): Integer;
var
  P: Integer;
begin
  P:= ASrcStart - 1;
  while (P >= 0) and (ABytes[P] <> LF_BYTE) do Dec(P);
  Result:= ASrcStart - P;
end;

// Collects the $DEFINEs of AText (and, transitively, of its includes) into
// ADefined, and -- when ATests is not nil -- the conditional tests of AText
// itself. Returns False when an include cannot be resolved.
function ScanSource(const AText, AOwnDir: string; const ASearchDirs: TArray<string>;
  ADefined: TSymbolSet; ATests: TList<TSymbolTest>; AVisited: TDictionary<string, Byte>;
  ADepth: Integer): Boolean;
var
  Chunks : TArray<TPPChunk>;
  Ch     : TPPChunk;
  Sym    : string;
  IncPath: string;
  IncText: string;
  M      : TMatch;
  Bytes  : TBytes;
  Test   : TSymbolTest;
begin
  Result:= True;
  Chunks:= LexDirectives(AText);
  Bytes:= TEncoding.UTF8.GetBytes(AText);
  for Ch in Chunks do
  begin
    if Ch.Kind <> ckDirective then Continue;
    if Ch.Dir = 'define' then
    begin
      Sym:= LeadingIdent(Ch.Args);
      if (Sym <> '') and not ADefined.ContainsKey(LowerCase(Sym)) then
        ADefined.Add(LowerCase(Sym), Sym);
    end
    else if (Ch.Dir = 'i') or (Ch.Dir = 'include') then
    begin
      // {$I+} / {$I-} is the I/O-checking switch, not an include.
      if (Ch.Args = '') or CharInSet(Ch.Args[1], ['+', '-']) then Continue;
      IncPath:= ResolveInclude(Ch.Args, AOwnDir, ASearchDirs);
      if (IncPath = '') or (ADepth >= MAX_INCLUDE_DEPTH) then Exit(False);
      if AVisited.ContainsKey(LowerCase(IncPath)) then Continue;
      AVisited.Add(LowerCase(IncPath), 0);
      if not TryReadSource(IncPath, IncText) then Exit(False);
      // Tests inside an include are the include's own business: only its
      // DEFINEs are collected here.
      if not ScanSource(IncText, ExtractFilePath(IncPath), ASearchDirs, ADefined, nil,
        AVisited, ADepth + 1) then Exit(False);
    end
    else if ATests <> nil then
    begin
      Test:= Default(TSymbolTest);
      Test.Line:= Ch.Line + 1;
      Test.Col := DirectiveCol(Bytes, Ch.SrcStart);
      if (Ch.Dir = 'ifdef') or (Ch.Dir = 'ifndef') then
      begin
        Test.Symbol:= LeadingIdent(Ch.Args);
        if Test.Symbol <> '' then ATests.Add(Test);
      end
      else if (Ch.Dir = 'if') or (Ch.Dir = 'elseif') then
      begin
        M:= TRegEx.Match(Ch.Args, '\bdefined\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)', [roIgnoreCase]);
        while M.Success do
        begin
          Test.Symbol:= M.Groups[1].Value;
          ATests.Add(Test);
          M:= M.NextMatch;
        end;
      end;
    end;
  end;
end;

// The nearest known spelling within MAX_SUGGEST_DISTANCE, or ''.
function NearestSymbol(const ASymbol: string; AProjectDefs, AUnitDefs: TSymbolSet): string;
var
  Best    : Integer;
  D       : Integer;
  Spelling: string;
  Source  : TSymbolSet;
  Sources : TArray<TSymbolSet>;
begin
  Result:= '';
  if Length(ASymbol) < MIN_SUGGEST_LENGTH then Exit;
  Best:= MAX_SUGGEST_DISTANCE + 1;
  Sources:= [AProjectDefs, AUnitDefs];
  for Source in Sources do
    for Spelling in Source.Values do
    begin
      D:= EditDistance(ASymbol, Spelling);
      if (D < Best) or ((D = Best) and (CompareText(Spelling, Result) < 0)) then
      begin
        Best:= D;
        Result:= Spelling;
      end;
    end;
end;

class function TIfdefUndefinedCheck.CheckFiles(const AFiles: TArray<string>;
  const ADprojPath: string; const AAllow: TArray<string>;
  const AExtraIncludeDirs: TArray<string>): TArray<TLintFinding>;
var
  ProjectDefs: TSymbolSet;
  UnitDefs   : TSymbolSet;
  Visited    : TDictionary<string, Byte>;
  Tests      : TList<TSymbolTest>;
  Findings   : TList<TLintFinding>;
  SearchDirs : TArray<string>;
  FilePath   : string;
  Text       : string;
  Sym        : string;
  Test       : TSymbolTest;
  Finding    : TLintFinding;
  Hint       : string;
  ProjName   : string;
begin
  Result:= nil;
  if (ADprojPath = '') or not TFile.Exists(ADprojPath) then Exit;
  ProjName:= ExtractFileName(ADprojPath);

  ProjectDefs:= TSymbolSet.Create;
  UnitDefs   := TSymbolSet.Create;
  Visited    := TDictionary<string, Byte>.Create;
  Tests      := TList<TSymbolTest>.Create;
  Findings   := TList<TLintFinding>.Create;
  try
    // Read the dproj ONCE for every file of the run.
    CollectDprojDefines(ADprojPath, ProjectDefs, nil);
    for Sym in AAllow do
      if Trim(Sym) <> '' then ProjectDefs.AddOrSetValue(LowerCase(Trim(Sym)), Trim(Sym));
    SearchDirs:= AExtraIncludeDirs + DprojSearchDirs(ADprojPath);

    for FilePath in AFiles do
    begin
      if not TryReadSource(FilePath, Text) then Continue;
      UnitDefs.Clear;
      Visited.Clear;
      Tests.Clear;
      // An unresolvable include might define anything: skip the file.
      if not ScanSource(Text, ExtractFilePath(ExpandFileName(FilePath)), SearchDirs,
        UnitDefs, Tests, Visited, 0) then Continue;
      for Test in Tests do
      begin
        Sym:= LowerCase(Test.Symbol);
        if ProjectDefs.ContainsKey(Sym) or UnitDefs.ContainsKey(Sym)
          or IsCompilerPredefined(Sym) then Continue;
        Hint:= NearestSymbol(Test.Symbol, ProjectDefs, UnitDefs);
        Finding:= Default(TLintFinding);
        Finding.RuleId    := IFDEF_UNDEFINED_RULE_ID;
        Finding.Severity  := 'warning';
        Finding.FilePath  := FilePath;
        Finding.StartLine := Test.Line;
        Finding.StartCol  := Test.Col;
        Finding.EndLine   := Test.Line;
        Finding.EndCol    := Test.Col;
        Finding.SymbolName:= Test.Symbol;
        Finding.Message   := Format(
          'Conditional symbol ''%s'' is defined nowhere: not predefined by the compiler, ' +
          'not in any DCC_Define of %s (any config or platform), and not $DEFINEd in this ' +
          'file or its includes -- this branch is dead in every build',
          [Test.Symbol, ProjName]);
        if Hint <> '' then
          Finding.Message:= Finding.Message + Format(' (did you mean ''%s''?)', [Hint]);
        Findings.Add(Finding);
      end;
    end;
    Result:= Findings.ToArray;
  finally
    Findings.Free;
    Tests.Free;
    Visited.Free;
    UnitDefs.Free;
    ProjectDefs.Free;
  end;
end;

end.
