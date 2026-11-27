unit uFb1;

{ Fixture of 1.56 lane FB-1: the value charts (ask value-origin / ask value-use) over data_flows,
  numeric value rows (val_class) included. Read by tests\autotest\run_v156_FB1.ps1; every routine
  below is one asserted flow, so keep the names and the shapes. }

interface

type
  TOrder = class
  private
    FQty: Integer;
    FPrice: Double;
    FTotal: Currency;
    FPaid: Boolean;
    FName: string;
    FLabel: string;
    FRate: Double;
  public
    procedure SetQty(pQty: Integer);
    procedure SetPrice(pPrice: Double);
    procedure SetName(const pName: string);
    procedure Recalc;
    function Total: Currency;
    function NameLen: Integer;
    procedure Describe;
    procedure Reset;
  end;

var
  GLastTotal: Currency;

function Twice(pN: Integer): Integer;
procedure Feed(pOrder: TOrder; pCount: Integer);
procedure Report(pOrder: TOrder);

implementation

uses
  System.SysUtils;

function Twice(pN: Integer): Integer;
begin
  Result := pN * 2;
end;

procedure TOrder.SetQty(pQty: Integer);
begin
  FQty := pQty;
end;

procedure TOrder.SetPrice(pPrice: Double);
begin
  FPrice := pPrice;
end;

procedure TOrder.SetName(const pName: string);
begin
  FName := pName;
end;

procedure TOrder.Recalc;
begin
  FTotal := FQty * FPrice;
  FPaid := FTotal > 0;
  GLastTotal := FTotal;
end;

function TOrder.Total: Currency;
begin
  Result := FTotal;
end;

function TOrder.NameLen: Integer;
begin
  Result := Length(FName);
end;

procedure TOrder.Describe;
begin
  FLabel := FName + ': ' + IntToStr(FQty);
end;

procedure TOrder.Reset;
begin
  FRate := 1.5;
end;

procedure Feed(pOrder: TOrder; pCount: Integer);
begin
  pOrder.SetQty(Twice(pCount));
end;

procedure Report(pOrder: TOrder);
begin
  GLastTotal := pOrder.Total;
end;

end.
