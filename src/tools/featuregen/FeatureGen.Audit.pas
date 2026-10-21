unit FeatureGen.Audit;

{ Registry audit and the verify fingerprint (spec section 7): which entries are thin,
  unverified, stale, or describe a surface that changed since they were verified.
  Pure functions over the loaded registry and the live surface; the verify and audit
  verbs in FeatureGen.Commands do the I/O. }

interface

uses
  System.SysUtils
  , FeatureGen.Model
  , FeatureGen.Live
  ;

type
  /// <summary>One audit finding: an entry and the kind of gap it has.</summary>
  TAuditFinding = record
    Id: string;
    Owner: string;
    /// <summary>thin-leaf, no-usage, no-flags, no-steps, no-questions, no-access, stale-verified, surface-changed or no-wiki-page.</summary>
    Kind: string;
  end;

const
  /// <summary>An entry verified more than this many days before the audit date is reported stale-verified.</summary>
  AUDIT_STALE_DAYS = 90;
  /// <summary>An entry with no intro and a wiki body shorter than this many characters is reported thin-leaf.</summary>
  AUDIT_THIN_CHARS = 200;

/// <summary>The help block of one verb: its "  drag-lint verb ..." line(s) and their more deeply indented continuation lines.</summary>
/// <param name="pHelp">Loaded engine help; nil reads as no help.</param>
/// <param name="pVerb">Cli verb.</param>
/// <param name="pSub">Subcommand or ''; when no block starts with "verb sub" the verb's own block is used.</param>
/// <returns>Lines joined with LF, trailing blanks trimmed; '' when the help has no block for the verb.</returns>
function HelpBlock(const pHelp: TLiveHelp; const pVerb, pSub: string): string;

/// <summary>SHA-256 fingerprint of the live surface an entry describes.</summary>
/// <param name="pEntry">The entry; every surface contributes one text block, in surface order.</param>
/// <param name="pLive">The harvested live surface (captions, hosts, mcp tools); nil: only the static text counts.</param>
/// <param name="pHelp">Engine help, the source of cli blocks (see HelpBlock); nil: cli surfaces contribute only their declared verb.</param>
/// <returns>64 lowercase hex digits. cli: the verb's help block; ide-menu / ide-context / ide-about: the declared path
/// plus the harvested caption that matches its last segment ("&lt;absent&gt;" when none does); the other kinds: their
/// declared fields. Blocks are joined with LF.</returns>
/// <remarks>Changes when a verb's help text (flags included) or a harvested caption changes; does not change when only
/// prose of the entry changes. Not thread-safe.</remarks>
function SurfaceHash(const pEntry: TFeatureEntry; const pLive: TLiveSurface; const pHelp: TLiveHelp = nil): string;

/// <summary>Runs every audit rule over the registry.</summary>
/// <param name="pReg">Loaded registry; deprecated entries are skipped.</param>
/// <param name="pRepo">Repo root; wiki bodies are read from docs\wiki\&lt;WikiPage&gt;.md. A wikiPage listed in features\site-format.json generatedWikiPages counts as an empty body (the leaf has no Details section), so such an entry without an intro is thin-leaf.</param>
/// <param name="pLive">Live surface for surface-changed; nil: that kind is not reported.</param>
/// <param name="pHelp">Engine help for surface-changed (see SurfaceHash).</param>
/// <param name="pToday">The date stale-verified counts from.</param>
/// <returns>Findings ordered by entry id (ordinal), then in the order thin-leaf, no-usage, no-flags, no-steps, no-questions, no-access,
/// stale-verified, surface-changed, no-wiki-page. no-usage / no-flags concern cli surfaces; no-steps concerns ide-menu,
/// ide-context, ide-about and tool-window surfaces. surface-changed needs a stored verified.surfaceHash.</returns>
function AuditRegistry(const pReg: TRegistry; const pRepo: string; const pLive: TLiveSurface; const pHelp: TLiveHelp;
  pToday: TDateTime): TArray<TAuditFinding>;

implementation

uses
  System.IOUtils
  , System.Hash
  , System.DateUtils
  , System.RegularExpressions
  , System.Generics.Collections
  , FeatureGen.SiteFormat
  ;

function HelpBlock(const pHelp: TLiveHelp; const pVerb, pSub: string): string;
var
  lKey: string;
  lLines: TArray<string>;
  lRe: TRegEx;
  lSb: TStringBuilder;
  lIn: Boolean;
  lLine: string;
  lPass: Integer;
begin
  Result := '';
  if (pHelp = nil) or (pVerb = '') then
    Exit;
  lLines := pHelp.Lines;
  for lPass := 0 to 1 do
  begin
    if lPass = 0 then
    begin
      if pSub = '' then
        Continue;
      lKey := pVerb + ' ' + pSub;
    end
    else
      lKey := pVerb;
    lRe := TRegEx.Create('^ {2}drag-lint\s+' + TRegEx.Escape(lKey) + '(?=\s|$)');
    lSb := TStringBuilder.Create;
    try
      lIn := False;
      for lLine in lLines do
      begin
        if lRe.IsMatch(lLine) then
          lIn := True
        else if not (lLine.StartsWith('   ') and (Trim(lLine) <> '')) then
          lIn := False;
        if lIn then
          lSb.Append(TrimRight(lLine)).Append(#10);
      end;
      Result := TrimRight(lSb.ToString);
    finally
      lSb.Free;
    end;
    if Result <> '' then
      Exit;
  end;
end;

function LiveCaption(const pKey: string; const pCaptions: TArray<string>): string;
var
  lC: string;
begin
  for lC in pCaptions do
    if CaptionKey(lC) = pKey then
      Exit(lC);
  Result := '<absent>';
end;

function LastSegment(const pPath: string): string;
var
  lParts: TArray<string>;
begin
  lParts := pPath.Split(['>']);
  Result := Trim(lParts[High(lParts)]);
end;

function SurfaceText(const pS: TSurface; const pLive: TLiveSurface; const pHelp: TLiveHelp): string;
var
  lCaps: TArray<string>;
begin
  if pS.Kind = 'cli' then
    Result := 'cli:' + pS.Verb + ' ' + pS.Sub + #10 + HelpBlock(pHelp, pS.Verb, pS.Sub)
  else if pS.Kind = 'ide-menu' then
  begin
    Result := 'ide-menu:' + pS.Path;
    if pLive <> nil then
      Result := Result + #10 + LiveCaption(CaptionKey(LastSegment(pS.Path)), pLive.Captions);
  end
  else if pS.Kind = 'ide-context' then
  begin
    Result := 'ide-context:' + pS.Host + '|' + pS.Caption;
    if pLive <> nil then
    begin
      lCaps := nil;
      if pLive.ContextCaptions.ContainsKey(pS.Host) then
        lCaps := pLive.ContextCaptions[pS.Host];
      Result := Result + #10 + LiveCaption(CaptionKey(pS.Caption), lCaps);
    end;
  end
  else if pS.Kind = 'ide-about' then
  begin
    Result := 'ide-about:' + pS.Caption;
    if pLive <> nil then
      Result := Result + #10 + LiveCaption(CaptionKey(pS.Caption), pLive.AboutButtons + pLive.Captions);
  end
  else
    Result := pS.Kind + ':' + pS.Path + '|' + pS.Keys + '|' + pS.Name + '|' + pS.Method + '|' + pS.Tool + '|' + pS.Menu;
end;

function SurfaceHash(const pEntry: TFeatureEntry; const pLive: TLiveSurface; const pHelp: TLiveHelp): string;
var
  lS: TSurface;
  lSb: TStringBuilder;
begin
  lSb := TStringBuilder.Create;
  try
    for lS in pEntry.Surfaces do
      lSb.Append(SurfaceText(lS, pLive, pHelp)).Append(#10);
    Result := THashSHA2.GetHashString(lSb.ToString, SHA256);
  finally
    lSb.Free;
  end;
end;

function WikiBodyLength(const pEntry: TFeatureEntry; const pRepo: string; pHasFmt: Boolean; const pFmt: TSiteFormat): Integer;
var
  lFile: string;
begin
  Result := 0;
  if pEntry.WikiPage = '' then
    Exit;
  // a generated page (Features, Home, ...) is never the entry's own body: its leaf has no Details section
  if pHasFmt and IsGeneratedWikiPage(pFmt, pEntry.WikiPage) then
    Exit;
  lFile := TPath.Combine(pRepo, 'docs\wiki\' + pEntry.WikiPage + '.md');
  if TFile.Exists(lFile) then
    Result := Length(TFile.ReadAllText(lFile, TEncoding.UTF8));
end;

function VerifiedAgeDays(const pDate: string; pToday: TDateTime; out pAge: Integer): Boolean;  // dl:ok out-param-not-set@2908 -- REVIEWED 2026-10-19: set on the success path; every caller reads it only after a True result
var
  lM: TMatch;
  lD: TDateTime;
begin
  Result := False;
  lM := TRegEx.Match(pDate, '^(\d{4})-(\d{2})-(\d{2})$');
  if not lM.Success then
    Exit;
  if not TryEncodeDate(StrToInt(lM.Groups[1].Value), StrToInt(lM.Groups[2].Value), StrToInt(lM.Groups[3].Value), lD) then  // dl:ok magic-literal@ea38 -- REVIEWED 2026-10-19: a width, index or ASCII bound that is its own meaning at this spot; a named constant would only rename it
    Exit;
  pAge := DaysBetween(Trunc(pToday), lD);
  if lD > Trunc(pToday) then
    pAge := 0;
  Result := True;
end;

function AuditRegistry(const pReg: TRegistry; const pRepo: string; const pLive: TLiveSurface; const pHelp: TLiveHelp;
  pToday: TDateTime): TArray<TAuditFinding>;
var
  lList: TList<TAuditFinding>;
  lE: TFeatureEntry;
  lS: TSurface;
  lNoUsage, lNoFlags, lNoSteps, lHasIde: Boolean;
  lAge: Integer;
  lFmt: TSiteFormat;
  lHasFmt: Boolean;

  procedure Add(const pKind: string);
  var
    lF: TAuditFinding;
  begin
    lF.Id := lE.Id;
    lF.Owner := lE.Owner;
    lF.Kind := pKind;
    lList.Add(lF);
  end;

begin
  lList := TList<TAuditFinding>.Create;
  try
    lHasFmt := TFile.Exists(TPath.Combine(pRepo, 'features\site-format.json'));
    lFmt := Default(TSiteFormat);
    if lHasFmt then
      lFmt := LoadSiteFormat(pRepo);
    for lE in pReg.Entries do
    begin
      if lE.Status = 'deprecated' then
        Continue;
      lNoUsage := False;
      lNoFlags := False;
      lNoSteps := False;
      lHasIde := False;
      for lS in lE.Surfaces do
      begin
        if lS.Kind = 'cli' then
        begin
          lNoUsage := lNoUsage or (lS.Usage = '');
          lNoFlags := lNoFlags or (Length(lS.Flags) = 0);
        end
        else if (lS.Kind = 'ide-menu') or (lS.Kind = 'ide-context') or (lS.Kind = 'ide-about') or (lS.Kind = 'tool-window') then
        begin
          lHasIde := True;
          lNoSteps := lNoSteps or (Length(lS.Steps) = 0);
        end;
      end;
      if (lE.Intro = '') and (WikiBodyLength(lE, pRepo, lHasFmt, lFmt) < AUDIT_THIN_CHARS) then
        Add('thin-leaf');
      if lNoUsage then
        Add('no-usage');
      if lNoFlags then
        Add('no-flags');
      if lNoSteps then
        Add('no-steps');
      if Length(lE.Questions) = 0 then
        Add('no-questions');
      if (not lHasIde) and (lE.Access = '') and ((lE.Status = 'shipped') or (lE.Status = 'experimental')) then
        Add('no-access');
      if VerifiedAgeDays(lE.VerifiedDate, pToday, lAge) and (lAge > AUDIT_STALE_DAYS) then
        Add('stale-verified');
      if (pLive <> nil) and (lE.VerifiedSurfaceHash <> '') and (lE.VerifiedSurfaceHash <> SurfaceHash(lE, pLive, pHelp)) then
        Add('surface-changed');
      if (lE.WikiPage = '') or not TFile.Exists(TPath.Combine(pRepo, 'docs\wiki\' + lE.WikiPage + '.md')) then
        Add('no-wiki-page');
    end;
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

end.
