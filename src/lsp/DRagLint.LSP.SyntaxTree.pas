unit DRagLint.LSP.SyntaxTree;

{ The one tree-sitter parse the LSP feature units share: UTF-8 bytes of a live
  buffer (or the file on disk, after EnsureUtf8Bytes) -> a Delphi 13 tree,
  read through a bounded-chunk callback. }

interface

uses
  System.SysUtils
  , TreeSitter
  ;

/// <summary>Parses UTF-8 source bytes with the bundled tree-sitter-delphi13
/// grammar, AFTER the same preprocessing the LSP's lint applies.</summary>
/// <param name="ASource">The source as UTF-8 bytes; byte offsets in the tree
/// index into it (the preprocessing is length-preserving).</param>
/// <param name="AFile">The file the bytes came from; only its directory is
/// used, as the preprocessor's base for {$I} define harvesting. '' is
/// allowed.</param>
/// <returns>A new tree the caller frees; nil when the parse failed.</returns>
/// <remarks>The tree is built from
/// TAstParseCache.ApplyPreprocess(ASource, AFile) -- the ONE transform the
/// lint walk uses: lone CRs normalised, and, when the process enabled
/// preprocessing (TAstParseCache.SetPreprocess, set once at lsp start-up),
/// inactive {$IFDEF} branches blanked to spaces; fail-open to the normalised
/// bytes. So semantic tokens and inlay hints carry nothing inside a branch
/// the compiler never sees, and every position after it keeps its line and
/// column. Callers keep slicing identifier text out of their own ASource:
/// the active text is byte-identical. Rename does not edit text inside an
/// inactive branch either: its edits come from the index, which is built
/// from preprocessed text (not from this parse). The read callback hands
/// tree-sitter at most 64 KiB per call, so a re-read never copies the whole
/// remaining buffer. Thread-safe per call (a parser per call; the
/// per-file define profile is resolved on every call through TAstParseCache's
/// resolver, whose cache is thread-safe).
/// Guards: tests\autotest\run_lsp_c9_preprocess_guard.ps1,
/// tests\autotest\run_lsp_c10_feature_parse_guard.ps1.</remarks>
function ParseDelphiUtf8(const ASource: TBytes; const AFile: string = ''): TTSTree;

implementation

uses
  TreeSitterLib
  , DRagLint.Parser.Delphi13
  , DRagLint.Diagnostics.ParseCache
  ;

const
  READ_CHUNK = 65536; // bytes handed to tree-sitter per read callback

function ParseDelphiUtf8(const ASource: TBytes; const AFile: string): TTSTree;
begin
  // C9: parse what the compiler sees, exactly as the LSP's lint does (C8)
  var Src: TBytes:= TAstParseCache.ApplyPreprocess(ASource, AFile);
  var Parser: TTSParser:= TTSParser.Create;
  try
    Parser.Language:= tree_sitter_delphi13;
    Result:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      begin
        var Remaining: Integer:= Length(Src) - Integer(AByteIndex);
        // bounded: never copy the whole tail per call
        if Remaining > READ_CHUNK then Remaining:= READ_CHUNK;
        if Remaining <= 0 then
        begin
          ABytesRead:= 0;
          Exit(nil);
        end;
        SetLength(Result, Remaining);
        Move(Src[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
  finally
    Parser.Free;
  end;
end;

end.
