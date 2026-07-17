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
  DRagLint.Preprocess.Types;

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
/// <remarks>No shared mutable state -- each call builds its own defines
/// dictionary and IF stack.</remarks>
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
function Preprocess(const AUtf8: TBytes; const AOptions: TPPOptions): TBytes; overload;

implementation

uses
  System.Types,                 // TStringDynArray (TDirectory.GetDirectories)
  System.IOUtils,
  System.Generics.Defaults,     // default comparer for TArray.Sort<string>
  DRagLint.Preprocess.Lexer,
  DRagLint.Preprocess.Expr;

const
  // Cycle guard: matches preprocess.js maxIncludeDepth (option default 64).
  MAX_INCLUDE_DEPTH = 64;
  // v1.2.1 port change #2: how many parent levels the nearest-first {$I} search
  // climbs (preprocess.js options.searchLevels default 3).
  SEARCH_LEVELS = 3;

var
  // v1.2.1 port change #2: process-lifetime cache of directory listings for the
  // nearest-first include search (dir -> sorted absolute subdirectory paths).
  // Mirrors preprocess.js's _subdirCache: corpus scans call the resolver once
  // per file with heavily-repeated baseDirs, so caching the readdir keeps the
  // widened search cheap. No invalidation -- acceptable for a preprocessor
  // utility's process lifetime. Created lazily; freed in the unit finalization.
  GSubdirCache: TDictionary<string, TArray<string>> = nil;

type
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
// ''. A rooted AName is honored as-is.
function ResolveInclude(const AName, ABaseDir: string; ANearSearch: Boolean): string;
var
  P    : string ;
  Dir  : string ;
  Sub  : string ;
  Lvl  : Integer;
  Parent: string;
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

  // Pass 1: ABaseDir itself (the strict, pre-#2 behavior).
  Result:= TryResolveIn(AName, ABaseDir);
  if Result <> '' then Exit;
  if not ANearSearch then Exit;

  // Pass 2: nearest-first widened search. Level 0 = ABaseDir's immediate subdirs
  // (ABaseDir itself was already tried above). Levels 1..SEARCH_LEVELS = the
  // parent dir itself + its immediate subdirs. Stop when GetDirectoryName no
  // longer changes (filesystem root).
  Dir:= TPath.GetFullPath(ABaseDir);
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
  const AIncludeMode, ABaseDir: string;
  ANearSearch: Boolean;
  ADepth: Integer;
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
  procedure ApplyIncludeDefines(const AName: string);
  var
    Resolved : string ;
    SubBytes : TBytes ;
    SubOut   : TBytes ;
    SubPos   : Integer;
  begin
    Resolved:= ResolveInclude(AName, ABaseDir, ANearSearch);
    if Resolved = '' then Exit; // unresolved -> nothing to apply (blank only)
    SubBytes:= TFile.ReadAllBytes(Resolved);
    SetLength(SubOut, Length(SubBytes)); // throwaway (child text is discarded)
    SubPos:= 0;
    // Recurse with the SAME ADefines/ANumeric instances (NOT copies) so the
    // child's {$DEFINE}/{$UNDEF} are visible to the parent's later {$IFDEF}. The
    // child's BaseDir is the resolved include's own directory, and NearSearch is
    // threaded through so a nested {$I} resolves nearest-first from there too.
    PreprocessInto(
      SubBytes, ADefines, ANumeric, AIncludeMode,
      TPath.GetDirectoryName(Resolved), ANearSearch, ADepth + 1, SubOut, SubPos);
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
      var Cond: Boolean;
      if C.Dir = 'ifdef' then Cond:= ADefines.ContainsKey(LowerCase(C.Args))
      else if C.Dir = 'ifndef' then Cond:= not ADefines.ContainsKey(LowerCase(C.Args))
      else if C.Dir = 'if' then Cond:= EvalPPExpr(C.Args, ADefines, ANumeric)
      else Cond:= False; // ifopt -- conservative
      var OuterInactive: Boolean:= not EffectivelyActive;
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
        var Cond2: Boolean:= EvalPPExpr(C.Args, ADefines, ANumeric);
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

    if (C.Dir = 'i') or (C.Dir = 'include') then
    begin
      // {$I}/{$INCLUDE} (preprocess.js:149-186, minus 'expand'). ALWAYS blank
      // the directive (no body splice). In 'defines-only', when the directive
      // is effectively active and within depth, also apply the .inc's defines
      // to the shared parent table.
      if EffectivelyActive
        and (ADepth < MAX_INCLUDE_DEPTH)
        and (AIncludeMode = 'defines-only') then
        ApplyIncludeDefines(StripQuotes(C.Args));
      BlankifyDirective(C.SrcStart, C.SrcEnd);
      Continue;
    end;

    // Any other directive is blanked (the lexer routes unknown directives to
    // text chunks, so this is a guard).
    BlankifyDirective(C.SrcStart, C.SrcEnd);
  end;
end;

function Preprocess(const AUtf8: TBytes; const AOptions: TPPOptions): TBytes; overload;
var
  Defines: TDictionary<string, Boolean>;
  Numeric: TDictionary<string, Integer>;
  D      : string           ;
  P      : TPair<string, Integer>;
  OutPos : Integer          ;
begin
  SetLength(Result, Length(AUtf8));
  OutPos:= 0;

  Defines:= TDictionary<string, Boolean>.Create;
  Numeric:= TDictionary<string, Integer>.Create;
  try
    // Seed the live defines set from the profile ONCE (already lowercased); the
    // recursion then SHARES these instances (never re-seeds per include).
    for D in AOptions.Profile.Defines do
      if D <> '' then Defines.AddOrSetValue(LowerCase(D), True);
    for P in AOptions.Profile.NumericDefines do
      Numeric.AddOrSetValue(LowerCase(P.Key), P.Value);

    PreprocessInto(
      AUtf8, Defines, Numeric, AOptions.IncludeMode, AOptions.BaseDir,
      AOptions.NearSearch, 0, Result, OutPos);
  finally
    Numeric.Free;
    Defines.Free;
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
finalization
  // Release the process-lifetime subdir cache (v1.2.1 port change #2). Lazily
  // created in SubdirsOf; may be nil if the widened search was never used.
  GSubdirCache.Free;

end.
