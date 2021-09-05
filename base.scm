;;----------------------------------------------------------------
;; Utility functions and macros
;;----------------------------------------------------------------

(require "core")
(require "export.scm")

;;--------------------------------
;; Symbols defined separately in minion.mk
;;--------------------------------

(print "Defined in minion.mk: \\n \\H \\L \\R [ ] OUTDIR _isIndirect")

(export-comment " base.scm")

(define OUTDIR
  &public
  &native
  ".out/")


(define (_isIndirect target)
  &public
  &native
  (findstring "@" (word 1 (subst "(" "( " target))))


(define \H &native &public "#")
(define \n &native &public "\n")
(set-native "\\L" "{")
(set-native "\\R" "}")


(define `(isInstance target)
  &public
  (filter "%)" target))


;;--------------------------------
;; Exported symbols
;;--------------------------------

;; Discriminate instances -- CLASS(ARGS) -- from other target list entries or
;; goals.  We assume ID is either a valid target (instance, make target),
;; alias, or indirection.
;;
;; Return truth if ID is an instance:  CLASS(ARGS)
(define (_isInstance id)
  &public
  &native
  (filter "%)" id))

(export (native-name _isInstance) 1)


;; Discriminate indirections (@VAR, C@VAR, D@C@VAR, ...) from other target
;; list entries or goals.  We assume ID is either a valid target (instance,
;; make target), alias, or indirection.
;;
(define (_isIndirect id)
  &public
  &native
  (findstring "@" (filter-out "%)" id)))

(export (native-name _isIndirect) 1)


;; Return truthy if NAME is an alias.
;;
(define (_isAlias name)
  &public
  &native
  (filter "s% r%" (._. (native-flavor (.. "Alias(" name ").in"))
                       (native-flavor (.. "Alias(" name ").command")))))

(export (native-name _isAlias) 1)


;; Translate goal NAME into an instance that will generate a rule whose
;; `out` will match NAME, *if* NAME is an alias, instance, or indirection.
;; Otherwise, it must be a valid target in a Make rule, and we return empty.
;;
(define (_goalID name)
  &native
  (if (_isAlias name)
      (.. "Alias(" name ")")
      (if (or (_isInstance name)
              (_isIndirect name))
          (.. "Goal(" name ")"))))

(export (native-name _goalID) 1)


;; Return the variable portion of indirection ID.
;;    @VAR, C@VAR, D@C@VAR  -->  VAR, VAR, VAR
;;
(define (_ivar id)
  &native
  (lastword (subst "@" " " id)))

(export (native-name _ivar) 1)


;; Return a pattern for expanding an indirection.
;;    @VAR, C@VAR, D@C@VAR  -->  %, C(%), D(C(%))
;;
(define (_ipat ref)
  &native
  (if (filter "@%" ref)
      "%"
      (subst " " ""
             (filter "%( %% )"
                     (.. (subst "@" "( " ref) " % " (subst "@" " ) " ref))))))

(export (native-name _ipat) 1)


(define (_expandX list)
  &native
  (foreach (w list)
    (or (filter "%)" w)
        (if (findstring "@" w)
            (patsubst "%" (_ipat w) (_expandX (native-var (_ivar w))))
            w))))

(export (native-name _expandX) nil)


;; Expand indirections in LIST
;;
(define (_expand list)
  &native
  (if (findstring "@" list)
      (_expandX list)
      list))

(export (native-name _expand) 1)


(begin
  ;; test _expand
  (set-native-fn "ev0" "")
  (set-native-fn "ev1" "a1 b1")
  (set-native-fn "ev2" "a2 @ev1 c@ev1 c(@v) D@C@ev1 E@ev0")
  (expect (_expand "E@ev0") "")
  (expect (_expand "a @ev2")
          "a a2 a1 b1 c(a1) c(b1) c(@v) D(C(a1)) D(C(b1))")
  nil)


;; Return non-nil if VAR has been assigned a value.
;;
(define `(undefined? var)
  &public
  (filter "u%" (native-flavor var)))

(define `(recursive? var)
  &public
  (filter "r%" (native-flavor var)))

(define `(simple? var)
  &public
  (filter "s%" (native-flavor var)))


;; Set variable named KEY to VALUE; return VALUE.
;;
;; We assume KEY does not contain ":", "=", "$", or whitespace.
(define (_set key value)
  &public
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
  &public
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

  (if (undefined? cacheVar)
      (_set cacheVar (native-var var))
      (native-var cacheVar)))

(export (native-name _once) nil)

(begin
  ;; test _once
  (native-eval "fv = 1")
  (native-eval "ff = $(fv)")
  (expect 1 (_once "ff"))
  (native-eval "fv = 2")
  (expect 2 (native-var "ff"))
  (expect 1 (_once "ff")))


;;----------------------------------------------------------------
;; Argument string parsing
;;----------------------------------------------------------------

(define (_argError arg)
  &native
  (subst "`(" "<(>" "`)" "<)>" arg))

(VF! (native-name _argError))


;; Protect special characters that occur between balanced brackets.
;; To "protect" them we de-nature them (remove the special prefix
;; that identifies them as syntactically significant).
;;
(define (_argGroup arg ?prev)
  &native
  ;; Split at brackets
  (define `a (subst "`(" " `(" "`)" " `)" arg))

  ;; Mark tail of "(..." with extra space
  (define `b (patsubst "`(%" "`(% " a))

  ;; Merge "(..." with immediately following ")", and mark with trailing "`"
  (define `c (subst "  `)" ")` " b))

  ;; Denature delimiters within matched "(...)"
  (define `d (foreach (w c)
               (if (filter "%`" w)
                   ;; Convert specials to ordinary chars & remove trailing "`"
                   (subst "`" "" w)
                   w)))

  (define `e (subst " " "" d))

  (if (findstring "`(" (subst ")" "(" arg))
      (if (findstring arg prev)
          (_argError arg)
          (_argGroup e arg))
      arg))

(export (native-name _argGroup) nil)


;; Construct a hash from an argument.  Check for balanced-ness in
;; brackets.  Protect ":" and "," when nested within brackets.
;;
(define (_argHash2 arg)
  &native

  ;; Mark delimiters as special by prefixing with "`"
  (define `(escape str)
    (subst "(" "`(" ")" "`)" "," "`," ":" "`:" str))

  (define `(unescape str)
    (subst "`" "" str))

  (unescape
    (foreach (w (subst "`," " " (_argGroup (escape arg))))
      (.. (if (findstring "`:" w) "" ":") w))))

(export (native-name _argHash2) 1)


;; Construct a hash from an instance argument.
;;
(define (_argHash arg)
  &public
  &native

  (if (or (findstring "(" arg) (findstring ")" arg) (findstring ":" arg))
      (_argHash2 arg)
      ;; common, fast cast
      (.. ":" (subst "," " :" arg))))

(export (native-name _argHash) 1)

(expect (_argHash "a:b:c,d:e,f,g") "a:b:c d:e :f :g")
(expect (_argHash "a") ":a")
(expect (_argHash "a,b,c") ":a :b :c")
(expect (_argHash "C(a)") ":C(a)")
(expect (_argHash "C(a:b)") ":C(a:b)")
(expect (_argHash "x:C(a)") "x:C(a)")
(expect (_argHash "c(a,b:1!R()),d,x:y") ":c(a,b:1!R()) :d x:y")
(expect (_argHash "c(a,b:1()),d,x:y")   ":c(a,b:1()) :d x:y")
(expect (_argHash "c(a,b:1()),d,x:y)(") ":c(a,b:1()) :d x:y<)><(>")

(expect (_argHash ",") ": :")
(expect (_argHash ",a,b,") ": :a :b :")


;; Get matching values from a hash
;;
(define (_hashGet hash ?key)
  &public
  &native
  (define `pat (.. key ":%"))
  (patsubst pat "%" (filter pat hash)))

(export (native-name _hashGet) nil)


(expect (_hashGet ":a :b x:y" "") "a b")
(expect (_hashGet ":a :b x:y" "x") "y")
