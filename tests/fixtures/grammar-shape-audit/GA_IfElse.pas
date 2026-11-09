unit GA_IfElse;

{ Grammar-shape audit fixture, shape (a): grammar v1.4.4 parses an if
  STATEMENT whose branches also read as expressions (bare calls, Exit,
  identifiers) as ifElse; v1.4.3 and older parsed it as statement(exprIf). }

interface

type
  TWidget = class
  private
    FCache: TObject;
    FCount: Integer;
    function GetCache: TObject;
  public
    procedure DoA;
    procedure DoB;
    procedure Run(pFlag: Boolean);
    procedure Same(pFlag: Boolean);
    procedure AfterExit(pFlag: Boolean);
    procedure AfterExitCall(pFlag: Boolean);
    procedure BothExit(pFlag: Boolean);
    procedure Nested(pA, pB, pC: Boolean);
    procedure Deep(pA, pB, pC, pD, pE, pF, pG: Boolean);
    procedure Many(pA, pB, pC, pD, pE, pF, pG, pH, pI, pJ, pK, pL: Boolean);
    procedure FreeBranch(pObj: TObject; pFlag: Boolean);
    procedure NilFree(pObj: TObject);
    procedure SameCond(pFlag: Boolean);
    procedure ConstCond;
    function Pick(pFlag: Boolean): Integer;
    function PickSame(pFlag: Boolean): Integer;
    property Cache: TObject read GetCache;
  end;

implementation

uses
  System.SysUtils;

procedure TWidget.DoA;
begin
  Inc(FCount);
end;

procedure TWidget.DoB;
begin
  Dec(FCount);
end;

procedure TWidget.Run(pFlag: Boolean);
begin
  if pFlag then DoA else DoB;
end;

procedure TWidget.Same(pFlag: Boolean);
begin
  if pFlag then DoA else DoA;
end;

procedure TWidget.AfterExit(pFlag: Boolean);
begin
  if pFlag then Exit else DoB;
  DoA;
end;

procedure TWidget.AfterExitCall(pFlag: Boolean);
begin
  if pFlag then
    Exit
  else
    DoB;
end;

procedure TWidget.BothExit(pFlag: Boolean);
begin
  if pFlag then Exit else Exit;
  DoA;
end;

procedure TWidget.Nested(pA, pB, pC: Boolean);
begin
  if pA then
    if pB then DoA else DoB
  else if pC then DoA else DoB;
end;

procedure TWidget.Deep(pA, pB, pC, pD, pE, pF, pG: Boolean);
begin
  while pA do
  begin
    if pB then
    begin
      while pC do
      begin
        if pD then
        begin
          while pE do
          begin
            if pF then
            begin
              if pG then DoA else DoB;
            end;
          end;
        end;
      end;
    end;
  end;
end;

procedure TWidget.Many(pA, pB, pC, pD, pE, pF, pG, pH, pI, pJ, pK, pL: Boolean);
begin
  if pA then DoA else DoB;
  if pB then DoA else DoB;
  if pC then DoA else DoB;
  if pD then DoA else DoB;
  if pE then DoA else DoB;
  if pF then DoA else DoB;
  if pG then DoA else DoB;
  if pH then DoA else DoB;
  if pI then DoA else DoB;
  if pJ then DoA else DoB;
  if pK then DoA else DoB;
  if pL then DoA else DoB;
  if pA and pB then DoA else DoB;
  if pC or pD then DoA else DoB;
  if pE and pF or pG then DoA else DoB;
  if pH then DoA else DoB;
end;

procedure TWidget.FreeBranch(pObj: TObject; pFlag: Boolean);
begin
  if pFlag then pObj.Free else DoA;
end;

procedure TWidget.NilFree(pObj: TObject);
begin
  if Assigned(pObj) then pObj.Free else DoA;
  if pObj <> nil then FreeAndNil(pObj) else DoB;
end;

procedure TWidget.SameCond(pFlag: Boolean);
begin
  if pFlag then DoA else if pFlag then DoB else DoA;
end;

procedure TWidget.ConstCond;
begin
  if True then DoA else DoB;
  if False then DoA else DoB;
end;

function TWidget.Pick(pFlag: Boolean): Integer;
begin
  if pFlag then Exit(1) else Exit(2);
end;

function TWidget.PickSame(pFlag: Boolean): Integer;
begin
  if pFlag then Exit(1) else Exit(1);
end;

function TWidget.GetCache: TObject;
begin
  if FCache = nil then FCache := TObject.Create else DoA;
  Result := FCache;
end;

end.
