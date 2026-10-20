unit CfAlpha;

// E18 T3a fixture: the implementation uses clause has a comment line between
// entries and a trailing comment after the semicolon (DemoAudit.pas /
// Regions.pas shapes). A uses-clause edit must keep both comments.

interface

/// <summary>Twice CfBeta's limit.</summary>
function AlphaTotal: Integer;

implementation

uses
  System.SysUtils,
  // CfBeta supplies the limit
  CfBeta; // why: the limit lives there

function AlphaTotal: Integer;
begin
  Result:= CBetaLimit * 2;
end;

end.