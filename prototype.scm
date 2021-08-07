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
                  (.. "$(call " fname ",$1,$2)")
                  (.. "$(" fname ")")
                  (.. "$(call " fname ",$1,$2,$3)")
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
;; Misc.
;;----------------------------------------------------------------

(define `(isInstance target)
  (filter "%]" target))


;; Mock implementation of `get`

(define *props* nil)  ;; "canned" answers

(define (get prop id)
  &native

  (define `key (.. id "." prop))

  (cond
   ((not (isInstance id))
    (dict-get prop {out: id}))

   ((not (dict-find key *props*))
    (expect key "NOTFOUND"))

   (else
    (dict-get key *props*))))


(define OUTDIR
  &native
  ".out/")


(define (_isIndirect target)
  &native
  (findstring "*" (word 1 (subst "[" "[ " target))))


(define (_ivar id)
  &native
  (lastword (subst "*" " " id)))


(define `(pair id file)
  (.. id "$" file))

(define (_pairIDs pairs)
  &native
  (filter-out "$%" (subst "$" " $" pairs)))

(define (_pairFiles pairs)
  &native
  (filter-out "%$" (subst "$" "$ " pairs)))


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


(set *props*
     { "C[a.c].out": "out/a",
       "P[a.o].out": "out/P/a",
       "P[C[a.c]].out": "out/P_C/a" })

(expect (_inferPairs "a.x a.o C[a.c]$out/a.o" "P.o")
        "a.x P[a.o]$out/P/a P[C[a.c]]$out/P_C/a")

(VF! (native-name _ivar))
(VF! (native-name _isIndirect))

(show (native-name _isIndirect))
(show (native-name _ivar))
(show (native-name _pairIDs))
(show (native-name _pairFiles))
(show (native-name _inferPairs))


;;----------------------------------------------------------------
;; Argument string parsing
;;----------------------------------------------------------------


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


(VF! (native-name _argHash2))


;; Construct a hash from an instance argument.
;;
(define (_argHash arg)
  &native
  (if (or (findstring "[" arg) (findstring "]" arg) (findstring "=" arg))
      (_argHash2 arg)
      ;; common, fast cast
      (.. "=" (subst "," " =" arg))))


(define (argHash a) (_argHash a))

(expect (argHash "a=b=c,d=e,f,g") "a=b=c d=e =f =g")
(expect (argHash "a") "=a")
(expect (argHash "a,b,c") "=a =b =c")
(expect (argHash "C[a]") "=C[a]")
(expect (argHash "C[a=b]") "=C[a=b]")
(expect (argHash "x=C[a]") "x=C[a]")
(expect (argHash "c[a,b=1!R[]],d,x=y") "=c[a,b=1!R[]] =d x=y")
(expect (argHash "c[a,b=1[]],d,x=y")   "=c[a,b=1[]] =d x=y")
(expect (argHash "c[a,b=1[]],d,x=y][") "=c[a,b=1[]] =d x=y<]><[>")

(expect (argHash ",") "= =")
(expect (argHash ",a,b,") "= =a =b =")


;; Get matching values from a hash
;;
(define (_hashGet hash ?key)
  &native
  (define `pat (.. key "=%"))
  (patsubst pat "%" (filter pat hash)))

(expect (_hashGet "=a =b x=y" "") "a b")
(expect (_hashGet "=a =b x=y" "x") "y")


(print "#---- argument parsing\n")
(show (native-name _argGroup))
(show (native-name _argHash2))
(show (native-name _argHash))
(show (native-name _hashGet))

;;----------------------------------------------------------------
;; Output file name generation
;;----------------------------------------------------------------

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

(set *props*
     { "File[d/a.c].out": "d/a.c",
       "C[a.c].out": ".out/C.c/a.o",
       "C[d/a.c].out": ".out/C.c/d/a.o"})


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


;; outBasis is the target file of the first argument value file (*not
;; inferred*), or, in the case of an indirection, its variable name.
;;
;; ARG1 = first unnamed argument value
;;
(define (_outBasis arg1 inFiles)
  &native

  (if (_isIndirect arg1)
      (lastword (subst "@_" " " "@D" "/" (_fsenc arg1)))
      (or (word 1 inFiles) "default")))


(begin
  (define `(test arg1 inFiles name)
    (expect (_outBasis arg1 inFiles) name))

  (test "a.c" "a.c" "a.c")
  (test "a.c,b.c" "a.c b.c" "a.c")
  (test "C[a.c]" ".out/C.c/a.o" ".out/C.c/a.o")
  (test "*var" "a.c b.c"  "var")
  (test "*@~a/var" "a.c b.c"  "@0@Ta/var")
  (test "C*D*var" ".out/C_D/a.o" "var")
  (test nil nil "default")   ;; ARG = "x=1,y=2"
  )


;; Encode the directory portion of path with fsenc characters
;; Result begins and ends with "/".
;;
(define `(safe-dir path)
  (subst "/" "//"
         "/_" "/__"
         "/./" "/_./"
         "/../" "/_../"
         "//" "/"
         "//" "/_root_/"
         (dir (.. "/" path))))

(expect (safe-dir "a.c") "/")
(expect (safe-dir "d/c/b/a") "/d/c/b/")
(expect (safe-dir "./../.d/_c/.a") "/_./_../.d/__c/")


;; _outDir for indirection arguments
;;   C*var    -->   _C@/var
;;   C*D*var  -->   _C@_D@/var
(define (_outDirI arg basis)
  &native
  ;; E.g.: "C@ _D@ _dir@Dvar"
  (define `a (subst "@_" "@ _" (_fsenc arg)))
  (dir (.. "_" (subst " " "" (filter "%@" a)) "/" basis)))


;; _outDir for simple arguments
(define (_outDirS arg basis class)
  &native
  (define `(collapse x)
    (patsubst (.. "_/" OUTDIR "%") "_%" x))

  (.. (_fsenc class)
      (if (_isIndirect arg)
          ;; indirection
          (_outDirI arg basis)
          ;; file or instance
          (.. (suffix basis)
              (collapse
               (.. (if (isInstance arg) "_")
                   (safe-dir basis)))))))

;; _outDir for complex arguments
(define (_outDirC arg basis class arg1)
  &native
  (_outDirS arg1 basis
            (.. class (subst (.. "_" arg1 ",") "_|," (.. "_" arg)))))


;;  arg = instance argument
;;  argHash = (_argHash arg) [or "=x" if we know it's simple]
;;
(define (_outDir arg basis class argHash)
  &native

  (define `argIsSimple
    (if (word 2 argHash) nil (filter "=%" argHash)))

  ;; "Simple" arguments have no commas and no named values
  (if argIsSimple
      (_outDirS arg basis class)
      (_outDirC arg basis class (word 1 (_hashGet argHash)))))


(begin
  ;; test _outDir

  (define `(test class arg out)
    (define `ah (_argHash arg))
    (define `a1 (word 1 (_hashGet ah)))

    (define `inFiles
      (cond
       ((filter "%]" a1) (get "out" a1))
       ((findstring "*" arg) ".out/C/a.o .out/C/b.o")
       (else a1)))

    (define `basis
      (_outBasis a1 inFiles))

    (expect (_outDir arg basis class ah) out))


  ;; C[FILE]
  (test "C" "a.c"          "C.c/")
  (test "C" "d/a.c"        "C.c/d/")
  (test "C" "/.././a"      "C/_root_/_../_./")
  (test "C@!" "a.c"        "C@0@B.c/")

  ;; C[INSTANCE]
  (test "P" "C[a.c]"       "P.o_C.c/")
  (test "P" "C[d/a.c]"     "P.o_C.c/d/")
  (test "P" "File[d/a.c]"  "P.c_/d/") ;; .out = d/a.c

  ;; C[*VAR]
  (test "C" "*var"         "C_@/")

  ;; C[CLS*VAR]
  (test "C" "D*var"        "C_D@/")
  (test "C" "D*E*var"      "C_D@_E@/")
  (test "C" "D@E*d/var"    "C_D@0E@/d/")

  ;; Complex
  (test "P" "a,b"          "P_@1,b/")
  (test "P" "d/a.c,o=3"    "P_@1,o@E3.c/d/")
  (test "P" "C[d/a.c],o=3" "P_@1,o@E3.o_C.c/d/")
  (test "P" "x=1,y=2"      "P_x@E1,y@E2/") ;; no unnamed arg
  (test "P" "*v,o=3"       "P_@1,o@E3_@/")
  (test "P" "C*v,o=3"      "P_@1,o@E3_C@/"))


(VF! (native-name _fsenc))
(VF! (native-name _outBasis))
(VF! (native-name _outDir))
(VF! (native-name _outDirI))
(VF! (native-name _outDirS))
(VF! (native-name _outDirC))

(print "#---- output file generation\n")
(show (native-name _fsenc))
(show (native-name _outBasis))
(show (native-name _outDirI))
(show (native-name _outDirS))
(show (native-name _outDirC))
(show (native-name _outDir))

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

(print "#---- object system\n")
(show (native-name _&))
(show (native-name get) "o A C & v" "; ;; ;;; ;;;; ;;;;;")
(show (native-name _getCA) "A C & v" "; ;; ;;; ;;;; ;;;;;")
(show (native-name .))
(show (native-name super) 0 1)
(show (native-name _supErr))
