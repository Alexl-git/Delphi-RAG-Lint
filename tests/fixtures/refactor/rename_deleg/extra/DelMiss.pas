unit DelMiss;

interface

uses
  DelTypes;

type
  TNoBar = class
  public
    procedure Other;
  end;

  { Delegates IFoo to a class that has no Bar: not compilable, so never built; the plan must refuse. }
  TMissAgg = class(TInterfacedObject, IFoo)
  private
    FImpl: TNoBar;
  public
    property Impl: TNoBar read FImpl implements IFoo;
  end;

implementation

procedure TNoBar.Other;
begin
end;

end.