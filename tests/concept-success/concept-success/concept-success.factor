USING: accessors calendar.english combinators fry hash-sets hashtables
       kernel locals math sequences vectors ;
IN: concept-success

TUPLE: point x y ;

: number-result ( -- n ) 42 ;

: string-result ( -- s ) 6 month-name ;

: array-result ( -- arr ) { 1 2 3 } ;

: vector-result ( -- vec ) V{ 1 2 3 } ;

: hashset-result ( -- hs ) HS{ "a" "b" "c" } ;

: hashtable-result ( -- ht ) H{ { "a" 1 } { "b" 2 } } ;

: tuple-result ( -- t ) point new 3 >>x 4 >>y ;

! Named locals via ::  and  :>  (locals vocab).
:: locals-result ( -- n )
    3 :> a
    4 :> b
    a a * b b * + ;

! Fry quotation '[ _ ... ]  (fry vocab) — captures the stack value into _.
: fry-result ( -- arr )
    { 1 2 3 } 10 '[ _ + ] map ;

! curry (kernel) and compose (combinators).
: curry-compose-result ( -- n )
    1 [ 2 + ] [ 3 * ] compose curry call ;
