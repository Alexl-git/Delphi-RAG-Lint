program RootsHarness;

{ v152 lane HBROOTS: console harness for LoadRoots and THbEscapeClassifier
  (DRagLint.Query.HappensBefore.Roots). Usage: RootsHarness <db> [<QName> ...]
  Prints one line per program: `CHAIN|<program>|<unreliable 0/1>|<reason>|<display>;<display>;...`,
  one line per chain link: `ROOT|<program>|<display>|<escape class of the link>`,
  then one line per QName: `ESC|<QName>|<escape class>` (`<missing>` / `<ambiguous>` when the QName
  does not name exactly one symbol). }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DRagLint.Core.Model,
  DRagLint.Core.Interfaces,
  DRagLint.Storage.SQLite,
  DRagLint.Query.HappensBefore.Roots;

begin
  var Store: ISymbolStore:= TSQLiteSymbolStore.Create(ParamStr(1), {AReadOnly=}True);
  var Classifier:= THbEscapeClassifier.Create(Store);
  try
    for var C: THbRootChain in LoadRoots(Store).Chains do
    begin
      var Names: string:= '';
      for var R: THbOrderedRoot in C.Roots do
        Names:= Names + (if Names = '' then '' else ';') + R.Display;
      Writeln(Format('CHAIN|%s|%d|%s|%s', [C.ProgramName, Ord(C.Unreliable), C.UnreliableReason, Names]));
      for var R: THbOrderedRoot in C.Roots do
        Writeln(Format('ROOT|%s|%s|%s', [C.ProgramName, R.Display, EscapeClassCode(Classifier.ClassOf(R.SymbolId))]));
    end;
    for var I: Integer:= 2 to ParamCount do
    begin
      var Syms: TArray<TSymbol>:= Store.FindSymbolsByQualifiedName(ParamStr(I));
      var Cls: string:= if Length(Syms) = 0 then '<missing>'
        else if Length(Syms) > 1 then '<ambiguous>'
        else EscapeClassCode(Classifier.ClassOf(Syms[0].Id));
      Writeln(Format('ESC|%s|%s', [ParamStr(I), Cls]));
    end;
  finally
    Classifier.Free;
  end;
end.