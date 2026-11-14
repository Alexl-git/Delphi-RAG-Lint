unit DunitxTestWithoutAssert;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TImportTests = class
  public
    [Test]
    procedure EmptyFileIsRead;
    [Test]
    procedure ChecksDirectly;
    [Test]
    procedure ChecksViaHelper;
    [Test]
    [WillRaise(EInvalidOp)]
    procedure RaisesExpected;
    [Test]
    [Ignore('later')]
    procedure Postponed;
    [TestCase('a', '1')]
    procedure CaseWithoutCheck(AValue: Integer);
    procedure Helper;
  end;

implementation

procedure Load;
begin
end;

procedure TImportTests.Helper;
begin
  Assert.AreEqual(1, 1);
end;

procedure TImportTests.EmptyFileIsRead;
begin
  Load;
end;

procedure TImportTests.ChecksDirectly;
begin
  Assert.IsTrue(True);
end;

procedure TImportTests.ChecksViaHelper;
begin
  Helper;
end;

procedure TImportTests.RaisesExpected;
begin
  raise EInvalidOp.Create('x');
end;

procedure TImportTests.Postponed;
begin
  Load;
end;

procedure TImportTests.CaseWithoutCheck(AValue: Integer);
begin
  Load;
end;

end.
