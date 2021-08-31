(require "core")
(require "export.scm")


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
  &public
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
  &public
  &native
  (define `pat (.. key "=%"))
  (patsubst pat "%" (filter pat hash)))

(export (native-name _hashGet) nil)


(expect (_hashGet "=a =b x=y" "") "a b")
(expect (_hashGet "=a =b x=y" "x") "y")
