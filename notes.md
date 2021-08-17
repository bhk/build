# Notes

## Todo

* Walk-Through

  - ordinary make goals

* Special characters

  In Make context, we must backslash-escape: ':' '=' ' ' '\t' '%'
  In Make context, we cannot escape: '*' '[' ']'

* C[A] --> C(A);  *VAR --> @VAR;  NAME=VALUE --> NAME:VALUE

  C[A] *may* run afoul of Make's pattern matching, in which case there is
  simply no way to use it as a goal.  We could allow C(A) as a work-around.

  C(A) *must* always be quoted.  We could allow C[A] as a shorthand.

  `*VAR` and `C*VAR` *may* run afoul of Make's pattern matching.

  NAME=VALUE cannot be provided on the command line.  `:` as work-around.
  This leads to confusion.

    -->  Can ":" be escaped within a target?

  The worst implication is for the help feature.  Perhaps make help
  HELP='...'  is a catch-all?

* Object system: Use $(_ID) as auto, not $A and $C
   - A, C = functions of $(_ID)
   - (extractClass) and (extractArg) not in fast path for `get`
   - _cp: fold in _& functionality, and eliminate defVars
       Single class name = cache as "&C.P"
       Multiple class names = cache as "&C1/C2/C3.P"
       "Run" -> "Shell Phony" -> "Phony" -> "Builder"


       (define (next-scope scopes)  ;; exported var-func
         `S1 = (word 1 scopes)
         (if (findstring "[" scopes)
           (word 1 (subst "[" " " scopes)))
           (strip (._. (value (.. S1 ".inherit")) (rest scopes))))

       ;; Scopes = "C[A]" | "Class" | "Mixin... Class"
       ;;
       (_cp scopes prop who)
         `S1 = (word 1 scopes)
         `defVar = (.. S1 "." prop)
         `outVar = (.. "&" (subst " " "&" scopes) "." prop)
         `(recur o) = (_cp (next-scope classes) who)
         `(compile-inherit code) =
            (if findstring "{inherit}" code)
              (subst "{inherit}" (recur) code)
              code)

         (if (defined outVar)
           outVar
           (if (defined defVar)
             (set outVar
               (compile-braces (compile-inherit (value defvar)))))
             (if scopes
               (recur)
               (error))))

  `get` path; one var ref in cache access

* Quiet mode


## Design Notes


### Special characters in filenames

This could be supported relatively easily.  It would look like this:

Target lists -- indirection variable contents, argument values, and {in} --
would understand quoted file names, converting them an internal word-encoded
form ("!" -> "!1", " " -> "!0", "\t" -> "!+", ...).

     sources = "f $1!00" f!00 bar
     $(call _expand,*sources)  -->  f!01!S!100 f!0o bar
     ${^}                      -->  "f \$1!00" "f 0" bar

Shorthand properties, {@}, {^} and {<}, encode their values for inclusion on
shell command lines.  Presence of "! means that quoting is necessary; other
file names are used unquoted.

Where file names appear elsewhere in rules, Minion would encode the names
properly for Make.

Observations:

Syntax:  Name := ( NameChar | '"' QChar+ '"' )+

For "~", we might want both the shell/Make meaning and the literal form.
E.g.: "~/\~" --> `~/!T`.  (Is there a way to escape for Make?)

For command-line goals, allow quoting *as in* target lists:
    `make 'Program["hello world.c"]'`

Calls to `$(wildcard ...)` will still be problematic.


### Rewrites

Can we define a class in terms of another?  Say we want to define `Foo[A]`
as `Bar[A,arg=X]`.  To avoid conflicts, these instance names will need to
have different output files, which means that `Foo[A]` will place the result
at a different location from `Bar[A,arg=X]`, or copy it.

    Foo.inherit = Rewrite
    Foo.in = Bar[$A,arg=X]

However, here `Foo` is not a sub-class of `Bar`, so properties attached to
instances or subclasses of `Foo` will not affect `Bar`.  `Foo` will have to
expose its own interface for extension, which will probably be limited.


### make C[A].P

Instead of a special syntax, use a custom class: PrintProp[C[A].P] (to
echo to stdout) or Prop[C[A].P] (to write to file).

    Prop.inherit = Write
    Prop.data = $(call get,$(_propArgProp),$(_propArgID))

Should this echo like `make help C[A].P` but without decoration?  Or
should it write to a file?  `Print[C[A].P]` could write

should this write the value to a file, so that Print[C[A].P] could echo
(if we wire

Maybe a custom class, like `Query[C[A].P]`, is a better solution.


### Variable Namespace Pollution

    $ echo '$(info $(sort $(patsubst %.,%,$(filter %.,$(subst .,. ,$(.VARIABLES))))))a:;@#' | make -f /dev/stdin
    COMPILE LEX LINK LINT PREPROCESS YACC


### Wildcard Characters in Targets

Passing instances and indirections on the command line may run afoul of
Make's wildcard matching.  When the user types `make CC[f.c]` we generate
a Make rule that looks like:

    CC[f.c]: .out/CC.c/f.o

If a file `CCc` exists, Make's wildcard matching will make the above rule
equivalent to:

    CCc: ...

...and Make will complain there is no rule for `CC[f.c]` or `*var`.  Instead
we could generate:

    CC[foo.c%: ...
    %var: ...

This defeats wildcard matching, and it will match (as a pattern) our goal.
The one problem remaining is that a pattern for one goal may also match
another goal named on the command line.

A more complete solution would be:

    % : <all goal targets> ; @true


### Aliases in Target Lists

Currently "target lists" can include indirections, instances, and "plain"
targets (source file names, or names of phony targets define by a legacy
Make rule), while "IDs" consist only of instances and plain targets.
Neither may contain a bare alias name (e.g. "default", rather than
"Alias[default]"); these appear only in goals.  To summarize:

   goals, cache         PLAIN | C[A] | *VAR | ALIAS   (user-facing)
   in, up, oo           PLAIN | C[A] | *VAR           (user-facing)
   get, needs, rollup   PLAIN | C[A]
   out, <, ^, up^       PLAIN                         (user-facing)

The following change would simplify documentation:

   goals, cache, in, ...  PLAIN | C[A] | *VAR | ALIAS   (user-facing)
   get, needs, rollup     PLAIN | C[A]
   out, <, ^, up^         PLAIN                         (user-facing)

[If we were to include ALIAS values in the middle category, then we have
the problem of duplicates due to, uh, "aliasing" of Alias[X] and X.]

This involves (only) a change to `_expand`, which is called many times,
and on occasions when order must be preserved, so performance is a
concern.  Some benchmarking in a large project is in order.  Performance
observations so far:

  * The argument to _expand is often empty.
  * When not empty, it usually has one element.
  * Usually it has no "*" and no alias name, and can return its input.

(define (_expand names)
  (if names
    (if (or (findstring "*" names)
            (filter _aliases names))
      (call _ex,names) ;; $(_ex)
      names)))


### Using `-include` and auto-restart for Cache Files

When using "-include" for the cached makefile, Make's auto-restart feature
will rebuild it when out of date (and then silently restart).  One potential
downside is that when a restart does occur, all of our reading-phase work
(including rule generation) is done twice.

Make doesn't tell us whether a restart *will* happen.  (And in the happy
path, it doesn't appear noticeably faster than sub-make.)  But we can
predict a restart *most* of the time with little difficulty. (Empty
_cachedIDs and/or _timestamp vs. $(shell date -r MAKEFILE +%s).)

OTOH, problems with sub-make are:

 - What is the proper way to invoke it to include all the same makefiles?
   [What if the user originally typed `make -f M1 -f M2` ?]

 - The user makefile will be executed twice, even in the happy path.
   (Perhaps better to be consistent in this respect?)

 - We have to be conscious of two different modes in which we are invoked.
   The first just forwards invocations to the sub-make.


### "Compress" recipe?

We could post-process the recipe to take advantage of $@, $(@D), $<, $^,
$(word 2,$^), ...

Or we could directly emit $(@D) for mkdir command, $@ for {@}, $< for {<}
(when non-empty)

Also: we could use a temporary variable to reduce repetition of the target
name within `rule` (in the Make rule, .PHONY)
