unit TlsVerificationDisabled;

interface

uses
  IdSSLOpenSSL, IdSSL, System.Net.HttpClient;

type
  TClient = class
    procedure OnVerifyPeer(Certificate: TObject; AOk: Boolean; ADepth, AError: Integer);
    function VerifyPeer(Certificate: TObject; AOk: Boolean; ADepth, AError: Integer): Boolean;
    procedure ValidateServerCertificate(const Sender: TObject; const ARequest: TObject;
      const Certificate: TObject; var Accepted: Boolean);
    procedure Setup(AIo: TIdSSLIOHandlerSocketOpenSSL);
  end;

implementation

procedure TClient.Setup(AIo: TIdSSLIOHandlerSocketOpenSSL);
begin
  AIo.SSLOptions.VerifyMode := [];
end;

function TClient.VerifyPeer(Certificate: TObject; AOk: Boolean; ADepth, AError: Integer): Boolean;
begin
  Result := True;
end;

procedure TClient.ValidateServerCertificate(const Sender: TObject; const ARequest: TObject;
  const Certificate: TObject; var Accepted: Boolean);
begin
  Accepted := True;
end;

procedure TClient.OnVerifyPeer(Certificate: TObject; AOk: Boolean; ADepth, AError: Integer);
var
  Flags: Cardinal;
begin
  Flags := SECURITY_FLAG_IGNORE_UNKNOWN_CA;
end;

end.
