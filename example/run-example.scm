;; Generate example walkthrough

(require "core")
(require "io")
(require "getopts")

;; Exec command; trim trailing blank line; prefix lines with line-prefix
;;
(define (exec command)
  ;; Trim comments from end of command
  (define `cmd-expr
    (first (filter-out "#%" (subst "#" " #" [command]))))

  (.. (fprintf 2 (.. "$ " command "\n"))
      "```console\n"
      "$ " command "\n"
      (concat-vec (shell-lines "%s" cmd-expr) "\n")
      "```\n"))

;; Insert a delay so that make won't "miss" a change.
;;
;; Make 3.81 has a flaw wherein a target with the *same* mtime as a
;; pre-requisite is considered *fresh*.  Given the one-second resolution of
;; most filesystems, when we build a target and then immediately modify its
;; pre-requisite, make might later treat the stale target as fresh.  This is
;; mainly a concern when invoking make from a script (as we are here).  In
;; our case, an "alternate build" (when `make` is invoked with command-line
;; variables) may generate an intermediate file that is different from other
;; alternate builds, or from the default configuration.  Since the solution
;; (inserting a one-second delay) is so heinous, we take some pains to do it
;; only when we need to: before and after each alternate build.
;;
(define *was-alt* nil)

(define (make-delay command)
  (define `does-make
    (and (findstring " make " (.. " " command))
         (not (findstring " help " command))))

  (when does-make
    (define `is-alt
      (findstring "=" (subst " V=" "" command)))

    (if (or is-alt *was-alt*)
        (shell "sleep 1"))
    (set *was-alt* is-alt)))


(define (run script)
  (define `lines (read-lines script))

  (concat-for (line lines "")
    (cond
     ;; run command & output command + result
     ((eq? "$" (word 1 line))
      (make-delay line)
      (exec (rest line)))

     ;; run command & output nothing
     ((eq? "!" (word 1 line))
      (begin
        (exec (rest line))
        nil))

     ;; output line literally
     (else
      (.. line "\n")))))


(define (done err-msg)
  (if err-msg (fprintf 2 "run-example: %s\n" err-msg))
  (if err-msg 1 0))


(define (main argv)
  (let ((map (getopts argv "-o=")))
    (define `[infile]  (dict-get "*" map))
    (define `[outfile] (dict-get "o" map))

    (or (if (not infile)
            (done "no input file given"))
        (if (not outfile)
            (done "no output file given"))
        (done (write-file outfile (run infile))))))
