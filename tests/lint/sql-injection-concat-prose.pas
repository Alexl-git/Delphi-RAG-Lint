unit SqlConcatProse;

interface

implementation

uses
  System.SysUtils;

procedure P(V: string);
var
  S: string;
begin
  // A UI confirmation that starts with the English verb "Delete" and carries a
  // plural marker "(s)" -- not SQL. Filed 2026-09-28 against ConvRules.MainForm.
  S := Format('Delete %d unit rule(s) and dismiss %d unit(s)?' + sLineBreak + '%s', [1, 2, V]);
  S := 'Update the list (optional) now? ' + V;
end;

end.
