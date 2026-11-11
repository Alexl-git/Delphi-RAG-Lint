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
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces;

const
  /// <summary>The rule id reported by TIfdefUndefinedCheck.</summary>
  IFDEF_UNDEFINED_RULE_ID = 'ifdef-undefined-symbol';

type
  /// <summary>One conditional test found in a unit: the symbol of an
  /// {$IFDEF} / {$IFNDEF}, or of a defined() inside {$IF} / {$ELSEIF}.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Lint.IfdefUndefined.pas) ?, DRagLint.Lint.IfdefUndefined.AddDirectiveTestsAt (DRagLint.Lint.IfdefUndefined.pas), DRagLint.Lint.IfdefUndefined.ScanFile (DRagLint.Lint.IfdefUndefined.pas) ?, DRagLint.Lint.IfdefUndefined.ScanRows (DRagLint.Lint.IfdefUndefined.pas) ?, DRagLint.Lint.IfdefUndefined.ScanSource (DRagLint.Lint.IfdefUndefined.pas) ? (+4 more)</para>
  /// <para>Used in units: DRagLint.Lint.IfdefUndefined, DRagLint.Lint.PlatformDivergent</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TConditionalTest = record
    /// <summary>The tested symbol as spelled.</summary>
    Symbol: string;
    /// <summary>1-based line of the directive.</summary>
    Line  : Integer;
    /// <summary>1-based column of the directive.</summary>
    Col   : Integer;
  end;

  /// <summary>Finds conditional-compilation tests of symbols that no build of
  /// the owning project defines.</summary>
  /// <remarks>
  /// Stateless; every method is a static class function and safe to
  /// call from any thread. Reads files, never writes them.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.Lint.PlatformDivergent.CollectDivergences (DRagLint.Lint.PlatformDivergent.pas), DRagLint.Lint.PlatformDivergent.TPlatformDivergentCheck.CheckFiles (DRagLint.Lint.PlatformDivergent.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Lint.PlatformDivergent</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TIfdefUndefinedCheck = class
  public
    /// <summary>The union of every DCC_Define in every PropertyGroup of a
    /// .dproj -- all configs, all platforms -- lowercased and deduplicated, with
    /// MSBuild property references such as the DCC_Define recursion token
    /// dropped.</summary>
    /// <param name="ADprojPath">The project file. Missing or unreadable yields
    /// an empty array; it never raises.</param>
    /// <returns>Lowercased symbol names, in first-seen order.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Calls: DRagLint.Lint.IfdefUndefined.CollectDprojDefines</para>
    /// <para>Returns: Order.ToArray</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.CollectDprojDefines"/>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.TIfdefUndefinedCheck.CheckFiles"/>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.TIfdefUndefinedCheck.IsCompilerPredefined"/>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.TIfdefUndefinedCheck.ProjectSearchDirs"/>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.TIfdefUndefinedCheck.ScanFileTests"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function DprojDefineUnion(const ADprojPath: string): TArray<string>; static;

    /// <summary>True when ASymbol is a conditional the Delphi compiler (or the
    /// RAD Studio build targets) defines by itself for SOME target platform,
    /// so no .dproj or $DEFINE is needed for it to be live.</summary>
    /// <param name="ASymbol">The symbol, any case.</param>
    /// <returns>True for VER followed by digits, any CPU-prefixed name, the
    /// named platform/feature conditionals, and PlatformBuiltins of every
    /// platform in KnownPlatforms. DEBUG and RELEASE are NOT predefined -- the IDE templates put them
    /// in DCC_Define -- and return False.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.IfdefUndefined.TIfdefUndefinedCheck.CheckFiles (DRagLint.Lint.IfdefUndefined.pas), DRagLint.Lint.PlatformDivergent.CollectDivergences (DRagLint.Lint.PlatformDivergent.pas)</para>
    /// <para>Calls: DRagLint.Lint.IfdefUndefined.InList, DRagLint.Lint.IfdefUndefined.IsVersionSymbol, DRagLint.Preprocess.Profile.KnownPlatforms, DRagLint.Preprocess.Profile.PlatformBuiltins, LowerCase, StartsStr</para>
    /// <para>Returns: False</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.InList"/>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.IsVersionSymbol"/>
    /// <seealso cref="DRagLint.Preprocess.Profile.KnownPlatforms"/>
    /// <seealso cref="DRagLint.Preprocess.Profile.PlatformBuiltins"/>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.TIfdefUndefinedCheck.CheckFiles"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
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
    /// <param name="AStore">150 PP: the project index, or nil. When it has
    /// pp_directives rows for a file whose stamp is current, the file's own
    /// directives are read from the table instead of re-lexing its text (see
    /// ScanFileTests); otherwise, and for every {$I} file, the text is scanned.
    /// The findings are identical either way.</param>
    /// <returns>One warning per undefined symbol per directive, anchored at the
    /// directive's line; the message names the symbol and, when one is within
    /// edit distance 2, the nearest defined symbol.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
    /// <para>Calls: Default, DRagLint.Lint.IfdefUndefined.CollectDprojDefines, DRagLint.Lint.IfdefUndefined.DprojSearchDirs, DRagLint.Lint.IfdefUndefined.NearestSymbol, DRagLint.Lint.IfdefUndefined.ScanFile, DRagLint.Lint.IfdefUndefined.TIfdefUndefinedCheck.IsCompilerPredefined, ExtractFileName, Format, LowerCase, Trim</para>
    /// <para>Returns: nil; Findings.ToArray</para>
    /// <para>Touches: file system</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.CollectDprojDefines"/>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.DprojSearchDirs"/>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.NearestSymbol"/>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.ScanFile"/>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.TIfdefUndefinedCheck.IsCompilerPredefined"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function CheckFiles(const AFiles: TArray<string>; const ADprojPath: string;
      const AAllow: TArray<string>;
      const AExtraIncludeDirs: TArray<string> = nil; const AStore: ISymbolStore = nil): TArray<TLintFinding>; static;

    /// <summary>The directories searched for {$I} files of a project: the
    /// .dproj's folder, then its literal (macro-free) DCC_IncludePath and
    /// DCC_UnitSearchPath entries, relative ones resolved against that
    /// folder.</summary>
    /// <param name="ADprojPath">The project file; unreadable yields just its
    /// folder.</param>
    /// <returns>Absolute directories, in search order.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.PlatformDivergent.TPlatformDivergentCheck.CheckFiles (DRagLint.Lint.PlatformDivergent.pas)</para>
    /// <para>Calls: DRagLint.Lint.IfdefUndefined.DprojSearchDirs</para>
    /// <para>Returns: DprojSearchDirs(ADprojPath)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.DprojSearchDirs"/>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.TIfdefUndefinedCheck.CheckFiles"/>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.TIfdefUndefinedCheck.DprojDefineUnion"/>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.TIfdefUndefinedCheck.IsCompilerPredefined"/>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.TIfdefUndefinedCheck.ScanFileTests"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function ProjectSearchDirs(const ADprojPath: string): TArray<string>; static;

    /// <summary>Scans one source file the way CheckFiles does: its own
    /// conditional tests, and every symbol it -- or a {$I} file it includes,
    /// transitively -- $DEFINEs or $UNDEFs.</summary>
    /// <param name="AFilePath">The source file.</param>
    /// <param name="ASearchDirs">Include search directories after the file's
    /// own folder (see ProjectSearchDirs).</param>
    /// <param name="ATests">The file's own tests, in source order.</param>
    /// <param name="ALocalSymbols">Lowercased symbols $DEFINEd or $UNDEFed in
    /// the file or its includes.</param>
    /// <param name="AStore">150 PP: the project index, or nil. Table-first:
    /// when the store has the pp_directives table, the file is indexed there
    /// with rows and its stamp (mtime + size) is current, the file's own
    /// directives come from GetPpDirectives; {$I} files are still read from
    /// disk. Any miss -- nil store, schema-23 DB, no rows, stale stamp, or the
    /// environment variable DRAGLINT_PP_TABLE=0 -- scans the text as before.
    /// Both paths give identical results (tests\autotest\run_pp_directives.ps1).</param>
    /// <returns>False when the file cannot be read or one of its includes
    /// cannot be resolved -- the caller should then skip the file, because
    /// the missing text might define anything.</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Lint.PlatformDivergent.TPlatformDivergentCheck.CheckFiles (DRagLint.Lint.PlatformDivergent.pas)</para>
    /// <para>Calls: DRagLint.Lint.IfdefUndefined.ScanFile</para>
    /// <para>Returns: ScanFile(AFilePath, ASearchDirs, Sets, Tests, AStore)</para>
    /// <para>Mutates: ATests (out), ALocalSymbols (out)</para>
    /// <para>Directives: static</para>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.ScanFile"/>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.TIfdefUndefinedCheck.CheckFiles"/>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.TIfdefUndefinedCheck.DprojDefineUnion"/>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.TIfdefUndefinedCheck.IsCompilerPredefined"/>
    /// <seealso cref="DRagLint.Lint.IfdefUndefined.TIfdefUndefinedCheck.ProjectSearchDirs"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function ScanFileTests(const AFilePath: string; const ASearchDirs: TArray<string>;
      out ATests: TArray<TConditionalTest>; out ALocalSymbols: TArray<string>;
      const AStore: ISymbolStore = nil): Boolean; static;
  end;

implementation

uses
  System.Classes,
  System.Math,
  System.StrUtils,
  System.IOUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  DRagLint.Preprocess,
  DRagLint.Preprocess.Types,
  DRagLint.Preprocess.Lexer,
  DRagLint.Preprocess.Profile,
  DRagLint.Core.FileTime;

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
  Sym : string;
  Plat: string;
begin
  Sym:= LowerCase(ASymbol);
  // CPU*: CPUX86, CPUX64, CPU32BITS, CPU64BITS, CPUARM, CPUARM64, CPU386, ...
  // The PlatformBuiltins lists are the indexer's own, so this rule can never
  // disagree with the define profile the preprocessor uses.
  if Sym = '' then Exit(False);
  if IsVersionSymbol(Sym) or StartsStr(CPU_PREFIX, Sym) then Exit(True);
  if InList(Sym, PREDEFINED) then Exit(True);
  for Plat in KnownPlatforms do
    if InList(Sym, PlatformBuiltins(Plat)) then Exit(True);
  Result:= False;
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

// The symbol sets one scan fills. Defined and Visited must not be nil; Undefs
// may be nil when the caller does not need the $UNDEFs.
type
  TScanSets = record
    Defined: TSymbolSet;
    Undefs : TSymbolSet;
    Visited: TDictionary<string, Byte>;
  end;

// Adds the leading identifier of a DEFINE / UNDEF argument to ASet (nil: no-op).
procedure AddDirectiveSymbol(const AArgs: string; ASet: TSymbolSet);
var
  Sym: string;
begin
  Sym:= LeadingIdent(AArgs);
  if (ASet <> nil) and (Sym <> '') and not ASet.ContainsKey(LowerCase(Sym)) then
    ASet.Add(LowerCase(Sym), Sym);
end;

// Adds the conditional tests of one directive chunk (IFDEF / IFNDEF symbol, or
// every defined() of an IF / ELSEIF) to ATests.
// 150 PP: the same, from a directive's word, argument text and 1-based position
// (a lexer chunk or a pp_directives row).
procedure AddDirectiveTestsAt(const ADir, AArgs: string; ALine, ACol: Integer;
  ATests: TList<TConditionalTest>);
var
  Test: TConditionalTest;
  M   : TMatch;
begin
  Test:= Default(TConditionalTest);
  Test.Line:= ALine;
  Test.Col := ACol;
  if (ADir = 'ifdef') or (ADir = 'ifndef') then
  begin
    Test.Symbol:= LeadingIdent(AArgs);
    if Test.Symbol <> '' then ATests.Add(Test);
  end
  else if (ADir = 'if') or (ADir = 'elseif') then
  begin
    M:= TRegEx.Match(AArgs, '\bdefined\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)', [roIgnoreCase]);
    while M.Success do
    begin
      Test.Symbol:= M.Groups[1].Value;
      ATests.Add(Test);
      M:= M.NextMatch;
    end;
  end;
end;

// 150 PP: forward -- ScanSource hands its lexed directives to ScanRows, which
// recurses into ScanSource for an {$I} file.
function ScanRows(const ARows: TArray<TPpDirectiveRow>; const AOwnDir: string;
  const ASearchDirs: TArray<string>; const ASets: TScanSets;
  ATests: TList<TConditionalTest>; ADepth: Integer): Boolean; forward;

// Collects the $DEFINEs of AText (and, transitively, of its includes) into
// ASets.Defined, its $UNDEFs into ASets.Undefs when that is not nil, and --
// when ATests is not nil -- the conditional tests of AText itself. Returns
// False when an include cannot be resolved.
function ScanSource(const AText, AOwnDir: string; const ASearchDirs: TArray<string>;
  const ASets: TScanSets; ATests: TList<TConditionalTest>; ADepth: Integer): Boolean;
var
  Chunks: TArray<TPPChunk>;
  Ch    : TPPChunk;
  Bytes : TBytes;
  Rows  : TList<TPpDirectiveRow>;
  Row   : TPpDirectiveRow;
begin
  Chunks:= LexDirectives(AText);
  Bytes:= TEncoding.UTF8.GetBytes(AText);
  // 150 PP: the lexed directives in the pp_directives row shape, then the one
  // loop both paths share (ScanRows).
  Rows:= TList<TPpDirectiveRow>.Create;
  try
    for Ch in Chunks do
    begin
      if Ch.Kind <> ckDirective then Continue;
      Row:= Default(TPpDirectiveRow);
      Row.Directive:= Ch.Dir;
      Row.Args     := Ch.Args;
      Row.Line     := Ch.Line + 1;
      Row.Col      := DirectiveCol(Bytes, Ch.SrcStart);
      Rows.Add(Row);
    end;
    Result:= ScanRows(Rows.ToArray, AOwnDir, ASearchDirs, ASets, ATests, ADepth);
  finally
    Rows.Free;
  end;
end;

// The directive loop of ScanSource, over rows: a lexed text's or -- 150 PP --
// a file's pp_directives rows (same order, same sets, same tests). An {$I}
// row resolves and scans the include's text from disk; tests inside an
// include are the include's own business, only its DEFINEs (and UNDEFs) are
// collected.
function ScanRows(const ARows: TArray<TPpDirectiveRow>; const AOwnDir: string;
  const ASearchDirs: TArray<string>; const ASets: TScanSets;
  ATests: TList<TConditionalTest>; ADepth: Integer): Boolean;
var
  Row    : TPpDirectiveRow;
  IncPath: string;
  IncText: string;
begin
  Result:= True;
  for Row in ARows do
  begin
    if Row.Directive = 'define' then
      AddDirectiveSymbol(Row.Args, ASets.Defined)
    else if Row.Directive = 'undef' then
      AddDirectiveSymbol(Row.Args, ASets.Undefs)
    else if (Row.Directive = 'i') or (Row.Directive = 'include') then
    begin
      // {$I+} / {$I-} is the I/O-checking switch, not an include.
      if (Row.Args = '') or CharInSet(Row.Args[1], ['+', '-']) then Continue;
      IncPath:= ResolveInclude(Row.Args, AOwnDir, ASearchDirs);
      if (IncPath = '') or (ADepth >= MAX_INCLUDE_DEPTH) then Exit(False);
      if ASets.Visited.ContainsKey(LowerCase(IncPath)) then Continue;
      ASets.Visited.Add(LowerCase(IncPath), 0);
      if not TryReadSource(IncPath, IncText) then Exit(False);
      if not ScanSource(IncText, ExtractFilePath(IncPath), ASearchDirs, ASets, nil,
        ADepth + 1) then Exit(False);
    end
    else if ATests <> nil then
      AddDirectiveTestsAt(Row.Directive, Row.Args, Row.Line, Row.Col, ATests);
  end;
end;

// 150 PP: the pp_directives rows of AFilePath when the store holds a CURRENT
// copy of the file (same mtime + size as on disk) and the table path is not
// switched off (DRAGLINT_PP_TABLE=0); nil otherwise -- the caller then scans.
function CurrentDirectiveRows(const AStore: ISymbolStore; const AFilePath: string): TArray<TPpDirectiveRow>;
var
  Full: string;
  Fid : Int64;
begin
  Result:= nil;
  if (AStore = nil) or (GetEnvironmentVariable('DRAGLINT_PP_TABLE') = '0') then Exit;
  if not AStore.HasPpDirectives then Exit;
  Full:= ExpandFileName(AFilePath);
  if not TFile.Exists(Full) then Exit;
  Fid:= AStore.FindFileIdByPath(Full);
  if Fid <= 0 then Exit;
  if not AStore.FileStampIsCurrent(Full, FileMTimeUnix(Full), TFile.GetSize(Full)) then Exit;
  Result:= AStore.GetPpDirectives(Fid);
end;

// 150 PP: the file's own scan, table-first. Fills ASets / ATests exactly as
// TryReadSource + ScanSource(..., 0) would, and returns what that would.
function ScanFile(const AFilePath: string; const ASearchDirs: TArray<string>;
  const ASets: TScanSets; ATests: TList<TConditionalTest>; const AStore: ISymbolStore): Boolean;
var
  Rows: TArray<TPpDirectiveRow>;
  Text: string;
begin
  Rows:= CurrentDirectiveRows(AStore, AFilePath);
  if PPTracePath <> '' then
    PPTraceAppend(Format('pp-directives: %s %s rows=%d',
      [if Length(Rows) > 0 then 'table' else 'scan', AFilePath, Length(Rows)]));
  if Length(Rows) > 0 then
    Exit(ScanRows(Rows, ExtractFilePath(ExpandFileName(AFilePath)), ASearchDirs, ASets, ATests, 0));
  if not TryReadSource(AFilePath, Text) then Exit(False);
  Result:= ScanSource(Text, ExtractFilePath(ExpandFileName(AFilePath)), ASearchDirs, ASets, ATests, 0);
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
  const AExtraIncludeDirs: TArray<string>; const AStore: ISymbolStore): TArray<TLintFinding>;
var
  ProjectDefs: TSymbolSet;
  UnitDefs   : TSymbolSet;
  Visited    : TDictionary<string, Byte>;
  Tests      : TList<TConditionalTest>;
  Findings   : TList<TLintFinding>;
  SearchDirs : TArray<string>;
  FilePath   : string;
  Sym        : string;
  Test       : TConditionalTest;
  Finding    : TLintFinding;
  Hint       : string;
  ProjName   : string;
  Sets       : TScanSets;
begin
  Result:= nil;
  if (ADprojPath = '') or not TFile.Exists(ADprojPath) then Exit;
  ProjName:= ExtractFileName(ADprojPath);

  ProjectDefs:= TSymbolSet.Create;
  UnitDefs   := TSymbolSet.Create;
  Visited    := TDictionary<string, Byte>.Create;
  Tests      := TList<TConditionalTest>.Create;
  Findings   := TList<TLintFinding>.Create;
  try
    // Read the dproj ONCE for every file of the run.
    CollectDprojDefines(ADprojPath, ProjectDefs, nil);
    for Sym in AAllow do
      if Trim(Sym) <> '' then ProjectDefs.AddOrSetValue(LowerCase(Trim(Sym)), Trim(Sym));
    SearchDirs:= AExtraIncludeDirs + DprojSearchDirs(ADprojPath);

    for FilePath in AFiles do
    begin
      UnitDefs.Clear;
      Visited.Clear;
      Tests.Clear;
      // An unresolvable include might define anything: skip the file.
      Sets:= Default(TScanSets);
      Sets.Defined:= UnitDefs;
      Sets.Visited:= Visited;
      if not ScanFile(FilePath, SearchDirs, Sets, Tests, AStore) then Continue; { 150 PP: table-first }
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

class function TIfdefUndefinedCheck.ProjectSearchDirs(const ADprojPath: string): TArray<string>;
begin
  Result:= DprojSearchDirs(ADprojPath);
end;

class function TIfdefUndefinedCheck.ScanFileTests(const AFilePath: string;
  const ASearchDirs: TArray<string>; out ATests: TArray<TConditionalTest>;
  out ALocalSymbols: TArray<string>; const AStore: ISymbolStore): Boolean;
var
  Defs   : TSymbolSet;
  Undefs : TSymbolSet;
  Visited: TDictionary<string, Byte>;
  Tests  : TList<TConditionalTest>;
  Sym    : string;
  Sets   : TScanSets;
begin
  ATests:= nil;
  ALocalSymbols:= nil;
  Defs   := TSymbolSet.Create;
  Undefs := TSymbolSet.Create;
  Visited:= TDictionary<string, Byte>.Create;
  Tests  := TList<TConditionalTest>.Create;
  try
    Sets.Defined:= Defs;
    Sets.Undefs := Undefs;
    Sets.Visited:= Visited;
    Result:= ScanFile(AFilePath, ASearchDirs, Sets, Tests, AStore); { 150 PP: table-first }
    if not Result then Exit;
    ATests:= Tests.ToArray;
    for Sym in Defs.Keys do ALocalSymbols:= ALocalSymbols + [Sym];
    for Sym in Undefs.Keys do ALocalSymbols:= ALocalSymbols + [Sym];
  finally
    Tests.Free;
    Visited.Free;
    Undefs.Free;
    Defs.Free;
  end;
end;

end.
