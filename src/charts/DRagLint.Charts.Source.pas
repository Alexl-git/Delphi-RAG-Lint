unit DRagLint.Charts.Source;

{ Freshness-gated source text for the ported chart emitters (spec P1, P5). Each
  routine ports the named function in charts\src\Emit-Common.ps1 (line numbers of
  2026-10-10). THE RULE they carry (R11 of PLAN-last-four-verbs): nothing reads a
  source line BY COLUMN without first proving the file on disk is the file that
  was indexed -- a stale file is reported as Stale, never read. The exception
  texts are the PS `throw` texts, verbatim. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , System.RegularExpressions
  , DRagLint.Charts.Index
  ;

type
  /// <summary>The comment-stripped text around ONE ref. Port of the Get-SourceContext result.</summary>
  /// <remarks>STALE IS A RESULT, NOT AN ERROR: when the file fails the freshness gate every
  /// text field is '' (the PS `$null`), Following is empty and Stale is True. A caller renders
  /// `[stale source]` and must not classify. PS trap closed: `$null` has no Delphi string
  /// counterpart, so Stale -- not an empty Token -- is the only test for staleness (a fresh
  /// ref inside a comment also reads a blank Token).</remarks>
  TSourceContext = record
    /// <summary>The indexed path asked about (never the override target).</summary>
    Path      : string;
    /// <summary>The 1-based line asked about.</summary>
    Line      : Integer;
    /// <summary>True when the file on disk does not hash to the indexed sha256.</summary>
    Stale     : Boolean;
    /// <summary>Stripped text left of the ref, untrimmed.</summary>
    Before    : string;
    /// <summary>Stripped text AT the ref; blank when the ref sits inside a comment or string.</summary>
    Token     : string;
    /// <summary>Stripped text right of the ref, untrimmed.</summary>
    After     : string;
    /// <summary>The previous non-blank stripped line, trimmed; '' when none.</summary>
    PrevLine  : string;
    /// <summary>PrevLine's 1-based number; 0 when none.</summary>
    PrevLineNo: Integer;
    /// <summary>The next pFollowing stripped lines, untrimmed, for a statement that continues.</summary>
    Following : TArray<string>;
  end;

  /// <summary>Reads indexed source files only after proving they are the files the index saw.</summary>
  /// <remarks>Holds per-run caches (file shas, freshness verdicts, stripped lines) exactly as the
  /// PS held them in $script: variables, so one reader answers for one index and one run: a test
  /// that manufactures a changed file must use a fresh read path (or a fresh reader). The index
  /// is NOT owned. Not thread-safe; one owning thread.</remarks>
  TSourceReader = class
  private
    FIndex    : TChartsIndex;
    FShas     : TDictionary<string, string>;
    FOverrides: TDictionary<string, string>;
    FFresh    : TDictionary<string, Boolean>;
    FStripped : TDictionary<string, TArray<string>>;
    function ReadPath(const pPath: string): string;
    function DbPathText: string;
    function BlankMatch(const pMatch: TMatch): string;
  public
    /// <summary>Creates a reader over one index.</summary>
    /// <param name="pIndex">The index whose files table is the freshness reference; not owned,
    /// must outlive the reader. nil is accepted for the index-free members
    /// (StrippedSourceLines, ContextOfLines); anything that needs a sha then raises.</param>
    constructor Create(pIndex: TChartsIndex);
    /// <summary>Frees the caches (never the index).</summary>
    destructor Destroy; override;
    /// <summary>path -> sha256 for every file of the index, loaded once.</summary>
    /// <returns>The reader's own dictionary -- do not free or modify it. Keys are case-insensitive.</returns>
    /// <exception cref="EChartsIndex">When the reader was created without an index.</exception>
    /// <remarks>Port of Get-IndexedFileShas (Emit-Common.ps1:794). PS trap closed: a plain @{}
    /// hashtable is case-insensitive, like the Windows paths it holds, so the dictionary uses
    /// TIStringComparer.Ordinal. The PS paging (CLIENT has 625 files) is gone: AllRows has no cap.
    /// The parallel path -> id map the PS also built is not ported (nothing here reads it).</remarks>
    function IndexedFileShas: TDictionary<string, string>;
    /// <summary>Reads pReadPath whenever pIndexedPath is asked about.</summary>
    /// <param name="pIndexedPath">A path of the index; matched case-insensitively.</param>
    /// <param name="pReadPath">The file to read (and hash) instead.</param>
    /// <remarks>Port of -SourceOverride / Resolve-SourceReadPath (Emit-Common.ps1:781): it exists
    /// so a test can manufacture a stale file deterministically. PS trap closed: the keys are
    /// compared OrdinalIgnoreCase, so the dictionary is case-insensitive.</remarks>
    procedure AddOverride(const pIndexedPath, pReadPath: string);
    /// <summary>Whether the file that would be READ for pPath hashes to the sha256 the index recorded.</summary>
    /// <param name="pPath">A path of the index (any case).</param>
    /// <returns>True when the hashes match; False when they differ or the read file is missing.</returns>
    /// <exception cref="EChartsIndex">'Test-SourceFresh: &lt;path&gt; is not a file of this index (&lt;db&gt;)'
    /// when pPath is not a file of the index -- a caller bug, not a staleness verdict.</exception>
    /// <remarks>Port of Test-SourceFresh (Emit-Common.ps1:815). Cached per pPath and read path.
    /// PS traps closed: Get-FileHash answers UPPER-case hex and THashSHA2 lower-case, and the PS
    /// compare is OrdinalIgnoreCase, so SameText; the cache hashtable key is case-insensitive.
    /// &lt;db&gt; is the file SQLite reports for the main database (the PS printed $DbPath as given).
    /// A directory at the read path reads as missing (False) where the PS Get-FileHash would fail.</remarks>
    function SourceFresh(const pPath: string): Boolean;
    /// <summary>Pascal source with every comment, string and directive replaced by spaces.</summary>
    /// <param name="pReadPath">The file to read.</param>
    /// <returns>The lines, each exactly as long as the original, newlines dropped; a final line
    /// break yields a final '' element. Cached per read path; the array is shared, do not modify it.</returns>
    /// <remarks>Port of Get-StrippedSourceLines (Emit-Common.ps1:840): ONE regex over the whole
    /// file, leftmost match wins (so `'{'` is a string and `{ ' }` a comment), regex verbatim:
    /// '[^'\r\n]*'|\{[^}]*\}|\(\*[\s\S]*?\*\)|//[^\r\n]* -- a match without LF becomes that many
    /// spaces, one with LF keeps every CR and LF and blanks the rest. Directives are blanked, not
    /// evaluated (R13). PS traps closed: the file is read as Latin-1 so one byte is one char, BUT
    /// .NET ReadAllText still honours a UTF-8 / UTF-16 byte-order mark, so a BOM is detected and
    /// decoded the same way (a UTF-32 BOM is not); `-split "\r?\n"` splits on LF and drops one CR
    /// before it, keeping a lone CR in the text; the cache hashtable key is case-insensitive.</remarks>
    function StrippedSourceLines(const pReadPath: string): TArray<string>;
    /// <summary>The comment-stripped text around ONE ref, gated on freshness.</summary>
    /// <param name="pPath">A path of the index.</param>
    /// <param name="pLine">1-based line (refs.line).</param>
    /// <param name="pCol">1-based column (refs.start_col).</param>
    /// <param name="pLen">end_col - start_col (end_col is exclusive -- P10).</param>
    /// <param name="pFollowing">How many following lines to return.</param>
    /// <returns>The context; Stale True with no text when the file is not fresh.</returns>
    /// <exception cref="EChartsIndex">pPath is not a file of the index (from SourceFresh), or
    /// pLine is outside a fresh file (from ContextOfLines).</exception>
    /// <remarks>Port of Get-SourceContext (Emit-Common.ps1:868): SourceFresh, then
    /// StrippedSourceLines of the read path, then ContextOfLines.</remarks>
    function SourceContext(const pPath: string; pLine, pCol, pLen: Integer; pFollowing: Integer = 0): TSourceContext;
    /// <summary>The non-stale half of SourceContext, over lines already stripped.</summary>
    /// <param name="pPath">Path to report in the result.</param>
    /// <param name="pLines">StrippedSourceLines' result.</param>
    /// <param name="pLine">1-based line.</param>
    /// <param name="pCol">1-based column; clamped to the line.</param>
    /// <param name="pLen">Token length; a negative length counts as 0, and the end clamps to the line.</param>
    /// <param name="pFollowing">How many following lines to return (fewer at the end of the file).</param>
    /// <returns>A fresh (Stale False) context.</returns>
    /// <exception cref="EChartsIndex">'Get-SourceContext: line &lt;n&gt; is outside &lt;path&gt;
    /// (&lt;count&gt; lines) although the file is fresh'.</exception>
    /// <remarks>Split out of Get-SourceContext (Emit-Common.ps1:878-893) so the geometry is testable
    /// without an index. PS trap closed: String.Trim trims Char.IsWhiteSpace characters (which in
    /// Latin-1 include #$85 and #$A0), not Delphi Trim's "everything up to #32", so PrevLine is
    /// trimmed and tested for blankness with the Unicode whitespace rule.</remarks>
    class function ContextOfLines(const pPath: string; const pLines: TArray<string>; pLine, pCol, pLen: Integer;
      pFollowing: Integer = 0): TSourceContext;
  end;

implementation

uses
  System.Classes
  , System.IOUtils
  , System.Hash
  , System.Math
  , System.Character
  , System.Generics.Defaults
  ;

const
  { Get-StrippedSourceLines' regex, verbatim }
  STRIP_PATTERN = '''[^''\r\n]*''|\{[^}]*\}|\(\*[\s\S]*?\*\)|//[^\r\n]*';
  BOM_UTF8: array[0..2] of Byte = ($EF, $BB, $BF);
  BOM_UTF16_LEN = 2;
  BYTE_FF = $FF;
  BYTE_FE = $FE;

{ PS String.Trim: strips Char.IsWhiteSpace characters from both ends. }
function PsTrim(const pS: string): string;
begin
  var First:= 1;
  var Last:= Length(pS);
  while (First <= Last) and pS[First].IsWhiteSpace do
    Inc(First);
  while (Last >= First) and pS[Last].IsWhiteSpace do
    Dec(Last);
  Result:= Copy(pS, First, Last - First + 1);
end;

{ [IO.File]::ReadAllText(path, Latin-1): a UTF-8 or UTF-16 BOM still wins, else one byte is one char. }
function ReadLatin1(const pPath: string): string;
begin
  var Bytes:= TFile.ReadAllBytes(pPath);
  var N:= Length(Bytes);
  if (N >= Length(BOM_UTF8)) and (Bytes[0] = BOM_UTF8[0]) and (Bytes[1] = BOM_UTF8[1]) and (Bytes[2] = BOM_UTF8[2]) then
    Exit(TEncoding.UTF8.GetString(Bytes, Length(BOM_UTF8), N - Length(BOM_UTF8)));
  if (N >= BOM_UTF16_LEN) and (Bytes[0] = BYTE_FF) and (Bytes[1] = BYTE_FE) then
    Exit(TEncoding.Unicode.GetString(Bytes, BOM_UTF16_LEN, N - BOM_UTF16_LEN));
  if (N >= BOM_UTF16_LEN) and (Bytes[0] = BYTE_FE) and (Bytes[1] = BYTE_FF) then
    Exit(TEncoding.BigEndianUnicode.GetString(Bytes, BOM_UTF16_LEN, N - BOM_UTF16_LEN));
  SetLength(Result, N);
  for var K:= 0 to N - 1 do
    Result[K + 1]:= Char(Bytes[K]);
end;

{ $s -split "\r?\n": split on LF, dropping one CR right before it. }
function SplitLines(const pS: string): TArray<string>;
begin
  var Parts:= TList<string>.Create;
  try
    var Start:= 1;
    for var K:= 1 to Length(pS) + 1 do
      if (K > Length(pS)) or (pS[K] = #10) then
      begin
        var Stop:= K;
        if (K <= Length(pS)) and (Stop > Start) and (pS[Stop - 1] = #13) then
          Dec(Stop);
        Parts.Add(Copy(pS, Start, Stop - Start));
        Start:= K + 1;
      end;
    Result:= Parts.ToArray;
  finally
    Parts.Free;
  end;
end;

{ ---- TSourceReader ---- }

constructor TSourceReader.Create(pIndex: TChartsIndex);
begin
  inherited Create;
  FIndex:= pIndex;
  FOverrides:= TDictionary<string, string>.Create(TIStringComparer.Ordinal);
  FFresh:= TDictionary<string, Boolean>.Create(TIStringComparer.Ordinal);
  FStripped:= TDictionary<string, TArray<string>>.Create(TIStringComparer.Ordinal);
end;

destructor TSourceReader.Destroy;
begin
  FStripped.Free;
  FFresh.Free;
  FOverrides.Free;
  FShas.Free;
  inherited Destroy;
end;

function TSourceReader.IndexedFileShas: TDictionary<string, string>;  // dl:ok function-result-not-set@5b47 -- rule FP (INBOX-2026-10-05): the nil-index raise guard is counted as a path; every other path ends in Result:= FShas
begin
  if FShas = nil then
  begin
    if FIndex = nil then
      raise EChartsIndex.Create('TSourceReader: no index to read file shas from');
    var Rows:= FIndex.AllRows('SELECT id, path, sha256 FROM files', 'id');
    try
      FShas:= TDictionary<string, string>.Create(TIStringComparer.Ordinal);
      for var R in Rows do
        FShas.AddOrSetValue(R.S('path'), R.S('sha256'));
    finally
      Rows.Free;
    end;
  end;
  Result:= FShas;
end;

procedure TSourceReader.AddOverride(const pIndexedPath, pReadPath: string);
begin
  FOverrides.AddOrSetValue(pIndexedPath, pReadPath);
end;

function TSourceReader.ReadPath(const pPath: string): string;
begin
  if not FOverrides.TryGetValue(pPath, Result) then
    Result:= pPath;
end;

function TSourceReader.DbPathText: string;
begin
  Result:= '';
  var Rows:= FIndex.Query('PRAGMA database_list');
  try
    for var R in Rows do
      if SameText(R.S('name'), 'main') then
        Exit(R.S('file'));
  finally
    Rows.Free;
  end;
end;

function TSourceReader.SourceFresh(const pPath: string): Boolean;  // dl:ok function-result-not-set@0cb0 -- rule FP (INBOX-2026-10-05): the not-in-index raise guard is counted as a path; the rest is Exit(False), the TryGetValue out param or Result:= SameText
var
  Sha: string;
begin
  if not IndexedFileShas.TryGetValue(pPath, Sha) then
    raise EChartsIndex.Create('Test-SourceFresh: ' + pPath + ' is not a file of this index (' + DbPathText + ')');
  var Read:= ReadPath(pPath);
  if not TFile.Exists(Read) then
    Exit(False);
  var Key:= pPath + '|' + Read;
  if not FFresh.TryGetValue(Key, Result) then
  begin
    Result:= SameText(THashSHA2.GetHashStringFromFile(Read), Sha);
    FFresh.Add(Key, Result);
  end;
end;

function TSourceReader.BlankMatch(const pMatch: TMatch): string;
begin
  var V:= pMatch.Value;
  if Pos(#10, V) = 0 then
    Exit(StringOfChar(' ', Length(V)));
  Result:= V;
  for var K:= 1 to Length(Result) do
    if not CharInSet(Result[K], [#13, #10]) then
      Result[K]:= ' ';
end;

function TSourceReader.StrippedSourceLines(const pReadPath: string): TArray<string>;
begin
  if not FStripped.TryGetValue(pReadPath, Result) then
  begin
    Result:= SplitLines(TRegEx.Replace(ReadLatin1(pReadPath), STRIP_PATTERN, BlankMatch));
    FStripped.Add(pReadPath, Result);
  end;
end;

function TSourceReader.SourceContext(const pPath: string; pLine, pCol, pLen: Integer;
  pFollowing: Integer): TSourceContext;
begin
  if not SourceFresh(pPath) then
  begin
    Result:= Default(TSourceContext);
    Result.Path:= pPath;
    Result.Line:= pLine;
    Result.Stale:= True;
    Exit;
  end;
  Result:= ContextOfLines(pPath, StrippedSourceLines(ReadPath(pPath)), pLine, pCol, pLen, pFollowing);
end;

class function TSourceReader.ContextOfLines(const pPath: string; const pLines: TArray<string>;  // dl:ok function-result-not-set@833d -- rule FP (INBOX-2026-10-05): the line-out-of-range raise guard is counted as a path; Result:= Default(...) follows it unconditionally
  pLine, pCol, pLen: Integer; pFollowing: Integer): TSourceContext;
begin
  var Count:= Integer(Length(pLines));
  if (pLine < 1) or (pLine > Count) then
    raise EChartsIndex.CreateFmt('Get-SourceContext: line %d is outside %s (%d lines) although the file is fresh',
      [pLine, pPath, Count]);
  var T:= pLines[pLine - 1];
  var C0:= Min(Max(pCol - 1, 0), Length(T));
  var C1:= Min(C0 + Max(pLen, 0), Length(T));
  Result:= Default(TSourceContext);
  Result.Path:= pPath;
  Result.Line:= pLine;
  Result.Stale:= False;
  Result.Before:= Copy(T, 1, C0);
  Result.Token:= Copy(T, C0 + 1, C1 - C0);
  Result.After:= Copy(T, C1 + 1, MaxInt);
  for var K:= pLine - 2 downto 0 do
    if PsTrim(pLines[K]) <> '' then
    begin
      Result.PrevLine:= PsTrim(pLines[K]);
      Result.PrevLineNo:= K + 1;
      Break;
    end;
  var Last:= Min(pLine + pFollowing, Count);
  if Last > pLine then
    Result.Following:= Copy(pLines, pLine, Last - pLine);
end;

end.
