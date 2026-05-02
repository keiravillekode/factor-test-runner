USING: accessors arrays ascii assocs combinators
       concurrency.combinators concurrency.locks continuations
       destructors exercism-tools formatting fry grouping
       hash-sets hashtables io kernel locals make math
       math.bitwise math.constants math.functions math.order
       math.parser math.primes math.statistics math.vectors
       namespaces prettyprint ranges sequences sets sorting
       splitting splitting.monotonic strings success tools.test
       vectors ;
IN: success.tests

{ "hello" } [ "calling greet" print greet ] unit-test
