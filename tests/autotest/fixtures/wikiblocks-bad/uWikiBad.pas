/// <summary>The NEGATIVE CONTROL fixture: its wiki block is wrong on
/// purpose.</summary>
/// <remarks>
/// This unit exists so that `wiki --check` can be proved to FAIL. A gate that
/// has only ever been seen passing is indistinguishable from a gate that
/// cannot fail at all -- and one that reports "0 problems" because it silently
/// examined nothing reads exactly like a working one.
///
/// Two distinct defects are planted:
///   1. a SeeCode entry naming a symbol that does not exist anywhere;
///   2. an alias on the second topic that collides with the FIRST topic's
///      name, which would make --term answer with the wrong topic.
///
/// dl:wiki Brollop Cycle
/// Aliases: the brollop
/// SeeCode: TBrollopStage, TNoSuchSymbolAnywhere
/// Body:
/// The first SeeCode entry resolves; the second cannot.
/// </remarks>
unit uWikiBad;

interface

type
  /// <summary>Exists so the FIRST SeeCode entry resolves -- without it the
  /// check would report two problems for one planted defect, and a count is
  /// part of what the guard asserts.</summary>
  /// <remarks>
  /// dl:wiki Second Topic
  /// Aliases: Brollop Cycle
  /// Body:
  /// This alias deliberately collides with the unit topic's NAME.
  /// </remarks>
  TBrollopStage = class
  end;

implementation

end.
