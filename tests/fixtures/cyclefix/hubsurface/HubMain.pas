unit HubMain;

interface

uses
  System.Classes, System.SysUtils;

type
  THubMain = class(TComponent)
    Log: TStringList;
  public
    Counter: Integer;
    Mark: Char;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Note(const pText: string; pLevel: Integer = 0);
    function Ready: Boolean;
  end;

var
  HubMainForm: THubMain;

procedure HubStamp(const pTag: string);
procedure Run;

implementation

uses
  HubSpokeA, HubSpokeB, HubSpokeC;

constructor THubMain.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Log:= TStringList.Create;
end;

destructor THubMain.Destroy;
begin
  Log.Free;
  inherited Destroy;
end;

procedure THubMain.Note(const pText: string; pLevel: Integer);
begin
  Log.Add(StringOfChar(' ', pLevel * 2) + pText);
end;

function THubMain.Ready: Boolean;
begin
  Result:= Counter > 0;
end;

procedure HubStamp(const pTag: string);
begin
  Writeln('stamp ', pTag);
end;

procedure Run;
begin
  HubMainForm:= THubMain.Create(nil);
  try
    SpokeA;
    SpokeB;
    SpokeC;
    Write(HubMainForm.Log.Text);
  finally
    HubMainForm.Free;
  end;
end;

end.
