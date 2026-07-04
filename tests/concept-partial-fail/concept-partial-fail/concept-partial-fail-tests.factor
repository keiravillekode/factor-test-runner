USING: concept-partial-fail exercism-tools io kernel math prettyprint sequences tools.test ;
IN: concept-partial-fail.tests

TASK: 1 squaring
{ 9 } [ "squaring 3" print 3 square ] unit-test

STOP-HERE

{ 16 } [ 4 square dup . ] unit-test

TASK: 2 cubing
{ 27 } [ "cubing 3" print 3 cube ] unit-test
{ 64 } [ 4 cube ] unit-test

TASK: 3 dropping the first element
{ { } } [ { } but-first ] unit-test

TASK: 4 divide by zero
{ 0 } [ 4 0 / ] unit-test

TASK: 5 index out of bounds
{ 0 } [ 10 { 1 2 3 } nth ] unit-test

TASK: 6 method lookup
{ "text" } [ 5 label ] unit-test

TASK: 7 stack effect mismatch
{ 0 } [ 5 [ drop ] call( x -- x ) ] unit-test
