unit uTtStubLib;

{ The fixture's "platform library": indexed into its OWN DB and passed as the second
  --db, so the fixture units reach these classes the way a real project reaches the
  VCL -- their refs stay unbound and the ancestry comes from the library. Hermetic:
  the guard never opens a real library index. }

interface

type
  TPersistent = class(TObject)
  end;

  TComponent = class(TPersistent)
  public
    Tag: Integer;
    Name: string;
  end;

  TStrings = class(TPersistent)
  public
    procedure Add(const S: string);
    procedure Clear;
  end;

  TStringList = class(TStrings)
  end;

  TCanvas = class(TPersistent)
  public
    procedure Lock;
  end;

  TBitmap = class(TPersistent)
  public
    Canvas: TCanvas;
  end;

  TControl = class(TComponent)
  public
    Caption: string;
    Visible: Boolean;
    procedure Hide;
    procedure Repaint;
    procedure Invalidate;
  end;

  TWinControl = class(TControl)
  public
    Handle: NativeUInt;
  end;

  TCustomForm = class(TWinControl)
  public
    procedure Close;
  end;

  TForm = class(TCustomForm)
  end;

  TLabel = class(TControl)
  end;

  TMemo = class(TWinControl)
  public
    Lines: TStrings;
    procedure Clear;
  end;

  TFmxObject = class(TComponent)
  public
    Position: Integer;
  end;

  TFmxRect = class(TFmxObject)
  end;

  TApplication = class(TComponent)
  public
    Terminated: Boolean;
    Title: string;
    procedure ProcessMessages;
  end;

  TScreen = class(TComponent)
  public
    Cursor: Integer;
  end;

  THomonym = class(TControl)
  end;

  TThread = class(TObject)
  public
    Terminated: Boolean;
    procedure Terminate;
  end;

var
  Application: TApplication;
  Screen: TScreen;

implementation

procedure TStrings.Add(const S: string);
begin
end;

procedure TStrings.Clear;
begin
end;

procedure TCanvas.Lock;
begin
end;

procedure TControl.Hide;
begin
end;

procedure TControl.Repaint;
begin
end;

procedure TControl.Invalidate;
begin
end;

procedure TCustomForm.Close;
begin
end;

procedure TMemo.Clear;
begin
end;

procedure TApplication.ProcessMessages;
begin
end;

procedure TThread.Terminate;
begin
end;

end.
