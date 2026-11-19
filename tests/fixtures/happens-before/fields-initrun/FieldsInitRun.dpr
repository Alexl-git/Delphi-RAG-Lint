program FieldsInitRun;

{ check-init fixture fields-initrun (lane HBFIELDS): the Init/Run pattern. TRunner.Init sets FQueue but no
  constructor calls it (MAY, writer list "not called by every constructor"); TRunner2.Create calls Init
  (the SET twin); TRunner2.Reset writes nil (the limits line names it); TRunner2.Destroy frees it (nil-safe)
  and reads it (the destructor also runs when a constructor raised before the write). }

uses
  fiRunner in 'fiRunner.pas';

var
  R: TRunner;
  R2: TRunner2;

begin
  R:= TRunner.Create;
  R.Init;
  R.Run;
  R2:= TRunner2.Create;
  R2.Run;
  R2.Reset;
  R2.Free;
end.