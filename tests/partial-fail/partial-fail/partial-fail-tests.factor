USING: exercism-tools io kernel partial-fail prettyprint tools.test ;
IN: partial-fail.tests

"greet returns hello" description
{ "hello" } [ "first call" print greet ] unit-test

STOP-HERE

"greet returns world" description
{ "world" } [ 2 . greet ] unit-test

"registering the same name twice throws" description
{ H{ { "ada" "hello" } } }
[ H{ } clone "hello" "ada" register "world" "ada" register ] unit-test
