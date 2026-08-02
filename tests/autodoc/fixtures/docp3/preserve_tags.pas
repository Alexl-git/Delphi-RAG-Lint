unit preserve_tags;

interface

/// <summary>Doubles AValue; hand-written summary must survive.</summary>
/// <deprecated/>
/// <param name="AValue">Hand-written param desc; must survive.</param>
/// <returns>The doubled value.</returns>
/// <exception cref="EFoo">Raised when AValue is negative.</exception>
/// <example>AllTags(21) returns 42.</example>
/// <seealso cref="Other.RelatedThing"/>
/// <since>1.2</since>
function AllTags(AValue: Integer): Integer;

procedure CallsAllTags;

/// <exception cref="EBar">Raised on bad input.</exception>
procedure ExceptionOnlyHasCaller;

procedure CallsExceptionOnly;

/// <summary>Plain summary; no exotic tags here.</summary>
procedure NoExoticTags;

/// <deprecated/>
procedure BareDeprecatedOnly;

procedure CallsBareDeprecatedOnly;

/// <summary>Uses <see cref="Other.RelatedThing"/> for related lookups and
/// can raise <exception cref="ENested">a nested, inline description</exception>
/// in edge cases.</summary>
procedure NestedTagsInSummary;

procedure CallsNestedTagsInSummary;

/// <deprecated>Use <see cref="Other.RelatedThing"/> instead of this old thing.</deprecated>
procedure NestedInDeprecated;

procedure CallsNestedInDeprecated;

/// <exception cref="EOuter">Added in <since>2.0</since> and still raised today.</exception>
procedure NestedSinceInException;

procedure CallsNestedSinceInException;

/// <example>Sample usage. <exception cref="EInExample">boom</exception> can happen.</example>
procedure NestedExceptionInExample;

procedure CallsNestedExceptionInExample;

/// <deprecated>Use Rev instead; this will be removed in 2.0.</deprecated>

procedure GappedDeprecatedMessage;

procedure CallsGappedDeprecatedMessage;

/// <see cref="Other.RelatedThing"/>
procedure BareSeeOnly;

procedure CallsBareSeeOnly;

/// Plain prose that mentions <seealso> without any cref, plus trailing words.
procedure ProseMentionsSeeAlso;
/// Grows the <seed> lookup table by one bucket.
procedure ProseMentionsSeed;
/// Marks the routine <deprecatedSoon> but not really.
procedure ProseMentionsDeprecatedSoon;

/// <summary>Has a deliberately blank example slot.</summary>
/// <example></example>
procedure EmptyExampleSurvives;

procedure CallsEmptyExampleSurvives;

/// <deprecated >Space before the closing angle bracket.</deprecated>
procedure SpaceBeforeCloseDeprecated;

procedure CallsSpaceBeforeCloseDeprecated;

/// <deprecated>No closing tag at all, just trailing words
procedure UnclosedDeprecated;

procedure CallsUnclosedDeprecated;

/// <DEPRECATED>Recognized case-insensitively.</DEPRECATED>
procedure AllCapsDeprecatedTag;

procedure CallsAllCapsDeprecatedTag;

/// <exception>Missing the required cref attribute.</exception>
procedure ExceptionNoCrefAttr;

procedure CallsExceptionNoCrefAttr;

/// <summary>Has a real, well-formed summary.</summary>
/// <seealso>Missing the required cref, sitting alongside a real tag.</seealso>
procedure SeeAlsoNoCrefWithSummary;

procedure CallsSeeAlsoNoCrefWithSummary;

/// <example>Unclosed example body, no closing tag
procedure UnclosedExampleTag;

procedure CallsUnclosedExampleTag;

/// <seealso	cref="Other.RelatedThing"/>
procedure TabSeparatedSeeAlso;

procedure CallsTabSeparatedSeeAlso;

/// <since>1.0 <exception cref="EInSince">x</exception></since>
procedure SinceWithNestedException;

procedure CallsSinceWithNestedException;

/// <since>2.0 <example>see the sample below</example> onwards</since>
procedure SinceWithNestedExample;

procedure CallsSinceWithNestedExample;

/// <since><deprecated>2.0-beta</deprecated></since>
procedure SinceWithNestedDeprecated;

procedure CallsSinceWithNestedDeprecated;

/// <exception cref="E1">exc text <summary>nested summary</summary> tail</exception>
procedure ExceptionWithNestedSummary;

procedure CallsExceptionWithNestedSummary;

/// <example>Ex <param name="AV">nested param desc</param> body.</example>
procedure ExampleWithNestedParam(AV: Integer);

procedure CallsExampleWithNestedParam;

/// <deprecated>dep <returns>nested returns text</returns> tail</deprecated>
function DeprecatedWithNestedReturns: Integer;

procedure CallsDeprecatedWithNestedReturns;

/// <example>ex <remarks>nested remarks</remarks> tail</example>
procedure ExampleWithNestedRemarks;

procedure CallsExampleWithNestedRemarks;

type
  TSeeAlsoHost = class
  public
    /// <summary>Does A.</summary>
    /// <since>1.0-hand</since>
    /// <seealso cref="Unrelated.HandWritten"/>
    procedure DoA;
    procedure DoB(AValue: Integer);
    procedure DoC(AText: string);
  end;

implementation

function AllTags(AValue: Integer): Integer;
begin
  Result := AValue * 2;
end;

procedure CallsAllTags;
begin
  AllTags(21);
end;

procedure ExceptionOnlyHasCaller;
begin
end;

procedure CallsExceptionOnly;
begin
  ExceptionOnlyHasCaller;
end;

procedure NoExoticTags;
begin
end;

procedure BareDeprecatedOnly;
begin
end;

procedure CallsBareDeprecatedOnly;
begin
  BareDeprecatedOnly;
end;

procedure NestedTagsInSummary;
begin
end;

procedure CallsNestedTagsInSummary;
begin
  NestedTagsInSummary;
end;

procedure NestedInDeprecated;
begin
end;

procedure CallsNestedInDeprecated;
begin
  NestedInDeprecated;
end;

procedure NestedSinceInException;
begin
end;

procedure CallsNestedSinceInException;
begin
  NestedSinceInException;
end;

procedure NestedExceptionInExample;
begin
end;

procedure CallsNestedExceptionInExample;
begin
  NestedExceptionInExample;
end;

procedure GappedDeprecatedMessage;
begin
end;

procedure CallsGappedDeprecatedMessage;
begin
  GappedDeprecatedMessage;
end;

procedure BareSeeOnly;
begin
end;

procedure CallsBareSeeOnly;
begin
  BareSeeOnly;
end;

procedure ProseMentionsSeeAlso;
begin
end;

procedure ProseMentionsSeed;
begin
end;

procedure ProseMentionsDeprecatedSoon;
begin
end;

procedure EmptyExampleSurvives;
begin
end;

procedure CallsEmptyExampleSurvives;
begin
  EmptyExampleSurvives;
end;

procedure SpaceBeforeCloseDeprecated;
begin
end;

procedure CallsSpaceBeforeCloseDeprecated;
begin
  SpaceBeforeCloseDeprecated;
end;

procedure UnclosedDeprecated;
begin
end;

procedure CallsUnclosedDeprecated;
begin
  UnclosedDeprecated;
end;

procedure AllCapsDeprecatedTag;
begin
end;

procedure CallsAllCapsDeprecatedTag;
begin
  AllCapsDeprecatedTag;
end;

procedure ExceptionNoCrefAttr;
begin
end;

procedure CallsExceptionNoCrefAttr;
begin
  ExceptionNoCrefAttr;
end;

procedure SeeAlsoNoCrefWithSummary;
begin
end;

procedure CallsSeeAlsoNoCrefWithSummary;
begin
  SeeAlsoNoCrefWithSummary;
end;

procedure UnclosedExampleTag;
begin
end;

procedure CallsUnclosedExampleTag;
begin
  UnclosedExampleTag;
end;

procedure TabSeparatedSeeAlso;
begin
end;

procedure CallsTabSeparatedSeeAlso;
begin
  TabSeparatedSeeAlso;
end;

procedure SinceWithNestedException;
begin
end;

procedure CallsSinceWithNestedException;
begin
  SinceWithNestedException;
end;

procedure SinceWithNestedExample;
begin
end;

procedure CallsSinceWithNestedExample;
begin
  SinceWithNestedExample;
end;

procedure SinceWithNestedDeprecated;
begin
end;

procedure CallsSinceWithNestedDeprecated;
begin
  SinceWithNestedDeprecated;
end;

procedure ExceptionWithNestedSummary;
begin
end;

procedure CallsExceptionWithNestedSummary;
begin
  ExceptionWithNestedSummary;
end;

procedure ExampleWithNestedParam(AV: Integer);
begin
end;

procedure CallsExampleWithNestedParam;
begin
  ExampleWithNestedParam(1);
end;

function DeprecatedWithNestedReturns: Integer;
begin
  Result:= 1;
end;

procedure CallsDeprecatedWithNestedReturns;
begin
  DeprecatedWithNestedReturns;
end;

procedure ExampleWithNestedRemarks;
begin
end;

procedure CallsExampleWithNestedRemarks;
begin
  ExampleWithNestedRemarks;
end;

procedure TSeeAlsoHost.DoA;
begin
  DoB(1);
  DoC('x');
end;

procedure TSeeAlsoHost.DoB(AValue: Integer);
begin
  Writeln(AValue);
end;

procedure TSeeAlsoHost.DoC(AText: string);
begin
  Writeln(AText);
end;

end.
