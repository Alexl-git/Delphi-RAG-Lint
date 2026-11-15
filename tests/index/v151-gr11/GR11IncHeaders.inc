{ v151 GR11: bare routine headers at an include-file root (grammar v1.4.12, declProc
  directly under root). Pasted into the interface of GR11IncHost.pas. }
type
  TGr11IncHolder = class
  end;

procedure Gr11IncFirst(pN: Integer);
function Gr11IncSecond: Integer;
procedure Gr11IncLast;
