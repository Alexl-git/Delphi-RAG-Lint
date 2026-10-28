unit evhandler;

{ A published event-handler method (no override) has no ancestor method of its own name:
  `inherited;` is legal and does nothing, `inherited ServiceShutdown(Sender)` is E2003
  "Undeclared identifier". The fixer must decline a procedure whose declaration is not an
  override. Found by the ORM3 --fix --apply build proof (TMicroniteMW1.ServiceShutdown). }

interface

type
  TBase = class
  end;

  TSvc = class(TBase)
  public
    procedure ServiceShutdown(Sender: TObject);
  end;

implementation

procedure TSvc.ServiceShutdown(Sender: TObject);
begin
  inherited;
end;

end.
