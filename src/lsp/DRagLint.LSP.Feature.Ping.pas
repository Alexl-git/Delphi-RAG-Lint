unit DRagLint.LSP.Feature.Ping;

{ `draglint/ping` -- the feature registry's positive control. It does nothing
  useful on purpose: it is the one method that can ONLY be answered through
  the registry, so a client (and run_lsp_feature_registry_guard.ps1) can tell
  "the registry is wired" from "the server happens to answer". }

interface

uses
  System.SysUtils
  , System.JSON
  , DRagLint.LSP.Context
  ;

type
  /// <summary>Raised by the test-only `draglint/testRaise` feature.</summary>
  ETestRaise = class(Exception);

  /// <summary>Answers `draglint/ping` with {pong: true, version, stores} and
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
    /// <summary>Replies {pong: true, version: DRAGLINT_VERSION, stores: N},
    /// N being Length(ACtx.Stores): the configured --db stores only, never a
    /// loose file's cached index (the guard pins that through this field).</summary>
    /// <param name="ACtx">The server surface.</param>
    /// <param name="AMethod">Always `draglint/ping`.</param>
    /// <param name="AId">The request id; a notification gets no reply.</param>
    /// <param name="AParams">Ignored.</param>
    procedure Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject); override;
  end;

  /// <summary>TEST-ONLY feature: `draglint/testRaise` always raises, so the
  /// guard can prove the server's feature dispatch isolates an exception (S8).</summary>
  /// <remarks>Registered from this unit's initialization ONLY when the
  /// environment variable DRAGLINT_LSP_TEST_RAISE is non-empty; in production
  /// the method does not exist and answers -32601. Advertises nothing.</remarks>
  TLspTestRaiseFeature = class(TLspFeature)
  public
    /// <summary>The one method: `draglint/testRaise`.</summary>
    /// <returns>['draglint/testRaise'].</returns>
    class function Methods: TArray<string>; override;
    /// <summary>Adds nothing: a test hook is never advertised.</summary>
    /// <param name="ACaps">initialize.result.capabilities under construction; untouched.</param>
    class procedure AddCapabilities(ACaps: TJSONObject); override;
    /// <summary>Raises ETestRaise('draglint/testRaise: deliberate test failure').</summary>
    /// <param name="ACtx">The server surface; unused.</param>
    /// <param name="AMethod">Always `draglint/testRaise`.</param>
    /// <param name="AId">The request id; unused.</param>
    /// <param name="AParams">Ignored.</param>
    /// <exception cref="ETestRaise">Always.</exception>
    procedure Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject); override;
  end;

implementation

uses
  DRagLint.Core.Model  // dl:unit DRagLint.Core.Model accepted -- only DRAGLINT_VERSION: ping echoes the product version
  ;

const
  PING_METHOD = 'draglint/ping';
  VENDOR_CAPS = 'draglint';
  TESTRAISE_METHOD = 'draglint/testRaise';
  TESTRAISE_ENV    = 'DRAGLINT_LSP_TEST_RAISE';

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
  Res.AddPair('stores' , TJSONNumber.Create(Length(ACtx.Stores)));
  ACtx.Reply(AId, Res);
end;

class function TLspTestRaiseFeature.Methods: TArray<string>;
begin
  Result:= [TESTRAISE_METHOD];
end;

class procedure TLspTestRaiseFeature.AddCapabilities(ACaps: TJSONObject);
begin
  // a test hook is never advertised
end;

procedure TLspTestRaiseFeature.Handle(const ACtx: ILspServerContext; const AMethod: string; const AId: TJSONValue; const AParams: TJSONObject);
begin
  raise ETestRaise.Create('draglint/testRaise: deliberate test failure');
end;

initialization
  RegisterLspFeature(TPingFeature);
  if GetEnvironmentVariable(TESTRAISE_ENV) <> '' then RegisterLspFeature(TLspTestRaiseFeature);

end.
