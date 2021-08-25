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

This builds the program, but `hello.o` was not rebuilt.  This is because we
have already built `CC[hello.c]`.  Doing nothing, whenever possible, is
what a build system is all about.

We can demonstrate that everything will get re-built, if necessary, by
re-issuing this command after invoking `make clean`.  The `clean` target is
defined by Minion, and it removes the "output directory", which, by default,
contains all generated artifacts.

    $ make clean
    $ make LinkC[hello.c]

Likewise, `Run` can also infer a `LinkC` instance (which in turn will infer
a `CC` instance):

    $ make Run[hello.c]


## Phony Targets

A `Run` instance writes to `stdout` and does not generate an output file.
It does not make sense to talk about whether its output file needs to be
"rebuilt", because there is no output file.  Targets like this, that exist
for side effects only, are called phony targets.  They are always executed
whenever they are named as a goal, or as a prerequisite of a target named as
a goal, and so on.

    $ make Run[hello.c]

A class named `Exec` also runs a program, but it captures its output in a
file, so its instances are *not* phony.

    $ make Exec[hello.c]

Using `Exec` is a way to run unit tests.  The existence of the output file
is evidence that the unit test passed (the program exited without an error
code).  If we want to view the output, we can use `Print`, which generates a
phony target that writes its input to `stdout`:

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
Indirections can be used in contexts where lists of targets are expected,
such as goals and arguments to instances.

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
we explicitly describe on the command line.  We want to be able to describe
complex builds in a Makefile so they can invoked with a simple command, like
`make` or `make deploy`.  Minion provides aliases for this purpose.  An
alias is a name that identifies a phony target instead of an actual file.

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


## Wrap-up

We can use a debug feature of Minion to see the Make rules that it
generates.  We bring this up just to illustrate what an equivalent Makefile
would look like, if one were to write it by hand, instead of leveraging
Minion:

    $ make default deploy minion_debug=%
