unit char_to_pchar_clean;

interface

implementation

uses Winapi.Windows;

type
  TRec = record
    Ch: Char;
  end;

procedure Clean(const S: string; P: Pointer);
var
  C: Char;
  R: TRec;
  B: array[0..1] of Char;
begin
  C := 'x';
  OutputDebugString(PChar(S));
  OutputDebugString(PChar(string(C)));
  OutputDebugString(PChar(P));
  OutputDebugString(PChar(@B[0]));
  OutputDebugString(PChar(R.Ch));
  OutputDebugString(PChar(Undeclared));
end;

end.
