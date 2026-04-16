USING: kernel locals ;
IN: annalyns-infiltration

: can-do-fast-attack ( knight-awake -- ? )
    not ;

! BUG: should be `or or`, not `and and`. 5 of 7 task-2 tests will fail.
: can-spy ( knight-awake archer-awake prisoner-awake -- ? )
    and and ;

! BUG: should be `swap not and`, not `and`. 2 of 4 task-3 tests will fail.
: can-signal-prisoner ( archer-awake prisoner-awake -- ? )
    and ;

:: can-free-prisoner ( knight-awake archer-awake prisoner-awake dog-present -- ? )
    dog-present archer-awake not and
    prisoner-awake knight-awake not and archer-awake not and
    or ;
