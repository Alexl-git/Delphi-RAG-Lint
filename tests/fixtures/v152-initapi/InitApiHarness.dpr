program InitApiHarness;

{ v152 lane INITAPI: console harness for ProgramInitOrders and InitializesBefore (DRagLint.Lint.InitSections).
  Usage: InitApiHarness <db> [<program>:<unitA>:<unitB> ...]
  Prints one line per program: `ORDER|<program>|<unreliable 0/1>|<reason>|<block yes/no>|<unit,unit,...>`,
  then one line per question: `PAIR|<program>|<A>|<B>|<unplaced|before|not-before|config-dependent>|<text>`. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DRagLint.Core.Model          in '..\..\..\src\core\DRagLint.Core.Model.pas',
  DRagLint.Core.Interfaces     in '..\..\..\src\core\DRagLint.Core.Interfaces.pas',
  DRagLint.Storage.SQLite      in '..\..\..\src\storage\DRagLint.Storage.SQLite.pas',
  DRagLint.Lint.InitSections   in '..\..\..\src\lint\DRagLint.Lint.InitSections.pas';

const
  ANSWER_NAMES: array[TInitOrderAnswer] of string = ('unplaced', 'before', 'not-before', 'config-dependent');

begin
  var Store: ISymbolStore:= TSQLiteSymbolStore.Create(ParamStr(1));
  for var O: TProgramInitOrder in ProgramInitOrders(Store) do
  begin
    var Names: string:= '';
    for var U: TProgramInitUnit in O.Units do
      Names:= Names + (if Names = '' then '' else ',') + U.Name;
    Writeln(Format('ORDER|%s|%d|%s|%s|%s', [O.ProgramName, Ord(O.Unreliable), O.UnreliableReason,
      (if O.ProgramBlockId > 0 then 'yes' else 'no'), Names]));
  end;
  for var I: Integer:= 2 to ParamCount do
  begin
    var Parts: TArray<string>:= ParamStr(I).Split([':']);
    if Length(Parts) <> 3 then Continue;
    var V: TInitOrderVerdict:= InitializesBefore(Store, Parts[0], Parts[1], Parts[2]);
    Writeln(Format('PAIR|%s|%s|%s|%s|%s', [Parts[0], Parts[1], Parts[2], ANSWER_NAMES[V.Answer], V.Text]));
  end;
end.
