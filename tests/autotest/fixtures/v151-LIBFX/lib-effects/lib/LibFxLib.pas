unit LibFxLib;

{ Library side of run_v151_LIBFX_lib_effects.ps1. Indexed as a folder into its
  own library DB; the project fixture only calls into it. }

interface

type
  TLibFxObj = class
  public
    procedure VirtBump; virtual;
  end;

var
  GLibCounter: Integer;

function BumpCounter: Boolean;
function PlainSum(A, B: Integer): Integer;
procedure FreeTemp;

implementation

procedure TLibFxObj.VirtBump;
begin
  GLibCounter := GLibCounter + 1;
end;

function BumpCounter: Boolean;
begin
  GLibCounter := GLibCounter + 1;
  Result := GLibCounter > 3;
end;

function PlainSum(A, B: Integer): Integer;
begin
  Result := A + B;
end;

procedure FreeTemp;
var
  P: Pointer;
begin
  GetMem(P, 4);
  FreeMem(P);
end;

end.
