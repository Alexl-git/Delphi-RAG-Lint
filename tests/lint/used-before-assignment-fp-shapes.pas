unit UbaFpShapes;

interface

implementation

uses
  System.Classes, System.SysUtils;

type
  TPair = record
    A: Integer;
    B: Integer;
  end;

procedure FillBuf(var Buf; Count: Integer);
begin
  FillChar(Buf, Count, 0);
end;

{ SHAPE 1a: pb[0] handed to a routine whose parameter is an UNTYPED var -- the
  callee writes it. }
function UntypedVarFree: Byte;
var
  pb: array[0..3] of Byte;
begin
  FillBuf(pb[0], 2);
  Result := pb[0];
end;

{ SHAPE 1b: TStream.Read(var Buffer; Count) -- same, through a method call. }
function UntypedVarMethod(AStream: TStream): Byte;
var
  pb: array[0..3] of Byte;
begin
  Result := 0;
  if AStream.Read(pb[0], 2) <> 2 then Exit;
  Result := pb[0];
end;

{ SHAPE 2: elements are read only up to a count the routine maintains. }
function CountGuarded(Port: Integer; Found: Boolean): Boolean;
var
  Chans: array[0..100] of Integer;
  ChanCount: Integer;
  j: Integer;
begin
  Result := False;
  ChanCount := 0;
  if Found then
  begin
    Chans[ChanCount] := Port;
    Inc(ChanCount);
  end;
  for j := 0 to ChanCount - 1 do
    if Port = Chans[j] then
      Result := True;
end;

{ SHAPE 3: a record whose field is assigned before that field is read in the
  exception handler (the handler edge also models "raised before anything ran"). }
function PartialRecord: Integer;
var
  R: TPair;
begin
  Result := 0;
  try
    R.A := 0;
    R := Default(TPair);
    Result := R.B;
  except
    Result := R.A;
  end;
end;

end.
