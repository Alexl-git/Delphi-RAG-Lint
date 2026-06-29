; Integer literals that are not in a small set of 'innocent' values may be magic
; numbers that deserve a named constant.
; Exempt list: 0, 1, 2, -1 (sentinels), small common values (3, 4, 8, 10, 100,
; 1000), powers of two used as buffer sizes / bit widths / bit flags
; (4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768,
; 65536), and ALL $-prefixed hex literals (used as bit masks / register values).
; NOTE: floats fall through here -- the regex below only exempts integers, so
; float literals that happen not to contain digits may still match; that is
; intentional (float magic numbers are caught by float-equality-comparison).
((literalNumber) @magic
  (#not-match? @magic "^([$][0-9A-Fa-f]+|0|1|2|3|4|8|10|16|32|64|100|128|256|512|1024|2048|4096|8192|16384|32768|65536|1000|-1|-2)$"))
