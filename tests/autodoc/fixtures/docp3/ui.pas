unit ui;

// Self-contained stand-in hierarchy: the UI-affinity fact must be testable
// without the real VCL/DevExpress being indexed, so this unit declares its own
// TControl / TCustomPanel. Both names are ON the curated UI_BASE_TYPES list, so
// FPanel is reachable by the DIRECT-NAME arm; FDerived's type is NOT on the
// list and reaches it only through type_ancestors, which is what proves the
// ancestry arm.

interface

type
  TControl = class
  public
    procedure Repaint;
  end;

  TCustomPanel = class(TControl)
  end;

  TMyPanel = class(TCustomPanel)
  end;

  TForm1 = class
  private
    FPanel: TCustomPanel;
    FDerived: TMyPanel;
    FCount: Integer;
  public
    procedure TouchesUi;
    procedure TouchesUiByAncestry;
    procedure NoUi;
  end;

implementation

procedure TControl.Repaint;
begin
end;

procedure TForm1.TouchesUi;
begin
  FPanel.Repaint;
end;

procedure TForm1.TouchesUiByAncestry;
begin
  FDerived.Repaint;
end;

// Touches a NON-UI field only. Its doc block exists because of that field
// access (a Writes: fact), so "no UI thread only line" is a real absence and
// not the absence of a block.
procedure TForm1.NoUi;
begin
  FCount := 1;
end;

end.
