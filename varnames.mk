# Test of Make's handling of variable names.
#
#  In Make 3.81:
#     NAME           $(call $V)   $($V)    $(NAME)
#     ------------   ----------   ------   -------
#     x()               FAIL        ok      FAIL
#     x)                FAIL        ok      FAIL
#     x(                 ok         ok       ok  [1]
#     x:y=z             FAIL       FAIL     FAIL [2]
#     x=y:z              ok         ok       ok
#
# [1] `$(x()` can *only* work when it does not appear within another
#     parenthesized expression, because it is unbalanced.  Oddly, it *will*
#     work when on the RHS of an assignment.
#
# [2] Of course `$(x:y=z)` fails, since it matches Make's syntax for
#     expanding a variable with substitution.  Oddly, this also disrupts the
#     functioning of `$($V)` and `$(call $V)`.
#
# In Make v3.81, `x y = 1` assigns a variable named `x y`.
# In Make v3.82, `x$(if ,, )y = 1` assigns a variable named `x y`, but...
#    `x y = 1` => error: missing separator
#    `x y := 1` => error: empty variable name
#    `x$(if ,,:) y = 1` => error: multiple target patterns
#

eq = $(if $(findstring -$1,$(findstring -$2,-$1)),1)

try = $(eval o=X)$(eval o = $1)$1 $(if $(call eq,$o,value), ok ,FAIL)  #

test = \
  $(eval $$V = value)\
  $(if $(findstring $(or ) $V$ , $(.VARIABLES) ),\
    $(info $(call try,$$(value $$V))\
           $(call try,$$(call $$V))\
           $(call try,$$($$V))\
           $(call try,$$($V))),\
    $(info Failed to define '$V'!))\
  $(eval $$V = X)


V = x y
$(test)

V = x()
$(test)

V = x)
$(test)

V = x(
$(test)

V = x:y
$(test)

V = x:y=z
$(test)

V = x=y:z
$(test)

V = x{}[]<>"'`"
$(test)

V = ~!@%^&*\|/?;,
$(test)


all:
	@ true

