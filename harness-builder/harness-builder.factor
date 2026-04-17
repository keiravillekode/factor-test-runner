! Builds a Factor harness file that runs each unit-test in an Exercism
! solution and writes a v3 results.json directly.
!
! Entry point: build-harness ( tests-path harness-path results-path -- )

USING: accessors arrays ascii assocs combinators
       combinators.short-circuit continuations io io.encodings.utf8
       io.files kernel locals make math math.parser sequences splitting
       strings vectors ;
IN: harness-builder

! ---------- Constants ----------

CONSTANT: definer-words {
    ":" "::" "SYNTAX:" "USING:" "USE:" "FROM:" "IN:" "DEFER:"
    "GENERIC:" "GENERIC#:" "HOOK:" "MIXIN:" "TUPLE:" "C-TYPE:"
    "M:" "MACRO:" "MEMO:" "PREDICATE:" "PRIMITIVE:" "SINGLETON:"
    "SYMBOL:" "SYMBOLS:" "VARIANT:" "ALIAS:" "CONSTANT:"
    "SLOT:" "UNION:" "INTERSECTION:"
}

CONSTANT: harness-runtime "USING: assocs continuations io io.encodings.utf8 io.files
       io.streams.string json kernel locals math math.parser
       prettyprint sequences tools.test ;

CONSTANT: max-output 500
CONSTANT: trunc-suffix \" [output truncated]\"

: truncate ( s -- s' )
    dup length max-output > [
        max-output trunc-suffix length - head trunc-suffix append
    ] when ;

:: make-entry ( name text task-id body status -- assoc )
    H{ } clone :> entry
    name \"name\" entry set-at
    text \"test_code\" entry set-at
    task-id [ task-id \"task_id\" entry set-at ] when
    status \"status\" entry set-at
    status \"pass\" = [
        body empty? [ body truncate \"output\" entry set-at ] unless
    ] [
        body \"message\" entry set-at
    ] if
    entry ;

: overall-status ( entries -- s )
    [ \"status\" of \"pass\" = ] all? [ \"pass\" ] [ \"fail\" ] if ;

:: emit-results ( entries results-path -- )
    H{ } clone :> result
    3 \"version\" result set-at
    entries overall-status \"status\" result set-at
    entries \"tests\" result set-at
    results-path utf8 [ result >json print ] with-file-writer ;
"

! ---------- Factor string-literal escaping ----------

: escape-char ( ch -- str )
    {
        { CHAR: " [ "\\\"" ] }
        { CHAR: \ [ "\\\\" ] }
        { 10 [ "\\n" ] }
        { 9 [ "\\t" ] }
        { 13 [ "\\r" ] }
        [ 1string ]
    } case ;

: factor-string ( s -- s' )
    [ escape-char ] { } map-as concat
    "\"" "\"" surround ;

! ---------- Tokenizer ----------
!
! A token is a { text start-pos } 2-array. Strings are emitted as a
! single token (including the quotes); `!` / `#!` line comments are
! consumed without emitting a token.

:: scan-string-literal ( text i n -- end )
    i 1 + :> j!
    f :> done!
    [ done not j n < and ] [
        j text nth :> ch
        ch CHAR: " = [
            j 1 + j!
            t done!
        ] [
            ch CHAR: \ = j 1 + n < and [ j 2 + j! ] [ j 1 + j! ] if
        ] if
    ] while
    j ;

:: tokenize ( text -- tokens )
    V{ } clone :> tokens
    text length :> n
    0 :> i!
    [ i n < ] [
        i text nth :> c
        c blank? [ i 1 + i! ] [
            c CHAR: " = [
                text i n scan-string-literal :> j
                i j text subseq i 2array tokens push
                j i!
            ] [
                i :> start
                [ i n < [ i text nth blank? not ] [ f ] if ] [ i 1 + i! ] while
                start i text subseq :> tok
                tok "!" = tok "#!" = or [
                    [ i n < [ i text nth CHAR: \n = not ] [ f ] if ] [ i 1 + i! ] while
                ] [
                    tok start 2array tokens push
                ] if
            ] if
        ] if
    ] while
    tokens ;

! ---------- Parser ----------
!
! Walks tokens; emits one assoc per unit-test:
!     H{ { "index" N } { "task_id" N/f } { "test_code" "..." }
!        { "start" N } { "end" N } }
! Skips `:` ... `;` word definitions. Tracks TASK: N declarations.

:: line-end-from ( text pos -- end )
    CHAR: \n pos text index-from [ text length ] unless* ;

:: parse-task-num ( line -- n/f )
    ! line is the substring after "TASK:" up to the newline.
    ! Return the first run of decimal digits as an integer, or f.
    line [ digit? ] find drop dup [
        :> start
        start line [ digit? not ] find-from drop
        [ line length ] unless*
        start swap line subseq string>number
    ] [ drop f ] if ;

:: emit-test ( tests text test-start end-pos current-task -- )
    H{ } clone :> entry
    tests length 1 + "index" entry set-at
    current-task "task_id" entry set-at
    test-start end-pos text subseq [ blank? ] trim "test_code" entry set-at
    test-start "start" entry set-at
    end-pos "end" entry set-at
    entry tests push ;

:: parse-tests ( text -- tests )
    text tokenize :> tokens
    V{ } clone :> tests
    f :> in-word!
    0 :> dc!
    0 :> ds!
    0 :> dp!
    f :> ts!
    f :> task!
    0 :> i!
    tokens length :> n
    [ i n < ] [
        i tokens nth first2 :> ( tok pos )
        in-word [
            tok "(" = [ dp 1 + dp! ] when
            tok ")" = [ dp 1 - dp! ] when
            tok ";" = dp 0 = and [ f in-word! ] when
            i 1 + i!
        ] [
            tok "TASK:" = [
                text pos line-end-from :> nl
                pos "TASK:" length + nl text subseq
                parse-task-num [ task! ] when*
                [ i n < [ i tokens nth second nl < ] [ f ] if ]
                [ i 1 + i! ] while
            ] [
                tok definer-words member? [
                    t in-word! i 1 + i!
                ] [
                    tok "{" = [
                        ts not dc 0 = and ds 0 = and [ pos ts! ] when
                        dc 1 + dc! i 1 + i!
                    ] [
                        tok "}" = [ dc 1 - dc! i 1 + i! ] [
                            tok "[" = [
                                ts not dc 0 = and ds 0 = and [ pos ts! ] when
                                ds 1 + ds! i 1 + i!
                            ] [
                                tok "]" = [ ds 1 - ds! i 1 + i! ] [
                                    tok "unit-test" = dc 0 = and ds 0 = and ts and [
                                        pos "unit-test" length + :> ep
                                        tests text ts ep task emit-test
                                        f ts!
                                    ] when
                                    i 1 + i!
                                ] if
                            ] if
                        ] if
                    ] if
                ] if
            ] if
        ] if
    ] while
    tests ;

! ---------- TASK: machinery stripping ----------
!
! Drop two kinds of lines that concept exercises put in their tests:
!   1. "TASK:" as a parsing-word definition: `: TASK: ... ; parsing`
!   2. "TASK: N description" call sites
! Both are markers we've already consumed via parse-tests.

: task-def-line? ( line -- ? )
    [ blank? ] trim {
        [ ":" head? ]
        [ "TASK:" subseq-of? ]
        [ "parsing" tail? ]
    } 1&& ;

: task-call-line? ( line -- ? )
    [ blank? ] trim-head "TASK:" head? ;

: strip-task-machinery ( prelude -- prelude' )
    "\n" split
    [ [ task-def-line? ] [ task-call-line? ] bi or not ] filter
    "\n" join ;

! ---------- Per-test wrap ----------

:: wrap-test ( test -- string )
    test "index" of :> idx
    test "task_id" of :> task-id
    test "test_code" of :> code
    "Test " idx number>string append factor-string :> name-lit
    code factor-string :> text-lit
    task-id [ task-id number>string ] [ "f" ] if :> task-lit
    {
        name-lit " " text-lit " " task-lit "\n"
        "[ [ " code " ] with-string-writer \"pass\" ]\n"
        "[ dup assert-sequence? [ \"fail\" ] [ \"error\" ] if swap unparse swap ]\n"
        "recover\n"
        "make-entry over push\n"
    } concat ;

! ---------- Assemble harness ----------

:: build-harness-text ( prelude tests results-path -- harness-text )
    [
        "IN: harness\n" %
        prelude strip-task-machinery [ blank? ] trim-tail %
        "\n" %
        harness-runtime %
        "V{ } clone\n" %
        tests [ wrap-test % ] each
        results-path factor-string % " emit-results\n" %
    ] "" make ;

:: build-harness ( tests-path harness-path results-path -- )
    tests-path utf8 file-contents :> text
    text parse-tests :> tests
    tests empty?
    [ text ]
    [ 0 tests first "start" of text subseq ] if :> prelude
    prelude tests results-path build-harness-text :> output
    output harness-path utf8 set-file-contents ;
