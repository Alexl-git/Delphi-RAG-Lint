/// <summary>Zorbimatic Dispatch -- the fixture's unit-level concept.</summary>
/// <remarks>
/// dl:wiki Zorbimatic Dispatch
/// Aliases: the zorbimatic, zorb dispatch, that dispatch thing
/// SeeCode: TZorbDispatcher, TZorbPayload.Deliver
/// Body:
/// A unit-level block: the recommended home for a concept owned by several
/// types. skUnit is not documentable, so the autodoc rewriter never opens
/// this comment.
/// A second body line, so a truncating parse is visible.
/// </remarks>
unit uWikiGood;

interface

type
  /// <summary>Carries one zorbimatic payload.</summary>
  /// <remarks>
  /// Ordinary hand-written remarks prose that has nothing to do with the wiki
  /// block below it. The hover strip must leave this alone.
  /// dl:wiki Zorb Payload
  /// Aliases: the payload
  /// Body:
  /// A type-attached block. Its survival across two document --apply passes
  /// is what proves the provenance contract holds for un-marked content.
  /// </remarks>
  TZorbPayload = class
  public
    /// <summary>Hands the payload to the dispatcher.</summary>
    procedure Deliver;
  end;

  /// <summary>Routes payloads. Deliberately carries no wiki block.</summary>
  TZorbDispatcher = class
  public
    /// <summary>Accepts one payload.</summary>
    /// <param name="pPayload">The payload; must not be nil.</param>
    procedure Accept(const pPayload: TZorbPayload);
  end;

implementation

procedure TZorbPayload.Deliver;
begin
end;

procedure TZorbDispatcher.Accept(const pPayload: TZorbPayload);
begin
end;

end.
