# minion.mk

# Disable implicit rules for better performance.
MAKEFLAGS := r $(MAKEFLAGS)

#--------------------------------
# Built-in Classes
#--------------------------------


# The `File` class is used to construct an instance when `get` is called
# with a target ID that is not an instance.  It implements the builder
# interface, so plain files names can be supplied anywhere instances are
# expected.  Property evaluation logic short-cuts the handling of File
# instances, so inheritance is not available.
#
File.out = $A
File.rule = #
File.needs = #


# Builder[ARG]:  Base class for builders.

# Shorthand properties
Builder.@ = {out}
Builder.< = $(firstword {^})
Builder.^ = {inFiles}

Builder.argHash = $(call _argHash,$A,_argError)

# `needs` should include all explicit dependencies and any instances
# required to build auto-generated implicit dependencies (which should be
# included in `ooIDs`).
Builder.needs = {inIDs} {upIDs} {ooIDs}

Builder.up^ = $(call get,out,{upIDs})
Builder.up< = $(firstword {up^})

# `in` is the user-supplied set of "inputs", in the form of a target list
# (target IDs or indirections).  It is intended to be easily overridden
# on a per-class or per-instance basis.
#
# The actual set of prerequisites differs from `in` in a few ways:
#  - Indirections are expanded
#  - Inference (as per `inferClasses`) may replace targets with
#    intermediate results.
#  - `up` targets are also dependencies (but not "inputs")
#
Builder.in = $(_args)

_pairs = $(foreach i,$(call _expand,$1),$(if $(filter %],$i),$i$$$(call get,out,$i),$i))

# list of ([ID,]FILE) pairs for inputs (reuse argPairs if relevant)
Builder.inPairs = $(call _inferPairs,$(if $(call _eq?,{in},$(_args)),$(call _pairs,$(_args)),$(call _pairs,{in})),{inferClasses})
Builder.inIDs = $(call _pairIDs,{inPairs})
Builder.inFiles = $(call _pairFiles,{inPairs})

# `up` contains dependencies that are typically specified by the class
# itself, not by the instance argument or `in` property.
Builder.up = #
Builder.upIDs = $(call _expand,{up})

# `orderOnly` is a target list (just like `in`)
Builder.orderOnly = #
Builder.ooIDs = $(call _expand,{orderOnly})

# `inferClasses` a list of words in the format "CLASS.EXT", implying
# that each input filename ending in ".EXT" should be replaced wth
# "CLASS[FILE.EXT]".  This is used to, for example, convert ".c" files
# to ".o" when they are provided as inputs to a Program instance.
Builder.inferClasses = #

# Note: By default, `outDir`, `outName`, and `outExt` are used to
# construct `out`, but any of them can be overridden.  Do not assume
# that, for example, `outDir` is always the same as `$(dir {out})`.
Builder.out = {outDir}{outName}
Builder.outDir = $(OUTDIR)$(dir {outBasis})
Builder.outName = $(call _applyExt,$(notdir {outBasis}),{outExt})
Builder.outExt = %
Builder.outBasis = $(call _outBasis,$C,$A,{outExt},$(call get,out,$(filter $(_arg1),$(word 1,$(call _expand,{in})))),$(_arg1))

_applyExt = $(basename $1)$(subst %,$(suffix $1),$2)

# Message to be displayed when/if the command executes (empty => nothing displayed)
Builder.message = \#-> $C[$A]
Builder.echoCommand = $(if {message},@echo $(call _shellQuote,{message}))

Builder.mkdirCommand = @mkdir -p $(dir {@})

Builder.phonyRule = #

Builder.depsFile = #

_prefixIf = $(if $2,$1$2)

# _defer can be used to embed a function or variable reference that will
# be expanded when-and-if the recipe is executed.  Generally, all "$"
# characters within {command} will be escaped to avoid expansion by
# Make, but "$(_defer)(...)" becomes "$(...)" in the resulting recipe.
_defer = $$$(\t)

# Remove empty lines, prefix remaining lines with \t, and escape `$`.
# Un-escape $(_defer) to enable on-demand execution of functions.
_recipe = $(subst $$$$$(\t)$[,$$$[,$(subst $$,$$$$,$(subst $(\t)$(\n),,$(subst $(\n),$(\n)$(\t),$(\t)$1)$(\n))))

define Builder.rule
{@} : {^} {up^} $(call _prefixIf,| ,$(call get,out,{ooIDs}))
$(call _recipe,{echoCommand}
{mkdirCommand}
{command}
)
{phonyRule}
$(addprefix -include ,{depsFile})
endef


# Phony[INPUTS] : Generate a phony rule.
#
#   A phony rule does not generate an output file.  Therefore, Make cannot
#   determine whether its result is "new" or "old", so it is always
#   considered "old", and its recipe will be executed whenever it is listed
#   as a target.
#
Phony.inherit = Builder
Phony.phonyRule = .PHONY: {@}
Phony.mkdirCommand = #
Phony.message = #
Phony.command = @true # avoid "nothing to be done for..." message


# Alias[GOAL] : Generate a rule that builds GOAL (a named alias, instance,
#    or indirection).  Goals may use `:` in place of `=` in order to allow
#    them to be used on the Make command line.
#
Alias.inherit = Phony
Alias.in = $(or $(addprefix *,$(call _aliasVar,$A)),$(subst :,=,$A))
Alias.out = $(subst :,\:,$A)


# NullAlias[GOAL] : Generate a rule for GOAL that does nothing.
#
NullAlias.inherit = Alias
NullAlias.in = #


# CAlias[GOAL] : Build GOAL using a "compiled" Makefile.
#
CAlias.inherit = Alias
CAlias.in = Makefile[Alias[$A]]
CAlias.command = @$(MAKE) -f {<}


# Makefile[ID] : Generate a makefile that builds ID.
#
#   The makefile includes rules for all dependencies, with ID apeparing
#   first.  Command expansion is deferred to rule processing phase, so that
#   we can avoid the time it takes to generate all the rules whenever the
#   target makefile is fresh.
#
Makefile.inherit = Builder
Makefile.in = $(MAKEFILE_LIST)
Makefile.command = $(_defer)(call get,deferredCommand,$C[$A])
define Makefile.deferredCommand
$(call _recipe,
@rm -f {@}_tmp_ $(foreach I,$(call _rollup,$A),
@$(call _printf,$(call get,rule,$I)$(\n)) >> {@}_tmp_)
@mv {@}_tmp_ {@})
endef


# Compile[SOURCE] : Compile a C file to an object file.
#
Compile.inherit = Builder
Compile.outExt = .o
Compile.command = {compiler} -c -o {@} {<} {flags} -MMD -MP -MF {depsFile}
Compile.compiler = gcc
Compile.depsFile = {@}.d
Compile.flags = {optFlags} {warnFlags} {libFlags} $(addprefix -I,{includes})
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
Program.outExt = #
Program.command = {compiler} -o {@} {^} {flags} 
Program.compiler = gcc
Program.inferClasses = Compile.c
Program.flags = {libFlags}
Program.libFlags = #


# Program++[INPUTS] : Link a command-line C++ program.
#
Program++.inherit = Program
Program++.compiler = g++
Program++.inferClasses = Compile.c Compile++.cpp


# Shell[PROGRAM] : This is a mixin that supports running command-line
# programs.
#
Shell.exec = {exportPrefix}./{<} {args}
Shell.inferClasses = Program.c Program.o Program++.cpp
Shell.args = #
Shell.exports = #
Shell.exportPrefix = $(foreach v,{exports},$v=$(call _shellQuote,{$v}) )


# Exec[PROGRAM] : Run PROGRAM, capturing its output (stdout).
#
Exec.inherit = Shell Builder
Exec.command = ( {exec} ) > {@} || rm {@}
Exec.outExt = .out


# Run[PROGRAM] : run program (as a Phony rule)
#
Run.inherit = Shell Phony
Run.command = {exec}


# Copy[INPUT]
# Copy[INPUT,out=OUT]
#
#   Copy an artifact.  If OUT is not provided, the file is copied to a
#   directory named $(OUTDIR)$C.
#
Copy.inherit = Builder
Copy.out = $(or $(foreach K,out,$(_arg1)),{inherit})
Copy.outDir = $(OUTDIR)$C/
Copy.command = cp {<} {@}


# Mkdir[DIR] : Create directory
#
Mkdir.inherit = Builder
Mkdir.in =
Mkdir.out = $A
Mkdir.command = mkdir -p {@}


# Touch[FILE] : Create empty file
#
Touch.inherit = Builder
Touch.in =
Touch.out = $A
Touch.command = touch {@}


# Remove[FILE] : Remove FILE from the file system
#
Remove.inherit = Phony
Remove.in =
Remove.command = rm -f $A


# Print[INPUT] : Write artifact to stdout.
#
Print.inherit = Phony
Print.command = @cat {<}


# Tar[INPUTS] : Construct a TAR file
#
Tar.inherit = Builder
Tar.outExt = .tar
Tar.command = tar -cvf {@} {^}


# Gzip[INPUT] :  Compress an artifact.
#
Gzip.inherit = Builder
Gzip.command = cat {<} | gzip - > {@} || rm {@}
Gzip.outExt = %.gz


# Zip[INPUTS] : Construct a ZIP file
#
Zip.inherit = Builder
Zip.outExt = .zip
Zip.command = zip {@} {^}


# Unzip[OUT] : Extract from a zip file
#
#   The argument is the name of the file to extract from ther ZIP file.  The
#   ZIP file name is based on the class name.  Declare a subclass with the
#   appropriate name, or override its `in` property to specify the zip file.
#
Unzip.inherit = Builder
Unzip.command = unzip -p {<} $A > {@} || rm {@}
Unzip.in = $C.zip


# Write[VAR]
# Write[VAR,out=OUT]
#
#   Write the value of a variable to a file.
#
Write.inherit = Builder
Write.out = $(or $(foreach K,out,$(_arg1)),$(OUTDIR)$C/$(notdir $(_arg1)))
Write.command = @$(call _printf,{data}) > {@}
Write.data = $($(_arg1))
Write.in = $(MAKEFILE_LIST)


#--------------------------------
# Variable & Function Definitions
#--------------------------------

# All build products are placed under this directory
OUTDIR ?= .out/

# Character constants

\s := $(if ,, )
\t := $(if ,,	)
\H := \#
\L := {
\R := }
[ := (
] := )
; := ,
define \n


endef

# Exported functions

_qv = $(if $(findstring $(\n),$1),$(subst $(\n),$(\n)  | ,$(\n)$1),'$1')
_eq? = $(findstring $(subst x$1,1,x$2),1)
_expectEQ = $(if $(call _eq?,$1,$2),,$(error Values differ:$(\n)A: $(_qv)$(\n)B: $(call _qv,$2)$(\n)))
_? = $(call __?,$$(call $1,$2,$3,$4,$5),$(call $1,$2,$3,$4,$5))
__? = $(info $1 -> $2)$2
_isDefined = $(if $(filter u%,$(flavor $1)),,$1)
_shellQuote = '$(subst ','\'',$1)'#'  (comment to fix font coloring)
_printfEsc = $(subst $(\n),\n,$(subst $(\t),\t,$(subst \,\\,$1)))
_printf = printf "%b" $(call _shellQuote,$(_printfEsc))

K :=
_who = $0
_args = $(call _hashGet,$(call .,argHash,$(_who)),$K)
_arg1 = $(word 1,$(_args))
_argIDs = $(call _expand,$(_args))
_argFiles = $(call get,out,$(_argIDs))


# $(call _log,NAME,VALUE): Output "NAME: VALUE" when NAME matches the
#   pattern in `$(minion_debug)`.
_log = $(if $(filter $(minion_debug),$1),$(info $1: $(call _qv,$2)))

# $(call _eval,NAME,VALUE): Log + eval VALUE
_eval = $(_log)$(eval $2)

# Expand indirections
_expv = $(subst :$1$(if $(findstring *,$(subst :$1*,,:$2)),*),,:$2)
# _expandMap: $1=CLASS, $2=CLASS*VAR
_expandMap = $(foreach o,$(call _expand,$(_expv)),$1[$o])
_expand = $(foreach w,$1,$(or $(filter %],$w),$(if $(findstring *,$w),$(if $(filter *%,$w),$(call _expand,$($(w:*%=%))),$(call _expandMap,$(word 1,$(subst *, ,$w)),$w)),$w)))

# Inspect targets/goals
_isInstance = $(filter %],$1)
_isIndirect = $(findstring *,$(word 1,$(subst [,[ ,$1)))
_aliasVar = $(or $(call _isDefined,make_$1),$(call _isDefined,MAKE_$1))

# Translate goal $1 to a instance if a rule needs to be generated.
_goalID = $(if $(or $(_isInstance),$(_isIndirect),$(_aliasVar)),$(if $(filter M%,$(_aliasVar)),C)Alias[$1])

# Get all instances in $1 and in their `needs`, transitively.
# $1 = list of IDs  $2 = seen IDs
_rollup = $(if $1,$(call _rollup,$(filter-out $1 $2,$(sort $(call get,needs,$(_isInstance)))),$2 $1),$(filter %],$2))

# Report an error (called by object system)
_error = $(error $1)

# Generated by prototype.scm:

# object system

_set = $(eval $1 := $(and $$(or )1,$(subst \#,$$(\H),$(subst $(\n),$$(\n),$(subst $$,$$$$,$2)))))$2
_once = $(if $(filter-out u%,$(flavor _|$1)),$(_|$1),$(call _set,_|$1,$($1)))
_getE1 = $(call _error,Reference to undefined property '$(word 2,$(subst .,. ,$1))' for $C[$A]$(if $(filter u%,$(flavor $C.inherit)),;$(\n)$Cis not a valid class name ($C.inherit is not defined),$(if $4,$(foreach w,$(patsubst &%,%,$(patsubst ^%,%,$4)),$(if $(filter ^&%,$4), from {inherit} in,$(if $(filter ^%,$4), from {$(word 2,$(subst .,. ,$1))} in,during evaluation of)):$(\n)$w = $(value $w))))$(\n))
_chain = $1 $(foreach w,$($1.inherit),$(call _chain,$w))
_& = $(filter %,$(foreach w,$(or $(&|$C),$(call _set,&|$C,$(call _chain,$C))),$(if $(filter u%,$(flavor $w.$1)),,$w.$1)))
_cp = $(or $(foreach w,$(word 1,$2),$(eval $1 = $$(or )$(subst \#,$$(\H),$(subst $(\n),$$(\n),$(if $(filter r%,$(flavor $w)),$(subst },$(if ,,,^$w$]),$(subst {,$(if ,,$$$[call .,),$(if $(findstring {inherit},$(value $w)),$(subst {inherit},$$(call $(if $(value $3),$3,$(call _cp,$3,$(wordlist 2,99999999,$2),_$3,^$1))),$(value $w)),$(value $w)))),$(subst $$,$$$$,$(value $w))))))$1),$(_getE1),$1)
_! = $(call $(if $(filter u%,$(flavor $C[$A].$1)),$(if $(value &$C.$1),&$C.$1,$(call _cp,&$C.$1,$(_&),_&$C.$1,$2)),$(call _cp,&$C[$A].$1,$C[$A].$1 $(_&),&$C.$1,$2)))
. = $(if $(filter s%,$(flavor ~$C[$A].$1)),$(~$C[$A].$1),$(call _set,~$C[$A].$1,$(call _!,$1,$2)))
_getE0 = $(call _error,Mal-formed instance name '$A'; $(if $(subst [,,$(filter %[,$(word 1,$(subst [,[ ,$A)))),empty ARG,$(if $(filter [%,$A),empty CLASS,missing '[')) in CLASS[ARG])
get = $(foreach A,$2,$(if $(filter %],$A),$(foreach C,$(or $(subst [,,$(filter %[,$(word 1,$(subst [,[ ,$A)))),$(_getE0)),$(foreach A,$(or $(subst &$C[,,&$(patsubst %],%,$A)),$(_getE0)),$(call .,$1))),$(foreach C,File,$(or $(File.$1),$(call .,$1)))))

# misc

_ivar = $(lastword $(subst *, ,$1))
_pairIDs = $(filter-out $$%,$(subst $$, $$,$1))
_pairFiles = $(filter-out %$$,$(subst $$,$$ ,$1))
_inferPairs = $(if $2,$(foreach w,$1,$(or $(foreach x,$(word 1,$(filter %],$(patsubst %$(or $(suffix $(call _pairFiles,$w)),.),%[$(call _pairIDs,$w)],$2))),$x$$$(call get,out,$x)),$w)),$1)

# argument parsing

_argGroup = $(if $(findstring :[,$(subst ],[,$1)),$(if $(findstring $1,$2),$(_argError),$(call _argGroup,$(subst $(\s),,$(foreach w,$(subst $(\s) :],]: ,$(patsubst :[%,:[% ,$(subst :], :],$(subst :[, :[,$1)))),$(if $(filter %:,$w),$(subst :,,$w),$w))),$1)),$1)
_argHash2 = $(subst :,,$(foreach w,$(subst :$;, ,$(call _argGroup,$(subst =,:=,$(subst $;,:$;,$(subst ],:],$(subst [,:[,$1)))))),$(if $(findstring :=,$w),,=)$w))
_argHash = $(if $(or $(findstring [,$1),$(findstring ],$1),$(findstring =,$1)),$(_argHash2),=$(subst $;, =,$1))
_hashGet = $(patsubst $2=%,%,$(filter $2=%,$1))

# output file defaults

_fsenc = $(subst *,@_,$(subst <,@l,$(subst /,@D,$(subst ~,@T,$(subst !,@B,$(subst =,@E,$(subst ],@-,$(subst [,@+,$(subst |,@1,$(subst @,@0,$1))))))))))
_outBX = $(subst @D,/,$(subst $(\s),,$(patsubst /%@_,_%@,$(addprefix /,$(subst @_,@_ ,$(_fsenc))))))
_outBS = $(_fsenc)$(if $(findstring %,$3),,$(suffix $4))$(if $4,$(patsubst _/$(OUTDIR)%,_%,$(if $(filter %],$2),_)$(subst //,/_root_/,$(subst //,/,$(subst /../,/_../,$(subst /./,/_./,$(subst /_,/__,$(subst /,//,/$4))))))),$(call _outBX,$2))
_outBasis = $(if $(filter $5,$2),$(_outBS),$(call _outBS,$1$(subst _$(or $5,|),_|,_$2),$(or $5,out),$3,$4))


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
aliases defined by your Makefile.

endef

_fmtList = $(if $(word 1,$1),$(subst $(\s),$(\n)   , $(strip $1)),(none))

_getID.P = $(foreach p,$(or $(lastword $(subst ].,] ,$1)),$(error Empty property name)),$(call get,$p,$(patsubst %].$p,%],$1)))

_isProp = $(filter ].%,$(lastword $(subst ], ],$1)))

# instance, indirection, alias, other
_goalType = $(if $(_isInstance),Instance,$(if $(_isIndirect),Indirect,$(if $(_aliasVar),Alias,$(if $(_isProp),Property,Other))))

_helpDeps = Direct dependencies: $(call _fmtList,$(call get,needs,$1))$(\n)$(\n)Indirect dependencies: $(call _fmtList,$(call filter-out,$(call get,needs,$1),$(call _rollup,$(call get,needs,$1))))


define _helpInstance
Target ID "$1" is an instance (a generated artifact).

Output: $(call get,out,$1)

Rule: $(call _qv,$(call get,rule,$1))

$(_helpDeps)
endef


define _helpIndirect
"$1" is an indirection on the following variable:

   $(_ivar) = $(value $(_ivar))

It expands to the following targets: $(call _fmtList,$(call _expand,$1))
endef


define _helpAlias
Target "$1" is an alias defined by:

   $(_aliasVar) = $(value $(_aliasVar))

$(call _helpDeps,Alias[$1])

Alias[$1] generates the following rule: $(call _qv,$(call get,rule,Alias[$1]))
endef


_helpProperty = $1 = $(call _qv,$(call _getID.P,$1))


define _helpOther
Target "$1" is not generated by Minion.  It may be a source
file or a target defined by a rule in the Makefile.
endef


# $1 = command line goals other than "help"
_help! = \
  $(if $1,,$(info $(_helpMessage)))\
  $(foreach g,$1,\
    $(info $(call _help$(call _goalType,$g),$g)))


#--------------------------------
# Rules
#--------------------------------

# This will be the default target when `$(end)` is omitted (and
# no goal is named on the command line)
_error_default: ; $(error Makefile included minion-start.mk but did not call `$$(end)`)

# Using "$*" in the following pattern rule we can capture the entirety of
# the goal, including embedded spaces.
$$%: ; @$(info $$$* = $(call _qv,$(call or,$$$*)))

_OUTDIR_safe? = $(filter-out . ..,$(subst /, ,$(OUTDIR)))

.PHONY: clean
clean: ; $(if $(_OUTDIR_safe?),rm -rf $(OUTDIR),@echo '** make clean is disabled; OUTDIR is unsafe: "$(OUTDIR)"' ; false)

end = $(eval $(value _epilogue))

define _epilogue
  # Check OUTDIR
  ifneq "/" "$(patsubst %/,/,$(OUTDIR))"
    $(error OUTDIR must end in "/")
  endif

  ifndef MAKECMDGOALS
    # .DEFAULT_GOAL only matters when there are no command line goals
    .DEFAULT_GOAL = default
    _goalIDs := $(call _goalID,default)
  else ifneq "" "$(filter $$%,$(MAKECMDGOALS))"
    # ignore when a '$(...)' target is given
  else ifneq "" "$(filter help,$(MAKECMDGOALS))"
    # When `help` is given on the command line, we treat all other goals as
    # things to describe, not build.  We display help messages right now and
    # emit "null" rules for the goals.
    $(call _help!,$(subst :,=,$(filter-out help,$(MAKECMDGOALS))))
    _goalIDs := $(MAKECMDGOALS:%=NullAlias[%])
  else
    _goalIDs := $(foreach g,$(MAKECMDGOALS),$(call _goalID,$g))
  endif

  _allIDs := $(filter %],$(call _rollup,$(_goalIDs)))
  $(call _log,all,$(_allIDs))
  $(foreach g,$(_allIDs),$(call _eval,eval-$g,$(call get,rule,$g)))
endef


ifndef minion_start
  $(end)
endif
