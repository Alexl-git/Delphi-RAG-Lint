unit LibConsts;

// INC3 lane fixture: a LIBRARY unit (outside the project's search path; indexed
// into a separate library DB). LIB_LEVEL refers to another constant, so its
// stored signature "= LIB_BASE + 5" must be evaluated in this unit's scope.

interface

const
  LIB_BASE = 4;
  LIB_LEVEL = LIB_BASE + 5;
  LIB_TYPED: Integer = 9; // EXT-E4: a TYPED constant in a library unit

type
  TLibThing = class
  end;

implementation

end.