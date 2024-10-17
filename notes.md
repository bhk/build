# Notes

## Design Notes

### How Minion Works

* The object system is essentially a flexible way of defining functions.
  The inputs are the instance name -- Class(args...) -- and property
  definitions associated with it or the classes it inherits from.  Each
  property can be viewed as a different function of those inputs.

* Builders are instances that can be used as Minion targets.  For each of
  these instances, the `rule` property evaluates to Make syntax that will
  later be fed to `$(eval ...).` Each such instance represents a single Make
  rule and a single make target.

  Each one of these root instances may (and usually wil) reference one or
  more instances as prerequisites.  An instance's `needs` property must list
  all instances that are required to generate rules to satisfy
  prerequisites.

* Minion "intercepts" Make goals.  It examines $(MAKECMDGOALS) to discover
  what needs to be built, and then -- prior to the rule processing phase --
  it detects Minion goals (instances, indirections, and aliases) and
  constructs a set of "root" builder instances whose targets match the
  Minion goals as named on the command line.  For goals not recognized as
  Minion goals, nothing is done ... it is assumes that some native Make rule
  exists to satisfy that goal.

* Fomr this root set, Minion traverses all these dependencies, transitively,
  to find all that instances that will be required to construct all required
  Make rules. Duplicates are removed from the complete set of required
  instances, then the rules for all of them are eval'ed.

* After processing all makefiles, Make proceeds to the rule processing
  phase.  At this point it operates on the rule definitions that have been
  eval'ed.


### Special Characters in Instances and Indirections

Consider goals on the command line, e.g. `make 'CC(a.c)'`.  Make's command
line handling makes spaces and `=` unworkable in this scenario, and we also
need to generate a rule with a target matching the goal.

In a Make rule, targets cannot contain the following characters literally:
space, `=`, `:`, `#`, and wildcards.  From probe.mak:

 * Space, `:`, `=`, and `#` can be escaped with `\`.

 * Wildcards cannot be escaped in Make 3.81 (but are unlikely to match
   actual files, so the result of the glob operation will leave the target
   unchanged).

Another challenge: defining instance property definitions.  This requires
special handling for `=`, `:`, and `#` on the LHS of an assignment.

   : --> $(if ,,:)
   = --> $(if ,,=)
   # --> \#

There are also problems with evaluating variables, which we fortunately
sidestep.  A `$(VAR)` expression fails if `VAR` contains `:`, even if that
`:` is the result of a sub-expression (like `$(colon)`).  Also, `$(call
VAR,...)  will run into problems with a right parenthesis *or* colon in the
variable name.  However, since Minion *compiles* property definitions and
memoizes the compilation, we store the compiled version in a variable
with a different name, avoiding the problems with `$(call ...)`.

Finally, there is the issue of computing output file names.  We encode
certain character to ensure that output file names are shell-safe and
make-safe, but for performance reasons we do not handle every such
character.


### Variable Namespace Pollution

Class names to be avoided:

    $ echo '$(info $(sort $(patsubst %.,%,$(filter %.,$(subst .,. ,$(.VARIABLES))))))a:;@#' | make -f /dev/stdin
    COMPILE LEX LINK LINT PREPROCESS YACC


## Possible Features


### Supporting Filenames with Spaces, etc.

We could support filenames that contain spaces and other characters that are
usually difficult to handle in Make.  It would look like this:

Whitespace can be encoded using "bang encoding": `!` --> `!1`, ` ` --> `!0`,
`\t` --> `!+`, ... .  Perhaps useful is that this encoding preserves
lexicographical sorting.  The result is words that can be placed in a Make
word list and manipulated with $(word N,LIST), $(wordlist ...), $(filter
...), $(patsubst ...), etc..

This encoding can be folded into the functionality of `_expand`, so
indirection variables can be assigned using an extended syntax:

     sources = "Hello World!.c" bar.c
     $(call _expand,*sources)  -->  Hello!0World!1.c bar.c
     {in}                      -->  Hello!0World!1.c bar.c
     {^}                       -->  'Hello World!.c' bar.c
     {<}                       -->  'Hello World!.c'

The resulting encoded lists can populate {in}, {oo}, {up}, and {deps}.  The
shorthand properties, {@}, {^} and {<}, would encode their values for
inclusion on shell command lines.

Quoting for the Make target and Make prerequisite contexts would be
different, and built into Builder.rule.  Backslashes can be used to escape
spaces and colons in prereqs and targets (modulo Make bugs... see probe.mak).

For `~`, we might want both the shell/Make meaning and the literal form.

Complications:

 * `$(wildcard ...)` won't work, but an equivalent can be constructed using
   `$(shell ls ... | sed ...)`.

 * Make functions aware of word boundaries -- most of them! -- cannot be
   used directly on {@} and {^}.  They *can* be used on {inIDs} and other
   proerties holding encoded values.

 * Assigning instance properties

       $(call _expand,CC("hello world.c").flags) = ...

 * Pretty-printing instance names

       P(C!ra!0b.c!r)  --> P("C(a b.c)")
       P(C(a!0b.c))    --> P(C("a b.c"))
       C(x!cy,a!Cz)    --> C("x,y","a=z")

 * Command-line goal processing

       $ make 'CC("a b.c")'  # 1 arg, 1 goal, 2 words in MAKECMDGOALS


### Rewrites

Can we define a class in terms of another?  Say we want to define `Foo(A)`
as `Bar(A,arg=X)`.  To avoid conflicts, these instance names will need to
have different output files, which means that `Foo(A)` will place the result
at a different location from `Bar(A,arg=X)`, or copy it.

    Foo.inherit = Rewrite
    Foo.in = Bar($(_arg1),arg=X)

However, here `Foo` is not a sub-class of `Bar`, so properties attached to
instances or subclasses of `Foo` will not affect `Bar`.  `Foo` will have to
expose its own interface for extension, which will probably be limited.


### make C(A).P

Instead of a special syntax, use a custom class: PrintProp(C(A).P) (to
echo to stdout) or Prop(C(A).P) (to write to file).

    Prop.inherit = Write
    Prop.data = $(call get,$(_propArgProp),$(_propArgID))


### Aliases in Target Lists

Currently "IDs" consist only of instances and "plain" targets (source file
names, or names of phony targets defined by a legacy Make rule).  An
"ingredient list" may contain IDs and indirections (which expand to IDs).
Neither may contain a bare alias name (e.g. "default", rather than
"Alias(default)").  Alias names appear only in goals.

To summarize:

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

  * The argument to _expand is often empty (~46%).
  * When not empty, it usually has one element. (~42%)
  * Usually it has no "*" and no alias name, and can return its input.

    (define (_expand names)
      (if names
        (if (or (findstring "@" names)
                (filter _aliases names))
          (call _ex,names) ;; $(_ex)
          names)))


### "Compress" recipe?

We could post-process the recipe to take advantage of $@, $(@D), $<, $^,
$(word 2,$^), ...  [$(@D) fails for files with spaces...]

Or we could directly emit $(@D) for mkdir command, $@ for {@}, $< for {<}
(when non-empty)

Also: we could use a temporary variable to reduce repetition of the target
name within `rule` (in the Make rule, .PHONY)


### More optimization possibilities

 * Separate the cache into "NAME.ids" and "NAME.mk".  NAME.ids
   assigns `_cachedIDs`, and NAME.mk has everything else.  NAME.mk
   is built as a side effect of building NAME.ids.  NAME.ids is
   included when we use the cache, and NAME.mk is used when-AND-IF
   _rollups encounters a cached ID.

   This avoids the time spent loading the cached makefile (and the dep and
   vv files) (maybe 100ms in med-sized project), when (A) restart will occur
   due to stale cache, (B) the goals are non-trivial yet are entirely
   outside the cache.

 * Allow instances to easily select "lazy" recipes, so that their command
   will be evaluated only if the target is stale. However, this provides no
   savings when vv includes {command}.  The only *actual* case right now is
   Makefile[minionCache], which does this on its own.  And Makefile would
   need a way to convert lazy rules into non-lazy:

      ;; assumes no '$@' or other rule-processing-phase-only vars
      (if (findstring "$" (subst "$$" "" rule))
         (subst "$" "$$" (native-call "or" rule)))


### Possible Arg Syntax

    $(_args)                -->  {:*}
    $(_arg1)                -->  {:1}
    $(call _nameArgs,NAME)  -->  {NAME:*}
    $(call _nameArg1,NAME)  -->  {NAME:1}


### Other optimizations

At one point the following (written to cache files) seemed to benefit builds
but I have no evidence of it at the moment so it has been removed:

    # Disable Make's built-in implicit pattern rules (they can slow things down)
    @echo 'a:' | $(MAKE) -pf - | sed '/^[^: ]*%[^: ]*\::* /!d' >> {@}_tmp_



## On Build Systems

Recommendations, bloviation, and random thoughts on build systems.


### Parallel Builds

Within a makefile one can set `MAKEFLAGS` to `-j` or `-jN` to use parallel
builds by default.  Some complications may ensue:

 * If your makefile does not correctly represent all prerequisites of each
   target, it may work "accidentally" but reliably in single-tasking mode
   and then "break" when a parallel build is specified.  With Minion, this
   it is much easier to avoid this problem, since much of the dependency
   tracking is automated.

 * We cannot detect within the Makefile whether the user has specified `-j1`
   on the command line, so some other way must be devised for allowing the
   user to select a non-parallel build (if so desired).

 * If your makefile invokes make, and the sub-make makefiles also set
   MAKEFLAGS to `-jN`, Make will probably display a warning.  We can avoid
   this by refraining from setting MAKEFLAGS when we detect "-j" in the
   inherited MAKEFLAGS.

While we're setting MAKEFLAGS, we might as well add `-Rr`, which disables
features that can slow Make down significantly and can unexpectedly
interfere with user makefiles -- features that are of no value when using
Minion.


### O(N) Multi-level Make

Multi-level make works wonderfully for large projects -- but *not* recursive
make in the general sense.

"Recursive make" is not bad because of the cost of invoking make N times.
Recursive make is bad because "diamonds" in the dependency graph can result
in an *exponential* number of invocations of make in very large projects.
We can eliminate this by creating a top-level "orchestrating" make that
directly invokes each sub-make at most once.  It knows of the dependencies
between the sub-makes so it can invoke them in the proper order.

A simple, performant solutions involves two levels -- one top-level
"orchestration" make, and some number of second-level "component" sub-makes.
This can be extended to more layers without losing O(N) performance as long
as we ensure that each makefile is invoked only by one other makefile.

In Minion, we can define the the follwing class:

    # Submake(DIR,[goal:GOAL]) : Run `make [GOAL]` in DIR
    Submake.inherit = Phony
    Submake.command = make -C $(_arg1) $(patsubst %,'%',$(call _namedArgs,goal))

The default target of the top-level make will be a sub-make that builds the
final results of the project:

    Alias(default).in = Submake(product)

Dependencies between sub-makes must be expressed in the top level makefile
like this:

    Submake(product).in = Submake(lib1) Submake(lib2)
    Submake(lib1).in = Submake(idls)
    ...

In the lower-level directories, typing `make` will build the default goal
for the current component without updating external dependencies.  We can
add the following line to a component makefile so that `make outer` will
build all its dependencies and then build its default goal:

    Alias(outer).in = Submake(../Makefile,goal:Submake(DIR1))

...or...

    Alias(outer).command = make -C ../Makefile 'Submake(DIR1)'


### Flat projects

Strive for the flattest possible structure that politics will allow for.
Fight the tendency that most projects have, which is to drift toward an
ever-more elaborate hierarchy with many nested directories.  Structures like
this present unnecessary complexity.  The need to navigate the structure
presents an initial learning curve for developer and, later, an ongoing
burden.

Some common reasons for these elaborate trees include:

 1. A desire to reflect the hierarchical structure of the software build.

 2. A desire to reflect the organizational structure.

One problem with #1 is that a directory hierarchy is inadequate to capture
the structure of software, because the structure of software is generally a
directed graph and *not* a tree.  With a flat directory structure, we can
easily express the graph-like relationships between components in the
top-level makefile.

The bigger problem with #1, and it shares this with #2, is it takes a
volatile aspect of the software and casts it in stone.  Regarding #1,
services may be grouped in different processes at different stages of
development, components may move from one library to another, and so on.
Regarding #2, software projects almost always outlive the divisions of
responsibilities.  People move on; groups are reorganized.

The practical reality is that restructuring the *code* -- moving or renaming
files and directory en masse -- is a very expensive operation, disrupting
many day-to-day activities of those who work on the code.  So the tree ends
up reflecting some past structure of the software or organization, with
directories named after teams or software components that no longer exist.
Over time, it becomes a bewildering mish-mash of recent and old structures.
The more elaborate the tree structure, the more likely it is to be wrong.


### Make's Straitjacket

In just about every build system there are three domains to consider,
ordered top to bottom here:

 * G: Rule generation logic.  For trivial projects, rules might static and
   hand-written, with no "logic" to speak of, but generally this is a
   program external to Make, or a program written *in* Make.

 * P: Make's rule processing, which is aware of file modification times and
   dependencies and can efficiently invoke commands in parallel.

 * X: The external world, where commands are executed, and targets actually
   get built.

There is a strict hierarchy here.  Domain P happens during "rule processing
phase" in Make, which follows strictly *after* everything in domain G.
Prior to rule processing, G can generate rules that describe how to build
targets and assign them prerequisites, but *during* P, the data structure
that controls P cannot be augmented, so freshness information cannot feed
back into rule generation.  Also, X, when invoked through P, cannot feed
back to G or P.

Also, there is a division of information.  P keeps its information to
itself, and X is blissfully unaware of what's going on above.

[An aside: Here we are dicsussing Make, but the same division applies to
almost every alternative, and those that try to bridge these divisions often
do so disastrously.]

Sometimes a domain inherently needs information available at a lower domain.
This is the root cause of ugliness when dealing with a number of scenarios.

#### Scenario #1

The thorniest problems revolve around "implicit dependencies".  By this I
mean dependencies on a target that are not explicitly listed in the commands
that build the target (in P), or named in the description of the target (in
G).  They are discovered at build time in X, as when, for example, a C
compiler actually processes preprocessor `#include` directives.

Make actually has a robust and straightforward solution for this problem in
a restricted case: namely, *when all implicit dependencies are static assets
(sources)*.  That solution always seemed like an ugly hack to me, probably
because of my nagging concern for cases it does not handle, but it is
actually elegant and ideal when you think about the divisons of
responsibility between domans and the nature of this specific case.  When a
target does not exist, we know it must be built regardless of what implicit
dependencies might exist, so they do not need to be known.  After a target
has been built, in a subsequent make invocation, all we care about are the
implicit dependencies *when it was last built*.  So the solution is that the
X phase emits, along with the target, a "dependency" file that describes the
implicit dependencies.  G knows about this dependency file, but typically it
never looks directly at the contents; it includes it as a makefile that adds
prerequisites to a target.  On subsequent invocations, P uses this
information.  This is such an established convention that both gcc and clang
support `-MF` options to generate exactly this kind of file.

Note that this is limited to static assets because X and P both know about
*files*.  X does not know about *potential* files (that P might know about),
and P does not know about *potential rules* (that G might know about).  X
can emit something that P can understand, because there are only files
involved, not rules.  And there is no need for this feedback to occur during
a given Make invocation.  The dependency file simply describes what went
into the target when it was generated.

#### Scenario #2

Upping the difficulty level, we come to **implicit dependencies on generated
files**.  A build command (running in domain X) does not know about what
might be generated, it just knows about files, so it will fail to discover
an implicit dependency unless it already exists.  Let's use the example of C
header files -- a common implicit dependency -- that are generated from some
other data file.

The pragmatic solution to this is to generate all the files that might be
identified as implicit dependencies *before* generating any of the files
that might find them to be implicit dependencies.  To be clear, we do not
necessarily name them as dependencies ... we just generate/update them (if
need be) *before* the files that might depend on them.  Make's "order-only
dependencies" feature does exactly this.

Clearly this might not be optimal, but let's first concern ourselves with
getting something that works.  And this will only work when we can identify
-- prior to phase P -- the entire universe of potential implicit
dependencies, and the universe of things that depend on them.  In the case
of header files generated from data and included by C sources, this is
workable.

It is unclear to whether this solution is applicable more generally, because
here we've sidestepped the whole problem of feedback from X to G.  G does
not need to be told what rules to emit because it pre-emptively decides
"emit all the rules!".

#### Scenario #3

Another scenario arises in unit testing.  Say we have a set of source files,
and for each source file we have a test that validates that source file.
The test is itself a source file, which, combined with its subject file,
constitutes a program that, when run, either succeeds or fails.

Test files and their subject files may, in turn, depend upon other source
files.  We have a strong desire to make sure that lower-level sources are
validated before they are used in higher-level tests.  Otherwise, we might
waste a lot of time chasing red herrings.  Consider:

    TestA + A     --link-->  TestProgA  --run-->  A.ok
    TestB + B + A --link-->  TestProgB  --run-->  B.ok

The dependency we want to introduce is an order-only dependency of B.ok on
A.ok.  We don't want to run TestProgB and call attention to its failure when
TestProgA fails!

Generally, the dependency that TestProgB has on A will be an implicit
dependency, so domain G and domain P have no *a priori* knowledge about it
... but the logic in G is what we would normally rely on to conclude, given
"TestProgB depends on A", that "B.ok order-only-depends on A.ok".

Unlike scenario #1, above, however, we cannot wait until a subsequent build.
We want the tests to be run in order even the first time make is invoked.
Pushing the dependency scanning operations back upstream into domain G is
not really a solution, because these are non-trivial operations that we want
to be subject to the same kind of need-based invocations that we are using a
build system for in the first place.

Another problem is that -- unlike scenario #2 -- we cannot *a priori*
segregate the order-only depend*er*s from the order-only depend*ee*s.  These
".ok" targets are all of the same type.

Here we run up against the general case that doesn't fit the straitjacket:
the things we need to do (in X) might determine what else we need to do (in
X).

Make offers us an escape hatch, of sorts.  (At least when phase G executes
within Make.)  If a makefile *includes* (in G) a makefile that is also the
target of a rule, and if it is found to be stale (in P) , then Make will
execute the commands to (re)generate that makefile (in X) and then *restart*
execution from the top (in G again), where the makefile results are now
available.

One can think of this as a crude looping mechanism, wherein the only "goto"
destination is the beginning of the program.  But there's a purity about it.
The only mutable state is outside.

So how might this work, exactly?

In the simplest case, the command that generates TestProg[X] will output as
a side-effect a dependency file that describes not just the dependencies for
TestProg[X], a la `-MF`, but also order-only dependencies for X.ok, in terms
that domain P can understand (file names).  This requires the program to
understand not just this notion of unit test order-only dependencies, but
also your project's naming conventions to determine whether unit tests
exist, where they are, and where their ".ok" files are.

More generally, perhaps, the side-effect dependency file will output data
usable by G -- e.g. files that assign make variables to lists of names -- so
G can apply its logic to that data.  The G domain could employ this as
needed.  Whenever it needs data from the X domain it can expand, e.g.,
`$(eval -include xxx.mk)$(xxx_scan)` and separately eval a rule for xxx.mk.
As this data leads it to discover new rules that need to be brought into
play, those in turn can employ their own included makefiles.  I've no doubt
it would *work*, but performance-wise it would not scale nicely.


## Minion Todo

 - Cache validity: Invalidate cached makfiles by detecting changes to inputs
   that (might) affect their contents.

   Approaches involve recording values in the cache file, and then when
   including the file comparing those to the current values.

    a) Automatically log expansion of wildcard indirections.

       Elegant and easy for users.  Does not cover complex wildcards, shell,
       environment variables.

    b) Allow users to define `minionCacheValidity` variable.

       This seems inelegant because of its obtrusiveness, but actually that
       is a plus, because it presents itself as something to think about.
       It is simple, efficient, and comprehensive.  A minor downside is that
       users may need to worry about whether changing *definitions* of this
       variable could give false negatives.

    c) _wildcard, _shell, _var: logging functions for users to call.

       Comprehensive.  Can be *focused* on the expressions that affect the
       cache file contents. On the downside, it can be easy to overlook a
       $(wildcard X) vs. $(call _wildcard,X) ... or to forget ... or to
       waste time mixing up $(call _wildcard,X) with $(_wildcard X).

    d) $(call _use,EXPR,...): perform second eval of arbitrary make expression.

       Comprehensive.  Focused.  Esoteric in implementation and in usage.
       Users will need to escape `$` as `$$` for function calls and late
       variable expansion, but avoid late expansion of positional args ($1,
       $2, ...).

           _use = $(call _logExprValue,$1,$(call or,$1))
           _logExprValue = $(eval LOG += $(call _e!,$1:$2))$2

 - {inherit NAME} : Similar to {inherit}, but it looks up the inherited
   definition of a different property, not the one currently being
   evaluated.  Just checking for this case might slightly slow down property
   definition compilation.

 - `make 'C(A).P'` : Compute and output property without any extraneous text.
