USING: exercism-tools tools.test wishlist-vocabs ;
IN: wishlist-vocabs.tests

"qw builds a sequence of strings" description
{ { "apple" "orange" "lime" } } [ fruits ] unit-test

"infix add sums two numbers" description
{ 7 } [ 3 4 add ] unit-test

"take-while keeps the leading run" description
{ { 1 2 } } [ { 1 2 3 4 1 } small-prefix ] unit-test

"interpolate fills in the name" description
{ "Hello, World!" } [ "World" greeting ] unit-test

"cycle repeats a sequence to length" description
{ { 1 2 3 1 2 } } [ { 1 2 3 } 5 padded-cycle ] unit-test

"circular indexing wraps around" description
{ 20 } [ 4 { 10 20 30 } wrap-nth ] unit-test

"pair-rocket builds an assoc" description
{ H{ { "ada" 1 } { "bob" 2 } } } [ scores ] unit-test
