USING: exercism-tools io partial-fail prettyprint tools.test ;
IN: partial-fail.tests

{ "hello" } [ "first call" print greet ] unit-test

STOP-HERE

{ "world" } [ 2 . greet ] unit-test
