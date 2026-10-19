unit LibB;

interface

uses
  Classes;

type
  TDstBtn = class(TPersistent)
  private
    FCaption: string;
    FOnPress: TNotifyEvent;
  public
    procedure Press;
  published
    property Caption: string read FCaption write FCaption;
    property OnPress: TNotifyEvent read FOnPress write FOnPress;
  end;

implementation

procedure TDstBtn.Press;
begin
end;

end.
