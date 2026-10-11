unit ChartsTests.CoreText;

{ Cases for DRagLint.Charts.Text, the pure text helpers ported from
  charts\src\Emit-Common.ps1. Each expected value is what the PowerShell
  function returns for the same input (spec P3/P4: the PS output is the
  reference); the case names the PS trap the port had to close. }

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCoreTextTests = class
  public
    [Test] procedure XmlTextEscapesFour;
    [Test] procedure UnitNameOfBlankIsUnknown;
    [Test] procedure ShortNameIsCaseBlindOnUnit;
    [Test] procedure RowHrefEscapesLikeUri;
    [Test] procedure TopRankedCountsHiddenSites;
    [Test] procedure TopRankedStripsNilRows;
    [Test] procedure DisclosureWording;
    [Test] procedure CommonRootLenAndZone;
  end;

implementation

uses
  System.SysUtils, System.Generics.Collections, DRagLint.Charts.Text;

const
  HREF_LINE = 12;
  CAP_TWO = 2;
  ROWS_FIVE = 5;
  HIDDEN_THREE = 3;
  SITES_HIDDEN = 12;   { rows 3,4,5 carry 3+4+5 sites }
  DISC_ROWS = 4;
  DISC_SITES = 9;
  ROOT_LEN = 3;        { C:\Proj\ORM3 }

type
  TSiteRow = class
  public
    Sites: Integer; // dl:ok public-field@8faf -- a test-only row object; the field IS the PS Sites property it stands in for
    constructor Create(pSites: Integer);
  end;

constructor TSiteRow.Create(pSites: Integer);
begin
  inherited Create;
  Sites:= pSites;
end;

procedure TCoreTextTests.XmlTextEscapesFour;
begin
  Assert.AreEqual('a &amp; b &lt;c&gt; &quot;d&quot; '#39'e'#39, XmlText('a & b <c> "d" '#39'e'#39));
  Assert.AreEqual('', XmlText(''));
  { & first, or the &lt; it produced would be escaped again }
  Assert.AreEqual('&amp;lt;', XmlText('&lt;'));
end;

procedure TCoreTextTests.UnitNameOfBlankIsUnknown;
begin
  Assert.AreEqual('(unknown)', UnitNameOf('   '));
  Assert.AreEqual('DRagLint.Core.Model', UnitNameOf('C:\Projects\src\core\DRagLint.Core.Model.pas')); // dl:ok hardcoded-absolute-path@5d1e -- synthetic test input: never touches the filesystem
  { .NET GetFileNameWithoutExtension splits on '/' too }
  Assert.AreEqual('uMain', UnitNameOf('C:/Projects/CLIENT/uMain.pas')); // dl:ok hardcoded-absolute-path@4a0e -- synthetic test input: never touches the filesystem
end;

procedure TCoreTextTests.ShortNameIsCaseBlindOnUnit;
begin
  Assert.AreEqual('TFoo.Bar', ShortName('uMain.TFoo.Bar', 'UMAIN'));
  Assert.AreEqual('uMainX.TFoo', ShortName('uMainX.TFoo', 'uMain'));
  Assert.AreEqual('uMain.TFoo', ShortName('uMain.TFoo', ''));
  Assert.AreEqual('', ShortName(' ', 'uMain'));
end;

procedure TCoreTextTests.RowHrefEscapesLikeUri;
begin
  Assert.AreEqual('draglint://open?file=C%3A%5CProjects%5CA%20B.pas&amp;line=12',
    RowHref('C:\Projects\A B.pas', HREF_LINE)); // dl:ok hardcoded-absolute-path@b7ee -- synthetic test input: never touches the filesystem
  { RFC 3986 unreserved survive; everything else is %XX, uppercase hex }
  Assert.AreEqual('draglint://open?file=aZ09-_.~%2B%26%23%25&amp;line=0', RowHref('aZ09-_.~+&#%', 0));
end;

procedure TCoreTextTests.TopRankedCountsHiddenSites;
var
  Rows: TArray<Integer>;
  R   : TRanked<Integer>;
begin
  Rows:= [1, 2, 3, 4, 5]; // dl:ok magic-literal@17b0 -- the ranked rows themselves; each row is its own site count
  R:= TRanked<Integer>.TopRanked(Rows, CAP_TWO, function(pRow: Integer): Integer begin Result:= pRow; end);
  Assert.AreEqual(ROWS_FIVE, R.Total);
  Assert.AreEqual(CAP_TWO, Integer(Length(R.Shown)));
  Assert.AreEqual(2, R.Shown[1]);
  Assert.AreEqual(HIDDEN_THREE, R.HiddenRows);
  Assert.AreEqual(SITES_HIDDEN, R.HiddenSites);
  { cap 0 shows everything and hides nothing }
  R:= TRanked<Integer>.TopRanked(Rows, 0, nil);
  Assert.AreEqual(ROWS_FIVE, Integer(Length(R.Shown)));
  Assert.AreEqual(0, R.HiddenRows);
  { no site counter -> rows are hidden but no sites are counted }
  R:= TRanked<Integer>.TopRanked(Rows, CAP_TWO, nil);
  Assert.AreEqual(HIDDEN_THREE, R.HiddenRows);
  Assert.AreEqual(0, R.HiddenSites);
end;

procedure TCoreTextTests.TopRankedStripsNilRows;
var
  A, B: TSiteRow;
  R   : TRanked<TSiteRow>;
begin
  A:= TSiteRow.Create(1);
  B:= TSiteRow.Create(HIDDEN_THREE);
  try
    R:= TRanked<TSiteRow>.TopRanked([nil, A, nil, B], 1,
      function(pRow: TSiteRow): Integer begin Result:= pRow.Sites; end);
    Assert.AreEqual(2, R.Total, '$null rows vanish before counting');
    Assert.AreSame(A, R.Shown[0]);
    Assert.AreEqual(1, R.HiddenRows);
    Assert.AreEqual(HIDDEN_THREE, R.HiddenSites);
  finally
    B.Free;
    A.Free;
  end;
end;

procedure TCoreTextTests.DisclosureWording;
begin
  Assert.AreEqual('', DisclosureText(0, DISC_SITES));
  Assert.AreEqual('+4 more routines not shown', DisclosureText(DISC_ROWS, 0));
  Assert.AreEqual('+4 more routines (+9 more sites) not shown', DisclosureText(DISC_ROWS, DISC_SITES));
  Assert.AreEqual('+4 more tables not shown', DisclosureText(DISC_ROWS, 0, 'tables'));
end;

procedure TCoreTextTests.CommonRootLenAndZone;
var
  Len: Integer;
begin
  { case differs and a duplicate and a blank are present: PS Sort-Object -Unique
    and -eq are both case-insensitive, so 'orm3' and 'ORM3' are one segment }
  Len:= CommonRootLen(['C:\Proj\ORM3\CLIENT', 'c:\proj\orm3\COMMON\OBJECTS', '', 'C:\Proj\ORM3\CLIENT', // dl:ok hardcoded-absolute-path@483f -- synthetic test input: never touches the filesystem
    'C:\PROJ\ORM3']); // dl:ok hardcoded-absolute-path@2882 -- synthetic test input: never touches the filesystem
  Assert.AreEqual(ROOT_LEN, Len);
  Assert.AreEqual('CLIENT', PathZone('C:\Proj\ORM3\CLIENT\uMain.pas', Len)); // dl:ok hardcoded-absolute-path@db86 -- synthetic test input: never touches the filesystem
  Assert.AreEqual('COMMON/OBJECTS', PathZone('C:\Proj\ORM3\COMMON\OBJECTS\uObj.pas', Len)); // dl:ok hardcoded-absolute-path@233d -- synthetic test input: never touches the filesystem
  Assert.AreEqual('(root)', PathZone('C:\Proj\ORM3\Micronite.dpr', Len)); // dl:ok hardcoded-absolute-path@6039 -- synthetic test input: never touches the filesystem
  Assert.AreEqual('(root)', PathZone('C:\Proj\ORM3\CLIENT\uMain.pas', 0)); // dl:ok hardcoded-absolute-path@8723 -- synthetic test input: never touches the filesystem
  Assert.AreEqual('(unknown)', PathZone('', Len));
  Assert.AreEqual(0, CommonRootLen(['C:\A', 'D:\A'])); // dl:ok hardcoded-absolute-path@3295 -- synthetic test input: never touches the filesystem
  Assert.AreEqual(0, CommonRootLen([]));
end;

end.
