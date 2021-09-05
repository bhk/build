# Example Walk-through


## Introduction

Here is an example command line session that introduces Minion
functionality.  You can follow along typing the commands yourself in the
`example` subdirectory of the project.

We begin with a minimal Makefile:

```console
$ cp Makefile1 Makefile
```
```console
$ cat Makefile
include ../minion.mk
```

This Makefile doesn't describe anything to be built, but it does invoke
Minion, so when we type `make` in this directory, Minion will process the
goals.  A *goal* is target name that is listed on the command line.  Goals
determine what Make actually does when it is invoked.


## Instances

The salient feature of Minion is instances.  An instance is a description of
a build step.  Instances can be provided as goals or as inputs to other
build steps.

An instance is written `CLASS(ARGUMENT)`.  `ARGUMENT` typically is the name
of an input to the build step.  `CLASS` is the name of a class that is
defined by Minion or your Makefile.  To get started, let's use some classes
built into Minion:

```console
$ make 'CC(hello.c)'
#-> CC(hello.c)
gcc -c -o .out/CC.c/hello.o hello.c     -MMD -MP -MF .out/CC.c/hello.o.d
```
```console
$ make 'LinkC(CC(hello.c))'
#-> LinkC(CC(hello.c))
gcc -o .out/LinkC.o_CC.c/hello .out/CC.c/hello.o  
```
```console
$ make 'Run(LinkC(CC(hello.c)))'
./.out/LinkC.o_CC.c/hello 
Hello world.
```


## Inference

Some classes have the ability to *infer* intermediate build steps, based on
the file extension.  For example, if we provide a ".c" file directly to
`LinkC`, it knows how to generate the intermediate artifacts.

```console
$ make 'LinkC(hello.c)'
#-> LinkC(hello.c)
gcc -o .out/LinkC.c/hello .out/CC.c/hello.o  
```

This command linked the program, but did not rebuild `hello.o`.  This is
because we have already built the inferred dependency, `CC(hello.c)`.  Doing
nothing, whenever possible, is what a build system is all about.

We can demonstrate that everything will get re-built, if necessary, by
re-issuing this command after invoking `make clean`.  The `clean` target is
defined by Minion, and it removes the "output directory", which, by default,
contains all generated artifacts.

```console
$ make clean; make 'LinkC(hello.c)'
rm -rf .out/
#-> CC(hello.c)
gcc -c -o .out/CC.c/hello.o hello.c     -MMD -MP -MF .out/CC.c/hello.o.d
#-> LinkC(hello.c)
gcc -o .out/LinkC.c/hello .out/CC.c/hello.o  
```

Likewise, `Run` can also infer a `LinkC` instance (which in turn will infer
a `CC` instance):

```console
$ make clean; make 'Run(hello.c)'
rm -rf .out/
#-> CC(hello.c)
gcc -c -o .out/CC.c/hello.o hello.c     -MMD -MP -MF .out/CC.c/hello.o.d
#-> LinkC(hello.c)
gcc -o .out/LinkC.c/hello .out/CC.c/hello.o  
./.out/LinkC.c/hello 
Hello world.
```


## Phony Targets

A `Run` instance writes to `stdout` and does not generate an output file.
It does not make sense to talk about whether its output file needs to be
"rebuilt", because there is no output file.  Targets like this, that exist
for side effects only, are called phony targets.  They are always executed
whenever they are named as a goal, or as a prerequisite of a target named as
a goal, and so on.

```console
$ make 'Run(hello.c)'
./.out/LinkC.c/hello 
Hello world.
```

A class named `Exec` also runs a program, but it captures its output in a
file, so its targets are *not* phony.

```console
$ make 'Exec(hello.c)'
#-> Exec(hello.c)
( ./.out/LinkC.c/hello  ) > .out/Exec.c/hello.out || rm .out/Exec.c/hello.out
```

Using `Exec` is a way to run unit tests.  The existence of the output file
is evidence that the unit test passed (the program exited without an error
code).  If we want to view the output, we can use `Print`, a class that
generates a phony target that writes its input to `stdout`:

```console
$ make 'Print(hello.c)'
#include <stdio.h>

int main() {
   printf("Hello world.\n");
}
```
```console
$ make 'Print(Exec(hello.c))'
Hello world.
```


## Help

When the goal `help` appears on the command line, Minion will describe all
of the other goals on the command line, instead of building them.  This
gives us visibility into how things are being interpreted, and how they map
to underlying Make primitives.

```console
$ make help 'Run(hello.c)'
Target ID "Run(hello.c)" is an instance (a generated artifact).

Output: .out/Run/hello.c

Rule: 
  | .PHONY: .out/Run/hello.c
  | .out/Run/hello.c : .out/LinkC.c/hello  | 
  | 	./.out/LinkC.c/hello 
  | 
  | 

Direct dependencies: 
   LinkC(hello.c)

Indirect dependencies: 
   CC(hello.c)
```
```console
$ make help 'Exec(hello.c)'
Target ID "Exec(hello.c)" is an instance (a generated artifact).

Output: .out/Exec.c/hello.out

Rule: 
  | .out/Exec.c/hello.out : .out/LinkC.c/hello  | 
  | 	@echo '#-> Exec(hello.c)'
  | 	@mkdir -p .out/Exec.c/
  | 	@echo '_vv=.( ./.out/LinkC.c/hello  ) > !@ || rm !@.' > .out/Exec.c/hello.c.vv
  | 	( ./.out/LinkC.c/hello  ) > .out/Exec.c/hello.out || rm .out/Exec.c/hello.out
  | 
  | _vv =
  | -include .out/Exec.c/hello.c.vv
  | ifneq "$(_vv)" ".( ./.out/LinkC.c/hello  ) > !@ || rm !@."
  |   .out/Exec.c/hello.out: .out/FORCE
  | endif
  | 

Direct dependencies: 
   LinkC(hello.c)

Indirect dependencies: 
   CC(hello.c)
```


## Indirections

An *indirection* is a notation for referencing the contents of a variable.
Indirections can be used in contexts where lists of targets are expected.
They are often used as a way to convey multiple input files in an argument.

There are two forms of indirections.  The first is called a simple
indirection, and it represents all of the targets identified in the
variable.

```console
$ make 'Tar(@sources)' sources='hello.c binsort.c'
#-> Tar(@sources)
tar -cvf .out/Tar_@/sources.tar hello.c binsort.c
```

The other form is called a mapped indirection.  This constructs an instance
for each target identified in the variable.

```console
$ make help Run@sources sources='hello.c binsort.c'
"Run@sources" is an indirection on the following variable:

   sources = hello.c binsort.c

It expands to the following targets: 
   Run(hello.c)
   Run(binsort.c)
```
```console
$ make Run@sources sources='hello.c binsort.c'
./.out/LinkC.c/hello 
Hello world.
#-> CC(binsort.c)
gcc -c -o .out/CC.c/binsort.o binsort.c     -MMD -MP -MF .out/CC.c/binsort.o.d
#-> LinkC(binsort.c)
gcc -o .out/LinkC.c/binsort .out/CC.c/binsort.o  
./.out/LinkC.c/binsort 
srch(7) = 5
srch(6) = 9
srch(12) = 9
srch(0) = 9
```
```console
$ make 'Tar(CC@sources)' sources='hello.c binsort.c'
#-> Tar(CC@sources)
tar -cvf .out/Tar_CC@/sources.tar .out/CC.c/hello.o .out/CC.c/binsort.o
```


## Aliases

So far we haven't added anything to our Makefile, so we can only build what
we explicitly describe on the command line.  A build system should allow us
to describe complex builds in a Makefile so they can invoked with a simple
command, like `make` or `make deploy`.  Minion provides aliases for this
purpose.  An alias is a name that identifies a phony target instead of an
actual file.

To define an alias, define a variable named `Alias(NAME).in` to specify a
list of targets to be built when NAME is given as a goal, *or* define
`Alias(NAME).command` to specify a command to be executed when NAME is given
as a goal.  Or define both.  Then, when Minion sees `NAME` listed on the
command line, it will know it should build the corresponding `Alias(NAME)`
instance.

This next Makefile defines alias goals for "default" and "deploy":

```console
$ cp Makefile2 Makefile
```
```console
$ cat Makefile
sources = hello.c binsort.c

Alias(default).in = Exec@sources
Alias(deploy).in = Copy@LinkC@sources

include ../minion.mk
```
```console
$ make deploy
#-> Copy(LinkC(hello.c))
cp .out/LinkC.c/hello .out/Copy/hello
#-> Copy(LinkC(binsort.c))
cp .out/LinkC.c/binsort .out/Copy/binsort
```

If no goals are provided on the command line, Minion attempts to build the
target named `default`, so these commands do the same thing:

```console
$ make
#-> Exec(binsort.c)
( ./.out/LinkC.c/binsort  ) > .out/Exec.c/binsort.out || rm .out/Exec.c/binsort.out
```
```console
$ make default
```

One last note about aliases: alias names are just for the Make command line.
Within a Minion makefile, when specifying targets we use only instances,
source file names, or targets of Make rules.  So if you want to refer to one
alias as a dependency of another alias, use its instance name:
`Alias(NAME)`.  For example:

    Alias(default).in = Alias(exes) Alias(tests)


## Properties and Customization

A build system should make it easy to customize how build results are
generated, and to define entirely new, unanticipated build steps.  Let's
show a couple of examples, and then dive into how and why they work.

```console
$ make 'CC(hello.c).flags=-Os'
#-> CC(hello.c)
gcc -c -o .out/CC.c/hello.o hello.c -Os -MMD -MP -MF .out/CC.c/hello.o.d
#-> LinkC(hello.c)
gcc -o .out/LinkC.c/hello .out/CC.c/hello.o  
#-> Exec(hello.c)
( ./.out/LinkC.c/hello  ) > .out/Exec.c/hello.out || rm .out/Exec.c/hello.out
```

Observe how this affected the `gcc` command line.  [Also, as a side note,
note that Minion knew to re-compile the object file, even when no input
files had changed ... only the command line changed.  This fine-grained
dependency tracking means that `make clean` is almost never needed, even
after editing makefiles.]

We can make this change apply more widely:

```console
$ make CC.flags=-Os
#-> CC(binsort.c)
gcc -c -o .out/CC.c/binsort.o binsort.c -Os -MMD -MP -MF .out/CC.c/binsort.o.d
#-> LinkC(binsort.c)
gcc -o .out/LinkC.c/binsort .out/CC.c/binsort.o  
```

So what's going on here?

Each instance is described by a set of properties.  Instances inherit
properties from classes, which may inherit properties from other classes,
and so on.  Properties can refer to other properties.  Minion's notion of
inheritance works like that of some object-oriented languages (hence the
term "instance"), but in Minion there is no mutable state.

The `command` property gives the command that will be executed to build an
output file.  We can ask Minion to describe that property:

```console
$ make help 'CC(hello.c).command'
CC(hello.c) inherits from: CC _CC Compile _Compile Builder 

CC(hello.c).command is defined by:

   _Compile.command = {compiler} -c -o {@} {<} {flags} -MMD -MP -MF {depsFile}

Its value is: 'gcc -c -o .out/CC.c/hello.o hello.c     -MMD -MP -MF .out/CC.c/hello.o.d'

```

This shows us the computed value, the definition, which is attached to a
base class called `_Compile`, and the classes from which this instance
inherits properties, in order of precedence.

Within a Minion property definition, `{NAME}` is a syntax for property
expansion.  When a property definition is evaluated, `{NAME}` is replaced
with the value of the property `NAME`.  The `@` and `<` properties mimic the
`$@` and `$<` variables available in Make recipes, and there is also a `^`
property analogous to `$^`.  We can see that the `_Compile.command`
definition concerns itself with specifying the input files, output files,
and implied dependencies.  It refers to a property named `flags` for
command-line options that address other concerns.

Our previous two examples, above, provided overriding definitions for
`flags`.  Setting `CC(hello.c).flags=-Os` defined an instance-specific
property, so it only affected the command line for one object file.  Setting
`CC.flags` provided a definition inherited by all `CC` instances (unless
they have their own instance-specific definitions).

### User Classes

An important note about overriding class properties: `CC` is a *user class*,
intended for customization by user makefiles.  Minion does not attach any
properties *directly* to user classes; it just provides a default
inheritance, and that, too, can be overridden by the user makefile.  User
classes are listed in `minion.mk`, and you can easily identify a user class
because it will inherit from an internal class that has the same name except
for a prefixed underscore (`_`).

Directly re-defining properties of non-user classes in Minion is not
supported.  Instead, define you own sub-classes.


## Custom Classes

```console
$ cp Makefile3 Makefile; diff Makefile2 Makefile3
5a6,11
> CCg.inherit = CC
> CCg.flags = -g {inherit}
> 
> Sizes.inherit = Phony
> Sizes.command = wc -c {^}
> 
```

A variable assignment of the form `CLASS.inherit` specifies the base class
from which `CLASS` inherits.  (It resembles a property definition, but
`inherit` is a special keyword, not a property.)

`Sizes` inherits from `Phony`, which is much more generic than `CC`, so its
subclasses have to define the `command` property in its entirety.

```console
$ make 'Sizes(CC(hello.c),CCg(hello.c))'
#-> CC(hello.c)
gcc -c -o .out/CC.c/hello.o hello.c     -MMD -MP -MF .out/CC.c/hello.o.d
#-> CCg(hello.c)
gcc -c -o .out/CCg.c/hello.o hello.c -g     -MMD -MP -MF .out/CCg.c/hello.o.d
wc -c .out/CC.c/hello.o .out/CCg.c/hello.o
     776 .out/CC.c/hello.o
    2056 .out/CCg.c/hello.o
    2832 total
```

The `CCg.flags` definition references `{inherit}`.  This is does not refer
to a property named "inherit"; it has a special function, and that is to
return the value for the current property that would be in effect if the
current definition did not exist.  It can be used recursively; an inherited
definition that was invoked via `{inherit}` may itself use `{inherit}`,
which will then continue up the inheritance chain, looking for the
next-lower-precedence definition.  Perhaps the following will illustrate:

```console
$ make help 'CCg(hello.c).flags' CC.flags='-Wall {inherit}'
CCg(hello.c) inherits from: CCg CC _CC Compile _Compile Builder 

CCg(hello.c).flags is defined by:

   CCg.flags = -g {inherit}

...wherein {inherit} references:

   CC.flags = -Wall {inherit}

...wherein {inherit} references:

   _Compile.flags = {optFlags} {warnFlags} {libFlags} $(addprefix -I,{includes})

Its value is: '-g -Wall    '

```


## Variants

We can build different *variants* of our the project described by our
Makefile.  Variants are separate instantiations of our build that will have
a similar overall structure, but may differ from each other in various ways.
For example, we may have "release" and "debug" variants, or "ARM" and
"Intel" variants of a C project.

Furthermore, we want these variants to exist side-by-side and not interfere
with each other, so we can retain the benefits of incremental builds.  We
have shown how typing `make CC.flags=-g` and then later `make CC.flags=-O3`
could be used to achieve some sort of "debug" vs. "release" distinction, but
not only is this cumbersome, it is inefficient.  Each time we switch
"variants", it has to compile everything again.  Instead, we do the
following:

  * Use the variable `V` to identify a variant name, so that `make
    V=<name>` can be used to build a specific variant.

  * Define properties in a way that depends on `$V`.

  * Incorporate `$V` into the output directory.  Minion does this by default
    when `V` is assigned a non-empty value.

When defining variant-dependent properties, we could use Make's functions:

    CC.flags = $(if $(filter debug,$V),-g, ... )

Instead, it is much more elegant to leverage Minion's property evaluation
and group property definitions into classes whose names incorporate `$V`.

    CC.inherit = CC-$V _CC

    CC-debug.flags = -g
    CC-fast.flags = -O3
    CC-small.flags = -Os

```console
$ cp Makefile4 Makefile
```
```console
$ make V=debug help 'CC(hello.c).flags'
CC(hello.c) inherits from: CC CC-debug  _CC Compile _Compile Builder 

CC(hello.c).flags is defined by:

   CC-debug.flags = -g

Its value is: '-g'

```
```console
$ make V=fast help 'CC(hello.c).flags'
CC(hello.c) inherits from: CC CC-fast  _CC Compile _Compile Builder 

CC(hello.c).flags is defined by:

   CC-fast.flags = -O3

Its value is: '-O3'

```

Finally, we want to be able to build multiple variants with a single
invocation.  Minion provides a built-in class, `Variants(TARGET)`, that
builds a number of variants of the target `TARGET`.  The `all` property
gives the list of variants, so assigning `Variants.all` will establish a
default set of variants for all instances of `Variants`.

The variable `Variants.all` is also used to provide a default for `V`: it
defaults to the first word in `Variants.all`.

```console
$ make sizes           # default (first) variant
#-> CC(hello.c)
gcc -c -o .out/debug/CC.c/hello.o hello.c -g -MMD -MP -MF .out/debug/CC.c/hello.o.d
#-> LinkC(hello.c)
gcc -o .out/debug/LinkC.c/hello .out/debug/CC.c/hello.o  
#-> CC(binsort.c)
gcc -c -o .out/debug/CC.c/binsort.o binsort.c -g -MMD -MP -MF .out/debug/CC.c/binsort.o.d
#-> LinkC(binsort.c)
gcc -o .out/debug/LinkC.c/binsort .out/debug/CC.c/binsort.o  
wc -c .out/debug/LinkC.c/hello .out/debug/LinkC.c/binsort
   49648 .out/debug/LinkC.c/hello
   49928 .out/debug/LinkC.c/binsort
   99576 total
```
```console
$ make sizes V=fast    # "fast" variant
#-> CC(hello.c)
gcc -c -o .out/fast/CC.c/hello.o hello.c -O3 -MMD -MP -MF .out/fast/CC.c/hello.o.d
#-> LinkC(hello.c)
gcc -o .out/fast/LinkC.c/hello .out/fast/CC.c/hello.o  
#-> CC(binsort.c)
gcc -c -o .out/fast/CC.c/binsort.o binsort.c -O3 -MMD -MP -MF .out/fast/CC.c/binsort.o.d
#-> LinkC(binsort.c)
gcc -o .out/fast/LinkC.c/binsort .out/fast/CC.c/binsort.o  
wc -c .out/fast/LinkC.c/hello .out/fast/LinkC.c/binsort
   49424 .out/fast/LinkC.c/hello
   49456 .out/fast/LinkC.c/binsort
   98880 total
```
```console
$ make all-sizes       # sizes for *all* variants
wc -c .out/debug/LinkC.c/hello .out/debug/LinkC.c/binsort
   49648 .out/debug/LinkC.c/hello
   49928 .out/debug/LinkC.c/binsort
   99576 total
wc -c .out/fast/LinkC.c/hello .out/fast/LinkC.c/binsort
   49424 .out/fast/LinkC.c/hello
   49456 .out/fast/LinkC.c/binsort
   98880 total
#-> CC(hello.c)
gcc -c -o .out/small/CC.c/hello.o hello.c -Os -MMD -MP -MF .out/small/CC.c/hello.o.d
#-> LinkC(hello.c)
gcc -o .out/small/LinkC.c/hello .out/small/CC.c/hello.o  
#-> CC(binsort.c)
gcc -c -o .out/small/CC.c/binsort.o binsort.c -Os -MMD -MP -MF .out/small/CC.c/binsort.o.d
#-> LinkC(binsort.c)
gcc -o .out/small/LinkC.c/binsort .out/small/CC.c/binsort.o  
wc -c .out/small/LinkC.c/hello .out/small/LinkC.c/binsort
   49424 .out/small/LinkC.c/hello
   49456 .out/small/LinkC.c/binsort
   98880 total
```


## Recap

To summarize the key concepts in Minion:

 - *Instances* are function-like descriptions of build products.  They can
   be given as targets, and named as inputs to other instances.  They
   consist of a *class* name and an *argument*.

 - *Indirections* are ways to reference Make variables that hold lists of
   other targets.  They can be used as arguments to instances, or in the
   `in` property for an instance, or on the command line.

 - *Aliases* are short names that can be specified on the command line.
   They can identify sets of other targets to build and/or commands to be
   executed when they are built.

 - Properties dictate how instances behave.  Properties are associated with
   classes or instances, and classes may inherit from other classes.
   Properties are defined using Make variable assignments, wherein the
   variable name is structured `CLASSNAME.PROPERTYNAME`.  The definitions
   are in Make syntax, and can refer to other properties using `{NAME}`.


