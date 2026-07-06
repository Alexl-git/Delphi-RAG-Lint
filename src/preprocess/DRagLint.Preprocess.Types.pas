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

implementation

end.