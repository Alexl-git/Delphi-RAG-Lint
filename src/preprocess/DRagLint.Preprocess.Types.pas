unit DRagLint.Preprocess.Types;

// Shared records for the in-process Delphi port of the tree-sitter-delphi13
// preprocessor. Chunk shapes mirror lexer.js; TDefineProfile is the active
// define set the resolver (Task 6) derives from a .dproj or platform built-ins.
// NOTE: directive literals like '{$' are STRING constants; never write a bare
// brace inside a // comment-free zone... comments here use // exclusively.

interface

uses
  System.Generics.Collections;

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
  /// <para>Used by: DRagLint.CLI.DoDumpPpLex (DRagLint.CLI.pas), DRagLint.Preprocess.Lexer.LexDirectives.FlushText (DRagLint.Preprocess.Lexer.pas), DRagLint.Preprocess.Lexer.LexDirectives (DRagLint.Preprocess.Lexer.pas), DRagLint.Preprocess.PreprocessInto (DRagLint.Preprocess.pas)</para>
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
  /// <para>Used by: DRagLint.CLI.ResolveIndexProfile (DRagLint.CLI.pas), DRagLint.CLI.BuildPlanItem (DRagLint.CLI.pas), DRagLint.CLI.DoPpProfile (DRagLint.CLI.pas), declaration (DRagLint.Core.Indexer.pas), DRagLint.Core.Indexer.TIndexer.SetPreprocess (DRagLint.Core.Indexer.pas) (+7 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Core.Indexer, DRagLint.Core.Interfaces, DRagLint.Index.Closure, DRagLint.Preprocess, DRagLint.Preprocess.Profile, DRagLint.Preprocess.Types</para>
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
  /// <para>Used by: DRagLint.CLI.DoPreprocessFile (DRagLint.CLI.pas), DRagLint.Core.Indexer.TIndexer.IndexFile (DRagLint.Core.Indexer.pas), declaration (DRagLint.Preprocess.Types.pas), DRagLint.Preprocess.Types.TPPOptionsDefault (DRagLint.Preprocess.Types.pas), declaration (DRagLint.Preprocess.pas) (+1 more)</para>
  /// <para>Used in units: DRagLint.CLI, DRagLint.Core.Indexer, DRagLint.Preprocess, DRagLint.Preprocess.Types</para>
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

implementation

function TPPOptionsDefault: TPPOptions;
begin
  Result := Default(TPPOptions);
  Result.IncludeMode := 'off';
  Result.NearSearch  := True;
  // v1.2.1 #5: the dcc-tolerance pass is OPT-IN (JS default: tolerances off).
  Result.Tolerances  := False;
end;

end.