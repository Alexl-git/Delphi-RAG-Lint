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
/// grammar.</summary>
/// <param name="ASource">The source as UTF-8 bytes; byte offsets in the tree
/// index into it.</param>
/// <returns>A new tree the caller frees; nil when the parse failed.</returns>
/// <remarks>The read callback hands tree-sitter at most 64 KiB per call, so a
/// re-read never copies the whole remaining buffer. Thread-safe per call (a
/// parser per call).</remarks>
function ParseDelphiUtf8(const ASource: TBytes): TTSTree;

implementation

uses
  TreeSitterLib
  , DRagLint.Parser.Delphi13
  ;

const
  READ_CHUNK = 65536; // bytes handed to tree-sitter per read callback

function ParseDelphiUtf8(const ASource: TBytes): TTSTree;
begin
  var Parser: TTSParser:= TTSParser.Create;
  try
    Parser.Language:= tree_sitter_delphi13;
    Result:= Parser.Parse(
      function (AByteIndex: UInt32; APosition: TTSPoint; var ABytesRead: UInt32): TBytes
      begin
        var Remaining: Integer:= Length(ASource) - Integer(AByteIndex);
        // bounded: never copy the whole tail per call
        if Remaining > READ_CHUNK then Remaining:= READ_CHUNK;
        if Remaining <= 0 then
        begin
          ABytesRead:= 0;
          Exit(nil);
        end;
        SetLength(Result, Remaining);
        Move(ASource[AByteIndex], Result[0], Remaining);
        ABytesRead:= Remaining;
      end, TTSInputEncoding.TSInputEncodingUTF8);
  finally
    Parser.Free;
  end;
end;

end.
