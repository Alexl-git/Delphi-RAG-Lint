unit touches;

interface

uses
  System.IOUtils;

type
  TTxn = class
  public
    procedure StartTransaction;
    procedure Commit;
  end;

function ReadConfig(const APath: string): string;
procedure RunTxn(ATxn: TTxn);
function AddUp(A, B: Integer): Integer;
function Driver: Integer;

implementation

procedure TTxn.StartTransaction;
begin
end;

procedure TTxn.Commit;
begin
end;

function ReadConfig(const APath: string): string;
begin
  Result := TFile.ReadAllText(APath);
end;

procedure RunTxn(ATxn: TTxn);
begin
  ATxn.StartTransaction;
  ATxn.Commit;
end;

// Gives the three routines above a caller fact so each one has a doc block --
// see harvest_drift.pas for why the parentheses are load-bearing. AddUp is the
// Pure case, so it must have a block for "Pure is present" to be assertable.
function Driver: Integer;
var
  T: TTxn;
begin
  T := nil;
  RunTxn(T);
  ReadConfig('x');
  Result := AddUp(1, 2);
end;

function AddUp(A, B: Integer): Integer;
begin
  Result := A + B;
end;

end.
