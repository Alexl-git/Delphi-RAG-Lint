program FieldsNoCtor;

{ check-init fixture fields-noctor (lane HBFIELDS): TPlain declares no constructor, so FValue (set in Load)
  is MAY with no-declared-ctor; FNever has no writer at all (NEVER-SET); TPlain2 declares one that sets
  FValue (the SET twin). }

uses
  fnPlain in 'fnPlain.pas';

begin
  TPlain.Create.Show;
  TPlain2.Create.Show;
end.