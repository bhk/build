# Notes

## Todo

* Use sub-make if "-r" is not given (and MAKELEVEL == 0)

  # during reading phase MAKEFLAGS seems to have a single word (no "-")
  # -R puts "-r" in MAKEFLAGS
  # --> MAKEFLAGS includes "var=value"
  ifeq "0" "$(MAKELEVEL)$(findstring r,$(MAKEFLAGS))"

  ** cgi/Makefile uses $(info ...) [prints twice on restart; 3X w/ submake?]
  ** Allow Makefiles to defeat sub-make?
  ** Allow makefiles to provide args for sub-make:
       -r vs. -R?  -k? -j N

* Consider how best to support "-j ..."

  export MAKEJ=... in .bashrc (system-dependent)
  MAKEFLAGS := $(MAKEJ) $(MAKEFLAGS)   in cgi/makefile

* Quiet mode

* Walk-Through

  - discuss ordinary make goals

* Arg syntax?

  {NAME:N} or {NAME:*}  --  {:1}, {:2}, {:*}, {out:1}

## Design Notes


### Special characters in filenames

We could support filenames that contain spaces and other characters that are
usually difficult to handle in Make.  It would look like this:

Target lists -- indirection variable contents, argument values, and {in} --
could contain quoted substrings, and _expand would convert them an internal
word-encoded form ("!" -> "!1", " " -> "!0", "\t" -> "!+", ...).

     sources = "f $1!00" f!00 bar
     $(call _expand,*sources)  -->  f!01!S!100 f!0o bar
     ${^}                      -->  "f \$1!00" "f 0" bar

Shorthand properties, {@}, {^} and {<}, encode their values for inclusion on
shell command lines.  Presence of "! means that quoting is necessary; other
file names are used unquoted.  Where file names are provided to Make (in
rules), Minion would encode the names properly for Make.  E.g.: $(call
_mkEnc,{out} : {prereqs} ...)

Syntax would be amended:
   Name := ( NameChar | '"' QChar+ '"' )+

For "~", we might want both the shell/Make meaning and the literal form.
E.g.: "~/\~" --> `~/!T`.  (Is there a way to escape for Make?)

In Make targets & pre-requisistes, we must backslash-escape:
      \s \t : = % * [ ] ?

In Make v3.81, wildcard character escaping does not work.

For command-line goals, allow quoting *as in* target lists:
    `make 'Program("hello world.c")'`

Calls to `$(wildcard ...)` will still be problematic.

Problems:

 * Assigning instance properties

     define minion_defs
       C("hello world.c").flags = ...
       ...
     endef

 * Pretty-printing instance names requires parsing...

     C!lA!r          --> "C(A)"
     P(C!ra!0b.c!r)  --> P("C(a b.c)")
     P(C(a!0b.c))    --> P(C("a b.c"))
     C(x!cy,a!Cz)    --> C("x,y","a=z")

 * Expressing goals on the command line:

     $ make 'CC("a b.c")'  # 1 arg, 1 goal, 2 words in MAKECMDGOALS


### Rewrites

Can we define a class in terms of another?  Say we want to define `Foo(A)`
as `Bar(A,arg=X)`.  To avoid conflicts, these instance names will need to
have different output files, which means that `Foo(A)` will place the result
at a different location from `Bar(A,arg=X)`, or copy it.

    Foo.inherit = Rewrite
    Foo.in = Bar($A,arg=X)

However, here `Foo` is not a sub-class of `Bar`, so properties attached to
instances or subclasses of `Foo` will not affect `Bar`.  `Foo` will have to
expose its own interface for extension, which will probably be limited.


### make C(A).P

Instead of a special syntax, use a custom class: PrintProp(C(A).P) (to
echo to stdout) or Prop(C(A).P) (to write to file).

    Prop.inherit = Write
    Prop.data = $(call get,$(_propArgProp),$(_propArgID))

Should this echo like `make help C(A).P` but without decoration?  Or
should it write to a file?  `Print(C(A).P)` could write

should this write the value to a file, so that Print(C(A).P) could echo
(if we wire

Maybe a custom class, like `Query(C(A).P)`, is a better solution.


### Variable Namespace Pollution

    $ echo '$(info $(sort $(patsubst %.,%,$(filter %.,$(subst .,. ,$(.VARIABLES))))))a:;@#' | make -f /dev/stdin
    COMPILE LEX LINK LINT PREPROCESS YACC


### Aliases in Target Lists

Currently "target lists" can include indirections, instances, and "plain"
targets (source file names, or names of phony targets define by a legacy
Make rule), while "IDs" consist only of instances and plain targets.
Neither may contain a bare alias name (e.g. "default", rather than
"Alias(default)"); these appear only in goals.  To summarize:

   goals, cache         PLAIN | C(A) | *VAR | ALIAS   (user-facing)
   in, up, oo           PLAIN | C(A) | *VAR           (user-facing)
   get, needs, rollup   PLAIN | C(A)
   out, <, ^, up^       PLAIN                         (user-facing)

The following change would simplify documentation:

   goals, cache, in, ...  PLAIN | C(A) | *VAR | ALIAS   (user-facing)
   get, needs, rollup     PLAIN | C(A)
   out, <, ^, up^         PLAIN                         (user-facing)

[If we were to include ALIAS values in the middle category, then we have
the problem of duplicates due to, uh, "aliasing" of Alias(X) and X.]

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
$(word 2,$^), ...  [$(@D) fails for files with spaces...]

Or we could directly emit $(@D) for mkdir command, $@ for {@}, $< for {<}
(when non-empty)

Also: we could use a temporary variable to reduce repetition of the target
name within `rule` (in the Make rule, .PHONY)
