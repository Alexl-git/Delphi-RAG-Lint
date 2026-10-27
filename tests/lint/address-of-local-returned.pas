unit address_of_local_returned;

interface

implementation

var
  GCounter: Integer;

function AddrOfLocal: Pointer;
var
  L: Integer;
begin
  L := 1;
  Result := @L;
end;

function AddrViaExit: PInteger;
var
  L: Integer;
begin
  L := 1;
  Exit(@L);
end;

function PCharOfLocalString: PChar;
var
  S: string;
begin
  S := 'text';
  Result := PChar(S);
end;

function PointerOfLocalString: Pointer;
var
  S: string;
begin
  S := 'text';
  Result := Pointer(S);
end;

function AddrOfByValueParam(V: Integer): PInteger;
begin
  Result := @V;
end;

function AddrOfVarParam(var V: Integer): PInteger;
begin
  Result := @V;
end;

function PCharOfConstParam(const S: string): PChar;
begin
  Result := PChar(S);
end;

function AddrOfGlobal: PInteger;
begin
  Result := @GCounter;
end;

function PointerOfLocalObject: Pointer;
var
  O: TObject;
begin
  O := nil;
  Result := Pointer(O);
end;

procedure AddrOfLocalNotReturned;
var
  L: Integer;
  P: PInteger;
begin
  P := @L;
  P^ := 1;
end;

end.
