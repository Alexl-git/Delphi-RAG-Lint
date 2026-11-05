unit wsa_app;

{ WITH-SELF-PROP. Every Site* method holds ONE with statement whose body names
  one bare member of TMyForm (or of its with target). The with target's own
  surface leaves this index, so only the library can say the target lacks it. }

interface

uses wsl_core;

type
  TGoer = class
  public
    procedure Go;
  end;

  TOpenTarget = class(TLibBase)
  public
    TargetProp: Integer;
  end;

  TCompleteTarget = class
  public
    CompleteProp: Integer;
  end;

  TLeavesTarget = class(TLibLeaves);
  TUnknownTarget = class(TNowhereAtAll);
  THelpedTarget = class(TLibHelped);
  TTwiceTarget = class(TLibTwice);
  TProjHelpedTarget = class(TLibForProjectHelper);

  { A PROJECT helper on a LIBRARY type: the target's type has it by inheritance. }
  TProjectHelper = class helper for TLibForProjectHelper
  public
    procedure ProjHelperCall;
  end;

  TMyForm = class(TLibBase)
  private
    FOwnField: Integer;
    FGoer: TGoer;
    function GetOwnProp: Integer;
    procedure SetOwnProp(AValue: Integer);
  public
    ShadowProp: Integer;
    RootShadow: Integer;
    FOpen: TOpenTarget;
    FDone: TCompleteTarget;
    FLeaves: TLeavesTarget;
    FUnknown: TUnknownTarget;
    FHelped: THelpedTarget;
    FTwice: TTwiceTarget;
    FProjHelped: TProjHelpedTarget;
    procedure OwnCall;
    procedure HelperCall;
    procedure TwiceCall;
    procedure ProjHelperCall;
    procedure Dispatch;
    procedure SiteCall;
    procedure SiteWrite;
    procedure SiteRead;
    procedure SiteField;
    procedure SiteReceiver;
    procedure SiteLayer;
    procedure SiteDone;
    procedure SiteSelf;
    procedure SiteTarget;
    procedure SiteHidden;
    procedure SiteHiddenRoot;
    procedure SiteLeaves;
    procedure SiteUnknown;
    procedure SiteHelper;
    procedure SiteTwice;
    procedure SiteProjHelper;
    procedure SiteFloor;
    property OwnProp: Integer read GetOwnProp write SetOwnProp;
    property Goer: TGoer read FGoer;
  end;

implementation

procedure TGoer.Go; begin end;
procedure TProjectHelper.ProjHelperCall; begin end;
function TMyForm.GetOwnProp: Integer; begin Result:= FOwnField; end;
procedure TMyForm.SetOwnProp(AValue: Integer); begin FOwnField:= AValue; end;
procedure TMyForm.OwnCall; begin end;
procedure TMyForm.HelperCall; begin end;
procedure TMyForm.TwiceCall; begin end;
procedure TMyForm.ProjHelperCall; begin end;
procedure TMyForm.Dispatch; begin end;

procedure TMyForm.SiteCall;
begin
  with FOpen do
    OwnCall;
end;

procedure TMyForm.SiteWrite;
begin
  with FOpen do
    OwnProp:= 1;
end;

procedure TMyForm.SiteRead;
var
  V: Integer;
begin
  with FOpen do
    V:= OwnProp;
end;

procedure TMyForm.SiteField;
begin
  with FOpen do
    FOwnField:= 1;
end;

procedure TMyForm.SiteReceiver;
begin
  with FOpen do
    Goer.Go;
end;

procedure TMyForm.SiteLayer;
begin
  with FDone, FOpen do
    CompleteProp:= 1;
end;

procedure TMyForm.SiteDone;
begin
  with FDone do
    OwnProp:= 1;
end;

procedure TMyForm.SiteSelf;
begin
  with Self do
    OwnProp:= 1;
end;

procedure TMyForm.SiteTarget;
begin
  with FOpen do
    TargetProp:= 1;
end;

procedure TMyForm.SiteHidden;
begin
  with FOpen do
    ShadowProp:= 1;
end;

procedure TMyForm.SiteHiddenRoot;
begin
  with FOpen do
    RootShadow:= 1;
end;

procedure TMyForm.SiteLeaves;
begin
  with FLeaves do
    OwnProp:= 1;
end;

procedure TMyForm.SiteUnknown;
begin
  with FUnknown do
    OwnProp:= 1;
end;

procedure TMyForm.SiteHelper;
begin
  with FHelped do
    HelperCall;
end;

procedure TMyForm.SiteTwice;
begin
  with FTwice do
    TwiceCall;
end;

procedure TMyForm.SiteProjHelper;
begin
  with FProjHelped do
    ProjHelperCall;
end;

procedure TMyForm.SiteFloor;
begin
  with FOpen do
    Dispatch;
end;

end.