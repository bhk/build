# Example Walk-through


## Introduction

Here is an example command line session that introduces Minion
functionality.  You can follow along typing the commands yourself in the
`example` subdirectory of the project.

We begin with a minimal Makefile:

    $ cp Makefile1 Makefile
    $ cat Makefile

This Makefile doesn't describe anything to be built, but it does invoke
Minion, so when we type `make` in this directory, Minion will process the
goals.  A *goal* is target name that is listed on the command line.  Goals
determine what Make actually does when it is invoked.


## Instances

The salient feature of Minion is instances.  An instance is a description of
a build step.  Instances can be provided as goals or as inputs to other
build steps.

An instance is written `CLASS[ARGUMENT]`.  `ARGUMENT` typically is the name
of an input to the build step.  `CLASS` is the name of a class that is
defined by Minion or your Makefile.  To get started, let's use some classes
built into Minion:

    $ make CC[hello.c]
    $ make LinkC[CC[hello.c]]
    $ make Run[LinkC[CC[hello.c]]]


## Inference

Some classes have the ability to *infer* intermediate build steps, based on
the file extension.  For example, if we provide a ".c" file directly to
`LinkC`, it knows how to generate the intermediate artifacts.

    $ make LinkC[hello.c]

This command linked the program, but did not rebuild `hello.o`.  This is
because we have already built the inferred dependency, `CC[hello.c]`.  Doing
nothing, whenever possible, is what a build system is all about.

We can demonstrate that everything will get re-built, if necessary, by
re-issuing this command after invoking `make clean`.  The `clean` target is
defined by Minion, and it removes the "output directory", which, by default,
contains all generated artifacts.

    $ make clean; make LinkC[hello.c]

Likewise, `Run` can also infer a `LinkC` instance (which in turn will infer
a `CC` instance):

    $ make clean; make Run[hello.c]


## Phony Targets

A `Run` instance writes to `stdout` and does not generate an output file.
It does not make sense to talk about whether its output file needs to be
"rebuilt", because there is no output file.  Targets like this, that exist
for side effects only, are called phony targets.  They are always executed
whenever they are named as a goal, or as a prerequisite of a target named as
a goal, and so on.

    $ make Run[hello.c]

A class named `Exec` also runs a program, but it captures its output in a
file, so its targets are *not* phony.

    $ make Exec[hello.c]

Using `Exec` is a way to run unit tests.  The existence of the output file
is evidence that the unit test passed (the program exited without an error
code).  If we want to view the output, we can use `Print`, a class that
generates a phony target that writes its input to `stdout`:

    $ make Print[hello.c]
    $ make Print[Exec[hello.c]]


## Help

When the goal `help` appears on the command line, Minion will describe all
of the other goals on the command line, instead of building them.  This
gives us visibility into how things are being interpreted, and how they map
to underlying Make primitives.

    $ make help Run[hello.c]
    $ make help Exec[hello.c]


## Indirections

An *indirection* is a notation for referencing the contents of a variable.
Indirections can be used in contexts where lists of targets are expected.
They are often used as a way to convey multiple input files in an argument.

There are two forms of indirections.  The first is called a simple
indirection, and it represents all of the targets identified in the
variable.

    $ make Tar[*sources] sources='hello.c binsort.c'

The other form is called a mapped indirection.  This constructs an instance
for each target identified in the variable.

    $ make help Run*sources sources='hello.c binsort.c'
    $ make Run*sources sources='hello.c binsort.c'
    $ make Tar[CC*sources] sources='hello.c binsort.c'


## Aliases

So far we haven't added anything to our Makefile, so we can only build what
we explicitly describe on the command line.  A build system should allow us
to describe complex builds in a Makefile so they can invoked with a simple
command, like `make` or `make deploy`.  Minion provides aliases for this
purpose.  An alias is a name that identifies a phony target instead of an
actual file.

To define an alias, define a variable named `Alias[NAME].in` to specify a
list of targets to be built when NAME is given as a goal, *or* define
`Alias[NAME].command` to specify a command to be executed when NAME is given
as a goal.  Or define both.

This next Makefile defines alias goals for "default" and "deploy":

    $ cp Makefile2 Makefile
    $ cat Makefile
    $ make deploy

If no goals are provided on the command line, Minion attempts to build the
target named `default`, so these commands do the same thing:

    $ make
    $ make default


## Properties and Customization

A build system should make it easy to customize how build results are
generated, and to define entirely new, unanticipated build steps.  Let's
show a couple of examples, and then dive into how and why they work.

    $ make CC[hello.c].flags=-Os

Observe how this affected the `gcc` command line.  [Also, as a side note,
note that Minion knew to re-compile the object file, even when no input
files had changed ... only the command line changed.  This fine-grained
dependency tracking means that `make clean` is almost never needed, even
after editing makefiles.]

We can make this change apply more widely:

    $ make CC.flags=-Os

So what's going on here?

Each instance is described by a set of properties.  Instances inherit
properties from classes, which may inherit properties from other classes,
and so on.  Properties can refer to other properties.  Minion's notion of
inheritance works like that of some object-oriented languages (hence the
term "instance"), but in Minion there is no mutable state.

The `command` property gives the command that will be executed to build an
output file.  We can ask Minion to describe that property:

    $ make help CC[hello.c].command

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
`flags`.  Setting `CC[hello.c].flags=-Os` defined an instance-specific
property, so it only affected the command line for one object file.  Setting
`CC.flags` provided a definition inherited by all `CC` instances (unless
they have their own instance-specific definitions).

### User Classes

An important note about overriding class properties: `CC` is a *user class*,
intended for customization by user makefiles.  Minion does not attach any
properties *directly* to user classes; it just provides a default
inheritance, which also can be overridden by the user makefile.  User
classes are listed in `minion.mk`, and you can easily identify a user class
because it will inherit from an internal class that has the same name except
for a prefixed underscore (`_`).

Directly re-defining properties of non-user classes in Minion is not
supported.  Instead, feel free to define you own classes.

## Custom Classes

    $ cp Makefile3 Makefile; diff Makefile2 Makefile3

A variable assignment of the form `CLASS.inherit` specifies the base class
from which `CLASS` inherits.  (It resembles a property definition, but
`inherit` is a special keyword, not a property.)

`Sizes` inherits from `Phony`, which is much more generic than `CC`, so its
subclasses have to define the `command` property in its entirety.

    $ make Sizes[CC[hello.c],CCg[hello.c]]

The `CCg.flags` definition references `{inherit}`.  This is does not refer
to a property named "inherit"; it has a special function, and that is to
return the value for the current property that would be in effect if the
current definition did not exist.  It can be used recursively; an inherited
definition that was invoked via `{inherit}` may itself use `{inherit}`,
which will then continue up the inheritance chain, looking for the
next-lower-precedence definition.  Perhaps the following will illustrate:

    $ make help CCg[hello.c].flags CC.flags='-Wall {inherit}'


## Wrap-up

We can use a debug feature of Minion to see the Make rules that it
generates.  We bring this up just to illustrate what an equivalent Makefile
would look like, if one were to write it by hand, instead of leveraging
Minion:

    $ make default deploy minion_debug=%
