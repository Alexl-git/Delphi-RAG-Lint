unit xt_app;

{ The PROJECT of the xtyped pair (item 4): uses xt_lib. P1-P9 / N1-N4 are the
  site labels of spec 2026-10-28-untypable-receivers s.7. }

interface

uses System.SysUtils, xt_lib;

type
  TAppStream = class(TLibStream)
  public
    procedure Own;
  end;

  TAppDup = class
  public
    procedure Anything;
  end;

var
  GArr: array [0 .. 3] of TAppStream;

procedure Go(S: TLibStream; A: TAppStream; D: TAppDup);

implementation

procedure TAppStream.Own; begin end;
procedure TAppDup.Anything; begin end;

procedure Go(S: TLibStream; A: TAppStream; D: TAppDup);
var
  X: string;
begin
  S.Read(X);
  S.Defs.Add('n');
  A.Pos := 1;
  A.Own;
  TLibEnc.UTF8.GetBytes('');
  LibApp.Base;
  GArr[1].Own;
  try
    X := '';
  except
    on E: ELibError do E.Base;
  end;
  LibFormat('x');
  D.Anything;
  Nowhere.Add('n');
  S.Missing;
  Exit;
end;

end.