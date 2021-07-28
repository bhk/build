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

(define (omit-calls body)
  (foldl (lambda (text fname)
           (subst (.. "$(call " fname ",$1)")
                  (.. "$(" fname ")")
                  text))
         body
         *var-functions*))


(define (swap fn names froms)
  (define `name (word 1 names))
  (define `from (word 1 froms))
  (define `reduced-fn
    (subst (.. "foreach " from ",") (.. "foreach " name ",")
           ;; if from is a single char, name must be also
           (.. "$" from) (.. "$" name)
           (.. "$(" from ")") (.. "$" name)
           fn))
  (if (not name)
      fn
      (swap reduced-fn (rest names) (rest froms))))


;; Output a SCAM function as Make code, renaming automatic vars.
;;
(define (show fn-name ?vars-to-in ?vars-from-in)
  ;; Avoid ";" since Minion uses $; for ","
  (define `vars-to (or vars-to-in "w x"))
  (define `vars-from (or vars-to-in "; ;;"))

  (define `fn-val (native-value fn-name))

  (print fn-name " = "
         (subst "$`" "$$"          ;; SCAM runtime -> Minion make
                "$  " "$(\\s)"     ;; SCAM runtime -> Minion make
                "$(if ,,,)" "$;"   ;; SCAM runtime -> Minion make
                "$(if ,,:,)" ":$;" ;; SCAM runtime -> Minion make
                "$(&)" "$&"        ;; smaller, isn't it?
                (omit-calls (swap fn-val vars-to vars-from)))
         "\n"))

;;----------------------------------------------------------------
;; Argument string parsing
;;----------------------------------------------------------------


;; Protect special characters that occur between balanced brackets.
;; To "protect" them we de-nature them (remove the special prefix
;; that identifies them as syntactically significant).
;;
(define (_argGroup arg errorFn ?prev)
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
          (native-call errorFn arg)
          (_argGroup e errorFn arg))
      arg))


;; Construct a hash from an argument.  Check for balanced-ness in
;; brackets.  Protect "=" and "," when nested within brackets.
;;
(define (_argHash2 arg errorFn)
  &native

  ;; Mark delimiters as special by prefixing with ":"
  (define `(escape str)
    (subst "[" ":[" "]" ":]" "," ":," "=" ":=" str))

  (define `(unescape str)
    (subst ":" "" str))

  (unescape
    (foreach (w (subst ":," " " (_argGroup (escape arg) errorFn)))
      (.. (if (findstring ":=" w) "" "=") w))))


;; Construct a hash from an argument.
;;
(define (_argHash arg errorFn)
  &native
  (if (or (findstring "[" arg) (findstring "]" arg) (findstring "=" arg))
      (_argHash2 arg errorFn)
      ;; common, fast cast
      (.. "=" (subst "," " =" arg))))


(define (argErr arg)
  (subst ":[" "<[>" ":]" "<]>" arg))

(define (argHash a) (_argHash a (native-name argErr)))

(expect (argHash "a=b=c,d=e,f,g") "a=b=c d=e =f =g")
(expect (argHash "a") "=a")
(expect (argHash "a,b,c") "=a =b =c")
(expect (argHash "C[a]") "=C[a]")
(expect (argHash "C[a=b]") "=C[a=b]")
(expect (argHash "x=C[a]") "x=C[a]")
(expect (argHash "c[a,b=1!R[]],d,x=y") "=c[a,b=1!R[]] =d x=y")
(expect (argHash "c[a,b=1[]],d,x=y")   "=c[a,b=1[]] =d x=y")
(expect (argHash "c[a,b=1[]],d,x=y][") "=c[a,b=1[]] =d x=y<]><[>")


;; Get matching values from a hash
;;
(define (_hashGet argHash key)
  &native
  (define `pat (.. key "=%"))
  (patsubst pat "%" (filter pat argHash)))

(expect (_hashGet "=a =b x=y" "") "a b")
(expect (_hashGet "=a =b x=y" "x") "y")


(print (string-len (.. _argGroup _argHash _argHash2)))
(print)

(show (native-name _argGroup))
(show (native-name _argHash2))
(show (native-name _argHash))
(show (native-name _hashGet))

(print "----------------------------------------------------------------")
(print)

;;----------------------------------------------------------------
;; Functions defined by Minion
;;----------------------------------------------------------------

(define `(bound? var)
  (if (filter "undef%" (native-flavor var)) "" var))

(define `(defined? var)
  (filter-out "undef%" (native-flavor var)))

(define `(memoIsSet key)
  (defined? key))

(define `(memoGet key)
  (native-var key))

;;----------------------------------------------------------------
;; Imports
;;----------------------------------------------------------------

;; Dynamic state during property evaulation enables `.`, `C`, `A`, and
;; `super`:
;;    & = word-encoded inheritance chain
;;    C = C
;;    A = A

(declare C &native)
(declare A &native)
(declare & &native)

(define _getErr &native "ERROR")

(define _dotErr &native "ERROR")

(define (_set key value)
  &native
  (set-native key value value))


;;----------------------------------------------------------------
;; Object system
;;----------------------------------------------------------------

(define `WD ";")

;; pack a list into one word
(define `(tw lst) (subst " " WD lst))

;; unpack a list from a word
(define `(fw w) (subst WD " " w))

(define `(key p c a)
  (.. "<" c "[" a "]." p ">"))

(define `(prop-chain p)
  (foreach (c (fw &))
    (.. c "." p " " c "[" A "]." p)))
;;  (patsubst "%" (.. "%." p " %[" A "]." p) (fw &)))

(define `(first-bound defs)
  (word 1 (foreach (v defs) (bound? v))))


;;--------------------------------
;; .
;;--------------------------------

(define `(rawDot p)
  (native-call (or (first-bound (prop-chain p))
                   "_dotErr")))

(define (. p)
  &native
  (if (memoIsSet (key p C A))
      (memoGet (key p C A))
      (rawDot p)))


;;--------------------------------
;; get
;;--------------------------------

;; Construct inheritance chain
(define (_& c)
  &native
  (if (filter "undef%" c)
      ""
      (._. c (foreach (sup (native-var (.. c ".inherit")))
               (_& sup)))))

;; Extract argument from OID: everything between first "[" and last "]"
;; Error if there is no "[".
;;
(define `(oidA oid)
  ;; w1 = "C[" or the entire oid if there is no "["
  (define `w1 (word 1 (subst "[" "[ " oid)))
  (or (patsubst "%]" "%" (subst (.. ":" w1) "" (.. ":" oid)))
      _getErr))

(expect (oidA "C[AC[A]]") "AC[A]")
(expect (oidA "[AC[A]]") "AC[A]")
(expect (oidA "C[AC]A]]") "AC]A]")
(expect (oidA "C[]") "ERROR")
(expect (oidA "CA]") "ERROR")

;; Extract class from OID, given the argument.  Error if class is empty.
;;
(define `(oidC oid a)
  (or (subst (.. "[" a "]:") "" (.. oid ":"))
      _getErr))

(expect (oidC "C[AC[A]]" "AC[A]") "C")
(expect (oidC "[AC[A]]" "AC[A]") "ERROR")


(define (_getCA p oid)
  &native
  (foreach (a (oidA oid))
    (foreach (c (oidC oid a))
      ;; check memo before building inheritance chain
      (define `k (key p c a))
      (define `wchain (tw (native-strip (_& c))))

      (if (memoIsSet k)
          (memoGet k)
          (_set k (foreach (& wchain)
                    (rawDot p)))))))

;; Get property for a single OID.  OID must be a construction or plain file
;; name; groups alias must have already been converted to constructions.
;;
(define `(getoid p oid)
  (if (filter "%]" oid)
      ;; construction syntax
      (_getCA p oid)
      ;; File: we don't handle inheritance or instance-specific definitions
      ;; in this case (not supported now because it would require
      ;; modification of built-in classes)
      (foreach (a oid)
        (foreach (c "File")
          (if (bound? (.. "File." p))
              (native-var (.. "File." p))
              _getErr)))))


(define (get p oids)
  &native
  (foreach (o (patsubst "@%" "Group[*%]" oids))
    (getoid p o)))


;;--------------------------------
;; Super
;;--------------------------------

(define `(current-prop current-fn)
  (lastword (subst "." " " current-fn)))

(define (_supErr fn ?found)
  &native
  (error (.. "$(super) called from function " fn
             (if found
                 " but there are no inherited definitions."
                 " which was not a property definition."))))

;; Return the name of the next function in the property chain.
;; To be used in "$(call $(super))"
;;
(define (super current-fn)
  &native
  (define `p
    (current-prop current-fn))

  (define `chain-after
    (fw (word 2 (subst (.. WD current-fn WD) "X "
                       (.. WD (tw (prop-chain p)) WD)))))

  (if (findstring (.. WD current-fn WD) (.. WD & WD))
      (or (first-bound chain-after)
          (_supErr current-fn 1))
      (_supErr current-fn)))

(show (native-name _&))
(show (native-name get) "o A C & v" "; ;; ;;; ;;;; ;;;;;")
(show (native-name _getCA) "A C & v" "; ;; ;;; ;;;; ;;;;;")
(show (native-name .))
(show (native-name super) 0 1)
(show (native-name _supErr))
