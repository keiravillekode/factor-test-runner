USING: concept-partial-fail exercism-tools io kernel prettyprint tools.test ;
IN: concept-partial-fail.tests

TASK: 1 squaring
{ 9 } [ "squaring 3" print 3 square ] unit-test

STOP-HERE

{ 16 } [ 4 square dup . ] unit-test

TASK: 2 cubing
{ 27 } [ "cubing 3" print 3 cube ] unit-test
{ 64 } [ 4 cube ] unit-test

TASK: 3 dropping the first element
! `{ } but-first` is `{ } rest`, which throws a slice-error. The runner must
! report the readable summary, not a bare `T{ slice-error ... }`.
{ { } } [ { } but-first ] unit-test
