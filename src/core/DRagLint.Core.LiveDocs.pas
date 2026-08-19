unit DRagLint.Core.LiveDocs;

{ Live, unsaved editor content for documents the client has open.

  WHY THIS EXISTS (2026-08-18). Every position-based LSP request -- hover,
  completion, definition, signature help -- located the identifier under the
  cursor by reading the file FROM DISK. The server deliberately did not
  implement textDocument/didChange (see the note on TLSPServer), on the
  reasoning that files are indexed ahead of time and a re-index is cheap.

  That reasoning holds for the INDEX. It does not hold for the CURSOR. An
  editor sends a position describing the BUFFER, and the buffer diverges from
  disk the moment the user types. The observed failure: the user typed
  `AExceptionInfo.Assign` and hovered `Assign`; disk still held
  `AExceptionInfo.;`, so the column landed past end-of-line, the identifier
  resolved to '', and hover returned null -- while the IDE's own Help Insight,
  which reads the live buffer, described the method correctly. The popup then
  showed only the line's lint finding, which read as "drag-lint has nothing to
  say about Assign".

  The failure mode is worth naming because it is silent and it inverts the
  usual staleness story: the answer is not merely OUT OF DATE, it is ABSENT,
  and absence is rendered as "no such symbol" rather than as an error. It also
  gets WORSE the more the user is actually editing, which is precisely when
  hover and completion are wanted.

  So the overlay is keyed by path and consulted BEFORE disk by every reader in
  the position pipeline. It holds only what the client has explicitly sent; an
  empty overlay means "no open buffer", never "an empty file", and every
  accessor falls through to disk in that case. It does NOT feed the indexer --
  the index remains a disk-derived artifact and nothing here writes to it. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections, System.IOUtils;

type
  /// <summary>
  /// Process-wide store of open documents' live text, keyed by absolute path.
  /// Consulted before disk by every position-based LSP reader.
  /// </summary>
  /// <remarks>
  /// Not thread-safe by design: the LSP server is a single-threaded stdio loop
  /// and every mutation arrives as a message on that loop. A guard here would
  /// be pure cost. If a threaded host is ever added, wrap the class in a lock
  /// rather than making the callers defensive.
  /// </remarks>
  TLiveDocuments = class
    strict private
      class var FTexts: TDictionary<string, string>;
      class function Key(const APath: string): string; static;
    public
      class constructor Create;
      class destructor Destroy;

      /// <summary>Records the client's current text for a document.</summary>
      /// <param name="APath">Absolute file path (already decoded from the URI).</param>
      /// <param name="AText">Full buffer content. Stored verbatim.</param>
      class procedure SetText(const APath, AText: string); static;

      /// <summary>Forgets a document, so later reads fall back to disk.</summary>
      class procedure Remove(const APath: string); static;

      /// <summary>Forgets every document. Used on shutdown.</summary>
      class procedure Clear; static;

      /// <summary>True when the client has sent text for this path.</summary>
      class function HasText(const APath: string): Boolean; static;

      /// <summary>Number of documents currently overlaid. For diagnostics.</summary>
      class function Count: Integer; static;

      /// <summary>
      /// The document's content as lines -- overlay when open, else the file on
      /// disk read as ANSI (the repo's source encoding).
      /// </summary>
      /// <returns>Empty array when the path is neither open nor on disk.</returns>
      class function ReadLines(const APath: string): TArray<string>; static;

      /// <summary>
      /// The document's raw bytes -- overlay encoded as UTF-8 when open, else
      /// the file on disk verbatim. Callers still normalise disk bytes through
      /// EnsureUtf8Bytes; overlay bytes are already UTF-8.
      /// </summary>
      class function ReadBytes(const APath: string; out AFromOverlay: Boolean): TBytes; static;

      /// <summary>
      /// True when the path can be read at all -- open in the client OR present
      /// on disk. Replaces bare TFile.Exists guards, which would reject a
      /// buffer that exists only in the editor.
      /// </summary>
      class function Readable(const APath: string): Boolean; static;
  end;

implementation

class constructor TLiveDocuments.Create;
begin
  FTexts:= TDictionary<string, string>.Create;
end;

class destructor TLiveDocuments.Destroy;
begin
  FTexts.Free;
end;

class function TLiveDocuments.Key(const APath: string): string;
begin
  { Windows paths are case-insensitive and the client's casing is not ours to
    trust: an editor may send the URI with the drive letter lowercased. Key on
    a normalised form so didChange and the following hover agree. }
  Result:= LowerCase(StringReplace(Trim(APath), '/', '\', [rfReplaceAll]));
end;

class procedure TLiveDocuments.SetText(const APath, AText: string);
begin
  if Trim(APath) = '' then Exit;
  FTexts.AddOrSetValue(Key(APath), AText);
end;

class procedure TLiveDocuments.Remove(const APath: string);
begin
  FTexts.Remove(Key(APath));
end;

class procedure TLiveDocuments.Clear;
begin
  FTexts.Clear;
end;

class function TLiveDocuments.HasText(const APath: string): Boolean;
begin
  Result:= FTexts.ContainsKey(Key(APath));
end;

class function TLiveDocuments.Count: Integer;
begin
  Result:= FTexts.Count;
end;

class function TLiveDocuments.Readable(const APath: string): Boolean;
begin
  Result:= HasText(APath) or TFile.Exists(APath);
end;

class function TLiveDocuments.ReadLines(const APath: string): TArray<string>;
var
  Text: string;
  SL  : TStringList;
begin
  SetLength(Result, 0);
  if FTexts.TryGetValue(Key(APath), Text) then
  begin
    { TStringList splits on CR, LF and CRLF alike, which matters because the
      client's buffer may not carry the file's line endings. }
    SL:= TStringList.Create;
    try
      SL.Text:= Text;
      Result:= SL.ToStringArray;
    finally
      SL.Free;
    end;
    Exit;
  end;
  if TFile.Exists(APath) then
    Result:= TFile.ReadAllLines(APath, TEncoding.ANSI);
end;

class function TLiveDocuments.ReadBytes(const APath: string; out AFromOverlay: Boolean): TBytes;
var
  Text: string;
begin
  SetLength(Result, 0);
  AFromOverlay:= False;
  if FTexts.TryGetValue(Key(APath), Text) then
  begin
    AFromOverlay:= True;
    Result:= TEncoding.UTF8.GetBytes(Text);
    Exit;
  end;
  if TFile.Exists(APath) then
    Result:= TFile.ReadAllBytes(APath);
end;

end.
