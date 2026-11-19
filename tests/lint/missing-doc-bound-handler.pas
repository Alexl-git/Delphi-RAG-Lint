unit MissingDocBoundHandler;

// Fixture for lane v152 DOCPOL (ruling B2). No .expected: run_lint_tests.ps1 skips it
// (missing-doc needs the store); tests\autotest\run_v152_DOCPOL.ps1 drives it through lint-all.
//   Button1Click -- bound by the .dfm, body has code     -> FLAGGED (reverses the 1.51.1 R2c skip)
//   Button2Click -- bound by the .dfm, body EMPTY        -> NOT flagged
//   Plain        -- not bound, no doc                    -> FLAGGED (positive control)

interface

type
  /// <summary>Form of the fixture.</summary>
  TFrm = class
  published
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure Plain;
  end;

implementation

procedure TFrm.Button1Click(Sender: TObject);
begin
  Plain;
end;

procedure TFrm.Button2Click(Sender: TObject);
begin
  // nothing yet
end;

procedure TFrm.Plain;
begin
  // helper
end;

end.
