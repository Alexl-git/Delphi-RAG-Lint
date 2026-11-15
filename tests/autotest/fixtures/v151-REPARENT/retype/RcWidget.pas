unit RcWidget;

// Fixture of extract-interface --retype-consumer (lane v151 REPARENT): the classes whose consumers RcUse.pas retypes.
// Each class's IInterface either never counts references (the retype may go ahead) or does, or cannot be told.

interface

uses
  System.Classes, System.Generics.Defaults;

type
  IRcCounter = interface
    ['{6B1F0A52-3C1E-4C55-9D0B-1A2B3C4D5E01}']
    function GetCount: Integer;
    procedure Bump;
    property Count: Integer read GetCount;
  end;

  /// <summary>A non-counting IInterface base: a consumer may take IRcCounter.</summary>
  TRcCounter = class(TSingletonImplementation, IRcCounter)
  strict private
    FCount: Integer;
    function GetCount: Integer;
  public
    procedure Bump;
    function Secret: Integer;
    property Count: Integer read GetCount;
  end;

  /// <summary>Inherits the interface and the non-counting base.</summary>
  TRcCounterKid = class(TRcCounter)
  public
    function Extra: Integer;
  end;

  IRcCounted = interface
    ['{6B1F0A52-3C1E-4C55-9D0B-1A2B3C4D5E02}']
    procedure Bump;
  end;

  /// <summary>Counts references: an interface temporary would free a caller's instance.</summary>
  TRcCounted = class(TInterfacedObject, IRcCounted)
  public
    procedure Bump;
  end;

  IRcPart = interface
    ['{6B1F0A52-3C1E-4C55-9D0B-1A2B3C4D5E03}']
    function PartName: string;
  end;

  /// <summary>TComponent's IInterface does not count references.</summary>
  TRcPart = class(TComponent, IRcPart)
  public
    function PartName: string;
  end;

  /// <summary>A project base whose _AddRef returns -1.</summary>
  TRcQuietBase = class(TObject, IInterface)
  protected
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  end;

  IRcQuiet = interface
    ['{6B1F0A52-3C1E-4C55-9D0B-1A2B3C4D5E04}']
    procedure Ping;
  end;

  TRcQuiet = class(TRcQuietBase, IRcQuiet)
  public
    procedure Ping;
  end;

  /// <summary>A project base whose _AddRef counts: nothing proves an instance survives.</summary>
  TRcLoudBase = class(TObject, IInterface)
  protected
    FRefs: Integer;
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    function _AddRef: Integer; stdcall;
    function _Release: Integer; stdcall;
  end;

  IRcLoud = interface
    ['{6B1F0A52-3C1E-4C55-9D0B-1A2B3C4D5E05}']
    procedure Shout;
  end;

  TRcLoud = class(TRcLoudBase, IRcLoud)
  public
    procedure Shout;
  end;

  /// <summary>No IInterface in the chain.</summary>
  TRcPlain = class
  public
    procedure Bump;
  end;

  IRcBare = interface
    ['{6B1F0A52-3C1E-4C55-9D0B-1A2B3C4D5E06}']
    procedure Bump;
  end;

  /// <summary>A non-counting base, but the class does not list IRcBare.</summary>
  TRcBare = class(TSingletonImplementation)
  public
    procedure Bump;
  end;

  IRcMapped = interface
    ['{6B1F0A52-3C1E-4C55-9D0B-1A2B3C4D5E07}']
    procedure Bump;
  end;

  /// <summary>A method resolution clause: the interface's Bump is not the class's Bump.</summary>
  TRcMapped = class(TSingletonImplementation, IRcMapped)
  public
    procedure IRcMapped.Bump = Other;
    procedure Bump;
    procedure Other;
  end;

  IRcAgain = interface
    ['{6B1F0A52-3C1E-4C55-9D0B-1A2B3C4D5E08}']
    procedure Bump;
  end;

  TRcAgain = class(TSingletonImplementation, IRcAgain)
  public
    procedure Bump;
  end;

  /// <summary>Lists IRcAgain again: a call through the interface would reach this Bump, the class call TRcAgain's.</summary>
  TRcAgainKid = class(TRcAgain, IRcAgain)
  public
    procedure Bump;
  end;

implementation

uses
  System.SysUtils;

function TRcCounter.GetCount: Integer;
begin
  Result:= FCount;
end;

procedure TRcCounter.Bump;
begin
  Inc(FCount);
end;

function TRcCounter.Secret: Integer;
begin
  Result:= 42;
end;

function TRcCounterKid.Extra: Integer;
begin
  Result:= Count + 1;
end;

procedure TRcCounted.Bump;
begin
end;

function TRcPart.PartName: string;
begin
  Result:= 'part';
end;

function TRcQuietBase.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then Result:= S_OK else Result:= E_NOINTERFACE;
end;

function TRcQuietBase._AddRef: Integer;
begin
  Result:= -1;
end;

function TRcQuietBase._Release: Integer;
begin
  Result:= -1;
end;

procedure TRcQuiet.Ping;
begin
  Write('ping ');
end;

function TRcLoudBase.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then Result:= S_OK else Result:= E_NOINTERFACE;
end;

function TRcLoudBase._AddRef: Integer;
begin
  Inc(FRefs);
  Result:= FRefs;
end;

function TRcLoudBase._Release: Integer;
begin
  Dec(FRefs);
  Result:= FRefs;
end;

procedure TRcLoud.Shout;
begin
end;

procedure TRcPlain.Bump;
begin
end;

procedure TRcBare.Bump;
begin
end;

procedure TRcMapped.Bump;
begin
end;

procedure TRcMapped.Other;
begin
end;

procedure TRcAgain.Bump;
begin
end;

procedure TRcAgainKid.Bump;
begin
end;

end.
