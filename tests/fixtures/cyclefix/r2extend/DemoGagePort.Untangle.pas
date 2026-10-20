unit DemoGagePort.Untangle;

// E18 T6 fixture r2extend: an existing leaf of DemoGagePort that uses no unit of
// the cycle. Recipe R2 inserts the extracted interface after TDemoGageUnit,
// inside this type block, and adds the uses clause the interface needs.

interface

type
  /// <summary>The unit a gage reads in.</summary>
  TDemoGageUnit = (guMillimetre, guInch);

implementation

end.