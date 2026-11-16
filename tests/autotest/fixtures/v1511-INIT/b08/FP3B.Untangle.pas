unit FP3B.Untangle;

// Created by `drag-lint cycles --plan`: declarations moved here from FP3B
// to break a circular unit dependency. This unit may use only units OUTSIDE
// that cycle -- never FP3A, FP3B, FP3C.

interface

type
  /// <summary>Signature of FP3BReport (FP3B), copied verbatim.</summary>
  TFP3BReportPtr = procedure(const pText: string);

var
  /// <summary>Holds FP3BReport, assigned by FP3B in its initialization section; the units of its former cycle call it instead of naming the routine.</summary>
  FP3BReportPtr: TFP3BReportPtr;

implementation

end.
