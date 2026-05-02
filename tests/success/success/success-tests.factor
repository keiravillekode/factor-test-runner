USING: exercism-tools io prettyprint success tools.test ;
IN: success.tests

{ "hello" } [ "calling greet" print greet ] unit-test
