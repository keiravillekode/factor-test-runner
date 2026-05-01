USING: accessors hash-sets hashtables kernel sequences vectors ;
IN: concept-success

TUPLE: point x y ;

: number-result ( -- n ) 42 ;

: string-result ( -- s ) "hello" ;

: array-result ( -- arr ) { 1 2 3 } ;

: vector-result ( -- vec ) V{ 1 2 3 } ;

: hashset-result ( -- hs ) HS{ "a" "b" "c" } ;

: hashtable-result ( -- ht ) H{ { "a" 1 } { "b" 2 } } ;

: tuple-result ( -- t ) point new 3 >>x 4 >>y ;
