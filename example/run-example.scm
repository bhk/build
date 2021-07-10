;; Generate example walkthrough

(require "core")
(require "io")


;; Exec command; trim trailing blank line; prefix lines with line-prefix
(define (exec command)
  (.. (fprintf 2 (.. "$ " command "\n"))
      "```console\n"
      "$ " command "\n"
      (concat-vec (shell-lines "%s" command) "\n")
      "```\n"))

(define (main argv)
  (define `lines (read-lines (nth 1 argv)))

  (print
   (concat-for (line lines "")
     (cond
      ;; run command & output command + result
      ((eq? "$" (word 1 line))
       (exec (rest line)))

      ;; run command & output nothing
      ((eq? "!" (word 1 line))
       (begin
         (exec (rest line))
         nil))

      ;; output line literally
      (else
       (.. line "\n"))))))
