unit DRagLint.Preprocess;

// PP-Task-4/6: the chunk processor -- the core of tree-sitter-delphi13
// preprocessor/preprocess.js (the preprocess() function). Walks the lexer's
// chunk stream, maintains a defines table + a nested-IF state stack, and emits
// a preprocessed byte buffer where INACTIVE branches and ALL directives are
// BLANKED to spaces with newlines preserved.
//
// THE OFFSET-IDENTITY INVARIANT (the whole point of this design):
//   Length(Preprocess(bytes)) = Length(bytes)   -- in BYTES.
// Because output length == input length byte-for-byte, tree-sitter spans over
// the resolved text map 1:1 back to the original file with NO source map. So
// ALL blanking is done at the BYTE level: for each chunk we operate on the
// ORIGINAL input bytes AUtf8[SrcStart..SrcEnd) (not a re-encoded copy of the
// chunk's Value string), guaranteeing the byte count is preserved even if a
// text span carries multi-byte UTF-8. A blanked byte is a space (byte 32); the
// ONLY byte preserved through blanking is LF (byte 10) -- CR (byte 13) is
// blanked like any other non-newline byte, matching the JS regex
// text.replace(/[^\n]/g, ' ').
//
// INCLUDES (PP-Task-6): an {$I}/{$INCLUDE} directive is handled per the
// TPPOptions.IncludeMode of the new overload:
//   'off'          -- BLANK the directive, ignore its defines (Task-4 behavior;
//                     the 2-arg form delegates here so its output is unchanged).
//   'defines-only' -- when the directive is effectively ACTIVE, resolve the
//                     include name relative to BaseDir, read the .inc UTF-8
//                     bytes, and recurse the SAME defines/numeric dictionaries
//                     (BY REFERENCE) through PreprocessInto so the child's
//                     {$DEFINE}/{$UNDEF} mutate the PARENT'S live set (this is
//                     the Task-6 bug-fix: a parent {$IFDEF X} AFTER
//                     {$I config.inc} where config.inc defined X now resolves
//                     correctly). The child's OUTPUT TEXT is DISCARDED; the
//                     {$I} directive itself is BLANKED (srcLen spaces). NO body
//                     splice -- offsets stay 1:1. Unresolved include / not
//                     effectively active / depth >= 64 all BLANK.
// The 'expand' body-splice branch of preprocess.js (lines 176-184) is
// deliberately NOT ported -- splicing a body would violate the offset-identity
// invariant. Length(output) == Length(input of the PARENT file) always holds.
//
// INCLUDE-DEFINE PROPAGATION (v1.2.1 port change #1): the JS v1.2.1 fix "include
// defines propagate in expand mode" is ALREADY satisfied here without a code
// change, because this port has no 'expand' mode -- and its 'defines-only'
// recursion already shares the parent's define dictionaries BY REFERENCE through
// every nesting level (see ApplyIncludeDefines below). So a {$DEFINE} in a
// nested include (main -> outer.inc -> inner.inc) propagates transitively to the
// top parent's later {$IFDEF}, byte-identically to the JS oracle. Regression-
// locked by tests/preprocess/run_include_modes.ps1 (the 'nested defines-only'
// block, oracle-diffed).
//
// BOM (v1.2.1 port change #3): a decoded UTF-8 BOM (the 3 bytes EF BB BF) at the
// START of the input is blanked to 3 spaces at every recursion entry -- it is
// encoding metadata, not source, and must not survive into the resolved text.
// The blanking is offset-preserving (3 bytes -> 3 space bytes), so the
// offset-identity invariant still holds. (In the production indexer path the
// top-level BOM is already removed by EnsureUtf8Bytes upstream; this keeps
// Preprocess robust for raw-byte callers -- e.g. the preprocess-file verb -- and
// oracle-parity with preprocess.js.)
//
// ENCODING NOTE: this feature is ABOUT braces, so this unit never writes a bare
// brace inside a // comment. Brace/dollar/space/newline literals in code are
// BYTE constants: 32 = space, 10 = newline (LF), 13 = CR.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DRagLint.Preprocess.Types,
  DRagLint.Preprocess.Decls;

type
  /// <summary>Lane INC3: an IF / ELSEIF directive, evaluated in active code,
  /// whose expression names something the symbol table could not resolve.
  /// The directive was taken as False.</summary>
  TPPUnresolvedIf = record
    Line : Integer;          // 1-based line of the directive
    Col  : Integer;          // 1-based column of the directive
    Expr : string;           // the directive's expression text
    Names: TArray<string>;   // the unresolved names, first-seen order
  end;

  /// <summary>Lane INC3: everything a preprocess run learned besides its bytes.</summary>
  TPPReport = record
    Sites     : TArray<TPPIncludeSite>;   // as Preprocess(..., out ASites)
    Unresolved: TArray<TPPUnresolvedIf>;  // top-level file only (not inside includes)
    Exported  : TArray<TPPDecl>;          // the file's interface declarations
    UsedUnits : TArray<string>;           // the active uses clauses, source order
  end;

/// <summary>Runs the compiler-directive preprocessor over AUtf8 under the given
/// define profile, returning a byte buffer of identical length where inactive
/// conditional branches and every directive are blanked to spaces (newlines
/// preserved). A faithful port of preprocess.js's preprocess() chunk walk. This
/// 2-arg form uses IncludeMode 'off' (includes are simply blanked, their
/// defines ignored) -- it delegates to the TPPOptions overload with an empty
/// BaseDir, so its output is byte-identical to the pre-Task-6 behavior.</summary>
/// <param name="AUtf8">The source file as UTF-8 bytes. Not modified.</param>
/// <param name="AProfile">The active define profile: Defines are lowercased
/// symbol names seeding the live defines set; NumericDefines map lowercased
/// names to integers for {$IF X op N} comparisons.</param>
/// <returns>A new TBytes with Length = Length(AUtf8) exactly (the offset-identity
/// invariant). Active-branch bytes are copied verbatim; inactive-branch and
/// directive bytes are replaced by spaces with LF (byte 10) preserved.</returns>
/// <remarks>
/// No shared mutable state -- each call builds its own defines
/// dictionary and IF stack.
/// <!-- drag-lint:auto BEGIN -->
/// <para>Called from: DRagLint.CLI.DoPreprocessFile (DRagLint.CLI.pas), DRagLint.Diagnostics.ParseCache.TAstParseCache.ApplyPreprocess (DRagLint.Diagnostics.ParseCache.pas), DRagLint.Index.Closure.TClosureResolver.MaybePreprocess (DRagLint.Index.Closure.pas), DRagLint.Preprocess.Preprocess/2 (DRagLint.Preprocess.pas)</para>
/// <para>Calls: DRagLint.Preprocess.Preprocess/2, DRagLint.Preprocess.Types.TPPOptionsDefault</para>
/// <para>Returns: Preprocess(AUtf8, Opts)</para>
/// <para>Overload 1 of 3</para>
/// <para>Recursive</para>
/// <para>Pure</para>
/// <para>Directives: overload</para>
/// <seealso cref="DRagLint.Preprocess.Types.TPPOptionsDefault"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function Preprocess(const AUtf8: TBytes; const AProfile: TDefineProfile): TBytes; overload;

/// <summary>PP-Task-6: runs the preprocessor over AUtf8 with include handling
/// per AOptions.IncludeMode ('off' or 'defines-only'). In 'defines-only' mode
/// an active {$I name} whose file resolves under AOptions.BaseDir has its
/// {$DEFINE}/{$UNDEF} applied to the PARENT'S live defines set (shared by
/// reference through the recursion), its output text discarded, and the {$I}
/// directive blanked -- so a parent {$IFDEF} after the include sees the child's
/// defines while output offsets stay 1:1. NO body splice ('expand' is not
/// ported). Unresolved / inactive / depth >= 64 includes are blanked.</summary>
/// <param name="AUtf8">The source file as UTF-8 bytes. Not modified.</param>
/// <param name="AOptions">Profile (seed defines/numerics), IncludeMode
/// ('off'|'defines-only'), and BaseDir (directory a relative include resolves
/// against; '' disables resolution -> every include blanks).</param>
/// <returns>A new TBytes with Length = Length(AUtf8) exactly. The {$I}
/// directive is always blanked, never spliced.</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: DRagLint.Preprocess.PreprocessWithSites</para>
/// <para>Returns: PreprocessWithSites(AUtf8, AOptions, nil)</para>
/// <para>Overload 2 of 3</para>
/// <para>Pure</para>
/// <para>Directives: overload</para>
/// <seealso cref="DRagLint.Preprocess.PreprocessWithSites"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
function Preprocess(const AUtf8: TBytes; const AOptions: TPPOptions): TBytes; overload;

/// <summary>N-06: the TPPOptions overload that also reports every active,
/// resolved include site it met. The returned bytes are byte-identical to
/// Preprocess(AUtf8, AOptions).</summary>
/// <param name="AUtf8">The source file as UTF-8 bytes. Not modified.</param>
/// <param name="AOptions">As for the 2-arg TPPOptions overload. Sites are only
/// produced in 'defines-only' mode (in 'off' no include is ever resolved).</param>
/// <param name="ASites">Receives the sites in source order, nested ones
/// included (TPPIncludeSite.Depth tells them apart); empty when none.</param>
/// <returns>A new TBytes with Length = Length(AUtf8) exactly.</returns>
/// <remarks>Each site's Resolved bytes are the child output the recursion
/// already produced -- no second preprocess.</remarks>
function Preprocess(const AUtf8: TBytes; const AOptions: TPPOptions;
  out ASites: TArray<TPPIncludeSite>): TBytes; overload;

/// <summary>Lane INC3: the TPPOptions preprocess that also reports what the
/// run learned -- include sites, IF directives with unresolved names, the
/// file's exported declarations and its uses clause.</summary>
/// <param name="AUtf8">The source file as UTF-8 bytes. Not modified.</param>
/// <param name="AOptions">As for Preprocess(AUtf8, AOptions).</param>
/// <param name="AReport">Receives the report (see TPPReport).</param>
/// <returns>Bytes identical to Preprocess(AUtf8, AOptions).</returns>
/// <remarks>IF expressions are evaluated against the constants declared
/// earlier in the active text, then against the units of the uses clause
/// through the installed PPUnitSource (none installed = same-file only).
/// Setting the environment variable DRAGLINT_PP_TRACE to a file path appends
/// one TSV line per evaluated IF (base dir, line, result, result without the
/// symbol table, unresolved names, expression) -- a measurement aid.</remarks>
function PreprocessReport(const AUtf8: TBytes; const AOptions: TPPOptions;
  out AReport: TPPReport): TBytes;

implementation

uses
  System.Types,                 // TStringDynArray (TDirectory.GetDirectories)
  System.IOUtils,
  System.Generics.Defaults,     // default comparer for TArray.Sort<string>
  DRagLint.Preprocess.Lexer,
  DRagLint.Preprocess.Expr,
  DRagLint.Preprocess.Tolerance; // v1.2.1 #5: opt-in dcc-tolerance pass

const
  // Cycle guard: matches preprocess.js maxIncludeDepth (option default 64).
  MAX_INCLUDE_DEPTH = 64;
  // v1.2.1 port change #2: how many parent levels the nearest-first {$I} search
  // climbs (preprocess.js options.searchLevels default 3).
  SEARCH_LEVELS = 3;
  // N-06: the LF byte; the include site's host column counts back to the line start.
  LF_BYTE = 10;

var
  // v1.2.1 port change #2: process-lifetime cache of directory listings for the
  // nearest-first include search (dir -> sorted absolute subdirectory paths).
  // Mirrors preprocess.js's _subdirCache: corpus scans call the resolver once
  // per file with heavily-repeated baseDirs, so caching the readdir keeps the
  // widened search cheap. No invalidation -- acceptable for a preprocessor
  // utility's process lifetime. Created lazily; freed in the unit finalization.
  GSubdirCache: TDictionary<string, TArray<string>> = nil;
  // Lane INC3: DRAGLINT_PP_TRACE target ('' = off), read once; GTraceLock
  // serialises the appends.
  GTracePath: string = '';
  GTraceLock: TObject = nil;

type
  // Lane INC3: per-run state shared BY REFERENCE through the include recursion
  // (like the define tables): the declaration scanner, the name lookup built
  // over it, and the unresolved-IF sink.
  TPPRunCtx = record
    Scanner   : TPPDeclScanner;
    Lookup    : TPPNameLookup;
    Unresolved: TList<TPPUnresolvedIf>;
  end;

  // One nested-IF state frame (preprocess.js stack entries):
  //   Active        -- is THIS frame emitting text right now?
  //   TakenBranch   -- has any THEN/ELSEIF branch of this IF already been taken?
  //   AnyOuterFalse -- was some ancestor IF false (whole subtree inactive)?
  TIfState = record
    Active       : Boolean;
    TakenBranch  : Boolean;
    AnyOuterFalse: Boolean;
  end;

// First whitespace-split token of AArgs, lowercased (JS ch.args.split(/\s+/)[0]).
// Empty when AArgs is empty/all-whitespace (guards an empty-name add/remove).
function FirstArgLower(const AArgs: string): string;
var
  T       : string ;
  SpacePos: Integer;
begin
  T:= Trim(AArgs);
  SpacePos:= 1;
  while (SpacePos <= Length(T)) and (T[SpacePos] > ' ') do Inc(SpacePos);
  Result:= LowerCase(Copy(T, 1, SpacePos - 1));
end;

// Strip ONE leading ' or " and ONE trailing ' or " from the include name, then
// trim (JS ch.args.replace(/^['"]|['"]$/g, '').trim()).
function StripQuotes(const AArgs: string): string;
var
  S: string;
begin
  S:= AArgs;
  if (Length(S) >= 1) and ((S[1] = '''') or (S[1] = '"')) then
    S:= Copy(S, 2, Length(S) - 1);
  if (Length(S) >= 1) and ((S[Length(S)] = '''') or (S[Length(S)] = '"')) then
    S:= Copy(S, 1, Length(S) - 1);
  Result:= Trim(S);
end;

// v1.2.1 port change #2: the sorted immediate subdirectories of ADir, cached for
// the process lifetime (mirrors preprocess.js subdirsOf + _subdirCache). An
// unreadable dir yields [] (treated as no subdirs). Absolute paths, ascending
// sort -- deterministic nearest-first candidate order.
function SubdirsOf(const ADir: string): TArray<string>;
var
  Entries: TArray<string>;
  Cached : TArray<string>;
begin
  if GSubdirCache = nil then GSubdirCache:= TDictionary<string, TArray<string>>.Create;
  if GSubdirCache.TryGetValue(ADir, Cached) then Exit(Cached);
  try
    Entries:= TDirectory.GetDirectories(ADir); // immediate subdirs only (no recurse)
  except
    Entries:= nil; // unreadable dir -> no subdirs
  end;
  TArray.Sort<string>(Entries);
  GSubdirCache.AddOrSetValue(ADir, Entries);
  Result:= Entries;
end;

// Try to resolve AName against ACandidateDir; return the existing full path or ''.
function TryResolveIn(const AName, ACandidateDir: string): string;
var
  P: string;
begin
  Result:= '';
  P:= TPath.GetFullPath(TPath.Combine(ACandidateDir, AName));
  if TFile.Exists(P) then Result:= P;
end;

// Resolve an include name. First try ABaseDir directly (JS path.resolve). If
// ANearSearch, widen nearest-first (preprocess.js:116-136): ABaseDir's immediate
// subdirs, then up to SEARCH_LEVELS parent levels -- each parent dir itself plus
// its immediate subdirs -- stopping when the filesystem root is reached. Returns
// the resolved absolute path if it exists, '' otherwise (caller blanks the
// directive; offsets stay 1:1). An empty ABaseDir or an unresolvable name yields
// ''. A rooted AName is honored as-is. Lane INC: ASearchPaths (the build's
// search path) are tried after ABaseDir and before the widened search.
function ResolveInclude(const AName, ABaseDir: string; ANearSearch: Boolean;
  const ASearchPaths: TArray<string>): string;
var
  P    : string ;
  Dir  : string ;
  Sub  : string ;
  Lvl  : Integer;
  Parent: string;
  SP   : string ;
begin
  Result:= '';
  if (AName = '') or (ABaseDir = '') then Exit;

  // Rooted name -- honored directly, no search.
  if TPath.IsPathRooted(AName) then
  begin
    P:= TPath.GetFullPath(AName);
    if TFile.Exists(P) then Result:= P;
    Exit;
  end;

  // Pass 1: ABaseDir itself (the strict, pre-#2 behavior); pass 1b (lane INC):
  // then the build's search path, in order.
  for SP in [ABaseDir] + ASearchPaths do
  begin
    if SP = '' then Continue;
    Result:= TryResolveIn(AName, SP);
    if Result <> '' then Exit;
  end;

  // Pass 2: nearest-first widened search. Level 0 = ABaseDir's immediate subdirs
  // (ABaseDir itself was already tried above). Levels 1..SEARCH_LEVELS = the
  // parent dir itself + its immediate subdirs. Stop when GetDirectoryName no
  // longer changes (filesystem root). Skipped entirely when not ANearSearch.
  Dir:= TPath.GetFullPath(ABaseDir);
  if ANearSearch then
  begin
    for Lvl:= 0 to SEARCH_LEVELS do
    begin
      if Lvl > 0 then
      begin
        Result:= TryResolveIn(AName, Dir);
        if Result <> '' then Exit;
      end;
      for Sub in SubdirsOf(Dir) do
      begin
        Result:= TryResolveIn(AName, Sub);
        if Result <> '' then Exit;
      end;
      Parent:= TPath.GetDirectoryName(Dir);
      if (Parent = '') or (Parent = Dir) then Break;
      Dir:= Parent;
    end;
  end;
end;

// Lane INC2: a directive's opening bytes (brace + dollar), and the length of
// that frame plus the closing brace -- what is cut to get the directive body.
const
  DIRECTIVE_OPEN      = #123'$';
  DIRECTIVE_FRAME_LEN = 3;

// Lane INC2: the long names of the switch directives {$IFOPT} can test, and
// the letter each one sets ({$RANGECHECKS ON} = {$R+}). Parallel arrays.
const
  SWITCH_LONG_NAMES: array[0..19] of string = (
    'booleval', 'assertions', 'debuginfo', 'importeddata', 'longstrings',
    'iochecks', 'writeableconst', 'localsymbols', 'typeinfo', 'optimization',
    'openstrings', 'overflowchecks', 'rangechecks', 'typedaddress', 'safedivide',
    'varstringchecks', 'stackframes', 'extendedsyntax', 'referenceinfo', 'definitioninfo');
  SWITCH_LONG_LETTERS: array[0..19] of string = (
    'b', 'c', 'd', 'g', 'h', 'i', 'j', 'l', 'm', 'o',
    'p', 'q', 'r', 't', 'u', 'v', 'w', 'x', 'y', 'y');

// Lane INC2: applies one switch directive body (the text between the dollar
// and the closing brace) to ASwitches: a letter list 'R+' / 'R-,Q+' or a long
// form 'RANGECHECKS ON'. Anything else ({$R file.res}, {$WARN ...}) is left
// alone. dcc applies a switch in source order, so the caller calls this for
// active directives only.
procedure ApplySwitchText(const AText: string; ASwitches: TDictionary<string, Boolean>);
var
  Parts: TArray<string>;
  Part : string;
  LongName: string;
  Rest : string;
  Sp   : Integer;
  K    : Integer;
begin
  Parts:= Trim(AText).Split([',']);
  if Length(Parts) = 0 then Exit;
  // Letter list: every part is exactly <letter><sign>.
  var IsList: Boolean:= True;
  for Part in Parts do
    if not ((Length(Trim(Part)) = 2) and CharInSet(Trim(Part)[1], ['A'..'Z', 'a'..'z'])
            and CharInSet(Trim(Part)[2], ['+', '-'])) then IsList:= False;
  if IsList then
  begin
    for Part in Parts do
      ASwitches.AddOrSetValue(LowerCase(Trim(Part)[1]), Trim(Part)[2] = '+');
    Exit;
  end;
  // Long form: NAME ON|OFF.
  Rest:= Trim(AText);
  Sp:= Pos(' ', Rest);
  if Sp = 0 then Exit;
  LongName:= LowerCase(Copy(Rest, 1, Sp - 1));
  Rest := LowerCase(Trim(Copy(Rest, Sp + 1, MaxInt)));
  if (Rest <> 'on') and (Rest <> 'off') then Exit;
  for K:= Low(SWITCH_LONG_NAMES) to High(SWITCH_LONG_NAMES) do
    if LongName = SWITCH_LONG_NAMES[K] then
    begin
      ASwitches.AddOrSetValue(SWITCH_LONG_LETTERS[K], Rest = 'on');
      Exit;
    end;
end;

// Lane INC2: {$IFOPT X+} / {$IFOPT X-} against the live switch states. A
// letter no profile or directive set is False either way (conservative, the
// pre-INC2 answer for every IFOPT).
function EvalIfOpt(const AArgs: string; ASwitches: TDictionary<string, Boolean>): Boolean;
var
  A : string;
  On: Boolean;
begin
  A:= Trim(AArgs);
  if (Length(A) < 2) or not CharInSet(A[2], ['+', '-']) then Exit(False);
  if not ASwitches.TryGetValue(LowerCase(A[1]), On) then Exit(False);
  Result:= On = (A[2] = '+');
end;

// The recursive worker (the faithful port of preprocess.js's preprocess()).
// ADefines / ANumeric are threaded BY REFERENCE through the recursion so a
// 'defines-only' child's {$DEFINE}/{$UNDEF} mutate the PARENT'S live table --
// this is the Task-6 bug-fix. AOut is a pre-sized byte buffer (Length =
// Length(ABytes)) written at AOutPos; on return AOutPos has advanced by
// Length(ABytes) exactly (offset-identity). A defines-only child gets a
// THROWAWAY AOut buffer (its bytes are discarded -- only its define mutations,
// visible through the shared dictionaries, matter).
procedure PreprocessInto(
  const ABytes: TBytes;
  ADefines: TDictionary<string, Boolean>;
  ANumeric: TDictionary<string, Integer>;
  ASwitches: TDictionary<string, Boolean>;
  const AIncludeMode, ABaseDir: string;
  ANearSearch: Boolean;
  const ASearchPaths: TArray<string>;
  ADepth: Integer;
  ASites: TList<TPPIncludeSite>;
  const ACtx: TPPRunCtx;
  var AOut: TBytes;
  var AOutPos: Integer);
var
  Bytes : TBytes            ; // working copy of ABytes with a leading UTF-8 BOM blanked
  Src   : string           ;
  Chunks: TArray<TPPChunk>  ;
  C     : TPPChunk          ;
  Stack : TArray<TIfState>  ;

  // Every stack frame Active? (preprocess.js effectivelyActive: stack.every).
  function EffectivelyActive: Boolean;
  var
    K: Integer;
  begin
    for K:= 0 to High(Stack) do
      if not Stack[K].Active then Exit(False);
    Result:= True;
  end;

  // Append a run of ACount space bytes (byte 32) at AOutPos.
  procedure EmitSpaces(ACount: Integer);
  var
    K: Integer;
  begin
    for K:= 0 to ACount - 1 do
    begin
      AOut[AOutPos]:= 32;
      Inc(AOutPos);
    end;
  end;

  // Lane INC3: evaluate an IF / ELSEIF expression against the run's symbol
  // table; an unresolved name (top-level file only) is recorded for the
  // pp-unresolved-if hint, and the trace line written when one is wanted.
  function EvalIf(const AChunk: TPPChunk): Boolean;
  var
    Unres: TArray<string>;
    U    : TPPUnresolvedIf;
    K    : Integer;
  begin
    Result:= EvalPPExprScoped(AChunk.Args, ADefines, ANumeric, ACtx.Lookup, Unres);
    if (Length(Unres) > 0) and (ADepth = 0) then
    begin
      U:= Default(TPPUnresolvedIf);
      U.Line:= AChunk.Line + 1;
      K:= AChunk.SrcStart;
      while (K > 0) and (Bytes[K - 1] <> LF_BYTE) do
        Dec(K);
      U.Col  := AChunk.SrcStart - K + 1;
      U.Expr := AChunk.Args;
      U.Names:= Unres;
      ACtx.Unresolved.Add(U);
    end;
    if GTracePath <> '' then
    begin
      var Bare: TArray<string>;
      var BareResult: Boolean:= EvalPPExprScoped(AChunk.Args, ADefines, ANumeric, nil, Bare);
      TMonitor.Enter(GTraceLock);
      try
        TFile.AppendAllText(GTracePath, Format('%s'#9'%d'#9'%s'#9'%s'#9'%s'#9'%s'#13#10,
          [ABaseDir, AChunk.Line + 1, BoolToStr(Result, True), BoolToStr(BareResult, True),
           string.Join(',', Unres), AChunk.Args.Replace(#9, ' ').Replace(#13, ' ').Replace(#10, ' ')]));
      finally
        TMonitor.Exit(GTraceLock);
      end;
    end;
  end;

  // Emit the chunk's ORIGINAL input bytes [AStart, AEnd). If effectively active,
  // copy them verbatim; else blank every byte to a space EXCEPT LF (byte 10),
  // which is preserved so line numbers stay aligned. Byte-level -> byte-exact.
  procedure BlankifyOrEmit(AStart, AEnd: Integer);
  var
    K   : Integer;
    Live: Boolean;
  begin
    Live:= EffectivelyActive;
    for K:= AStart to AEnd - 1 do
    begin
      // Copy from the BOM-blanked working buffer (Bytes), not ABytes, so a
      // leading UTF-8 BOM that was replaced with spaces below does not survive.
      if Live then AOut[AOutPos]:= Bytes[K]
      else if Bytes[K] = 10 then AOut[AOutPos]:= 10
      else AOut[AOutPos]:= 32;
      Inc(AOutPos);
    end;
  end;

  // A directive is ALWAYS blanked (its bytes -> spaces), regardless of active
  // state -- directive text never survives into the resolved output.
  procedure BlankifyDirective(AStart, AEnd: Integer);
  begin
    EmitSpaces(AEnd - AStart);
  end;

  // 'defines-only' handling for an ACTIVE {$I name}: resolve, read, recurse the
  // SAME dictionaries so the child's defines mutate the parent, discard the
  // child's output. The {$I} directive itself is blanked by the caller.
  procedure ApplyIncludeDefines(const AName: string; const AChunk: TPPChunk);
  var
    Resolved : string ;
    SubBytes : TBytes ;
    SubOut   : TBytes ;
    SubPos   : Integer;
    Site     : TPPIncludeSite;
    SiteIdx  : Integer;
    K        : Integer;
  begin
    Resolved:= ResolveInclude(AName, ABaseDir, ANearSearch, ASearchPaths);
    if Resolved = '' then Exit; // unresolved -> nothing to apply (blank only)
    SubBytes:= TFile.ReadAllBytes(Resolved);
    SetLength(SubOut, Length(SubBytes)); // throwaway (child text is discarded)
    SubPos:= 0;
    // N-06: reserve the site BEFORE recursing so a nested site lands after its
    // parent (source order); its Resolved bytes are filled in once SubOut is done.
    SiteIdx:= -1;
    if ASites <> nil then
    begin
      Site:= Default(TPPIncludeSite);
      Site.HostLine:= AChunk.Line + 1;
      K:= AChunk.SrcStart;
      while (K > 0) and (Bytes[K - 1] <> LF_BYTE) do
        Dec(K);
      Site.HostCol:= AChunk.SrcStart - K + 1;
      Site.Depth  := ADepth;
      Site.Path   := Resolved;
      SiteIdx:= ASites.Add(Site);
    end;
    // Recurse with the SAME ADefines/ANumeric instances (NOT copies) so the
    // child's {$DEFINE}/{$UNDEF} are visible to the parent's later {$IFDEF}. The
    // child's BaseDir is the resolved include's own directory, and NearSearch is
    // threaded through so a nested {$I} resolves nearest-first from there too.
    PreprocessInto(
      SubBytes, ADefines, ANumeric, ASwitches, AIncludeMode,
      TPath.GetDirectoryName(Resolved), ANearSearch, ASearchPaths, ADepth + 1, ASites, ACtx, SubOut, SubPos);
    if SiteIdx >= 0 then
    begin
      Site:= ASites[SiteIdx];
      Site.Resolved:= SubOut;
      ASites[SiteIdx]:= Site;
    end;
  end;

begin
  // v1.2.1 port change #3: a decoded UTF-8 BOM (the 3 bytes EF BB BF) at the
  // START of the input is encoding metadata, not source -- blank it
  // offset-preservingly so it never survives into the resolved text (mirrors
  // preprocess.js:57 input.charCodeAt(0)===0xFEFF -> ' '+slice, adapted to the
  // BYTE model: the JS blanks one decoded U+FEFF char to one space; the UTF-8
  // BOM is three bytes, and the offset-identity invariant requires blanking all
  // three to three spaces). Applies at EVERY recursion entry (so a defines-only
  // include body's own BOM is neutralized before it is scanned), never shifts
  // offsets, and leaves a BOM-less input untouched (identity copy). We make a
  // WORKING COPY (Bytes) because ABytes is const; all copying/blanking below
  // reads from Bytes, so the blanked BOM propagates through the lexer AND the
  // byte-copy path.
  Bytes:= ABytes;
  if (Length(Bytes) >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
  begin
    Bytes:= Copy(ABytes); // detach from ABytes before mutating (avoid aliasing)
    Bytes[0]:= 32;
    Bytes[1]:= 32;
    Bytes[2]:= 32;
  end;

  // Rebuild a string for the lexer (it re-encodes to UTF-8 internally, so the
  // byte offsets it returns index back into Bytes identically). We keep Bytes
  // as the authoritative byte source for all copying/blanking below.
  Src:= TEncoding.UTF8.GetString(Bytes);
  Chunks:= LexDirectives(Src);

  // The base frame: active, branch taken, no outer-false (preprocess.js:50).
  SetLength(Stack, 1);
  Stack[0].Active       := True;
  Stack[0].TakenBranch  := True;
  Stack[0].AnyOuterFalse:= False;

  for C in Chunks do
  begin
    if C.Kind = ckText then
    begin
      // Lane INC2: a passthrough directive may be a compiler switch ({$R-}).
      if (Length(C.Value) > DIRECTIVE_FRAME_LEN) and C.Value.StartsWith(DIRECTIVE_OPEN) and EffectivelyActive then
        ApplySwitchText(Copy(C.Value, Length(DIRECTIVE_OPEN) + 1, Length(C.Value) - DIRECTIVE_FRAME_LEN), ASwitches);
      // Lane INC3: only ACTIVE text declares anything an IF can see.
      if EffectivelyActive then ACtx.Scanner.Feed(C.Value);
      BlankifyOrEmit(C.SrcStart, C.SrcEnd);
      Continue;
    end;

    // Directive.
    if (C.Dir = 'define') or (C.Dir = 'undef') then
    begin
      if EffectivelyActive then
      begin
        var Name: string:= FirstArgLower(C.Args);
        if Name <> '' then
        begin
          if C.Dir = 'define' then ADefines.AddOrSetValue(Name, True)
          else ADefines.Remove(Name);
        end;
      end;
      BlankifyDirective(C.SrcStart, C.SrcEnd);
      Continue;
    end;

    if (C.Dir = 'ifdef') or (C.Dir = 'ifndef') or (C.Dir = 'if') or (C.Dir = 'ifopt') then
    begin
      var OuterInactive: Boolean:= not EffectivelyActive;
      // Lane INC3: dcc never evaluates an IF inside an inactive branch, and its
      // outcome cannot matter there (Active needs not OuterInactive; the ELSE
      // stays off through AnyOuterFalse) -- so neither do we.
      var Cond: Boolean:= if C.Dir = 'ifdef' then ADefines.ContainsKey(LowerCase(C.Args))
        else if C.Dir = 'ifndef' then not ADefines.ContainsKey(LowerCase(C.Args))
        else if C.Dir = 'if' then (not OuterInactive) and EvalIf(C)
        else EvalIfOpt(C.Args, ASwitches); // lane INC2
      SetLength(Stack, Length(Stack) + 1);
      Stack[High(Stack)].Active       := Cond and (not OuterInactive);
      Stack[High(Stack)].TakenBranch  := Cond;
      Stack[High(Stack)].AnyOuterFalse:= OuterInactive;
      BlankifyDirective(C.SrcStart, C.SrcEnd);
      Continue;
    end;

    if C.Dir = 'else' then
    begin
      // Mutate the TOP frame in place (a record in a dynamic array is a value
      // type; index the array directly so the write persists).
      Stack[High(Stack)].Active     := (not Stack[High(Stack)].TakenBranch)
                                       and (not Stack[High(Stack)].AnyOuterFalse);
      Stack[High(Stack)].TakenBranch:= True;
      BlankifyDirective(C.SrcStart, C.SrcEnd);
      Continue;
    end;

    if C.Dir = 'elseif' then
    begin
      if Stack[High(Stack)].TakenBranch then
        Stack[High(Stack)].Active:= False
      else
      begin
        var Cond2: Boolean:= (not Stack[High(Stack)].AnyOuterFalse) and EvalIf(C);
        Stack[High(Stack)].Active:= Cond2 and (not Stack[High(Stack)].AnyOuterFalse);
        if Cond2 then Stack[High(Stack)].TakenBranch:= True;
      end;
      BlankifyDirective(C.SrcStart, C.SrcEnd);
      Continue;
    end;

    if (C.Dir = 'endif') or (C.Dir = 'ifend') then
    begin
      if Length(Stack) > 1 then SetLength(Stack, Length(Stack) - 1);
      BlankifyDirective(C.SrcStart, C.SrcEnd);
      Continue;
    end;

    // Lane INC2: {$I+} / {$I-} is the IOCHECKS switch, not an include.
    if (C.Dir = 'i') and (C.Args <> '') and CharInSet(C.Args[1], ['+', '-']) then
    begin
      if EffectivelyActive then ApplySwitchText('I' + C.Args, ASwitches);
      BlankifyDirective(C.SrcStart, C.SrcEnd);
      Continue;
    end;

    if (C.Dir = 'i') or (C.Dir = 'include') then
    begin
      // {$I}/{$INCLUDE} (preprocess.js:149-186, minus 'expand'). ALWAYS blank
      // the directive (no body splice). In 'defines-only', when the directive
      // is effectively active and within depth, also apply the .inc's defines
      // to the shared parent table.
      if EffectivelyActive
        and (ADepth < MAX_INCLUDE_DEPTH)
        and (AIncludeMode = 'defines-only') then
        ApplyIncludeDefines(StripQuotes(C.Args), C);
      BlankifyDirective(C.SrcStart, C.SrcEnd);
      Continue;
    end;

    // Any other directive is blanked (the lexer routes unknown directives to
    // text chunks, so this is a guard).
    BlankifyDirective(C.SrcStart, C.SrcEnd);
  end;
end;

// N-06: the shared body of both TPPOptions overloads; ASites may be nil (no
// site collection -- the original behavior).
function PreprocessWithSites(const AUtf8: TBytes; const AOptions: TPPOptions;
  ASites: TList<TPPIncludeSite>; var AReport: TPPReport): TBytes;
var
  Ctx    : TPPRunCtx;
  Src    : IPPUnitSource;
  Lookup : TPPNameLookup;
  Defines: TDictionary<string, Boolean>;
  Numeric: TDictionary<string, Integer>;
  Switches: TDictionary<string, Boolean>;
  D      : string           ;
  P      : TPair<string, Integer>;
  S      : TPair<string, Boolean>;
  OutPos : Integer          ;
begin
  SetLength(Result, Length(AUtf8));
  OutPos:= 0;

  Defines:= TDictionary<string, Boolean>.Create;
  Numeric:= TDictionary<string, Integer>.Create;
  Switches:= TDictionary<string, Boolean>.Create;
  Ctx:= Default(TPPRunCtx);
  Ctx.Scanner   := TPPDeclScanner.Create;
  Ctx.Unresolved:= TList<TPPUnresolvedIf>.Create;
  Src:= PPUnitSource;
  try
    { Lane INC3: an IF name resolves in the constants declared earlier in the
      active text, then in the uses-clause units (last listed first, as dcc
      searches them), then in System. A dotted name asks its unit directly. }
    Lookup:=
      function(const AName: string; out AValue: TPPValue): TPPNameKind
      var
        D: TPPDecl;
        P: Integer;
        U: TArray<string>;
      begin
        AValue:= Default(TPPValue);
        P:= LastDelimiter('.', AName);
        if P > 0 then
        begin
          if Src = nil then Exit(pnkUnknown);
          Exit(Src.LookupInUnit(Copy(AName, 1, P - 1), Copy(AName, P + 1, MaxInt), AValue));
        end;
        if Ctx.Scanner.TryGet(AName, D) then
        begin
          if D.IsTypedConst then Exit(pnkTypedConst);
          if not (D.IsTrueConst and D.HasValue) then Exit(pnkDeclared);
          AValue:= D.Value;
          Exit(pnkConst);
        end;
        if Src = nil then Exit(pnkUnknown);
        U:= Ctx.Scanner.UsedUnits;
        for var I: Integer:= High(U) downto 0 do
        begin
          Result:= Src.LookupInUnit(U[I], AName, AValue);
          if Result <> pnkUnknown then Exit;
        end;
        Result:= Src.LookupInUnit('System', AName, AValue);
      end;
    Ctx.Lookup:= Lookup;
    Ctx.Scanner.OnEvalConst:=
      function(const AExpr: string; out AValue: TPPValue): Boolean
      begin
        Result:= TryEvalPPConst(AExpr, Defines, Numeric, Lookup, AValue);
      end;
    // Seed the live defines set from the profile ONCE (already lowercased); the
    // recursion then SHARES these instances (never re-seeds per include).
    for D in AOptions.Profile.Defines do
      if D <> '' then Defines.AddOrSetValue(LowerCase(D), True);
    for P in AOptions.Profile.NumericDefines do
      Numeric.AddOrSetValue(LowerCase(P.Key), P.Value);
    for S in AOptions.Profile.Switches do // lane INC2: {$IFOPT} states, later wins
      Switches.AddOrSetValue(LowerCase(S.Key), S.Value);

    { P1 (extractor 1.19.0-alpha): a Delphi 12+ multi-line string literal is
      neutralised BEFORE the directive lexer sees it -- unconditionally, unlike
      the opt-in tolerance pass below, because it is valid source both layers
      mis-read (see NeutralizeMultilineStrings). Same length, every LF kept, so
      the offset-identity invariant is untouched; a file without such a literal
      is passed through as the very same array. }
    PreprocessInto(
      NeutralizeMultilineStrings(AUtf8), Defines, Numeric, Switches, AOptions.IncludeMode, AOptions.BaseDir,
      AOptions.NearSearch, AOptions.SearchPaths, 0, ASites, Ctx, Result, OutPos);
    AReport.Unresolved:= Ctx.Unresolved.ToArray;
    AReport.Exported  := Ctx.Scanner.ExportedDecls;
    AReport.UsedUnits := Ctx.Scanner.UsedUnits;
  finally
    // The two closures share one frame that holds Lookup: clear every
    // reference or the frame keeps itself alive.
    Ctx.Scanner.OnEvalConst:= nil;
    Ctx.Lookup:= nil;
    Lookup:= nil;
    Ctx.Unresolved.Free;
    Ctx.Scanner.Free;
    Switches.Free;
    Numeric.Free;
    Defines.Free;
  end;

  // v1.2.1 port change #5: the OPT-IN dcc-tolerance pass runs over the fully
  // resolved TOP-LEVEL buffer only (never inside include recursion -- includes
  // contribute defines, not text). ApplyTolerances REPLACES one whitespace
  // byte per fixed line with ';', so Length(Result) is untouched and the
  // offset-identity invariant survives by construction.
  if AOptions.Tolerances then
    ApplyTolerances(Result);
end;

function Preprocess(const AUtf8: TBytes; const AOptions: TPPOptions): TBytes; overload;
var
  Report: TPPReport;
begin
  Report:= Default(TPPReport);
  Result:= PreprocessWithSites(AUtf8, AOptions, nil, Report);
end;

function PreprocessReport(const AUtf8: TBytes; const AOptions: TPPOptions;
  out AReport: TPPReport): TBytes;
var
  Sites: TList<TPPIncludeSite>;
begin
  AReport:= Default(TPPReport);
  Sites:= TList<TPPIncludeSite>.Create;
  try
    Result:= PreprocessWithSites(AUtf8, AOptions, Sites, AReport);
    AReport.Sites:= Sites.ToArray;
  finally
    Sites.Free;
  end;
end;

function Preprocess(const AUtf8: TBytes; const AOptions: TPPOptions;
  out ASites: TArray<TPPIncludeSite>): TBytes; overload;
var
  Sites: TList<TPPIncludeSite>;
begin
  Sites:= TList<TPPIncludeSite>.Create;
  try
    var Report: TPPReport:= Default(TPPReport);
    Result:= PreprocessWithSites(AUtf8, AOptions, Sites, Report);
    ASites:= Sites.ToArray;
  finally
    Sites.Free;
  end;
end;

function Preprocess(const AUtf8: TBytes; const AProfile: TDefineProfile): TBytes; overload;
var
  Opts: TPPOptions;
begin
  // Delegate to the include-aware overload with includes OFF and no base dir,
  // so the output is byte-identical to the pre-Task-6 behavior (includes were
  // blanked, their defines ignored). NearSearch is irrelevant in 'off' mode (no
  // include is ever resolved), but set it explicitly rather than rely on the
  // Boolean zero-init.
  Opts:= TPPOptionsDefault;
  Opts.Profile    := AProfile;
  Opts.IncludeMode:= 'off';
  Opts.BaseDir    := '';
  Result:= Preprocess(AUtf8, Opts);
end;

initialization
  GTracePath:= GetEnvironmentVariable('DRAGLINT_PP_TRACE');
  GTraceLock:= TObject.Create;
finalization
  GTraceLock.Free;
  // Release the process-lifetime subdir cache (v1.2.1 port change #2). Lazily
  // created in SubdirsOf; may be nil if the widened search was never used.
  GSubdirCache.Free;

end.
