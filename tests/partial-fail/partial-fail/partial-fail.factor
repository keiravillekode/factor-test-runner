USING: assocs.extras kernel ;
IN: partial-fail

: greet ( -- str ) "hello" ;

! set-once-at throws key-exists when the key is already present
! (assocs.extras), so registering the same name twice fails at runtime.
: register ( assoc greeting name -- assoc ) pick set-once-at ;
