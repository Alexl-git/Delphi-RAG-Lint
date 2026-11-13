unit GR11Orphan;
{ v151 GR11: a class body after conditional alternatives whose THEN branch is a
  complete short class (grammar v1.4.11 node classBodyOrphan). Indexed twice: as is
  (ELSE active: one ordinary class) and with GR11_ALT defined (THEN active: the
  members have no header). }
interface
type
  TGr11Base = class
  public
    procedure Gr11BaseRun; virtual;
  end;
  TGr11Other = class
  end;
{$IFDEF GR11_ALT}
  TGr11Dock = class(TGr11Other);
{$ELSE}
  TGr11Dock = class(TGr11Base)
{$ENDIF}
  protected
    FGr11A: Integer;
  public
    procedure Gr11DockRun;
  end;
  TGr11After = class(TGr11Base)
  public
    procedure Gr11AfterRun;
  end;
implementation
procedure TGr11Base.Gr11BaseRun;
begin
end;
procedure TGr11Dock.Gr11DockRun;
begin
end;
procedure TGr11After.Gr11AfterRun;
begin
  Gr11BaseRun;
end;
end.
