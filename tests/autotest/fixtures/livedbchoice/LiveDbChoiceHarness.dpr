program LiveDbChoiceHarness;

{ T-05: pins DragLint.Plugin.LiveDbChoice. Prints one "PASS <name>" or
  "FAIL <name> -- <detail>" line per case and exits 1 on any failure. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils
  , DragLint.Plugin.LiveDbChoice in '..\..\..\..\src\delphi-plugin\DragLint.Plugin.LiveDbChoice.pas'
  ;

const
  CClient = 'C:\P\ORM3\CLIENT\_D-RAG\Micronite2027.sqlite';
  CServer = 'C:\P\ORM3\SERVER\_D-RAG\MicroniteMW1Service.sqlite';
  CTester = 'C:\P\ORM3\TESTER\_D-RAG\TEST.sqlite';
  COther  = 'C:\P\Other\_D-RAG\Other.sqlite';

var
  GFailed: Boolean = False;

function Join(const A: TArray<string>): string;
begin
  Result:= '[' + string.Join('|', A) + ']';
end;

procedure Check(const AName: string; const AGot, AWant: TArray<string>);
begin
  if Join(AGot) = Join(AWant) then Writeln('PASS ', AName)
  else
  begin
    Writeln('FAIL ', AName, ' -- got ', Join(AGot), ' want ', Join(AWant));
    GFailed:= True;
  end;
end;

begin
  { ChooseLiveLintDbs }
  Check('single-owner file -> that DB',
    ChooseLiveLintDbs([CClient], CServer, COther), [CClient]);
  Check('shared unit, active project among candidates -> active DB',
    ChooseLiveLintDbs([CClient, CServer, CTester], CServer, ''), [CServer]);
  Check('active DB matches case-insensitively',
    ChooseLiveLintDbs([CClient, CServer], UpperCase(CServer), ''), [UpperCase(CServer)]);
  Check('active not a candidate, declared owner is -> owner',
    ChooseLiveLintDbs([CClient, CServer, CTester], COther, CTester), [CTester]);
  Check('shared unit, no tiebreak -> ALL candidates, not empty',
    ChooseLiveLintDbs([CClient, CServer, CTester], COther, ''), [CClient, CServer, CTester]);
  Check('no candidates, declared owner known -> owner',
    ChooseLiveLintDbs([], CServer, COther), [COther]);
  Check('nothing known -> empty',
    ChooseLiveLintDbs([], CServer, ''), []);

  { ParseResolveDbsJson }
  Check('parse: stderr note before the array',
    ParseResolveDbsJson('(loaded defaults from C:\Projects\.drag-lint.json)'#13#10
      + '["C:\\P\\A.sqlite","C:\\P\\B.sqlite"]'#13#10), ['C:\P\A.sqlite', 'C:\P\B.sqlite']);
  Check('parse: empty array spliced into a note -> empty',
    ParseResolveDbsJson('NOTE: no index covers X.pas -- no manifest section includes it[]'#13#10
      + ' or its folder.'), []);
  Check('parse: no JSON at all -> empty',
    ParseResolveDbsJson('ERROR: something'), []);

  if GFailed then ExitCode:= 1;
end.
