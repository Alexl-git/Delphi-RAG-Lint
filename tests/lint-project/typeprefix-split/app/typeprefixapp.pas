unit typeprefixapp;

interface

uses
  typeprefixlib;

type
  EKeyViolation = class(EDatabaseError);   // B1: must NOT fire (library hop)
  KeyViolation  = class(EDatabaseError);   // B2: fires, message says "E" (positive control)
  EBase = class(EDatabaseError);           // B3a: no finding
  EDerived = class(EBase);                 // B3b: two-level chain, no finding
  Widget = class(TObject);                 // B4: fires with "T"
  EWidget = class(TLibThing);              // B5: fires with "T" (E is no exemption)
  Foo = class(TVendorThing);               // B6: unknown origin -> gap error
  Vendor = class(EVendorBase);             // B7: unknown origin -> gap error
  EVendor = class(EVendorBase);            // B8: unknown origin -> gap error
  Plain = class;                           // B9: fires with "T"
  Svc = interface end;                     // B10: fires with "I"
  Rec = record X: Integer; end;            // B11: fires with "T", message says Record

implementation

end.
