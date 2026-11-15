unit raw_memory_leak_clean;

interface

implementation

uses System.Classes, System.SysUtils;

type
  PRec = ^TRec;
  TRec = record
    X: Integer;
  end;

  THolder = class
  private
    FBuf: Pointer;
    FList: TList;
  public
    procedure Clean;
    function Make: Pointer;
  end;

procedure THolder.Clean;
var
  A, B, C, D: Pointer;
  R: PRec;
  S: PChar;
begin
  GetMem(A, 10);
  try
    FillChar(A^, 10, 0);
  finally
    FreeMem(A);
  end;
  New(R);
  Dispose(R);
  GetMem(B, 10);
  FList.Add(B);
  GetMem(C, 10);
  FBuf := C;
  S := StrNew('x');
  StrDispose(S);
  GetMem(FBuf, 20);
  D := AllocMem(5);
  ReallocMem(D, 0);
end;

function THolder.Make: Pointer;
var
  P: Pointer;
begin
  GetMem(P, 10);
  Result := P;
end;

end.
