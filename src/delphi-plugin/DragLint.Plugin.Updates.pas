{ Update checking for the About dialog: what version is installed, what version
  GitHub has, and whether that is newer.

  DELIBERATELY FREE OF ToolsAPI, and of the dialog. Everything here is either
  pure arithmetic on version text or a self-contained Windows/HTTP call, so the
  deciding half is checkable by a console program (tests\UpdateCheckTests.dpr)
  while only the presenting half needs a running IDE. The split is the same one
  DragLint.Plugin.FanOutState makes, for the same reason: a person looking at a
  dialog can see that it said something, and cannot see that what it said was
  computed wrongly.

  THE COMPARISON IS NUMERIC, FIELD BY FIELD (AA.BB.CC.DD), and that is not
  pedantry. drag-lint's local build is 1.10.1-alpha and its newest published
  release is v1.4.0-alpha: a TEXT compare puts '1.10.1' BELOW '1.4.0' and would
  send the user to download an older release than the one they are running.
  That is the first thing a real click would have hit.

  THE TWO REPOS DO NOT AGREE ON TAG SHAPE, so nothing may assume one:
    Alexl-git/YADF            tags  '1.0.17.0'      four fields, no prefix
    Alexl-git/Delphi-RAG-Lint tags  'v1.4.0-alpha'  'v' prefix, three fields,
                                                    prerelease suffix
  NormalizeVersionText is the one place that reconciles them.

  A FAILED CHECK IS NOT AN ANSWER. Offline, rate-limited, renamed repo, proxy
  -- every one of those must render as UNKNOWN, never as "up to date", because
  "up to date" is the single outcome a user will not re-check. }
unit DragLint.Plugin.Updates;

interface

uses
  System.SysUtils, System.Classes;

type
  /// <summary>One product the About dialog reports on and can check.</summary>
  TDLComponentInfo = record
    /// <summary>Shown in the dialog, e.g. 'YADF'.</summary>
    DisplayName : string;
    /// <summary>GitHub 'owner/name', e.g. 'Alexl-git/YADF'.</summary>
    Repo        : string;
    /// <summary>Human page listing releases.</summary>
    ReleasesUrl : string;
    /// <summary>Raw/blob URL of the published CHANGELOG.md.</summary>
    ChangelogUrl: string;
  end;

const
  /// <summary>Everything the About dialog offers to check. Both repos are
  /// public and both already publish a CHANGELOG.md.</summary>
  DLUpdateComponents: array[0..1] of TDLComponentInfo = (
    (DisplayName : 'drag-lint';
     Repo        : 'Alexl-git/Delphi-RAG-Lint';
     ReleasesUrl : 'https://github.com/Alexl-git/Delphi-RAG-Lint/releases';
     ChangelogUrl: 'https://github.com/Alexl-git/Delphi-RAG-Lint/blob/main/CHANGELOG.md'),
    (DisplayName : 'YADF';
     Repo        : 'Alexl-git/YADF';
     ReleasesUrl : 'https://github.com/Alexl-git/YADF/releases';
     ChangelogUrl: 'https://github.com/Alexl-git/YADF/blob/main/CHANGELOG.md')
  );

/// <summary>Reduce a release tag or file version to a bare 'AA.BB.CC.DD'.
/// Strips a leading 'v'/'V', drops any '-prerelease' or '+build' tail, and
/// pads missing fields with 0.</summary>
/// <returns>'' when the text contains no leading number at all -- an EMPTY
/// result means UNKNOWN and must never be treated as 0.0.0.0.</returns>
function NormalizeVersionText(const AText: string): string;

/// <summary>Compare two versions field by field, numerically.</summary>
/// <returns>&gt;0 if A is newer, 0 if equal, &lt;0 if A is older. Unparseable
/// input on either side yields 0; callers must test parseability separately
/// rather than reading 0 as "same".</returns>
function CompareVersions(const A, B: string): Integer;

/// <summary>Should the user be told about ARemoteTag?</summary>
/// <param name="AReason">Always set: 'update available', 'up to date',
/// 'local build is ahead of the latest release', or 'unknown'.</param>
/// <returns>True ONLY when both versions parse and the remote is strictly
/// newer. Anything unknown is False with an 'unknown' reason -- never a
/// silent "up to date".</returns>
function IsUpdateAvailable(const ARemoteTag, ALocalVersion: string;
  out AReason: string): Boolean;

/// <summary>The Windows file-version resource of APath as 'AA.BB.CC.DD'.</summary>
/// <returns>'' if the file is missing or carries no version resource.</returns>
function FileVersionOf(const APath: string): string;

/// <summary>Full path of a registered design-time package whose file name
/// contains ANameFragment, read from the IDE's Known Packages.</summary>
/// <returns>'' when no registered package matches.</returns>
function FindKnownPackagePath(const ANameFragment: string): string;

/// <summary>Latest release tag of ARepo from the GitHub API.</summary>
/// <param name="ATimeoutMs">Applied to both connect and response. The caller
/// is a modal dialog, so this must never be unbounded.</param>
/// <param name="AError">'' on success; otherwise why it failed.</param>
/// <returns>The tag, or '' -- and '' with AError set is UNKNOWN, not
/// up to date.</returns>
function FetchLatestReleaseTag(const ARepo: string; ATimeoutMs: Integer;
  out AError: string): string;

implementation

uses
  Winapi.Windows, System.Win.Registry, System.Net.HttpClient,
  System.Net.URLClient, System.JSON, System.Math, System.StrUtils;

function NormalizeVersionText(const AText: string): string;
var
  S     : string ;
  I, P  : Integer;
  Parts : TArray<string>;
  Nums  : array[0..3] of Integer;
  Digits: string;
begin
  Result:= '';
  S:= Trim(AText);
  if S = '' then Exit;
  { 'v1.4.0-alpha' -> '1.4.0-alpha' }
  if (S <> '') and CharInSet(S[1], ['v', 'V']) then Delete(S, 1, 1);
  { drop a '-prerelease' or '+build' tail }
  P:= S.IndexOfAny(['-', '+']);
  if P >= 0 then S:= Copy(S, 1, P);
  S:= Trim(S);
  if S = '' then Exit;

  for I:= 0 to 3 do Nums[I]:= 0;
  Parts:= S.Split(['.']);
  if Length(Parts) = 0 then Exit;

  { The FIRST field must be a number, or this is not a version at all. Without
    this gate 'not-a-release' would normalise to '0.0.0.0' and compare equal to
    every other unknown -- which is exactly how a broken check starts reporting
    "up to date" forever. }
  Digits:= Trim(Parts[0]);
  if (Digits = '') or not CharInSet(Digits[1], ['0'..'9']) then Exit;

  for I:= 0 to Min(3, High(Parts)) do
  begin
    Digits:= Trim(Parts[I]);
    Nums[I]:= StrToIntDef(Digits, 0);
  end;
  Result:= Format('%d.%d.%d.%d', [Nums[0], Nums[1], Nums[2], Nums[3]]);
end;

function SplitNums(const ANormalized: string): TArray<Integer>;
var
  Parts: TArray<string>;
  I    : Integer;
begin
  SetLength(Result, 4);
  for I:= 0 to 3 do Result[I]:= 0;
  if ANormalized = '' then Exit;
  Parts:= ANormalized.Split(['.']);
  for I:= 0 to Min(3, High(Parts)) do Result[I]:= StrToIntDef(Parts[I], 0);
end;

function CompareVersions(const A, B: string): Integer;
var
  NA, NB: string;
  VA, VB: TArray<Integer>;
  I     : Integer;
begin
  Result:= 0;
  NA:= NormalizeVersionText(A);
  NB:= NormalizeVersionText(B);
  if (NA = '') or (NB = '') then Exit;
  VA:= SplitNums(NA);
  VB:= SplitNums(NB);
  for I:= 0 to 3 do
    if VA[I] <> VB[I] then
      Exit(VA[I] - VB[I]);
end;

function IsUpdateAvailable(const ARemoteTag, ALocalVersion: string;
  out AReason: string): Boolean;
var
  NR, NL: string;
  C     : Integer;
begin
  Result:= False;
  NR:= NormalizeVersionText(ARemoteTag);
  NL:= NormalizeVersionText(ALocalVersion);

  { UNKNOWN IS ITS OWN OUTCOME. Collapsing it into "up to date" is the one
    failure a user never re-checks, so it is spelled out on both sides. }
  if NR = '' then
  begin
    AReason:= 'unknown -- could not read the published version';
    Exit;
  end;
  if NL = '' then
  begin
    AReason:= 'unknown -- could not read the installed version';
    Exit;
  end;

  C:= CompareVersions(NR, NL);
  if C > 0 then
  begin
    AReason:= Format('update available: %s -> %s', [NL, NR]);
    Result := True;
  end
  else if C = 0 then
    AReason:= Format('up to date (%s)', [NL])
  else
    { Live case: drag-lint builds 1.10.1-alpha while its newest release is
      v1.4.0-alpha. Saying "up to date" here would be a lie of a different
      kind, so it says which way round it is. }
    AReason:= Format('local build is ahead of the latest release (%s > %s)', [NL, NR]);
end;

function FileVersionOf(const APath: string): string;
var
  Size, Handle: DWORD  ;
  Buf         : TBytes ;
  FI          : PVSFixedFileInfo;
  Len         : UINT   ;
begin
  Result:= '';
  if (APath = '') or not FileExists(APath) then Exit;
  Handle:= 0;
  Size  := GetFileVersionInfoSize(PChar(APath), Handle);
  if Size = 0 then Exit;
  SetLength(Buf, Size);
  if not GetFileVersionInfo(PChar(APath), Handle, Size, Pointer(Buf)) then Exit;
  FI:= nil;
  Len:= 0;
  if not VerQueryValue(Pointer(Buf), '\', Pointer(FI), Len) then Exit;
  if (FI = nil) or (Len = 0) then Exit;
  Result:= Format('%d.%d.%d.%d',
    [HiWord(FI.dwFileVersionMS), LoWord(FI.dwFileVersionMS),
     HiWord(FI.dwFileVersionLS), LoWord(FI.dwFileVersionLS)]);
end;

function FindKnownPackagePath(const ANameFragment: string): string;
const
  { The IDE's own list of design-time packages. Reading it rather than guessing
    a path is what makes this report the package actually LOADED, not one that
    happens to sit in a build folder. }
  KNOWN_PACKAGES = '\Software\Embarcadero\BDS\37.0\Known Packages';
var
  Reg  : TRegistry;
  Names: TStringList;
  S    : string   ;
begin
  Result:= '';
  if ANameFragment = '' then Exit;
  Reg:= TRegistry.Create(KEY_READ);
  try
    Reg.RootKey:= HKEY_CURRENT_USER;
    if not Reg.OpenKeyReadOnly(KNOWN_PACKAGES) then Exit;
    Names:= TStringList.Create;
    try
      Reg.GetValueNames(Names);
      for S in Names do
        if ContainsText(ExtractFileName(S), ANameFragment) then
          Exit(S);
    finally
      Names.Free;
    end;
  finally
    Reg.Free;
  end;
end;

function FetchLatestReleaseTag(const ARepo: string; ATimeoutMs: Integer;
  out AError: string): string;
var
  Http: THTTPClient;
  Resp: IHTTPResponse;
  Body: string      ;
  Obj : TJSONObject ;
begin
  Result:= '';
  AError:= '';
  if ARepo = '' then begin AError:= 'no repository configured'; Exit; end;
  try
    Http:= THTTPClient.Create;
    try
      { A modal dialog is waiting on this. Both timeouts are set because a
        connect that never completes and a response that never arrives are
        different stalls and only one of them is covered by either setting. }
      Http.ConnectionTimeout := ATimeoutMs;
      Http.ResponseTimeout   := ATimeoutMs;
      { GitHub rejects requests with no User-Agent. }
      Http.UserAgent         := 'drag-lint-ide-plugin';
      Http.CustomHeaders['Accept']:= 'application/vnd.github+json';

      Resp:= Http.Get('https://api.github.com/repos/' + ARepo + '/releases/latest');
      if Resp = nil then begin AError:= 'no response'; Exit; end;
      if Resp.StatusCode <> 200 then
      begin
        { 404 = no releases yet or renamed repo; 403 = rate limited. Both are
          UNKNOWN, and the status code is kept so the reason is diagnosable
          rather than just "failed". }
        AError:= Format('HTTP %d', [Resp.StatusCode]);
        Exit;
      end;
      Body:= Resp.ContentAsString(TEncoding.UTF8);
    finally
      Http.Free;
    end;

    Obj:= TJSONObject.ParseJSONValue(Body) as TJSONObject;
    if Obj = nil then begin AError:= 'unreadable response'; Exit; end;
    try
      Result:= Obj.GetValue<string>('tag_name', '');
      if Result = '' then AError:= 'no tag_name in the response';
    finally
      Obj.Free;
    end;
  except
    on E: Exception do
    begin
      { Offline is the ordinary case, not an exceptional one: it must leave a
        reason and an empty tag, which the caller renders as UNKNOWN. }
      AError:= E.Message;
      Result:= '';
    end;
  end;
end;

end.
