unit LabExcHost;

interface

uses
  System.SysUtils, LabExcWidget;

procedure LabExcFire(pTarget: TObject);

implementation

procedure LabExcFire(pTarget: TObject);
begin
  try
    (pTarget as TLabExcWidget).Touch;
  except
    on EInvalidCast do
      Writeln('[exc] not a widget');
  end;
end;

end.
