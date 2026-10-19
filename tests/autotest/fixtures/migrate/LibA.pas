unit LibA;

interface

uses
  Classes;

type
  TSrcBtn = class(TPersistent)
  private
    FCaption: string;
    FHint: string;
    FOnClick: TNotifyEvent;
  public
    procedure Click;
    function Count: Integer;
  published
    property Caption: string read FCaption write FCaption;
    property Hint: string read FHint write FHint;
    property OnClick: TNotifyEvent read FOnClick write FOnClick;
  end;

implementation

procedure TSrcBtn.Click;
begin
end;

function TSrcBtn.Count: Integer;
begin
  Result:= 0;
end;

end.
