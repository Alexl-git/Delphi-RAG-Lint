unit DRagLint.Diagnostics.ParseCache;

interface

uses
  System.SysUtils, System.Generics.Collections, TreeSitter, TreeSitterLib;

type
  /// <summary>One parsed source file: raw bytes + the tree-sitter tree. The owning
  /// TAstParseCache frees Tree; consumers must not.</summary>
  TParsedFile = record
    Src : TBytes;
    Tree: TTSTree;
  end;

  /// <summary>Process-wide parse-once cache so the many TAstChecker rules reuse one
  /// TTSTree per file instead of each re-reading and re-parsing it.</summary>
  /// <remarks>Not thread-safe; the lint pipeline is single-threaded per process.
  /// Call Clear between files in a batch to bound memory.</remarks>
  TAstParseCache = class
  strict private
    class var FMap: TDictionary<string, TParsedFile>;
  public
    /// <summary>Returns the parse-once result for AFile: its raw bytes and tree-sitter tree,
    /// parsing and memoizing on the first call and returning the cached entry thereafter.</summary>
    /// <param name="AFile">Path to the source file; resolved to a normalized full path used as the cache key.</param>
    /// <returns>A TParsedFile whose Tree is nil when AFile is missing or unreadable. The cache owns Tree;
    /// callers must NOT free it (call Clear to release all trees).</returns>
    class function Get(const AFile: string): TParsedFile;
    /// <summary>Frees every cached tree and empties the cache. Call between files in a batch to bound
    /// memory, and once at the end of a single-file lint.</summary>
    class procedure Clear;
  end;

function tree_sitter_delphi13: PTSLanguage; cdecl; external 'tree-sitter-delphi13';

implementation

uses
  System.IOUtils;

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
    PF.Src:= TFile.ReadAllBytes(AFile);
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

class procedure TAstParseCache.Clear;
var PF: TParsedFile;
begin
  if FMap = nil then Exit;
  for PF in FMap.Values do
    if PF.Tree <> nil then PF.Tree.Free;
  FMap.Clear;
end;

end.
