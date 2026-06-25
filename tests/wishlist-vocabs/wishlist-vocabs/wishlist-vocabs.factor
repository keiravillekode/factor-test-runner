USING: arrays circular hashtables infix interpolate kernel math
       namespaces pair-rocket qw sequences sequences.extras
       sequences.repeating ;
IN: wishlist-vocabs

! qw{ ... } reads a whitespace-separated literal sequence of strings (qw).
: fruits ( -- seq ) qw{ apple orange lime } ;

! Standard infix arithmetic over locals (infix).
INFIX:: add ( x y -- z ) x + y ;

! take-while keeps the leading run satisfying the predicate (sequences.extras);
! it returns a slice, so >array normalizes it for an exact unit-test compare.
: small-prefix ( seq -- arr ) [ 3 < ] take-while >array ;

! ${var} string interpolation, reading from a dynamic variable (interpolate).
: greeting ( name -- str )
    [ "name" set "Hello, ${name}!" interpolate>string ] with-scope ;

! cycle repeats a sequence up to a given length (sequences.repeating).
: padded-cycle ( seq n -- arr ) cycle >array ;

! <circular> wraps a sequence so indices read modulo its length (circular).
: wrap-nth ( n seq -- elt ) <circular> nth ;

! => pairs each key with the next value, building assoc literals (pair-rocket).
: scores ( -- assoc ) { "ada" => 1 "bob" => 2 } >hashtable ;
