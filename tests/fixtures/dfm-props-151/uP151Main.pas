unit uP151Main;
interface
uses
  System.Classes, Vcl.Forms, Vcl.StdCtrls, Vcl.ActnList, Vcl.ComCtrls, Vcl.ExtCtrls,
  uP151Dlg, uP151Act, uP151Child, uP151Mdi, uP151Hooks;
type
  TfrmP151Main = class(TForm)
    btnOpen: TButton;
    btnAct: TButton;
    btnMdi: TButton;
    alMain: TActionList;
    actDlg: TAction;
    actOth: TAction;
    actChild: TAction;
    lstMain: TListBox;
    sbMain: TStatusBar;
    imgMain: TImage;
    btnHelp: TButton;
    btnHelp2: TButton;
    alHelp: TActionList;
    actHelp2: TAction;
    procedure btnOpenClick(Sender: TObject);
    procedure actDlgExecute(Sender: TObject);
    procedure actChildExecute(Sender: TObject);
    procedure btnMdiClick(Sender: TObject);
    procedure btnHelpClick(Sender: TObject);
    procedure btnHelp2Click(Sender: TObject);
  private
    FGo: procedure of object;
    procedure DoHelp;
    procedure DoHelp2;
  end;
var
  frmP151Main: TfrmP151Main;
implementation
{$R *.dfm}
procedure TfrmP151Main.btnOpenClick(Sender: TObject);
begin
  TfrmP151Dlg.Create(Self).ShowModal;
end;
procedure TfrmP151Main.actDlgExecute(Sender: TObject);
begin
  TfrmP151Act.Create(Self).ShowModal;
end;
procedure TfrmP151Main.actChildExecute(Sender: TObject);
begin
  TfrmP151Child.Create(Self);
end;
procedure TfrmP151Main.btnMdiClick(Sender: TObject);
begin
  TfrmP151Mdi.Create(Self);
end;
{ the helpers run through a method pointer: no call edge, so forms-csv's text walk (CaptionForHandler) names the control }
procedure TfrmP151Main.btnHelpClick(Sender: TObject);
begin
  FGo:= DoHelp;
  FGo;
end;
procedure TfrmP151Main.btnHelp2Click(Sender: TObject);
begin
  FGo:= DoHelp2;
  FGo;
end;
{ the dialogs open through registered hooks (uP151Hooks): the index explains no Main ->
  Help pair, forms-csv's text edge does, with the caption CaptionForHandler reads }
procedure TfrmP151Main.DoHelp;
begin
  HelpHook();
end;
procedure TfrmP151Main.DoHelp2;
begin
  Help2Hook();
end;
end.