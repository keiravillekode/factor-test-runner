USING: kernel math sequences strings ;
IN: concept-partial-fail

: square ( n -- n^2 ) dup * ;

: cube ( n -- n^3 ) dup dup * + ;

: but-first ( seq -- rest ) rest ;

GENERIC: label ( obj -- str )
M: string label drop "text" ;
