unit uIndForm;

{ 1.56 EXT-C2 fixture: event handlers bound in the .dfm, a library event bound in code, and a
  component class of the index whose event the .dfm binds (TIndPanel.OnPing). Pinned by
  tests\autotest\run_v156_EXTC2_indirect.ps1 -- append only. }

interface

uses
  System.Classes, Vcl.Forms, Vcl.StdCtrls, Vcl.Controls;

type
  TIndPanel = class(TComponent)
  private
    FOnPing: TNotifyEvent;
  public
    procedure Ping;
  published
    property OnPing: TNotifyEvent read FOnPing write FOnPing;
  end;

  TIndForm = class(TForm)
    Button1: TButton;
    Button2: TButton;
    Panel1: TIndPanel;
    procedure Button1Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure PanelPing(Sender: TObject);
  private
    procedure NotWired(Sender: TObject);
  end;

var
  IndForm: TIndForm;

implementation

{$R *.dfm}

procedure TIndPanel.Ping;
begin
  if Assigned(FOnPing) then FOnPing(Self);
end;

procedure TIndForm.Button1Click(Sender: TObject);
begin
end;

procedure TIndForm.FormCreate(Sender: TObject);
begin
  Button2.OnClick:= Button1Click;
end;

procedure TIndForm.PanelPing(Sender: TObject);
begin
end;

procedure TIndForm.NotWired(Sender: TObject);
begin
end;

end.
