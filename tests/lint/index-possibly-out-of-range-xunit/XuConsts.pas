unit XuConsts;
{ Foreign constant arrays for tests\lint\index-possibly-out-of-range-xunit\XuUse.pas: their bounds
  reach the rule only through the index (lint --db). MscConst.pas:189 shape: subrange element type. }

interface

const
  NssDistConvert     : array [0 .. 4] of 0 .. 8   = (0, 1, 3, 7, 8)   ;
  NssConv: array [0 .. 4] of Integer = (0, 1, 3, 7, 8);
  Twice: array [0 .. 4] of Integer = (0, 1, 2, 3, 4);
  SevColor: array [0 .. 10] of Integer = (0, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3);
  QTab: array [1 .. 10] of Integer = (10, 15, 20, 25, 35, 50, 75, 100, 150, 200);
  Aql: array [1 .. 8] of Double = (0.01, 0.015, 0.025, 0.040, 0.065, 0.1, 0.15, 0.25);

implementation

end.