unit CurPlat;

{ Stands for TODAY's platform: TPlatCursor lost pcrSQLWait / pcrOther and gained pcrAdded;
  TGoneCursor is gone; the migration targets live here. }

interface

type
  TPlatCursor = (pcrDefault, pcrHourGlass, pcrAdded);
  TNewCursor = (ncrNone, ncrDefault, ncrHourGlass, ncrSQLWait, ncrAdded);
  TNewGone = (ngnWait, ngnBusy);

implementation

end.
