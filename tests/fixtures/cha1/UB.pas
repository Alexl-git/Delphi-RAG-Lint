unit UB;

interface

uses
  UC, System.Classes;

type
  TB = class abstract
  public
    procedure Foo; virtual; abstract;
  end;

  TB2 = class(TB)
  public
    procedure Foo; override;
  end;

implementation

procedure TB2.Foo;
begin
end;

end.
