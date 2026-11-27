unit uUaf;

{ v156 HB6 fixture: --preset use-after-free. One variable per case; the routines of a twin pair
  differ by one construct. }

interface

uses
  System.Classes, System.SysUtils;

type
  TBox = class
  private
    FItems: TStringList;
    FOther: TStringList;
  public
    procedure AfterFree;
    procedure OtherReceiver(pBox: TBox);
  end;

var
  GA, GB, GC, GD, GE: TStringList;
  GF, GG: TStringList;

procedure UafAfter;
procedure UafRenewed;
procedure UafBranch(pDrop: Boolean);
procedure UafCallee;
procedure UafNever;
procedure UafLoop(pCount: Integer);
procedure UafExcept;

implementation

procedure UafAfter;
begin
  GA := TStringList.Create;
  GA.Free;
  GA.Add('x');
end;

procedure UafRenewed;
begin
  GB := TStringList.Create;
  GB.Free;
  GB := TStringList.Create;
  GB.Add('x');
end;

procedure UafBranch(pDrop: Boolean);
begin
  GC := TStringList.Create;
  if pDrop then
    GC.Free;
  GC.Add('x');
end;

procedure RenewD;
begin
  GD := TStringList.Create;
end;

procedure UafCallee;
begin
  GD := TStringList.Create;
  GD.Free;
  RenewD;
  GD.Add('x');
end;

procedure UafNever;
begin
  GE := TStringList.Create;
  GE.Add('x');
end;

procedure TBox.AfterFree;
begin
  FItems.Free;
  FItems.Add('x');
end;

procedure TBox.OtherReceiver(pBox: TBox);
begin
  pBox.FOther.Free;
  FOther.Add('x');
end;

procedure UafLoop(pCount: Integer);
begin
  GF := TStringList.Create;
  while pCount > 0 do
  begin
    GF.Add('x');
    GF.Free;
    Dec(pCount);
  end;
end;

procedure UafExcept;
begin
  GG.Free;
  try
    GG := TStringList.Create;
    GG.Add('x');
  except
    GG.Add('y');
  end;
end;

end.
