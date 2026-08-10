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
/// <remarks>
/// <!-- drag-lint:auto BEGIN -->
/// Called from: DRagLint.CLI.DoWiring (DRagLint.CLI.pas), DRagLint.MCP.Server.TMCPServer.HandleToolsCall (DRagLint.MCP.Server.pas)
/// Calls: DRagLint.Core.Interfaces.ISymbolStore.FindDiResolveSites, DRagLint.Core.Interfaces.ISymbolStore.FindEventHandlersForForm, DRagLint.Core.Interfaces.ISymbolStore.FindImplementationsOf, DRagLint.Core.Interfaces.ISymbolStore.GetFilePath
/// Returns: TJSONObject.Create
/// Pure
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindDiResolveSites"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindEventHandlersForForm"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindImplementationsOf"/>
/// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.GetFilePath"/>
/// <!-- drag-lint:auto END -->
/// </remarks>
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
  try
    // Adopt the arrays into Result up front, and each JO into its array BEFORE
    // calling GetFilePath (a live DB query that can raise). That way any
    // mid-build exception leaves the whole tree owned by Result, which the
    // except clause frees -- no orphaned arrays/objects (review fix).
    JImpls := TJSONArray.Create;
    JSites := TJSONArray.Create;
    JHandlers := TJSONArray.Create;
    Result.AddPair('qname', AQName);
    Result.AddPair('implementations', JImpls);
    Result.AddPair('resolved_at', JSites);
    Result.AddPair('event_handlers', JHandlers);

    for B in Impls do
    begin
      JO := TJSONObject.Create;
      JImpls.AddElement(JO);
      JO.AddPair('impl', B.ImplName);
      JO.AddPair('lifetime', B.Lifetime);
      JO.AddPair('file', AStore.GetFilePath(B.FileId));
      JO.AddPair('line', TJSONNumber.Create(B.StartLine));
    end;
    for R in Sites do
    begin
      JO := TJSONObject.Create;
      JSites.AddElement(JO);
      JO.AddPair('file', AStore.GetFilePath(R.FileId));
      JO.AddPair('line', TJSONNumber.Create(R.StartLine));
    end;
    for R in Handlers do
    begin
      JO := TJSONObject.Create;
      JHandlers.AddElement(JO);
      JO.AddPair('handler', R.NameText);
      JO.AddPair('file', AStore.GetFilePath(R.FileId));
      JO.AddPair('line', TJSONNumber.Create(R.StartLine));
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
