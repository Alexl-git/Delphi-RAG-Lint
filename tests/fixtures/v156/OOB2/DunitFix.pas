unit DunitFix;

// dunitx-attribute-hygiene (G-26)

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]  // FIRE dunitx-attribute-hygiene
  TNoTests = class
  public
    procedure Helper;
  end;

  [TestFixture]
  TWithTests = class
  public
    [Test]
    procedure Works;
    [Test]
    procedure AlsoWorks;
  end;

  [TestFixture]
  TCasesOnly = class
  public
    [TestCase('a', '1')]
    [TestCase('b', '2')]
    procedure Cases(A: Integer);
  end;

  TBaseTests = class
  public
    [Test]
    procedure BaseTest;
  end;

  [TestFixture]
  TInheriting = class(TBaseTests)
  public
    procedure Own;
  end;

  [TestFixture]
  TConvention = class
  published
    procedure TestSomething;
  end;

  TNotAFixture = class
  public
    procedure Helper;
  end;

  [TestFixture]
  TIgnores = class
  public
    [Test]
    [Ignore]  // FIRE dunitx-attribute-hygiene
    procedure Bare;
    [Test]
    [Ignore('')]  // FIRE dunitx-attribute-hygiene
    procedure Empty;
    [Test]
    [Ignore('flaky on the build server')]
    procedure Reasoned;
  end;

  [TestFixture]
  [Ignore]  // FIRE dunitx-attribute-hygiene
  TIgnoredFixture = class
  public
    [Test]
    procedure One;
  end;

  [Ignore]
  TPlainIgnored = class
  public
    procedure One;
  end;

  [TestFixture]
  TTwice = class
  public
    [Setup]
    procedure PrepA;
    [Setup]  // FIRE dunitx-attribute-hygiene
    procedure PrepB;
    [TearDown]
    procedure DoneA;
    [TearDown]  // FIRE dunitx-attribute-hygiene
    procedure DoneB;
    [Test]
    procedure Works;
  end;

  [TestFixture]
  TOnceEach = class
  public
    [SetupFixture]
    procedure PrepAll;
    [Setup]
    procedure Prep;
    [TearDown]
    procedure Done;
    [TearDownFixture]
    procedure DoneAll;
    [Test]
    procedure Works;
  end;

  [TestFixture]
  TDerivedSetup = class(TTwice)
  public
    [Setup]
    procedure PrepC;
    [Test]
    procedure Works2;
  end;

implementation

end.
