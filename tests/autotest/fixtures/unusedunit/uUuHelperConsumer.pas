unit uUuHelperConsumer;

{ Fixture: the false positive itself.

  Every name this unit references from its two imports is a TYPE HELPER MEMBER:
    ZzShout  -- TZzStringHelper, declared in uUuHelpProvider (project-local)
    ToUpper  -- TStringHelper,   declared in System.SysUtils  (library index)
  Neither import's own TYPE is named anywhere here, so before the helper read
  both units were reported as dead imports. Removing either one fails to
  compile with E2003/E2671. }

interface

uses
  uUuHelpProvider, System.SysUtils;

function ZzDescribe(const AText: string): string;

implementation

function ZzDescribe(const AText: string): string;
begin
  Result:= AText.ZzShout + AText.ToUpper;
end;

end.
