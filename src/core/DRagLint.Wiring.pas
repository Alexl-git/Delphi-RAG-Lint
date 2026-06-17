unit DRagLint.Wiring;

/// <summary>
///   Shared builder for the "wiring" view (Spring4D DI + DFM event edges), used by
///   BOTH the CLI `wiring` command and the MCP `get_wiring` tool so the two
///   surfaces always return identical data.
/// </summary>
interface

uses
  System.JSON,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces;

/// <summary>Builds the wiring JSON object for a qualified name: DI
/// implementations (+lifetime), DI resolve-sites, and DFM event handlers.</summary>
/// <param name="AQName">Interface name (DI) or form/class name (DFM handlers).</param>
/// <param name="AStore">Open symbol store to query.</param>
/// <returns>A new TJSONObject { qname, implementations[], resolved_at[],
/// event_handlers[] }. The caller owns and must free it.</returns>
function BuildWiringJson(const AQName: string;
  const AStore: ISymbolStore): TJSONObject;

implementation

function BuildWiringJson(const AQName: string;
  const AStore: ISymbolStore): TJSONObject;
var
  Impls: TArray<TDiBindingRow>;
  Sites, Handlers: TArray<TReference>;
  B: TDiBindingRow;
  R: TReference;
  JImpls, JSites, JHandlers: TJSONArray;
  JO: TJSONObject;
begin
  Impls := AStore.FindImplementationsOf(AQName);
  Sites := AStore.FindDiResolveSites(AQName);
  Handlers := AStore.FindEventHandlersForForm(AQName);

  Result := TJSONObject.Create;
  JImpls := TJSONArray.Create;
  JSites := TJSONArray.Create;
  JHandlers := TJSONArray.Create;

  Result.AddPair('qname', AQName);
  for B in Impls do
  begin
    JO := TJSONObject.Create;
    JO.AddPair('impl', B.ImplName);
    JO.AddPair('lifetime', B.Lifetime);
    JO.AddPair('file', AStore.GetFilePath(B.FileId));
    JO.AddPair('line', TJSONNumber.Create(B.StartLine));
    JImpls.AddElement(JO);
  end;
  for R in Sites do
  begin
    JO := TJSONObject.Create;
    JO.AddPair('file', AStore.GetFilePath(R.FileId));
    JO.AddPair('line', TJSONNumber.Create(R.StartLine));
    JSites.AddElement(JO);
  end;
  for R in Handlers do
  begin
    JO := TJSONObject.Create;
    JO.AddPair('handler', R.NameText);
    JO.AddPair('file', AStore.GetFilePath(R.FileId));
    JO.AddPair('line', TJSONNumber.Create(R.StartLine));
    JHandlers.AddElement(JO);
  end;
  Result.AddPair('implementations', JImpls);
  Result.AddPair('resolved_at', JSites);
  Result.AddPair('event_handlers', JHandlers);
end;

end.
