unit ResLib;

{ Library side of the run_v1511_RES_*.ps1 runners. Indexed as a folder into its
  own library DB; the project fixture only names what it declares. }

interface

type
  TResStore = class
  public
    procedure OpenKey;
    function Sub: TResStore;
  end;

var
  { A library unit-level object, as Vcl.Forms.Application is. }
  GResApp: TResStore;
  GResCounter: Integer;
  { Names the project fixture also declares itself (uResShadow). }
  GResOwn: TResStore;

{ The shared object: a project reaches TResStore.OpenKey without naming the type. }
function ResReg: TResStore;
{ Writes a global: a caller that names it bare is not effect-free. }
function ResBump: Boolean;
function ResNeedsArg(A: Integer): Boolean;
function ResOwn: Boolean;

implementation

procedure TResStore.OpenKey;
begin
end;

function TResStore.Sub: TResStore;
begin
  Result := Self;
end;

function ResReg: TResStore;
begin
  Result := GResApp;
end;

function ResBump: Boolean;
begin
  GResCounter := GResCounter + 1;
  Result := GResCounter > 3;
end;

function ResNeedsArg(A: Integer): Boolean;
begin
  Result := A > 0;
end;

function ResOwn: Boolean;
begin
  Result := True;
end;

end.
