divert(-1)
undefine(`len')
#
# append an underscore to FORTRAN function names
#
define(`FUNCTION',`$1_')
define(`ARGS',`($1`'undivert(1))')
define(`SAVE',`divert(1)$1`'divert(0)')
define(`STRING_ARG',`$1_ptr`'SAVE(`, $1_len')')
define(`STRING_ARG_DECL',`char * $1_ptr; int $1_len')
define(`STRING_LEN',`$1_len')
define(`STRING_PTR',`$1_ptr')
define(`FortranInt',`int')
define(`FortranReal',`float')
define(`FortranDouble',`double')
define(`FortranByte',`unsigned char')
divert(0)
