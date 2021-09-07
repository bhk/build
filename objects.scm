;;----------------------------------------------------------------
;; Object system
;;----------------------------------------------------------------

(require "core")
(require "export.scm")
(require "base.scm")

(export-comment " objects.scm")


;; Dynamic state during property evaluation enables `.`, `C`, and `A`:
;;   I = current instance, bound with `foreach`
;;   C = current class, bound with `foreach`
;;   A = function of I and C (but accessed as a variable)
(declare I &native)
(declare C &native)

;; Display an error and halt.  We call this function, instead of `error`, so
;; that is can be dynamically interecpted for testing purposes.
;;
(define (_error msg)
  &native
  (error msg))

(export (native-name _error) 1)


;; Return the class portion of an instance name, or nil if ID is a
;; valid file name instead.
;;
(define (_idC id)
  &native
  (if (findstring "(" id)
      (word 1 (subst "(" " " id))))

(export (native-name _idC) 1)


;; Return next level "up" in inheritance.  PARENTS = list of classes from
;; which to inherit.
;;
(define (_pup parents)
  &native
  (filter-out
   "&%" (.. (native-var (.. (word 1 parents) ".inherit")) " &" parents)))

(export (native-name _pup) 1)


;; Return the nearest ancestor parent list in which P is defined by the
;; first named class.  Return nil if there is no definition.
;;
(define (_walk parents p)
  &native
  (define `C1 (word 1 parents))
  (if parents
      (if (defined? (.. C1 "." p))
          parents
          (_walk (_pup parents) p))))

(export (native-name _walk) nil)


;; Construct an E1 (undefined property) error message
;;
;; WHO = referrer.  One of:
;;   &&OBJ => {PROP} in a property defn, where &OBJ is its compilation
;;   ^PARENTS => {inherit} in property definition (source) VAR
;;   OTHER => $(call .,PROP,OTHER)  ($0 of calling context)
;;
(define `(e1-msg who prop class id)
  ;; Recover a source variable from a compiled variable &OBJ or &&OBJ.
  ;; Compilations may be stored in two locations: &PARENTS.P and &C.P
  (define `src-var
    (if (filter "&%" who)
        (foreach (who-prop (lastword (subst "." " " who)))
          (.. (word 1 (_walk (word 1 (subst "." " " "&" " " who)) who-prop))
              "." who-prop))
        (if (filter "^%" who)
            (.. (subst "^" "" (word 1 who)) "." prop)
            who)))

  (define `who-desc
    (cond
     ;; {inherit}
     ((filter "^%" who) " from {inherit} in")
     ;; {prop}
     ((filter "&&%" who) (.. " from {" prop "} in"))
     ;; $(call .,P,$0)
     (else " during evaluation of")))

  (define `cause
    (cond
     ((undefined? (.. class ".inherit"))
      (.. ";\n" class " is not a valid class name "
          "(" class ".inherit is not defined)"))
     (who
      (.. who-desc ":\n" (_describeVar src-var)))))

  (.. "Undefined property '" prop "' for " id
      " was referenced" cause "\n"))


;; Report error: undefined property
;;
(define (_E1 _ p who)
  &native
  (_error (e1-msg who p C I)))

(export (native-name _E1) 1)


;; cap-memo holds a previously computed value of C(A).P.  Prior to that it
;; may momentarily hold the compilation of its definition.  We use [], not
;; (), because a literal ")" causes problems with native-var.
;;
(define `(cap-memo p)
  (.. "~" I "." p))


;; Compile a definition of P in the scope defined by PARENTS; return the
;; name of the variable holding the result.
;;
;; PARENTS must be the location of a definition of P, or nil.
;;
;; WHO = who referenced the property (see e1-msg)
;;
(define (_cx parents p who ?is-cap)
  &native
  (define `src-var (.. (word 1 parents) "." p))
  (define `memo-var (.. "&" parents "." p))
  (define `out-var (if is-cap (subst ")" "]" (cap-memo p)) memo-var))
  (define `inherit-var
    (_cx (_walk (if is-cap C (_pup parents)) p)
         p
         (.. "^" parents)))

  (define `obj
    (foreach (src-var src-var)
      (define `src
        (native-value src-var))
      (if (simple? src-var)
          (subst "$" "$$" (native-var src-var))
          (subst "{inherit}" (if (findstring "{inherit}" src)
                                 (.. "$(call " inherit-var ")"))
                 "{" "$(call .,"
                 "}" ",&$0)"
                 src))))

  (if parents
      (if (native-value memo-var)
          memo-var
          (_fset out-var obj))
      (_E1 parents p who)))

(export (native-name _cx) nil)


;; Return the name of the variable that holds the compilation of C[A].P
;;
(define (.& p who)
  &native
  (define `I.P (.. I "." p))
  (define `&C.P (.. "&" C "." p))

  (if (defined? I.P)
      (_cx I p who 1)
      (if (defined? &C.P)
          &C.P
          (_fset &C.P (native-value (_cx (_walk C p) p who))))))

(export (native-name .&) 1)


;; Evaluate property P for current instance (given by dynamic C and A)
;; and cache the result.
;;
;; WHO = requesting variable
;;
;; Performance notes:
;;  * memoization avoids exponential times
;;  * C(A).P value hit rate is about 50% for med-to-large projects
;;  * &C.P hit rate approaches 100% in large projects
;;  * We cannot directly "call" variables with ")" in their name, due
;;    to a quirk of Make.
;;
(define (. p ?who)
  &native
  (if (simple? (cap-memo p))
      (native-value (cap-memo p))
      (_set (cap-memo p) (native-call (.& p who)))))

(export (native-name .) nil)


;; Extract the class name from I, where I contains at least one "(".  Return
;; nil if I begins with "(" or does not end with ")".
;;
(define `(extractClass)
  (subst "|" "" (word 1 (subst "(" " | " (filter "%)" I)))))


;; Report error: mal-formed instance name
;;
(define (_E0)
  &native
  ;; When called from `get`, A holds the instance name
  (define `reason
    (if (filter "(%" I)
        "empty CLASS"
        (if (findstring "(" I)
            "missing ')'"
            "unbalanced ')'")))

  (_error (.. "Mal-formed instance name '" I "'; " reason " in CLASS(ARGS)")))

(export (native-name _E0) 1)


(define (A)
  &native
  (patsubst (.. C "(%)") "%" I))

(declare A &native)
(export (native-name A) nil)


(define (get p ids)
  &public
  &native

  (foreach (I ids)
    (if (findstring "(" I)
        ;; instance
        ;;    Save 5%:
        ;;    (if (simple? (cap-memo p))
        ;;        (native-value (cap-memo p))
        ;;        (foreach (C (or (extractClass) (_E0)))
        ;;          (_set (cap-memo p) (native-call (.& p nil)))))
        (foreach (C (or (extractClass) (_E0)))
          (. p))
        ;; file
        (if (findstring ")" I)
            (_E0)
            (foreach (C "File")
              (or (native-var (.. "File." p))
                  ;; error case...
                  (. p)))))))

;; Override automatic variable names to I and C for dynamic binding
(export (native-name get) nil "I C")

;;--------------------------------
;; describeDefn
;;--------------------------------

;; Like `_pup`, but also handles initial "C(A)" -> "C" inheritance step.
;;
(define `(pup0 id-or-parents)
  (or (_idC id-or-parents)
      (_pup id-or-parents)))


(define (_describeProp parents prop)
  &native
  (define `(recur)
    (_describeProp (pup0 parents) prop))

  (define `C1.P
    (.. (word 1 parents) "." prop))

  (define `has-inherit
    (and (recursive? C1.P)
         (findstring "{inherit}" (native-value C1.P))))

  (if parents
      (if (undefined? C1.P)
          (recur)
          (.. (_describeVar C1.P "   ")
              (if has-inherit
                  (.. "\n\n...wherein {inherit} references:\n\n" (recur)))))
      "Error: no definition found!"))

(export (native-name _describeProp) nil)


(define (_chain parents ?seen)
  &native
  (if parents
      (_chain (_pup parents) (._. seen (word 1 parents)))
      (strip seen)))

(export (native-name _chain) nil)


;;--------------------------------
;; Tests
;;--------------------------------

(set-native-fn "A.inherit" "")
(set-native-fn "B1.inherit" "A")
(set-native-fn "B2.inherit" "A")
(set-native-fn "C.inherit" "B1 B2")

(set-native-fn "A.x" "<A.x:$C>")
(set-native-fn "A.y" "<A.y>")
(set-native    "A.i" " (A.i) ")
(set-native-fn "B1.y" "<B1.y>")
(set-native-fn "B1.y2" "<B1.y2>")
(set-native-fn "B2.y" "<B2.y>")
(set-native-fn "C.z" "<C.z>")
(set-native-fn "C.i" "<C.i:{inherit}>")        ;; recursive w/ {inherit}
(set-native    "C(a).s" "<C(a).s:$C($A){x}>")  ;; simple
(set-native    "C(X(f)).s" "<C(X(f)).s>")      ;; simple
(set-native-fn "C(a).r" "<C(a).r:$C($A)>")     ;; recursive
(set-native-fn "C(a).p" "<C(a).p:{x}>")        ;; recursive w/ prop
(set-native-fn "C(a).i" "<C(a).i:{inherit}>")  ;; recursive w/ {inherit}

;; _walk
(expect (_walk "C" "z") "C")
(expect (_walk "C" "y") "B1 B2")
(expect (_walk "C" "x") "A B2")
(expect (_walk "C" "un") nil)
(expect (_walk "XX B2" "i") "A")

;; _chain

(expect (_chain "C") "C B1 A B2 A")

;; E1 "who" logic
(expect 1 (see "not a valid class" (e1-msg nil nil "CX" "a")))
(expect 1 (see "from {x} in:\nC.z =" (e1-msg "&&C.z" "x" "C" "a")))
(expect 1 (see "from {x} in:\nB1.y =" (e1-msg "&&C.y" "x" "C" "a")))
(expect 1 (see "from {x} in:\nB1.y =" (e1-msg "&&B1 B2.y" "x" "C" "a")))
(expect 1 (see "from {inherit} in:\nA.x =" (e1-msg "^A B" "x" "C" "a")))
(expect 1 (see "during evaluation of:\n_cx =" (e1-msg "_cx" "x" "C" "a")))

(let-global ((I "C(a)")
             (C "C"))

  ;; .&

  (define `(test.& prop name-out value-out)
    (expect (.& prop nil) name-out)
    (expect (native-call name-out) value-out))

  (test.& "x" "&C.x" "<A.x:C>")                  ;; no CAP
  (test.& "z" "&C.z" "<C.z>")
  (test.& "y" "&C.y" "<B1.y>")
  (test.& "y2" "&C.y2" "<B1.y2>")
  (test.& "s" "~C(a].s" "<C(a).s:$C($A){x}>")     ;; simple CAP
  (test.& "r" "~C(a].r" "<C(a).r:C(a)>")          ;; recursive CAP
  (test.& "p" "~C(a].p" "<C(a).p:<A.x:C>>")       ;; recursive CAP + {prop}
  (test.& "i" "~C(a].i" "<C(a).i:<C.i: (A.i) >>") ;; recursive CAP + {inh}

  ;; .

  (expect (. "x") "<A.x:C>")
  (expect (native-var (cap-memo "x")) "<A.x:C>")
  (expect (. "x") "<A.x:C>")  ;; again (after caching)
  (let-global ((I "C(X(f))"))
    (expect (. "s" nil) "<C(X(f)).s>"))           ;; challenging $A?

  nil)

(set-native-fn "File.id" "$C($A)")
(expect (get "x" "C(a)") "<A.x:C>")
(expect (get "id" "f") "File(f)")

;; caching of &C.P

(expect "<A.x:$C>" (native-value "&C.x"))   ;; assert: memo var was set
(set-native-fn "&C.x" "NEW")
(expect (get "x" "C(b)") "NEW")             ;; assert: uses memo

;; error reporting

(define *last-error* nil)
(define (trapError msg)
  (set *last-error* msg))

(define `(error-contains str)
  (expect 1 (see str *last-error*)))

(define `(expect-error expr value error-content)
  (let-global ((_error trapError))
    (set *last-error* nil)
    (expect expr value)
    (error-contains error-content)))

(expect-error (get "p" "(a)") nil
               "'(a)'; empty CLASS in CLASS(ARGS)")

(expect-error (get "p" "C(a") nil
              "'C(a'; missing ')' in CLASS(ARGS)")

(expect-error (get "p" "Ca)") nil
              "'Ca)'; unbalanced ')' in CLASS(ARGS)")

(expect-error (get "asdf" "C(a)") nil
              "Undefined")

(set-native-fn "C.e1" "{inherit}")
(expect-error (get "e1" "C(a)") nil
              "Undefined")
(error-contains "from {inherit} in:\nC.e1 = {inherit}")

(set-native-fn "C(a).e2" "{inherit}")
(expect-error (get "e2" "C(a)") nil
              (.. "Undefined property 'e2' for C(a) was referenced from "
                  "{inherit} in:\nC(a).e2 = {inherit}"))

(set-native-fn "C.eu" "{undef}")
(expect-error (get "eu" "C(a)") nil
              (.. "Undefined property 'undef' for C(a) was referenced "
                  "from {undef} in:\nC.eu = {undef}"))

;; _describeProp

(expect (_describeProp "C(a)" "i")
        (.. "   C(a).i = <C(a).i:{inherit}>\n"
            "\n"
            "...wherein {inherit} references:\n"
            "\n"
            "   C.i = <C.i:{inherit}>\n"
            "\n"
            "...wherein {inherit} references:\n"
            "\n"
            "   A.i :=  (A.i) "))

(expect (_describeProp "UNDEF(a)" "foo")
        (.. "Error: no definition found!"))
