unit IncDeclD;

interface

{$I IncDeclD_decls.inc}

implementation

{$I IncDeclD_impl.inc}

procedure R;
begin
end;

procedure HostUseD;
var
  LHid: THiddenD;
  N: Integer;
begin
  N := cImplD;
  ImplR;
end;

end.
