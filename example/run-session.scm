;; Expand commands in a Markdown document to include console output

(require "core")
(require "io")
(require "getopts")

;; Exec command; trim trailing blank line; prefix lines with line-prefix
;;
(define (exec command)
  ;; Trim comments from end of command
  (define `cmd-expr
    (first (filter-out "#%" (subst "#" " #" [command]))))

  ;; show progress message
  (fprintf 2 "$ %s\n" command)

  (sprintf (.. "```console\n"
               "$ %s\n"
               "%s\n"
               "```\n")
           command
           (concat-vec (shell-lines "( %s ) 2>&1" cmd-expr) "\n")))


;; Insert a delay so that make won't "miss" a change.
;;
;; Given the one-second resolution of most filesystems, when we build a
;; target and then immediately modify some pre-requisite, make might not
;; treat the target as out-of-date.  This is mainly a concern when invoking
;; make from a script (as we are here).  In our case, this can happen
;; because a "modified build" (i.e. when `make` is invoked with command-line
;; variables) may generate an intermediate file that is different from other
;; modified builds, or from the default configuration.  Our solution is to
;; insert one-second delay, which is so heinous we take some pains to do it
;; only when necessary: before and after each modified build.
;;
(define *was-mod* nil)

(define (delay-for-make command)
  (define `is-make
    (and (filter "make" command)
         (not (filter "help" command))))
  (define `is-mod
    (findstring "=" (subst " V=" "" command)))

  (when is-make
    (if (or is-mod *was-mod*)
        (shell "sleep 1"))
    (set *was-mod* is-mod)))


(define (run script)
  (define `lines (read-lines script))

  (concat-for (line lines "")
    (cond
     ;; run command & output command + result
     ((eq? "$" (word 1 line))
      (delay-for-make line)
      (exec (rest line)))

     ;; run command & output nothing
     ((eq? "!" (word 1 line))
      (begin
        (exec (rest line))
        nil))

     ;; output line literally
     (else
      (.. line "\n")))))


(define (main argv)
  (let ((map (getopts argv "-o=")))
    (define `[infile]  (dict-get "*" map))
    (define `[outfile] (dict-get "o" map))

    (define err-msg
      (cond
       ((not infile) "no input file given")
       ((not outfile) "no output file given")
       (else (write-file outfile (run infile)))))

    (when err-msg
      (fprintf 2 "run-session: %s\n" err-msg)
      1)))
