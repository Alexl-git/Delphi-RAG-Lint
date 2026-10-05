unit uGroups6;

interface

uses
  System.Classes, Vcl.Forms, Vcl.StdCtrls, Vcl.ActnList, uGroupEdit6, uLog6;

type
  TfrmGroups6 = class(TForm)
    btnEditGroup: TButton;
    lbGroups: TListBox;
    alGroups: TActionList;
    actOpenLog: TAction;
    procedure btnEditGroupClick(Sender: TObject);
    procedure lbGroupsDblClick(Sender: TObject);
    procedure actOpenLogExecute(Sender: TObject);
  end;

implementation

{$R *.dfm}

procedure TfrmGroups6.btnEditGroupClick(Sender: TObject);
begin
  TfrmGroupEdit6.Create(Self).ShowModal;
end;

procedure TfrmGroups6.lbGroupsDblClick(Sender: TObject);
begin
  actOpenLog.Execute;
end;

procedure TfrmGroups6.actOpenLogExecute(Sender: TObject);
begin
  TfrmLog6.Create(Self).Show;
end;

end.