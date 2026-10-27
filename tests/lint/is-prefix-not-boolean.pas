unit IsPrefix;

interface

function IsReady: Integer;
function HasName(const pName: string): string;
function CanRun: Boolean;
function IsOk: Boolean;
function IsolateName: string;
function Island(pX: Integer): Integer;
function Hash(pX: Integer): Integer;
procedure IsDone;

type
  TFoo = class
    function IsValid: Integer;
    function HasItems: Boolean;
    function CanDo: ByteBool;
  end;

implementation

function IsReady: Integer;
begin
  Result := 1;
end;

function HasName(const pName: string): string;
begin
  Result := pName;
end;

function CanRun: Boolean;
begin
  Result := True;
end;

function IsOk: Boolean;
begin
  Result := True;
end;

function IsolateName: string;
begin
  Result := '';
end;

function Island(pX: Integer): Integer;
begin
  Result := pX;
end;

function Hash(pX: Integer): Integer;
begin
  Result := pX;
end;

procedure IsDone;
begin
end;

function TFoo.IsValid: Integer;
begin
  Result := 0;
end;

function TFoo.HasItems: Boolean;
begin
  Result := False;
end;

function TFoo.CanDo: ByteBool;
begin
  Result := False;
end;

end.
