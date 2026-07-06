unit since;

// Fixture for run_doc_since.ps1 -- the <since> doc-source (git-derived, opt-in).
// TSvc.DoIt calls Helper(..) (PARENTHESIZED call site) so the facts builder
// registers a Calls fact -> the facts-only default keeps the managed block, so
// the <since> line has somewhere to render. The <since> date is derived from
// the git commit that introduced DoIt's declaration line; with --since ON and
// the file committed in a git repo, a /// <since>YYYY-MM-DD</since> line is
// emitted inside the managed fence. With no git repo, nothing is emitted.

interface

type
  TSvc = class
  public
    procedure DoIt;
    procedure Helper(AValue: Integer);
  end;

implementation

procedure TSvc.DoIt;
begin
  Helper(1);
end;

procedure TSvc.Helper(AValue: Integer);
begin
  Writeln(AValue);
end;

end.
