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
  TPPChunkKind = (ckText, ckDirective);

  /// <summary>One chunk from the directive lexer. Value is set for ckText;
  /// Dir (lowercased keyword) + Args for ckDirective. SrcStart/SrcEnd are byte
  /// offsets into the input; Line is 0-based (matches lexer.js lineAt).</summary>
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
  TPPOptions = record
    Profile    : TDefineProfile;
    IncludeMode: string        ;
    BaseDir    : string        ;
    NearSearch : Boolean       ;
  end;

/// <summary>Returns a TPPOptions initialized to the JS-oracle defaults:
/// IncludeMode 'off', empty BaseDir, and NearSearch True (matching
/// preprocess.js's options.nearSearch !== false default). Use this instead of
/// Default(TPPOptions) when constructing options so the widened include search
/// is on unless a caller explicitly opts out.</summary>
function TPPOptionsDefault: TPPOptions;

implementation

function TPPOptionsDefault: TPPOptions;
begin
  Result := Default(TPPOptions);
  Result.IncludeMode := 'off';
  Result.NearSearch  := True;
end;

end.