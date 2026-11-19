program FieldsEscape;

{ check-init fixture fields-escape (lane HBFIELDS): TEsc.Create hands Self to Register BEFORE it sets
  FData (MAY, self-escapes-in-ctor); TEsc2.Create does it after the write (the SET twin). A constructor
  declared `overload` leaves the inherited TObject.Create callable on TOver (MAY, ctor-misses-field);
  TOver2 is the same class without `overload` (SET). }

uses
  feEsc in 'feEsc.pas';

begin
  TEsc.Create.Show;
  TEsc2.Create.Show;
  TOver.Create(1).Show;
  TOver2.Create(1).Show;
end.