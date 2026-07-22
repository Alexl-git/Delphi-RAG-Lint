unit esc;
interface
/// <summary>Legacy entry point kept for callers not yet migrated.</summary>
/// <remarks>Hand-written note: prefer NewWay for A &lt;-&gt; B mapping.</remarks>
// OldEsc is deprecated with a message that contains XML metacharacters (< > &)
// AND a literal </remarks> close tag. The generated managed block MUST XML-escape
// all of it: raw '<', '>', '&' would make the DocInsight XML ill-formed, and a raw
// '</remarks>' would additionally break the regex-based re-parse (the non-greedy
// <remarks>...</remarks> match stops at the injected close tag), which drops the
// hand-written prose after the fence -> non-idempotent + lost author content.
procedure OldEsc; deprecated 'use A<B> & </remarks> instead';
procedure UseIt;
implementation
procedure OldEsc;
begin
end;
procedure UseIt;
begin
  OldEsc();
end;
end.
