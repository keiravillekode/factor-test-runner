USING: arrays combinators kernel math.functions math.parser prettyprint sequences ;
IN: raindrops

: convert ( n -- str )
    dup . ! print n
    dup
    [ 3 divisor? "Pling" and ]
    [ 5 divisor? "Plang" and ]
    [ 7 divisor? "Plong" and ] tri
    3array [ ] filter
    [ number>string ] [ concat swap drop ] if-empty ;
