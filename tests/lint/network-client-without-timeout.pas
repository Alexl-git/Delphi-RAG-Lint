unit NetworkClientWithoutTimeout;

interface

uses
  System.SysUtils, IdHTTP, IdTCPClient, System.Net.HttpClient;

type
  TFetcher = class
  private
    FHttp: TIdHTTP;
    FTcp: TIdTCPClient;
  public
    constructor Create;
    procedure Fetch;
  end;

implementation

procedure NoTimeout;
var
  H: TIdHTTP;
begin
  H:= TIdHTTP.Create(nil);
  try
    H.Get('http://example.com');
  finally
    H.Free;
  end;
end;

procedure WithTimeout;
var
  H: TIdHTTP;
begin
  H:= TIdHTTP.Create(nil);
  try
    H.ReadTimeout:= 5000;
    H.ConnectTimeout:= 5000;
    H.Get('http://example.com');
  finally
    H.Free;
  end;
end;

procedure NetClientNoTimeout;
var
  C: THTTPClient;
begin
  C:= THTTPClient.Create;
  try
    C.Get('http://example.com');
  finally
    C.Free;
  end;
end;

procedure NetClientTimeout;
var
  C: THTTPClient;
begin
  C:= THTTPClient.Create;
  try
    C.ConnectionTimeout:= 3000;
    C.ResponseTimeout:= 3000;
    C.Get('http://example.com');
  finally
    C.Free;
  end;
end;

procedure NotCreatedHere(AClient: TIdHTTP);
var
  H: TIdHTTP;
begin
  H:= AClient;
  H.Get('http://example.com');
end;

constructor TFetcher.Create;
begin
  inherited Create;
  FHttp:= TIdHTTP.Create(nil);
  FTcp:= TIdTCPClient.Create(nil);
  FTcp.ReadTimeout:= 1000;
end;

procedure TFetcher.Fetch;
begin
  FHttp.Get('http://example.com');
end;

end.
