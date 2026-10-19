unit FeatureGen.Markdown;

{ Wiki page body -> website Markdown (spec 5.2): drops the page title, demotes
  headings, tags bare opening fences, rewrites wiki links into the site set,
  collects image refs, and refuses raw HTML and non-ASCII. }

interface

uses
  System.SysUtils
  , System.Generics.Collections
  , FeatureGen.Model
  , FeatureGen.SiteFormat
  ;

type
  /// <summary>One image a leaf pulls in from docs\Images.</summary>
  TImageRef = record
    /// <summary>Repo-relative source path, e.g. docs\Images\x.png.</summary>
    Source: string;
    /// <summary>Path relative to the features folder, e.g. img\ask-1.png.</summary>
    Target: string;
  end;

  /// <summary>Maps a wiki page name to the id of the entry whose leaf replaces it.</summary>
  /// <remarks>Page names match ignoring case. When two entries name the same page the lowest id (ordinal) wins. Not thread-safe.</remarks>
  TWikiLinkMap = class
  strict private
    FMap: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Adds one page-to-id mapping; an existing mapping with a lower or equal id is kept.</summary>
    /// <param name="pPage">Wiki page name, without .md.</param>
    /// <param name="pId">Entry id.</param>
    procedure Add(const pPage, pId: string);
    /// <summary>Adds every site-included entry that names a wikiPage; links to excluded entries stay unmapped (plain text).</summary>
    /// <param name="pFmt">Site format deciding which entries are included.</param>
    /// <param name="pReg">Loaded registry.</param>
    procedure Load(const pReg: TRegistry; const pFmt: TSiteFormat);
    /// <summary>Looks a page up.</summary>
    /// <param name="pPage">Wiki page name, without .md.</param>
    /// <param name="pId">Receives the entry id.</param>
    /// <returns>True when the page maps into the set.</returns>
    function TryGet(const pPage: string; out pId: string): Boolean;
  end;

/// <summary>Transforms one wiki page body into leaf Markdown.</summary>
/// <param name="pMd">Wiki page text, any line ending.</param>
/// <param name="pMap">Wiki page to entry id map.</param>
/// <param name="pLeafId">Id of the leaf being built; names the images and the error messages.</param>
/// <param name="pImages">Receives the images found, numbered from 1 in order of appearance.</param>
/// <param name="pFenceLang">Language tag put on every opening fence that has none.</param>
/// <returns>The body with LF line ends, trimmed. The first "# " title line is dropped, headings are one level deeper,
/// links into the set point at id.md[#anchor], other links are plain text.</returns>
/// <exception cref="EFeatureGen">Raw HTML outside code, a non-ASCII character, or an image outside docs\Images; the message names the leaf and the 1-based line.</exception>
/// <remarks>Code means fenced blocks and inline backtick spans; HTML and link rewriting never look inside it.</remarks>
function TransformWikiBody(const pMd: string; const pMap: TWikiLinkMap; const pLeafId: string;
  out pImages: TArray<TImageRef>; const pFenceLang: string = 'text'): string;

implementation

uses
  System.Classes
  , System.RegularExpressions
  , FeatureGen.Output
  ;

const
  RE_HTML = '<[a-zA-Z/][^>]*>';
  RE_LINK = '\[\[([^\]|#]+)(?:#([^\]|]+))?(?:\|([^\]]+))?\]\]'
    + '|(?<!!)\[([^\]]+)\]\(([^)\s]+)\)';
  RE_IMAGE = '!\[([^\]]*)\]\(([^)\s]+)\)';

constructor TWikiLinkMap.Create;
begin
  inherited Create;
  FMap := TDictionary<string, string>.Create;
end;

destructor TWikiLinkMap.Destroy;
begin
  FMap.Free;
  inherited;
end;

procedure TWikiLinkMap.Add(const pPage, pId: string);
var
  lKey, lOld: string;
begin
  lKey := LowerCase(pPage);
  if (lKey <> '') and ((not FMap.TryGetValue(lKey, lOld)) or (CompareStr(pId, lOld) < 0)) then
    FMap.AddOrSetValue(lKey, pId);
end;

procedure TWikiLinkMap.Load(const pReg: TRegistry; const pFmt: TSiteFormat);
var
  lE: TFeatureEntry;
begin
  for lE in pReg.Entries do
    if EntryOnSite(pFmt, lE) then
      Add(lE.WikiPage, lE.Id);
end;

function TWikiLinkMap.TryGet(const pPage: string; out pId: string): Boolean;
begin
  Result := FMap.TryGetValue(LowerCase(pPage), pId);
end;

type
  TBodyWork = class
  public
    Map: TWikiLinkMap;
    LeafId: string;
    Images: TList<TImageRef>;
    Line: Integer;
    function Fail(const pWhat: string): EFeatureGen;
    function Image(const pAlt, pSrc: string): string;
    function ImageMatch(const pM: TMatch): string;
    function Link(const pM: TMatch): string;
    function Segment(const pText: string): string;
  end;

function TBodyWork.Fail(const pWhat: string): EFeatureGen;
begin
  Result := EFeatureGen.CreateFmt('wiki body of leaf "%s", line %d: %s', [LeafId, Line, pWhat]);
end;

function TBodyWork.Image(const pAlt, pSrc: string): string;
var
  lM: TMatch;
  lRef: TImageRef;
  lExt, lName: string;
begin
  lM := TRegEx.Match(pSrc, '(?i)(?:^|[\\/])Images[\\/]([^\\/]+)$');
  if (not lM.Success) or (Pos('://', pSrc) > 0) then
    raise Fail('image "' + pSrc + '" is not under docs\Images');
  lExt := LowerCase(ExtractFileExt(lM.Groups[1].Value));
  lName := Format('%s-%d%s', [LeafId, Images.Count + 1, lExt]);
  lRef.Source := 'docs\Images\' + lM.Groups[1].Value;
  lRef.Target := 'img\' + lName;
  Images.Add(lRef);
  Result := '![' + pAlt + '](img/' + lName + ')';
end;

function TBodyWork.ImageMatch(const pM: TMatch): string;
begin
  Result := Image(pM.Groups[1].Value, pM.Groups[2].Value);
end;

function GroupText(const pM: TMatch; pIdx: Integer; out pText: string): Boolean;
begin
  Result := (pIdx < pM.Groups.Count) and pM.Groups[pIdx].Success and (pM.Groups[pIdx].Value <> '');
  if Result then
    pText := pM.Groups[pIdx].Value
  else
    pText := '';
end;

function TBodyWork.Link(const pM: TMatch): string;
var
  lId, lPage, lAnchor, lText, lTarget, lG: string;
  lHash: Integer;
begin
  if GroupText(pM, 1, lPage) then
  begin
    lPage := Trim(lPage);
    lAnchor := '';
    if GroupText(pM, 2, lG) then
      lAnchor := '#' + Trim(lG);
    lText := lPage;
    if GroupText(pM, 3, lG) then
      lText := Trim(lG);
  end
  else
  begin
    GroupText(pM, 4, lText);
    GroupText(pM, 5, lTarget);
    if TRegEx.IsMatch(lTarget, '^(?i)[a-z][a-z0-9+.-]*:') or (lTarget[1] = '#') then
      Exit(pM.Value);
    lHash := Pos('#', lTarget);
    lAnchor := '';
    if lHash > 0 then
    begin
      lAnchor := Copy(lTarget, lHash, MaxInt);
      lTarget := Copy(lTarget, 1, lHash - 1);
    end;
    lPage := ExtractFileName(StringReplace(lTarget, '/', '\', [rfReplaceAll]));
    if SameText(ExtractFileExt(lPage), '.md') then
      lPage := Copy(lPage, 1, Length(lPage) - 3);
  end;  if Map.TryGet(lPage, lId) then
    Result := '[' + lText + '](' + lId + '.md' + lAnchor + ')'
  else
    Result := lText;
end;

{ One stretch of a line with no inline code in it. }
function TBodyWork.Segment(const pText: string): string;
var
  lM: TMatch;
begin
  lM := TRegEx.Match(pText, RE_HTML);
  if lM.Success then
    raise Fail('raw HTML tag "' + lM.Value + '" outside code');
  Result := TRegEx.Replace(pText, RE_IMAGE, ImageMatch);
  Result := TRegEx.Replace(Result, RE_LINK, Link);
end;

function TransformLine(pWork: TBodyWork; const pLine: string): string;
var
  lSpans: TMatchCollection;
  lM: TMatch;
  lPos, i: Integer;
  lCode: TArray<string>;
begin
  Result := '';
  lPos := 1;
  lSpans := TRegEx.Matches(pLine, '`[^`]*`');
  SetLength(lCode, 0);
  for lM in lSpans do
  begin
    SetLength(lCode, Length(lCode) + 1);
    lCode[High(lCode)] := lM.Value;
    Result := Result + Copy(pLine, lPos, lM.Index - lPos) + #1 + IntToStr(High(lCode)) + #2;
    lPos := lM.Index + lM.Length;
  end;
  Result := pWork.Segment(Result + Copy(pLine, lPos, MaxInt));
  for i := High(lCode) downto 0 do
    Result := StringReplace(Result, #1 + IntToStr(i) + #2, lCode[i], [rfReplaceAll]);
end;
procedure CheckAscii(pWork: TBodyWork; const pLine: string);
var
  i: Integer;
begin
  for i := 1 to Length(pLine) do
    if Ord(pLine[i]) > 127 then
      raise pWork.Fail(Format('non-ASCII character U+%.4X', [Ord(pLine[i])]));
end;

function TransformWikiBody(const pMd: string; const pMap: TWikiLinkMap; const pLeafId: string;
  out pImages: TArray<TImageRef>; const pFenceLang: string): string;
var
  lWork: TBodyWork;
  lLines: TArray<string>;
  lOut: TStringList;
  lLine, lRest: string;
  i: Integer;
  lInFence, lTitleDone: Boolean;
begin
  lWork := TBodyWork.Create;
  lOut := TStringList.Create;
  try
    lWork.Map := pMap;
    lWork.LeafId := pLeafId;
    lWork.Images := TList<TImageRef>.Create;
    lLines := pMd.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
    lInFence := False;
    lTitleDone := False;
    for i := 0 to High(lLines) do
    begin
      lWork.Line := i + 1;
      lLine := lLines[i];
      CheckAscii(lWork, lLine);
      if (not lTitleDone) and (Trim(lLine) <> '') then
      begin
        lTitleDone := True;
        if TRegEx.IsMatch(lLine, '^\s*#\s') then
          Continue;
      end;
      if TRegEx.IsMatch(lLine, '^\s*```') then
      begin
        if not lInFence then
        begin
          lRest := Trim(TRegEx.Replace(lLine, '^\s*`+', ''));
          if lRest = '' then
            lLine := TrimRight(lLine) + pFenceLang;
        end;
        lInFence := not lInFence;
        lOut.Add(lLine);
        Continue;
      end;
      if lInFence then
      begin
        lOut.Add(lLine);
        Continue;
      end;
      if TRegEx.IsMatch(lLine, '^#{1,5}\s') then
        lLine := '#' + lLine;
      lOut.Add(TransformLine(lWork, lLine));
    end;
    pImages := lWork.Images.ToArray;
    Result := Trim(StringReplace(lOut.Text, #13#10, #10, [rfReplaceAll]));
  finally
    lWork.Images.Free;
    lOut.Free;
    lWork.Free;
  end;
end;

end.
