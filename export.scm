;;----------------------------------------------------------------
;; Facililities for "exporting" functions to Minion
;;----------------------------------------------------------------

(require "core")

(define *var-functions* nil)

;; Mark a function as safe to be replaced with a variable reference
;;  $(call FN,$1)    -> $(FN)
;;  $(call FN,$1,$2) -> $(FN)
;; Must be non-recursive, and must not have optional arguments.
;;
(define (VF! fn-name)
  &public
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
  &public

  ;; Avoid ";" because Minion uses `$;` for ","
  (define `vars-to (or vars-to-in "w x"))
  (define `vars-from (or vars-from-in "; ;; ;;; ;;;; ;;;;;"))

  (if is-vf
      (VF! fn-name))
  (set-native-fn fn-name
       (omit-calls
        (rename-vars (native-value fn-name) vars-from vars-to)))
  (set *exports* (conj *exports* fn-name)))


(define (export-text text)
  &public
  (set *exports* (conj *exports* (.. "=" text))))


;; Output a SCAM function as Make code, renaming automatic vars.
;;
(define (show-export fn-name)
  &public

  (define `minionized
    (subst "$  " "$(\\s)"     ;; SCAM runtime -> Minion make
           "$ \t" "$(\\t)"    ;; SCAM runtime -> Minion make
           "$ " ""            ;; not needed to avoid keywords in "=" defns
           "$(if ,,,)" "$;"   ;; SCAM runtime -> Minion make
           "$(if ,,:,)" ":$;" ;; SCAM runtime -> Minion make
           "$(&)" "$&"        ;; smaller, isn't it?
           "$`" "$$"          ;; SCAM runtime -> Minion make
           (native-value fn-name)))

  (define `escaped
    (subst "\n" "$(\\n)" "#" "\\#" minionized))

  (if (filter "s%" (native-flavor fn-name))
      (print fn-name " := " (native-var fn-name))
      (print fn-name " = " escaped)))


(define (show-exports)
  &public

  (foreach (e *exports*)
    (if (filter "=%" e)
        (print "\n" (first (patsubst "=%" "%" e)) "\n")
        (show-export (first e)))))

(at-exit show-exports)
