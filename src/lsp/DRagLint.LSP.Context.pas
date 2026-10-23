unit DRagLint.LSP.Context;

{ The LSP feature registry: the seam every new LSP method plugs into.

  WHY IT EXISTS. Before S0 every method the server answered was one more
  `else if Method = '...'` in TLSPServer.Run and one more pair in
  HandleInitialize, all inside a 3,000-line unit. Each new method meant editing
  the same two hot spots of the same file, which is where parallel lanes collide.
  A feature unit now declares its methods and capabilities and registers itself
  from `initialization`; the server asks the registry and never names it.

  WHAT A FEATURE MAY TOUCH. Only ILspServerContext -- never TLSPServer -- so a
  feature unit does not use DRagLint.LSP.Server, and the server's private state
  (stores, the ephemeral index, the live-buffer overlay) stays behind one
  narrow, documented surface. }

interface

uses
  System.SysUtils
  , System.JSON
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  , DRagLint.Lint.Linter
  ;

type
  /// <summary>What a registered LSP feature may ask of the running server:
  /// URI/path mapping, the open symbol stores, the server's own position
  /// resolution and the replies it would send, and the reply channel.</summary>
  /// <remarks>
  /// <para>Lines and columns are 0-BASED everywhere on this interface (the LSP
  /// convention). The stores are 1-based; converting is the server's job.</para>
  /// <para>Every JSON value returned is NEW and owned by the caller; every JSON
  /// value passed to Reply / Notify is CONSUMED.</para>
  /// <para>Not thread-safe: call only from inside TLspFeature.Handle, which runs
  /// on the server's message loop.</para>
  /// </remarks>
  ILspServerContext = interface
    ['{6C2A0E51-3B7D-4F2A-9C1E-5D8B7A4F0E21}']
    /// <summary>Maps a `file:///` URI from the client to a local path.</summary>
    /// <param name="AUri">The URI as the client sent it.</param>
    /// <returns>The local path; '' for an empty URI.</returns>
    function FileFromUri(const AUri: string): string;
    /// <summary>Maps a local path to the `file:///` URI form the server
    /// answers with.</summary>
    /// <param name="APath">A local path.</param>
    /// <returns>The URI.</returns>
    function FileToUri(const APath: string): string;
    /// <summary>The configured --db stores in command-line order; for a
    /// position in a file use StoresForFile, which prepends that file's own
    /// ephemeral index.</summary>
    /// <returns>A copy of the store list; may be empty. Never contains a loose
    /// file's cached index, whatever was hovered before.</returns>
    function Stores: TArray<ISymbolStore>;
    /// <summary>The stores to consult for a position in APath: the configured
    /// stores, with an ephemeral index of APath prepended when no configured
    /// store owns that file.</summary>
    /// <param name="APath">The local path of the document.</param>
    /// <returns>The store list, in lookup order.</returns>
    function StoresForFile(const APath: string): TArray<ISymbolStore>;
    /// <summary>The identifier under a position, read from the live buffer
    /// when the editor sent one, else from disk.</summary>
    /// <param name="APath">The local path.</param>
    /// <param name="ALine0">0-based line.</param>
    /// <param name="ACol0">0-based column.</param>
    /// <returns>The identifier text; '' when the cursor is not on one.</returns>
    function IdentifierAtPosition(const APath: string; ALine0, ACol0: Integer): string;
    /// <summary>The single symbol a position refers to: IdentifierAtPosition,
    /// an exact-name lookup across StoresForFile, declaration/implementation
    /// matching, TTypeAtResolver narrowing at a call site, and
    /// DedupAndPreferSource when nothing narrowed.</summary>
    /// <param name="APath">The local path.</param>
    /// <param name="ALine0">0-based line.</param>
    /// <param name="ACol0">0-based column.</param>
    /// <param name="ASym">Receives the symbol; valid only on True.</param>
    /// <param name="AStore">Receives the store ASym belongs to; valid only on
    /// True. Further queries about ASym must go to THIS store.</param>
    /// <returns>False when nothing resolves (no identifier, a compiler
    /// intrinsic, no indexed symbol, or only the inherited-member owner-type
    /// floor).</returns>
    function ResolveSymbolAt(const APath: string; ALine0, ACol0: Integer; out ASym: TSymbol; out AStore: ISymbolStore): Boolean;
    /// <summary>The body `textDocument/definition` answers for a position.</summary>
    /// <param name="APath">The local path.</param>
    /// <param name="ALine0">0-based line.</param>
    /// <param name="ACol0">0-based column.</param>
    /// <returns>A new Location[] array, possibly empty; the caller owns it.</returns>
    function Definition(const APath: string; ALine0, ACol0: Integer): TJSONArray;
    /// <summary>The body `textDocument/references` answers for a position.</summary>
    /// <param name="APath">The local path.</param>
    /// <param name="ALine0">0-based line.</param>
    /// <param name="ACol0">0-based column.</param>
    /// <param name="AIncludeDecl">Also list the declarations of the name.</param>
    /// <returns>A new Location[] array, possibly empty; the caller owns it.</returns>
    function References(const APath: string; ALine0, ACol0: Integer; AIncludeDecl: Boolean): TJSONArray;
    /// <summary>The `counts` array `draglint/callerCounts` answers for a file.</summary>
    /// <param name="APath">The local path.</param>
    /// <returns>A new array of {line, count} with 0-based lines; empty for a
    /// file no store knows. The caller owns it.</returns>
    function CallerCounts(const APath: string): TJSONArray;
    /// <summary>The markdown `textDocument/hover` shows for a position.</summary>
    /// <param name="APath">The local path.</param>
    /// <param name="ALine0">0-based line.</param>
    /// <param name="ACol0">0-based column.</param>
    /// <returns>The markdown; '' when hover would answer null.</returns>
    function HoverMarkdown(const APath: string; ALine0, ACol0: Integer): string;
    /// <summary>The server's linter, created on first use.</summary>
    /// <returns>The shared TLinter; owned by the server, never free it.</returns>
    function Linter: TLinter;
    /// <summary>Sends {jsonrpc, id, result}.</summary>
    /// <param name="AId">The request id (cloned; nil omits the id pair, the
    /// shape the built-in handlers have always sent).</param>
    /// <param name="AResult">The result value; CONSUMED, even on failure.
    /// nil sends result null.</param>
    procedure Reply(const AId: TJSONValue; AResult: TJSONValue);
    /// <summary>Sends {jsonrpc, id, error:{code, message}}.</summary>
    /// <param name="AId">The request id (cloned; nil sends id null).</param>
    /// <param name="ACode">The JSON-RPC error code, e.g. -32602.</param>
    /// <param name="AMessage">Human-readable message.</param>
    procedure ReplyError(const AId: TJSONValue; ACode: Integer; const AMessage: string);
    /// <summary>Sends a notification {jsonrpc, method, params}.</summary>
    /// <param name="AMethod">The notification method.</param>
    /// <param name="AParams">The params object; CONSUMED. nil omits params.</param>
    procedure Notify(const AMethod: string; AParams: TJSONObject);
  end;

  /// <summary>Base class of one LSP feature: the methods it answers, the
  /// capabilities it advertises, and its handler.</summary>
  /// <remarks>
  /// <para>A feature unit declares a descendant and calls RegisterLspFeature
  /// from its `initialization`; DRagLint.LSP.Features lists every feature
  /// unit so the registrations happen. The server creates ONE instance per
  /// registered class for its lifetime and owns it.</para>
  /// <para>Built-in methods answered directly by TLSPServer.Run win over the
  /// table; a feature cannot shadow one. Two features claiming one method:
  /// the first registered keeps it.</para>
  /// </remarks>
  TLspFeature = class abstract
  public
    /// <summary>Creates the feature. Virtual so the server's
    /// `TLspFeatureClass.Create` reaches a descendant's own constructor.</summary>
    constructor Create; virtual;
    /// <summary>The JSON-RPC methods this feature answers.</summary>
    /// <returns>Method names, e.g. ['textDocument/documentSymbol'].</returns>
    class function Methods: TArray<string>; virtual; abstract;
    /// <summary>Adds this feature's pairs to initialize.result.capabilities.</summary>
    /// <param name="ACaps">The capabilities object being built; add pairs,
    /// never free it. A pair named like an existing one is added anyway, so
    /// a feature must only use names nothing else uses.</param>
    class procedure AddCapabilities(ACaps: TJSONObject); virtual; abstract;
    /// <summary>Answers one request or notification.</summary>
    /// <param name="ACtx">The server surface; valid for this call only.</param>
    /// <param name="AMethod">The method, one of Methods.</param>
    /// <param name="AId">The request id; nil for a notification (send nothing).</param>
    /// <param name="AParams">The params object; nil when absent or not an
    /// object. Owned by the server; do not keep it.</param>
    procedure Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject); virtual; abstract;
  end;

  /// <summary>A registered feature class.</summary>
  TLspFeatureClass = class of TLspFeature;

/// <summary>Registers a feature class; call from the feature unit's
/// `initialization`.</summary>
/// <param name="AClass">The class; registering the same class twice is a no-op.</param>
procedure RegisterLspFeature(AClass: TLspFeatureClass);

/// <summary>Every registered feature class, in registration order.</summary>
/// <returns>A copy of the registry.</returns>
function RegisteredLspFeatures: TArray<TLspFeatureClass>;

implementation

var
  GFeatures: TArray<TLspFeatureClass>;

constructor TLspFeature.Create;
begin
  inherited Create;
end;

procedure RegisterLspFeature(AClass: TLspFeatureClass);
begin
  if AClass = nil then Exit;
  for var C: TLspFeatureClass in GFeatures do
    if C = AClass then Exit;
  GFeatures:= GFeatures + [AClass];
end;

function RegisteredLspFeatures: TArray<TLspFeatureClass>;
begin
  Result:= Copy(GFeatures);
end;

end.
