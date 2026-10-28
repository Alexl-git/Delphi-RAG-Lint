unit ObjLeakAdder;

interface

implementation

uses
  System.SysUtils, System.JSON;

{ JRow is handed to JRows.AddElement, which OWNS it. The only path on which it
  is still open at the exit is the modelled mid-body exception edge into the
  typed handler -- not a missed Free. }
procedure ArrayAdder(UseJson: Boolean; N: Integer);
var
  JRows  : TJSONArray;
  JRow   : TJSONArray;
  c, r   : Integer;
  Failure: string;
begin
  JRows := nil;
  if UseJson then JRows := TJSONArray.Create;
  try
    try
      r := 0;
      while r < N do
      begin
        if UseJson then
        begin
          JRow := TJSONArray.Create;
          for c := 0 to N do JRow.AddElement(TJSONString.Create('x'));
          JRows.AddElement(JRow);
        end;
        Inc(r);
      end;
    except
      on E: Exception do
        Failure := E.Message;
    end;
  finally
    JRows.Free;
  end;
end;

{ same for AddPair on a TJSONObject receiver }
procedure PairAdder(N: Integer);
var
  Root   : TJSONObject;
  Sub    : TJSONObject;
  c      : Integer;
  Failure: string;
begin
  Root := TJSONObject.Create;
  try
    try
      for c := 0 to N do
      begin
        Sub := TJSONObject.Create;
        Sub.AddPair('n', TJSONString.Create('x'));
        Root.AddPair('sub', Sub);
      end;
    except
      on E: Exception do
        Failure := E.Message;
    end;
  finally
    Root.Free;
  end;
end;

{ POSITIVE CONTROL: Sub is only the RECEIVER of AddPair, never handed to an
  owner, so it really leaks. }
procedure Control;
var
  Sub: TJSONObject;
begin
  Sub := TJSONObject.Create;
  Sub.AddPair('a', 'b');
end;

end.
