unit StreamBufferAfterFree;

interface

uses
  System.Classes, System.SysUtils;

procedure Consume(P: Pointer);
procedure Hits;
procedure Controls(Cond: Boolean);

implementation

procedure Consume(P: Pointer);
begin
  if P = nil then Exit;
end;

procedure HitMemoryFinally;
var
  S: TMemoryStream;
  P: Pointer;
begin
  S := TMemoryStream.Create;
  try
    P := S.Memory;
  finally
    S.Free;
  end;
  Consume(P); // HIT
end;

procedure HitBytesAddress;
var
  S: TBytesStream;
  Q: PByte;
begin
  S := TBytesStream.Create;
  try
    Q := @S.Bytes[0];
  finally
    FreeAndNil(S);
  end;
  Consume(Q); // HIT
end;

procedure HitCastBytes;
var
  S: TStringStream;
  P: PAnsiChar;
begin
  S := TStringStream.Create('x');
  P := PAnsiChar(Pointer(S.Bytes));
  S.Free;
  Consume(P); // HIT
end;

procedure HitInline;
var
  S: TMemoryStream;
begin
  S := TMemoryStream.Create;
  var P := PByte(S.Memory) + 4;
  S.Free;
  Consume(P); // HIT
end;

procedure Hits;
begin
  HitMemoryFinally;
  HitBytesAddress;
  HitCastBytes;
  HitInline;
end;

{ TBytes is reference-counted: the array outlives the stream. The literal candidate is not a bug. }
procedure CtlBytesRefCounted;
var
  S: TBytesStream;
  B: TBytes;
begin
  S := TBytesStream.Create;
  B := S.Bytes;
  S.Free;
  Consume(@B[0]); // NOHIT
end;

procedure CtlUseBeforeFree;
var
  S: TMemoryStream;
  P: Pointer;
begin
  S := TMemoryStream.Create;
  P := S.Memory;
  Consume(P); // NOHIT
  S.Free;
end;

procedure CtlReassigned;
var
  S: TMemoryStream;
  P: Pointer;
begin
  S := TMemoryStream.Create;
  P := S.Memory;
  S.Free;
  P := nil;
  Consume(P); // NOHIT
end;

procedure CtlConditionalFree(Cond: Boolean);
var
  S: TMemoryStream;
  P: Pointer;
begin
  S := TMemoryStream.Create;
  P := S.Memory;
  if Cond then
    S.Free
  else
    Consume(P); // NOHIT
end;

procedure CtlFreeInExceptReraises;
var
  S: TMemoryStream;
  P: Pointer;
begin
  S := TMemoryStream.Create;
  try
    P := S.Memory;
  except
    S.Free;
    raise;
  end;
  Consume(P); // NOHIT
  S.Free;
end;

{ a list, not a stream: Memory here is nobody's buffer }
procedure CtlOtherType;
var
  S: TList;
  P: Pointer;
begin
  S := TList.Create;
  P := S.List;
  S.Free;
  Consume(P); // NOHIT
end;

procedure Controls(Cond: Boolean);
begin
  CtlBytesRefCounted;
  CtlUseBeforeFree;
  CtlReassigned;
  CtlConditionalFree(Cond);
  CtlFreeInExceptReraises;
  CtlOtherType;
end;

end.