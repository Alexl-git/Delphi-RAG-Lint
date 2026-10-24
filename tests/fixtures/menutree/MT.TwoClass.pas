unit MT.TwoClass;

{ menu-tree fixture (e3d vcl-roots): two classes in ONE unit that each own a
  field of the same name (FMenu, FPopup) and add different items to it. They
  must stay two external roots (TFirstMenu.FMenu / TSecondMenu.FMenu), never one
  merged FMenu root. Compiled, never run. }

interface

uses
  Vcl.Menus;

type
  TFirstMenu = class
  private
    FMenu: TMenuItem;
    FPopup: TPopupMenu;
    procedure DoAlpha(Sender: TObject);
    procedure DoBeta(Sender: TObject);
  public
    procedure Build;
  end;

  TSecondMenu = class
  private
    FMenu: TMenuItem;
    FPopup: TPopupMenu;
    procedure DoGamma(Sender: TObject);
    procedure DoDelta(Sender: TObject);
  public
    procedure Build;
  end;

implementation

procedure TFirstMenu.DoAlpha(Sender: TObject);
begin
end;

procedure TFirstMenu.DoBeta(Sender: TObject);
begin
end;

procedure TFirstMenu.Build;
var
  X: TMenuItem;
begin
  X:= TMenuItem.Create(nil);
  X.Caption:= 'First Alpha';
  X.OnClick:= DoAlpha;
  FMenu.Add(X);
  X:= TMenuItem.Create(nil);
  X.Caption:= 'First Beta';
  X.OnClick:= DoBeta;
  FPopup.Items.Add(X);
end;

procedure TSecondMenu.DoGamma(Sender: TObject);
begin
end;

procedure TSecondMenu.DoDelta(Sender: TObject);
begin
end;

procedure TSecondMenu.Build;
var
  X: TMenuItem;
begin
  X:= TMenuItem.Create(nil);
  X.Caption:= 'Second Gamma';
  X.OnClick:= DoGamma;
  FMenu.Add(X);
  X:= TMenuItem.Create(nil);
  X.Caption:= 'Second Delta';
  X.OnClick:= DoDelta;
  FPopup.Items.Add(X);
end;

end.
