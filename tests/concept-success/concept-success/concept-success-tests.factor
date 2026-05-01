USING: concept-success exercism-tools tools.test ;
IN: concept-success.tests

TASK: 1 numbers
{ 42 } [ number-result ] unit-test

STOP-HERE

TASK: 2 strings
{ "hello" } [ string-result ] unit-test

TASK: 3 arrays
{ { 1 2 3 } } [ array-result ] unit-test

TASK: 4 vectors
{ V{ 1 2 3 } } [ vector-result ] unit-test

TASK: 5 hashsets
{ HS{ "a" "b" "c" } } [ hashset-result ] unit-test

TASK: 6 hashtables
{ H{ { "a" 1 } { "b" 2 } } } [ hashtable-result ] unit-test

TASK: 7 tuples
{ T{ point f 3 4 } } [ tuple-result ] unit-test
