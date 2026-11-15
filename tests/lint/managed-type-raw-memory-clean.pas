unit managed_type_raw_memory_clean;

interface

implementation

type
  TPunkt = record
    X, Y: Integer;
    Name: string[20];
  end;
  TAdresse = record
    Name: string;
  end;
  PAdresse = ^TAdresse;

procedure Clean;
var
  A, B: TPunkt;
  P: PAdresse;
  Buf: PByte;
  Q: TAdresse;
begin
  FillChar(A, SizeOf(A), 0);
  Move(A, B, SizeOf(TPunkt));
  GetMem(P, SizeOf(TAdresse));
  Initialize(P^);
  Finalize(P^);
  FreeMem(P);
  GetMem(Buf, 10);
  FreeMem(Buf);
  Finalize(Q);
  FillChar(Q, SizeOf(Q), 0);
end;

end.
