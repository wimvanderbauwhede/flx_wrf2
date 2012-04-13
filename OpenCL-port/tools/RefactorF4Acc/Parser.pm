package RefactorF4Acc::Parser;

use RefactorF4Acc::Config;
use RefactorF4Acc::Utils;
use RefactorF4Acc::CallGraph qw ( add_to_call_tree );
# 
#   (c) 2010-2012 Wim Vanderbauwhede <wim@dcs.gla.ac.uk>
#   

use vars qw( $VERSION );
$VERSION = "1.0.0";

use warnings::unused;
use warnings;
use warnings FATAL => qw(uninitialized);
use strict;
use Carp;
use Data::Dumper;

use Exporter;

@RefactorF4Acc::Parser::ISA = qw(Exporter);

@RefactorF4Acc::Parser::EXPORT_OK = qw(
    &parse_fortran_src
);

# -----------------------------------------------------------------------------
# parse_fortran_src() only parses the source to build the call tree, nothing else
# We don't need to parse the includes nor the functions at this stage.
# All that should happen in a separate pass. But we do it here anyway
sub parse_fortran_src {
    ( my $f, my $stref ) = @_;

    #    print "PARSING $f\n ";
    # 1. Read the source and do some minimal processsing
    $stref = read_fortran_src( $f, $stref );
    my $sub_or_func = sub_func_or_incl( $f, $stref );
    my $Sf          = $stref->{$sub_or_func}{$f};
    my $is_incl     = exists $stref->{'IncludeFiles'}{$f} ? 1 : 0;
#    my $is_func     = exists $stref->{'Functions'}{$f} ? 1 : 0;
    
    # Set 'RefactorGlobals' to 0, we only refactor the globals for subs that are kernel targets and their dependencies
    if (not exists $Sf->{'RefactorGlobals'} ){ 
        $Sf->{'RefactorGlobals'} = 0;
    }
# 2. Parse the type declarations in the source, create a per-target table Vars and a per-line VarDecl list
# We don't do this in functions at the moment, because we don't need to? NO! FIXME!
#    if ( not $is_func ) {
#    	die if $f eq 'cgszll';
        $stref = get_var_decls( $f, $stref );
#    }
            # 3. Parse includes
    $stref = parse_includes( $f, $stref );
    if ( not $is_incl ) {

        #       my $sub_or_func = sub_func_or_incl( $f, $stref );
#       my $is_sub = ( $sub_or_func eq 'Subroutines' ) ? 1 : 0;

# For subroutines, we detect blocks, parse include and parse nested subroutine calls.
        $stref = detect_blocks($stref,$f);
# Note that function calls have been dealt with (as a side effect) in get_var_decls()
#        if ($is_sub) {
# Detect the presence of a block in this target, only sets 'HasBlocks'
# Detect include statements and add to Subroutine 'Include' field       

        if ( $stref->{$sub_or_func}{$f}{'HasBlocks'} == 1 ) {
            $stref = separate_blocks( $f, $stref );
        }

        # Recursive descent via subroutine calls
        $stref = parse_subroutine_and_function_calls( $f, $stref );
        $stref->{$sub_or_func}{$f}{'Status'} = $PARSED;
    } else {    # includes
                
# 4. For includes, parse common blocks and parameters, create $stref->{'Commons'}
        $stref = get_commons_params_from_includes( $f, $stref );
        $stref->{'IncludeFiles'}{$f}{'Status'} = $PARSED;
    }
    
    $stref=create_annotated_lines($stref,$f);    
    return $stref;
}    # END of parse_fortran_src()

# -----------------------------------------------------------------------------

sub create_annotated_lines {
	(my $stref,my $f)=@_;	
	my $sub_or_func_or_inc = sub_func_or_incl( $f, $stref );
	my $Sf = $stref->{$sub_or_func_or_inc}{$f};
    # Merge source lines and tags into annotated lines @{$annlines}
    my @lines = @{ $Sf->{'Lines'} };
    my @info = defined $Sf->{'Info'} ? @{ $Sf->{'Info'} } : ();
    my $annlines = [];
    for my $line (@lines) {
        my $tags = shift @info;
        if (not defined $tags) {
        	$tags={};
        }
        push @{$annlines}, [ $line, $tags ];
    }
	$Sf->{'AnnLines'}=$annlines;
	return $stref;
}
# Create a table of all variables declared in the target, and a list of all the var names occuring on each line.
# We record the type of the var and whether it's a scalar or array, because we need that information for translation to C.
# Also check if the variable happens to be a function. If that is the case, mark that function as 'Called'; if we have not yet parsed its source, do it now.

sub get_var_decls {
    ( my $f, my $stref ) = @_;

#   my $is_incl = exists $stref->{'IncludeFiles'}{$f} ? 1 : 0;

    #           my $sub_or_incl = $is_incl ? 'Includes' : 'Subroutines';
    my $sub_func_incl = sub_func_or_incl( $f, $stref );
    my $srcref = $stref->{$sub_func_incl}{$f}{'Lines'};
    if ( defined $srcref ) {
        print "\nVAR DECLS in $f:\n" if $V;
        my %vars  = ();
        my $first = 1;
        for my $index ( 0 .. scalar( @{$srcref} ) - 1 ) {
            my $line = $srcref->[$index];

            if ( $line =~ /^C\s+/ ) {
                next;
            }
            if ( $line =~ /^\!\s/ ) {
                $stref->{$sub_func_incl}{$f}{'Info'}
                  ->[$index]{'TrailingComments'} = {};
                next;
            }
            if ( $line =~ /implicit\s+none/ ) {

                #               print "INFO: $f has 'implicit none'\n";
                $stref->{$sub_func_incl}{$f}{'Info'}->[$index]{'ImplicitNone'} =
                  {};
                $stref->{$sub_func_incl}{$f}{'ImplicitNone'} = $index;
            }
            if ( $line =~
/(logical|integer|real|double\s*precision|character|character\*?(?:\d+|\(\*\)))\s+(.+)\s*$/
              )
            {
                my $type    = $1;
                my $varlst  = $2;
                my $tvarlst = $varlst;

                if ( $tvarlst =~ /\(((?:[^\(\),]*?,)+[^\(]*?)\)/ ) {
                    while ( $tvarlst =~ /\(((?:[^\(\),]*?,)+[^\(]*?)\)/ ) {
                        my $chunk  = $1;
                        my $chunkr = $chunk;
                        $chunkr =~ s/,/;/g;
                        my $pos = index( $tvarlst, $chunk );
                        substr( $tvarlst, $pos, length($chunk), $chunkr );
                    }
                }

                my @tvars    = split( /\s*\,\s*/, $tvarlst );
                my $p        = '';
                my @varnames = ();
                for my $var (@tvars) {
                    $var =~ s/^\s+//;
                    $var =~ s/\s+$//;
                    my $tvar     = $var;
                    my $shapestr = '';
                    $tvar =~ /\((.*?)\)/ && do {
                        $shapestr = $1;
                        $tvar =~ s/\(.*?\)/(0)/g;    # get rid of array shape
                    };
                    my @shape = ();
                    if ( $shapestr ne '' ) {
                        if ( $shapestr =~ /;/ ) {
                            my @elts = split( /;/, $shapestr );
                            for my $elt (@elts) {
                                my @tup = ();
                                if ( $elt =~ /:/ ) {
                                    @tup = split( /:/, $shapestr );
                                } else {
                                    @tup = ( 1, $elt );
                                }
                                @shape = ( @shape, @tup );
                            }
                        } else {
                            if ( $shapestr =~ /:/ ) {
                                @shape = split( /;/, $shapestr );
                            } else {
                                @shape = ( 1, $shapestr );
                            }
                        }
                    }

                    if ( $tvar =~ /\(.*?\)/ && $tvar !~ /\(0\)/ ) {
                        die "FATAL ERROR: $tvar shouln't look like this!";
                    }

                    if ( $tvar =~ s/\(0\)// ) {    # remove (0) placeholder

#                       $tvar =~ s/\*\d+//;
                         # FIXME: char string handling is not correct!
                         # remove *number from the type, this is wrong. The right thing is to replace
                         # this notation with type(number)
                         # Also, this is not limited to arrays, we could have e.g. integer v*4
                         if ($tvar =~ /\*(\d+)/) {                          
                            $type="$type($1)";
                            $tvar =~ s/\*\d+//;
                         }
                        $vars{$tvar}{'Kind'}  = 'Array';
                        $vars{$tvar}{'Shape'} = [@shape];
                        $p                    = '()';
                    } else {
                        $vars{$tvar}{'Kind'}  = 'Scalar';
                        $vars{$tvar}{'Shape'} = [];
                    }
                    $vars{$tvar}{'Type'} = $type;
                    $var =~ s/;/,/g;
                    $vars{$tvar}{'Decl'} = "        $type $var"
                      ; # TODO: this should maybe not be a textual representation
                        # make it [$type,$var] ?
                    if ( exists $stref->{'Functions'}{$tvar} ) {
                    	
                        $stref->{'Functions'}{$tvar}{'Called'} = 1;
                        $stref->{'Functions'}{$tvar}{'Callers'}{$f}++;
                        if ( not exists $stref->{'Functions'}{$tvar}{'Lines'} )
                        {
                            $stref = parse_fortran_src( $tvar, $stref );
#                            die Dumper($stref->{'Functions'}{$tvar}) if $tvar eq 'cgszll';    
                        } 
                    }
                    push @varnames, $tvar;
                }
                print "\t", join( ',', @varnames ), "\n" if $V;
                $stref->{$sub_func_incl}{$f}{'Info'}->[$index]{'VarDecl'} =
                  \@varnames;
                if ($first) {
                    $first = 0;
                    $stref->{$sub_func_incl}{$f}{'Info'}
                      ->[$index]{'ExGlobVarDecls'} = {};
                }
            }
        }
        $stref->{$sub_func_incl}{$f}{'Vars'} = \%vars;
    }

    #           die "FIXME: shapes not correct!";
    return $stref;
}    # END of get_var_decls()
# -----------------------------------------------------------------------------
# For every 'include' statement in a subroutine 
# the filename is entered in 'Includes' and in Info->[$index]{'Include'}
# If the include was not yet read, do it now.
sub parse_includes {
    ( my $f, my $stref ) = @_;
    print "PARSING INCLUDES for $f\n" if $V;
    my $sub_or_func_or_inc = sub_func_or_incl( $f, $stref );
    my $Sf=$stref->{$sub_or_func_or_inc}{$f};
    my $srcref = $Sf->{'Lines'};
    for my $index ( 0 .. scalar( @{$srcref} ) - 1 ) {
        my $line = $srcref->[$index];
        if ( $line =~ /^C\s+/ or $line =~ /^\!\s/ ) {
            next;
        }

        if ( $line =~ /^\s*include\s+\'(\w+)\'/ ) {
            my $name = $1;
            print "FOUND include $name in $f\n" if $V;
            $Sf->{'Includes'}{$name} = $index;
            $Sf->{'Info'}->[$index]{'Include'}{'Name'} = $name;
            if ( $stref->{'IncludeFiles'}{$name}{'Status'} == $UNREAD ) {
                print $line, "\n" if $V;
                # Initial guess for Root. OK? FIXME?
                $stref->{'IncludeFiles'}{$name}{'Root'}      = $f;
                $stref->{'IncludeFiles'}{$name}{'HasBlocks'} = 0;
                $stref = parse_fortran_src( $name, $stref );
            } else {
                print $line, " already processed\n" if $V;
            }
        }
    }

    return $stref;
}    # END of parse_includes()
# -----------------------------------------------------------------------------

sub detect_blocks {
    ( my $stref, my $s ) = @_;
    print "CHECKING BLOCKS in $s\n" if $V;
    my $sub_func_incl = sub_func_or_incl( $s, $stref );
    $stref->{$sub_func_incl}{$s}{'HasBlocks'} = 0;
    my $srcref = $stref->{$sub_func_incl}{$s}{'Lines'};
    for my $line ( @{$srcref} ) {       
        if ( $line =~ /^C\s/i ) {

# I'd like to use the OpenACC compliant pragma !$acc kernels , !$acc end kernels
# but OpenACC does not allow to provide a name
# so I propose my own tag: !$acc subroutine name, !$acc end subroutine
            if (   $line =~ /^C\s+BEGIN\sSUBROUTINE\s(\w+)/
                or $line =~ /^C\s\$acc\ssubroutine\s(\w+)/i )
            {
                $stref->{$sub_func_incl}{$s}{'HasBlocks'} = 1;
                my $tgt = uc( substr( $sub_func_incl, 0, 3 ) );
                print "$tgt $s HAS BLOCK: $1\n" if $V;
                last;
            }
        }
    }
    
    return $stref;
}    # END of detect_blocks()
# -----------------------------------------------------------------------------
=pod

=begin markdown

### Factoring out code blocks into subroutines



=end markdown

=cut


sub separate_blocks {
    ( my $f, my $stref ) = @_;

#    die "separate_blocks(): FIXME: we need to add in the locals from the parent subroutine as locals in the new subroutine!";
    my $sub_or_func = sub_func_or_incl( $f, $stref );
    my $Sf          = $stref->{$sub_or_func}{$f};
    my $srcref      = $Sf->{'Lines'};
    # All local variables in the parent subroutine
    my %vars        = %{ $Sf->{'Vars'} };
    # Occurence
    my %occs        = ();
    # A map of every block in the parent
    my %blocks      = (); 
    my $in_block    = 0;
    # Initial settings
    my $block       = 'OUTER';
    $blocks{'OUTER'} = { 'Lines' => [] };
#   my $block_idx = 0;
    
    # 1. Process every line in $f, scan for blocks marked with pragmas.
    # What this does is to separate the code into blocks (%blocks) and keep track of the line numbers
    # The lines with the pragmas occur both in OUTER and the block
     
#TODO: replace by sub
#    (my $stref, my $blocksref) = separate_into_blocks($stref,$f);
    
    for my $index ( 0 .. scalar( @{$srcref} ) - 1 ) {
        my $line = $srcref->[$index];
        if (   $line =~ /^C\s+BEGIN\sSUBROUTINE\s(\w+)/
            or $line =~ /^C\s\$acc\s+subroutine\s(\w+)/i )
        {
            $in_block = 1;
            $block    = $1;
            print "FOUND BLOCK $block\n" if $V;
            # Enter the name of the block in the metadata for the line
            $Sf->{'Info'}[$index]{'RefactoredSubroutineCall'}{'Name'} = $block;
            $Sf->{'Info'}[$index]{'SubroutineCall'}{'Name'} = $block;
            delete $Sf->{'Info'}[$index]{'Comments'};
            $Sf->{'Info'}[$index]{'BeginBlock'}{'Name'} = $block;
            # Push the line with the pragma onto the list of 'OUTER' lines
            push @{ $blocks{'OUTER'}{'Lines'} }, "C *** Refactored code into $block ***";
            # Push the line with the pragma onto the list of lines for the block,
            # to be replaced by function signature
            push @{ $blocks{$block}{'Lines'} }, "C *** Original code from $f starts here ***";
            # Add the name and index to %blocks  
            push @{ $blocks{$block}{'Info'} },
              { 'RefactoredSubroutineCall' => { 'Name' => $block } };
            $blocks{$block}{'BeginBlockIdx'} = $index;
            next;
        }
        if (   $line =~ /^C\s+END\sSUBROUTINE\s(\w+)/
            or $line =~ /^C\s\$acc\s+end\ssubroutine\s(\w+)/i )
        {
            $in_block = 0;
            $block    = $1;
            # Push end-of-block pragma onto 'OUTER'
            push @{ $blocks{'OUTER'}{'Lines'} }, $line;
            # Push 'end' onto the list of lines for the block,
            push @{ $blocks{$block}{'Lines'} }, '      end';
            # Add info to %blocks. 
            push @{ $blocks{$block}{'Info'} }, $Sf->{'Info'}[$index];
            $Sf->{'Info'}[$index]{'EndBlock'}{'Name'} = $block;
            $blocks{$block}{'EndBlockIdx'} = $index; 
            next;
        }
        if ($in_block) {
            # Push the line onto the list of lines for the block
            push @{ $blocks{$block}{'Lines'} }, $line;
            # and the index onto Info in %blocks and $Sf
            push @{ $blocks{$block}{'Info'} }, $Sf->{'Info'}->[$index];         
            $Sf->{'Info'}[$index]{'InBlock'}{'Name'} = $block;
        } else {
            # Other lines go onto 'OUTER'
            push @{ $blocks{'OUTER'}{'Lines'} }, $line;
        }
    }

    # 2. For all non-OUTER blocks, create an entry for the new subroutine in 'Subroutines'
    # Based on the content of %blocks
    # TODO: $stref=create_new_subroutine_entries($blocksref,$stref)
    for my $block ( keys %blocks ) {
        next if $block eq 'OUTER';
        $stref->{'Subroutines'}{$block}={};
        my $Sblock=$stref->{'Subroutines'}{$block};
        $Sblock->{'Lines'} = $blocks{$block}{'Lines'};
        $Sblock->{'Info'}  = $blocks{$block}{'Info'};
        $Sblock->{'Source'} = $Sf->{'Source'};      
        $Sblock->{'RefactorGlobals'} = 1;
        if ($Sf->{'RefactorGlobals'} == 0) {
          $Sf->{'RefactorGlobals'} = 2;
        } else {
            die 'BOOM!';
        }
    }

    # 3. Identify which vars are used
    #   - in both => these become function arguments
    #   - only in "outer" => do nothing for those
    #   - only in "inner" => can be removed from outer variable declarations
    #
    # Find all vars used in each block, starting with the outer block
    # It is best to loop over all vars per line per block, because we can remove the encountered vars
    # TODO: my $occsref = determine_new_subroutine_arguments($blocksref,$varsref,$linesref);
    for my $block ( keys %blocks ) {
        my @lines = @{ $blocks{$block}{'Lines'} };
        my %tvars = %vars; # Hurray for pass-by-value!
        print "\nVARS in $block:\n\n" if $V;
        for my $line (@lines) {
            my $tline = $line;
            $tline =~ s/\'.+?\'//;
            for my $var ( sort keys %tvars ) {
                if ( $tline =~ /\W$var\W/ or $tline =~ /\W$var\s*$/ ) {
                    print "FOUND $var\n" if $V;
                    $occs{$block}{$var} = $var;
                    delete $tvars{$var};
                }
            }
        }
    }

    # 4. Construct the subroutine signatures
    # TODO: $stref = construct_new_subroutine_signatures();
    # TODO: see if this can be separated into shorter subs
    my %args = ();
    for my $block ( keys %blocks ) {
        next if $block eq 'OUTER';      
        my $Sblock=$stref->{'Subroutines'}{$block};
        print "\nARGS for BLOCK $block:\n" if $V;
        # Collect args for new subroutine
        for my $var ( sort keys %{ $occs{$block} } ) {
            if ( exists $occs{'OUTER'}{$var} ) {
                print "$var\n" if $V;
                push @{ $args{$block} }, $var;
            }
        }
        $Sblock->{'Args'} = $args{$block};
        # Create Signature and corresponding Decls
        my $sig   = "      subroutine $block(";
        my $decls = [];
        for my $argv ( @{ $args{$block} } ) {
            $sig .= "$argv,";
            my $decl = $vars{$argv}{'Decl'};
            push @{$decls}, $decl;
        }
        $sig =~ s/\,$/)/s;
        $Sblock->{'Sig'}   = $sig;
        $Sblock->{'Decls'} = $decls;        
        # Add variable declarations and info to line 
        my $siginfo = shift @{ $Sblock->{'Info'} };
        for my $argv ( @{ $args{$block} } ) {
            my $decl = $vars{$argv}{'Decl'};
            unshift @{ $Sblock->{'Lines'} }, $decl;
            unshift @{ $Sblock->{'Info'} }, { 'VarDecl' => [$argv] };
        }
        unshift @{ $Sblock->{'Info'} }, $siginfo;
        
        # Now also add include statements and the actual sig to the line
        my $fl = shift @{ $Sblock->{'Info'} };
        for my $inc ( keys %{ $Sf->{'Includes'} } ) {
            $Sblock->{'Includes'}{$inc} = 1;
            unshift @{ $Sblock->{'Lines'} }, "      include '$inc'";
            unshift @{ $Sblock->{'Info'} }, { 'Include' => { 'Name' => $inc } };
            $Sblock->{'Includes'}{$inc} = 1;
        }
        unshift @{ $Sblock->{'Lines'} }, $sig;
        # And finally, in the original source, replace the blocks by calls to the new subs
#        print "\n-----\n".Dumper($srcref)."\n-----";
        for my $tindex ( 0 .. scalar( @{$srcref} ) - 1 ) {
#           print $f,':',$tindex,"\n",$srcref->[$tindex],"\n";          
            if ( $tindex == $blocks{$block}{'BeginBlockIdx'} ) {
                $sig =~ s/subroutine/call/;
                $srcref->[$tindex] = $sig;
            } elsif ( $tindex > $blocks{$block}{'BeginBlockIdx'}
                and $tindex <= $blocks{$block}{'EndBlockIdx'} )
            {
                $srcref->[$tindex] = '';
            }
        }
        unshift @{ $Sblock->{'Info'} }, $fl;
        
        if ($V) {
            print $sig, "\n";
            print join( "\n", @{$decls} ), "\n";
        }
        $Sblock->{'Status'} = $READ;
    }
    return $stref;
}    # END of separate_blocks()

# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------

sub parse_subroutine_and_function_calls {
    ( my $f, my $stref ) = @_;
    print "PARSING SUBROUTINE/FUNCTION CALLS in $f\n" if $V;
    my $pnid        = $stref->{'NId'};
    my $sub_or_func = sub_func_or_incl( $f, $stref );
    my $Sf          = $stref->{$sub_or_func}{$f};

    # For C translation and call tree generation
    if ( $translate == $GO
        || ( $call_tree_only && ( $gen_sub || $main_tree ) ) )
    {
        if ( $translate != $GO ) {
            print "ADDING $f to CALL TREE\n" if $V;
            $stref = add_to_call_tree( $f, $stref );
        }    # else {
        if ( $translate == $GO ) {
            $stref = add_to_C_build_sources( $f, $stref );
        }
    }
    my $srcref = $Sf->{'Lines'};
#   croak Dumper( $srcref) if $f=~/timemanager/;
    if ( defined $srcref ) {

        #        my %called_subs         = ();
        for my $index ( 0 .. scalar( @{$srcref} ) - 1 ) {
            my $line = $srcref->[$index];
            next if $line =~ /^C\s+/;

      # Subroutine calls. Surprisingly, these even occur in functions! *shudder*
            if ( $line =~ /call\s(\w+)\((.*)\)/ || $line =~ /call\s(\w+)\s*$/ )
            {
                
                my $name  = $1;
                
                my $Sname = $stref->{'Subroutines'}{$name};
                
                $stref->{'NId'}++;
                my $nid = $stref->{'NId'};
                push @{ $stref->{'Nodes'}{$pnid}{'Children'} }, $nid;
                $stref->{'Nodes'}{$nid} = {
                    'Parent'     => $pnid,
                    'Children'   => [],
                    'Subroutine' => $name
                };

                my $argstr = $2 || '';
                if ( $argstr =~ /^\s*$/ ) {
                    $argstr = '';
                }

                $Sname->{'Called'} = 1;
                $Sname->{'Callers'}{$f}++;
#               if ($Sf->{'RefactorGlobals'} == 2) {
#               warn "NAME: $f => $name,".(exists $Sname->{'RefactorGlobals'}? $Sname->{'RefactorGlobals'} : 'UNDEF')."\n" if $f eq 'timemanager';
#               }
                if ($Sf->{'RefactorGlobals'}==1) {
                    print "SUB $name NEEDS GLOBALS REFACTORING\n" if $V;
                    $Sname->{'RefactorGlobals'} = 1;                    
                }

                #                $called_subs{$name} = $name;
                $Sf->{'Info'}->[$index]{'SubroutineCall'}{'Args'} = $argstr;
                my $tvarlst = $argstr;

                # replace , by ; in array indices and nested function calls
                if ( $tvarlst =~ /\(((?:[^\(\),]*?,)+[^\(]*?)\)/ ) {
                    while ( $tvarlst =~ /\(((?:[^\(\),]*?,)+[^\(]*?)\)/ ) {
                        my $chunk  = $1;
                        my $chunkr = $chunk;
                        $chunkr =~ s/,/;/g;
                        my $pos = index( $tvarlst, $chunk );
                        substr( $tvarlst, $pos, length($chunk), $chunkr );
                    }
                }

                my @tvars   = split( /\s*\,\s*/, $tvarlst );
#               my $p       = '';
                my @argvars = ();
                for my $var (@tvars) {
                    $var =~ s/^\s+//;
                    $var =~ s/\s+$//;
                    $var =~ s/;/,/g;
                    push @argvars, $var;
                }

                $Sf->{'Info'}->[$index]{'SubroutineCall'}{'Args'} = \@argvars;
                $Sf->{'Info'}->[$index]{'SubroutineCall'}{'Name'} = $name;

                if ( defined $Sname
                    and not exists $Sf->{'CalledSubs'}{$name} )
                {
                    $Sf->{'CalledSubs'}{$name} = 1;

                    if (   not exists $Sname->{'Status'}
                        or $Sname->{'Status'} < $PARSED
                        or $gen_sub )
                    {
                        die $name
                          if $f eq 'calcpar' && $line =~ /call\s+xyindex_/;
                        print "\tFOUND SUBROUTINE CALL $name in $f\n" if $V;
                        if ( $call_tree_only && ( $gen_sub || $main_tree ) ) {
                            $stref->{'Indents'} += 4;
                        }
                        $stref = parse_fortran_src( $name, $stref );
                        if ( $call_tree_only && ( $gen_sub || $main_tree ) ) {
                            $stref->{'Indents'} -= 4;
                        }
                    } else {
                        $stref->{'Indents'} += 4;
                        $stref = add_to_call_tree( $name, $stref, '*' );
                        $stref->{'Indents'} -= 4;
                    }
                }
            }

            # Maybe Function calls
            if (   $line !~ /function\s/
                && $line !~ /subroutine\s/
                && $line =~ /(\w+)\(/ )
            {
                my @chunks = ();
                my $cline  = $line;
                while ( $cline =~ /(\w+)\(/ ) {
                    if ( $line !~ /call\s+$1/ ) {
                        push @chunks, $1;
                        $cline =~ s/$1\(//;
                    } else {
                        $cline =~ s/call\s+\w+\(//;
                    }
                }
                for my $chunk (@chunks) {
                    if (
                        exists $stref->{'Functions'}{$chunk}

                       # This means it's the first call to function $chunk in $f
                        and not exists $Sf->{'CalledFunctions'}{$chunk}
                      )
                    {
                        $Sf->{'CalledFunctions'}{$chunk} = 1;
                        print "FOUND FUNCTION CALL $chunk in $f\n" if $V;
                        if ( $chunk eq $f ) { die $line }
                        $stref->{'Functions'}{$chunk}{'Called'} = 1;

# We need to parse the function to detect called functions inside it, unless that has been done
                        if (   not exists $stref->{'Functions'}{$chunk}
                            or not
                            exists $stref->{'Functions'}{$chunk}{'Status'}
                            or $stref->{'Functions'}{$chunk}{'Status'} <
                            $PARSED )
                        {
                            $stref->{'Indents'} += 4;
                            $stref = parse_fortran_src( $chunk, $stref );
                            $stref->{'Indents'} -= 4;
                        } else {
                            $stref->{'Indents'} += 4;
                            $stref = add_to_call_tree( $chunk, $stref, '*' );
                            $stref->{'Indents'} -= 4;
                        }
                    }
                }
            }
        }

        #        $Sf->{'CalledSubs'}=\%called_subs;
    }
    return $stref;
}    # END of parse_subroutine_and_function_calls()

# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------

sub get_commons_params_from_includes {
    ( my $f, my $stref ) = @_;
    my $srcref = $stref->{'IncludeFiles'}{$f}{'Lines'};
    if ( defined $srcref ) {

        #       warn "GETTING COMMONS/PARAMS from INCLUDE $f\n";
        my %vars        = %{ $stref->{'IncludeFiles'}{$f}{'Vars'} };
        my $has_pars    = 0;
        my $has_commons = 0;

        for my $index ( 0 .. scalar( @{$srcref} ) - 1 ) {
            my $line = $srcref->[$index];
            if ( $line =~ /^C\s+/ ) {
                next;
            }
            if ( $line =~ /^\s*common\s+\/\s*[\w\d]+\s*\/\s+(.+)$/ ) {
                my $commonlst = $1;
                $has_commons = 1;
                my @tcommons = split( /\s*\,\s*/, $commonlst );
                for my $var (@tcommons) {
                    if ( not defined $vars{$var} ) {
                        print "WARNING: MISSING: <", $var, ">\n" if $W;
                    } else {
                        print $var, "\t", $vars{$var}{'Type'}, "\n"
                          if $V;
                        $stref->{'IncludeFiles'}{$f}{'Commons'}{$var} =
                          $vars{$var};
                    }
                }
                $stref->{'IncludeFiles'}{$f}{'Info'}->[$index]{'Common'} = {};
            }

            if ( $line =~ /parameter\s*\(\s*(.*)\s*\)/ ) {

                my $parliststr = $1;
                $has_pars = 1;
                my @partups = split( /\s*,\s*/, $parliststr );
                my @pvars =
                  map { s/\s*=.+//; $_ } @partups;    # Perl::Critic, EYHO

                for my $var (@pvars) {
                    if ( not defined $vars{$var} ) {
                        print "WARNINGS: NOT A PARAMETER: <", $var, ">\n"
                          if $W;
                    } else {
                        $stref->{'IncludeFiles'}{$f}{'Parameters'}{$var} =
                          $vars{$var};
                    }
                }
                $stref->{'IncludeFiles'}{$f}{'Info'}->[$index]{'Parameter'} =
                  {};
            }
        }

        if ($V) {
            print "\nCOMMONS for $f:\n\n";
            for my $v ( sort keys %{ $stref->{'IncludeFiles'}{$f}{'Commons'} } )
            {
                print $v, "\n";
            }
        }

        # FIXME!
        # An include file should basically only contain parameters and commons.
        # If it contains commons, we should remove them!
        if ( $has_commons && $has_pars ) {
            die
"The include file $f contains both parameters and commons, this is not yet supported.\n";
        } elsif ($has_commons) {
            $stref->{'IncludeFiles'}{$f}{'InclType'} = 'Common';
        } elsif ($has_pars) {
            $stref->{'IncludeFiles'}{$f}{'InclType'} = 'Parameter';
        } else {
            $stref->{'IncludeFiles'}{$f}{'InclType'} = 'None';
        }
        for my $var ( keys %vars ) {
            if (
                (
                    $has_pars
                    and not
                    exists( $stref->{'IncludeFiles'}{$f}{'Parameters'}{$var} )
                )
                or ( $has_commons
                    and not
                    exists( $stref->{'IncludeFiles'}{$f}{'Commons'}{$var} ) )
              )
            {
                warn Dumper( $stref->{'IncludeFiles'}{$f}{'Lines'} );
                croak
"The include $f contains a variable $var that is neither a parameter nor a common variable, this is not supported\n";
            }
        }
    }
    return $stref;
}    # END of get_commons_params_from_includes()
# -----------------------------------------------------------------------------
# This subroutine reads the FORTRAN source and does very little else:
# - it combines continuation lines in a single line
# - it lowercases everything
# - it detects and normalises comments
# - it detects block markers (for factoring blocks out into subs)
# The routine is called by parse_fortran_src()
# A better way is to extract all subs in a single pass
# I guess the best wat is to first join the lines, then separate the subs
sub read_fortran_src {
    ( my $s, my $stref ) = @_;

    my $is_incl = exists $stref->{'IncludeFiles'}{$s} ? 1 : 0;

    my $sub_func_incl = sub_func_or_incl( $s, $stref );
    $stref->{$sub_func_incl}{$s}{'HasBlocks'} = 0;
    my $f = $is_incl ? $s : $stref->{$sub_func_incl}{$s}{'Source'};

    if ( $stref->{$sub_func_incl}{$s}{'Status'} == $UNREAD ) {
        my $ok = 1;
        open my $SRC, '<', $f or do {
            print "WARNING: Can't find '$f' ($s)\n";
            $ok = 0;
        };
        if ($ok) {
            print "READING SOURCE for $f ($sub_func_incl)\n" if $V;
            local $V = 0;
            my $lines    = [];
            my $prevline = '';

            # 0. Slurp the source; standardise the comments
            # 1. Join up the continuation lines
            # TODO: split lines with ;
            # TODO: Special case: comments in continuation lines.
            # For now, I just throw them away.
            my $cont = 0;

            my %strconsts             = ();
            my @phs                   = ();
            my @placeholders_per_line = ();
            my $ct                    = 0;

            my $line = '';
            while (<$SRC>) {
                $line = $_;
                chomp $line;

                # Skip blanks
                $line =~ /^\s*$/ && next;

                # Detect blocks
                if ( $stref->{$sub_func_incl}{$s}{'HasBlocks'} == 0 ) {
                    if ( $line =~ /^C\s+BEGIN\sSUBROUTINE\s(\w+)/ ) {
                        $stref->{$sub_func_incl}{$s}{'HasBlocks'} = 1;
                    }
                }

                # Detect and standardise comments
                if ( $line =~ /^[CD\*\!]/i or $line =~ /^\ {6}\s*\!/i ) {
                    $line =~ s/^\s*[CcDd\*\!]/C /;
                } elsif ( $line =~ /\s+\!.*$/ )
                {    # FIXME: trailing comments are discarded!
                    my $tline = $line;
                    $tline =~ s/\'.+?\'//;
                    if ( $tline =~ /\s+\!.*$/ ) {

                  # convert trailing comments into comments on the previous line
                        $line = ( split( /\s+\!/, $line ) )[0];
                    }
                }

                if ( $line =~ /^\ {5}[^0\s]/ ) {    # continuation line
                    $line =~ s/^\s{5}.\s*/ /;
                    $prevline .= $line;
                    $cont = 1;
                } elsif ( $line =~ /^\&/ ) {
                    $line =~ s/^\&\t*/ /;
                    $prevline .= $line;
                    $cont = 1;
                } elsif ( $line =~ /^\t[1-9]/ ) {
                    $line =~ s/^\t[0-9]/ /;
                    $prevline .= $line;
                    $cont = 1;
                } elsif ( $prevline =~ /\&\s&$/ ) {
                    $prevline =~ s/\&\s&$//;
                    $prevline .= $line;
                    $cont = 1;
                } elsif ( $line =~ /^C\ / && ( $cont == 1 ) ) {

                    # A comment occuring after a continuation line. Skip!
                    next;
                } else {

                    my $sixspaces = ' ' x 6;
                    $prevline =~ s/^\t/$sixspaces/;
                    $prevline =~ /^(\d+)\t/ && do {
                        my $label  = $1;
                        my $ndig   = length($label);
                        my $spaces = ' ' x ( 6 - $ndig );
                        my $str    = $label . $spaces;
                        $prevline =~ s/^(\d+)\t/$str/;
                    };
                    if ( substr( $prevline, 0, 2 ) ne 'C ' ) {
                        if ( $prevline !~ /^\s+include\s+\'/i ) {

                            # replace string constants by placeholders
                            while ( $prevline =~ /(\'.*?\')/ ) {
                                my $strconst = $1;
                                my $ph       = '__PH' . $ct . '__';
                                push @phs, $ph;
                                $strconsts{$ph} = $strconst;
                                $prevline =~ s/\'.*?\'/$ph/;
                                $ct++;
                            }
                        }

     # remove trailing comments
     #                  ( $prevline, my $comment ) = split( /\s+\!/, $prevline );
                    }
                    my $lcprevline =
                      ( substr( $prevline, 0, 2 ) eq 'C ' )
                      ? $prevline
                      : lc($prevline);
                    $lcprevline =~ s/__ph(\d+)__/__PH$1__/g;

                    #                     warn "$lcprevline\n";
                    push @{$lines},
                      $lcprevline;    # unless $lcprevline eq ''; # HACK
                    push @placeholders_per_line, [@phs];
                    @phs      = ();
                    $prevline = $line;
                    $cont     = 0;
                }
            }

            # There can't be strings on the last line (except in a include?)
            # and substr($prevline,-length($line),length($prevline)) ne $line
            if ( $line ne $prevline )
            {    # Too weak, if there are comments in between it breaks!
                my $lcprevline =
                  ( substr( $prevline, 0, 2 ) eq 'C ' )
                  ? $prevline
                  : lc($prevline);
                push @{$lines}, $lcprevline;
            }

            # HACK! FIXME!
            if (    $f =~ /^include/
                and length($line) != length($prevline)
                and substr( $prevline, -length($line), length($prevline) ) eq
                $line )
            {

                # the last line was already appended to the previous line!
            } else {
                my $lcline =
                  ( substr( $line, 0, 2 ) eq 'C ' ) ? $line : lc($line);
                push @{$lines}, $lcline;
            }
            push @placeholders_per_line, [];
            push @placeholders_per_line, [];
            close $SRC;

            #           die if $f =~ /coordtrafo/;
            #           die Dumper($lines) if $f =~ /coordtrafo/;
            my $name = 'NONE';
            my $ok   = 0;
            if ($is_incl) {
                $ok                                    = 1;
                $name                                  = $s;
                $stref->{$sub_func_incl}{$s}{'Status'} = $READ;
            }
            my $index = 0;
            for my $line ( @{$lines} ) {
                my $phs_ref = shift @placeholders_per_line;
                if ( not defined $line ) {
                    $line = 'C UNDEF';
                }

# If it's a subroutine source, skip all lines before the matching subroutine signature
# and all lines from (and including) the next non-matching subroutine signature

       # FIXME: weak, the return type of the function can be more than one word!
                if (   $is_incl == 0
                    && $line =~
                    /^\s+(program|subroutine|(?:\w+\s+)?function)\s+(\w+)/ )
                {
                    my $keyword = $1;
                    $name = $2;
                    if ( $keyword =~ /function/ ) {
                        $sub_func_incl = 'Functions';
                    } else {
                        $sub_func_incl = 'Subroutines';
                    }

                    #                   warn "\t$name\n";
                    $ok                                       = 1;
                    $index                                    = 0;
                    $stref->{$sub_func_incl}{$name}{'Status'} = $READ;

                    #                   $stref->{$sub_func_incl}{$name}{'HasBlocks'}    = 0;
                    $stref->{$sub_func_incl}{$name}{'StringConsts'} =
                      \%strconsts
                      ; # Means we have all consts in the file, not just the sub, but who cares?
                }
                if ( $ok == 1 ) {
                    push @{ $stref->{$sub_func_incl}{$name}{'Lines'} }, $line;
                    if ( $line =~ /^C/ ) {
                        $stref->{$sub_func_incl}{$name}{'Info'}
                          ->[$index]{'Comments'} = {};
                    }
                    $stref->{$sub_func_incl}{$name}{'Info'}->[$index] =
                      { 'PlaceHolders' => $phs_ref }
                      if @{$phs_ref};
                    $index++;
                }

            }
        }    # if OK
    }    # if Status==0

    return $stref;
}    # END of read_fortran_src()

# -----------------------------------------------------------------------------