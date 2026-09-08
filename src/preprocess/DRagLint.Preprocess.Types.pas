unit DRagLint.Preprocess.Types;

// Shared records for the in-process Delphi port of the tree-sitter-delphi13
// preprocessor. Chunk shapes mirror lexer.js; TDefineProfile is the active
// define set the resolver (Task 6) derives from a .dproj or platform built-ins.
// NOTE: directive literals like '{$' are STRING constants; never write a bare
// brace inside a // comment-free zone... comments here use // exclusively.

interface

uses
  System.SysUtils, System.Generics.Collections;

type
  /// <summary>A lexed chunk: plain text or a recognized compiler directive.</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Preprocess.Types.pas)</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TPPChunkKind = (ckText, ckDirective);

  /// <summary>One chunk from the directive lexer. Value is set for ckText;
  /// Dir (lowercased keyword) + Args for ckDirective. SrcStart/SrcEnd are byte
  /// offsets into the input; Line is 0-based (matches lexer.js lineAt).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Preprocess.Lexer.pas), DRagLint.CLI.DoDumpPpLex (DRagLint.CLI.pas), DRagLint.Preprocess.Lexer.LexDirectives (DRagLint.Preprocess.Lexer.pas), DRagLint.Preprocess.Lexer.LexDirectives.FlushText (DRagLint.Preprocess.Lexer.pas), DRagLint.Preprocess.PreprocessInto (DRagLint.Preprocess.pas)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Preprocess, DRagLint.Preprocess.Lexer</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TPPChunk = record
    Kind    : TPPChunkKind;
    Value   : string ;
    Dir     : string ;
    Args    : string ;
    SrcStart: Integer;
    SrcEnd  : Integer;
    Line    : Integer;
  end;

  /// <summary>The active define profile for one preprocess run. Defines are
  /// lowercased symbol names; NumericDefines maps a lowercased name to an
  /// integer (for {$IF CompilerVersion >= 37} style checks).</summary>
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Core.Indexer.pas), DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoPpProfile (DRagLint.CLI.pas), DRagLint.CLI.ResolveIndexProfile (DRagLint.CLI.pas), DRagLint.Core.Indexer.TIndexer.SetPreprocess (DRagLint.Core.Indexer.pas) (+9 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Core.Indexer, DRagLint.Core.Interfaces, DRagLint.Diagnostics.ParseCache, DRagLint.Index.Closure, DRagLint.Preprocess, DRagLint.Preprocess.Profile, DRagLint.Preprocess.Types</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TDefineProfile = record
    Defines       : TArray<string>;
    NumericDefines: TArray<TPair<string, Integer>>;
  end;

  /// <summary>PP-Task-6: options carrier for a Preprocess run that handles
  /// includes. Profile is the active define profile (as above). IncludeMode is
  /// the {$I}/{$INCLUDE} handling strategy: 'off' blanks the directive and
  /// ignores its defines; 'defines-only' reads the .inc, applies its
  /// {$DEFINE}/{$UNDEF} to the PARENT's live defines set, then blanks the
  /// directive (NO body splice -- offsets stay 1:1). The 'expand' body-splice
  /// mode of preprocess.js is deliberately NOT ported (it breaks the
  /// offset-identity invariant). BaseDir is the directory a relative include
  /// name resolves against; '' disables resolution (every include blanks).
  /// NearSearch (v1.2.1 port change #2) widens {$I} resolution beyond BaseDir:
  /// when True (the default via TPPOptionsDefault), the resolver also tries
  /// BaseDir's immediate subdirs, then up to 3 parent levels each with their
  /// immediate subdirs, nearest first (real layouts: EurekaLog Source\Common\,
  /// AsyncPro PrnDrv\Win9xME\ -> source\). When False, resolution is strict
  /// BaseDir-only (the pre-#2 behavior). A default-initialized TPPOptions has
  /// NearSearch=False (Boolean zero), so callers that want the widened search
  /// must set it True -- use TPPOptionsDefault to get the JS-matching default.</summary>
  /// Tolerances (v1.2.1 port change #5) opts into the dcc-tolerance pass
  /// (DRagLint.Preprocess.Tolerance): after the chunk walk, constructs that
  /// dcc32 accepts with a missing ';' (final routine-directive group;
  /// array[..]-of-T last record field) get the ';' by REPLACING one adjacent
  /// whitespace byte -- offset-identity preserved trivially. Default False
  /// (opt-in, matching preprocess.js options.tolerances).
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// <para>Used by: declaration (DRagLint.Preprocess.Types.pas), DRagLint.CLI.DoPreprocessFile (DRagLint.CLI.pas), DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas), DRagLint.Diagnostics.ParseCache.TAstParseCache.ApplyPreprocess (DRagLint.Diagnostics.ParseCache.pas), DRagLint.Preprocess.Types.TPPOptionsDefault (DRagLint.Preprocess.Types.pas) (+2 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Core.Indexer, DRagLint.Diagnostics.ParseCache, DRagLint.Preprocess, DRagLint.Preprocess.Types</para>
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TPPOptions = record
    Profile    : TDefineProfile;
    IncludeMode: string        ;
    BaseDir    : string        ;
    NearSearch : Boolean       ;
    Tolerances : Boolean       ;
  end;

/// <summary>Returns a TPPOptions initialized to the JS-oracle defaults:
/// IncludeMode 'off', empty BaseDir, and NearSearch True (matching
/// preprocess.js's options.nearSearch !== false default). Use this instead of
/// Default(TPPOptions) when constructing options so the widened include search
/// is on unless a caller explicitly opts out.</summary>
/// <returns><!-- drag-lint:auto -->TPPOptions -- Observed: Default(TPPOptions).</returns>
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// <para>Calls: Default</para>
/// <para>Pure</para>
/// <!-- drag-lint:auto END -->
/// </remarks>
function TPPOptionsDefault: TPPOptions;

/// <summary>Replaces every CR that is NOT followed by LF with LF, so a
/// tree-sitter parse numbers its rows the way an editor does.</summary>
/// <param name="ASource">UTF-8 source bytes. NOT modified.</param>
/// <returns>The input unchanged when it holds no lone CR (the 99.5% case),
/// otherwise a normalised COPY of it.</returns>
/// <remarks>Pure, and byte-for-byte LENGTH PRESERVING, so every stored offset
/// stays valid. Idempotent, so applying it at more than one stage is harmless.
/// <para>Lives HERE, in the extractor hash surface, and not beside either of its
/// callers: the indexer half must be inside that surface so a change to it trips
/// run_extractor_version_guard, and this unit is a leaf (it uses nothing but the
/// RTL) so both callers can reach it without a cycle. It is deliberately NOT in
/// DRagLint.Parser.Delphi13, because DRagLint.Diagnostics.ParseCache avoids
/// importing that unit on purpose -- see the duplicate-global note beside its
/// own tree_sitter_delphi13 declaration.</para></remarks>
function NormalizeLoneCR(const ASource: TBytes): TBytes;

implementation

function TPPOptionsDefault: TPPOptions;
begin
  Result := Default(TPPOptions);
  Result.IncludeMode := 'off';
  Result.NearSearch  := True;
  // v1.2.1 #5: the dcc-tolerance pass is OPT-IN (JS default: tolerances off).
  Result.Tolerances  := False;
end;

{ WHY THIS EXISTS. Delphi accepts CR, LF and CRLF as line terminators, and so do
  .NET, VS Code and the RAD Studio IDE. tree-sitter counts rows by LF ONLY, so a
  lone CR does not advance its row counter and EVERY line the engine reports
  after that byte is one lower than any editor shows.

  Measured (session 58): C:\Projects\DataCopy\Tests\Test.UsageWiring.pas holds
  exactly one bare CR, at byte 11642 -- `implementation<CR><CR><LF>` -- and from
  there on the engine reported line N for the editor's line N+1.

  WHY IT IS WORSE THAN A COSMETIC OFFSET. `allow --fix-line N` writes the review
  marker to the line the user read off the report, so it lands one line off --
  the same data-damage shape DataCopy reported in
  INBOX-drag-lint-allow-corrupts-the-source-it-annotates. Gutter icons and the
  Problems panel point at the wrong line, and review-marker-stale then hashes the
  wrong line, so a marker in such a file can never verify.

  RARE, AND DELIBERATELY STILL FIXED. A scan of all 34 indexes on this machine
  (11,370 distinct indexed files) found 58 files with a lone CR, of which only 7
  are code and 6 of those are vendored or third-party. That is why this rode the
  extractor batch rather than justifying a ~5 h reindex by itself -- not because
  it was tolerable where it occurs, which is silent and data-damaging.

  ONE KNOWN EDGE, stated rather than hidden: inside a Delphi 12+ multi-line
  string literal a lone CR is CONTENT, and this rewrites it to LF, changing the
  literal by that one byte. Accepted, because the editor already displays such a
  CR as a line break -- so LF is the interpretation the author sees -- and
  because the alternative is every line number in the file being wrong.

  .dfm AND .sql ARE DELIBERATELY NOT NORMALISED. The same scan found the .dfm
  half to be the larger count (51 of 58) and the smaller problem: findings are
  not reported against .dfm lines, so a shifted row there points nothing
  anywhere. Left alone on purpose, so the asymmetry is a decision on record. }
function NormalizeLoneCR(const ASource: TBytes): TBytes;
var
  i    : Integer;
  Found: Boolean;
begin
  { SCAN FIRST, and return the input untouched when there is nothing to do. Two
    reasons, and the first is CORRECTNESS, not speed:

    * a TBytes assignment SHARES the reference -- Delphi dynamic arrays are
      reference-counted but NOT copy-on-write -- so `Result := ASource` followed
      by `Result[i] := 10` would write straight through into the CALLER's buffer,
      which is a `const` parameter. `Copy` is what makes the copy real;
    * 58 files in 11,370 hold a lone CR (0.51%), so 99.5% of parses would
      otherwise pay a full memcpy of the source for nothing. }
  Found:= False;
  for i:= 0 to High(ASource) do
    if (ASource[i] = 13) and ((i = High(ASource)) or (ASource[i + 1] <> 10)) then
    begin
      Found:= True;
      Break;
    end;
  if not Found then Exit(ASource);

  Result:= Copy(ASource, 0, Length(ASource));
  for i:= 0 to High(Result) do
    if (Result[i] = 13) and ((i = High(Result)) or (Result[i + 1] <> 10)) then
      Result[i]:= 10;
end;

end.
