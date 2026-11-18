program SearchParseTests;
{$APPTYPE CONSOLE}
uses
  System.SysUtils,
  DragLint.Plugin.SearchParse in '..\..\src\delphi-plugin\DragLint.Plugin.SearchParse.pas';
var
  GFail: Integer = 0;
procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then Writeln('PASS ', AName)
  else begin Writeln('FAIL ', AName); Inc(GFail); end;
end;
const
  NAME_JSON =
    '[{"id":577,"kind":"method","name":"SearchText","qualified_name":"DRagLint.Core.Interfaces.ISymbolStore.SearchText",' +
    '"file":"C:\\p\\Interfaces.pas","start_line":144},' +
    '{"id":2416,"kind":"method","name":"SearchText","qualified_name":"X.SearchText","file":"C:\\p\\SQLite.pas","start_line":78}]';
  TEXT_JSON =
    '[{"file_path":"C:\\p\\DockForm.pas","start_line":209,"source":"pas","kind":"literal","text":"Find Usages","enclosing":"X"}]';
  USAGES_JSON =
    '{"name":"SearchText","width":"narrow",' +
    '"declarations":[{"kind":"method","qname":"X.SearchText","file":"C:\\p\\I.pas","line":144}],' +
    '"reads":[],"writes":[],"calls":[{"file":"C:\\p\\CLI.pas","line":2023,"col":21}],' +
    '"types":[],"attributes":[],"events":[],"impact":[]}';
var
  R: TSearchRows;
begin
  R := ParseNameJson(NAME_JSON);
  Check('name: 2 rows', Length(R) = 2);
  Check('name: row0 category', (Length(R) > 0) and (R[0].Category = 'Symbol'));
  Check('name: row0 ColA', (Length(R) > 0) and (R[0].ColA = 'SearchText'));
  Check('name: row0 ColB kind', (Length(R) > 0) and (R[0].ColB = 'method'));
  Check('name: row0 line', (Length(R) > 0) and (R[0].Line = 144));
  Check('name: row0 file', (Length(R) > 0) and R[0].FilePath.EndsWith('Interfaces.pas'));

  R := ParseTextJson(TEXT_JSON);
  Check('text: 1 row', Length(R) = 1);
  Check('text: category', (Length(R) > 0) and (R[0].Category = 'Text'));
  Check('text: ColA text', (Length(R) > 0) and (R[0].ColA = 'Find Usages'));
  Check('text: ColB source', (Length(R) > 0) and (R[0].ColB = 'pas'));
  Check('text: line', (Length(R) > 0) and (R[0].Line = 209));

  R := ParseUsagesJson(USAGES_JSON);
  Check('usages: 2 rows (1 decl + 1 call)', Length(R) = 2);
  Check('usages: has Decl', (Length(R) > 0) and (R[0].Category = 'Decl'));
  Check('usages: has Call line 2023', (Length(R) > 1) and (R[1].Category = 'Call') and (R[1].Line = 2023));

  Check('kind: function is Method', KindMatchesFilter('function', 'Method'));
  Check('kind: class is NOT Method', not KindMatchesFilter('class', 'Method'));
  Check('kind: field is Field/Var', KindMatchesFilter('field', 'Field/Var'));
  Check('kind: Any matches anything', KindMatchesFilter('method', 'Any'));
  Check('kind: empty matches anything', KindMatchesFilter('const', ''));

  { BK-SCOPEUI B31: the Search page's 4-way scope and full-path Location column }
  Check('scope: index 0 = symbol', SearchScopeWord(0) = 'symbol');
  Check('scope: index 1 = project', SearchScopeWord(1) = 'project');
  Check('scope: index 2 = group', SearchScopeWord(2) = 'group');
  Check('scope: index 3 = everywhere', SearchScopeWord(3) = 'everywhere');
  Check('scope: -1 falls back to project', SearchScopeWord(-1) = 'project');
  Check('scope: 9 falls back to project', SearchScopeWord(9) = 'project');
  Check('scope args: project', SearchUsagesScopeArgs(1, 'C:\g.groupproj') = ' --scope project');
  Check('scope args: symbol', SearchUsagesScopeArgs(0, '') = ' --scope symbol');
  Check('scope args: everywhere', SearchUsagesScopeArgs(3, '') = ' --scope everywhere');
  Check('scope args: group names the group file', SearchUsagesScopeArgs(2, 'C:\g.groupproj') = ' --scope group --group "C:\g.groupproj"');
  Check('scope args: group without a file has no --group', SearchUsagesScopeArgs(2, '') = ' --scope group');
  Check('location: full path and line', SearchLocationText('C:\p\CLI.pas', 2023) = 'C:\p\CLI.pas:2023');
  Check('location: not navigable is empty', SearchLocationText('C:\p\CLI.pas', 0) = '');
  Check('scope note: read from the answer', ParseUsagesScopeNote('{"scope":"project","scope_note":"no position binds a symbol"}') = 'no position binds a symbol');
  Check('scope note: absent is empty', ParseUsagesScopeNote(USAGES_JSON) = '');
  Check('scope note: not JSON is empty', ParseUsagesScopeNote('ERROR x') = '');
  if GFail > 0 then begin Writeln(GFail, ' FAILED'); Halt(1); end
  else Writeln('searchparse: all pass');
end.
