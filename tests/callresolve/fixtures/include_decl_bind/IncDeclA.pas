unit IncDeclA;

interface

{$I IncDeclA_decls.inc}

type
  TBar = class
    procedure Go;
  end;

procedure Q;

implementation

{$I IncDeclA_impl.inc}

procedure TFoo.Run;
begin
end;

procedure TBar.Go;
begin
end;

procedure P;
begin
end;

procedure Q;
begin
end;

end.
