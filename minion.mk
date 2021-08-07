# Minion: See minion.md for documentation.

# All build products are placed under this directory
OUTDIR ?= .out/

# Invoking with "make -Rr ..." saves time and avoids potential confusion.
# We can set -r here; it's too late for -R but that can affect sub-makes.
MAKEFLAGS := Rr $(MAKEFLAGS)

################################
# Utilities
################################

# Character constants
\s := $(if ,, )
\t := $(if ,,	)
\h := \#
; := ,
define \n


endef

# Format a value for readability (prefix lines of a multi-line value)
_q1 = $(if $(findstring $(\n),$1),$(subst $(\n),$(\n)  | ,$(\n)$1),'$1')
_q2 = $(call _q1,$2)

# Test equality
_eq? = $(findstring $(subst x$1,1,x$2),1)

# Unit test helper
_expectEQ = $(if $(call _eq?,$1,$2),,$(error Values differ:$(\n)A: $(_q1)$(\n)B: $(_q2)$(\n)))

# ? FN ARGS... : Equivalent to $(call FN,ARGS...) but logs the result to stdout
? = $(info ?: $$(call $1,$2,$3,$4,$5) -> $(call _q1,$(call $1,$2,$3,$4,$5)))$(call $1,$2,$3,$4,$5)

# _log NAME VALUE : Output "NAME: VALUE" when NAME matches $(minion_debug)
_log = $(if $(filter $(minion_debug),$1),$(info $1: $(_q2)))

# _eval NAME VALUE : Log + eval VALUE
_eval = $(_log)$(eval $2)

# _isDefined VAR : True if VAR is the name of a defined variable
_isDefined = $(if $(filter undefined,$(flavor $1)),,$1)

# Return all but the first word in a list
_rest = $(wordlist 2,99999999,$1)

# Quote an argument for /bin/sh or /bin/bash
_shellQuote = '$(subst ','\'',$1)'#'  (comment to fix font coloring)

# Escape string contents for inclusion in a `printf` format string
_printfEsc = $(subst %,%%,$(subst $(\n),\n,$(subst $(\t),\t,$(subst \,\\,$1))))

# Expand indirections
_expv = $(subst :$1$(if $(findstring *,$(subst :$1*,,:$2)),*),,:$2)
# _expandMap: $1=CLASS, $2=CLASS*VAR
_expandMap = $(foreach o,$(call _expand,$(_expv)),$1[$o])
_expand = $(foreach w,$1,$(or $(filter %],$w),$(if $(findstring *,$w),$(if $(filter *%,$w),$(call _expand,$($(w:*%=%))),$(call _expandMap,$(word 1,$(subst *, ,$w)),$w)),$w)))

# $K=key, $1=value -> value
_memoSet = $(eval $$K := $$(or )$(subst $(\n),$$(\n),$(subst \#,$$(\h),$(subst $$,$$$$,$1))))$1

# $K=key -> bool
_memoIsSet = $(filter-out undef%,$(flavor $K))

# _once VAR : Evaluate a variable at most once
_once = $(foreach K,~$1,$(if $(_memoIsSet),$($K),$(call _memoSet,$($1))))

# Inspect targets/goals
_isInstance = $(filter %],$1)
_isIndirect = $(findstring *,$(word 1,$(subst [,[ ,$1)))
_aliasInputs = $(addprefix *,$(call _isDefined,make_$1))

# Translate goal $1 to a instance if a rule needs to be generated.
_goalID = $(if $(or $(_isInstance),$(_isIndirect),$(_aliasInputs)),Alias[$1])

# Get all instances in $1 and in their `needs`, transitively.
# $1 = list of IDs  $2 = seen IDs
_rollup = $(if $1,$(call _rollup,$(filter-out $1 $2,$(sort $(call get,needs,$(_isInstance)))),$2 $1),$(filter %],$2))

# See prototype.scm for documentation on the following:

_pairIDs = $(filter-out $$%,$(subst $$, $$,$1))
_pairFiles = $(filter-out %$$,$(subst $$,$$ ,$1))
_inferPairs = $(if $2,$(foreach w,$1,$(or $(foreach x,$(word 1,$(filter %],$(patsubst %$(or $(suffix $(call _pairFiles,$w)),.),%[$(call _pairIDs,$w)],$2))),$x$$$(call get,out,$x)),$w)),$1)

_argGroup = $(if $(findstring :[,$(subst ],[,$1)),$(if $(findstring $1,$2),$(_argError),$(call _argGroup,$(subst $(\s),,$(foreach w,$(subst $(\s) :],]: ,$(patsubst :[%,:[% ,$(subst :], :],$(subst :[, :[,$1)))),$(if $(filter %:,$w),$(subst :,,$w),$w))),$1)),$1)
_argHash2 = $(subst :,,$(foreach w,$(subst :$;, ,$(call _argGroup,$(subst =,:=,$(subst $;,:$;,$(subst ],:],$(subst [,:[,$1)))))),$(if $(findstring :=,$w),,=)$w))
_argHash = $(if $(or $(findstring [,$1),$(findstring ],$1),$(findstring =,$1)),$(_argHash2),=$(subst $;, =,$1))
_hashGet = $(patsubst $2=%,%,$(filter $2=%,$1))

_fsenc = $(subst /,@D,$(subst ~,@T,$(subst !,@B,$(subst *,@_,$(subst =,@E,$(subst ],@-,$(subst [,@+,$(subst |,@1,$(subst @,@0,$1)))))))))
_outBasis = $(if $(_isIndirect),$(lastword $(subst @D,/,$(subst @_, ,$(_fsenc)))),$(or $(word 1,$2),default))
_outDirI = $(dir _$(subst $(\s),,$(filter %@,$(subst @_,@ _,$(_fsenc))))/$2)
_outDirS = $(call _fsenc,$3)$(if $(_isIndirect),$(_outDirI),$(suffix $2)$(patsubst _/$(OUTDIR)%,_%,$(if $(filter %],$1),_)$(subst //,/_root_/,$(subst //,/,$(subst /../,/_../,$(subst /./,/_./,$(subst /_,/__,$(subst /,//,$(dir /$2)))))))))
_outDirC = $(call _outDirS,$4,$2,$3$(subst $(if ,,_$4,),$(if ,,_|,),_$1))
_outDir = $(if $(if $(word 2,$4),,$(filter =%,$4)),$(_outDirS),$(call _outDirC,$1,$2,$3,$(word 1,$(call _hashGet,$4))))


#--------------------------------
# Property evaluation
#--------------------------------

# & PROPERTY : Search inheritance chain for first matching property definition
& = $(or $(call _isDefined,$C[$A].$1),$(call _isDefined,$C.$1),$(firstword $(foreach C,$($C.inherit),$(call &,$1))))

# . PROPERTY : Evaluate property on self (during some other property evaulation)
. = $(foreach K,<$C[$A].$1>,$(if $(_memoIsSet),$($K),$(call _memoSet,$(call $(or $&,$(_dotErr))))))

_dotErr = $(error property '$1' not defined for $C[$A])

# get PROPERTY IDs : Evaluate property on multiple target IDs
get = $(foreach o,$2,$(if $(filter %],$o),$(foreach C,$(_getC),$(foreach A,$(_getA),$(call .,$1))),$(foreach C,File,$(foreach A,$o,$(call .,$1)))))

_getC = $(or $(subst [,,$(filter %[,$(word 1,$(subst [,[ ,$o)))),$(_getErr))
_getA = $(or $(subst :$C[,,:$(o:%]=%)),$(_getErr))
_getErr = $(error Mal-formed target ID '$o' in $$(call get,$1,$o)$(\n)  Expected 'Class[Arg]'))


#--------------------------------
# Help system
#--------------------------------

define _helpMessage
$(word 1,$(MAKEFILE_LIST)) usage:

   make                     Build the target named "default"
   make GOALS...            Build the named targets
   make help                Show this message
   make help GOALS...       Describe the named targets
   make help C[A].P         Compute value of property P for C[A]
   make clean               `$(call get,command,Alias[clean])`

Goals can be ordinary Make targets defined by your Makefile,
instances (`Class[Arg]`), variable indirections (`*var`), or
aliases defined by your Makefile.  See minion.md for more.

endef

_fmtList = $(if $(word 1,$1),$(subst $(\s),$(\n)   , $(strip $1)),(none))

_getID.P = $(foreach p,$(or $(lastword $(subst ].,] ,$1)),$(error Empty property name)),$(call get,$p,$(patsubst %].$p,%],$1)))

_isProp = $(filter ].%,$(lastword $(subst ], ],$1)))

# instance, indirection, alias, other
_goalType = $(if $(_isInstance),Instance,$(if $(_isIndirect),Indirect,$(if $(_aliasInputs),Alias,$(if $(_isProp),Property,Other))))

_ivar = $(lastword $(subst *, ,$1))

_helpDeps = Direct dependencies: $(call _fmtList,$(call get,needs,$1))$(\n)$(\n)Indirect dependencies: $(call _fmtList,$(call filter-out,$(call get,needs,$1),$(call _rollup,$(call get,needs,$1))))


define _helpInstance
Target ID "$1" is an instance (a generated artifact).

Output: $(call get,out,$1)

Rule: $(call _q1,$(call get,rule,$1))

$(_helpDeps)
endef


define _helpIndirect
"$1" is an indirection on the following variable:

   $(_ivar) = $(value $(_ivar))

It expands to the following targets: $(call _fmtList,$(call _expand,$1))
endef


define _helpAlias
Target "$1" is an alias defined by:

   make_$1 = $(value make_$1)

$(call _helpDeps,Alias[$1])

Alias[$1] generates the following rule: $(call _q1,$(call get,rule,Alias[$1]))
endef


_helpProperty = $1 = $(call _q1,$(call _getID.P,$1))


define _helpOther
Target "$1" is not generated by Minion.  It may be a source
file or a target defined by a rule in the Makefile.
endef


# $1 = command line goals other than "help"
_help! = \
  $(if $(filter com%,$(origin help_expr)),\
    $(info $(value help_expr) = $(call _q1,$(help_expr))),\
    $(if $1,,$(info $(_helpMessage)))\
    $(foreach g,$1,\
      $(info $(call _help$(call _goalType,$g),$g))))


#--------------------------------
# Rules
#--------------------------------

# This will be the default target when `$(end)` is omitted (and
# nothing is listed on the command line)
_error_default: ; $(error Makefile included minion-start.mk but did not call `$$(end)`)

# Using "$*" in the following pattern rule we can capture the entirety of
# the goal, including embedded spaces.  We re-invoke Make to evaluate the
# string prior to the rule processing phase.
$$%: ; @$(MAKE) -f $(word 1,$(MAKEFILE_LIST)) help help_expr=$(call _shellQuote,$$$*)

# Define an alias for `clean`.  User makefiles can override these.
make_clean ?= # no dependencies
Alias[clean].command ?= rm -rf $(filter-out /% . ./,$(OUTDIR))

end = $(eval $(value _epilogue))

define _epilogue
  ifndef MAKECMDGOALS
    # .DEFAULT_GOAL only matters when there are no command line goals
    .DEFAULT_GOAL = default
    _goalIDs := $(call _goalID,default)
  else ifneq "" "$(filter help,$(MAKECMDGOALS))"
    # When `help` is given on the command line, we treat all other goals as
    # things to describe, not build.  We display help messages right now,
    # before the rule processing phase, and emit "null" rules for goals so
    # that rule processing will silently do nothing.
    $(call _help!,$(subst :,=,$(filter-out help,$(MAKECMDGOALS))))
    _goalIDs := $(MAKECMDGOALS:%=NullAlias[%])
  else
    _goalIDs := $(foreach g,$(MAKECMDGOALS),$(call _goalID,$g))
  endif

  _allIDs := $(filter %],$(call _rollup,$(_goalIDs)))
  $(call _log,all,$(_allIDs))
  $(foreach g,$(_allIDs),$(call _eval,eval-$g,$(call get,rule,$g)))
endef


#--------------------------------
# Built-in Classes
#--------------------------------

# Shorthand variables: $@, $<, $^

@ = $(call .,out)
^ = $(call .,^)
< = $(firstword $^)

# Obtain argument values for the current argument.  The argument is treated
# as a comma-delimited list of values, each with an optional "NAME=" prefix
# (a missing prefix is equivalent to an empty NAME).

# Return argument values associated with the name $1.
_argValues = $(call _hashGet,$(call .,argHash),$1)
_arg1 = $(word 1,$(_argValues))
_argIDs = $(call _expand,$(_argValues))
_argFiles = $(call get,out,$(_argIDs))
_argError = $(info $C[$A] contains unbalanced brackets in its argument)$1


# The `File` class is a built-in class that is used to construct instances
# when an ordinary file or target name is provided (typically, these
# identify source artifacts).  The `File` class implements the builder
# interface, so plain files names can be supplied anywhere instances are
# expected.  Property evaluation short-cuts its handling of File instances,
# so inheritance is not available.
#
File.out = $A
File.rule = #
File.needs = #


# Builder:  See minion.md
# 
Builder.rule = $(subst $(\t)$(\n),,$(Builder_rule))

Builder.argHash = $(call _argHash,$A,_argError)

# `needs` should include all explicit dependencies and any instances
# required to build auto-generated implicit dependencies (which should be
# included in `ooIDs`).
Builder.needs = $(call .,inIDs) $(call .,upIDs) $(call .,ooIDs)

Builder.^ = $(call .,inFiles)
Builder.< = $(firstword $(call .,^))

Builder.U^ = $(call get,out,$(call .,upIDs))
Builder.U< = $(firstword $(call .,U^))

# `in` is the target list giving user-supplied inputs, and is intended to be
# easily overridden on a per-class or per-instance basis.  Depending on the
# class, other secondary input files may be inferred (this is controlled by
# the `inferClasses` property).
Builder.in = $(call _argValues)

# _inPairs = named input pairs (*before* inference)
Builder._inPairs = $(foreach i,$(call _expand,$(call .,in)),$(if $(filter %],$i),$i$$$(call get,out,$i),$i))

# inPairs = input (ID,FILE) pairs (direct; after inference)
Builder.inPairs = $(call _inferPairs,$(call .,_inPairs),$(call .,inferClasses))
Builder.inIDs = $(call _pairIDs,$(call .,inPairs))
Builder.inFiles = $(call _pairFiles,$(call .,inPairs))

# `up` provides dependencies built into the class itself.
Builder.up = #
Builder.upIDs = $(call _expand,$(call .,up))

# `orderOnly` is a target list (just like `in`)
Builder.orderOnly = #
Builder.ooIDs = $(call _expand,$(call .,orderOnly))

# `inferClasses` a list of words in the format "CLASS.EXT", implying that
# each input filename ending in ".EXT" should be replaced wth
# "CLASS[FILE.EXT]".  This is used to, for example, convert ".c" files to
# ".o" when they are provided as inputs to a Program instance.
Builder.inferClasses = #

# Note: `outDir`, `outName`, and `outSuffix` are inputs to `out`, and any of
# them can be overridden.  Do not assume that, for example, `outDir` is
# always the same as `$(dir $(call .,out))`.
Builder.out = $(call .,outDir)$(call .,outName)
Builder.outDir = $(OUTDIR)$(call _outDir,$A,$(call .,outBasis),$C,$(call .,argHash))
Builder.outName = $(basename $(notdir $(call .,outBasis)))$(call .,outSuffix)
Builder.outSuffix = $(suffix $(call .,outBasis))
Builder.outBasis = $(call _outBasis,$(_arg1),$(call _pairFiles,$(call .,_inPairs)))

# Message to be displayed when/if the command executes (empty => nothing displayed)
Builder.message = \#-> $C[$A]
Builder.echoCommand = $(if $(call .,message),@echo $(call _shellQuote,$(call .,message)))

Builder.mkdirCommand = @mkdir -p $(dir $@)

Builder.phonyRule = #

Builder.depsFile = #

_prefixIf = $(if $2,$1$2)

# Note: blank command lines are deleted in Builder.rule
define Builder_rule
$@ : $(call .,^) $(call .,U^) $(call _prefixIf, | ,$(call get,out,$(call .,ooIDs)))
	$(subst $$,$$$$,$(call .,echoCommand)
	$(call .,mkdirCommand)
	$(subst $(\n),$(\n)$(\t),$(call .,command)))

$(call .,phonyRule)
$(addprefix -include ,$(call .,depsFile))
endef


# Phony[INPUTS] : Generate a phony rule.
#
#   A phony rule does not generate an output file.  Therefore, Make cannot
#   determine whether its result is "new" or "old", so it is always
#   considered "old", and its recipe will be executed whenever it is listed
#   as a target.
#
Phony.inherit = Builder
Phony.phonyRule = .PHONY: $@
Phony.mkdirCommand = #
Phony.message = #
Phony.command = @true # avoid "nothing to be done for..." message


# Alias[GOAL] : Generate a rule that builds GOAL (a named alias, instance,
#    or indirection).  Goals may use `:` in place of `=` in order to allow
#    them to be used on the Make command line.
#
Alias.inherit = Phony
Alias.in = $(or $(call _aliasInputs,$A),$(subst :,=,$A))
Alias.out = $(subst :,\:,$A)


# NullAlias[GOAL] : Generate a rule for GOAL that does nothing.
#
NullAlias.inherit = Alias
NullAlias.in = #


# Compile[SOURCE] : Compile a C file to an object file.
#
Compile.inherit = Builder
Compile.outSuffix = .o
Compile.command = $(call .,compiler) -c -o $@ $< $(call .,flags) -MMD -MP -MF $(call .,depsFile)
Compile.compiler = gcc
Compile.depsFile = $@.d
Compile.flags = $(call .,optFlags) $(call .,warnFlags) $(call .,libFlags) $(addprefix -I,$(call .,includes))
Compile.optFlags = -Os
Compile.warnFlags = -W -Wall -Wmultichar -Wpointer-arith -Wcast-align -Wcast-qual -Wwrite-strings -Wredundant-decls -Wdisabled-optimization -Woverloaded-virtual -Wsign-promo -Werror
Compile.libFlags = #
Compile.includes = #


# Compile++[SOURCE] : Compile a C++ file to an object file.
#
Compile++.inherit = Compile
Compile++.compiler = g++
Compile++.warnFlags = -W -Wall -Wmultichar -Wpointer-arith -Wcast-align -Wcast-qual -Wwrite-strings -Wredundant-decls -Wdisabled-optimization -Woverloaded-virtual -Wsign-promo -Werror


# Program[INPUTS] : Link a command-line C program.
#
Program.inherit = Builder
Program.outSuffix = #
Program.command = $(call .,compiler) -o $@ $^ $(call .,flags) 
Program.compiler = gcc
Program.inferClasses = Compile.c
Program.flags = $(call .,libFlags)
Program.libFlags = #


# Program++[INPUTS] : Link a command-line C++ program.
#
Program++.inherit = Program
Program++.compiler = g++
Program++.inferClasses = Compile.c Compile++.cpp


# Shell[PROGRAM] : This is a mixin that supports running command-line
# programs.
#
Shell.exec = $(_exportPrefix)./$< $(call .,args)
Shell.inferClasses = Program.c Program.o Program++.cpp
Shell.args = #
Shell.exports = #

_exportPrefix = $(foreach v,$(call .,exports),$v=$(call _shellQuote,$(call .,$v)) )


# Exec[PROGRAM] : Run PROGRAM, capturing its output (stdout).
#
Exec.inherit = Shell Builder
Exec.command = ( $(call .,exec) ) > $@ || rm $@
Exec.outSuffix = .out


# Run[PROGRAM] : run program (as a Phony rule)
#
Run.inherit = Shell Phony
Run.command = $(call .,exec)


# Compute `out` from `out=...` arg value, or default to $(OUTDIR)$C/$(notdir ...)
_arg_out = 


# Copy[INPUT]
# Copy[INPUT,out=OUT]
#
#   Copy an artifact.  If OUT is not provided, the file is copied to a
#   directory named $(OUTDIR)$C.
#
Copy.inherit = Builder
Copy.out = $(or $(call _arg1,out),$(OUTDIR)$C/$(notdir $<))
Copy.command = cp $< $@


# Mkdir[DIR] : Create directory
#
Mkdir.inherit = Builder
Mkdir.in =
Mkdir.out = $A
Mkdir.command = mkdir -p $@


# Touch[FILE] : Create empty file
#
Touch.inherit = Builder
Touch.in =
Touch.out = $A
Touch.command = touch $@


# Remove[FILE] : Remove FILE from the file system
#
Remove.inherit = Phony
Remove.in =
Remove.command = rm -f $A


# Print[INPUT] : Write artifact to stdout.
#
Print.inherit = Phony
Print.command = @cat $<


# Tar[INPUTS] : Construct a TAR file
#
Tar.inherit = Builder
Tar.outSuffix = .tar
Tar.command = tar -cvf $@ $^


# Gzip[INPUT] :  Compress an artifact.
#
Gzip.inherit = Builder
Gzip.command = cat $< | gzip - > $@ || rm $@
Gzip.outSuffix = $(suffix $<).gz


# Zip[INPUTS] : Construct a ZIP file
#
Zip.inherit = Builder
Zip.outSuffix = .zip
Zip.command = zip $@ $^

# Unzip[OUT] : Extract from a zip file
#
#   The argument is the file to extract.  The zip file name is based on the
#   class name.  Declare a subclass with the appropriate name, or override
#   its `in` property to specify the zip file.
#
Unzip.inherit = Builder
Unzip.command = unzip -p $< $A > $@ || rm $@
Unzip.in = $C.zip


# Write[VAR]
# Write[VAR,out=OUT]
#
#   Write the value of a variable to a file.
#
Write.inherit = Builder
Write.out = $(or $(call _arg1,out),$(OUTDIR)$C/$(notdir $(call _arg1)))
Write.command = @printf $(call _shellQuote,$(call _printfEsc,$(call .,data))) > $@
Write.data = $($(call _arg1))
Write.in = $(MAKEFILE_LIST)


ifndef minion_start
  $(end)
endif
