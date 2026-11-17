unit CastWrite;

interface

type
  TGreeting = class
  private
    FReplaced: Boolean;
    FNever   : Boolean;
  public
    function IsReplaced: Boolean;
    function IsNever: Boolean;
  end;

  TController = class
  public
    procedure Replace(AOld: TObject);
  end;

implementation

function TGreeting.IsReplaced: Boolean;
begin
  Result:= FReplaced;
end;

function TGreeting.IsNever: Boolean;
begin
  Result:= FNever;
end;

procedure TController.Replace(AOld: TObject);
var
  LOld: TObject;
begin
  LOld:= AOld;
  TGreeting(LOld).FReplaced:= True;
end;

end.