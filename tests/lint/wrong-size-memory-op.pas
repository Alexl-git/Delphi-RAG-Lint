unit WrongSize;

interface

uses
  System.Classes;

implementation

type
  TRec = record
    A, B: Integer;
  end;

procedure Bad(pStream: TStream);
var
  P: PByte;
  S: string;
  Buf: array[0..9] of Byte;
  Rec: TRec;
  Txt: string;
  Bytes: TBytes;
  Obj: IInterface;
  Cnt: Integer;
begin
  FillChar(P^, SizeOf(P), 0);
  ZeroMemory(P^, SizeOf(P));
  Move(S[1], Buf, Length(S));
  CopyMemory(@Buf, S[1], Length(S));
  pStream.Write(S[1], Length(S));
  FillChar(Txt, SizeOf(Txt), 0);
  FillChar(Bytes, SizeOf(Bytes), 0);
  FillChar(Obj, SizeOf(Obj), 0);
end;

procedure Good(pStream: TStream);
var
  P: PByte;
  S: string;
  Buf: array[0..9] of Byte;
  Rec: TRec;
  Bytes: TBytes;
  Cnt: Integer;
begin
  FillChar(P^, SizeOf(P^), 0);
  FillChar(Rec, SizeOf(Rec), 0);
  Move(S[1], Buf, Length(S) * SizeOf(Char));
  Move(Bytes[0], Buf, Length(Bytes));
  pStream.Write(S[1], Length(S) * 2);
  Move(S[1], Buf, ByteLength(S));
  FillChar(Cnt, SizeOf(Cnt), 0);
end;

type
  TOwner = class
    FName: string;
    procedure Run;
  end;

procedure TOwner.Run;
var
  Buf: array[0..9] of Byte;
begin
  { Known FP shape: a FIELD has no visible declaration in the routine, so
    #declared-type? stays silent (no guess). }
  Move(FName[1], Buf, Length(FName));
  FillChar(FName, SizeOf(FName), 0);
end;

end.
