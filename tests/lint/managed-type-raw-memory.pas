unit managed_type_raw_memory;

interface

implementation

uses Winapi.Windows;

type
  TAdresse = record
    Name: string;
    PLZ: Integer;
  end;
  PAdresse = ^TAdresse;
  TIntfRec = record
    Obj: IInterface;
  end;
  TListe = array[0..3] of TAdresse;

procedure Hits;
var
  Adresse, Kopie: TAdresse;
  P: PAdresse;
  I: TIntfRec;
  L: TListe;
  S1, S2: string;
begin
  FillChar(Adresse, SizeOf(Adresse), 0);
  Move(Adresse, Kopie, SizeOf(TAdresse));
  GetMem(P, SizeOf(TAdresse));
  FreeMem(P);
  ZeroMemory(@I, SizeOf(I));
  FillChar(L, SizeOf(L), 0);
  Move(S1, S2, SizeOf(string));
end;

end.
