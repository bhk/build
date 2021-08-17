;; prototype.scm:  SCAM prototypes of functions for Minion

(require "core")
(require "string")

;;----------------------------------------------------------------
;; Utilities
;;----------------------------------------------------------------

(define *var-functions* nil)

;; Mark a function as safe to be replaced with a variable reference
;;  $(call FN,$1)    -> $(FN)
;;  $(call FN,$1,$2) -> $(FN)
;; Must be non-recursive, and must not have optional arguments.
;;
(define (VF! fn-name)
  (set *var-functions*
       (append *var-functions* fn-name)))


(define single-chars
  (.. "a b c d e f g h i j k l m n o p q r s t u v w x y z "
      "A B C D E F G H I J K L M N O P Q R S T U V W X Y Z "
      ";"))

;; Rename variable references and "foreach" bindings
;;
(define (rename-vars fn-body froms tos)
  (define `(var-ref name)
    (if (filter single-chars name)
        (.. "$" name)
        (.. "$(" name ")")))

  (define `from (word 1 froms))
  (define `to (word 1 tos))
  (define `renamed
    (subst (.. "foreach " from ",") (.. "foreach " to ",")
           (var-ref from) (var-ref to)
           fn-body))

  (if froms
      (rename-vars renamed (rest froms) (rest tos))
      fn-body))


(expect (rename-vars "$(foreach a,bcd,$(foreach bcd,a $a,$(bcd)))"
                     "a bcd" "A BCD")
        "$(foreach A,bcd,$(foreach BCD,a $A,$(BCD)))")


;; Collapse function calls into variable references.
;;
(define (omit-calls body)
  (foldl (lambda (text fname)
           (subst (.. "$(call " fname ")")
                  (.. "$(" fname ")")
                  (.. "$(call " fname ",$1)")
                  (.. "$(" fname ")")
                  (.. "$(call " fname ",$1,$2)")
                  (.. "$(" fname ")")
                  (.. "$(call " fname ",$1,$2,$3)")
                  (.. "$(" fname ")")
                  (.. "$(call " fname ",$1,$2,$3,$4)")
                  (.. "$(" fname ")")
                  text))
         body
         *var-functions*))


(define *exports* nil)


;; Mark FN-NAME as a function to be exported to Minion, and perform
;; relevant translations.
;;
(define (export fn-name is-vf ?vars-to-in ?vars-from-in)
  ;; Avoid ";" because Minion uses `$;` for ","
  (define `vars-to (or vars-to-in "w x"))
  (define `vars-from (or vars-from-in "; ;; ;;; ;;;; ;;;;;"))

  (if is-vf
      (VF! fn-name))
  (set-native-fn fn-name
       (omit-calls
        (rename-vars (native-value fn-name) vars-from vars-to)))
  (set *exports* (conj *exports* fn-name)))


(define (export-comment text)
  (set *exports* (conj *exports* (.. "#" text))))

;; Output a SCAM function as Make code, renaming automatic vars.
;;
(define (show-export fn-name)
  (define `minionized
    (subst "$`" "$$"          ;; SCAM runtime -> Minion make
           "$  " "$(\\s)"     ;; SCAM runtime -> Minion make
           "$ \t" "$(\\t)"    ;; SCAM runtime -> Minion make
           "$ " ""            ;; not needed to avoid keywords in "=" defns
           "$(if ,,,)" "$;"   ;; SCAM runtime -> Minion make
           "$(if ,,:,)" ":$;" ;; SCAM runtime -> Minion make
           "$(&)" "$&"        ;; smaller, isn't it?
           (native-value fn-name)))

  (define `escaped
    (subst "\n" "$(\\n)" "#" "\\#" minionized))

  (print fn-name " = " escaped))


(define (show-exports)
  (for (e *exports*)
    (if (filter "#%" e)
        (print "\n" e "\n")
        (show-export e))))



;;----------------------------------------------------------------
;; Object system
;;----------------------------------------------------------------

(export-comment " object system")

(print "Imports: \\H \\n \\L \\R [ ]")
(define \H &native "#")
(define \n &native "\n")
(set-native "\\L" "{")
(set-native "\\R" "}")


;; Return non-nil if VAR has been assigned a value.
;;
(define `(bound? var)
  (filter-out "u%" (native-flavor var)))

(define `(undefined? var)
  (filter "u%" (native-flavor var)))

(define `(recursive? var)
  (filter "r%" (native-flavor var)))

(define `(simple? var)
  (filter "s%" (native-flavor var)))

;; Return VAR if VAR has been assigned a value.
;;
(define `(boundName? var)
  (if (filter "u%" (native-flavor var)) "" var))


;; Set variable named KEY to VALUE; return VALUE.
;;
;; We assume KEY does not contain ":", "=", "$", or whitespace.
(define (_set key value)
  &native
  (define `(escape str)
    "$(or )" (subst "$" "$$" "\n" "$(\\n)" "#" "$(\\H)" str))
  (.. (native-eval (.. key " := " (escape value)))
      value))

(export (native-name _set) 1)


(begin
  (define `(test value)
    (_set "tmp_set_test" value)
    (expect (native-var "tmp_set_test") value))
  (test "a\\b#c\\#\\\\$v\nz"))


;; Assign a recursive variable, given the code to be evaluated.  The
;; resulting value will differ, but the result of its evaluation should be
;; the same as that of VALUE.
;;
(define `(_setfn name value)
  &native
  (native-eval (.. name " = $(or )" (subst "\n" "$(\\n)" "#" "$(\\H)" value))))


(begin
  (define `(test var-name)
    (define `out (.. "~" var-name))
    (_setfn out (native-value var-name))
    (expect (native-var var-name) (native-var out)))

  (native-eval "define TX\n   abc   \n\n\nendef\n")
  (test "TX")
  (native-eval "TX = a\\\\\\\\c\\#c")
  (test "TX")
  (native-eval "TX = echo '#-> x'")
  (test "TX"))


;; Return value of VAR, evaluating it only the first time.
;;
(define (_once var)
  &native
  (define `cacheVar (.. "_|" var))

  (if (bound? cacheVar)
      (native-var cacheVar)
      (_set cacheVar (native-var var))))

(export (native-name _once) nil)

(begin
  ;; test _once
  (native-eval "fv = 1")
  (native-eval "ff = $(fv)")
  (expect 1 (_once "ff"))
  (native-eval "fv = 2")
  (expect 2 (native-var "ff"))
  (expect 1 (_once "ff")))


;; Dynamic state during property evaluation enables `.`, `C`, `A`, and
;; `super`:
;;    C = C
;;    A = A
;;
(declare C &native)
(declare A &native)



;; This "mock" _error records the last error for testing
;;
(define *last-error* nil)
(define (_error msg)
  &native
  (set *last-error* msg))



;; Construct an E1 (undefined property) error message
;;
(define `(e1-msg who outVar class arg)
  (define `prop
    (lastword (subst "." " " outVar)))

  (define `who-desc
    (cond
     ;; {inherit}
     ((filter "^&%" who) " from {inherit} in")
     ;; {prop}
     ((filter "^%" who) (.. " from {" prop "} in"))
     ;; $(call .,P,$0)
     (else "during evaluation of")))

  (define `cause
    (cond
     ((undefined? (.. class ".inherit"))
      (.. ";\n" class "is not a valid class name "
          "(" class ".inherit is not defined)"))
     (who
      (foreach (src-var (patsubst "&%" "%" (patsubst "^%" "%" who)))
        (.. who-desc ":\n" src-var " = " (native-value src-var))))))

  (.. "Reference to undefined property '" prop "' for "
      class "[" arg "]" cause "\n"))


;; Report error: undefined property
;;    Property 'P' is not defined for C[A]
;;    + C[A] was used as a target, but 'C.inherit' is not defined.
;;    + Property 'P' is not defined for C[A]; Used by {P} in DEFVAR.
;;    + '{inherit}' from DEFVAR failed for C[A].  Ancestor classes = ....
;;
(define (_getE1 outVar _ _ who)
  &native
  (_error (e1-msg who outVar C A)))

(export (native-name _getE1) 1)


;; Get the inheritance chain for a class (the class and its inherited
;; classes, transitively).
;;
(define (_chain c)
  &native
  (._. c
       (foreach (sup (native-var (.. c ".inherit")))
         (_chain sup))))

(export (native-name _chain) nil)


(define `(scopes class)
  (define `cache-var (.. "&|" class))

  (or (native-var cache-var)
      (_set cache-var (_chain class))))


;; Return all inherited definitions of P for CLASS
;;
(define (_& p)
  &native
  (strip
   (foreach (c (scopes C))
     (if (undefined? (.. c "." p))
         nil
         (.. c "." p)))))

(export (native-name _&) 1)


;; User-defined C[A].PROP var
(define `(cap-var prop) (.. C "[" A "]." prop))

;; Compiled property PROP for class C
(define `(cp-var prop)  (.. "&" C "." prop))

(declare (_cp outVar chain nextOutVar who) &native)

(define `(_cp-cache outVar chain nextOutVar who)
  (if (native-value outVar)
      outVar
      (_cp outVar chain nextOutVar who)))

;; Compile first definition in CHAIN, writing result to OUTVAR, returning
;; OUTVAR.  NEXTOUTVAR = outVar for next definition in chain (used only when
;; the first definition contains {inherit}.
;;
;; A)  &C[A].P  "C[A].P B.P A.P"  &C.P
;;     &C.P     "B.P A.P"         _&C.P
;;     _&C.P    "A.P"             __&C.P
;;
;; B)  &C.P     "B.P A.P"        _&C.P
;;     _&C.P    "A.P"            __&C.P
;;
(define (_cp outVar defVars nextOutVar who)
  &native

  (define `success
    (foreach (srcVar (word 1 defVars))
      (define `src
        (native-value srcVar))

      (define `inherit-var
        (_cp-cache nextOutVar
                   (rest defVars)
                   (.. "_" nextOutVar)
                   (.. "^" outVar)))

      (define `out
        (if (recursive? srcVar)
            (subst "{" "$(call .,"
                   "}" (.. ",^" srcVar ")")
                   (if (findstring "{inherit}" src)
                       (subst "{inherit}" (.. "$(call " inherit-var ")")
                              src)
                       src))
            (subst "$" "$$" src)))

      (.. (_setfn outVar out)
          ;;(print outVar " = " (native-value outVar))
          outVar)))

  (or success
      (_getE1 outVar defVars nextOutVar who)
      outVar))

(export (native-name _cp) nil)


;; Evaluate property P for instance C[A]  (don't cache result)
;;
(define (_! p who)
  &native
  (native-call
   (if (undefined? (cap-var p))
       (_cp-cache (cp-var p) (_& p) (.. "_" (cp-var p)) who)
       ;; don't bother checking
       (_cp (.. "&" (cap-var p))
           (._. (cap-var p) (_& p))
           (cp-var p)
           who))))

(export (native-name _!) nil)


;; Evaluate property P for current instance (given by dynamic C and A)
;; and cache the result.
;;
;;  WHO = requesting target ID
;;
;; Performance notes:
;;  * . results are cached (same C, A, P => fast access)
;;  * &C.P is cached (same C => just a variable reference)
;;
(define (. p ?who)
  &native
  (define `cache-var
    (.. "~" C "[" A "]." p))

  (if (simple? cache-var)
      (native-var cache-var)
      (_set cache-var (_! p who))))

(export (native-name .) nil)


;; Extract class name from ID stored in variable `A`.  Return (_getE) if
;; class does not contain "[" or begins with "[".
;;
(define `(extractClass)
  (subst "[" "" (filter "%[" (word 1 (subst "[" "[ " A)))))

;; Extract argument from ID stored in variable `A`, given class name `C`.
;; Call _getE0 and return nil if argument is empty.
;;
(define `(extractArg)
  (subst (.. "&" C "[") nil (.. "&" (patsubst "%]" "%" A))))


;; Report error: mal-formed instance name
;;
(define (_getE0)
  &native
  ;; When called from `get`, A holds the instance name
  (define `id A)

  (define `reason
    (if (extractClass)
        "empty ARG"
        (if (filter "[%" id)
            "empty CLASS"
            "missing '['")))

  (_error (.. "Mal-formed instance name '" id "'; " reason " in CLASS[ARG]")))

(export (native-name _getE0) 1)


(define (get p ids)
  &native
  (foreach (A ids)
    (if (filter "%]" A)
        ;; instance
        (foreach (C (or (extractClass) (_getE0)))
          (foreach (A (or (extractArg) (_getE0)))
            (. p)))
        ;; file
        (foreach (C "File")
          (or (native-var (.. "File." p))
              ;; error case...
              (. p))))))

;; Override automatic variable names so they will be visible to otheeginr
;; functions as $C and $A.
(export (native-name get) nil "A C A")


(begin
  (set-native-fn "A.inherit" "")
  (set-native-fn "B1.inherit" "A")
  (set-native-fn "B2.inherit" "A")
  (set-native-fn "C.inherit" "B1 B2")

  (expect 1 (see "not a valid class" (e1-msg nil nil "CX" "a")))
  (expect 1 (see "from {x} in:\nC.foo =" (e1-msg "^C.foo" "_&C.x" "C" "a")))
  (expect 1 (see "from {inherit} in:\nB.x =" (e1-msg "^&B.x" "_&C.x" "C" "a")))
  (expect 1 (see "during evaluation of:\nB.x =" (e1-msg "&B.x" "_&C.x" "C" "a")))

  (expect (strip (scopes "C")) "C B1 A B2 A")
  (expect (strip (scopes "C")) "C B1 A B2 A")

  (set-native-fn "A.x" "(A.x:$C)")
  (set-native-fn "A.y" "(A.y)")
  (set-native    "A.i" " (A.i) ")

  (set-native-fn "B1.y" "(B1.y)")
  (set-native-fn "B2.y" "(B2.y)")

  (set-native-fn "C.z" "(C.z)")
  (set-native-fn "C.i" "<C.i:{inherit}>")        ;; recursive w/ {inherit}

  (set-native    "C[a].s" "(C[a].s:$C[$A]{x})")  ;; simple
  (set-native-fn "C[a].r" "(C[a].r:$C[$A])")     ;; recursive
  (set-native-fn "C[a].p" "(C[a].p:{x})")        ;; recursive w/ prop
  (set-native-fn "C[a].i" "<C[a].i:{inherit}>")  ;; recursive w/ {inherit}

  (let-global ((C "C")
               (A "a"))
    ;; chain
    (expect (_& "z") "C.z")
    (expect (_& "x") "A.x A.x")
    (expect (_& "y") "B1.y A.y B2.y A.y")

    ;; compile-src & _cc
    ;;(expect (compile-src "C[a].s" "-" "") "(C[a].s:$$C[$$A]{x})")
    ;;(expect (compile-src "C[a].p" "-" "") "(C[a].p:${call .,x})")

    ;;(expect (compile-src "C[a].i" "xCP" "C.i A.i") "<C[a].i:$(xCP)>")
    ;;(expect (native-value "xCP") "$(or )<C.i:$(_xCP)>")
    ;;(expect (native-value "_xCP") "$(or ) (A.i) ")

    ;; _cp
    (expect (_cp "cpo1" "C[a].s" "_cpo1" nil) "cpo1")
    (expect (native-value "cpo1") "$(or )(C[a].s:$$C[$$A]{x})")
    (expect (_cp "cpo2" "C[a].p" "_cpo2" nil) "cpo2")
    (expect (native-value "cpo2") "$(or )(C[a].p:$(call .,x,^C[a].p))")
    (expect (_cp "cpo3" "C[a].i C.i A.i" "_cpo3" nil) "cpo3")
    (expect (native-value "cpo3") "$(or )<C[a].i:$(call _cpo3)>")
    (expect (native-value "_cpo3") "$(or )<C.i:$(call __cpo3)>")
    (expect (native-value "__cpo3") "$(or ) (A.i) ")

    ;; _!

    (expect (_! "s" nil) "(C[a].s:$C[$A]{x})")      ;; non-recursive CAP
    (expect (_! "r" nil) "(C[a].r:C[a])")           ;; recursive CAP

    (expect (_! "x" nil) "(A.x:C)")                 ;; undefined CAP
    (expect (native-value "&C.x") "$(or )(A.x:$C)")
    (expect (_! "x" nil) "(A.x:C)")

    (expect (_! "p" nil) "(C[a].p:(A.x:C))")        ;; recursive CAP w/ prop
    (expect (_! "i" nil) "<C[a].i:<C.i: (A.i) >>")  ;; recursive CAP w/ inherit

    ;; .

    (expect (. "x") "(A.x:C)")
    (expect (. "x") "(A.x:C)")  ;; again (after caching)

    nil)

  (set-native-fn "File.id" "$C[$A]")
  (expect (get "x" "C[a]") "(A.x:C)")
  (expect (get "id" "f") "File[f]")

  ;; caching of &C.P

  (expect "$(or )(A.x:$C)" (native-value "&C.x"))
  (set-native-fn "&C.x" "NEW")
  (expect (get "x" "C[b]") "NEW")
  (set-native-fn "C[i].x" "<{inherit}>")
  (expect (get "x" "C[i]") "<NEW>")

  ;; error reporting

  (define `(error-contains str)
    (expect 1 (see str *last-error*)))

  (expect (get "p" "[a]") nil)
  (error-contains "'[a]'; empty CLASS in CLASS[ARG]")

  (expect (get "p" "Ca]") nil)
  (error-contains "'Ca]'; missing '[' in CLASS[ARG]")

  (expect (get "p" "C[]") nil)
  (error-contains "'C[]'; empty ARG in CLASS[ARG]")

  (expect (get "asdf" "C[a]") nil)
  (error-contains "undefined")

  (set-native-fn "C.e1" "{inherit}")
  (expect (get "e1" "C[a]") nil)
  (error-contains "undefined")
  (error-contains "from {inherit} in:\nC.e1 = {inherit}")

  (set-native-fn "C[a].e2" "{inherit}")
  (expect (get "e2" "C[a]") nil)
  (error-contains (.. "undefined property 'e2' for C[a] from "
                      "{inherit} in:\nC[a].e2 = {inherit}"))

  (set-native-fn "C.eu" "{undef}")
  (expect (get "eu" "C[a]") nil)
  (error-contains (.. "undefined property 'undef' for C[a] "
                      "from {undef} in:\nC.eu = {undef}"))

  nil)


;;----------------------------------------------------------------
;; Misc
;;----------------------------------------------------------------

(export-comment " misc")

(define `(isInstance target)
  (filter "%]" target))


;; Mock implementation of `get`

;; (define *props* nil)  ;; "canned" answers
;;
;; (define (get prop id)
;;   &native
;;
;;   (define `key (.. id "." prop))
;;
;;   (cond
;;    ((not (isInstance id))
;;     (dict-get prop {out: id}))
;;
;;    ((not (dict-find key *props*))
;;     (expect key "NOTFOUND"))
;;
;;    (else
;;     (dict-get key *props*))))
;;

(define OUTDIR
  &native
  ".out/")


(define (_isIndirect target)
  &native
  (findstring "*" (word 1 (subst "[" "[ " target))))

;; We expect this to be provided by minion.mk
;;(export (native-name _isIndirect) 1)


(define (_ivar id)
  &native
  (lastword (subst "*" " " id)))

(export (native-name _ivar) 1)


(define `(pair id file)
  (.. id "$" file))

(define (_pairIDs pairs)
  &native
  (filter-out "$%" (subst "$" " $" pairs)))

(export (native-name _pairIDs) 1)


(define (_pairFiles pairs)
  &native
  (filter-out "%$" (subst "$" "$ " pairs)))

(export (native-name _pairFiles) 1)

(expect "a.c" (_pairIDs "a.c"))
(expect "C[a.c]" (_pairIDs "C[a.c]$a.o"))

(expect "a.c" (_pairFiles "a.c"))
(expect "a.o" (_pairFiles "C[a.c]$a.o"))



;; Infer intermediate instances given a set of input IDs and their
;; corresponding output files.
;;
;; PAIRS = list of "ID$FILE" pairs, or just "FILE"
;;
(define (_inferPairs pairs inferClasses)
  &native
  (if inferClasses
      (foreach (p pairs)
        (define `id (_pairIDs p))
        (define `file (_pairFiles p))

        (define `inferred
          (word 1
                (filter "%]"
                        (patsubst (.. "%" (or (suffix file) "."))
                                  (.. "%[" id "]")
                                  inferClasses))))

        (or (foreach (i inferred)
              (pair i (get "out" i)))
            p))
      pairs))

(export (native-name _inferPairs) nil)


(set-native "IC[a.c].out" "out/a.o")
(set-native "IP[a.o].out" "out/P/a")
(set-native "IP[IC[a.c]].out" "out/IP_IC/a")

(expect (_inferPairs "a.x a.o IC[a.c]$out/a.o" "IP.o")
        "a.x IP[a.o]$out/P/a IP[IC[a.c]]$out/IP_IC/a")


;;----------------------------------------------------------------
;; Argument string parsing
;;----------------------------------------------------------------

(export-comment " argument parsing")

(define (_argError arg)
  &native
  (subst ":[" "<[>" ":]" "<]>" arg))

(VF! (native-name _argError))


;; Protect special characters that occur between balanced brackets.
;; To "protect" them we de-nature them (remove the special prefix
;; that identifies them as syntactically significant).
;;
(define (_argGroup arg ?prev)
  &native
  ;; Split at brackets
  (define `a (subst ":[" " :[" ":]" " :]" arg))

  ;; Mark tail of "[..." with extra space
  (define `b (patsubst ":[%" ":[% " a))

  ;; Merge "[..." with immediately following "]", and mark with trailing ":"
  (define `c (subst "  :]" "]: " b))

  ;; Denature delimiters within matched "[...]"
  (define `d (foreach (w c)
               (if (filter "%:" w)
                   ;; Convert specials to ordinary chars & remove trailing ":"
                   (subst ":" "" w)
                   w)))

  (define `e (subst " " "" d))

  (if (findstring ":[" (subst "]" "[" arg))
      (if (findstring arg prev)
          (_argError arg)
          (_argGroup e arg))
      arg))

(export (native-name _argGroup) nil)


;; Construct a hash from an argument.  Check for balanced-ness in
;; brackets.  Protect "=" and "," when nested within brackets.
;;
(define (_argHash2 arg)
  &native

  ;; Mark delimiters as special by prefixing with ":"
  (define `(escape str)
    (subst "[" ":[" "]" ":]" "," ":," "=" ":=" str))

  (define `(unescape str)
    (subst ":" "" str))

  (unescape
    (foreach (w (subst ":," " " (_argGroup (escape arg))))
      (.. (if (findstring ":=" w) "" "=") w))))

(export (native-name _argHash2) 1)


;; Construct a hash from an instance argument.
;;
(define (_argHash arg)
  &native
  (if (or (findstring "[" arg) (findstring "]" arg) (findstring "=" arg))
      (_argHash2 arg)
      ;; common, fast cast
      (.. "=" (subst "," " =" arg))))

(export (native-name _argHash) 1)

(expect (_argHash "a=b=c,d=e,f,g") "a=b=c d=e =f =g")
(expect (_argHash "a") "=a")
(expect (_argHash "a,b,c") "=a =b =c")
(expect (_argHash "C[a]") "=C[a]")
(expect (_argHash "C[a=b]") "=C[a=b]")
(expect (_argHash "x=C[a]") "x=C[a]")
(expect (_argHash "c[a,b=1!R[]],d,x=y") "=c[a,b=1!R[]] =d x=y")
(expect (_argHash "c[a,b=1[]],d,x=y")   "=c[a,b=1[]] =d x=y")
(expect (_argHash "c[a,b=1[]],d,x=y][") "=c[a,b=1[]] =d x=y<]><[>")

(expect (_argHash ",") "= =")
(expect (_argHash ",a,b,") "= =a =b =")


;; Get matching values from a hash
;;
(define (_hashGet hash ?key)
  &native
  (define `pat (.. key "=%"))
  (patsubst pat "%" (filter pat hash)))

(export (native-name _hashGet) nil)


(expect (_hashGet "=a =b x=y" "") "a b")
(expect (_hashGet "=a =b x=y" "x") "y")


;;----------------------------------------------------------------
;; Output file name generation
;;----------------------------------------------------------------

(export-comment " output file name generation")

;; The chief requirement for output file names is that conflicts must be
;; avoided.  Avoiding conflicts is complicated by the inference feature, which
;; creates multiple ways of expressing the same thing.  For example,
;; `Program[foo.c]` vs. `Program[Compile[foo.c]]` produce equivalent results,
;; but they are different instance names, and as such must have different
;; output file names.
;;
;; The strategy for avoiding conflicts begins with including all components of
;; the instance name in the output directory.  For readability, however, we
;; re-arrange them, and we avoid repeating the output file name in the
;; directory name.  We do retain the input file extension, since that will
;; often not appear in `outName`.  We also encode ".." and "." path elements
;; and leading "/" for safety and to avoid aliasing.  [The instance names
;; `C[f]` and `C[./f]` need different output files.]
;;
;;     Instance Name          outDir                     outName
;;     --------------------   ----------------------     -------------
;;     CLASS[DIRS/NAME.EXT]   OUTDIR/CLASS.EXT/DIRS/     NAME{outExt}
;;     Compile[f.c]           .out/Compile.c/            f.o
;;     Compile[d/f.cpp]       .out/Compile.cpp/d/        f.o
;;     Compile[.././f.c]      .out/Compile.c/_../_./     f.o
;;     Compile[/d/f.c]        .out/Compile.c/_root_/d/   f.o
;;
;; When the argument is an instance (not a file name), we obtain
;; "DIRS/NAME.EXT" from `.<` (the output file of the first argument value)
;; rather than the argument itself, and we suffix "CLASS.EXT" with "_" to
;; distinguish it from the `CLASS[FILE]` form.  Finally, for readability, we
;; collapse "CLASS.EXT_/OUTDIR/..." to "CLASS.EXT_...":
;;
;;     Instance Name           outDir                      outName
;;     ---------------------   -------------------------   -------
;;     Program[Compile[f.c]]   .out/Program.o_Compile.c/   f
;;     Program[f.c]            .out/Program.c/             f        [*]
;;
;; [*] Note on handling inference: We compute .outDir based on the named
;;     FILE (f.c) , not on the inferred `.out/Compile.c/f.o`.  Otherwise,
;;     the result would collide with Program[Compile[f.c]].
;;
;; When the argument is an indirection, we use the variable name as the basis
;; for the file name, and we decorate `outDir`.
;;
;;     Instance Name          outDir                     outName
;;     --------------------   ----------------------     -----------
;;     CLASS[*VAR]            OUTDIR/CLASS_@/            VAR{outExt}
;;     CLASS[C2*VAR]          OUTDIR/CLASS_C2@/          VAR{outExt}
;;
;; When the argument is complex (with named values or comma-delimited values)
;; we include the entirety of the argument in the directory, after these
;; transformations:
;;
;;   1. Enode unsafe characters
;;   2. Replace the first unnamed argument with a special character
;;      sequence.  This avoids excessively long directory names and reduces
;;      the number of directories needed for a large project.
;;
;;     Instance Name           outDir                          outName
;;     ---------------------   -----------------------------   ------------
;;     CLASS[D/NAME.EXT,...]   OUTDIR/CLASS.EXT__{encArg}/D/   NAME{outExt}
;;     P[d/a.c,x.c,opt=3]      .out/P.c__@1,x.c,opt@E3/d/      a
;;
;; Output file names should avoid Make and shell special characters, so that
;; we do not need to quote them.  We rely on the restrictions of instance
;; syntax.  Here are the ASCII punctuation characters legal in Minion class
;; names, arguments, ordinary (source file) target IDs, and comma-delimited
;; argument values, alongside those unsafe in Bash and Make:
;;
;; File:   - + _ @ { } . / ^ ~
;; Class:  - + _ @ { } .       !
;; Value:  - + _ @ { } . / ^ ~ !   = * [ ]
;; Arg:    - + _ @ { } . / ^ ~ ! , = * [ ]
;; ~Make:                    ~     = * [ ] ? # $ % ; \ :
;; ~Bash:                    ~ !     * [ ] ? # $ % ; \   | & ( ) < > ` ' "
;;
;;
;; When encoding an argument for inclusion in a directory name, we use the
;; following substitutions:
;;
;;   @ [ ] = * ! ~ /  -->  @A @+ @- @E @_ @B @T @D
;;   ARG1  -->  @1
;;



;; Encode all characters that may appear in class names or arguments with
;; fsenc characters.
;;
(define (_fsenc str)
  &native

  (subst "@" "@0"
         "|" "@1"
         "[" "@+"
         "]" "@-"
         "=" "@E"
         "*" "@_"
         "!" "@B"
         "~" "@T"
         "/" "@D"
         str))

(export (native-name _fsenc) 1)


;; Encode the directory portion of path with fsenc characters
;; Result begins and ends with "/".
;;
(define `(safe-path path)
  (subst "/" "//"
         "/_" "/__"
         "/./" "/_./"
         "/../" "/_../"
         "//" "/"
         "//" "/_root_/"
         (.. "/" path)))

(expect (safe-path "a.c") "/a.c")
(expect (safe-path "d/c/b/a") "/d/c/b/a")
(expect (safe-path "./../.d/_c/.a") "/_./_../.d/__c/.a")


;; _outBasis for indirection arguments
;;   C*var    -->   _C@/var
;;   C*D*var  -->   _C@_D@/var
(define (_outBI arg)
  &native
  ;; E.g.: "C@ _D@ _dir@Dvar"
  (define `a (subst "@_" "@ _" "@D" "/" (_fsenc arg)))
  ;; E.g.: "_C@_D@ _dir@Dvar"
  (define `b (subst " |" "" (.. "_ " (patsubst "%@" "|%@" a))))
  (subst " _" "/" b))

;; _outBasis for simple arguments
(define (_outBS arg file class outExt)
  &native
  (define `(collapse x)
    (patsubst (.. "_/" OUTDIR "%") "_%" x))

  (.. (_fsenc class)
      (if (_isIndirect arg)
          ;; indirection
          (_outBI arg)
          ;; file or instance
          (.. (if (findstring "%" outExt)
                  ""
                  (suffix file))
              (collapse
               (.. (if (isInstance arg) "_")
                   (safe-path file)))))))

;; _outBasis for complex arguments
(define (_outBC arg file class outExt arg1)
  &native
  (_outBS arg1 (or file "default")
          (.. class (subst (.. "_" arg1 ",") "_|," (.. "_" arg)))
          outExt))

;;  arg = this instance's argument
;;  file = first input file (prior to any rule inference)
;;  class = this instance's class
;;  argHash = (_argHash arg) [or "=x" if we know it's simple]
;;  outExt = pattern for constructing output file's extension
;;           If it does not contain "%", we include the input file's
;;           extension in the class directory.
;;
(define (_outBasis arg file class outExt argHash)
  &native

  (define `argIsSimple
    (if (word 2 argHash) nil (filter "=%" argHash)))

  ;; "Simple" arguments have no commas and no named values
  (if argIsSimple
      (_outBS arg file class outExt)
      (_outBC arg file class outExt (word 1 (_hashGet argHash)))))

(export (native-name _outBI) 1)
(export (native-name _outBS) 1)
(export (native-name _outBC) 1)
(export (native-name _outBasis) 1)


(begin
  ;; test _outBasis

  (define `(test class arg out)
    (define `aHash (_argHash arg))
    (define `arg1 (word 1 (_hashGet aHash)))

    (define `file
      (cond
       ((filter "%]" arg1) (get "out" arg1))
       ((findstring "*" arg) ".out/C/a.o")
       (else arg1)))

    (define `outExt
      (cond ((eq? "C" class) ".o")
            ((eq? "P" class) "")
            (else "%")))

    (expect (_outBasis arg file class outExt aHash) out))


  (set-native "File[d/a.c].out" "d/a.c")
  (set-native "C[a.c].out" ".out/C.c/a.o")
  (set-native "C[d/a.c].out" ".out/C.c/d/a.o")


  ;; C[FILE]
  (test "C" "a.c"          "C.c/a.c")
  (test "C" "d/a.c"        "C.c/d/a.c")
  (test "D" "d/a.c"        "D/d/a.c")
  (test "C" "/.././a"      "C/_root_/_../_./a")
  (test "C@!" "a.c"        "C@0@B/a.c")

  ;; C[INSTANCE]
  (test "P" "C[a.c]"       "P.o_C.c/a.o")
  (test "P" "C[d/a.c]"     "P.o_C.c/d/a.o")
  (test "P" "File[d/a.c]"  "P.c_/d/a.c") ;; .out = d/a.c

  ;; C[*VAR]
  (test "C" "*var"         "C_@/var")

  ;; C[CLS*VAR]
  (test "C" "D*var"        "C_D@/var")
  (test "C" "D*E*var"      "C_D@_E@/var")
  (test "C" "D@E*d/var"    "C_D@0E@/d/var")

  ;; Complex
  (test "P" "a,b"          "P_@1,b/a")
  (test "P" "d/a.c,o=3"    "P_@1,o@E3.c/d/a.c")
  (test "Q" "d/a.c,o=3"    "Q_@1,o@E3/d/a.c")
  (test "P" "C[d/a.c],o=3" "P_@1,o@E3.o_C.c/d/a.o")
  (test "P" "x=1,y=2"      "P_x@E1,y@E2/default") ;; no unnamed arg
  (test "P" "*v,o=3"       "P_@1,o@E3_@/v")
  (test "P" "C*v,o=3"      "P_@1,o@E3_C@/v"))


;;--------------------------------

(show-exports)
