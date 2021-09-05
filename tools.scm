;;----------------------------------------------------------------
;; Minion "Tools" functions
;;----------------------------------------------------------------

(require "core")
(require "export.scm")
(require "base.scm")
(require "objects.scm")

(export-comment " tools.scm")

;;----------------------------------------------------------------
;; _inferPairs
;;----------------------------------------------------------------


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
(expect "C(a.c)" (_pairIDs "C(a.c)$a.o"))

(expect "a.c" (_pairFiles "a.c"))
(expect "a.o" (_pairFiles "C(a.c)$a.o"))



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
                (filter "%)"
                        (patsubst (.. "%" (or (suffix file) "."))
                                  (.. "%(" id ")")
                                  inferClasses))))

        (or (foreach (i inferred)
              (pair i (get "out" i)))
            p))
      pairs))

(export (native-name _inferPairs) nil)


(set-native "IC(a.c).out" "out/a.o")
(set-native "IP(a.o).out" "out/P/a")
(set-native "IP(IC(a.c)).out" "out/IP_IC/a")

(expect (_inferPairs "a.x a.o IC(a.c)$out/a.o" "IP.o")
        "a.x IP(a.o)$out/P/a IP(IC(a.c))$out/IP_IC/a")


;; Return transitive dependencies of ID, excluding non-instances.  Memoize
;; results so this can be applied efficiently to many IDs in arbitrary
;; order.
;;
(define (_depsOf id)
  &native
  (define `memoVar (.. "_&deps-" id))
  (define `xdeps
    (sort (foreach (i (isInstance (get "needs" id)))
            (._. i (_depsOf i)))))
  (or (native-var memoVar)
      (_set memoVar (or xdeps " "))))

(export (native-name _depsOf) nil)


;; Return IDS and their transitive dependencies, excluding non-instances.
;;
(define (_rollup ids)
  &native
  (sort
   (foreach (i (isInstance ids))
     (._. i (_depsOf i)))))

(export (native-name _rollup) 1)


;; Return IDS and their transitive dependencies that are instances,
;; excluding those listed in EXCLUDES.  For instances that are in EXCLUDES,
;; use $($(_i_cachedNeeds)) rather than {needs} to obtain their
;; dependencies.
;;
(define (_rollupEx ids excludes ?seen)
  &native
  (define `(cachedNeeds id)
    (native-value (.. "_" id "_needs")))

  (define `deps
    (sort
     (._. (isInstance (get "needs" (filter-out excludes ids)))
          (foreach (i (filter excludes ids))
            (cachedNeeds i)))))

  (if ids
      (_rollupEx (filter-out (._. seen ids) deps)
                 excludes
                 (._. seen ids))
      (filter-out excludes seen)))

(export (native-name _rollupEx) nil)


(begin
  ;; Test _depsOf, _rollup, _rollupEx
  (set-native "R(a).needs" "R(b) R(c) x y z")
  (set-native "R(b).needs" "R(c) R(d) x y z")
  (set-native "R(c).needs" "R(d)")
  (set-native "R(d).needs" "R(e)")
  (set-native "R(e).needs" "")

  (expect (_depsOf "R(a)")
          "R(b) R(c) R(d) R(e)")

  (expect (_rollup "R(a)")
          "R(a) R(b) R(c) R(d) R(e)")

  (expect (strip (_rollupEx "R(a)" ""))
          "R(a) R(b) R(c) R(d) R(e)")

  (expect (strip (_rollupEx "R(a)" "R(d)"))
          "R(a) R(b) R(c)")

  (set-native "_R(d)_needs" "R(x)")
  (set-native "R(x).needs" "")

  (expect (strip (_rollupEx "R(a)" "R(d)"))
          "R(a) R(b) R(c) R(x)")
  nil)


;; Display the definition of variable NAME; prefix all lines with PREFIX
;;
(define (_showVar name prefix)
  &native
  (.. prefix
      (if (recursive? name)
          (if (findstring "\n" (native-value name))
              (subst "\n" (.. "\n" prefix)
                     (.. "define " name "\n" (native-value name) "\nendef"))
              (.. name " = " (native-value name)))
          (.. name " := " (subst "\n" "$(\\n)" (native-var name))))))

(export (native-name _showVar) 1)

(begin
  (set-native "sv-s" "a\nb")
  (set-native-fn "sv-r1" "a b")
  (set-native-fn "sv-r2" "a\nb")

  (expect (_showVar "sv-s" "P: ")  "P: sv-s := a$(\\n)b")
  (expect (_showVar "sv-r1" "P: ")  "P: sv-r1 = a b")
  (expect (_showVar "sv-r2" "P: ")  (.. "P: define sv-r2\n"
                                        "P: a\n"
                                        "P: b\n"
                                        "P: endef")))


(define (_showDefs2 s1 otherScopes tail)
  &native
  (define `(recur)
    (_showDefs2 (word 1 otherScopes) (rest otherScopes) tail))
  (define `var (.. s1 tail))

  (define `inherits
    (and (recursive? var)
         (findstring "{inherit}" (native-value var))))

  (if s1
      (if (undefined? var)
          (recur)
          (.. (_showVar var "   ")
              (if inherits
                  (.. "\n\n...wherein {inherit} references:\n\n" (recur)))))
      "... no definition in scope!"))

(export (native-name _showDefs2) nil)


(define (_showDefs id prop)
  &native
  (_showDefs2 id
              (scopes (word 1 (subst "(" " " id)))
              (.. "." prop)))

(export (native-name _showDefs) nil)

(begin
  (set-native-fn "SD(a).foo" "{inherit}")
  (set-native    "SD.inherit" "SDP")
  (set-native-fn "SDP.inherit" "SDPP")
  (set-native-fn "SDP.inherit" "SDPP")
  (set-native    "SDPP.foo" "b")

  (expect (_showDefs "SD(a)" "foo")
          (.. "   SD(a).foo = {inherit}\n"
              "\n"
              "...wherein {inherit} references:\n"
              "\n"
              "   SDPP.foo := b"))

  (expect (_showDefs "UNDEF(a)" "foo")
          (.. "... no definition in scope!"))

  nil)
