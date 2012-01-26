#!/usr/bin/perl
use warnings;
use strict;
use Carp;
use Data::Dumper;

=head1 SYNOPSIS

Run the script with -G and read the generated PDF documentation

=head1 TODOs

* Subroutine args marked as InOut can actually be In if the value is never used. We should check that!
"Never used" means that we have to check against all calls to the subroutine. 
As I am interested in factored-out routines, I will focus on single-call routines.
- If an argument is marked as InOut 
    - if the actual value is an expression, set to In
    - if the actual value is a local variable and it is not read after the call to the subroutine, set to In
        This is more complicated: 
        1. determine it's a local variable, i.e. not in the caller argument list. OK
        2. look if it occurs after the call to the subroutine => need to parse all lines

* Remap scalar arguments into arrays to have fewer arguments to pass -> mostly done, but not complete
What is needed is not just a merge for scalars, but also for arrays    

* Deal with OFRTRAN's arcane KIND approach 
  
*  Declarations from F2C-ACC are broken, emit our own => OK

*  But F2C-ACC's function calls are wrong too! They use the non-pointer vars where they should use the pointers! => OK

*  Put F2C-ACC into our tree, if the license allows it. => OK

=begin markdown

# FORTRAN Refactoring Tool |$VER|

## SYNOPSIS

    |$usage|
    
## DESCRIPTION

    The purpose of this tool is to refactor FORTRAN code by automatically performing the following transformations:
    * Replace all `common` block variables by subroutine arguments.
    * Factor out marked blocks of code into subroutines
    * Resolve name conflicts between parameters, local variables and function arguments
    * Rewrite label-based loops into DO-loops
    * Normalise the code to lowercase and 6-spaces based layout
    
    Furthermore, the tool preforms a number of operations intended to facilitate translation to C:
    * Replace `continue` statements by calls to a no-op routine
    * Analyse which `goto`'s can be replaced by `break` statements in C
    * Analyse the IO direction and type of all subroutine arguments
     
    It is designed to work on large FORTRAN programs, split over multiple files, written in a mixture of FORTRAN 77 and FORTRAN 95.        

## DESIGN

Because the aim of the tool is to refactor the source code, and not to translate or compile it, 
we don't use a full grammar-based lexer and parser but instead we perform context-free parsing using  
regular expression. As in many cases we require the context to analysed the parsed data, the program 
maintains a global state with the following structure:

    State
        Top
        Nodes
        NId
        CallTree
        Indents
        Subroutines
            Source -- 
            Lines -- the source per line, split lines have been merged
            Info -- information about each line            
            Blocks -- blocks marked for refactoring into subroutines
            HasBlocks 
*            Args -- subroutine arguments
            Includes
*            Vars -- all declared variables. FIXME: do this for functions too!
            CalledSubs --   
            Status -- 
*            Globals            
*            CommonIncludes
*            Commons
*            HasCommons            
            ConflictingParams -- 
            StringConsts -- string constants are replaced by placeholders            
            Gotos -- 
*            Program --
            Called --
*            RefactoredArgIODirs # TODO: make this RefactoredArgs -> IODirs, List, ...
*            RefactoredArgList
            RefactoredCode -- refactored source, line by line, long lines are split
        Functions
            Source            
            Lines
            Info
            [Blocks]
            HasBlocks            
            Includes            
            CalledSubs
            Status      
            StringConsts
            [Gotos]
            Called
            RefactoredCode      
        Includes
            Source
            Lines
            Info
            Vars            
            Status            
*            Type -- Common or Parameter
*            Root -- highest subroutine in the call tree for every include
            Commons 
*            ConflictingGlobals
            RefactoredCode
        BuildSources    

### Refactoring 'common' variables into subroutine arguments

FORTRAN's `common` blocks are a mechanism to create global variables:

"The COMMON statement defines a block of main memory storage so that
different program units can share the same data without using arguments." [F77 ref]

This is problematic for translation of code to OpenCL as of course it is not possible to have
globals across memory spaces. 
(Also, I personally think these globals are /evil/ -- as the FLEXPART codebase shows repeatedly:
e.g. PI is defined in one place as a parameter and in another place as a common variable, which is only assigned
in a deeply nested subroutine.) 

#### Codebase Inventory 

To refactor 'common' variables into subroutine arguments requires first of all an analysis of the full codebase. 
Therefore, the first step is to determine which files in a directory are used by the main program. 
To do so we first create an inventory of all subroutines, functions and include files in the codebase, 
and then we perform a dependency analysis and build the call tree.    
The inventory is done by finding all FORTRAN source files (using `File::Find`, and looking in them 
for subroutine, function and program signatures and include statements.

#### Dependency Analysis and Call Tree
 
Next, we perform a recursive descent on the main program, descending in all subroutine and function calls.



## Draft Outline  

0.2 Get rid of "common" variables, move them into function arguments 
This is refactoring, and there is really only one proper way to do this:
- parse the FORTRAN source in a labeled-block-aware way
- check which variables from the common block are used
- put them in the function signature
- for variables declared outside the block in question, find the ones that are used within the block
and add them to the function signature as well

Now, I don't have a full FORTRAN parser, but let's see what we can do with some limiting assumptions:
- assume the block is simply identified with a comment "C BEGIN blockname" and "C END blockname"
- assume any line starting with `/^\s[\+\&]/` is a continuation line, deal with these first
- assume that _all_ variables in includecom are common, and _all_ variable in includepar are parameters?
That won't do. No, we read the includes, and parse the "common" blocks
- we're only really interested in a few specific intrinsic types: 

    /(integer|real|double\s+precision|character\*?(?:\d+|\(\*\)))\s+(.+)\s*$/ 

The most difficult bit is finding the variables, I guess `$varname` should do?

With these assumptions, we can write a crude parser and function arg identifier as follows:
0. Slurp the source; strip the comments
1. Join up the continuation lines (maybe split lines with ; )
2. Parse the type declarations in the source, create a table %vars
3. Parse includes, recursively doing 0/1/2
4. For includes, parse common blocks, create %commons
5. Split the source based on the block markers
6. Identify which vars are used
	- in both => these become function arguments
	- only in "outer" => do nothing for those
	- only in "inner" => can be removed from outer variable declarations
7. Identify which commons are used in inner, make them function arguments

Not necessarily in this order:
8. When encountering a CALL, recurse and resolve globals (but only that)
9. When encountering a  function call, idem; although I'd prefer it if functions would be pure!
10. F2C-ACC is a bit buggy, so help it a bit: identify which CONTINUE statements are actually END DO
and replace them accordingly; for the other CONTINUE statements, it might be better to 
ensure that instead of CONTINUE, they do nothing in a different way. 
The only reliable way I found is to replace the continue with call noop, where noop is a subroutine that does nothing

How do we replace the args in a subroutine call?

- Find a subroutine call
- first check if we now about it by looking in a list of subroutine calls => We use 'IsSub'
- if we know it, it means we have resolved the globals, the list should be added to the node;
then just add the globals to the call
- otherwise, add the index in the list of source lines to a hash of subs 
- in fact, this can be a hash of "anythings", i.e.
 
        $stref->{'Nodes'}{$filename}{'SubroutineCall'}{$name}={'Pos'=>[$index,...],'Globals'=>[],...};
    
    As this is a "global", I need to pass it around between calls.
- recurse and figure out globals used. also, store the signature in the node hash
- add the globals to the end of the signature, and emit the new code.
- it would be nice to emit the code in a hash 

        $refactored_sources{$filename}=\@lines;
    
- return the list of all the globals to be added to the call
- update the call in %refactored_sources

        'Subroutines' => { 
                    $name => {
                       'Source' => $src,
                       'Lines' =>[$line],
                       'Blocks'=>{},
                       'HasBlocks'=>0|1                       
                       'Vars'=>
                       'RefactoredCode' => {},    
                       'Status' => 0|1|2|3,
                       'Info' => [ {
                       	    'Signature' => {'Name' => ..., 'Args' => ...},
                       	    'Include' => {'Name' => ...,}
                       	    'ExGlobVarDecls'=> ...
                       	    'SubroutineCall'=>{'Name' => ..., 'Args' => ...}
                       	    'VarDecl' => [...]
                       } ],        
                     }
        }

Status: for programs, subroutines, functions and includes 
    0: after find_subroutines_functions_and_includes() 
    1: after read_fortran_src()
    2: after parse_fortran_src_OLD()
    3: after create_subroutine_source_from_block()
After building this structure, what we need is to go through it an revert it so it becomes index => information

=end markdown



In Haskell, I guess we'd have a type representing all fields rather than a map:

State = MkState {
        subroutines::Subroutines
    ,   nid::Int
    ,   nodes::Nodes
    ,   includes::Includes
    ,   functions::Functions
    ,   calltree::CallTree
    ,

}

Nodes = Hash.Map Int Node

=cut

use Getopt::Std;
use File::Find;
use File::Copy;
use Digest::MD5;

our $VER = '0.3';

our $usage = "
    $0 [-hvwCTNbB] <toplevel subroutine name> 
       [<subroutine name(s) for C translation>]
    -h: help
    -w: show warnings 
    -v: verbose (implies -w)
    -i: show info messages
    -C: Only generate call tree, don't refactor or emit
    -T: Translate <subroutine name> and dependencies to C 
    -N: Don't replace CONTINUE by CALL NOOP
    -b: Generate SCons build script, currently ignored 
    -B: Build FLEXPART (implies -b)
    -G: Generate Markdown documentation
    \n";

our $V = 0;    # Verbose
our $W = 0;    # Warnings
our $I = 0;    # Info

# Instead of FORTRAN's 'continue', we insert a call to a subroutine noop() that does nothing
# This is because F2C_ACC handles continue incorrectly
our $noop           = 1;
our $call_tree_only = 0;
our $main_tree      = 0;

# Flag used when generating a subroutine from a marked block of code
our $gen_sub = 0;

# States for translation to C etc
( our $NO, our $YES, our $GO ) = ( 0 .. 2 );
our $translate        = $NO;
our %subs_to_translate = ();

# The state of each subroutine, function or include
#   FROM_BLOCK indicates a marked block of code factored out into a subroutine
#   C_SOURCE means that this source code will be translated to C
( our $UNREAD, our $READ, our $PARSED, our $FROM_BLOCK, our $C_SOURCE ) =
  ( 0 .. 4 );
our $targetdir = '../RefactoredSources';

&main();

# -----------------------------------------------------------------------------

=pod

=begin markdown

## Main subroutine

The `main()` subroutine performs following actions:

- Argument parsing
- `init_state()`: Initialise the global state
- {find_subroutines_functions_and_includes()}: Find all subroutines, functions and includes (from now on, 'targets') in the source code tree. 
The subroutine creates an entry in the state for every target:

        $stref->{$target_type}{$target_name}{'Source'}  = $target_source;
        $stref->{$target_type}{$target_name}{'Status'}  = $UNREAD;
        
- `parse_fortran_src()` :

    * Read the source and do some minimal processsing
    $stref = read_fortran_src( $f, $stref );
    * 2. Parse the type declarations in the source, create a table %vars
    * 2.1 Get variable declarations unless the target is a function 
    * 3. Parse Subroutines & Functions
            $stref = detect_blocks( $f, $stref );     
            $stref = parse_includes( $f, $stref );        
            $stref = parse_subroutine_and_function_calls( $f, $stref );
        Set Status to PARSED    
    * 4. Parse Includes: parse common blocks and parameters, create $stref->{'Commons'}
        $stref = get_commons_params_from_includes( $f, $stref );
        
- `find_root_for_includes() :
    
=end markdown

=cut

sub main {

	# Argument parsing. Factor out!
	if ( not @ARGV ) {
		die "Please specifiy FORTRAN subroutine or program to refactor\n";
	}
	my %opts = ();
	getopts( 'vwihCTNbBG', \%opts );
	my $subname = $ARGV[0];
	if ($subname) {
		$subname =~ s/\.f$//;
	}

	#	  die %opts;
	$V = ( $opts{'v'} ) ? 1 : 0;
	$I = ( $opts{'i'} or $V ) ? 1 : 0;
	$W = ( $opts{'w'} or $V ) ? 1 : 0;
	my $help = ( $opts{'h'} ) ? 1 : 0;
	if ($help) {
		die $usage;
	}
	if ( $opts{'G'} ) {
		print "Generating docs...\n";
		generate_docs();
		exit(0);
	}
	if ( $opts{'C'} ) {
		$call_tree_only = 1;
		$main_tree = $ARGV[1] ? 0 : 1;

	}
	if ( $opts{'T'} ) {
		if ( !@ARGV ) {
			die "Please specify a target subroutine to translate.\n";
		}
		$translate        = 1;
		%subs_to_translate = map {$_ => 1 } @ARGV[1,-1];		
	}
	$noop = ( $opts{'N'} ) ? 0 : 1;

	#	my $gen = ( $opts{'b'} || $opts{'B'} ) ? 1 : 0;
	my $build = ( $opts{'B'} ) ? 1 : 0;

	#  Initialise the global state.
	my $stateref = init_state($subname);

	# Find all subroutines in the source code tree
	$stateref = find_subroutines_functions_and_includes($stateref);

# First we analyse the code for use of globals and blocks to be transformed into subroutines
#    $stateref->{'Nodes'}{0}={
#    	'Parent'=>0,
#    	'Children'=>[],
#    	'Subroutine'=>$subname
#    };
	$stateref = parse_fortran_src( $subname, $stateref );

	if ( $call_tree_only and not $ARGV[1] ) {
		create_call_graph($stateref);

		# TODO: I should really store the call tree and print it out here
		print "\nCall tree for $subname:\n\n" if $main_tree;
		for my $entry ( @{ $stateref->{'CallTree'} } ) {
			print $entry;
		}
		exit(0);
	}

	# Find the root for each include in a proper way
	$stateref = find_root_for_includes( $stateref, $subname );

	# Now we can do proper globals handling
	# We need to walk the tree again, find the globals in rec descent.
	$stateref = resolve_globals( $subname, $stateref );

#    $stateref= resolve_globals($subname,$stateref);
# I think we need to refactor the source first without creating the new sources,
# then us this info to determine the IO direction

	# Now we do the reformatting, block detection etc.
	$stateref = determine_argument_io_direction_rec( $subname, $stateref );

	$stateref = analyse_sources($stateref);

	# So at this point all we need to do is the actual refactoring ...
	#	die Dumper($stateref->{'Subroutines'}{'flexpart_wrf'});
	# Refactor the source
	$stateref = refactor_all_subroutines($stateref);
	$stateref = refactor_includes($stateref);
	$stateref = refactor_called_functions($stateref);

	if ( not $call_tree_only ) {

		# Emit the refactored source
		emit_all($stateref);
	}

	#	elsif ( $call_tree_only and $ARGV[1] ) {
	#		$subname = $ARGV[1];
	#		$gen_sub = 1;
	#		print "\nCall tree for $subname:\n\n";
	#		$stateref = parse_fortran_src( $subname, $stateref );
	#        for my $entry (@{$stateref->{'CallTree'}}) {
	#            print $entry;
	#        }
	#      exit(0);
	#	}
	if ( $translate == $YES ) {
		$translate = $GO;
		for my $subname   (keys %subs_to_translate ) {
		print "\nTranslating $subname to C\n";
		$gen_sub  = 1;
		$stateref = parse_fortran_src( $subname, $stateref );
		$stateref = refactor_C_targets($stateref);
		emit_C_targets($stateref);
		&translate_to_C($stateref);
		}
	}
	create_build_script($stateref);
	if ($build) {
		build_flexpart();
	}
	exit(0);

}    # END of main()

# -----------------------------------------------------------------------------

sub init_state {
	( my $subname ) = @_;

	# Nodes|Subroutines|Includes|Functions|NId|BuildSources|Indents
	my $stateref = {
		'Top'      => $subname,
		'Includes' => {},

		#        'Sources' => {'Subroutines' => {},'Functions'=>{}},
		'Subroutines'  => {},
		'BuildSources' => {}
		,    # sources to be built, can be C, H (header) or F (Fortran)
		'Indents' => 0,    # bit silly, purely for pretty-printing
		'NId'     => 0,    # running node id for traversal
		'Nodes'   => {     # nodes in call tree
			0 => {
				'Parent'     => 0,
				'Children'   => [],
				'Subroutine' => $subname
			}
		}
	};
	return $stateref;
}

# -----------------------------------------------------------------------------
# This is the most important routine
# It parses the FORTRAN source as discussed above
# Identification of
# Signature
# VarDecl
# InBlock etc
# Includes

=pod

=begin haskell

-- We really need to use the State monad!
parse_fortran_src :: String -> STRef -> STRef
parse_fortran_src  f stref =
    let
        stref' = read_fortran_src f stref
        m_incls = Hash.lookup "Includes" stref
        is_incl = case m_incls of
            Just incls -> Hash.member f incls
            Nothing -> False
        stref'' = get_var_decls f stref'

=end haskell

=cut

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

	my $is_incl = exists $stref->{'Includes'}{$f}  ? 1 : 0;
	my $is_func = exists $stref->{'Functions'}{$f} ? 1 : 0;

# 2. Parse the type declarations in the source, create a per-target table Vars and a per-line VarDecl list
# We don't do this in functions at the moment, because we don't need to? NO! FIXME!
	if ( not $is_func ) {
		$stref = get_var_decls( $f, $stref );
	}
	if ( not $is_incl ) {
		my $sub_or_func = sub_func_or_incl( $f, $stref );
		my $is_sub = ( $sub_or_func eq 'Subroutines' ) ? 1 : 0;

# For subroutines, we detect blocks, parse include and parse nested subroutine calls.
# Note that function calls have been dealt with (as a side effect) in get_var_decls()
#        if ($is_sub) {
# Detect the presence of a block in this target, only sets 'HasBlocks'
# Detect include statements and add to Subroutine 'Include' field
		$stref = parse_includes( $f, $stref );

		if ( $stref->{$sub_or_func}{$f}{'HasBlocks'} == 1 ) {
			$stref = separate_blocks( $f, $stref );
		}

		# Recursive descent via subroutine calls
		$stref = parse_subroutine_and_function_calls( $f, $stref );
		$stref->{$sub_or_func}{$f}{'Status'} = $PARSED;
	} else {    # includes
		        # 3. Parse includes

# 4. For includes, parse common blocks and parameters, create $stref->{'Commons'}
		$stref = get_commons_params_from_includes( $f, $stref );
		$stref->{'Includes'}{$f}{'Status'} = $PARSED;
	}
	return $stref;
}    # END of parse_fortran_src()

# -----------------------------------------------------------------------------
# Maybe I need an additional Status here
sub analyse_sources {
	( my $stref ) = @_;
	for my $f ( keys %{ $stref->{'Subroutines'} } ) {
		if (
			(
				exists $stref->{'Subroutines'}{$f}{'Called'}
				&& $stref->{'Subroutines'}{$f}{'Called'} == 1
			)
			or ( exists $stref->{'Subroutines'}{$f}{'Program'}
				&& $stref->{'Subroutines'}{$f}{'Program'} == 1 )
		  )
		{
			$stref = identify_loops_breaks( $f, $stref );
		} else {
			print "INFO: Subroutine $f is never called, skipping analysis\n"
			  if $I;
		}
	}
	for my $f ( keys %{ $stref->{'Functions'} } ) {
		if ( exists $stref->{'Functions'}{$f}{'Called'}
			&& $stref->{'Functions'}{$f}{'Called'} == 1 )
		{
			$stref = identify_loops_breaks( $f, $stref );
		} else {
			print "INFO: Function $f is never called, skipping analysis\n"
			  if $I;
		}
	}
	return $stref;
}

# -----------------------------------------------------------------------------
# To find the root for all includes, we first find the leaves of the call tree
# Then we find the root for each include in turn

=pod

=begin markdown
## Handling of Common Block Variables

FORTRAN's `common` blocks are a mechanism to create global variables:

"The COMMON statement defines a block of main memory storage so that
different program units can share the same data without using arguments." [F77 ref]

This is problematic for translation of code to OpenCL as of course it is not possible to have
globals across memory spaces. 
[ Also, I personally think these globals are /evil/ -- for examples, see FLEXPART.]  


=end markdown

=cut 

sub find_root_for_includes {
	( my $stref, my $f ) = @_;
	$stref = find_leaves( $stref, 0 );  # assumes we start at node 0 in the tree
	for my $inc ( keys %{ $stref->{'Includes'} } ) {
		if ( $stref->{'Includes'}{$inc}{'Type'} eq 'Common' ) {

			#        	print "FINDING ROOT FOR $inc ($f)\n" ;
			$stref = find_root_for_include( $stref, $inc, $f );
			print "ROOT for $inc is "
			  . $stref->{'Includes'}{$inc}{'Root'} . "\n"
			  if $V;
		}
	}
	return $stref;
}    # END of find_root_for_includes()

# -----------------------------------------------------------------------------
sub find_root_for_include {
	( my $stref, my $inc, my $sub ) = @_;
	if ( exists $stref->{'Subroutines'}{$sub}{'Includes'}{$inc} ) {
		$stref->{'Includes'}{$inc}{'Root'} = $sub;
	} else {
		my $nchildren   = 0;
		my $singlechild = '';
		for my $calledsub (
			keys %{ $stref->{'Subroutines'}{$sub}{'CalledSubs'} } )
		{

			#			print "$calledsub\n";
			if (
				exists $stref->{'Subroutines'}{$calledsub}{'CommonIncludes'}
				{$inc} )
			{
				$nchildren++;
				$singlechild = $calledsub;
			}
		}
		if ( $nchildren == 0 ) {
			die
"find_root_for_include(): Can't find $inc in parent or any children, something's wrong!\n";
		} elsif ( $nchildren == 1 ) {

			#			print "DESCEND into $singlechild\n";
			delete $stref->{'Subroutines'}{$sub}{'CommonIncludes'}{$inc};
			find_root_for_include( $stref, $inc, $singlechild );
		} else {

			# head node is root
			#			print "Found $nchildren children with $inc\n";
			$stref->{'Includes'}{$inc}{'Root'} = $sub;
		}
	}
	return $stref;
}    # END of find_root_for_include()

# -----------------------------------------------------------------------------
# What we do is simply a recursive descent until we hit the include and we log that path
# Then we prune the paths until they differ, that's the root
# We also need to add the include to all nodes in the divergent paths
sub find_leaves {
	( my $stref, my $nid ) = @_;
	my @chain = ();
	if ( exists $stref->{'Nodes'}{$nid}{'Children'}
		and @{ $stref->{'Nodes'}{$nid}{'Children'} } )
	{

		# Find all children of $nid
		my @children = @{ $stref->{'Nodes'}{$nid}{'Children'} };

# Now for each of these children, find their children until the leaf nodes are reached
		for my $child (@children) {
			$stref = find_leaves( $stref, $child );
		}
	} else {

# We reached a leaf node
#		print "Reached leaf $nid\n";
# Now we work our way back up via the parent using a separate recursive function
		$stref = create_chain( $stref, $nid, $nid );

# The chain is identified by the name of the leaf child
# Check if the chain contains the $inc on the way up
# Note that we can check this for every inc so we need to do this only once if we're clever -- looks like the coffee is working!

		# When all leaf nodes have been processed, we should do the following:
		# Create a list of all chains for each $inc
		# Now find the deepest common node.
	}

	return $stref;
}    # END of find_leaves()

# -----------------------------------------------------------------------------
# From each leaf node we follow the path back to the root of the tree
# We combine all includes of all child nodes of a node, and the node's own includes, into CommonIncludes

sub create_chain {
	( my $stref, my $nid, my $cnid ) = @_;

	#	print "create_chain $nid $cnid ";
	# In $c
	# If there are includes with common blocks, merge them into CommonIncludes
	my $pnid = $stref->{'Nodes'}{$nid}{'Parent'};
	my $csub = $stref->{'Nodes'}{$cnid}{'Subroutine'};
	my $sub  = $stref->{'Nodes'}{$nid}{'Subroutine'};
	if ( exists $stref->{'Subroutines'}{$sub}{'Includes'}
		and not exists $stref->{'Subroutines'}{$sub}{'CommonIncludes'} )
	{
		for my $inc ( keys %{ $stref->{'Subroutines'}{$sub}{'Includes'} } ) {
			if ( $stref->{'Includes'}{$inc}{'Type'} eq 'Common'
				and not
				exists $stref->{'Subroutines'}{$sub}{'CommonIncludes'}{$inc} )
			{
				$stref->{'Subroutines'}{$sub}{'CommonIncludes'}{$inc} = 1;
			}
		}
	}
	if ( $nid != $cnid ) {
		my $csub = $stref->{'Nodes'}{$cnid}{'Subroutine'};
		if ( exists $stref->{'Subroutines'}{$csub}{'CommonIncludes'} ) {
			for my $inc (
				keys %{ $stref->{'Subroutines'}{$csub}{'CommonIncludes'} } )
			{
				if (
					not exists $stref->{'Subroutines'}{$sub}{'CommonIncludes'}
					{$inc} )
				{
					print "$sub:\tMERGING $inc FROM $csub\n"
					  if $sub =~ /advance/;
					$stref->{'Subroutines'}{$sub}{'CommonIncludes'}{$inc} = 1;
				}
			}
		}
	}
	if ( $nid != 0 ) {
		$stref = create_chain( $stref, $pnid, $nid );
	}

	#	else {
	# reached head node, return $stref
	#		print "Reached head node\n";
	#	}
	return $stref;
}

# -----------------------------------------------------------------------------
sub refactor_globals {
	( my $stref, my $f, my $annlines ) = @_;

	print "REFACTORING GLOBALS in $f\n"
	  if $V; #die Dumper( $stref->{'Subroutines'}{$f}{'Args'}) if $f=~/advance/;
	my $rlines        = [];
	my $s             = $stref->{'Subroutines'}{$f}{'Source'};
	my $is_C_target   = exists $stref->{'BuildSources'}{'C'}{$s} ? 1 : 0;	
	my $idx           = 0;
	for my $annline ( @{$annlines} ) {
		my $line      = $annline->[0] || '';
		my $tags_lref = $annline->[1];
		my %tags      = ( defined $tags_lref ) ? %{$tags_lref} : ();
		print '*** ' . join( ',', keys(%tags) ) . "\n" if $V;
		print '*** ' . $line . "\n" if $V;
		my $skip = 0;

		if ( exists $tags{'Signature'} ) {
			$stref = refactor_subroutine_signature( $stref, $f )
			  ;    # Do this before the analysis for RefactoredArgs!
			$rlines =
			  create_refactored_subroutine_signature( $stref, $f, $annline,
				$rlines );

			$skip = 1;
		}

		if ( exists $tags{'Include'} ) {
			$skip = skip_common_include_statement( $stref, $f, $annline );

		}

		if ( exists $tags{'ExGlobVarDecls'} ) {

			# First, abuse ExGlobVarDecls as a hook for the addional includes
			$rlines =
			  create_new_include_statements( $stref, $f, $annline, $rlines );

			# Then generate declarations for ex-globals
			$rlines =
			  create_exglob_var_declarations( $stref, $f, $annline, $rlines );
			  
			# While we're here, might as well generate the declarations for remapping and reshaping.
			# If the subroutine contains a call to a function that requires this, of course.
			# Executive decision: do this only for the routines to be translated to C/OpenCL
			for my $called_sub (keys %{ $stref->{'Subroutines'}{$f}{'CalledSubs'} }) {
				if (exists $subs_to_translate{$called_sub}) {
				    # OK, we need to do the remapping, so create the machinery here
				    # 1. Get the arguments of the called sub
				    
				    # 2. Work out if they need reshaping. If so, create the declarations for the new 1-D arrays
				    
				    # 3. Work out which remapped arrays will be used; create the declarations for these arrays
				     	
				}
			}

		}
		if ( exists $tags{'VarDecl'} ) {
			$rlines = create_refactored_vardecls( $stref, $f, $annline, $rlines,
				$is_C_target );
			$skip = 1;
		}
		if ( exists $tags{'SubroutineCall'} ) {

			# simply tag the common vars onto the arguments
			$rlines = create_refactored_subroutine_call( $stref, $f, $annline,
				$rlines );
			$skip = 1;
		}

		if ( not exists $tags{'Comments'} and $skip == 0 ) {
			$rlines =
			  rename_conflicting_locals( $stref, $f, $annline, $rlines );
			$skip = 1;
		}
		push @{$rlines}, $annline unless $skip;
		$idx++;
	}
	return $rlines;
}    # END of refactor_globals()

# -----------------------------------------------------------------------------
sub refactor_subroutine_signature {
	( my $stref, my $f ) = @_;

	if ($V) {
		if ( exists $stref->{'Subroutines'}{$f}{'Args'} ) {
			print "SUB $f ORIG ARGS:"
			  . join( ',', @{ $stref->{'Subroutines'}{$f}{'Args'} } ), "\n";
		} else {
			print "SUB $f ORIG ARGS: ()\n";
		}
	}
	my %args     = map { $_ => 1 } @{ $stref->{'Subroutines'}{$f}{'Args'} };
	my @exglobs  = ();
	my @nexglobs = ();
	my $conflicting_params = $stref->{'Subroutines'}{$f}{'ConflictingParams'};
	for my $inc ( keys %{ $stref->{'Subroutines'}{$f}{'Globals'} } ) {
		print "INFO: INC $inc in $f\n" if $V;
		if ( not exists $stref->{'Includes'}{$inc}{'Root'} ) {
			die "$inc has no Root in $f";
		}
		if ( $stref->{'Includes'}{$inc}{'Root'} eq $f ) {
			print "INFO: $f is root for $inc (lookup)\n" if $V;
			next;
		}
		if ( defined $stref->{'Subroutines'}{$f}{'Globals'}{$inc} ) {
			for my $var ( @{ $stref->{'Subroutines'}{$f}{'Globals'}{$inc} } ) {
				if ( not exists $stref->{'Subroutines'}{$f}{'Vars'}{$var} ) {
					$stref->{'Subroutines'}{$f}{'Vars'}{$var} =
					  $stref->{'Includes'}{$inc}{'Vars'}{$var};
				}
			}
			print "$inc:"
			  . join( ',', @{ $stref->{'Subroutines'}{$f}{'Globals'}{$inc} } ),
			  "\n"
			  if $V;
			@exglobs =
			  ( @exglobs, @{ $stref->{'Subroutines'}{$f}{'Globals'}{$inc} } );
		}
	}
	for my $var (@exglobs) {
		if ( exists $conflicting_params->{$var} ) {
			print
"WARNING: CONFLICT in arguments for $f, renamed $var to ${var}_GLOB\n"
			  if $W;
			push @nexglobs, $conflicting_params->{$var};
			$stref->{'Subroutines'}{$f}{'Vars'}{ $conflicting_params->{$var} } =
			  $stref->{'Subroutines'}{$f}{'Vars'}{$var};
		} else {
			push @nexglobs, $var;
		}
	}
	my $args_ref =
	  ordered_union( $stref->{'Subroutines'}{$f}{'Args'}, \@nexglobs );
	$stref->{'Subroutines'}{$f}{'RefactoredArgs'}{'List'} = $args_ref;
	return $stref;
}    # END of refactor_subroutine_signature()

# --------------------------------------------------------------------------------
sub rename_conflicting_locals {
	( my $stref, my $f, my $annline, my $rlines ) = @_;
	my $line               = $annline->[0] || '';
	my $tags_lref          = $annline->[1];
	my %conflicting_locals = ();
	if ( exists $stref->{'Subroutines'}{$f}{'ConflictingGlobals'} ) {
		%conflicting_locals =
		  %{ $stref->{'Subroutines'}{$f}{'ConflictingGlobals'} };
	}
	my $rline = $line;
	for my $lvar ( keys %conflicting_locals ) {
		if ( $rline =~ /\b$lvar\b/ ) {
			print
"WARNING: CONFLICT in $f, renaming $lvar with $conflicting_locals{$lvar}\n"
			  if $W;
			$rline =~ s/\b$lvar\b/$conflicting_locals{$lvar}/g;
		}
	}
	push @{$rlines}, [ $rline, $tags_lref ];
	return $rlines;
}    # END of rename_conflicting_locals()

# --------------------------------------------------------------------------------
sub create_refactored_vardecls {
	( my $stref, my $f, my $annline, my $rlines, my $is_C_target ) = @_;
	my $line      = $annline->[0] || '';
	my $tags_lref = $annline->[1];
	my %tags      = ( defined $tags_lref ) ? %{$tags_lref} : ();
	my %args      = map { $_ => 1 } @{ $stref->{'Subroutines'}{$f}{'Args'} };
	my @vars      = @{ $tags{'VarDecl'} };
	( my $maybe_args, my $globals ) = get_maybe_args_globs( $stref, $f );
	my %conflicting_locals = ();

	if ( exists $stref->{'Subroutines'}{$f}{'ConflictingGlobals'} ) {
		%conflicting_locals =
		  %{ $stref->{'Subroutines'}{$f}{'ConflictingGlobals'} };
	}
	my $rline = $line;
	my @nvars = ();
	for my $var (@vars) {
		my $skip_var = 0;
		if ( exists $stref->{'Functions'}{$var} ) {
			if ($is_C_target) {
				print "WARNING: $var in $f is a function!\n" if $W;
				$skip_var = 1;
			}
		}
		if ( not $skip_var ) {
			if ( exists $globals->{$var} and not exists $args{$var} ) {
				print
"WARNING: CONFLICT in $f ($stref->{'Subroutines'}{$f}{'Source'}):  renaming local $var to $var\_LOCAL\n"
				  if $W;
				my $nvar = $var . '_LOCAL';
				$conflicting_locals{$var} = $nvar;
				$rline =~ s/\b$var\b/$nvar/;
				push @nvars, $nvar;
			} else {
				push @nvars, $var;
			}
		}
	}
	$rline =~ s/,\s*$//;
	if ( $line !~ /\(.*?\)/ ) {    # FIXME: can't handle arrays yet!
		                           # NEW code
		my $spaces = $line;
		$spaces =~ s/[^\s].*$//;
		$rline =
		    $spaces
		  . $stref->{'Subroutines'}{$f}{'Vars'}{ $vars[0] }{'Type'} . ' '
		  . join( ',', @nvars ) . "\n";
	}

	push @{$rlines}, [ $rline, $tags_lref ];

	return $rlines;
}    # END of create_refactored_vardecls()

# --------------------------------------------------------------------------------
sub create_exglob_var_declarations {
	( my $stref, my $f, my $annline, my $rlines ) = @_;
	my $line      = $annline->[0] || '';
	my $tags_lref = $annline->[1];
	my %tags      = ( defined $tags_lref ) ? %{$tags_lref} : ();
	my %args      = map { $_ => 1 } @{ $stref->{'Subroutines'}{$f}{'Args'} };
	my $conflicting_params = $stref->{'Subroutines'}{$f}{'ConflictingParams'};

	for my $inc ( keys %{ $stref->{'Subroutines'}{$f}{'Globals'} } ) {
		print "INFO: GLOBALS from INC $inc in $f\n" if $V;
		for my $var ( @{ $stref->{'Subroutines'}{$f}{'Globals'}{$inc} } ) {
			if ( exists $args{$var} ) {
				my $rline = "*** ARG MASKS GLOB $var in $f!";

				#                        warn $rline,"\n";
				push @{$rlines}, [ $rline, $tags_lref ];
			} else {
				if ( exists $stref->{'Subroutines'}{$f}{'Commons'}{$inc} ) {
					if ( $f ne $stref->{'Includes'}{$inc}{'Root'} ) {
						print "\tGLOBAL $var from $inc in $f\n" if $V;
						my $rline =
						  $stref->{'Subroutines'}{$f}{'Commons'}{$inc}{$var}
						  {'Decl'};
						if ( exists $conflicting_params->{$var} ) {
							my $gvar = $conflicting_params->{$var};
							print
"WARNING: CONFLICT in arg decls for $f: renaming $var to ${var}_GLOB\n"
							  if $W;
							$rline =~ s/\b$var\b/$gvar/;
						}
						if ( not defined $rline ) {
							print "*** NO DECL for $var in $f!\n" if $V;
							$rline = "*** NO DECL for $var in $f!";
						}
						push @{$rlines}, [ $rline, $tags_lref ];
					} elsif ($V) {
						print last;
					}
				} elsif ($V) {
					print "*** NO COMMONS for $inc in $f ";
					if ( $f eq $stref->{'Includes'}{$inc}{'Root'} ) {
						print '(Root)' . "\n";
					} else {
						print 'BUT NOT ROOT!' . "\n";
					}
					last;
				}
			}
		}    # for
	}
	return $rlines;
}    # END of create_exglob_var_declarations()

# --------------------------------------------------------------------------------
sub create_new_include_statements {
	( my $stref, my $f, my $annline, my $rlines ) = @_;
	my $line      = $annline->[0] || '';
	my $tags_lref = $annline->[1];
	my %tags      = ( defined $tags_lref ) ? %{$tags_lref} : ();

	for my $inc ( keys %{ $stref->{'Subroutines'}{$f}{'Globals'} } ) {
		print "INC: $inc, root: $stref->{'Includes'}{$inc}{'Root'} \n"
		  if $V;
		if (

			#               $stref->{'Subroutines'}{$f}{'Includes'}{$inc} < 0
			exists $stref->{'Subroutines'}{$f}{'CommonIncludes'}{$inc}
			and $f eq $stref->{'Includes'}{$inc}{'Root'}
		  )
		{    # and $f ne $stref->{'Top'}) { # FIXME: not sure about this!
			print "INFO: instantiating merged INC $inc in $f\n" if $V;
			my $rline = "      include '$inc'";
			$tags_lref->{'Include'}{'Name'} = $inc;
			push @{$rlines}, [ $rline, $tags_lref ];
		}
	}
	return $rlines;
}    # END of create_new_include_statements()

# --------------------------------------------------------------------------------
sub skip_common_include_statement {
	( my $stref, my $f, my $annline ) = @_;
	my $line      = $annline->[0] || '';
	my $tags_lref = $annline->[1];
	my %tags      = ( defined $tags_lref ) ? %{$tags_lref} : ();
	my $skip      = 0;
	my $inc       = $tags{'Include'}{'Name'};
	print "INFO: INC $inc in $f\n" if $V;
	if ( $stref->{'Includes'}{$inc}{'Type'} eq 'Common' ) {

		if ($V) {
			print "SKIPPED $inc: Root: ",
			  ( $stref->{'Includes'}{$inc}{'Root'} ne $f ) ? 0 : 1, "\tTop:",
			  (       ( $stref->{'Includes'}{$inc}{'Root'} eq $f )
				  and ( $f eq $stref->{'Top'} ) ) ? 1 : 0, "\n";
		}
		$skip = 1;
	}
	return $skip;
}    # END of skip_common_include_statement()

# --------------------------------------------------------------------------------
sub create_refactored_subroutine_signature {
	( my $stref, my $f, my $annline, my $rlines ) = @_;
	my $line      = $annline->[0] || '';
	my $tags_lref = $annline->[1];
	my %tags      = ( defined $tags_lref ) ? %{$tags_lref} : ();
	( my $maybe_args, my $globals ) = get_maybe_args_globs( $stref, $f );
	my $args_ref = $stref->{'Subroutines'}{$f}{'RefactoredArgs'}{'List'};
	my $args_str = join( ',', @{$args_ref} );
	print "NEW ARGS: $args_str\n" if $V;
	my $rline = '';

	if ( $stref->{'Subroutines'}{$f}{'Program'} ) {
		$rline = '      program ' . $f;
	} else {
		$rline = '      subroutine ' . $f . '(' . $args_str . ')';
	}
	$tags{'Refactored'} = 1;
	push @{$rlines}, [ $rline, $tags_lref ];

	# IO direction information
	for my $arg ( @{$args_ref} ) {
		if (
			exists $stref->{'Subroutines'}{$f}{'RefactoredArgs'}{$arg}
			{'IODir'} )
		{
			my $iodir =
			  $stref->{'Subroutines'}{$f}{'RefactoredArgs'}{$arg}{'IODir'};
			my $kind =
			  $stref->{'Subroutines'}{$f}{'RefactoredArgs'}{$arg}
			  {'Kind'};    #Unknown';
			my $type =
			  $stref->{'Subroutines'}{$f}{'RefactoredArgs'}{$arg}
			  {'Type'};    #Unknown';

		  #			if ( exists $maybe_args->{$arg}{'Kind'} ) {
		  #				$kind = $maybe_args->{$arg}{'Kind'};
		  #				$type = $maybe_args->{$arg}{'Type'};
		  #			} else {
		  #                print "WARNING: No type info for $arg in $f\n" if $W;
		  #            }
			my $ntabs = ' ' x 8;
			if ( $iodir eq 'In' and $kind eq 'Scalar' ) {
				$ntabs = '';
			} elsif ( $iodir eq 'Out' ) {
				$ntabs = ' ' x 4;
			}
			my $comment = "C      $ntabs$arg:\t$iodir, $kind, $type";
			push @${rlines}, [ $comment, { 'Comment' => 1 } ];
		} else {
			print "WARNING: No IO info for $arg in $f\n" if $W;
		}
	}

	return $rlines;
}    # END of create_refactored_subroutine_signature()

# ----------------------------------------------------------------------------------------------------
sub create_refactored_subroutine_call {
	( my $stref, my $f, my $annline, my $rlines ) = @_;
	my $line      = $annline->[0] || '';
	my $tags_lref = $annline->[1];
	my %tags      = ( defined $tags_lref ) ? %{$tags_lref} : ();

	# simply tag the common vars onto the arguments
	my $name = $tags{'SubroutineCall'}{'Name'};

	my $conflicting_locals = {};
	if ( exists $stref->{'Subroutines'}{$f}{'ConflictingGlobals'} ) {
		$conflicting_locals = $stref->{'Subroutines'}{$f}{'ConflictingGlobals'};
	}
	my $globals = determine_exglob_subroutine_call_args( $stref, $f, $name );
	my $orig_args = [];
	for my $arg ( @{ $tags{'SubroutineCall'}{'Args'} } ) {
		if ( exists $conflicting_locals->{$arg} ) {
			push @{$orig_args}, $conflicting_locals->{$arg};
		} else {
			push @{$orig_args}, $arg;
		}
	}
	my $args_ref = ordered_union( $orig_args, $globals );

	my $args_str = join( ',', @{$args_ref} );
	$line =~ s/call\s.*$//;
	my $rline = "call $name($args_str)\n";
	push @{$rlines}, [ $line . $rline, $tags_lref ];
	return $rlines;
}    # END of create_refactored_subroutine_call()

# ----------------------------------------------------------------------------------------------------
sub determine_exglob_subroutine_call_args {
	( my $stref, my $f, my $name ) = @_;
	my %conflicting_locals = ();
	my %conflicting_params = ();
	if ( exists $stref->{'Subroutines'}{$f}{'ConflictingParams'} ) {
		%conflicting_params =
		  %{ $stref->{'Subroutines'}{$f}{'ConflictingParams'} };
	}
	if ( exists $stref->{'Subroutines'}{$f}{'ConflictingGlobals'} ) {
		%conflicting_locals =
		  %{ $stref->{'Subroutines'}{$f}{'ConflictingGlobals'} };
	}
	my %conflicting_exglobs_params = ();
	if (%conflicting_params) {
		%conflicting_exglobs_params =
		  ( %conflicting_locals, %conflicting_params );
	}
	my @globals = ();
	for my $inc ( keys %{ $stref->{'Subroutines'}{$name}{'Globals'} } ) {
		next if $stref->{'Includes'}{$inc}{'Root'} eq $name;
		if ( defined $stref->{'Subroutines'}{$name}{'Globals'}{$inc} ) {
			if (%conflicting_exglobs_params) {
				for my $var (
					@{ $stref->{'Subroutines'}{$name}{'Globals'}{$inc} } )
				{
					if ( exists $conflicting_exglobs_params{$var} ) {
						print
"WARNING: CONFLICT in call to $name in $f:renaming $var with ${var}_GLOB!\n"
						  if $W;
						push @globals, $conflicting_exglobs_params{$var};
					} else {
						push @globals, $var;
					}
				}
			} else {
				@globals = (
					@globals,
					@{ $stref->{'Subroutines'}{$name}{'Globals'}{$inc} }
				);
			}
		}
	}

	return \@globals;
}    # END of determine_exglob_subroutine_call_args

# ----------------------------------------------------------------------------------------------------
sub refactor_subroutine_call_args {
	( my $stref, my $f, my $idx ) = @_;

	my $tags = $stref->{'Subroutines'}{$f}{'Info'}[$idx];

	# simply tag the common vars onto the arguments
	my $name = $tags->{'SubroutineCall'}{'Name'};

	my %conflicting_locals = ();
	my %conflicting_params = ();
	if ( exists $stref->{'Subroutines'}{$f}{'ConflictingParams'} ) {
		%conflicting_params =
		  %{ $stref->{'Subroutines'}{$f}{'ConflictingParams'} };
	}
	if ( exists $stref->{'Subroutines'}{$f}{'ConflictingGlobals'} ) {
		%conflicting_locals =
		  %{ $stref->{'Subroutines'}{$f}{'ConflictingGlobals'} };
	}
	my %conflicting_exglobs_params = ();
	if (%conflicting_params) {
		%conflicting_exglobs_params =
		  ( %conflicting_locals, %conflicting_params );
	}
	my @globals = ();
	for my $inc ( keys %{ $stref->{'Subroutines'}{$name}{'Globals'} } ) {
		next if $stref->{'Includes'}{$inc}{'Root'} eq $name;
		if ( defined $stref->{'Subroutines'}{$name}{'Globals'}{$inc} ) {
			if (%conflicting_exglobs_params) {
				for my $var (
					@{ $stref->{'Subroutines'}{$name}{'Globals'}{$inc} } )
				{
					if ( exists $conflicting_exglobs_params{$var} ) {
						print
"WARNING: CONFLICT in call to $name in $f:renaming $var with ${var}_GLOB!\n"
						  if $W;
						push @globals, $conflicting_exglobs_params{$var};
					} else {
						push @globals, $var;
					}
				}
			} else {
				@globals = (
					@globals,
					@{ $stref->{'Subroutines'}{$name}{'Globals'}{$inc} }
				);
			}
		}
	}

	my $orig_args = [];
	for my $arg ( @{ $tags->{'SubroutineCall'}{'Args'} } ) {
		if ( exists $conflicting_locals{$arg} ) {
			push @{$orig_args}, $conflicting_locals{$arg};
		} else {
			push @{$orig_args}, $arg;
		}
	}
	my $args_ref = ordered_union( $orig_args, \@globals );
	$tags->{'SubroutineCall'}{'RefactoredArgs'} = $args_ref;
	$stref->{'Subroutines'}{$f}{'Info'}[$idx] = $tags;
	return $stref;
}    # END of refactor_subroutine_call_args

# ----------------------------------------------------------------------------------------------------
sub refactor_blocks_OLD {
	( my $stref, my $f, my $annlines ) = @_;
	die;
	my $rlines = [];
	print "REFACTORING BLOCKS in $f\n" if $V;
	my @blocks = ();
	my $name   = 'NONE';
	for my $annline ( @{$annlines} ) {
		my $line      = $annline->[0];
		my $tags_lref = $annline->[1];
		my %tags =
		  ( defined $tags_lref )
		  ? %{$tags_lref}
		  : ( 'Nil' => [] );    # FIXME: needed?
		my $skip = 0;
		if ( exists $tags{'RefactoredSubroutineCall'} ) {
			$name = $tags{'RefactoredSubroutineCall'}{'Name'};
			$tags{'RefactoredSubroutineCall'}{'Args'} =
			  [ @{ $stref->{'Subroutines'}{$f}{'Blocks'}{$name}{'Args'} } ];
			push @blocks, $name;

			#we should refactor the block here to get the correct args
			#                $stref=$refactor_block_->($name,$f,$stref);
			my @args = @{ $stref->{'Subroutines'}{$name}{'Args'} };
			my $rline = 'C     call ' . $name . '(' . join( ',', @args ) . ')';
			$tags_lref = {%tags};
			delete $tags_lref->{'Comments'};
			push @{$rlines}, [ $rline, $tags_lref ];
			$skip = 1;
		}
		if ( exists $tags{'InBlock'} or exists $tags{'EndBlock'} ) {
			if ( $name ne 'NONE' ) {
				push @{ $stref->{'Subroutines'}{$f}{'Blocks'}{$name}{'Info'} },
				  $tags_lref;
			}
			$skip = 1;
		}
		push @{$rlines}, $annline unless $skip;
	}

	for my $name (@blocks) {
		$stref = create_subroutine_source_from_block( $name, $f, $stref );

		# Now we must parse this source
		$stref = get_var_decls( $name, $stref );
		$stref = parse_includes( $name, $stref );
		$stref = parse_subroutine_and_function_calls( $name, $stref );
		$stref = identify_globals_used_in_subroutine( $name, $stref );
		$stref = determine_argument_io_direction( $name, $stref );

		# Now we're ready to refactor this source
		$stref = refactor_subroutine( $name, $stref );    # shiver!
		croak Dumper( $stref->{'Subroutines'}{$name} );
	}

	# Now go through the lines again and create the proper call
	#        $annlines=$rlines;
	for my $annline ( @{$rlines} ) {
		my $line      = $annline->[0];
		my $tags_lref = $annline->[1];
		my %tags =
		  ( defined $tags_lref )
		  ? %{$tags_lref}
		  : ( 'Nil' => [] );                              # FIXME: needed?
		if ( exists $tags{'RefactoredSubroutineCall'} ) {

			# simply tag the common vars onto the arguments
			my $name    = $tags{'RefactoredSubroutineCall'}{'Name'};
			my @globals = ();
			for my $inc ( keys %{ $stref->{'Subroutines'}{$name}{'Globals'} } )
			{
				next if $stref->{'Includes'}{$inc}{'Root'} eq $name;
				@globals = (
					@globals,
					@{ $stref->{'Subroutines'}{$name}{'Globals'}{$inc} }
				);
			}
			my $orig_args = [];

			# FIXME: do I need to check for conflicting locals?
			for my $arg ( @{ $tags{'RefactoredSubroutineCall'}{'Args'} } ) {

		  #                    if (exists $conflicting_locals{$arg}) {
		  #                        push @{$orig_args},$conflicting_locals{$arg};
		  #                    } else {
				push @{$orig_args}, $arg;

				#                    }
			}
			my $args_ref = ordered_union( $orig_args, \@globals );
			my $args_str = join( ',', @{$args_ref} );
			my $rline = "      call $name($args_str)";
			$annline->[0] = $rline;
		}
	}

	return ( $stref, $rlines );
}    # END of refactor_blocks_OLD()

# -----------------------------------------------------------------------------

#* BeginDo: just remove the label
#* EndDo: replace label CONTINUE by END DO
#* Break: keep as is; add a comment to identify it as a break
#* Goto: Do nothing
#* GotoTarget: Do nothing
#* NoopBreakTarget: replace CONTINUE with "call noop"
#* BreakTarget: Do nothing
sub create_refactored_source {
	( my $stref, my $f, my $annlines ) = @_;
	print "CREATING FINAL $f CODE\n" if $V;
	my $rlines      = [];
	my @extra_lines = ();
	my $sub_or_func =
	  ( exists $stref->{'Subroutines'}{$f} ) ? 'Subroutines' : 'Functions';
	$stref->{$sub_or_func}{$f}{'RefactoredCode'} = [];

	#	die Dumper(@{$annlines} ) if $f eq 'particles_main_loop';
	for my $annline ( @{$annlines} ) {
		my $line = $annline->[0] || '';    # FIXME: why would line be undefined?
		my $tags_lref = $annline->[1] || {};
		my %tags = %{$tags_lref};

		# BeginDo: just remove the label
		if ( exists $tags{'BeginDo'} ) {
			$line =~ s/do\s+\d+\s+/do /;
		}

# EndDo: replace label CONTINUE by END DO; if no continue, remove label & add end do on next line
		if ( exists $tags{'EndDo'} ) {
			my $is_goto_target = 0;
			if (
				$stref->{$sub_or_func}{$f}{'Gotos'}{ $tags{'EndDo'}{'Label'} } )
			{

				# this is an end do which serves as a goto target
				$is_goto_target = 1;
			}
			my $count = $tags{'EndDo'}{'Count'};
			if ( $line =~ /^\s{0,4}\d+\s+continue/ ) {
				if ( $is_goto_target == 0 ) {
					$line = '      end do';
					$count--;
				} elsif ($noop) {
					$line =~ s/continue/call noop/;
				}
			} elsif ( $line =~ /^\d+\s+\w/ ) {
				if ( $is_goto_target == 0 ) {
					$line =~ s/^\d+//;
				}
			}
			while ( $count > 0 ) {
				push @extra_lines, '      end do';
				$count--;
			}
		}
		if ( $noop
			&& ( exists $tags{'NoopBreakTarget'} || exists $tags{'NoopTarget'} )
		  )
		{
			$line =~ s/continue/call noop/;
		}
		if ( exists $tags{'Break'} ) {
			$line .= '  !Break';

			# $line=~s/goto\s+(\d+)/call break($1)/;
		}

		if ( exists $tags{'PlaceHolders'} ) {
			my @phs = @{ $tags{'PlaceHolders'} };
			for my $ph (@phs) {
				my $str = $stref->{$sub_or_func}{$f}{'StringConsts'}{$ph};
				$line =~ s/$ph/$str/;
			}
		}
		if ( not exists $tags{'Comments'} ) {
			print $line, "\n" if $V;
			my @split_lines = split_long_line($line);
			for my $sline (@split_lines) {
				push @{ $stref->{$sub_or_func}{$f}{'RefactoredCode'} }, $sline;
			}
			if (@extra_lines) {
				for my $extra_line (@extra_lines) {
					push @{ $stref->{$sub_or_func}{$f}{'RefactoredCode'} },
					  $extra_line;
				}
				@extra_lines = ();
			}
		} else {
			push @{ $stref->{$sub_or_func}{$f}{'RefactoredCode'} }, $line;
		}
	}
	return $stref;
}    # END of create_refactored_source()

# -----------------------------------------------------------------------------

=pod

=begin markdown

## Info refactoring

for every line
- check if it needs changing:
- need to mark the insert points for subroutine calls that replace the refactored blocks! 
This is a node called 'RefactoredSubroutineCall'
- we also need the "entry point" for adding the declarations for the localized global variables 'ExGlobVarDecls'

* Signature: add the globals to the signature
(* VarDecls: keep as is)
* ExGlobVarDecls: add new var decls
* SubroutineCall: add globals for that subroutine to the call
* RefactoredSubroutineCall: insert a new subroutine call instead of the "begin of block" comment. 
* InBlock: skip; we need to handle the blocks separately
* BeginBlock: insert the new subroutine signature and variable declarations
* EndBlock: insert END
                      
=end markdown
=cut

sub refactor_subroutine {
	( my $f, my $stref ) = @_;
	if ($V) {
		print "\n\n";
		print "#" x 80, "\n";
		print "Refactoring $f\n";
		print "#" x 80, "\n";
	}

	print "REFACTORING SUBROUTINE $f\n" if $V;

	my @lines = @{ $stref->{'Subroutines'}{$f}{'Lines'} };
	my @info =
	  defined $stref->{'Subroutines'}{$f}{'Info'}
	  ? @{ $stref->{'Subroutines'}{$f}{'Info'} }
	  : ();
	my $annlines = [];
	for my $line (@lines) {
		my $tags = shift @info;
		push @{$annlines}, [ $line, $tags ];
	}

	my $rlines = $annlines;

	if ( $stref->{'Subroutines'}{$f}{'HasCommons'} ) {
		$rlines = refactor_globals( $stref, $f, $annlines );
	}

	#	if ( $stref->{'Subroutines'}{$f}{'HasBlocks'} == 1 ) {
	#		( $stref, $rlines ) = refactor_blocks( $stref, $f, $rlines );
	#	}    # HasBlocks

	if (   not exists $stref->{'Subroutines'}{$f}{'RefactoredCode'}
		or $stref->{'Subroutines'}{$f}{'RefactoredCode'} == []
		or exists $stref->{'BuildSources'}{'C'}
		{ $stref->{'Subroutines'}{$f}{'Source'} } )
	{
		$stref = create_refactored_source( $stref, $f, $rlines );
	}

#   print STDERR "REFACTORED $f\n";
#    die Dumper($stref->{'Subroutines'}{$f}{'RefactoredCode'}) if $f eq 'timemanager' ;
	return $stref;
}    # END of refactor_subroutine()

# -----------------------------------------------------------------------------
sub refactor_all_subroutines {
	( my $stref ) = @_;

	#	print Dumper(keys %{ $stref->{'Subroutines'} });
	for my $f ( keys %{ $stref->{'Subroutines'} } ) {
		if ( not defined $stref->{'Subroutines'}{$f}{'Status'} ) {
			$stref->{'Subroutines'}{$f}{'Status'} = $UNREAD;
			print "WARNING: no Status for $f\n" if $W;
		}
		next if $stref->{'Subroutines'}{$f}{'Status'} == $UNREAD;
		do {

			#			warn "Not parsed: $f\n";
			next;
		} if $stref->{'Subroutines'}{$f}{'Status'} == $READ;
		next if $stref->{'Subroutines'}{$f}{'Status'} == $FROM_BLOCK;
		$stref = refactor_subroutine( $f, $stref );
	}
	return $stref;
}    # END of refactor_all_subroutines()

# -----------------------------------------------------------------------------
sub refactor_called_functions {
	( my $stref ) = @_;

	for my $f ( keys %{ $stref->{'Functions'} } ) {

		#    	warn "REFACTORING FUNCTION $f? ";
		if ( defined $stref->{'Functions'}{$f}{'Called'} ) {

			#        	warn "YES\n";
			$stref = refactor_function( $f, $stref );
		} else {

			#        	warn "NOT REFACTORING FUNCTION $f\n";
			#        	die if $f eq 'cspanf';
		}
	}
	return $stref;
}    # END of refactor_called_functions()

#  -----------------------------------------------------------------------------
sub refactor_C_targets {
	( my $stref ) = @_;
	print "\nREFACTORING C TARGETS\n";

	#   print Dumper(keys %{ $stref->{'Subroutines'} });
	for my $f ( keys %{ $stref->{'Subroutines'} } ) {
		if (
			exists $stref->{'BuildSources'}{'C'}
			{ $stref->{'Subroutines'}{$f}{'Source'} } )
		{
			$stref = refactor_subroutine( $f, $stref );
		}
	}
	return $stref;
}

# -----------------------------------------------------------------------------
sub emit_C_targets {
	( my $stref ) = @_;
	print "\nEMITTING C TARGETS\n";
	for my $f ( keys %{ $stref->{'Subroutines'} } ) {
		if (
			exists $stref->{'BuildSources'}{'C'}
			{ $stref->{'Subroutines'}{$f}{'Source'} } )
		{
			emit_refactored_subroutine( $f, $targetdir, $stref, 1 );
		}
	}
}

# -----------------------------------------------------------------------------
# In fact, "preconditioning" might be the better term
sub refactor_includes {
	( my $stref ) = @_;

	for my $f ( keys %{ $stref->{'Includes'} } ) {

		if (   $stref->{'Includes'}{$f}{'Type'} eq 'Common'
			or $stref->{'Includes'}{$f}{'Type'} eq 'Parameter' )
		{
			print "\nREFACTORING INCLUDE $f\n" if $V;
			refactor_include( $f, $stref );
		}
	}
	return $stref;
}

# -----------------------------------------------------------------------------
sub refactor_include {
	( my $f, my $stref ) = @_;

	if ($V) {
		print "\n\n";
		print "#" x 80, "\n";
		print "Refactoring INC $f\n";
		print "#" x 80, "\n";
	}

	my @lines = @{ $stref->{'Includes'}{$f}{'Lines'} };
	my @info =
	  defined $stref->{'Includes'}{$f}{'Info'}
	  ? @{ $stref->{'Includes'}{$f}{'Info'} }
	  : ();
	my $annlines = [];
	for my $line (@lines) {
		my $tags = shift @info;
		push @{$annlines}, [ $line, $tags ];
	}

	my $rlines = [];
	for my $annline ( @{$annlines} ) {
		my $line      = $annline->[0] || '';
		my $tags_lref = $annline->[1];
		my %tags      = ( defined $tags_lref ) ? %{$tags_lref} : ();
		print '*** ' . join( ',', keys(%tags) ) . "\n" if $V;
		print '*** ' . $line . "\n" if $V;
		my $skip = 0;
		if ( exists $tags{'Common'} ) {
			$skip = 1;
		}
		if ( exists $tags{'VarDecl'} ) {
			my @nvars = ();
			for my $var ( @{ $annline->[1]{'VarDecl'} } ) {
				if ( $stref->{'Includes'}{$f}{'Type'} ne 'Parameter'
					and exists $stref->{'Includes'}{$f}{'ConflictingGlobals'}
					{$var} )
				{
					my $gvar =
					  $stref->{'Includes'}{$f}{'ConflictingGlobals'}{$var};
					print
"WARNING: CONFLICT in var decls in $f: renaming $var to $gvar\n"
					  if $W;
					push @nvars, $gvar;
					$line =~ s/\b$var\b/$gvar/;
				} else {
					push @nvars, $var;
				}
			}
			$annline->[1]{'VarDecl'} = [@nvars];
		}
		if ( $skip == 0 ) {

			if ( not exists $tags{'Comments'} ) {
				print $line, "\n" if $V;
				my @split_lines = split_long_line($line);
				for my $sline (@split_lines) {
					push @{ $stref->{'Includes'}{$f}{'RefactoredCode'} },
					  $sline;
				}
			} else {
				push @{ $stref->{'Includes'}{$f}{'RefactoredCode'} }, $line;
			}
		}
	}

	return $stref;

}    # refactor_include()

# -----------------------------------------------------------------------------
sub refactor_function {
	( my $f, my $stref ) = @_;
	if ($V) {
		print "\n\n";
		print "#" x 80, "\n";
		print "Refactoring $f\n";
		print "#" x 80, "\n";
	}

	print "REFACTORING FUNCTION $f\n" if $V;
	die Dumper( $stref->{'Functions'}{$f} ) if $f eq 'gser';
	my @lines = @{ $stref->{'Functions'}{$f}{'Lines'} };

	my @info =
	  defined $stref->{'Functions'}{$f}{'Info'}
	  ? @{ $stref->{'Functions'}{$f}{'Info'} }
	  : ();

	my $annlines = [];
	for my $line (@lines) {
		my $tags = shift @info;
		push @{$annlines}, [ $line, $tags ];
	}

	my $rlines = $annlines;

	if (   not exists $stref->{'Functions'}{$f}{'RefactoredCode'}
		or $stref->{'Functions'}{$f}{'RefactoredCode'} == []
		or exists $stref->{'BuildSources'}{'C'}
		{ $stref->{'Functions'}{$f}{'Source'} } )
	{
		$stref = create_refactored_source( $stref, $f, $rlines );
	}

	#   print STDERR "REFACTORED $f\n";
	#    die Dumper($stref->{'Functions'}{$f}{'RefactoredCode'}) ;
	return $stref;

}    # END of refactor_function()

# -----------------------------------------------------------------------------
sub emit_refactored_include {
	( my $f, my $dir, my $stref ) = @_;
	my $srcref = $stref->{'Includes'}{$f}{'RefactoredCode'};
	if ( defined $srcref ) {
		print "INFO: emitting refactored code for include $f\n" if $V;
		my $mode = '>';
		open my $SRC, $mode, "$dir/$f" or die $!;
		for my $line ( @{$srcref} ) {
			print $SRC "$line\n";
			print "$line\n" if $V;
		}
		close $SRC;
	}
}

# -----------------------------------------------------------------------------

sub emit_refactored_function {
	( my $f, my $dir, my $stref ) = @_;

	print "EMITTING source for FUNCTION $f\n" if $V;

	#    die Dumper($stref->{'Functions'}{$f}) if $f =~/ran3/;
	my $overwrite = 0;
	my $srcref    = $stref->{'Functions'}{$f}{'RefactoredCode'};
	my $s         = $stref->{'Functions'}{$f}{'Source'};
	if ( defined $srcref ) {
		print "INFO: emitting refactored code for function $f\n" if $V;

		#    } else {
		#    	$srcref=$stref->{'Functions'}{$f}{'Lines'};
		#    }
		my $mode = '>';
		if ( -e "$dir/$s" and not $overwrite ) {
			$mode = '>>';
		} else {
			if (    not exists $stref->{'BuildSources'}{'C'}{$s}
				and not exists $stref->{'BuildSources'}{'F'}{$s} )
			{
				$stref->{'BuildSources'}{'F'}{$s} = 1;
			}
		}
		open my $SRC, $mode, "$dir/$s" or die $!;
		if ( $mode eq '>>' ) {
			print $SRC "\nC *** FUNCTION $f ***\n";
		}
		for my $line ( @{$srcref} ) {
			print $SRC "$line\n";
			print "$line\n" if $V;
		}
		close $SRC;

	}

	#    else {
	#    	warn "NO REFACTORED CODE FOR $f\n";
	#    	warn Dumper($stref->{'Functions'}{$f}{'Lines'});
	#    }
}

# -----------------------------------------------------------------------------
sub emit_refactored_subroutine {
	( my $f, my $dir, my $stref, my $overwrite ) = @_;
	my $srcref = $stref->{'Subroutines'}{$f}{'RefactoredCode'};
	if ( defined $srcref ) {
		my $s = $stref->{'Subroutines'}{$f}{'Source'};
		print "INFO: emitting refactored code for $f in $s\n" if $V;
		if ( $s =~ /\w\/\w/ ) {

			# Source resides in subdirectory, create it if required
			my @dirs = split( /\//, $s );
			pop @dirs;
			map {
				my $targetdir = $_;
				if ( not -e $targetdir ) {
					mkdir $targetdir;
				}
			} @dirs;
		}
		my $mode = '>';
		if ( -e "$dir/$s" and not $overwrite ) {
			$mode = '>>';
		} else {
			if (    not exists $stref->{'BuildSources'}{'C'}{$s}
				and not exists $stref->{'BuildSources'}{'F'}{$s} )
			{
				$stref->{'BuildSources'}{'F'}{$s} = 1;
			}
		}
		open my $SRC, $mode, "$dir/$s" or die $!;
		if ( $mode eq '>>' ) {
			print $SRC "\nC *** SUBROUTINE $f ***\n";
		}
		for my $line ( @{$srcref} ) {
			print $SRC "$line\n";
			print "$line\n" if $V;
		}
		close $SRC;
	}
}    # END of emit_refactored_subroutine()

# -----------------------------------------------------------------------------
sub emit_all {
	( my $stref ) = @_;

	if ( not -e $targetdir ) {
		mkdir $targetdir;
		my @incs = glob('include*');
		map { copy( $_, "$targetdir/$_" ) }
		  @incs;    # Perl::Critic wants a for-loop, drat it

	} elsif ( not -d $targetdir ) {
		die "ERROR: $targetdir exists but is not a directory!\n";
	} else {
		my @oldsrcs = glob("$targetdir/*.f");
		map { unlink $_ } @oldsrcs;

		# Check if includes have changed
		my @incs = glob('include*');
		for my $inc (@incs) {
			open( my $OLD, $inc );
			binmode($OLD);
			open( my $NEW, $inc );
			binmode($NEW);
			if ( Digest::MD5->new->addfile($OLD)->hexdigest ne
				Digest::MD5->new->addfile($NEW)->hexdigest )
			{
				copy( $inc, "$targetdir/$inc" );
			}
			close $OLD;
			close $NEW;
		}
	}
	for my $f ( keys %{ $stref->{'Subroutines'} } ) {
		emit_refactored_subroutine( $f, $targetdir, $stref, 0 );
	}
	for my $f ( keys %{ $stref->{'Includes'} } ) {
		emit_refactored_include( $f, $targetdir, $stref );
	}
	for my $f ( keys %{ $stref->{'Functions'} } ) {
		emit_refactored_function( $f, $targetdir, $stref );
	}

	# NOOP source
	# Note that we always use the C source
	if ($noop) {
		copy( '../OpenCL-port/tools/noop.c', "$targetdir/noop.c" );
	}

}    # END of emit_all()

# -----------------------------------------------------------------------------

sub translate_to_C {
	( my $stref ) = @_;

# At first, all we do is get the call tree and translate all sources to C with F2C_ACC
# The next step is to fix the bugs in F2C_ACC via post-processing (later maybe actually debug F2C_ACC)
	chdir $targetdir;
	print "\n", "=" x 80, "\n" if $V;
	print "TRANSLATING TO C\n\n" if $V;
	print `pwd`                  if $V;
	foreach my $csrc ( keys %{ $stref->{'BuildSources'}{'C'} } ) {
		if ( -e $csrc ) {
			my $cmd = "../OpenCL-port/tools/f2c $csrc";
			print $cmd, "\n" if $V;
			system($cmd);
		} else {
			print "WARNING: $csrc does not exist\n" if $W;
		}
	}

# A minor problem is that we need to translate all includes contained in the tree as well
	foreach my $inc ( keys %{ $stref->{'BuildSources'}{'H'} } ) {
		my $cmd = "f2c $inc -H";
		print $cmd, "\n" if $V;
		system($cmd);
	}
	my $i = 0;
	print "\nPOSTPROCESSING C CODE\n\n";
	foreach my $csrc ( keys %{ $stref->{'BuildSources'}{'C'} } ) {
		$csrc =~ s/\.f/\.c/;
		postprocess_C( $stref, $csrc, $i );

		#	   die if $csrc=~/hanna\./;
		$i++;
	}

	# Test the generated code
	foreach my $ii ( 0 .. $i - 1 ) {
		my $cmd = 'gcc -Wall -c -I$GPU_HOME/include tmp' . $ii . '.c';
		print $cmd, "\n";
		system $cmd;
	}

}    # END of translate_to_C()

# -----------------------------------------------------------------------------
# We need a separate pass I think to get the C function signatures
# Then we need to change all array accesses used as arguments to pointers:
# a[i] => a+i
# Every arg in C must be a pointer (FORTRAN uses pass-by-ref)
# So any arg in a call that is not a pointer is wrong
# We can assume that if the arg is say v and v__G exists, then
# it should be v__G
# vdepo[FTNREF1D(i,1)] => vdepo+FTNREF1D(i,1)
#
# Next, we need to figure out which arguments can remain non-pointer scalars
# That means:
# - parse the C function signature
# - find corresponding arguments in the FORTRAN signature
# - if they are Input Scalar, don't make them pointers
# - in that case, comment out the corresponding "int v = *v__G;" line

sub postprocess_C {
	( my $stref, my $csrc, my $i ) = @_;
	print "POSTPROC $csrc\n";
	my $sub           = '';
	my $argstr        = '';
	my %params        = ();
	my %vars          = ();
	my %argvars       = ();
	my %labels        = ();
	my %input_scalars = ();

	# We need to check if this particular label is a Break
	# So we need a list of all labels per subroutine.
	my $isBreak = sub {
		( my $label ) = @_;
		return ( $labels{$label} eq 'BreakTarget'
			  || $labels{$label} eq 'NoopBreakTarget' );
	};

	my $isNoop = sub {
		( my $label ) = @_;
		return ( $labels{$label} eq 'NoopBreakTarget' );
	};

	#    my %functions = %{ $stref->{'Functions'} };

	open my $CSRC,   '<', $csrc;
	open my $PPCSRC, '>', 'tmp' . $i . '.c';    # FIXME
	my $skip = 0;

	while ( my $line = <$CSRC> ) {
		my $decl = '';
		$line =~ /^\s*void\s+(\w+)_\s+\(\s*(.*?)\s*\)\s+\{/ && do {
			$sub    = $1;
			$argstr = $2;

			my @args = split( /\s*\,\s*/, $argstr );

			%argvars = map {
				s/^\w+\s+\*?//;
				s/^F2C-ACC.*?\.\s+\*?//;
				$_ => 1;
			} @args;

			for my $i ( keys %{ $stref->{'Subroutines'}{$sub}{'Includes'} } ) {
				if ( $stref->{'Includes'}{$i}{'Type'} eq 'Parameter' ) {
					%params =
					  ( %params, %{ $stref->{'Includes'}{$i}{'Parameters'} } );
				}
			}
			%vars = %{ $stref->{'Subroutines'}{$sub}{'Vars'} };
			for my $arg (@args) {
				$arg =~ s/^\w+\s+\*//;
				$arg =~ s/^F2C-ACC.*?\.\s+\*?//;
				my $var = $arg;
				$var =~ s/__G//;
				if ( exists $vars{$var} and $vars{$var}{'Type'} ) {
					my $ftype = $vars{$var}{'Type'};
					my $ctype = toCType($ftype);
					my $iodir =
					  $stref->{'Subroutines'}{$sub}{'RefactoredArgs'}{$var}
					  {'IODir'};
					my $kind = $vars{$var}{'Kind'};

#                    print "ARG $var\n" if ( $iodir eq 'In' and $kind eq 'Scalar');
					if ( $iodir eq 'In' and $kind eq 'Scalar' ) {
						$arg = "$ctype $var";
					} else {
						$arg = "$ctype *$arg";
					}
				} else {
					die "No entry for $var in $sub\n" . Dumper(%vars);
				}
			}
			$line = "\t void ${sub}_( " . join( ',', @args ) . " ){\n";

			%labels = ();
			if ( exists $stref->{'Subroutines'}{$sub}{'Gotos'} ) {
				%labels = %{ $stref->{'Subroutines'}{$sub}{'Gotos'} };
			}
			$decl = $line;
			$decl =~ s/\{.*$/;/;
			my $hfile = "$sub.h";
			open my $INC, '>', $hfile;
			my $shield = $hfile;
			$shield =~ s/\./_/;
			$shield = '_' . uc($shield) . '_';
			print $INC '#ifndef ' . $shield . "\n";
			print $INC '#define ' . $shield . "\n";
			print $INC $decl, "\n";
			print $INC '#endif //' . $shield . "\n";
			close $INC;

			$skip = 1;
		};

		$line =~ /(\w+)=\*(\w+)__G;/ && do {
			if ( $1 eq $2 ) {
				my $var = $1;
				my $iodir =
				  $stref->{'Subroutines'}{$sub}{'RefactoredArgs'}{$var}
				  {'IODir'};
				my $kind = $vars{$var}{'Kind'};
				if ( $iodir eq 'In' and $kind eq 'Scalar' ) {
					$line =~ s|^|\/\/|;
					$input_scalars{ $var . '__G' } = $var;
				}
			}
		};
		$line =~ /F2C\-ACC\:\ Type\ not\ recognized\./ && do {
			my @chunks = split( /\,/, $line );
			for my $chunk (@chunks) {
				$chunk =~ /F2C\-ACC\:\ Type\ not\ recognized\.\ \*?(\w+)/
				  && do {
					my $var = $1;
					$var =~ s/__G//;
					if ( exists $vars{$var} and $vars{$var}{'Type'} ) {
						my $ftype = $vars{$var}{'Type'};
						my $vtype = toCType($ftype);
						$chunk =~ s/F2C\-ACC\:\ Type\ not\ recognized\./$vtype/;
					} else {
						die "No entry for $var in $sub\n" . Dumper(%vars);
					}
				  };
			}
			$line = join( ',', @chunks );
		};

		#        if ($decl ne '') {
		#        	$decl=$line;
		#                $decl=~s/\{.*$/;/;
		#                my $hfile="$sub.h";
		#               open my $INC,'>',$hfile;
		#               my $shield=$hfile;
		#               $shield=~s/\./_/;
		#               $shield='_'.uc($shield).'_';
		#               print $INC '#ifndef '.$shield."\n";
		#               print $INC '#define '.$shield."\n";
		#               print $INC $decl,"\n";
		#               print $INC '#endif //'.$shield."\n";
		#               close $INC;
		#        }
		$line =~ /F2C\-ACC\:\ xUnOp\ not\ supported\./
		  && do {    # FIXME: we assume the unitary operation is .not.
			my @chunks = split( /\,/, $line );
			for my $chunk (@chunks) {
				$chunk =~ s/F2C\-ACC\:\ xUnOp\ not\ supported\./\!/;
			}
			$line = join( ',', @chunks );

		  };
		next if $line =~ /^\s*extern\s+void\s+noop/;
		if ( $skip == 0 ) {
			if ( $line =~ /^\s*extern\s+\w+\s+(\w+)_\(/ ) {
				my $inc   = $1;
				my $hfile = $inc . '.h';

				if ( not -e $hfile ) {
					$line =~ s/^\s*extern\s+//;

					#               open my $INC,'>',$hfile;
					#               my $shield=$hfile;
					#               $shield=~s/\./_/;
					#               $shield='_'.uc($shield).'_';
					#               print $INC '#ifndef '.$shield."\n";
					#               print $INC '#define '.$shield."\n";
					#               print $INC $line;
					#               print $INC '#endif //'.$shield."\n";
					#               close $INC;
				}
				print $PPCSRC '#include "' . $hfile . '"' . "\n";
				next;
			}

			$line =~ /^\s+extern\s+\w+\s+\w+[;,]/ && do {
				$line =~ s|^|\/\/|;
			};    # because parameters are macros, not variables

			#*  float float and similar need to be removed
			$line =~ /float\s+(float|sngl|sqrt)/ && do {
				$line =~ s|^|\/\/|;
			};

			$line =~ /int\s+(int|mod)/ && do {
				$line =~ s|^|\/\/|;
			};

			$line =~ /(short|int)\s+(int2|short)/ && do {
				$line =~ s|^|\/\/|;
			};

			$line =~ /(long|int)\s+(int8|long)/ && do {
				$line =~ s|^|\/\/|;
			};
			if ( $line =~ /^\s*(?:\w+\s+)?\w+\s+(\w+);/ )
			{ # FIXME: only works for types consisting of single strings, e.g. double precision will NOT match!
				my $mf = $1;
				if (
					exists $stref->{'Subroutines'}{$sub}{'CalledFunctions'}
					{$mf} )
				{
					$line =~ s|^|\/\/|;
				}
			}
			$line =~ s/int\(/(int)(/g
			  ;    # int is a FORTRAN primitive converting float to int
			$line =~ s/(int2|short)\(/(int)(/g
			  ;    # int is a FORTRAN primitive converting float to int
			$line =~ s/(int8|long)\(/(long)(/g
			  ;    # int is a FORTRAN primitive converting float to int
			$line =~ s/float\(/(float)(/g
			  ;    # float is a FORTRAN primitive converting int to float
			$line =~ s/(dfloat|dble)\(/(double)(/g
			  ;    # dble is a FORTRAN primitive converting int to float
			$line =~ s/sngl\(/(/g
			  ;    # sngl is a FORTRAN primitive converting double to float

			$line =~ /goto\ C__(\d+):/ && do {
				my $label = $1;
				if ( $isBreak->($label) ) {
					$_ = $line;
					eval("s/goto\\ C__$label:/break/");
					$line = $_;
				} else {
					$line =~ s/C__(\d+)\:/C__$1/;
				}
			};

	 #    s/goto\ C__37:/break/; # must have a list of all gotos that are breaks
			$line =~ /^\s+C__(\d+)/ && do {
				my $label = $1;
				if ( $isNoop->($label) ) {
					$line =~ s|^|\/\/|;
				}
			};

			# Subroutine call
			$line !~ /\#define/
			  && $line =~ s/\s([\+\-\*\/\%])\s/$1/g;    # super ad-hoc!
			$line =~ /(^|^.*?\{\s)\s*(\w+)_\(\s([\+\*\,\w\(\)\[\]]+)\s\);/
			  && do {

				# We need to replace the arguments with the correct ones.
				my $maybe_if  = $1;
				my $calledsub = $2;
				my $argstr    = $3;
				my @args      = split( /\s*\,\s*/, $argstr )
				  ; # FIXME: this will split things like v1,indzindicator[FTNREF1D(i,1)],v3
				my $ii = 0;
				my $called_sub_args =
				  $stref->{'Subroutines'}{$calledsub}{'RefactoredArgs'}{'List'};
				my @nargs = ();

				for my $jj ( 1 .. scalar @{$called_sub_args} ) {
					my $arg            = shift @args;
					my $called_sub_arg = $called_sub_args->[$ii];
					$ii++;
					my $is_input_scalar =
					  ( $stref->{'Subroutines'}{$calledsub}{'Vars'}
						  {$called_sub_arg}{'Kind'} eq 'Scalar' )
					  && ( $stref->{'Subroutines'}{$calledsub}{'RefactoredArgs'}
						{$called_sub_arg}{'IODir'} eq 'In' )
					  ? 1
					  : 0;

				#        		print "CALLED SUB $calledsub ARG: $called_sub_arg\n";
				#        		my $targ=$arg;
					if ( $arg =~ /^\((\w+)\)$/ ) {
						$arg = $1;
					}

					#        		$targ=~s/[\(\)]//g;
					if ( $arg =~ /(\w+)\[/ ) {
						my $var = $1;

						# What is the type of $var?
						my %calledsubvars =
						  %{ $stref->{'Subroutines'}{$calledsub}{'Vars'} };
						my $ftype  = $calledsubvars{$called_sub_arg}{'Type'};
						my $tftype = $vars{$var}{'Type'};
						if ( $ftype ne $tftype ) {
							print
"WARNING: $tftype $var ($sub) <> $ftype $called_sub_arg ($calledsub)\n"
							  if $W;
						}
						my $ctype  = toCType($ftype);
						my $cptype = $ctype . '*';

						while ( $arg !~ /\]/ ) {
							my $targ = shift @args;

							#        			 print "TARG: $targ\t";
							$arg .= ',' . $targ;

							#        			 print $arg,"\n";
						}

						if ( not $is_input_scalar ) {
							$arg =~ s/\[/+/g;
							$arg =~ s/\]//g;
							$arg = "($cptype)($arg)";
						}

						#        		die $arg;
					}

					#        		print $arg,"\n";
					if ( exists $argvars{ $arg . '__G' } ) {

# this is an argument variable
# if the called function argument type is Input Scalar
# and the argument variable is in %input_scalars
# then don't add __G
# Still not good: the arg for the called sub must be positional! So we must get the signature and count the position ...
# which means we need to parse the source first.

# print " SUBCALL $calledsub: $called_sub_arg: $is_input_scalar:" . $stref->{'Subroutines'}{$calledsub}{'Vars'}{$called_sub_arg}{'Kind'} .','. $stref->{'Subroutines'}{$calledsub}{'RefactoredArgs'}{'IODir'}{$called_sub_arg}."\n";

						if ( not exists $input_scalars{ $arg . '__G' } ) {

							# means v__G in enclosing sub signature is a pointer
							if ( not $is_input_scalar ) {

								# means the arg of the called sub is a pointer
								$arg .= '__G';
							} else {

								# means the arg of the called sub is a scalar
								#        					$arg;
							}
						} else {

							# means v in enclosing sub signature is a scalar
							if ( not $is_input_scalar ) {
								$arg = '&' . $arg;
							}
						}
					} elsif ( exists $vars{$arg}
						and $vars{$arg}{'Kind'} ne 'Array' )
					{

						# means $arg is a Scalar
						if ( not $is_input_scalar ) {
							$arg = '&' . $arg;
						}
					}
					push @nargs, $arg;
				}
				my $nargstr = join( ',', @nargs );
				chomp $line;
				$line =~ /^\s+if/ && do {
					$line =~ s/^.*?\{//;
				};
				$line =~ s/\(.*//;
				$line .= '(' . $nargstr . ');' . "\n";
				my $close_if = ( $maybe_if =~ /if\s*\(/ ) ? '}' : '';
				$line = $maybe_if . $line . $close_if;

				#        	die $line if $calledsub=~/initialize/;
			  };

		} else {
			$skip = 0;
		}

		# VERY AD-HOC: get rid of write() statements
		$line =~ /^\s*write\(/ && do {
			$line =~ s|^|\/\/|;
		};

# fix % on float
# This is a pain: need to get the types of the operands and figure out the cases:
# int float, float int, float float
# FIXME: we assume float, float
		$line =~ s/\s+([\w\(\)]+)\s*\%\s*([\w\(\)]+)/ mod($1,$2)/;
		print $PPCSRC $line;
	}
	close $CSRC;
	close $PPCSRC;
}    # END of postprocess_C()

# -----------------------------------------------------------------------------
sub toCType {
	( my $ftype ) = @_;
	my %corr = (
		'logical'          => 'int',
		'integer'          => 'int',
		'real'             => 'float',
		'double precision' => 'double',
		'doubleprecision'  => 'double',
		'character'        => 'char'
	);
	if ( exists( $corr{$ftype} ) ) {
		return $corr{$ftype};
	} else {
		print "WARNING: NO TYPE for $ftype\n" if $W;
		return 'NOTYPE';
	}
}    # END of toCType()

# -----------------------------------------------------------------------------
sub create_build_script {
	( my $stref ) = @_;

	# FIXME: we should probe the system here!
	my @gfs = (
		'/opt/local/bin/gfortran-mp-4.6',
		'/usr/local/bin/gfortran-4.6', '/usr/bin/gfortran'
	);
	my $gfortran = 'gfortran';
	for my $mgf (@gfs) {
		if ( -e $mgf ) {
			$gfortran = $mgf;
			last;
		}
	}
	my @fsourcelst = sort keys %{ $stref->{'BuildSources'}{'F'} };
	my $fsources = join( ',', map { "'" . $_ . "'" } @fsourcelst );

	my $csources = '';
	if ($noop) {
		$stref->{'BuildSources'}{'C'}{'noop.f'} = 1;
	}
	if ( exists $stref->{'BuildSources'}{'C'} ) {
		my @csourcelst = sort keys %{ $stref->{'BuildSources'}{'C'} };
		$csources = join( ',', map { s/\.f$/.c/; "'" . $_ . "'" } @csourcelst );
	}
	my $date  = localtime;
	my $scons = <<ENDSCONS;
# Generated build script for refactored FLEXPART source code
# $date

csources =[$csources]

fsources = [$fsources]

envC=Environment(CC='gcc',CPPPATH=['/Users/wim/SoC_Research/F2C-ACC/include/']); # FIXME: use ENV
if csources:
    envC.Library('wrfc',csources)

FFLAGS  = ['-O3', '-m64', '-fconvert=little-endian', '-frecord-marker=4']
envF=Environment(FORTRAN='$gfortran',FORTRANFLAGS=FFLAGS,FORTRANPATH=['.','/opt/local/include','/usr/local/include'])
if csources:
    envF.Program('flexpart_wrf',fsources,LIBS=['netcdff','wrfc','m'],LIBPATH=['.','/opt/local/lib','/usr/local/lib'])	
else:
    envF.Program('flexpart_wrf',fsources,LIBS=['netcdff','m'],LIBPATH=['.','/opt/local/lib','/usr/local/lib'])
ENDSCONS
	open my $SC, '>', "$targetdir/SConstruct.flx_wrf";
	print $SC $scons;
	print $scons if $V;
	close $SC;

}    # END of create_build_script()

# -----------------------------------------------------------------------------
sub build_flexpart {
	system('scons -f SConstruct.flx_wrf');
}

# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------

sub parse_subroutine_and_function_calls {
	( my $f, my $stref ) = @_;
	print "PARSING SUBROUTINE/FUNCTION CALLS in $f\n" if $V;
	my $pnid = $stref->{'NId'};
	my $sub_or_func = sub_func_or_incl( $f, $stref );

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
	my $srcref = $stref->{$sub_or_func}{$f}{'Lines'};
	if ( defined $srcref ) {

		#        my %called_subs         = ();
		for my $index ( 0 .. scalar( @{$srcref} ) - 1 ) {
			my $line = $srcref->[$index];
			next if $line =~ /^C\s+/;

	  # Subroutine calls. Surprisingly, these even occur in functions! *shudder*
			if ( $line =~ /call\s(\w+)\((.*)\)/ || $line =~ /call\s(\w+)\s*$/ )
			{
				my $name = $1;
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

				$stref->{'Subroutines'}{$name}{'Called'} = 1;
				$stref->{'Subroutines'}{$name}{'Callers'}{$f}++;

				#                $called_subs{$name} = $name;
				$stref->{$sub_or_func}{$f}{'Info'}
				  ->[$index]{'SubroutineCall'}{'Args'} = $argstr;
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
				my $p       = '';
				my @argvars = ();
				for my $var (@tvars) {
					$var =~ s/^\s+//;
					$var =~ s/\s+$//;
					$var =~ s/;/,/g;
					push @argvars, $var;
				}

				$stref->{$sub_or_func}{$f}{'Info'}
				  ->[$index]{'SubroutineCall'}{'Args'} = \@argvars;
				$stref->{$sub_or_func}{$f}{'Info'}
				  ->[$index]{'SubroutineCall'}{'Name'} = $name;

				if ( exists $stref->{'Subroutines'}{$name}
					and not
					exists $stref->{$sub_or_func}{$f}{'CalledSubs'}{$name} )
				{
					$stref->{$sub_or_func}{$f}{'CalledSubs'}{$name} = 1;

					if (   not exists $stref->{'Subroutines'}{$name}{'Status'}
						or $stref->{'Subroutines'}{$name}{'Status'} < $PARSED
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
						and not
						exists $stref->{$sub_or_func}{$f}{'CalledFunctions'}
						{$chunk}
					  )
					{
						$stref->{$sub_or_func}{$f}{'CalledFunctions'}{$chunk} =
						  1;
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

		#        $stref->{$sub_or_func}{$f}{'CalledSubs'}=\%called_subs;
	}
	return $stref;
}    # END of parse_subroutine_and_function_calls()

# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# Walk the tree from the top
# For the leaf nodes, find the globals
# On the return,
# - find globals in the current sub
# - merge the globals for the just-processed sub with the current ones

sub resolve_globals {
	( my $f, my $stref ) = @_;

	#	print "RESOLVE: $f\n" if $f=~/timemanager|advance|interpol_all/;
	if ( exists $stref->{'Subroutines'}{$f}{'CalledSubs'}
		and scalar keys %{ $stref->{'Subroutines'}{$f}{'CalledSubs'} } )
	{

		# Not a leaf node, descend
		my %globs = ();

	  #		die Dumper($stref->{'Subroutines'}{$f}{'CalledSubs'}) if $f=~/advance/;
	  # Globals for $csub have been determined
		$stref = identify_globals_used_in_subroutine( $f, $stref );
		my @csubs = keys %{ $stref->{'Subroutines'}{$f}{'CalledSubs'} };
		for my $csub (@csubs) {

	   #			print "$f CALLS $csub\n" if $f =~/advance/ and $csub=~/interpol_all/;
			$stref = resolve_globals( $csub, $stref );

#			print Dumper($stref->{'Subroutines'}{$csub}{'Globals'}) if $csub=~/interpol_all/;

# Merge them with globals for $f
#			print "BEFORE:".Dumper($stref->{'Subroutines'}{$f}{'Globals'}{'includecom'}) if $f=~/advance/;
#			print "MERGE $csub INTO $f: " if $f=~/advance/;
			for my $inc (
				keys %{ $stref->{'Subroutines'}{$f}{'CommonIncludes'} } )
			{
				$stref->{'Subroutines'}{$f}{'Globals'}{$inc} = ordered_union(
					$stref->{'Subroutines'}{$f}{'Globals'}{$inc},
					$stref->{'Subroutines'}{$csub}{'Globals'}{$inc}
				);
			}

#			print Dumper($stref->{'Subroutines'}{$f}{'Globals'}{'includecom'}) if $f=~/advance/;
		}

#		  print "AFTER LOOP:".Dumper($stref->{'Subroutines'}{$f}{'Globals'}{'includecom'}) if $f=~/advance/;
	} else {

		# Leaf node, find globals
		print "SUB $f is LEAF\n" if $V;
		$stref = identify_globals_used_in_subroutine( $f, $stref );
	}

	#	if ($f=~/flexpart_wrf/) {

	#	print Dumper(keys %{ $stref->{'Subroutines'}{$f}{'Globals'} });
	for my $inc ( keys %{ $stref->{'Subroutines'}{$f}{'Includes'} } ) {
		if ( $stref->{'Includes'}{$inc}{'Type'} eq 'Parameter' ) {

# So now I have to see if there are any conflicts between parameters and ex-globals
			for
			  my $commoninc ( keys %{ $stref->{'Subroutines'}{$f}{'Globals'} } )
			{
				for my $mpar (
					@{ $stref->{'Subroutines'}{$f}{'Globals'}{$commoninc} } )
				{
					if ( exists $stref->{'Includes'}{$inc}{'Vars'}{$mpar} ) {
						print
"WARNNG: $mpar from $inc conflicts with $mpar from $commoninc\n"
						  if $V;
						$stref->{'Subroutines'}{$f}{'ConflictingGlobals'}
						  {$mpar} = $mpar . '_GLOB';
						$stref->{'Includes'}{$commoninc}{'ConflictingGlobals'}
						  {$mpar} = $mpar . '_GLOB';
						$stref->{'Includes'}{$inc}{'ConflictingGlobals'}
						  {$mpar} = $mpar . '_GLOB';
					}
				}
			}
		}
	}

  #    die Dumper($stref->{'Subroutines'}{$f}{'Globals'}) if $f=~/flexpart_wrf/;
  #    }
	$stref->{'Subroutines'}{$f}{'ConflictingParams'} = {};
	for my $inc ( keys %{ $stref->{'Subroutines'}{$f}{'Includes'} } ) {
		if ( $stref->{'Includes'}{$inc}{'Type'} eq 'Parameter' ) {
			if ( exists $stref->{'Includes'}{$inc}{'ConflictingGlobals'} ) {
				%{ $stref->{'Subroutines'}{$f}{'ConflictingParams'} } = (
					%{ $stref->{'Subroutines'}{$f}{'ConflictingParams'} },
					%{ $stref->{'Includes'}{$inc}{'ConflictingGlobals'} }
				);
			}
		}
	}
	return $stref;
}    # END of resolve_globals()

# ----------------------------------------------------------------------------------------------------
sub identify_globals_used_in_subroutine {
	( my $f, my $stref ) = @_;

	#	local $V=1 if $f=~/interpol/;
	#	warn "GLOBALS in $f\n";
	my $srcref = $stref->{'Subroutines'}{$f}{'Lines'};
	if ( defined $srcref ) {

		# First determine subroutine arguments
		for my $index ( 0 .. scalar( @{$srcref} ) - 1 ) {
			my $line = $srcref->[$index];
			if ( $line =~ /^C\s+/ ) {
				next;
			}

			# Determine the subroutine arguments
			if ( $line =~ /^\s+subroutine\s+(\w+)\s*\((.*)\)/ ) {
				my $name   = $1;
				my $argstr = $2;

				#                    warn "FOUND SUB SIG $name WITH $argstr\n";
				$argstr =~ s/^\s+//;
				$argstr =~ s/\s+$//;

				#                   my @args=();
				my @args = split( /\s*,\s*/, $argstr );

				#                    warn "ARGS: ".join(',',@args)."\n";
				$stref->{'Subroutines'}{$f}{'Info'}
				  ->[$index]{'Signature'}{'Args'} = [@args];
				$stref->{'Subroutines'}{$f}{'Info'}
				  ->[$index]{'Signature'}{'Name'} = $name;
				$stref->{'Subroutines'}{$f}{'Args'} = [@args];

#                    die Dumper($stref->{'Subroutines'}{$f}{'Args'}) if $name eq 'ij_to_latlon';
				last;
			} elsif ( $line =~ /^\s+subroutine\s+(\w+)[^\(]*$/ ) {
				my $name = $1;
				$stref->{'Subroutines'}{$f}{'Info'}
				  ->[$index]{'Signature'}{'Args'} = [];
				my $has_var_decls =
				  scalar %{ $stref->{'Subroutines'}{$f}{'Vars'} };
				if ( not $has_var_decls ) {
					print "INFO: $f has no arguments and no local var decls\n"
					  if $V;
					if ( exists $stref->{'Subroutines'}{$f}{'ImplicitNone'} ) {
						print "INFO: $f has 'implicit none'\n" if $V;
						my $idx =
						  $stref->{'Subroutines'}{$f}{'ImplicitNone'} + 1;
						$stref->{'Subroutines'}{$f}{'Info'}
						  ->[$idx]{'ExGlobVarDecls'} = {};
					} else {
						$stref->{'Subroutines'}{$f}{'Info'}
						  ->[$index]{'ExGlobVarDecls'} = {};
					}
				}
				$stref->{'Subroutines'}{$f}{'Info'}
				  ->[$index]{'Signature'}{'Name'} = $name;
				$stref->{'Subroutines'}{$f}{'Args'} = [];
				last;
			}

			# Determine the program arguments
			# FIXME: Not sure why this is done here?
			if ( $line =~ /^\s+program\s+(\w+)\s*$/ ) {
				my $name = $1;
				$stref->{'Subroutines'}{$f}{'Info'}
				  ->[$index]{'Signature'}{'Args'} = [];
				$stref->{'Subroutines'}{$f}{'Info'}
				  ->[$index]{'Signature'}{'Name'} = $name;
				last;
			}
		}    # for each line

		my %commons = ();
		print "COMMONS ANALYSIS in $f\n" if $V;
		if ( not exists $stref->{'Subroutines'}{$f}{'Commons'} ) {
			for my $inc (
				keys %{ $stref->{'Subroutines'}{$f}{'CommonIncludes'} } )
			{
				print "COMMONS from $inc in $f? " if $V;
				$commons{$inc} = $stref->{'Includes'}{$inc}{'Commons'};
			}
			$stref->{'Subroutines'}{$f}{'Commons'}    = \%commons;
			$stref->{'Subroutines'}{$f}{'HasCommons'} = 1;
		} else {
			print "already done\n" if $V;
			%commons = %{ $stref->{'Subroutines'}{$f}{'Commons'} };
		}
		my $first = 1;
		for my $inc ( keys %{ $stref->{'Subroutines'}{$f}{'CommonIncludes'} } )
		{
			print "\nGLOBAL VAR ANALYSIS for $inc in $f\n" if $V;
			my @globs = ();
			my %tvars = %{ $commons{$inc} };
			for my $index ( 0 .. scalar( @{$srcref} ) - 1 ) {
				my $line = $srcref->[$index];
				if ( $line =~ /^C\s+/ ) {
					next;
				}

				if ( $line =~ /^\s+(subroutine|program)\s+(\w+)/ ) {
					next;
				}

				# We shouldn't look for globals in the declarations, silly!
				if ( $line =~
/(logical|integer|real|double\s+precision|character|character\*?(?:\d+|\(\*\)))\s+(.+)\s*$/
				  )
				{
					next;
				}

				my @chunks = split( /\W+/, $line );
				for my $mvar (@chunks) {

#				next if $mvar =~/\b(?:if|then|do|goto|integer|real|call|\d+)\b/; # is slower!
# if a var on a line is declared locally, it is obviously not a global!
					if ( exists $tvars{$mvar}
						and not $stref->{'Subroutines'}{$f}{'Vars'}{$mvar} )
					{
						my $is_par = 0;

						for my $inc (
							keys %{ $stref->{'Subroutines'}{$f}{'Includes'} } )
						{
							if ( $stref->{'Includes'}{$inc}{'Type'} eq
								'Parameter' )
							{
								if (
									exists $stref->{'Includes'}{$inc}{'Vars'}
									{$mvar} )
								{
									print
"WARNING: $mvar in $f is a PARAMETER from $inc!\n"
									  if $W;
									$is_par = 1;
									last;
								}
							}
						}
						if ( not $is_par ) {
							print "FOUND global $mvar in $line\n" if $V;
							push @globs, $mvar;
							delete $tvars{$mvar};
						}
					}
				}
			}    # for each line
			if ($V) {
				print "\nGLOBAL VARS from $inc in subroutine $f:\n\n";
				for my $var (@globs) {
					print "$var\n";
				}
				print "\n";
			}
			$stref->{'Subroutines'}{$f}{'Globals'}{$inc} = \@globs;
			$first = 0;
		}
	}

	#	die Dumper($stref->{'Subroutines'}{$f}{'Globals'}) if $f=~/interpol_all/;
	return $stref;
}    # END of identify_globals_used_in_subroutine()

# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# We do a recusive descent for all called subroutines, and for the leaves we do the analysis
sub determine_argument_io_direction_rec {
	( my $f, my $stref ) = @_;

	#    my $srcref = $stref->{'Subroutines'}{$f}{'Lines'};
	if ( exists $stref->{'Subroutines'}{$f}{'CalledSubs'} ) {
		for
		  my $calledsub ( keys %{ $stref->{'Subroutines'}{$f}{'CalledSubs'} } )
		{
			$stref = determine_argument_io_direction_rec( $calledsub, $stref );
		}
	}

#    $stref=determine_argument_io_direction_rec_core($f,$stref);
# For a leaf, this should resolve all
# For a non-leaf, we should merge the declarations from the calls
# This is more tricky than it seems because a sub can be called multiple times with different arguments.
# So first we need to determine the argument of the call, then map them to the arguments of the sub
	$stref = refactor_subroutine_signature( $stref, $f );
	$stref = determine_argument_io_direction_core( $stref, $f );

	return $stref;
}    # determine_argument_io_direction_rec()

# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
sub get_iodirs_from_subcall {
	( my $stref, my $f, my $index ) = @_;

	# First refactor!
	$stref = refactor_subroutine_call_args( $stref, $f, $index );
	my $tags = $stref->{'Subroutines'}{$f}{'Info'}->[$index];
	my $name = $tags->{'SubroutineCall'}{'Name'};
	my %args =
	  map { $_ => 1 }
	  @{ $stref->{'Subroutines'}{$f}{'RefactoredArgs'}{'List'} };
	my $called_arg_iodirs = {};

	# Now get the RefactoredArgs
	my $ref_call_args =
	  $stref->{'Subroutines'}{$f}{'Info'}
	  ->[$index]{'SubroutineCall'}{'RefactoredArgs'};

#                print "CALL to $name in $f\n";#" (".join(',',@{ $stref->{'Subroutines'}{$f}{'RefactoredArgs'}{'List'} }).")\n";
#               print "CALL $name: ",join(',',@{ $ref_call_args })."\n";
# Get the RefactoredArgList
	my $ref_sig_args = $stref->{'Subroutines'}{$name}{'RefactoredArgs'}{'List'};

	#               print " SIG $name: ",join(',',@{ $ref_sig_args })."\n";
	my $ca = scalar( @{$ref_call_args} );
	my $sa = scalar( @{$ref_sig_args} );
	if ( $ca != $sa ) {
		print "WARNING: NOT SAME LENGTH! ($ca<>$sa)\n" if $W;
		die;
	} else {
		my $i = 0;
		for my $call_arg ( @{$ref_call_args} ) {
			my $sig_arg = $ref_sig_args->[$i];

			# int is a FORTRAN primitive converting float to int
			# int2|short is a FORTRAN primitive converting float to int
			# int8|long is a FORTRAN primitive converting float to int
			# float is a FORTRAN primitive converting int to float
			# dfloat|dble is a FORTRAN primitive converting int to float
			# sngl is a FORTRAN primitive converting double to float
			$call_arg =~
			  s/(^|\W)(?:int|int2|int8|short|long|sngl|dfloat|dble|float)\(//
			  && $call_arg =~ s/\)$//;

			# Clean up call args for comparison
			$call_arg =~ s/(\w+)\(.*?\)/$1/g;
			$i++;
			if ( exists $args{$call_arg} ) {

				# This means that $call_arg is an argument of the caller $f
				# look up the IO direction for the corresponding $sig_arg
				$called_arg_iodirs->{$call_arg} =
				  $stref->{'Subroutines'}{$name}{'RefactoredArgs'}{$sig_arg}
				  {'IODir'};
			} else {
				if ( $call_arg =~ /\W/ ) {
					print
"INFO: ARG $call_arg in call to $name in $f is an expression\n"
					  if $V;
					my @maybe_args = split( /\W+/, $call_arg );
					for my $maybe_arg (@maybe_args) {
						if ( exists $args{$maybe_arg}
							and not exists $called_arg_iodirs->{$maybe_arg} )
						{
							print
"INFO: Setting IO dir for $maybe_arg in call to $name in $f to In\n"
							  if $V;
							$called_arg_iodirs->{$maybe_arg} = 'In';
							if (
								scalar keys
								%{ $stref->{'Subroutines'}{$name}{'Callers'} }
								== 1
								and
								$stref->{'Subroutines'}{$name}{'Callers'}{$f} ==
								1
								and
								$stref->{'Subroutines'}{$name}{'RefactoredArgs'}
								{$sig_arg}{'IODir'} ne 'In' )
							{
								print
"INFO: $name in $f is called only once; $sig_arg is an expression, setting IODir to 'In'\n"
								  if $I;
								$stref->{'Subroutines'}{$name}{'RefactoredArgs'}
								  {$sig_arg}{'IODir'} = 'In';
							}
						}
					}
				} elsif ( $call_arg =~ /^\s*[\d\.]+\s*$/ ) {
					if (
						scalar
						keys %{ $stref->{'Subroutines'}{$name}{'Callers'} } == 1
						and $stref->{'Subroutines'}{$name}{'Callers'}{$f} == 1
						and $stref->{'Subroutines'}{$name}{'RefactoredArgs'}
						{$sig_arg}{'IODir'} ne 'In' )
					{
						print
"INFO: $name in $f is called only once; $sig_arg is a numeric constant, setting IODir to 'In'\n"
						  if $I;
						$stref->{'Subroutines'}{$name}{'RefactoredArgs'}
						  {$sig_arg}{'IODir'} = 'In';
					}
				} else {

				   # This means the call argument must be a local variable of $f
				   #					print "LOCAL $call_arg for call to $name in $f\n";
					$called_arg_iodirs->{$call_arg} =
					  $stref->{'Subroutines'}{$name}{'RefactoredArgs'}{$sig_arg}
					  {'IODir'};
					if ( $called_arg_iodirs->{$call_arg} eq 'InOut' ) {
						$called_arg_iodirs->{$call_arg} = 'InMaybeOut';
					}

				}
			}
		}
	}
	return ( $called_arg_iodirs, $stref );
}    # END of get_iodirs_from_subcall()

# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
sub determine_argument_io_direction_core {
	( my $stref, my $f ) = @_;
	my $srcref  = $stref->{'Subroutines'}{$f}{'Lines'};
	my $tagsref = $stref->{'Subroutines'}{$f}{'Info'};

	#   local $V=1 if $f=~/advance/;
	print "DETERMINE IO DIR FOR SUB $f\n" if $V;
	my $ref_sig_args    = $stref->{'Subroutines'}{$f}{'RefactoredArgs'}{'List'};
	my %args            = map { $_ => 'Unknown' } @{$ref_sig_args};
	my $called_sub_args = {};
	my $called_sub      = "";

	# Then for each of these, we go through the args.
	# If an arg has a non-'U' value, we overwrite it.

	if ( defined $srcref ) {
		for my $index ( 0 .. scalar( @{$srcref} ) - 1 ) {
			my $line = $srcref->[$index];

			my $tags = $tagsref->[$index];
			if ( $line =~ /^C\s+/ ) {
				next;
			}

			# Skip the declarations
			if ( exists $tags->{'VarDecl'} ) { next; }

			# Write & File open statements
			if ( $line =~ /^\s+(?:write|open)\s*\(\s*(.+)$/ ) {
				find_vars( $1, \%args, \&set_io_dir );
				for my $csub ( keys %{$called_sub_args} ) {
					if ( %{ $called_sub_args->{$csub} } ) {
						find_vars( $1, $called_sub_args->{$csub},
							\&set_io_dir );
					}
				}

			}
			if ( exists $tags->{'SubroutineCall'} ) {
				my $name = $tags->{'SubroutineCall'}{'Name'};

#						print "\n\nLINE:$line\n";
#						print "CALLING $name:\n",join(',',@{ $stref->{'Subroutines'}{$name}{'RefactoredArgs'}{'List'} }),"\n\n";
				( my $iodirs, $stref ) =
				  get_iodirs_from_subcall( $stref, $f, $index );
				for my $var ( keys %{$iodirs} ) {
					if ( exists $args{$var} ) {
						if ( $iodirs->{$var} eq 'In' ) {
							if ( $args{$var} eq 'Unknown' ) {
								$args{$var} = 'In';
							} elsif ( $args{$var} eq 'Out' ) {

	   # if the parent arg is Out and the child arg is In, parent arg stays Out!
								$args{$var} = 'Out';
							}
						} elsif ( $iodirs->{$var} eq 'InOut' ) {
							if ( $args{$var} eq 'Unknown' ) {
								$args{$var} = 'InOut';
							} elsif ( $args{$var} eq 'Out' ) {
								$args{$var} = 'Out';
							}
						} elsif ( $iodirs->{$var} eq 'Out' ) {
							if ( $args{$var} eq 'Unknown' ) {
								$args{$var} = 'Out';
							} elsif ( $args{$var} eq 'In' ) {
								$args{$var} = 'InOut';
							}
						} else {
							print
"WARNING: IO direction for $var in call to $name in $f is Unknown\n"
							  if $W;
						}
					} else {

						#								print "$var is LOCAL".$iodirs->{$var}."\n";
					}
				}
				if (
					scalar
					keys %{ $stref->{'Subroutines'}{$name}{'Callers'} } == 1
					and $stref->{'Subroutines'}{$name}{'Callers'}{$f} == 1 )
				{
					$called_sub = $name;
				} else {
					$called_sub = "";
				}
				if ( $line =~ /^\s*if\s*\((.+)\)\s+call\s+/ ) {
					my $cond = $1;
					$cond =~ s/[\(\)]+//g;
					$cond =~ s/\.(eq|ne|gt|ge|lt|le|and|or|not|eqv|neqv)\./ /;
					find_vars( $cond, \%args, \&set_io_dir );
					for my $csub ( keys %{$called_sub_args} ) {
						if ( %{ $called_sub_args->{$csub} } ) {
							find_vars( $cond, $called_sub_args->{$csub},
								\&set_io_dir );
						}
					}
				}
				if ( $called_sub ne "" ) {
					$called_sub_args->{$called_sub} = $iodirs;
				}
				next;
			}

			# Encounter Assignment
			if (    $line =~ /\s+(\w+)(?:\([^=]*\))?\s*=\s*(.+?)\s*$/
				and $line !~ /^\s*do\s+.+\s*=/ )
			{    # Assignment, but not a loop. FIXME: This is weak!
				my $var = $1;
				my $rhs = $2;
				if ( exists $args{$var} ) {

					if ( $args{$var} eq 'Unknown' ) {
						print "LINE: $line\n"     if $V;
						print "ARG $var: 'Out'\n" if $V;
						$args{$var} = 'Out';
					} elsif ( $args{$var} eq 'In' ) {
						print "LINE: $line\n"       if $V;
						print "ARG $var: 'InOut'\n" if $V;
						$args{$var} = 'InOut';
					}
				}
				if ( $line =~ /^\s*if/ ) {
					( my $cond, my $rest ) =
					  split( /\s+(\w+)(?:\([^=]*\))?\s*=\s*/, $line );
					find_vars( $cond, \%args, \&set_io_dir );
					for my $csub ( keys %{$called_sub_args} ) {
						if ( %{ $called_sub_args->{$csub} } ) {
							find_vars( $cond, $called_sub_args->{$csub},
								\&set_io_dir );
						}
					}

				}
				find_vars( $rhs, \%args, \&set_io_dir );
				for my $csub ( keys %{$called_sub_args} ) {
					if ( %{ $called_sub_args->{$csub} } ) {
						find_vars( $rhs, $called_sub_args->{$csub},
							\&set_io_dir );
					}
				}

			} else {    # not an assignment, do as before
				print "LINE: $line\n" if $V;
				find_vars( $line, \%args, \&set_io_dir );
				for my $csub ( keys %{$called_sub_args} ) {
					if ( %{ $called_sub_args->{$csub} } ) {
						find_vars( $line, $called_sub_args->{$csub},
							\&set_io_dir );
					}
				}

			}
		}
	}
	for my $csub ( keys %{$called_sub_args} ) {
		for my $arg ( keys %{ $called_sub_args->{$csub} } ) {
			if ( $called_sub_args->{$csub}{$arg} eq 'InMaybeOut' ) {

		 #	      			print "ARG $arg for call to $csub in $f is actually 'In'\n";
		 #	      			$called_sub_args->{$csub}{$arg}='In';
				$stref->{'Subroutines'}{$csub}{'RefactoredArgs'}{$arg}
				  {'IODir'} = 'In';
			}
		}
	}

	( my $maybe_args, my $globals ) = get_maybe_args_globs( $stref, $f );
	for my $arg ( keys %args ) {
		$stref->{'Subroutines'}{$f}{'RefactoredArgs'}{$arg}{'IODir'} =
		  $args{$arg};
		my $kind = 'Unknown';
		my $type = 'Unknown';
		my $shape = [];
		if ( exists $maybe_args->{$arg}{'Type'} ) {
			$kind = $maybe_args->{$arg}{'Kind'};
			$type = $maybe_args->{$arg}{'Type'};
			$shape = $maybe_args->{$arg}{'Shape'};
		} else {
			print "WARNING: No kind/type info for $arg in $f\n" if $W;
		}

		$stref->{'Subroutines'}{$f}{'RefactoredArgs'}{$arg}{'Kind'} = $kind;
		$stref->{'Subroutines'}{$f}{'RefactoredArgs'}{$arg}{'Type'} = $type;
		$stref->{'Subroutines'}{$f}{'RefactoredArgs'}{$arg}{'Shape'} = $shape;
	}
	$stref = remap_args( $stref, $f ); # FIXME: I don't think this should be here
	$stref = reshape_args( $stref, $f ); # FIXME: I don't think this should be here
	return $stref;
}    # determine_argument_io_direction_core()

# -----------------------------------------------------------------------------
# To determine if a subroutine argument is I, O or IO:
# if it appears only on the LHS of an '=' => O
# if does not appear on the LHS of an '=' => I
# otherwise => IO
# So start by setting them all to 'I'
# so, look for '=' and split in LHS/RHS

# -----------------------------------------------------------------------------
# This function works on RHS variables, i.e. variables being read
# The rules are
# Read =>
#   Unknown => In
#   Out => InOut
# Write =>
#   Out
sub set_io_dir {
	( my $mvar, my $args_ref ) = @_;
	if ( $args_ref->{$mvar} eq 'Out' or $args_ref->{$mvar} eq 'InMaybeOut' ) {
		print "FOUND InOut ARG $mvar\n" if $V;

		#				warn "$mvar is InMaybeOut\n";
		$args_ref->{$mvar} = 'InOut';
	} elsif ( $args_ref->{$mvar} eq 'Unknown' ) {
		print "FOUND In ARG $mvar\n" if $V;
		$args_ref->{$mvar} = 'In';
	}
	return $args_ref;
}

# -----------------------------------------------------------------------------
sub find_vars {
	( my $line, my $args_ref, my $subref ) = @_;
	my %args = %{$args_ref};
	my @chunks = split( /\W+/, $line );
	for my $mvar (@chunks) {
		if ( exists $args{$mvar} ) {
			$args_ref = $subref->( $mvar, $args_ref );
		}
	}
	return $args_ref;
}    # END of find_vars()

# -----------------------------------------------------------------------------
sub detect_blocks {
	( my $s, my $stref ) = @_;
	print "CHECKING BLOCKS in $s\n" if $V;
	my $sub_func_incl = sub_func_or_incl( $s, $stref );
	$stref->{$sub_func_incl}{$s}{'HasBlocks'} = 0;
	my $srcref = $stref->{$sub_func_incl}{$s}{'Lines'};
	for my $line ( @{$srcref} ) {
		if ( $line =~ /^C\s/i ) {
			if ( $line =~ /^C\s+BEGIN\sSUBROUTINE\s(\w+)/ ) {
				$stref->{$sub_func_incl}{$s}{'HasBlocks'} = 1;
				my $tgt = uc( substr( $sub_func_incl, 0, 3 ) );

				#				warn "$tgt $s HAS BLOCK: $1\n" if $V;
				print "$tgt $s HAS BLOCK: $1\n" if $V;
				last;
			}
		}
	}
	return $stref;
}    # END of detect_blocks()

# -----------------------------------------------------------------------------
#		sub create_subroutine_source_from_block_OLD {
#			( my $f, my $p, my $stref ) = @_;
#			print "CREATING SOURCE for $f\n" if $V;
#
#			#        print STDERR "KEYS in $p\n";
#			#        for my $k (sort keys %{$stref->{'Subroutines'}{$p}}) {
#			#        	print STDERR "$k\n";
#			#        };
#
#			my @lines = @{ $stref->{'Subroutines'}{$p}{'Blocks'}{$f}{'Lines'} };
#			my @info  = @{ $stref->{'Subroutines'}{$p}{'Blocks'}{$f}{'Info'} };
#
#			#	    my $annlines = [];
#			my $index = 0;
#
#			my $rlines = [];
#			push @{$rlines}, $stref->{'Subroutines'}{$p}{'Blocks'}{$f}{'Sig'};
#			$stref->{'Subroutines'}{$f}{'Info'}->[$index]{'Signature'}{'Name'} =
#			  $f;
#			$stref->{'Subroutines'}{$f}{'Info'}->[$index]{'Signature'}{'Args'} =
#			  $stref->{'Subroutines'}{$p}{'Blocks'}{$f}{'Args'};
#			$index++;
#			for my $inc (
#				keys %{ $stref->{'Subroutines'}{$p}{'Blocks'}{$f}{'Includes'} }
#			  )
#			{
#				push @{$rlines}, "        include '$inc'";
#				$stref->{'Subroutines'}{$f}{'Info'}
#				  ->[$index]{'Include'}{'Name'} = $inc;
#				$index++;
#			}
#			my $first = 1;
#			for my $decl (
#				@{ $stref->{'Subroutines'}{$p}{'Blocks'}{$f}{'Decls'} } )
#			{
#				my $var =
#				  shift @{ $stref->{'Subroutines'}{$p}{'Blocks'}{$f}{'Args'} };
#				push @{$rlines}, "  $decl";
#				if ( $first == 1 ) {
#					$stref->{'Subroutines'}{$f}{'Info'}
#					  ->[$index]{'ExGlobVarDecls'} = {};
#					$first = 0;
#				}
#				$stref->{'Subroutines'}{$f}{'Info'}->[$index]{'VarDecl'} =
#				  [$var];
#				$index++;
#			}
#			for my $line (@lines) {
#				push @{$rlines}, $line;
#				my $tags_lref = shift @info;
#				$stref->{'Subroutines'}{$f}{'Info'}->[$index] = $tags_lref;
#				$index++;
#			}
#			push @{$rlines}, '      end';
#			$stref->{'Subroutines'}{$f}{'Lines'}        = $rlines;
#			$stref->{'Subroutines'}{$f}{'Status'}       = $FROM_BLOCK;
#			$stref->{'Subroutines'}{$f}{'HasBlocks'}    = 0;
#			$stref->{'Subroutines'}{$f}{'Program'}      = 0;
#			$stref->{'Subroutines'}{$f}{'StringConsts'} =
#			  $stref->{'Subroutines'}{$p}{'StringConsts'};
#			my $extract_sub_src = $stref->{'Subroutines'}{$p}{'Source'};
#			$extract_sub_src =~ s/\.f$//;
#			$extract_sub_src .= "_$f.f";
#			$stref->{'Subroutines'}{$f}{'Source'} = $extract_sub_src;
#
#			if ($V) {
#				@lines = @{ $stref->{'Subroutines'}{$f}{'Lines'} };
#				@info  = @{ $stref->{'Subroutines'}{$f}{'Info'} };
#				my $annlines = [];
#				for my $line (@lines) {
#					my $tags = shift @info;
#					push @{$annlines}, [ $line, $tags ];
#				}
#				for my $annline ( @{$annlines} ) {
#					my $line      = $annline->[0] || '';
#					my $tags_lref = $annline->[1];
#					my %tags      = ( defined $tags_lref ) ? %{$tags_lref} : ();
#					print '*** ' . join( ',', keys(%tags) ) . "\n" if $V;
#					print '*** ' . $line . "\n" if $V;
#				}
#			}
#
#			#         print STDERR "KEYS in $f\n";
#			#        for my $k (sort keys %{$stref->{'Subroutines'}{$f}}) {
#			#            print STDERR "$k\n";
#			#        };
#
#			return $stref;
#		}    # END of create_subroutine_source_from_block_OLD()

# -----------------------------------------------------------------------------
# For every 'include' statement in a subroutine (and I assume functions don't have includes, don't be evil!)
# the filename is entered in 'Includes' and in Info->[$index]{'Include'}
# If the include was not yet read, do it now.
sub parse_includes {
	( my $f, my $stref ) = @_;
	print "PARSING INCLUDES for $f\n" if $V;
	my $sub_or_func = sub_func_or_incl( $f, $stref );

	my $srcref = $stref->{$sub_or_func}{$f}{'Lines'};
	for my $index ( 0 .. scalar( @{$srcref} ) - 1 ) {
		my $line = $srcref->[$index];
		if ( $line =~ /^C\s+/ or $line =~ /^\!\s/ ) {
			next;
		}

		if ( $line =~ /^\s*include\s+\'(\w+)\'/ )
		{    # TODO: nested includes not supported!

			my $name = $1;
			print "FOUND include $name in $f\n" if $V;
			$stref->{$sub_or_func}{$f}{'Includes'}{$name} = $index;
			$stref->{$sub_or_func}{$f}{'Info'}->[$index]{'Include'}{'Name'} =
			  $name;
			if ( $stref->{'Includes'}{$name}{'Status'} == $UNREAD ) {
				print $line, "\n" if $V;

				# Initial guess for Root. OK? FIXME?
				$stref->{'Includes'}{$name}{'Root'}      = $f;
				$stref->{'Includes'}{$name}{'HasBlocks'} = 0;
				$stref = parse_fortran_src( $name, $stref );
			} else {
				print $line, " already processed\n" if $V;
			}
		}
	}

	return $stref;
}    # END of parse_includes()

# -----------------------------------------------------------------------------
# Create a table of all variables declared in the target, and a list of all the var names occuring on each line.
# We record the type of the var and whether it's a scalar or array, because we need that information for translation to C.
# Also check if the variable happens to be a function. If that is the case, mark that function as 'Called'; if we have not yet parsed its source, do it now.

sub get_var_decls {
	( my $f, my $stref ) = @_;

	my $is_incl = exists $stref->{'Includes'}{$f} ? 1 : 0;

	#			my $sub_or_incl = $is_incl ? 'Includes' : 'Subroutines';
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

				#            	print "INFO: $f has 'implicit none'\n";
				$stref->{$sub_func_incl}{$f}{'Info'}->[$index]{'ImplicitNone'} =
				  {};
				$stref->{$sub_func_incl}{$f}{'ImplicitNone'} = $index;
			}
			if ( $line =~
/(logical|integer|real|double\s+precision|character|character\*?(?:\d+|\(\*\)))\s+(.+)\s*$/
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
					my $tvar = $var;					
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
					
                    if ($tvar =~ /\(.*?\)/ && $tvar !~/\(0\)/) {
                            die "FATAL ERROR: $tvar shouln't look like this!";
                    }
					
					if ( $tvar =~ s/\(0\)// ) { # remove (0) placeholder 
															
						$tvar =~ s/\*\d+//
						  ;    # FIXME: char string handling is not correct!
						  # remove *number from the type, this is wrong. The right thing is to replace
						  # this notation with type(number)
						  # Also, this is not limited to arrays, we could have e.g. integer v*4  
						$vars{$tvar}{'Kind'}  = 'Array';
						$vars{$tvar}{'Shape'} = [@shape];
						$p                    = '()';
					} else {
						$vars{$tvar}{'Kind'} = 'Scalar';
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
							$stref = read_fortran_src( $tvar, $stref );
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

	#			die "FIXME: shapes not correct!";
	return $stref;
}    # END of get_var_decls()

# -----------------------------------------------------------------------------

sub get_commons_params_from_includes {
	( my $f, my $stref ) = @_;
	my $srcref = $stref->{'Includes'}{$f}{'Lines'};
	if ( defined $srcref ) {

		#		warn "GETTING COMMONS/PARAMS from INCLUDE $f\n";
		my %vars        = %{ $stref->{'Includes'}{$f}{'Vars'} };
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
						$stref->{'Includes'}{$f}{'Commons'}{$var} = $vars{$var};
					}
				}
				$stref->{'Includes'}{$f}{'Info'}->[$index]{'Common'} = {};
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
						$stref->{'Includes'}{$f}{'Parameters'}{$var} =
						  $vars{$var};
					}
				}
				$stref->{'Includes'}{$f}{'Info'}->[$index]{'Parameter'} = {};
			}
		}

		if ($V) {
			print "\nCOMMONS for $f:\n\n";
			for my $v ( sort keys %{ $stref->{'Includes'}{$f}{'Commons'} } ) {
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
			$stref->{'Includes'}{$f}{'Type'} = 'Common';
		} elsif ($has_pars) {
			$stref->{'Includes'}{$f}{'Type'} = 'Parameter';
		} else {
			$stref->{'Includes'}{$f}{'Type'} = 'None';
		}
		for my $var ( keys %vars ) {
			if (
				(
					$has_pars
					and not
					exists( $stref->{'Includes'}{$f}{'Parameters'}{$var} )
				)
				or ( $has_commons
					and not exists( $stref->{'Includes'}{$f}{'Commons'}{$var} )
				)
			  )
			{
				warn Dumper( $stref->{'Includes'}{$f}{'Lines'} );
				die
"The include $f contains a variable $var that is neither a parameter nor a common variable, this is not supported\n";
			}
		}
	}
	return $stref;
}    # END of get_commons_params_from_includes()

# -----------------------------------------------------------------------------
sub separate_blocks {
	( my $f, my $stref ) = @_;

#    die "separate_blocks(): FIXME: we need to add in the locals from the parent subroutine as locals in the new subroutine!";
	my $sub_or_func = sub_func_or_incl( $f, $stref );
	my $srcref      = $stref->{$sub_or_func}{$f}{'Lines'};
	my %vars        = %{ $stref->{$sub_or_func}{$f}{'Vars'} };
	my %occs        = ();
	my %blocks      = ();
	my $in_block    = 0;
	my $block       = 'OUTER';
	$blocks{'OUTER'} = { 'Lines' => [] };
	my $block_idx = 0;

	for my $index ( 0 .. scalar( @{$srcref} ) - 1 ) {
		my $line = $srcref->[$index];

		if ( $line =~ /^C\s+BEGIN\sSUBROUTINE\s(\w+)/ ) {
			$in_block = 1;
			$block    = $1;
			print "FOUND BLOCK $block\n" if $V;

			#push @{ $blocks{'OUTER'}{'Lines'} }, $line;
			$stref->{$sub_or_func}{$f}{'Info'}
			  ->[$index]{'RefactoredSubroutineCall'}{'Name'} = $block;
			delete $stref->{$sub_or_func}{$f}{'Info'}->[$index]{'Comments'};
			$stref->{$sub_or_func}{$f}{'Info'}->[$index]{'BeginBlock'}{'Name'} =
			  $block;
			push @{ $blocks{'OUTER'}{'Lines'} }, $line;
			push @{ $blocks{$block}{'Lines'} },
			  $line;    # to be replaced by function signature
			push @{ $blocks{$block}{'Info'} },
			  { 'RefactoredSubroutineCall' => { 'Name' => $block } };
			$blocks{$block}{'BeginBlockIdx'} = $index;
			next;
		}
		if ( $line =~ /^C\s+END\sSUBROUTINE\s(\w+)/ ) {
			$in_block = 0;
			$block    = $1;
			push @{ $blocks{'OUTER'}{'Lines'} }, $line;
			push @{ $blocks{$block}{'Lines'} }, '      end';
			push @{ $blocks{$block}{'Info'} },
			  $stref->{$sub_or_func}{$f}{'Info'}->[$index];
			$stref->{$sub_or_func}{$f}{'Info'}->[$index]{'EndBlock'}{'Name'} =
			  $block;
			$blocks{$block}{'EndBlockIdx'} = $index;
			next;
		}
		if ($in_block) {
			push @{ $blocks{$block}{'Lines'} }, $line;
			push @{ $blocks{$block}{'Info'} },
			  $stref->{$sub_or_func}{$f}{'Info'}->[$index];
			$stref->{$sub_or_func}{$f}{'Info'}->[$index]{'InBlock'}{'Name'} =
			  $block;
		} else {

			#	print "OUTER:",$line,"\n";
			push @{ $blocks{'OUTER'}{'Lines'} }, $line;
		}
	}

	# WV06/12/2011: OK up to here
	#die Dumper($blocks{'OUTER'}{'Lines'});
	for my $block ( keys %blocks ) {
		next if $block eq 'OUTER';

		# Here we create an entry for the new subroutine
		# I think we need more than just Lines!
		$stref->{$sub_or_func}{$block}{'Lines'} = $blocks{$block}{'Lines'};
		$stref->{$sub_or_func}{$block}{'Info'}  = $blocks{$block}{'Info'};
		$stref->{$sub_or_func}{$block}{'Source'} =
		  $stref->{$sub_or_func}{$f}{'Source'};
	}

	#die Dumper($blocks{'OUTER'}{'Lines'});
	# 6. Identify which vars are used
	#   - in both => these become function arguments
	#   - only in "outer" => do nothing for those
	#   - only in "inner" => can be removed from outer variable declarations

# Find all vars used in each block, starting with the outer block
# It is best to loop over all vars per line per block, because we can remove the encountered vars
	for my $block ( keys %blocks ) {
		my @lines = @{ $blocks{$block}{'Lines'} };
		my %tvars = %vars;                           # Hurray for pass-by-value!
		print "\nVARS in $block:\n\n" if $V;
		for my $line (@lines) {

			#    	print $block,':',$line,"\n";
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

	# Construct the subroutine signatures
	my %args = ();
	for my $block ( keys %blocks ) {
		next if $block eq 'OUTER';

		print "\nARGS for BLOCK $block:\n" if $V;
		for my $var ( sort keys %{ $occs{$block} } ) {
			if ( exists $occs{'OUTER'}{$var} ) {
				print "$var\n" if $V;
				push @{ $args{$block} }, $var;
			}
		}

		$stref->{'Subroutines'}{$block}{'Args'} = $args{$block};
		my $sig   = "      subroutine $block(";
		my $decls = [];
		for my $argv ( @{ $args{$block} } ) {
			$sig .= "$argv,";
			my $decl = $vars{$argv}{'Decl'};    #|| $commons{$argv}{'Decl'};
			push @{$decls}, $decl;
		}
		$sig =~ s/\,$/)/s;

 #        $stref->{$sub_or_func}{$f}{'Blocks'}{$block}{'Args'}  = $args{$block};
		$stref->{$sub_or_func}{$block}{'Sig'}   = $sig;
		$stref->{$sub_or_func}{$block}{'Decls'} = $decls;
		my $marker  = shift @{ $stref->{$sub_or_func}{$block}{'Lines'} };
		my $siginfo = shift @{ $stref->{$sub_or_func}{$block}{'Info'} };
		for my $argv ( @{ $args{$block} } ) {
			my $decl = $vars{$argv}{'Decl'};
			unshift @{ $stref->{$sub_or_func}{$block}{'Lines'} }, $decl;
			unshift @{ $stref->{'Subroutines'}{$block}{'Info'} },
			  { 'VarDecl' => [$argv] };
		}
		unshift @{ $stref->{'Subroutines'}{$block}{'Info'} }, $siginfo;
		my $fl = shift @{ $stref->{$sub_or_func}{$block}{'Info'} };
		for my $inc ( keys %{ $stref->{$sub_or_func}{$f}{'Includes'} } ) {

#            $stref->{$sub_or_func}{$f}{'Blocks'}{$block}{'Includes'}{$inc} = -2;
			$stref->{'Subroutines'}{$block}{'Includes'}{$inc} = 1;

			unshift @{ $stref->{'Subroutines'}{$block}{'Lines'} },
			  "      include '$inc'";
			unshift @{ $stref->{'Subroutines'}{$block}{'Info'} },
			  { 'Include' => { 'Name' => $inc } };
			$stref->{'Subroutines'}{$block}{'Includes'}{$inc} = 1;
		}
		unshift @{ $stref->{$sub_or_func}{$block}{'Lines'} }, $sig;

		for my $index ( 0 .. scalar( @{$srcref} ) - 1 ) {
			if ( $index == $blocks{$block}{'BeginBlockIdx'} ) {
				$sig =~ s/subroutine/call/;
				$srcref->[$index] = $sig;
			} elsif ( $index > $blocks{$block}{'BeginBlockIdx'}
				and $index <= $blocks{$block}{'EndBlockIdx'} )
			{
				$srcref->[$index] = '';
			}
		}
		unshift @{ $stref->{$sub_or_func}{$block}{'Info'} }, $fl;
		if ($V) {
			print $sig, "\n";
			print join( "\n", @{$decls} ), "\n";
		}
		$stref->{'Subroutines'}{$block}{'Status'} = $READ;

		#        die Dumper($stref->{'Subroutines'}{$block});
	}

	#die Dumper($stref->{'Subroutines'}{$f});
	return $stref;
}    # END of separate_blocks()

# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# FIXME: "error: break statement not within loop or switch"
sub identify_loops_breaks {
	( my $f, my $stref ) = @_;
	my $sub_or_func = sub_func_or_incl( $f, $stref );
	my $srcref = $stref->{$sub_or_func}{$f}{'Lines'};
	if ( defined $srcref ) {
		my %do_loops = ();
		my %gotos    = ();

		#	my %labels=();
		my $nest = 0;
		for my $index ( 0 .. scalar( @{$srcref} ) - 1 ) {
			my $line = $srcref->[$index];
			next if $line =~ /^C\s+/;

			# BeginDo:
			$line =~ /^\s+do\s+(\d+)\s+\w/ && do {
				my $label = $1;
				$stref->{$sub_or_func}{$f}{'Info'}
				  ->[$index]{'BeginDo'}{'Label'} = $label;
				if ( not exists $do_loops{$label} ) {
					@{ $do_loops{$label} } = ( [$index], $nest );
					$nest++;
				} else {
					push @{ $do_loops{$label}[0] }, $index;

#        		print STDERR "WARNING: $f: Found duplicate label $label at: ".join(',',@{ $do_loops{$label}[0] })."\n";
				}
				next;
			};

			# Goto
			$line =~ /^\s+.*?[\)\ ]\s*goto\s+(\d+)\s*$/ && do {
				my $label = $1;
				$stref->{$sub_or_func}{$f}{'Info'}->[$index]{'Goto'}{'Label'} =
				  $label;
				$stref->{$sub_or_func}{$f}{'Gotos'}{$label} = 1;
				push @{ $gotos{$label} }, [ $index, $nest ];
				next;
			};

			# continue can be end of do loop or break target (amongs others?)
			$line =~ /^\s{0,4}(\d+)\s+(continue|\w)/ && do {
				my $label = $1;
				my $is_cont = $2 eq 'continue' ? 1 : 0;
				if ( exists $do_loops{$label} ) {
					if ( $nest == $do_loops{$label}[1] + 1 ) {
						$stref->{$sub_or_func}{$f}{'Info'}
						  ->[$index]{'EndDo'}{'Label'} = $label;
						$stref->{$sub_or_func}{$f}{'Info'}
						  ->[$index]{'EndDo'}{'Count'} =
						  scalar @{ $do_loops{$label}[0] };
						delete $do_loops{$label};
						$nest--;
					} else {
						print
"WARNING: $f: Found continue for label $label but nesting level is wrong: $nest<>$do_loops{$label}[1]\n"
						  if $W;
					}
				} elsif ( exists $gotos{$label} ) {
					my $target = 'GotoTarget';
					for my $pair ( @{ $gotos{$label} } ) {
						( my $tindex, my $tnest ) = @{$pair};
						$target = 'GotoTarget';
						if ( $nest <= $tnest )
						{  # What if there are several gotos point to one label?
							if ( $tnest > 0 ) {
								if ($is_cont) {
									$target = 'NoopBreakTarget';
									$stref->{$sub_or_func}{$f}{'Info'}
									  ->[$tindex]{'Break'}{'Label'} = $label;
								} else {
									$target = 'BreakTarget';
									$stref->{$sub_or_func}{$f}{'Info'}
									  ->[$tindex]{'Break'}{'Label'} = $label;

#                    	print STDERR "WARNING: $f: Found BREAK target not NOOP for label $label\n";
								}
							} else {
								if ($is_cont) {
									$target = 'NoopTarget';
								}

#							print "WARNING: goto $label ($tindex) is not in loop ($f)\n" if $translate==$GO;
							}
						} else {
							print
"WARNING: $f: Found GOTO target not BREAK for label $label: wrong nesting $nest<>$gotos{$label}[1]\n"
							  if $W;
						}
					}
					$stref->{$sub_or_func}{$f}{'Info'}
					  ->[$index]{$target}{'Label'} = $label;
					$stref->{$sub_or_func}{$f}{'Gotos'}{$label} = $target;
					delete $gotos{$label};

				}
				next;
			};

   # When an open() fails, you can pass a label to some place for error handling
   # Some evil code combines this end-of-do-block labels
			$line =~ /^\s+open.*?\,\s*err\s*=\s*(\d+)\s*\)/ && do {
				my $label = $1;
				$stref->{$sub_or_func}{$f}{'Gotos'}{$label} = 1;
				next;
			};
		}
	} else {
		print "NO SOURCE for $f\n";
	}
	return $stref;
}    # END of identify_loops_breaks()

# -----------------------------------------------------------------------------
# This subroutine reads the FORTRAN source and does very little else:
# - it combines continuation lines in a single line
# - it lowercases everything
# - it detects and normalises comments
# - it detects block markers (for factoring blocks out into subs)
# The routine is called by parse_fortran_src_OLD()
# A better way is to extract all subs in a single pass
# I guess the best wat is to first join the lines, then separate the subs
sub read_fortran_src {
	( my $s, my $stref ) = @_;

	my $is_incl = exists $stref->{'Includes'}{$s} ? 1 : 0;

	# FIXME: handle Functions too!
	# Unfortunately, a source can contain both subroutines and functions ...
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
						( $line, my $comment ) =
						  split( /\s+\!/, $line );
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

 #                    warn "TAB FORMAT for $prevline ?\n" if $prevline =~/9100/;
 #                    ($prevline=~/^\t/ || $prevline=~/^\d+\t/ ) && do {
 #                        warn "TAB FORMAT for $prevline\n" ;
 #                    };
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
	 #	               	( $prevline, my $comment ) = split( /\s+\!/, $prevline );
					}
					my $lcprevline =
					  ( substr( $prevline, 0, 2 ) eq 'C ' )
					  ? $prevline
					  : lc($prevline);
					$lcprevline =~ s/__ph(\d+)__/__PH$1__/g;

					#	                  warn "$lcprevline\n";
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

			#	        die if $f =~ /coordtrafo/;
			#	        die Dumper($lines) if $f =~ /coordtrafo/;
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

#	        	print STDERR '[',join(',',@{$phs_ref}),"]\n";
# If it's a subroutine source, skip all lines before the matching subroutine signature
#and all lines from (and including) the next non-matching subroutine signature

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

					#	            	warn "\t$name\n";
					$ok                                       = 1;
					$index                                    = 0;
					$stref->{$sub_func_incl}{$name}{'Status'} = $READ;

					#					$stref->{$sub_func_incl}{$name}{'HasBlocks'}    = 0;
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

	#die $sub_func_incl.Dumper($stref->{'Functions'}{'ew'}) if $f=~/ew/;
	return $stref;
}    # END of read_fortran_src()

# -----------------------------------------------------------------------------
# Find all source files in the current directory
sub find_subroutines_functions_and_includes {
	my $stref = shift;
	my $dir   = '.';
	my $ext   = '.f';

	# find sources (borrowed from PerlMonks)
	my %src_files = ();
	my $tf_finder = sub {
		return if !-f;
		return if !/\.f$/;
		$src_files{$File::Find::name} = 1;
	};
	find( $tf_finder, $dir );

	for my $src ( keys %src_files ) {
		open my $SRC, '<', $src;
		while ( my $line = <$SRC> ) {

			# Skip blanks
			$line =~ /^\s*$/ && next;

			# Detect and standardise comments
			$line =~ /^[C\*\!]/i && next;

			# Find subroutine/program signatures
			$line =~ /^\s+(subroutine|program)\s+(\w+)/i && do {
				my $is_prog = $1 eq 'program' ? 1 : 0;
				if ( $is_prog == 1 ) {
					print "Found program $2 in $src\n" if $V;
				}
				my $sub = lc($2);
				if (
					not exists $stref->{'Subroutines'}{$sub}{'Source'}
					or (    $src =~ /$sub\.f/
						and $stref->{'Subroutines'}{$sub}{'Source'} !~
						/$sub\.f/ )
				  )
				{
					if (    exists $stref->{'Subroutines'}{$sub}{'Source'}
						and $src =~ /$sub\.f/
						and $stref->{'Subroutines'}{$sub}{'Source'} !~
						/$sub\.f/ )
					{
						print "WARNING: Ignoring source "
						  . $stref->{'Subroutines'}{$sub}{'Source'}
						  . " because source $src matches subroutine name $sub.\n"
						  if $W;
					}
					$stref->{'Subroutines'}{$sub}{'Source'}  = $src;
					$stref->{'Subroutines'}{$sub}{'Status'}  = $UNREAD;
					$stref->{'Subroutines'}{$sub}{'Program'} = $is_prog;

				} else {
					print
"WARNING: Ignoring source $src for $sub because another source, "
					  . $stref->{'Subroutines'}{$sub}{'Source'}
					  . " exists.\n"
					  if $W;
				}
			};

			# Find include statements
			$line =~ /^\s*include\s+\'(\w+)\'/ && do {
				my $inc = $1;
				if ( not exists $stref->{'Includes'}{$inc} ) {
					$stref->{'Includes'}{$inc}{'Status'} = $UNREAD;
				}
			};

			# Find function signatures
			$line =~ /^\s*\w*\s+function\s+(\w+)/i && do {
				my $func = lc($1);
				$stref->{'Functions'}{$func}{'Source'} = $src;
				$stref->{'Functions'}{$func}{'Status'} = $UNREAD;
			};

		}
		close $SRC;
	}
	return $stref;
}    # END of find_subroutines_functions_and_includes()
 # -----------------------------------------------------------------------------
 # Quick and dirty way to get the Kinds of all arguments

sub get_maybe_args_globs {
	( my $stref, my $f ) = @_;

	my @globs      = ();
	my %maybe_args = ();
	for my $inc ( keys %{ $stref->{'Subroutines'}{$f}{'Globals'} } ) {
		if ( defined $stref->{'Subroutines'}{$f}{'Globals'}{$inc} ) {
			@globs =
			  ( @globs, @{ $stref->{'Subroutines'}{$f}{'Globals'}{$inc} } );
		}
		if ( defined $stref->{'Includes'}{$inc}{'Vars'} ) {
			%maybe_args =
			  ( %maybe_args, %{ $stref->{'Includes'}{$inc}{'Vars'} } );
		}
	}
	%maybe_args = ( %{ $stref->{'Subroutines'}{$f}{'Vars'} }, %maybe_args );
	my %globals = map { $_ => 1 } @globs;
	return ( \%maybe_args, \%globals );
}

# -----------------------------------------------------------------------------

=pod
 We remap as follows:
 Kind
 - Scalar => 0, Array => 1
 IODir
 - In => 1
 - Out => 0
 - InOut => 2
 Type
    float
    double 
    char
    short
    int 
    long
 We use four arrays: int, long, float, double
 and we have 2 bits extra to indicate if it is char (1=>0),short (2=>1) or int (4=>3)
 
 So the encoding is:
 
 Scalar:
 0|IODir(2)|Type(2)|Subtype(2)|Index(rest)
 Array:
 1|Index(rest)
      
Now, the actual remapped argument list consists of
- the arrays for all Types and IODirs
- all other arrays
As we can only use these

--------------------------

I think we should generate everything in remap_args (though maybe we need reshape_args separately?)

But then we need to store the declarations and statements for caller and called sub in the $stref  

       
=cut

sub remap_args {
	( my $stref, my $f ) = @_;

	my $subtype;
	my @index   = ();
	my $refargs = $stref->{'Subroutines'}{$f}{'RefactoredArgs'}{'List'};

	#    print "\t$f( ".join(',',@{ $refargs })." )\n";
	print $f. ':' . scalar @{$refargs}, " => ";

	my $aidx          = 12;    # {In,Out,InOut}x{int,long,float,double}
	my $code          = 0;
	my $remapped_args = [];
	for my $refarg ( @{$refargs} ) {
		my $kind =
		  $stref->{'Subroutines'}{$f}{'RefactoredArgs'}{$refarg}{'Kind'};

		my $type =
		  $stref->{'Subroutines'}{$f}{'RefactoredArgs'}{$refarg}{'Type'};
		my $iodir =
		  $stref->{'Subroutines'}{$f}{'RefactoredArgs'}{$refarg}{'IODir'};
		my $k = ( $kind eq 'Scalar' ) ? 0 : 1;
		if ( $k == 1 ) {

			# If it's an array, we need the dimensions as well!
		}
		my $i = $iodir eq 'In' ? 1 : ( $iodir eq 'Out' ? 0 : 2 );
		( my $t, my $s ) = get_typecode( $refarg, $type );
		if ( $t == -1 ) {    # Unknown type, don't remap
			$k = 1;
		} else {
			if ( defined $index[$i][$t] ) {
				$index[$i][$t]++;
			} else {
				$index[$i][$t] = 0;
			}
		}
		if ( $k == 1 ) {

			# 1|_______|xxxxxxxx
			$code = ( 1 << 15 ) + ( $aidx & 0xFF );
			$remapped_args->[$aidx] = $refarg;
			$aidx++;
		} else {

			# 0|xx|xx|xx|_|xxxxxxxx
			$code =
			  ( 0 << 15 ) +
			  ( $i << 13 ) +
			  ( $t << 11 ) +
			  ( $s << 9 ) +
			  ( $index[$i][$t] & 0xFF );
			$remapped_args->[ $i * 4 + $t ] =
			  'scalars_' . toCType($type) . '_' . lc($iodir);
		}
		$stref->{'Subroutines'}{$f}{'RefactoredArgs'}{$refarg}{'Remapped'} =
		  $code;
	}
	@{$remapped_args} = grep { defined $_ } @{$remapped_args};

	# 	print "\t$f( ".join(',',@{ $remapped_args })." )\n";
	print scalar @{$remapped_args}, "\n";
	$stref->{'Subroutines'}{$f}{'RefactoredArgs'}{'RemappedList'} =
	  $remapped_args;

	# 	  die if $f eq 'particles_main_loop';
	return $stref;

} # END of remap_args()

# -----------------------------------------------------------------------------
sub get_typecode {
	( my $var, my $ftype ) = @_;
	my $t    = 0;
	my $s    = 0;
	my %corr = (
		'logical'          => [ 0, 3 ],
		'integer'          => [ 0, 3 ],
		'real'             => [ 2, 0 ],
		'double precision' => [ 3, 0 ],
		'doubleprecision'  => [ 3, 0 ],
		'character'        => [ 0, 1 ],
		'integer*1'        => [ 0, 0 ],
		'integer*2'        => [ 0, 1 ],
		'integer*4'        => [ 0, 2 ],
		'integer*8'        => [ 1, 0 ]
	);
	if ( exists( $corr{$ftype} ) ) {
		return @{ $corr{$ftype} };
	} else {
		print "WARNING: NO TYPE for $var $ftype\n" if $W;
		return ( -1, -1 );
	}
}

# -----------------------------------------------------------------------------
sub reshape_args {
    ( my $stref, my $f ) = @_;

    my $subtype;
    my @index   = ();
    my $refargs = $stref->{'Subroutines'}{$f}{'RefactoredArgs'}{'List'};

#    print $f. ':' . scalar @{$refargs}, " => ";

    my $reshaped_args = [];
    for my $refarg ( @{$refargs} ) {    	
        my $kind =
          $stref->{'Subroutines'}{$f}{'RefactoredArgs'}{$refarg}{'Kind'};
        my $k = ( $kind eq 'Scalar' ) ? 0 : 1;
        # No need to reshape scalars
        if ( $k == 1 ) {
            my $shape =
              $stref->{'Subroutines'}{$f}{'RefactoredArgs'}{$refarg}{'Shape'};
              if (defined $shape) {
              	if ( scalar @{$shape} == 2 && $shape->[0] == 1) {
              		die $refarg,@{$shape};              		
              	} 
              } else {
              	die keys %{$stref->{'Subroutines'}{$f}{'RefactoredArgs'}{$refarg}};
              }
            my $type =
              $stref->{'Subroutines'}{$f}{'RefactoredArgs'}{$refarg}{'Type'};
            # We need to reshape in both directions; but in reshape_args() 
            # we don't have the actual call arguments so we can only work out the 
            # new args for the called sub
            my $decl = "$type, dimension(size($refarg)):: $refarg\_1D";
            my $reshape = "$refarg = reshape($refarg\_1D,shape($refarg)";
            warn $stref->{'Subroutines'}{$f}{'Vars'}{$refarg}{'Decl'},"\n",$decl,"\n",$reshape,"\n";             	         
            $stref->{'Subroutines'}{$f}{'RefactoredArgs'}{$refarg}{'Reshaped'}{'Decl'} = $decl;
            $stref->{'Subroutines'}{$f}{'RefactoredArgs'}{$refarg}{'Reshaped'}{'Reshape'} = $reshape;
            push @{ $reshaped_args }, $refarg;
        }        
    }
    
#    print scalar @{$reshaped_args}, "\n";
    $stref->{'Subroutines'}{$f}{'RefactoredArgs'}{'ReshapedList'} =
      $reshaped_args;
    return $stref;
} # END of reshape_args()

# -----------------------------------------------------------------------------
=pod

Now, for the actual subroutine call, we can create the 
=cut

# -----------------------------------------------------------------------------
sub sub_func_or_incl {
	( my $f, my $stref ) = @_;
	if ( exists $stref->{'Subroutines'}{$f} ) {
		return 'Subroutines';
	} elsif ( exists $stref->{'Functions'}{$f} ) {
		return 'Functions';
	} elsif ( exists $stref->{'Includes'}{$f} ) {
		return 'Includes';
	} else {
		croak "No entry for $f in the state\n";
	}
}

# -----------------------------------------------------------------------------
sub show_info {
	( my $stref ) = @_;
	if ($V) {
		print "\n\n";
		print "#" x 80, "\n";
		print "Info\n";
		print "#" x 80, "\n\n";
	}

	for my $f ( keys %{ $stref->{'Subroutines'} } ) {

		if (    exists $stref->{'Subroutines'}{$f}{'Lines'}
			and exists $stref->{'Subroutines'}{$f}{'Info'} )
		{
			print "\nSUBROUTINE: $f\n\n";

			#           die Dumper($stref->{'Subroutines'}{$f}{'Info'});
			my @lines = @{ $stref->{'Subroutines'}{$f}{'Lines'} };
			my @info  = @{ $stref->{'Subroutines'}{$f}{'Info'} };
			if ( scalar(@lines) != scalar(@info) ) {
				die scalar(@lines) . '!=' . scalar(@info) . " for $f";
			} else {

				for my $i ( 0 .. @lines - 1 ) {
					my $line = $lines[$i];
					my $item = $info[$i];
					if ( defined $item ) {
						print $line, "\t\t**** ";
						print join( ',', keys %{$item} ), "\n";
					}
				}
				print "\n";
			}
		} else {
			print "WARNING: No info for $f\n" if $W;
		}

	}

}

# -----------------------------------------------------------------------------
sub insert_lines {
	( my $lref, my $srcref, my $idx ) = @_;    # \@lines, \@src_lines, $idx;
	my $nsrc = [ @{$srcref} ];
	splice( @{$nsrc}, $idx, 0, @{$lref} );
	return $nsrc;
}    # END of insert_lines()

# -----------------------------------------------------------------------------

# A convenience function to split long lines.
# - count the number of characters, i.e. length()
# - find the last comma before we exceed 64 characters (I guess it's really 72-5?):

sub split_long_line {
	my $line   = shift;
	my @chunks = @_;

	my $nchars = 64;
	if ( scalar(@chunks) == 0 ) {
		print "\nLINE: \n$line\n" if $V;
		$nchars = 72;
	}
	my $split_on  = ',';
	my $split_on2 = ' ';
	my $split_on3 = '.ro.';
	my $split_on4 = '.dna.';

	my $smart = 0;
	if ( length($line) > $nchars ) {
		my $patt  = '';
		my $ll    = length($line);
		my $rline = join( '', reverse( split( '', $line ) ) );

		#		print $rline,"\n";
		#		print "$ll - $nchars = ",$ll - $nchars,"\n";
		my $idx  = index( $rline, $split_on,  $ll - $nchars );
		my $idx2 = index( $rline, $split_on2, $ll - $nchars );
		my $idx3 = index( $rline, $split_on3, $ll - $nchars );
		my $idx4 = index( $rline, $split_on4, $ll - $nchars );
		if ( $idx < 0 && $idx2 < 0 && $idx3 < 0 && $idx4 < 0 ) {
			print "WARNING: Can't split line \n$line\n" if $W;
		} elsif ( $idx >= 0 ) {
			print "Split line on ", $ll - $idx, ", '$split_on'\n" if $V;
		} elsif ( $idx < 0 && $idx2 >= 0 ) {
			$idx = $idx2;
			print "Split line on ", $ll - $idx2, ", '$split_on2'\n"
			  if $V;
		} elsif ( $idx < 0 && $idx2 < 0 && $idx3 >= 0 ) {
			$idx = $idx3;
			print "SPLIT line on ", $ll - $idx, ", '$split_on3'\n"
			  if $V;

			# Need smarter split
			$smart = 1;
			$patt = join( '', reverse( split( '', $split_on3 ) ) );
		} elsif ( $idx < 0 && $idx2 < 0 && $idx4 >= 0 ) {
			$idx = $idx4;
			print "SPLIT line on ", $ll - $idx, ", '$split_on4'\n"
			  if $V;

			# Need smarter split
			$smart = 1;
			$patt = join( '', reverse( split( '', $split_on4 ) ) );
		}

#		if ($smart==1) {
#			die substr( $line, 0, $ll - $idx3, '' ) if length(substr( $line, 0, $ll - $idx3, '' ))>$nchars;
#		}
		push @chunks, substr( $line, 0, $ll - $idx, '' );
		print "CHUNKS:\n", join( "\n", @chunks ), "\n" if $V;
		print "REST:\n", $line, "\n" if $V;
		&split_long_line( $line, @chunks );
	} else {
		push @chunks, $line;

		my @split_lines = ();
		if ( @chunks > 1 ) {
			my $fst = 1;
			for my $chunk (@chunks) {
				if ($fst) {
					$fst = 0;
				} else {
					if ( $chunk =~ /^\s*$/ ) {
						$chunk = '';
					} else {

						#						$chunk = '     &  ' . $chunk;
						$chunk = '     &' . $chunk;
					}
				}
				push @split_lines, $chunk;
			}
		} else {
			@split_lines = @chunks;
		}
		if (   $split_lines[0] !~ /^C/
			&& $split_lines[0] =~ /\t/
			&& $split_lines[0] !~ /^\s{6}/
			&& $split_lines[0] !~ /^\t/ )
		{

			# problematic tab!
			print "WARNING: Pathological TAB in " . $split_lines[0] . "\n"
			  if $W;
			my $sixspaces = ' ' x 6;
			$split_lines[0] =~ s/^\ +\t//;
			if ( length( $split_lines[0] ) > 66 ) {
				$split_lines[0] =~ s/^\s+//;
				$split_lines[0] =~ s/\s+$//;
			}
			if ( length( $split_lines[0] ) > 66 ) {
				print "WARNING: Line still too long: " . $split_lines[0] . "\n"
				  if $W;
			}
			$split_lines[0] = $sixspaces . $split_lines[0]
			  unless $split_lines[0] =~ /^\s+\d+/;

			#			warn "<$split_lines[0]>\n";

		}
		return @split_lines;
	}
}

# -----------------------------------------------------------------------------
sub union {
	( my $aref, my $bref ) = @_;
	my %as = map { $_ => 1 } @{$aref};
	for my $elt ( @{$bref} ) {
		$as{$elt} = 1;
	}
	my @us = sort keys %as;
	return \@us;
}    # END of union()

# -----------------------------------------------------------------------------
# This union is obtained by removing duplicates from @b. It is a bit slower but preserves the order
sub ordered_union {
	( my $aref, my $bref ) = @_;
	my @us = @{$aref};
	my %as = map { $_ => 1 } @{$aref};
	for my $elt ( @{$bref} ) {
		if ( not exists $as{$elt} ) {
			push @us, $elt;
		}
	}
	return \@us;
}    # END of ordered_union()

# -----------------------------------------------------------------------------
sub add_to_call_tree {
	( my $f, my $stref, my $stubbed ) = @_;
	$stubbed ||= ' ';
	my $sub_or_func = sub_func_or_incl( $f, $stref );
	my $src         = $stref->{$sub_or_func}{$f}{'Source'};
	my $nspaces     = 64 - $stref->{'Indents'} - length($f); # -length($src) -2;
	my $incls = join( ',', keys %{ $stref->{$sub_or_func}{$f}{'Includes'} } );
	my $padding = ' ' x ( 32 - length($src) );
	my $src_padded = $src . $padding;
	my $tgt        = uc( substr( $sub_or_func, 0, 3 ) );
	my @strs       = (
		' ' x $stref->{'Indents'},
		$f, $stubbed, ' ' x $nspaces,
		$tgt, ' ', $src_padded, "\t", $incls, "\n"
	);
	my $str = join( '', @strs );
	push @{ $stref->{'CallTree'} }, $str;
	return $stref;
}    # END of add_to_call_tree()

# -----------------------------------------------------------------------------
sub add_to_C_build_sources {
	( my $f, my $stref ) = @_;
	my $sub_or_func = sub_func_or_incl( $f, $stref );
	my $src = $stref->{$sub_or_func}{$f}{'Source'};
	if ( not exists $stref->{'BuildSources'}{'C'}{$src} ) {
		print "ADDING $src to C BuildSources\n" if $V;
		$stref->{'BuildSources'}{'C'}{$src} = 1;
		$stref->{$sub_or_func}{$f}{'Status'} = $C_SOURCE;
	}

# Assuming no includes in Functions, this is not needed for Functions
# However, this might be too restrictive: surely includes with constants must be supported! FIXME!
	for my $inc ( keys %{ $stref->{$sub_or_func}{$f}{'Includes'} } ) {
		if ( not exists $stref->{'BuildSources'}{'H'}{$inc} ) {
			print "ADDING $inc to C Header BuildSources\n" if $V;
			$stref->{'BuildSources'}{'H'}{$inc} = 1;
		}
	}
	return $stref;
}

# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
sub create_call_graph {
	( my $stref ) = @_;

	open my $DOT, '>', 'callgraph.dot';
	print $DOT 'digraph FlxWrf {
node [shape=box];
rankdir="LR";
ratio="fill";
';
	for my $pnid ( keys %{ $stref->{'Nodes'} } ) {
		my %seen = ();
		my $i    = 0;
		for my $cnid ( @{ $stref->{'Nodes'}{$pnid}{'Children'} } ) {

			# Repeated calls to subs without children are pruned
			if ( scalar( @{ $stref->{'Nodes'}{$cnid}{'Children'} } ) != 0
				or not exists $seen{ $stref->{'Nodes'}{$cnid}{'Subroutine'} } )
			{
				my $psub = $stref->{'Nodes'}{$pnid}{'Subroutine'};
				my $csub = $stref->{'Nodes'}{$cnid}{'Subroutine'};
				print $DOT "$cnid [label=\"$csub\"];\n";
				if ( $i == 0 ) {
					print $DOT "$pnid [label=\"$psub\"];\n";
				}
				print $DOT "$pnid -> $cnid ;\n";
			}
			$seen{ $stref->{'Nodes'}{$cnid}{'Subroutine'} }++;
			$i++;
		}
		my $sub = $stref->{'Nodes'}{$pnid}{'Subroutine'};

		#        print $DOT "$pnid [label=\"$sub\"];\n";
	}
	print $DOT "}\n";
	close $DOT;
}

# -----------------------------------------------------------------------------

sub generate_docs {
	my $scriptsrc = $0;
	my $src       = $scriptsrc;
	$src =~ s/\.pl//;
	$src =~ s/^.*\///;
	my $markdownsrc = $src . '.markdown';
	open my $PL, '<', $scriptsrc;
	open my $MD, '>', $markdownsrc;
	my $md = 0;

	while (<$PL>) {
		/^=begin\s+markdown/ && do {
			$md = 1;
			next;
		};
		/^=end\s+markdown/ && do {
			$md = 0;
			next;
		};

		if ( $md == 1 ) {
			my $el = $_;
			while ( $el =~ /\|(\$\w+)\|/ ) {
				my $var  = $1;    # so this is a '$' and then some \w's
				my $evar = '';
				eval("\$evar= $var");
				warn $var, '=', $evar;
				my $svar = "\\|\\$var\\|";
				$el =~ s/$svar/$evar/;
			}
			print $MD $el;
		}
	}
	close $PL;
	close $MD;
	my $tex_src_in = $src . '_in.tex';
	system("pandoc -f markdown -t latex $markdownsrc > $tex_src_in ");

	my $tex_src_out = $src . '.tex';

	open my $TEXIN,  '<', $tex_src_in;
	open my $TEXOUT, '>', $tex_src_out;
	print $TEXOUT <<'ENDH';
\documentclass{article}
\usepackage[T1]{fontenc}
\usepackage{textcomp}

%%  Latex generated from POD in document /Users/wim/SoC_Research/FLEXPART/flx_wrf2/OpenCL-port/tools/refactor_block_subroutine.pod
%%  Using the perl module Pod::LaTeX
%%  Converted on Sun Nov 13 23:38:44 2011


\usepackage{makeidx}
\makeindex


\begin{document}

\tableofcontents

ENDH

	my $code = 0;
	while (<$TEXIN>) {
		/verbatim/ && do {
			$code = 1 - $code;
		};
		print $TEXOUT $_;
		if ($code) {
			print $TEXOUT "\n";
		}
	}
	close $TEXIN;
	print $TEXOUT '\printindex' . "\n";
	print $TEXOUT '\end{document}' . "\n";
	close $TEXOUT;
	system("pdflatex $tex_src_out");
	my @exts = qw(
	  _in.tex
	  .toc
	  .log
	  .idx
	  .aux
	);
	map { unlink $src . $_ } @exts;

}

