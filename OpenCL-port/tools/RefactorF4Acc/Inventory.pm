package RefactorF4Acc::Inventory;

use RefactorF4Acc::Config qw ($V $W $UNREAD);
# 
#   (c) 2010-2012 Wim Vanderbauwhede <wim@dcs.gla.ac.uk>
#   

use vars qw( $VERSION );
$VERSION = "1.0.0";

use warnings;
use strict;
use Data::Dumper;
use Exporter;

@RefactorF4Acc::Inventory::ISA = qw(Exporter);

@RefactorF4Acc::Inventory::EXPORT = qw(
    &find_subroutines_functions_and_includes
);

use File::Find;

use RefactorF4Acc::Config;

# Find all source files in the current directory
# The files are parsed to determine the following information:
# Subroutines, Functions or IncludeFile
# Fortran style: FStyle
# Free or fixed form: FreeForm
# Are there blocks to be refactored: HasBlocks
sub find_subroutines_functions_and_includes {	
    my $stref = shift;
    my $prefix   = $Config{PREFIX}->[0];
    my @srcdirs=@{ $Config{SRCDIRS} };
    # find sources (borrowed from PerlMonks)
    my %src_files = ();
    my $tf_finder = sub {
        return if !-f;
        return if (!/\.f(?:90)?$/ &&!/\.c$/); # rather ad-hoc for Flexpart + WRF
        # FIXME: we must have a list of folders to search or not to search!
        $src_files{$File::Find::name} = 1;
    };
    for my $dir (@srcdirs) { 
    	print "$dir\n";
    find( $tf_finder, "$prefix/$dir" );
    }

    for my $src ( sort keys %src_files ) {
    	if  ($src=~/\.c$/) {
#    		warn "C SOURCE: $src\n";
    		# FIXME: ugly ad-hoc hack!
    		# WRF uses cpp to make subroutine names match with Fortran
    		# So we need to call cpp first, but with all the correct macros ...
    		# Without any defined macros, it's like this:    	
#    		my @lines=`grep -v '#include' $src  | cpp -P -`;
    		# I guess we could use some command-line flag to add the macro definitions
    		# And now we must parse C sources too ...
    		
#    		die;
            
    	} else {
#    	   print "F90 SOURCE: $src\n"; 
    	}
        $stref=process_src($src,$stref);
    }
#    die;
#die $stref->{'Subroutines'}{'timemanager'}{'HasBlocks'}  ;
    return $stref;
}    # END of find_subroutines_functions_and_includes()

sub process_src {
	(my $src, my $stref)=@_;
	
    my $srctype=''; # sub, func or incl
    my $f=''; # name of the entity
    my $has_blocks=0;
    my $free_form=0;
    my $fstyle='F77';   
    my $translate_to='';
    
        open my $SRC, '<', $src;
        while ( my $line = <$SRC> ) {

            # Skip blanks
            $line =~ /^\s*$/ && next;
            # Translate pragma
        if ( $line =~ /^\!\s*\$acc\stranslate\s(\w+)/i ) { 
            $translate_to=$1;
        }             

        # Detect blocks
            if ( $has_blocks == 0 ) {
                if ( $line =~ /^[Cc\*\!]\s+BEGIN\sSUBROUTINE\s(\w+)/ 
        or $line =~ /^\!\s*\$acc\ssubroutine\s(\w+)/i ){
                         my $sub=$1;
                        $has_blocks = 1;
                        if ($translate_to ne '') {
                            $stref->{'Subroutines'}{$sub}{'Translate'}= $translate_to;
                            $translate_to='';                           
                        }
                }
            }

            # Skip comments 
            $line =~ /^\s*[C\*\!]/i && next;
            
        # Tests for free or fixed form
        if ($free_form==0) {
            if ( $line !~ /^[\s\d]{5}.+/ and $line !~ /^\t[\t\s]*\w/ and $line !~/^\s+\t/) {
                $free_form = 1;       
#                die $line,$src;                                                     
            } 
               
            if ($line =~ /\&\s*$/ ) {
                    $free_form = 1;          
            }
        }   
        # Tests for F77 or F95
        if ($fstyle eq 'F77') {
            if ( $line =~ /\bmodule\b/i ) { 
                    $fstyle='F95';
            } elsif ( $line =~ /^\s*(.*)\s*::\s*(.*?)\s*$/ ) {
                 $fstyle='F95';
            }
        }
        
            # Find subroutine/program signatures
            $line =~ /^\s*(recursive\s+subroutine|subroutine|program)\s+(\w+)/i && do {                
                my $is_prog = (lc($1) eq 'program') ? 1 : 0;
                if ( $is_prog == 1 ) {
                    print "Found program $2 in $src\n" if $V;
                }                
                my $sub  = lc($2);
                $f=$sub;                
                $srctype='Subroutines';
                $stref->{'Subroutines'}{$sub}={};
                $stref->{'SourceContains'}{$src}{$f}=$srctype;
                my $Ssub = $stref->{'Subroutines'}{$sub};
                if (
                    not exists $Ssub->{'Source'}
                    or (    $src =~ /$sub\.f(?:90)?/
                        and $Ssub->{'Source'} !~ /$sub\.f(?:90)?/ )
                  )
                {
                    if (    exists $Ssub->{'Source'}
                        and $src =~ /$sub\.f(?:90)?/
                        and $Ssub->{'Source'} !~ /$sub\.f(?:90)?/ )
                    {
                        print "WARNING: Ignoring source "
                          . $Ssub->{'Source'}
                          . " because source $src matches subroutine name $sub.\n"
                          if $W;
                    }
                    $Ssub->{'Source'}  = $src;
                    $Ssub->{'Status'}  = $UNREAD;
                    $Ssub->{'Program'} = $is_prog;
                    $Ssub->{'Callers'}  = {};
                    if ($translate_to ne '') {
                        $Ssub->{'Translate'}  = $translate_to;
                        $translate_to = '';
                    }

                } else {
                    print
"WARNING: Ignoring source $src for $sub because another source, "
                      . $Ssub->{'Source'}
                      . " exists.\n"
                      if $W;
                }
            };

            # Find include statements
            $line =~ /^\s*include\s+\'(\w+)\'/ && do {
                my $inc = $1;
                if ( not exists $stref->{'IncludeFiles'}{$inc} ) {
                    $stref->{'IncludeFiles'}{$inc}{'Status'} = $UNREAD;
            $f=$inc;
            $srctype='IncludeFiles';
                }
            };

            # Find function signatures
            $line =~ /\bfunction\s+(\w+)/i && do {
                my $func = lc($1);               
                $stref->{'Functions'}{$func}{'Source'} = $src;
                $stref->{'Functions'}{$func}{'Status'} = $UNREAD;
                if ($translate_to ne '') {
                        $stref->{'Functions'}{$func}{'Translate'}  = $translate_to;
                        $translate_to = '';
                    }
                  $f=$func;
                  $srctype='Functions';
                  $stref->{'SourceContains'}{$src}{$f}=$srctype;
            };
            
            $stref->{$srctype}{$f}{'FStyle'}=$fstyle;
            $stref->{$srctype}{$f}{'FreeForm'}=$free_form;  
            $stref->{$srctype}{$f}{'HasBlocks'}=$has_blocks;
        
        } # loop over lines;
            
        close $SRC;
        return $stref;	
	
}
