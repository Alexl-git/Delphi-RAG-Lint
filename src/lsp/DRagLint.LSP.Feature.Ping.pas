unit DRagLint.LSP.Feature.Ping;

{ `draglint/ping` -- the feature registry's positive control. It does nothing
  useful on purpose: it is the one method that can ONLY be answered through
  the registry, so a client (and run_lsp_feature_registry_guard.ps1) can tell
  "the registry is wired" from "the server happens to answer". }

interface

uses
  System.JSON
  , DRagLint.LSP.Context
  ;

type
  /// <summary>Answers `draglint/ping` with {pong: true, version} and
  /// advertises capabilities.draglint.ping = true.</summary>
  /// <remarks>Stateless; registered from this unit's initialization.</remarks>
  TPingFeature = class(TLspFeature)
  public
    /// <summary>The one method: `draglint/ping`.</summary>
    /// <returns>['draglint/ping'].</returns>
    class function Methods: TArray<string>; override;
    /// <summary>Adds or extends the vendor `draglint` capability object with
    /// `ping: true`.</summary>
    /// <param name="ACaps">initialize.result.capabilities under construction.</param>
    class procedure AddCapabilities(ACaps: TJSONObject); override;
    /// <summary>Replies {pong: true, version: DRAGLINT_VERSION}.</summary>
    /// <param name="ACtx">The server surface.</param>
    /// <param name="AMethod">Always `draglint/ping`.</param>
    /// <param name="AId">The request id; a notification gets no reply.</param>
    /// <param name="AParams">Ignored.</param>
    procedure Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject); override;
  end;

implementation

uses
  DRagLint.Core.Model
  ;

const
  PING_METHOD = 'draglint/ping';
  VENDOR_CAPS = 'draglint';

class function TPingFeature.Methods: TArray<string>;
begin
  Result:= [PING_METHOD];
end;

class procedure TPingFeature.AddCapabilities(ACaps: TJSONObject);
begin
  { One shared vendor object: later features add their own flags to it rather
    than each claiming a top-level capability name. }
  var Vendor: TJSONObject:= ACaps.GetValue(VENDOR_CAPS) as TJSONObject;
  if Vendor = nil then
  begin
    Vendor:= TJSONObject.Create;
    ACaps.AddPair(VENDOR_CAPS, Vendor);
  end;
  Vendor.AddPair('ping', TJSONBool.Create(True));
end;

procedure TPingFeature.Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject);
begin
  if AId = nil then Exit;
  var Res: TJSONObject:= TJSONObject.Create;
  Res.AddPair('pong'   , TJSONBool.Create(True));
  Res.AddPair('version', DRAGLINT_VERSION      );
  ACtx.Reply(AId, Res);
end;

initialization
  RegisterLspFeature(TPingFeature);

end.
