unit DRagLint.Refactor.TestStub;

interface

uses
  System.SysUtils
  , System.Classes
  , System.RegularExpressions
  , DRagLint.Core.Model
  , DRagLint.Core.Interfaces
  ;

type
  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoGenerateTest (DRagLint.CLI.pas), declaration (DRagLint.Refactor.TestStub.pas), DRagLint.Refactor.TestStub.TTestStubGenerator.Generate (DRagLint.Refactor.TestStub.pas)
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTestFramework = (tfDUnitX, tfDUnit);

  /// <remarks>
  /// <!-- drag-lint:auto BEGIN -->
  /// Used by: DRagLint.CLI.DoGenerateTest (DRagLint.CLI.pas)
  /// Used in units: DRagLint.CLI
  /// <!-- drag-lint:auto END -->
  /// </remarks>
  TTestStubGenerator = class
    public
      /// <param name="AStore"><!-- drag-lint:auto type -->const ISymbolStore</param>
      /// <param name="AQName"><!-- drag-lint:auto type -->const string</param>
      /// <param name="AFramework"><!-- drag-lint:auto type -->TTestFramework</param>
      /// <returns><!-- drag-lint:auto -->Observed: ''; Sb.ToString.</returns>
      /// <remarks>
      /// <!-- drag-lint:auto BEGIN -->
      /// Called from: DRagLint.CLI.DoGenerateTest (DRagLint.CLI.pas)
      /// Calls: DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName, DRagLint.Refactor.TestStub.TSG_LastSegment, DRagLint.Refactor.TestStub.TSG_SecondLastSegment
      /// Pure
      /// <seealso cref="DRagLint.Core.Interfaces.ISymbolStore.FindSymbolsByQualifiedName"/>
      /// <seealso cref="DRagLint.Refactor.TestStub.TSG_LastSegment"/>
      /// <seealso cref="DRagLint.Refactor.TestStub.TSG_SecondLastSegment"/>
      /// <!-- drag-lint:auto END -->
      /// </remarks>
      class function Generate(const AStore: ISymbolStore; const AQName: string; AFramework: TTestFramework): string;
  end;

implementation

// ---------------------------------------------------------------------------
// Helpers (shared with DocStub -- duplicated here to keep unit standalone)
// ---------------------------------------------------------------------------

function TSG_LastSegment(const S: string; ASep: Char): string;
var
  DotPos: Integer;
begin
  DotPos:= LastDelimiter(ASep, S);
  if DotPos > 0 then Result:= Copy(S, DotPos + 1, MaxInt)
  else Result:= S;
end;

// SecondLastSegment: for "Unit.TClass.Method" returns "TClass".
// For two-segment names like "Unit.Method" returns "Unit".
function TSG_SecondLastSegment(const S: string; ASep: Char): string;
var
  Parts: TArray<string>;
begin
  Parts:= S.Split([ASep]);
  if Length(Parts) >= 2 then Result:= Parts[High(Parts) - 1]
  else Result:= '';
end;

// ---------------------------------------------------------------------------
// TTestStubGenerator
// ---------------------------------------------------------------------------

class function TTestStubGenerator.Generate(const AStore: ISymbolStore; const AQName: string; AFramework: TTestFramework): string;
var
  Syms         : TArray<TSymbol>;
  Sym          : TSymbol        ;
  ClassName    : string         ;
  MethodName   : string         ;
  TestClassName: string         ;
  Sb           : TStringBuilder ;
begin
  Result:= '';
  Syms:= AStore.FindSymbolsByQualifiedName(AQName);
  if Length(Syms) = 0 then Exit;
  Sym:= Syms[0];

  MethodName:= TSG_LastSegment      (AQName, '.');
  ClassName := TSG_SecondLastSegment(AQName, '.');
  if ClassName = '' then ClassName:= 'TSubject';

  // T<Class><Method>Tests, e.g. TWidgetComputeTests
  TestClassName:= 'T' + ClassName + MethodName + 'Tests';

  Sb:= TStringBuilder.Create;
  try
    case AFramework of
      tfDUnitX:
      begin
        // Interface part
        Sb.AppendLine('[TestFixture]');
        Sb.AppendLine(TestClassName + ' = class');
        Sb.AppendLine('public'  );
        Sb.AppendLine('  [Test]');
        Sb.AppendLine('  procedure Test_' + MethodName + '_HappyPath;');
        Sb.AppendLine('  [Test]');
        Sb.AppendLine('  procedure Test_' + MethodName + '_EdgeCases;');
        Sb.AppendLine('end;'          );
        Sb.AppendLine(''              );
        Sb.AppendLine('implementation');
        Sb.AppendLine(''              );
        // HappyPath body
        Sb.AppendLine('procedure ' + TestClassName + '.Test_' + MethodName + '_HappyPath;');
        Sb.AppendLine('var');
        Sb.AppendLine('  Subject: ' + ClassName + ';');
        Sb.AppendLine('begin');
        Sb.AppendLine('  Subject := ' + ClassName + '.Create;');
        Sb.AppendLine('  try');
        Sb.AppendLine('    Assert.AreEqual(0, Subject.' + MethodName + '(0), ''' + MethodName + ' happy path'');');
        Sb.AppendLine('  finally'        );
        Sb.AppendLine('    Subject.Free;');
        Sb.AppendLine('  end;'           );
        Sb.AppendLine('end;'             );
        Sb.AppendLine(''                 );
        // EdgeCases body
        Sb.AppendLine('procedure ' + TestClassName + '.Test_' + MethodName + '_EdgeCases;');
        Sb.AppendLine('begin'                );
        Sb.AppendLine('  // TODO: edge cases');
        Sb.Append    ('end;'                 );
      end; // case

      tfDUnit:
      begin
        // Interface part (published style)
        Sb.AppendLine(TestClassName + ' = class(TTestCase)');
        Sb.AppendLine('published');
        Sb.AppendLine('  procedure Test_' + MethodName + '_HappyPath;');
        Sb.AppendLine('  procedure Test_' + MethodName + '_EdgeCases;');
        Sb.AppendLine('end;'          );
        Sb.AppendLine(''              );
        Sb.AppendLine('implementation');
        Sb.AppendLine(''              );
        // HappyPath body
        Sb.AppendLine('procedure ' + TestClassName + '.Test_' + MethodName + '_HappyPath;');
        Sb.AppendLine('var');
        Sb.AppendLine('  Subject: ' + ClassName + ';');
        Sb.AppendLine('begin');
        Sb.AppendLine('  Subject := ' + ClassName + '.Create;');
        Sb.AppendLine('  try');
        Sb.AppendLine('    CheckEquals(0, Subject.' + MethodName + '(0), ''' + MethodName + ' happy path'');');
        Sb.AppendLine('  finally'        );
        Sb.AppendLine('    Subject.Free;');
        Sb.AppendLine('  end;'           );
        Sb.AppendLine('end;'             );
        Sb.AppendLine(''                 );
        // EdgeCases body
        Sb.AppendLine('procedure ' + TestClassName + '.Test_' + MethodName + '_EdgeCases;');
        Sb.AppendLine('begin'                );
        Sb.AppendLine('  // TODO: edge cases');
        Sb.Append    ('end;'                 );
      end; // begin
    end; // case
    Result:= Sb.ToString;
  finally
    Sb.Free;
  end; // try
end; // function

end.
