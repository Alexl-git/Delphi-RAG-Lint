unit raw_memory_leak;

interface

implementation

uses System.Classes, System.SysUtils;

type
  PRec = ^TRec;
  TRec = record
    X: Integer;
  end;

function Pruefsumme(P: Pointer; N: Integer): Integer;
begin
  Result := N;
end;

function Hits(AStream: TStream; Groesse: Integer): Integer;
var
  Puffer: Pointer;
  P: PByte;
  R: PRec;
  S: PChar;
begin
  GetMem(Puffer, Groesse);
  AStream.ReadBuffer(Puffer^, Groesse);
  Result := Pruefsumme(Puffer, Groesse);
  P := AllocMem(16);
  P^ := 1;
  New(R);
  R^.X := 2;
  S := StrNew('abc');
  Result := Result + Length(S);
end;

end.
