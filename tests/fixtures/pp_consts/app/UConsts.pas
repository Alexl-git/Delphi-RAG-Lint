unit UConsts;

// INC3 lane fixture: a project unit whose constant UMain's $IF reads. The .dpr
// lists UMain FIRST, so on a first build this unit is not indexed yet when UMain
// is preprocessed -- the per-unit pre-pass must make the order irrelevant.

interface

const
  PROJ_LEVEL = 2 + 3;

implementation

end.