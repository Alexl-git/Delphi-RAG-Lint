unit FeatureGen.SiteFormat;

{ The website format config: features\site-format.json. Every value of spec
  5.2 that WWW may still change lives there, not in code. }

interface

uses
  System.SysUtils
  , FeatureGen.Live
  ;

type
  /// <summary>Parsed features\site-format.json.</summary>
  /// <remarks>Help is set by the caller and is NOT owned; nil means usage falls back to "drag-lint verb".</remarks>
  TSiteFormat = record
    /// <summary>Website root, repo-relative.</summary>
    Root: string;
    Product: string;
    /// <summary>Front matter keys in output order.</summary>
    FrontMatterKeys: TArray<string>;
    IncludeStatuses: TArray<string>;
    ExcludeAudiences: TArray<string>;
    FenceDefaultLang: string;
    /// <summary>Opening Markdown sentence of index.md.</summary>
    MicroniteIndex: string;
    /// <summary>Opening Markdown sentence of whats-new.md.</summary>
    MicroniteWhatsNew: string;
    ImageDir: string;
    /// <summary>Repo-relative engine exe path.</summary>
    Engine: string;
    /// <summary>Repo-relative path of the docs-sync guard that lists $UndocumentedOnPurpose.</summary>
    UndocumentedSource: string;
    Help: TLiveHelp;
  end;

/// <summary>Reads features\site-format.json.</summary>
/// <param name="pRepo">Repo root holding features\.</param>
/// <returns>The format; Help is nil.</returns>
/// <exception cref="EFeatureJson">The file is missing or malformed.</exception>
function LoadSiteFormat(const pRepo: string): TSiteFormat;

/// <summary>True when an entry belongs on the site.</summary>
/// <param name="pFmt">Format holding the include/exclude lists.</param>
/// <param name="pStatus">Entry status.</param>
/// <param name="pAudience">Entry audience ('' when absent).</param>
/// <returns>Status is in IncludeStatuses and audience is not in ExcludeAudiences.</returns>
function SiteIncludes(const pFmt: TSiteFormat; const pStatus, pAudience: string): Boolean;

implementation

uses
  System.IOUtils
  , System.JSON
  , FeatureGen.Json
  ;

function Strs(pObj: TJSONValue; const pName: string): TArray<string>;
var
  lV: TJSONValue;
  i: Integer;
begin
  SetLength(Result, 0);
  if pObj is not TJSONObject then
    Exit;
  lV := TJSONObject(pObj).GetValue(pName);
  if lV is not TJSONArray then
    Exit;
  SetLength(Result, TJSONArray(lV).Count);
  for i := 0 to High(Result) do
    Result[i] := TJSONArray(lV).Items[i].Value;
end;

function LoadSiteFormat(const pRepo: string): TSiteFormat;
var
  lRoot, lMic: TJSONValue;
begin
  Result := Default(TSiteFormat);
  lRoot := ReadJsonFile(TPath.Combine(pRepo, 'features\site-format.json'));
  try
    Result.Root := Prop(lRoot, 'root');
    Result.Product := Prop(lRoot, 'product');
    Result.FrontMatterKeys := Strs(lRoot, 'frontMatterKeys');
    Result.IncludeStatuses := Strs(lRoot, 'includeStatuses');
    Result.ExcludeAudiences := Strs(lRoot, 'excludeAudiences');
    Result.FenceDefaultLang := Prop(lRoot, 'fenceDefaultLang');
    lMic := nil;
    if lRoot is TJSONObject then
      lMic := TJSONObject(lRoot).GetValue('micronite');
    Result.MicroniteIndex := Prop(lMic, 'index');
    Result.MicroniteWhatsNew := Prop(lMic, 'whatsNew');
    Result.ImageDir := Prop(lRoot, 'imageDir');
    Result.Engine := Prop(lRoot, 'engine');
    Result.UndocumentedSource := Prop(lRoot, 'undocumentedSource');
  finally
    lRoot.Free;
  end;
end;

function SiteIncludes(const pFmt: TSiteFormat; const pStatus, pAudience: string): Boolean;
var
  lS: string;
begin
  Result := False;
  for lS in pFmt.IncludeStatuses do
    if lS = pStatus then
      Result := True;
  for lS in pFmt.ExcludeAudiences do
    if lS = pAudience then
      Result := False;
end;

end.
