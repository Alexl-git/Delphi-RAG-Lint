unit DRagLint.Charts.Text;

{ Pure text helpers shared by every ported chart emitter (spec P1). Each routine
  is a port of the named function in charts\src\Emit-Common.ps1 (line numbers of
  2026-10-10); the PowerShell output is the reference (P3/P4), so every port
  comment names the PS trap it closes. No I/O, no state, no index access. }

interface

uses
  System.SysUtils;

const
  /// <summary>What UnitNameOf and PathZone return for a blank path (the PS literal).</summary>
  UNKNOWN_TEXT = '(unknown)';
  /// <summary>What PathZone returns for a file at or above the common root (the PS literal).</summary>
  ROOT_ZONE = '(root)';

type
  /// <summary>The top of an already-ranked row list and an exact account of what was cut.</summary>
  /// <remarks>Port of the object Get-TopRanked (Emit-Common.ps1:711) returns. Delphi has no
  /// generic global functions, so the routine is the static TopRanked on this record:
  /// <c>TRanked&lt;TRow&gt;.TopRanked(Rows, Cap, SitesOf)</c>.</remarks>
  TRanked<T> = record
    /// <summary>The first Cap rows (every row when Cap &lt;= 0 or the list is short).</summary>
    Shown      : TArray<T>;
    /// <summary>Rows after nil rows were stripped.</summary>
    Total      : Integer;
    /// <summary>Rows left out (Total - Length(Shown)).</summary>
    HiddenRows : Integer;
    /// <summary>Sum of the site counter over the rows left out; 0 without a counter.</summary>
    HiddenSites: Integer;
    /// <summary>Cuts an ALREADY-RANKED list to its top pCap rows and counts what was left out.</summary>
    /// <param name="pRows">Rows in rank order; ranking is the caller's job. Nil class or
    /// interface rows are stripped first.</param>
    /// <param name="pCap">Rows to keep; 0 or less keeps every row.</param>
    /// <param name="pSites">Per-row site count to total over the hidden rows, or nil when the
    /// rows carry none (the PS row without a Sites property).</param>
    /// <returns>The shown rows and the counts of what was hidden.</returns>
    /// <remarks>PS trap closed: `$null` in a pipeline -- the PS strips null rows because
    /// `$x = if (...) { @() }` assigns $null and `@($null)` is a one-element array; a Delphi
    /// array of a class type can likewise carry nil, so nil rows are dropped before counting.
    /// Rows are not copied; Shown shares the caller's references.</remarks>
    class function TopRanked(const pRows: TArray<T>; pCap: Integer; const pSites: TFunc<T, Integer>): TRanked<T>; static;
  end;

/// <summary>XML-escapes text for a DOT HTML label or an SVG attribute.</summary>
/// <param name="pS">Plain text; '' gives ''.</param>
/// <returns>pS with &amp; &lt; &gt; and the double quote escaped, ampersand first.</returns>
/// <remarks>Port of ConvertTo-XmlText (Emit-Common.ps1:31). PS trap closed: `$null` reads as
/// '' (Delphi strings are never nil). The single quote is NOT escaped, as in the PS.</remarks>
function XmlText(const pS: string): string;

/// <summary>The unit name of a source path: its file name without the extension.</summary>
/// <param name="pFile">A source path; '/' and '\' both separate.</param>
/// <returns>The bare unit name, or UNKNOWN_TEXT when pFile is blank or whitespace.</returns>
/// <remarks>Port of Get-UnitName (Emit-Common.ps1:36). PS trap closed: .NET
/// GetFileNameWithoutExtension splits on '/' as well as '\', Delphi's ExtractFileName does
/// not, so '/' is normalised first; IsNullOrWhiteSpace is matched with Trim.</remarks>
function UnitNameOf(const pFile: string): string;

/// <summary>A qualified name with its unit prefix removed.</summary>
/// <param name="pQName">The qualified name.</param>
/// <param name="pUnit">The unit to strip; '' strips nothing.</param>
/// <returns>pQName without the leading '&lt;pUnit&gt;.', or pQName unchanged; '' for a blank pQName.</returns>
/// <remarks>Port of Get-ShortName (Emit-Common.ps1:41). PS trap closed: the PS uses
/// StartsWith(..., OrdinalIgnoreCase), so the unit match is case-blind (StartsText).</remarks>
function ShortName(const pQName, pUnit: string): string;

/// <summary>The draglint:// open-at-line link a chart row carries, already XML-escaped.</summary>
/// <param name="pFile">Source path to open.</param>
/// <param name="pLine">1-based line.</param>
/// <returns><c>draglint://open?file=&lt;escaped&gt;&amp;amp;line=&lt;n&gt;</c>.</returns>
/// <remarks>Port of New-RowHref (Emit-Common.ps1:49). PS trap closed: [uri]::EscapeDataString
/// is NOT TNetEncoding.URL -- it keeps only the RFC 3986 unreserved set (A-Z a-z 0-9 - _ . ~)
/// and writes every other UTF-8 byte as %XX in UPPERCASE hex (a space is %20, never '+').
/// The '&amp;amp;' between the two parameters is literal, as the PS emits it.</remarks>
function RowHref(const pFile: string; pLine: Integer): string;  // dl:ok unused-public-symbol@4270 -- REVIEWED 2026-10-11: step-1 port of Emit-Common for the in-process emitters (spec P1/P3); no production caller until an emitter is ported; pinned by ChartsTests.CoreText and the ChartsCoreProbe parity harness, which sit outside this project index

/// <summary>The one "not shown" sentence every chart uses.</summary>
/// <param name="pHiddenRows">Rows left out; 0 or less gives ''.</param>
/// <param name="pHiddenSites">Sites inside those rows; shown only when positive.</param>
/// <param name="pNoun">What a row is, plural.</param>
/// <returns>'+N more &lt;noun&gt; (+M more sites) not shown', or '' when nothing was hidden.</returns>
/// <remarks>Port of Get-DisclosureText (Emit-Common.ps1:736). No trap: integers only.</remarks>
function DisclosureText(pHiddenRows, pHiddenSites: Integer; const pNoun: string = 'routines'): string;  // dl:ok unused-public-symbol@d21f -- REVIEWED 2026-10-11: step-1 port of Emit-Common for the in-process emitters (spec P1/P3); no production caller until an emitter is ported; pinned by ChartsTests.CoreText and the ChartsCoreProbe parity harness, which sit outside this project index

/// <summary>How many leading '\'-separated segments every directory shares.</summary>
/// <param name="pDirs">Directories; blanks are ignored.</param>
/// <returns>The common segment count, 0 when none is shared or no directory was given.</returns>
/// <remarks>Port of Get-CommonRootLen (Emit-Common.ps1:572). PS traps closed: `Sort-Object
/// -Unique` dedupes case-insensitively and segments compare with `-eq` (case-insensitive),
/// so segments compare with SameText -- 'orm3' and 'ORM3' are one directory; `-split '\\'`
/// keeps empty segments, as does string.Split. The PS sort only fixes which directory seeds
/// the prefix, which a case-insensitive comparison makes irrelevant, so no sort is done.</remarks>
function CommonRootLen(const pDirs: TArray<string>): Integer;  // dl:ok unused-public-symbol@cb31 -- REVIEWED 2026-10-11: step-1 port of Emit-Common for the in-process emitters (spec P1/P3); no production caller until an emitter is ported; pinned by ChartsTests.CoreText and the ChartsCoreProbe parity harness, which sit outside this project index

/// <summary>The zone of a source file: its directory below the common root, '/'-joined.</summary>
/// <param name="pPath">The source file path.</param>
/// <param name="pRootLen">CommonRootLen of the population.</param>
/// <returns>e.g. 'COMMON/OBJECTS'; ROOT_ZONE at or above the root or when pRootLen &lt;= 0;
/// UNKNOWN_TEXT for a blank path.</returns>
/// <remarks>Port of Get-PathZone (Emit-Common.ps1:587). PS trap closed: .NET GetDirectoryName
/// treats '/' as a separator and Delphi ExtractFileDir does not, so '/' is normalised first.</remarks>
function PathZone(const pPath: string; pRootLen: Integer): string;  // dl:ok unused-public-symbol@49ba -- REVIEWED 2026-10-11: step-1 port of Emit-Common for the in-process emitters (spec P1/P3); no production caller until an emitter is ported; pinned by ChartsTests.CoreText and the ChartsCoreProbe parity harness, which sit outside this project index

/// <summary>The file-name part of a path, '/' and '\' both separating.</summary>
/// <param name="pPath">A path.</param>
/// <returns>What follows the last separator.</returns>
/// <remarks>Stands in for [IO.Path]::GetFileName, which the PS calls inline in several
/// helpers (the candidate list of Resolve-MemberSelection, Get-EdgelessDisclosure). PS trap
/// closed: .NET splits on '/' as well as '\'; Delphi ExtractFileName does not.</remarks>
function FileNameOf(const pPath: string): string;

implementation

uses
  System.StrUtils;

const
  SEG_SEP = '\';
  ZONE_SEP = '/';
  ALT_SEP = '/';
  HEX_DIGITS = 2;

function NormalSeparators(const pPath: string): string;
begin
  Result:= StringReplace(pPath, ALT_SEP, SEG_SEP, [rfReplaceAll]);
end;

class function TRanked<T>.TopRanked(const pRows: TArray<T>; pCap: Integer; const pSites: TFunc<T, Integer>): TRanked<T>;
var
  All: TArray<T>;
  N  : Integer;
begin
  SetLength(All, Length(pRows));
  N:= 0;
  for var Row in pRows do
  begin
    { $null vanishes: a nil class/interface row is not a row }
    if (GetTypeKind(T) in [tkClass, tkInterface, tkPointer]) and (PPointer(@Row)^ = nil) then
      Continue;
    All[N]:= Row;
    Inc(N);
  end;
  SetLength(All, N);
  Result:= Default(TRanked<T>);
  Result.Total:= N;
  Result.Shown:= All;
  if (pCap > 0) and (N > pCap) then
  begin
    Result.Shown:= Copy(All, 0, pCap);
    for var K:= pCap to N - 1 do
    begin
      Inc(Result.HiddenRows);
      if Assigned(pSites) then
        Inc(Result.HiddenSites, pSites(All[K]));
    end;
  end;
end;

function XmlText(const pS: string): string;
begin
  Result:= pS.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;');
end;

function FileNameOf(const pPath: string): string;
begin
  Result:= ExtractFileName(NormalSeparators(pPath));
end;

function UnitNameOf(const pFile: string): string;
begin
  if Trim(pFile) = '' then
    Exit(UNKNOWN_TEXT);
  Result:= ChangeFileExt(FileNameOf(pFile), '');
end;

function ShortName(const pQName, pUnit: string): string;
begin
  if Trim(pQName) = '' then
    Exit('');
  if (pUnit <> '') and StartsText(pUnit + '.', pQName) then
    Exit(Copy(pQName, Length(pUnit) + 2, MaxInt));
  Result:= pQName;
end;

function EscapeDataString(const pS: string): string;
const
  UNRESERVED = ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '~'];
var
  SB: TStringBuilder;
begin
  SB:= TStringBuilder.Create;
  try
    for var B in TEncoding.UTF8.GetBytes(pS) do
      if AnsiChar(B) in UNRESERVED then
        SB.Append(Char(B))
      else
        SB.Append('%').Append(IntToHex(B, HEX_DIGITS));
    Result:= SB.ToString;
  finally
    SB.Free;
  end;
end;

function RowHref(const pFile: string; pLine: Integer): string;
begin
  Result:= 'draglint://open?file=' + EscapeDataString(pFile) + '&amp;line=' + IntToStr(pLine);
end;

function DisclosureText(pHiddenRows, pHiddenSites: Integer; const pNoun: string): string;
begin
  if pHiddenRows <= 0 then
    Exit('');
  Result:= Format('+%d more %s', [pHiddenRows, pNoun]);
  if pHiddenSites > 0 then
    Result:= Result + Format(' (+%d more sites)', [pHiddenSites]);
  Result:= Result + ' not shown';
end;

function CommonRootLen(const pDirs: TArray<string>): Integer;
var
  Common: TArray<string>;
  Seeded: Boolean;
begin
  Seeded:= False;
  for var Dir in pDirs do
  begin
    if Dir = '' then
      Continue;
    var Parts:= Dir.Split([SEG_SEP]);
    if not Seeded then
    begin
      Common:= Parts;
      Seeded:= True;
      Continue;
    end;
    var N:= Length(Common);
    if Length(Parts) < N then
      N:= Length(Parts);
    var Keep:= 0;
    while (Keep < N) and SameText(Common[Keep], Parts[Keep]) do
      Inc(Keep);
    if Keep = 0 then
      Exit(0);
    SetLength(Common, Keep);
  end;
  Result:= Length(Common);
end;

function PathZone(const pPath: string; pRootLen: Integer): string;
begin
  if Trim(pPath) = '' then
    Exit(UNKNOWN_TEXT);
  var Parts:= ExtractFileDir(NormalSeparators(pPath)).Split([SEG_SEP]);
  if (pRootLen <= 0) or (Length(Parts) <= pRootLen) then
    Exit(ROOT_ZONE);
  Result:= string.Join(ZONE_SEP, Copy(Parts, pRootLen, MaxInt));
end;

end.
