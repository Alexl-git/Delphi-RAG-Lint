unit ctf;

interface

uses System.Generics.Collections, ctf_a, ctf_b;

type
  TMine = class
  public
    procedure Add(X: Integer);
  end;

  TMineKid = class(TMine)
  end;

procedure RealMine(M: TMine);
procedure RealKid(K: TMineKid);
procedure LibTyped(L: TList<string>);
procedure ForeignTyped(O: TOther);
procedure Untyped(V: Variant);

implementation

procedure TMine.Add(X: Integer); begin end;

procedure RealMine(M: TMine);
begin
  M.Add(1);
end;

procedure RealKid(K: TMineKid);
begin
  K.Add(2);
end;

procedure LibTyped(L: TList<string>);
begin
  L.Add('x');
end;

procedure ForeignTyped(O: TOther);
begin
  O.Add(3);
end;

procedure Untyped(V: Variant);
begin
  V.Add(4);
end;

end.
