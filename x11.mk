# Set minion_x11='FN ...' to slow down functions by a factor of 11.
#
#   minion_start=1
#   include minion.mk
#   include x11.mk
#   $(minion_end)
#
_x11 = $(if $(foreach x,1 2 3 4 5 6 7 8 9 0,$(if $($0_),)),)$($0_)
_x101 = $(if $(foreach x,1 2 3 4 5 6 7 8 9 0,\
           $(foreach y,1 2 3 4 5 6 7 8 9 0,\
              $(if $($0_),))),)$($0_)

$(foreach x,_x11 _x101,\
  $(foreach f,$(minion$x),\
    $(eval $f_ = $(value $f))\
    $(eval $f = $$($x))\
    $(info $f_ = $(value $f_))))


