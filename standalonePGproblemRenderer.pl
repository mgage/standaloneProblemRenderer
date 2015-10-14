#!/Volumes/WW_test/opt/local/bin/perl -w

################################################################################
# WeBWorK Online Homework Delivery System
# Copyright © 2000-2007 The WeBWorK Project, http://openwebwork.sf.net/
# 
# This program is free software; you can redistribute it and/or modify it under
# the terms of either: (a) the GNU General Public License as published by the
# Free Software Foundation; either version 2, or (at your option) any later
# version, or (b) the "Artistic License" which comes with this package.
# 
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See either the GNU General Public License or the
# Artistic License for more details.
################################################################################

package OpaqueServer::RenderProblem;
=head1 NAME

Render one pg problem problem from the command line by directly accessing 
the pg directory and parts of the webwork2 directory.

=head1 SYNOPSIS

 

=head1 DESCRIPTION

This module provides functions for rendering html from files outside the normal
context of providing a webwork homework set user  an existing problem set.

It can be used to create a live version of a single problem, one that is not
part of any set, and can facilitate editing these problems outside of the 
context of WeBWorK2. 

=cut

use strict;
use warnings;


#######################################################
# Find the webwork2 root directory
#######################################################
BEGIN {
        die "WEBWORK_ROOT not found in environment. \n
             WEBWORK_ROOT can be defined in your .cshrc or .bashrc file\n
             It should be set to the webwork2 directory (e.g. /opt/webwork/webwork2)"
                unless exists $ENV{WEBWORK_ROOT};
	# Unused variable, but define it twice to avoid an error message.
	$WeBWorK::Constants::WEBWORK_DIRECTORY = $ENV{WEBWORK_ROOT};
	
	# Define MP2 -- this would normally be done in webwork.apache2.4-config
	$ENV{MOD_PERL_API_VERSION}=2;
}

our $UNIT_TESTS_ON =1;
our $HTML_OUTPUT   =0;
 # Path to a temporary file for storing the output of renderProblem.pl
use constant  TEMPOUTPUTFILE   => "$ENV{WEBWORK_ROOT}/DATA/renderProblemOutput.html"; 
die "You must first create an output file at ".TEMPOUTPUTFILE()." with permissions 777 " unless
-w TEMPOUTPUTFILE();
 # Command line for displaying the temporary file in a browser.
 #use constant  DISPLAY_COMMAND  => 'open -a firefox ';   #browser opens tempoutputfile above
  use constant  DISPLAY_COMMAND  => "open -a 'Google Chrome' ";
 #use constant DISPLAY_COMMAND => " less ";   # display tempoutputfile with less

use constant LOG_FILE => "$ENV{WEBWORK_ROOT}/DATA/bad_problems.txt";
die "You must first create an output file at ".LOG_FILE()." with permissions 777 " unless
-w LOG_FILE();

  
use constant DISPLAYMODE   => 'MathJax'; 


###################################
# Obtain the basic urls and the paths to the basic directories on this site
###################################

BEGIN {
	my $hostname = 'http://localhost';
	my $courseName = 'gage_course';

	#Define the OpaqueServer static variables
	my $topDir = $WeBWorK::Constants::WEBWORK_DIRECTORY;
	$topDir =~ s|webwork2?$||;   # remove webwork2 link
	my $root_dir = "$topDir/ww_opaque_server";
	my $root_pg_dir = "$topDir/pg";
	my $root_webwork2_dir = "$topDir/webwork2";

	my $rpc_url = '/opaqueserver_rpc';
	my $files_url = '/opaqueserver_files';
	my $wsdl_url = '/opaqueserver_wsdl';

	
	# Find the library directories for 
	# ww_opaque_server, pg and webwork2
	# and place them in the search path for modules

	eval "use lib '$root_dir/lib'"; die $@ if $@;
	eval "use lib '$root_pg_dir/lib'"; die $@ if $@;
	eval "use lib '$root_webwork2_dir/lib'"; die $@ if $@;

	############################################
	# Define basic urls and the paths to basic directories, 
	############################################
	$OpaqueServer::TopDir = $topDir;   #/opt/webwork/
	$OpaqueServer::Host = $hostname;
	$OpaqueServer::RootDir = $root_dir;
	$OpaqueServer::RootPGDir = $root_pg_dir;
	$OpaqueServer::RootWebwork2Dir = $root_webwork2_dir;
	$OpaqueServer::RPCURL = $rpc_url;
	$OpaqueServer::WSDLURL = $wsdl_url;

	$OpaqueServer::FilesURL = $files_url;
	$OpaqueServer::courseName = $courseName;

	# suppress warning messages
	my $foo = $OpaqueServer::TopDir; 
	$foo = $OpaqueServer::RootDir;
	$foo = $OpaqueServer::Host;
	$foo = $OpaqueServer::WSDLURL;
	$foo = $OpaqueServer::FilesURL;
	$foo ='';
} # END BEGIN


use Carp;
use WeBWorK::DB;
use WeBWorK::Utils::Tasks qw(fake_set fake_problem fake_user);   # may not be needed
use WeBWorK::PG; 
use WeBWorK::PG::ImageGenerator; 
use WeBWorK::DB::Utils qw(global2user); 
use WeBWorK::Form;
use WeBWorK::Debug;
use WeBWorK::CourseEnvironment;
use PGUtil qw(pretty_print not_null);
use constant fakeSetName => "Undefined_Set";
use constant fakeUserName => "Undefined_User";
use vars qw($courseName);

$Carp::Verbose = 1;


##############################
# Create the course environment $ce and the database object $db
##############################
our $ce = create_course_environment();
my $dbLayout = $ce->{dbLayout};	
our $db = WeBWorK::DB->new($dbLayout);


########################################################################
# Run problem on a given file
########################################################################

my $filePath = $ARGV[0];
my $formFields = {                            #$r->param();
    	AnSwEr0001 =>'foo',
    	AnSwEr0002 => 'bar',
    	AnSwEr0003 => 'foobar',
    	AnSwEr0004 => 'foobar',
    	prec       =>  1000,
    	
};
my $pg = standaloneRenderer($filePath, $formFields);
my $body_text = $pg->{body_text};
my $fileName = $filePath;

if ($HTML_OUTPUT) {
	my $output= <<EOF;
<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="utf-8" />
	<title>$filePath</title>
</head>
<body>
<h1> $filePath </h1>
$body_text
</body>
</html>
EOF

	local(*FH);
	open(FH, '>'.TEMPOUTPUTFILE) or die "Can't open file ".TEMPOUTPUTFILE()." for writing";
	print  $output;
	close(FH);

	system(DISPLAY_COMMAND().TEMPOUTPUTFILE());

} elsif ($fileName) {
	local(*FH);
	
	open(FH, ">>".LOG_FILE()) || die "Can't open log file ". LOG_FILE();
	my $return_string='';
	if ( $pg )    {
	        print "\n\n Result of renderProblem \n\n" if $UNIT_TESTS_ON;
	        print $pg,"\n" if $UNIT_TESTS_ON;
	        print join(" ", keys %$pg,"\n");
	        print $pg->{body_text};
	    if (not defined $pg) {  #FIXME make sure this is the right error message if site is unavailable
	    	$return_string = "Empty output while  rendering this problem\n";
	    } elsif (defined($pg->{flags}->{error_flag}) and $pg->{flags}->{error_flag} ) {
			$return_string = "0\t $fileName has errors\n";
		} elsif (defined($pg->{errors}) and $pg->{errors} ){
			$return_string = "0\t $fileName has syntax errors\n";
		} else {
			# 
			if (defined($pg->{flags}->{DEBUG_messages}) ) {
				my @debug_messages = @{$pg->{flags}->{DEBUG_messages}};
				$return_string .= (pop @debug_messages ) ||'' ; #avoid error if array was empty
				if (@debug_messages) {
					$return_string .= join(" ", @debug_messages);
				} else {
							$return_string = "";
				}
			}
			if (defined($pg->{errors}) ) {
				$return_string= $pg->{errors};
			}
			if (defined($pg->{flags}->{WARNING_messages}) ) {
				my @warning_messages = @{$pg->{flags}->{WARNING_messages}};
				$return_string .= (pop @warning_messages)||''; #avoid error if array was empty
					$@=undef;
				if (@warning_messages) {
					$return_string .= join(" ", @warning_messages);
				} else {
					$return_string = "";
				}
			}
			$return_string = "0\t ".$return_string."\n" if $return_string;   # add a 0 if there was an warning or debug message.
		}
		unless ($return_string) {
			$return_string = "1\t $fileName is ok\n";
		} else {
			$return_string = "0\t $fileName has errors\n";
		}
	} else {
		
		$return_string = "0\t $fileName has undetermined errors -- could not be read perhaps?\n";
	}
	print FH $return_string;
	close(FH);
} else {
    print "0 $fileName  something went wrong -- could not render file\n";
	print STDERR "Useage: ./checkProblem.pl    [file_name]\n";
	print STDERR "For example: ./checkProblem.pl    input.txt\n";
	print STDERR "Output is sent to the log file: ",LOG_FILE();
	
}



########################################################################
# Subroutine which renders the problem
########################################################################
# TODO 
#      allow for formField inputs with the response
#      allow problem seed input
#      allow for adjustment of other options
########################################################################

sub  standaloneRenderer {
    #print "entering standaloneRenderer\n\n";
    my $problemFile = shift//'';
    my $formFields  = shift//'';
    my %args = ();


	my $key = '3211234567654321';
	
	my $user          = $args{user} || fake_user($db);
	my $set           = $args{'this_set'} || fake_set($db);
	my $problem_seed  = $args{'problem_seed'} || 0; #$r->param('problem_seed') || 0;
	my $showHints     = $args{showHints} || 0;
	my $showSolutions = $args{showSolutions} || 0;
	my $problemNumber = $args{'problem_number'} || 1;
    my $displayMode   = $ce->{pg}->{options}->{displayMode};
    # my $key = $r->param('key');
  
	
	my $translationOptions = {
		displayMode     => "MathJax",
		showHints       => $showHints,
		showSolutions   => $showSolutions,
		refreshMath2img => 1,
		processAnswers  => 1,
		QUIZ_PREFIX     => '',	
		use_site_prefix => $ce->{server_root_url},
		use_opaque_prefix => 1,	
	};
	my $extras = {};   # Check what this is used for.
	
	# Create template of problem then add source text or a path to the source file
	local $ce->{pg}{specialPGEnvironmentVars}{problemPreamble} = {TeX=>'',HTML=>''};
	local $ce->{pg}{specialPGEnvironmentVars}{problemPostamble} = {TeX=>'',HTML=>''};
	my $problem = fake_problem($db, 'problem_seed'=>$problem_seed);
	$problem->{value} = -1;	
	if (ref $problemFile) {
			$problem->source_file('');
			$translationOptions->{r_source} = $problemFile; # a text string containing the problem
	} else {
			$problem->source_file($problemFile); # a path to the problem
	}
	
	#FIXME temporary hack
	$set->set_id('this set') unless $set->set_id();
	$problem->problem_id("1") unless $problem->problem_id();
		
		
	my $pg = new WeBWorK::PG(
		$ce,
		$user,
		$key,
		$set,
		$problem,
		123, # PSVN (practically unused in PG)
		$formFields,
		$translationOptions,
		$extras,
	);
		$pg;
}

####################################################################################
# Create_course_environment -- utility function
# requires webwork_dir
# requires courseName to keep warning messages from being reported
# Remaining inputs are required for most use cases of $ce but not for all of them.
####################################################################################



sub create_course_environment {
	my $ce = WeBWorK::CourseEnvironment->new( 
				{webwork_dir		=>		$OpaqueServer::RootWebwork2Dir, 
				 courseName         =>      $OpaqueServer::courseName,
				 webworkURL         =>      $OpaqueServer::RPCURL,
				 pg_dir             =>      $OpaqueServer::RootPGDir,
				 });
	warn "Unable to find environment for course: |$OpaqueServer::courseName|" unless ref($ce);
	return ($ce);
}





1;
