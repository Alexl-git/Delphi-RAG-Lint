unit Z_Kinds;

{ Fixture for run_returns_owner_order.ps1 (151 X2R, 152b DF/O7): a class whose
  name does NOT follow the T/I convention, one that does, and two Windows-style
  value aliases (HWND / DWORD) that are neither classes nor T/I-named. }

interface

type
  Widget = class
  public
    N: Integer;
  end;

  TZThing = class
  public
    N: Integer;
  end;

  HWND  = NativeUInt;
  DWORD = Cardinal;

implementation

end.