; Integer literals that are not in a small set of 'innocent' values may be magic
; numbers that deserve a named constant.
; Exempt list: 0, 1, 2, -1 (sentinels), small common values (3, 4, 8, 10, 100,
; 1000), powers of two used as buffer sizes / bit widths / bit flags
; (4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768,
; 65536), and ALL $-prefixed hex literals (used as bit masks / register values).
; NOTE: floats fall through here -- the regex below only exempts integers, so
; float literals that happen not to contain digits may still match; that is
; intentional (float magic numbers are caught by float-equality-comparison).
; CALIBRATION FIX: the exempt list said "small common values (3, 4, 8, 10, ...)"
; but the regex skipped 5, 6, 7, 9 and 11-15 entirely, so a rule called
; LARGE-magic-number was flagging `shl 6`, `if I >= 5` and `array[0..5]`. That
; was 304 findings on drag-lint's own source, the third-largest rule in the
; report, for literals no reader would call large. The regex now matches the
; comment: every integer through 16 is exempt, plus the usual round and
; power-of-two values above it.
((literalNumber) @magic
  (#not-match? @magic "^([$][0-9A-Fa-f]+|-?(0|1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16)|20|24|30|32|50|60|64|90|100|128|180|255|256|360|512|1000|1024|2048|4096|8192|16384|32768|65536)$"))
