unit UMain;

{ Fixture for lane v151 EXCL: the unit the program lists. It reaches UHelper
  and ExtU through uses (both unlisted), names UGlob only inside an inactive
  conditional branch, looks a class up by name, and owns a local record that
  happens to share its name with the unrelated unit Cfg. }

interface

procedure Run;

implementation

uses
  System.Classes,
  UHelper,
  ExtU
  {$IFDEF EXTRA_GLOBAL}
  , UGlob
  {$ENDIF}
  ;

type
  TCfgRec = record
    Value: Integer;
  end;

procedure Run;
var
  Cfg: TCfgRec;
  C  : TPersistentClass;
  S  : string;
begin
  S:= 'UOrphan.TOrphan is text, not a link';
  Cfg.Value:= HelperValue + ExtValue + Length(S);
  C:= GetClass('TPlugin');
  if C = nil then Cfg.Value:= 0;
  {$IFDEF EXTRA_GLOBAL}
  UGlob.GlobalCounter:= Cfg.Value;
  {$ENDIF}
end;

end.
