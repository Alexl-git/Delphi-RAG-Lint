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
  /// <para>Used by: DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckSyntaxErrors (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnbalancedBeginEnd (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUndeclared (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnusedLocals (DRagLint.Diagnostics.AstChecks.pas) (+41 more)</para>
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
  /// <para>Used by: DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUnbalancedBeginEnd (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckUndeclared (DRagLint.Diagnostics.AstChecks.pas) (+48 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Core.Indexer, DRagLint.Diagnostics.AstChecks, DRagLint.Diagnostics.CloneChecks, DRagLint.Diagnostics.DeadCodeChecks, DRagLint.Diagnostics.FlowChecks, DRagLint.Diagnostics.NamingChecks, DRagLint.Doc.SymbolFacts, DRagLint.Lint.ClassMetrics, DRagLint.Lint.Linter, DRagLint.Lint.ProjectRules, DRagLint.Refactor.ExtractMethod, DRagLint.Refactor.NamingFix, DRagLint.Refactor.Rename</para>
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
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.CLI.DoIndex (DRagLint.CLI.pas) ?, DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas)</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.ApplyPreprocess"/>
    /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Clear"/>
    /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class procedure SetPreprocess(AEnabled: Boolean; const AProfile: TDefineProfile);
    /// <summary>Applies the configured preprocessing to AUtf8, or returns it unchanged.</summary>
    /// <param name="AUtf8"><!-- drag-lint:auto type -->const TBytes</param>
    /// <param name="AFile"><!-- drag-lint:auto type -->const string</param>
    /// <returns><!-- drag-lint:auto -->TBytes -- Observed: AUtf8; Preprocess(AUtf8,
    /// PpOpts).</returns>
    /// <remarks>
    /// ONE transform and ONE fail-open path, shared by this cache and by
    /// TLinter -- which deliberately builds its own parser and would otherwise
    /// need a second copy of the same logic. Two copies is how the two lint
    /// entry points would drift into disagreeing about which branches are live,
    /// which is the defect this whole change exists to close.
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Diagnostics.ParseCache.TAstParseCache.Get (DRagLint.Diagnostics.ParseCache.pas), DRagLint.Lint.Linter.TLinter.CheckFileImpl (DRagLint.Lint.Linter.pas), DRagLint.Lint.Linter.TLinter.HarvestFile (DRagLint.Lint.Linter.pas)</para>
    /// <para>Calls: DRagLint.Preprocess.Preprocess/2</para>
    /// <para>Touches: file system</para>
    /// <seealso cref="DRagLint.Preprocess.Preprocess"/>
    /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Clear"/>
    /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
    /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.SetPreprocess"/>
    /// <!-- drag-lint:auto END -->
    /// </remarks>
    class function ApplyPreprocess(const AUtf8: TBytes; const AFile: string): TBytes;
    /// <summary>Returns the parse-once result for AFile: its raw bytes and tree-sitter tree,
    /// parsing and memoizing on the first call and returning the cached entry thereafter.</summary>
    /// <param name="AFile">Path to the source file; resolved to a normalized full path used as the cache key.</param>
    /// <returns>A TParsedFile whose Tree is nil when AFile is missing or unreadable. The cache owns Tree;
    /// callers must NOT free it (call Clear to release all trees).</returns>
    /// <remarks>
    /// <!-- drag-lint:auto BEGIN -->
    /// <para>Called from: DRagLint.Diagnostics.AstChecks.TAstChecker.BuildUnusedLocalFixEdits (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCodeAfterExit (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCognitiveComplexity/2 (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckControlFlowInFinally (DRagLint.Diagnostics.AstChecks.pas), DRagLint.Diagnostics.AstChecks.TAstChecker.CheckCriticalSection (DRagLint.Diagnostics.AstChecks.pas) (+48 more)</para>
    /// <para>Calls: DRagLint.Core.Encoding.EnsureUtf8Bytes, DRagLint.Diagnostics.ParseCache.TAstParseCache.ApplyPreprocess, Integer, LowerCase, Move, TreeSitter.TTSParser.Create, TreeSitter.TTSParser.Parse</para>
    /// <para>Touches: file system</para>
    /// <seealso cref="DRagLint.Core.Encoding.EnsureUtf8Bytes"/>
    /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.ApplyPreprocess"/>
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
    /// <para>Called from: DRagLint.CLI.DoCheckAst (DRagLint.CLI.pas), DRagLint.CLI.DoLint (DRagLint.CLI.pas), DRagLint.CLI.DoLintAll (DRagLint.CLI.pas), DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas), DRagLint.Lint.ClassMetrics.TClassMetrics.Run (DRagLint.Lint.ClassMetrics.pas) (+15 more)</para>
    /// <para>Pure</para>
    /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.ApplyPreprocess"/>
    /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.Get"/>
    /// <seealso cref="DRagLint.Diagnostics.ParseCache.TAstParseCache.SetPreprocess"/>
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
  { LINE-ENDING NORMALISATION FIRST, and BEFORE the early exit below, because it
    must happen whether or not preprocessing is enabled.

    tree-sitter advances its row counter on LF only, so a CR that is not part of
    a CRLF does not start a new line for it -- while Delphi, the RAD Studio IDE,
    VS Code and .NET all treat it as a terminator. Every line reported after such
    a byte is then one lower than the editor shows, which is what makes
    `allow --fix-line N` write its review marker to the WRONG line: the user
    reads N off the report and the marker lands one line off. Gutter icons and
    the Problems panel point at the wrong line for the same reason, and
    review-marker-stale then hashes the wrong line, so markers in such a file can
    never verify.

    THIS IS THE CHOKE POINT FOR BOTH LINT ENTRY POINTS. TLinter builds its own
    TTSParser and does not share this cache, but both call HERE, which is exactly
    why the transform belongs in this function and not in either caller.

    NO EXTRACTOR BUMP. src\diagnostics is outside the hash surface
    (run_extractor_version_guard: src\parser, src\preprocess, src\index), so this
    half ships without a reindex. The indexer's own copy lives in
    DRagLint.Parser.Delphi13.Parse and DOES bill the bump.

    Length-preserving, so every finding's line/col offset stays valid -- the same
    property the preprocessor's blank-to-spaces rule relies on. }
  Result:= NormalizeLoneCR(AUtf8);
  if not (FPreprocess and FProfileSet) then Exit;
  try
    var PpOpts: TPPOptions:= TPPOptionsDefault;
    PpOpts.Profile    := FProfile;
    PpOpts.IncludeMode:= 'defines-only';
    PpOpts.BaseDir    := TPath.GetDirectoryName(AFile);
    { Preprocess the NORMALISED bytes (Result), never the raw AUtf8 -- passing
      AUtf8 here silently discards the line-ending normalisation above whenever
      preprocessing is enabled, which is the default. Both are the same length,
      so this is not a behaviour change for any file without a lone CR. }
    Result:= Preprocess(Result, PpOpts);
  except
    { FAIL-OPEN, matching the indexer (Indexer.pas:948). If preprocessing throws,
      lint the RAW bytes: findings are KEPT. The safe direction here is noise,
      never silent suppression -- a swallowed exception that dropped a file's
      findings would be invisible, and no count anywhere would move. }
    { NORMALISED, not raw: the fallback drops the PREPROCESSING, which is what
      threw, and must not also drop the line-ending normalisation, which cannot
      throw and is what keeps reported lines pointing where the editor does. }
    on E: Exception do Result:= NormalizeLoneCR(AUtf8);
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
