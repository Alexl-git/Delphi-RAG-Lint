unit PForm;

// Handler is private (not published) and assigned only in PForm.dfm: narrowing it would break the binding.

interface

uses
  LibTypes;

type
  TFrm = class
  private
    procedure Handler(pP: TNpLeaf);
    procedure Plain(pP: TNpLeaf);
  public
    procedure Go;
  end;

implementation

procedure TFrm.Handler(pP: TNpLeaf);
begin
  pP.Foo;
end;

procedure TFrm.Plain(pP: TNpLeaf);
begin
  pP.Foo;
end;

procedure TFrm.Go;
begin
  Plain(nil);
end;

end.
