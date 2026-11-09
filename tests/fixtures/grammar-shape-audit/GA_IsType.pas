unit GA_IsType;

{ Grammar-shape audit fixture, shape (b): grammar v1.4.5 parses the right of
  `is` as a TYPE node (identifier / typerefDot / typerefTpl, `is not T` an
  exprUnary) and `O is T and F` groups as `(O is T) and F`. }

interface

uses
  System.Classes, System.Generics.Collections;

type
  TSealedThing = class sealed
  end;

  TOther = class
  end;

  TProbe = class
  private
    FTag: Integer;
  public
    procedure DoA;
    procedure Grouping(pObj: TObject; pFlag: Boolean);
    procedure Dotted(pObj: TObject);
    procedure Generic(pObj: TObject);
    procedure IsNot(pObj: TObject);
    procedure IsThenCast(pObj: TObject);
    procedure IsThenAs(pObj: TObject);
    procedure DupIs(pObj: TObject);
    procedure SealedNever(pThing: TSealedThing);
    procedure Chain(pObj: TObject);
    procedure IsInExprIf(pObj: TObject);
    procedure IsBoolCompare(pObj: TObject);
  end;

implementation

procedure TProbe.DoA;
begin
  Inc(FTag);
end;

procedure TProbe.Grouping(pObj: TObject; pFlag: Boolean);
begin
  if pObj is TComponent and pFlag then DoA;
  if pFlag and pObj is TComponent then DoA;
  if pObj is TComponent and (pObj as TComponent).Tag = 0 then DoA;
end;

procedure TProbe.Dotted(pObj: TObject);
begin
  if pObj is System.Classes.TComponent then
    TComponent(pObj).Tag := 1;
end;

procedure TProbe.Generic(pObj: TObject);
begin
  if pObj is TList<Integer> then
    TList<Integer>(pObj).Clear;
end;

procedure TProbe.IsNot(pObj: TObject);
begin
  if pObj is not TComponent then DoA;
  if not (pObj is TComponent) then DoA;
end;

procedure TProbe.IsThenCast(pObj: TObject);
begin
  if pObj is TComponent then
    TComponent(pObj).Tag := 1;
end;

procedure TProbe.IsThenAs(pObj: TObject);
begin
  if pObj is TComponent then
    (pObj as TComponent).Tag := 1;
end;

procedure TProbe.DupIs(pObj: TObject);
begin
  if (pObj is TComponent) or (pObj is TComponent) then DoA;
  if pObj is TComponent and pObj is TComponent then DoA;
end;

procedure TProbe.SealedNever(pThing: TSealedThing);
begin
  if TObject(pThing) is TOther then DoA;
end;

procedure TProbe.Chain(pObj: TObject);
begin
  if pObj is TComponent then
    DoA
  else if pObj is TStrings then
    DoA
  else if pObj is TList<Integer> then
    DoA
  else if pObj is TComponent then
    DoA;
end;

procedure TProbe.IsInExprIf(pObj: TObject);
var
  LTag: Integer;
begin
  LTag := if pObj is TComponent then 1 else 0;
  FTag := LTag;
end;

procedure TProbe.IsBoolCompare(pObj: TObject);
begin
  if (pObj is TComponent) = True then DoA;
  if pObj is TComponent = False then DoA;
end;

end.
