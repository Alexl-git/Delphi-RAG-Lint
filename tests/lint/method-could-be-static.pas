unit method_could_be_static;

{ Fixture for method-could-be-static (OFF by default, hint).
  Hit: a plain (non-virtual) method of a class that never mentions Self,
  inherited, a field, or another member of its class, and whose class has no
  ancestor outside this file (so no unseen inherited member can be used).
  FP shapes kept silent: virtual/override/dynamic/message methods, class
  methods, constructors/destructors, event handlers (first param Sender),
  published methods (DFM wiring), property accessors, methods whose address
  is taken, methods of a class that implements an interface or has an
  unresolved ancestor, bodies using a field/method/Self/inherited. }

interface

type
  IThing = interface
    procedure Run;
  end;

  TFoo = class
  private
    FCount: Integer;
    function GetCount: Integer;
    procedure Helper;
  public
    procedure Hit(N: Integer);
    function HitFn(const S: string): string;
    procedure NoHitField;
    procedure NoHitMember;
    procedure NoHitSelf;
    procedure NoHitInherited;
    procedure NoHitVirtual; virtual;
    class procedure NoHitClassMethod;
    procedure NoHitHandler(Sender: TObject);
    procedure NoHitAddr;
    property Count: Integer read GetCount;
  published
    procedure NoHitPublished(N: Integer);
  end;

  TImpl = class(TInterfacedObject, IThing)
  public
    procedure Run;
  end;

  TUnknownParent = class(TSomethingElsewhere)
  public
    procedure NoHitUnknownAncestor(N: Integer);
  end;

implementation

procedure TFoo.Hit(N: Integer);
begin
  Writeln(N);
end;

function TFoo.HitFn(const S: string): string;
begin
  Result:= S + 'x';
end;

procedure TFoo.NoHitField;
begin
  Inc(FCount);
end;

procedure TFoo.NoHitMember;
begin
  Helper;
end;

procedure TFoo.NoHitSelf;
begin
  Writeln(Self.ClassName);
end;

procedure TFoo.NoHitInherited;
begin
  inherited;
end;

procedure TFoo.NoHitVirtual;
begin
  Writeln(1);
end;

class procedure TFoo.NoHitClassMethod;
begin
  Writeln(1);
end;

procedure TFoo.NoHitHandler(Sender: TObject);
begin
  Writeln(1);
end;

procedure TFoo.NoHitAddr;
begin
  Writeln(2);
end;

function TFoo.GetCount: Integer;
begin
  Result:= 3;
end;

procedure TFoo.Helper;
begin
  FCount:= FCount + 1;
end;

procedure TFoo.NoHitPublished(N: Integer);
begin
  Writeln(N);
end;

procedure TImpl.Run;
begin
  Writeln(1);
end;

procedure TUnknownParent.NoHitUnknownAncestor(N: Integer);
begin
  Writeln(N);
end;

var
  Callback: procedure of object;
  Foo: TFoo;
initialization
  Callback:= Foo.NoHitAddr;
end.