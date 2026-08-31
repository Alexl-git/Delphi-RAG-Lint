unit DRagLint.Diagnostics.ParseCache;

interface

uses
  System.SysUtils, System.Generics.Collections, TreeSitter, TreeSitterLib,
  DRagLint.Preprocess, DRagLint.Preprocess.Types;

type
  /// <summary>One parsed source file: raw bytes + the tree-sitter tree. The owning
  /// TAstParseCache frees Tree; consumers must not.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUndeclared (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnbalancedBeginEnd (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSyntaxErrors (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnusedLocals (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits (DRagLint.Diagnostics.AstChecks.pas) (+38 more)</para>
  /// <para>Used in units: DRagLint.Diagnostics.AstChecks, DRagLint.Diagnostics.CloneChecks, DRagLint.Diagnostics.DeadCodeChecks, DRagLint.Diagnostics.FlowChecks, DRagLint.Diagnostics.NamingChecks, DRagLint.Diagnostics.ParseCache, DRagLint.Doc.SymbolFacts, DRagLint.Lint.ProjectRules, DRagLint.Refactor.ExtractMethod, DRagLint.Refactor.NamingFix, DRagLint.Refactor.Rename</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TParsedFile = record
    { What the parser saw and what every AST rule slices. Since the lint walk
      started preprocessing, this is the PREPROCESSED text: dead branches and
      the directives themselves are blanked to spaces. }
    Src   : TBytes;
    { The bytes as they are ON DISK. Kept because blanking removes the
      DIRECTIVES, so any check that reads directive TEXT out of the source --
      CheckSyntaxErrors.BuildConditionalRanges is the one that does -- must read
      this and not Src, or it sees no conditionals at all. Offsets are identical
      between the two: the preprocessor is offset-preserving by construction. }
    RawSrc: TBytes;
    Tree  : TTSTree;
  end;

  /// <summary>Process-wide parse-once cache so the many TAstChecker rules reuse one
  /// TTSTree per file instead of each re-reading and re-parsing it.</summary>
  /// <remarks>
  /// Not thread-safe; the lint pipeline is single-threaded per process.
  /// Call Clear between files in a batch to bound memory.
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUndeclared (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnbalancedBeginEnd (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSyntaxErrors (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnusedLocals (DRagLint.Diagnostics.AstChecks.pas) (+40 more)</para>
  /// <para>Used in units: DRagLint.Core.Indexer, DRagLint.Diagnostics.AstChecks, DRagLint.Diagnostics.CloneChecks, DRagLint.Diagnostics.DeadCodeChecks, DRagLint.Diagnostics.FlowChecks, DRagLint.Diagnostics.NamingChecks, DRagLint.Doc.SymbolFacts, DRagLint.Lint.ClassMetrics, DRagLint.Lint.ProjectRules, DRagLint.Refactor.ExtractMethod, DRagLint.Refactor.NamingFix, DRagLint.Refactor.Rename</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TAstParseCache = class
  strict private
    class var FMap: TDictionary<string, TParsedFile>;
    class var FPreprocess: Boolean;
    class var FProfile   : TDefineProfile;
    class var FProfileSet: Boolean;
  public
    /// <summary>Enables the same preprocessing the INDEX side already does, so the
    /// lint walk stops reporting findings inside branches the compiler never sees.</summary>
    /// <param name="AEnabled">False restores raw-byte parsing (what --no-preprocess asks for).</param>
    /// <param name="AProfile">The define profile; resolve it the way the indexer does.</param>
    /// <remarks>
    /// Mirrors TIndexer.SetPreprocess. Call BEFORE the first Get for a file --
    /// entries are memoized, so flipping this mid-run leaves earlier files parsed
    /// the old way. The CLI sets it once per verb, before any walking starts.
    /// </remarks>
    class procedure SetPreprocess(AEnabled: Boolean; const AProfile: TDefineProfile);
    /// <summary>Applies the configured preprocessing to AUtf8, or returns it unchanged.</summary>
    /// <remarks>
    /// ONE transform and ONE fail-open path, shared by this cache and by
    /// TLinter -- which deliberately builds its own parser and would otherwise
    /// need a second copy of the same logic. Two copies is how the two lint
    /// entry points would drift into disagreeing about which branches are live,
    /// which is the defect this whole change exists to close.
    /// </remarks>
    class function ApplyPreprocess(const AUtf8: TBytes; const AFile: string): TBytes;
    /// <summary>Returns the parse-once result for AFile: its raw bytes and tree-sitter tree,
    /// parsing and memoizing on the first call and returning the cached entry thereafter.</summary>
    /// <param name="AFile">Path to the source file; resolved to a normalized full path used as the cache key.</param>
    /// <returns>A TParsedFile whose Tree is nil when AFile is missing or unreadable. The cache owns Tree;
    /// callers must NOT free it (call Clear to release all trees).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCognitiveComplexity/2 (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckControlFlowInFinally (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCriticalSection (DRagLint.Diagnostics.AstChecks.pas) (+44 more)</para>
    /// <para>Calls: DRagLint.Core.Encoding.EnsureUtf8Bytes, Integer, LowerCase, Move, TreeSitter.TTSParser.Create, TreeSitter.TTSParser.Parse</para>
    /// <para>Touches: file system</para>
    /// <seealso cref="DRagLint.Core.Encoding.EnsureUtf8Bytes"/>
    /// <seealso cref="TreeSitter.TTSParser.Create"/>
    /// <seealso cref="TreeSitter.TTSParser.Parse"/>
    /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Clear"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function Get(const AFile: string): TParsedFile;
    /// <summary>Frees every cached tree and empties the cache. Call between files in a batch to bound
    /// memory, and once at the end of a single-file lint.</summary>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoCheckAst (DRagLint.CLI.pas), DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas), DRagLint.Lint.ClassMetrics.TClassMetrics.Run (DRagLint.Lint.ClassMetrics.pas) (+9 more)</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure Clear;
  end;

implementation

uses
  System.IOUtils, DRagLint.Core.Encoding;

{ DECLARED HERE, NOT IN THE INTERFACE, and that is the point rather than a
  tidiness preference. DRagLint.Parser.Delphi13 already exports this same
  external import from ITS interface, so exporting it here too meant any unit
  that used both got whichever came last in its uses clause -- the exact
  uses-order hazard duplicate-global-decl exists to report, in our own tree.
  Surfaced 2026-08-31 when that rule was widened past ('const','var').
  DRagLint.Diagnostics.AstChecks already declares it in its implementation for
  the same reason; this now matches. Only TAstParseCache.Get uses it. }
function tree_sitter_delphi13: PTSLanguage; cdecl; external 'tree-sitter-delphi13';

class function TAstParseCache.Get(const AFile: string): TParsedFile;
var
  Key   : string;
  Parser: TTSParser;
  PF    : TParsedFile;
begin
  Key:= LowerCase(TPath.GetFullPath(AFile));
  if FMap = nil then FMap:= TDictionary<string, TParsedFile>.Create;
  if FMap.TryGetValue(Key, Result) then Exit;

  PF.Src := nil;
  PF.Tree:= nil;
  if TFile.Exists(AFile) then
  begin
    // v0.86 (Task 3): transcode ANSI/UTF-16 sources to valid UTF-8 up front.
    // PF.Src is fed to tree-sitter below AND sliced by every AST rule
    // downstream (all assume UTF-8), so transcoding here fixes them all.
    PF.RawSrc:= EnsureUtf8Bytes(TFile.ReadAllBytes(AFile));
    PF.Src   := PF.RawSrc;
    { THE LINT WALK NOW PREPROCESSES, and before this it never did -- not "with
      the wrong defines", but not at all: Preprocess had three production
      callers and every one was on the index side. So `lint` parsed raw bytes
      and reported code the compiler never compiles. Measured: 592 findings,
      3.7% of ORM3 SERVER's entire lint-all, from ONE file whose 7,074-line body
      sits inside a never-defined IFDEF.

      It also fixes the OPPOSITE and more dangerous direction. The grammar
      handles IFDEF/ELSE itself and unconditionally keeps the FIRST
      branch, so a TAKEN ELSE branch was never linted at all -- silently, with no
      count anywhere going up to say so.

      FAIL-OPEN, matching the indexer (Indexer.pas:948): if preprocessing
      throws, parse the RAW bytes. Findings are kept. The safe direction here is
      noise, never silent suppression.

      Offsets are preserved by construction -- the preprocessor blanks to spaces
      rather than deleting -- so every finding's line/col stays valid and no
      caller needs remapping. }
    PF.Src:= ApplyPreprocess(PF.RawSrc, AFile);
    Parser:= TTSParser.Create;
    try
      Parser.Language:= tree_sitter_delphi13;
      PF.Tree:= Parser.Parse(
        function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
        var Remaining: Integer;
        begin
          Remaining:= Length(PF.Src) - Integer(AByteIndex);
          if Remaining <= 0 then begin ABytesRead:= 0; SetLength(Result, 0); Exit; end;
          SetLength(Result, Remaining);
          Move(PF.Src[AByteIndex], Result[0], Remaining);
          ABytesRead:= Remaining;
        end, TTSInputEncoding.TSInputEncodingUTF8);
    finally
      Parser.Free; { the tree outlives the parser }
    end;
  end;
  FMap.Add(Key, PF);
  Result:= PF;
end;

class function TAstParseCache.ApplyPreprocess(const AUtf8: TBytes; const AFile: string): TBytes;
begin
  Result:= AUtf8;
  if not (FPreprocess and FProfileSet) then Exit;
  try
    var PpOpts: TPPOptions:= TPPOptionsDefault;
    PpOpts.Profile    := FProfile;
    PpOpts.IncludeMode:= 'defines-only';
    PpOpts.BaseDir    := TPath.GetDirectoryName(AFile);
    Result:= Preprocess(AUtf8, PpOpts);
  except
    { FAIL-OPEN, matching the indexer (Indexer.pas:948). If preprocessing throws,
      lint the RAW bytes: findings are KEPT. The safe direction here is noise,
      never silent suppression -- a swallowed exception that dropped a file's
      findings would be invisible, and no count anywhere would move. }
    on E: Exception do Result:= AUtf8;
  end;
end;

class procedure TAstParseCache.SetPreprocess(AEnabled: Boolean; const AProfile: TDefineProfile);
begin
  FPreprocess:= AEnabled;
  FProfile   := AProfile;
  FProfileSet:= True;
  { Entries already parsed keep the treatment they were parsed under, so a
    caller that flips this mid-walk gets a mixture. Clearing here would be worse
    -- it would silently discard trees other rules still hold. The contract is
    "set it before the first Get", and the CLI does. }
end;

class procedure TAstParseCache.Clear;
var PF: TParsedFile;
begin
  if FMap = nil then Exit;
  for PF in FMap.Values do
    if PF.Tree <> nil then PF.Tree.Free;
  FMap.Clear;
end;

end.
