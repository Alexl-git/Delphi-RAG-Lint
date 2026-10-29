unit basic;

interface

type
  TFoo = class
    procedure Hello;
  end;

implementation

procedure TFoo.Hello;
begin
end;

procedure Run(O: TObject);
begin
  TFoo(O).Hello;
end;

end.
