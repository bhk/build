;;----------------------------------------------------------------
;; Object system
;;----------------------------------------------------------------

(require "core")
(require "export.scm")
(require "base.scm")

(export-comment " objects.scm")


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
    (word 2 (subst "." ". " outVar)))

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
      (.. ";\n" class " is not a valid class name "
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
  &public
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
  &public
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
