unit uFinUser;

{ v156 HB6 fixture: the users of uFinRes' globals. }

interface

type
  TNode = class
  public
    destructor Destroy; override;
  end;

procedure Work;
procedure Farewell;

implementation

uses
  uFinRes;

destructor TNode.Destroy;
begin
  GCache.Add('gone');
  inherited;
end;

procedure Work;
var
  Node: TNode;
begin
  Node := TNode.Create;
  Node.Free;
  GPlain.Add('work');
  GHelper.Add('work');
  Log('work');
end;

procedure Farewell;
begin
  GLate.Add('bye');
end;

initialization

finalization
  Farewell;
end.
