unit DemoAudit.Untangle;

// E18 T4b fixture: an EXISTING leaf unit for DemoAudit, holding an unrelated
// enum and used by no unit of the DemoAudit cycle. `cycles --plan` must insert
// the declarations it moves out of DemoAudit HERE instead of creating a new
// unit. It uses only RTL units, so it is still a leaf for that cycle.

interface

uses
  System.SysUtils;

type
  /// <summary>Where an audit line is written; unrelated to the cycle.</summary>
  TDemoAuditChannel = (acFile, acConsole);

implementation

end.
