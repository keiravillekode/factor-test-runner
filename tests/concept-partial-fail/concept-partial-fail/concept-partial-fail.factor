USING: kernel math ;
IN: concept-partial-fail

: square ( n -- n^2 ) dup * ;

: cube ( n -- n^3 ) dup dup * + ;
