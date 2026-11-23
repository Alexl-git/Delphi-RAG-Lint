unit uPipeClientConnection;

{ Stub of the ORM3 unit of the same name: only what the generated _CLIENT units reference. }

interface

uses
  System.SysUtils,
  Winapi.Windows,
  Pipes.Protocol;

type
  TPipeClientConnection = class
  public
    function Connected: Boolean;
    function ExecuteCommand(ACmd: TCommandID; const APayload: TBytes; out AHeader: TPipeMessageHeader;
      out AResponse: TBytes): DWORD;
  end;

implementation

function TPipeClientConnection.Connected: Boolean;
begin
  Result := False;
end;

function TPipeClientConnection.ExecuteCommand(ACmd: TCommandID; const APayload: TBytes;
  out AHeader: TPipeMessageHeader; out AResponse: TBytes): DWORD;
begin
  AHeader.CommandID := 0;
  AResponse := nil;
  Result := ERROR_SUCCESS;
end;

end.
