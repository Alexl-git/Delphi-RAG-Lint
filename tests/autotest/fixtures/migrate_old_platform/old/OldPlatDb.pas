unit OldPlatDb;

{ Stands for the OLD platform (a Delphi 5 Db.pas): indexed into its own library DB. }

interface

type
  TPlatCursor = (pcrDefault, pcrHourGlass, pcrSQLWait, pcrOther);
  TGoneCursor = (gcoWait, gcoBusy);
  TOnlyInOld = (oioA, oioB);

implementation

end.
