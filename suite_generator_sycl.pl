use strict;
use warnings;

BEGIN
{
    use lib $ENV{ICS_PERLLIB};
}

use File::Basename;
use File::Spec;
use File::Copy;

use XML::Simple;
use Data::Dumper;
local $Data::Dumper::Sortkeys = 1;
local $Data::Dumper::Terse = 1;
local $Data::Dumper::Indent = 1;

my $command_status = 0;
my $command_output = "";

my $test_suite_repo = '.';
my $test_suite_repo_rev = '';
my $test_suite_repo_date = '';
my $testbase = "/rdrive/tests/mainline/CT-SpecialTests/llvm-test-suite";

my $sycl_dir = '';

my $feature_folder = "SYCL";
my $feature_name = "";
my $config_folder = "config_sycl";
my $suite_name = "llvm_test_suite_sycl";
my $suite_description = "";
my $help_info = "Suite files generator for sycl tests\n\n"
              . "Usage: perl suite_generator_sycl.pl [tests_folder]\n"
              . "       perl suite_generator_sycl.pl tests_folder [description_file]\n\n"
              . "Argument explanation: \n"
              . "        - Empty, no argument. Generate tc files for SYCL folder(llvm_test_suite_sycl)\n"
              . "        - Argument [tests_folder] is the folder where you put your tests and\n"
              . "          the second argument [description_file] is the file which describes the suite.\n\n"
              . "          Notes: The folder name must be in uppercase and start with 'SYCL_'.\n\n"
              . "Examples:\n"
              . "          1)Generate tc files for folder SYCL_FEATURE_FOLDER\n"
              . "                perl suite_generator_sycl.pl SYCL_FEATURE_FOLDER\n"
              . "          2)Generate tc files for folder SYCL_FEATURE_FOLDER; and use the description in file DES.TXT\n"
              . "                perl suite_generator_sycl.pl SYCL_FEATURE_FOLDER DES.TXT\n\n";

sub main
{
    $test_suite_repo = File::Spec->rel2abs($test_suite_repo);
    $sycl_dir = "$test_suite_repo/$feature_folder";

    check_src();

    execute("cd $sycl_dir && find -iname '*.cpp' | grep -vw 'Inputs'");
    my @list = split( "\n", $command_output);
    execute("rm -rf $config_folder && mkdir $config_folder");

    my $tests = {};
    foreach my $t (@list)
    {
        my $path;
        if ( $t =~ /(.*)\.cpp$/) {
            $path = $1;
        } else {
            die "Wrong regexp";
        }

        $path =~ s/^\./$feature_folder/;
        my $name = $path;
        my $short_name = basename( $path);
        $path = dirname( $path);
        $name =~ s/$feature_folder\///;
        $name =~ s/[\/\/\-\.]/_/g;
        $name = lc $name;
        my $r = { name => $name, path => $path, fullpath =>"$path/$short_name.cpp", short_name => $short_name};

        $tests->{ $name} = $r;

        print( Dumper( $r));
        my $xml_text = gen_test( $r);
        print2file( $xml_text, "./$config_folder/TEMPLATE_$suite_name.xml");
    }

    print2file( gen_suite( $tests), "$suite_name.xml");
    print "The number of tests in $suite_name: ";
    print scalar keys %{ $tests};
}

sub check_src
{
    execute( "cd $sycl_dir && git log -1 ./");

    if ( $command_output =~ m/commit (.*)/)
    {
        $test_suite_repo_rev = $1;
    }
    if ( $command_output =~ m/Date:(.*)/)
    {
        $test_suite_repo_date = $1;
    }
}

sub gen_suite
{
    my $tests = shift;
    ###
    my $xml = {};
    my $descr = "";
    if ($suite_description ne "") {
        $descr = $suite_description;
    } else {
        $descr = "Port of $suite_name.\n"
               . "Suite is autogenerated by suite_generator_sycl.pl that you can find in the root dir of suite\n"
               . "Sources repo git-amr-2.devtools.intel.com/gerrit/icl_tst-llvm-project-llvm-test-suite\n"
               . "Last Changed Revision: $test_suite_repo_rev $test_suite_repo_date\n";
    }

    $xml->{description} = { content => $descr};
    if ($feature_folder eq "SYCL") {
        $xml->{files}       = { file => [ { path => 'cmake'}, { path => 'tools'}, { path => 'CMakeLists.txt'}, { path => 'litsupport'}, { path => 'lit.cfg'}, { path => 'lit.site.cfg.in'}, { path => 'SYCL'}, { path => '$INFO_TDRIVE/ref/lit'}, { path => $config_folder}]};
    } else {
        $xml->{files}       = { file => [ { path => 'cmake'}, { path => 'tools'}, { path => 'CMakeLists.txt'}, { path => 'litsupport'}, { path => 'lit.cfg'}, { path => 'lit.site.cfg.in'}, { path => 'SYCL'}, { path => $feature_folder}, { path => '$INFO_TDRIVE/ref/lit'}, { path => $config_folder}]};
    }

    my @strings = ();
    my $pre_xml_file = "${testbase}/$suite_name.xml";
    if ( -e $pre_xml_file ) {
        open my $fh, '<', $pre_xml_file or die "Could not open '$pre_xml_file'!\n";
        while (my $line = <$fh>) {
            chomp $line;
            push(@strings, $line)
        }
    }

    foreach my $testname ( sort keys %{ $tests})
    {
        my @pre_xml = ();
        my $pre_xml_name = "";

        if ( @strings != 0 ) {
            @pre_xml = grep /testName="$testname"/, @strings;
        }
        if (@pre_xml != 0 and $pre_xml[0] =~ m/configFile="([^\s]*\.xml)"/) {
            $pre_xml_name = $1;
            my $pre_xml_file = basename($pre_xml_name);
            if (-f "${testbase}/$pre_xml_name" and ! -f "$pre_xml_file") {
                copy("${testbase}/$pre_xml_name", "./$config_folder/") or die "copy failed: $!";
                push @{ $xml->{tests}{test}}, { configFile => "$pre_xml_name", testName => $testname};
                next;
            }
        }
        push @{ $xml->{tests}{test}}, { configFile => "$config_folder/TEMPLATE_$suite_name.xml", testName => $testname};
    }

    return XMLout( $xml, xmldecl => '<?xml version="1.0" encoding="UTF-8" ?>', RootName => 'suite');
}

sub gen_test
{
    my $r = shift;
    my $xml = {};
    $xml->{driverID} = 'llvm_test_suite_sycl';
    $xml->{name}     = 'TEMPLATE';
    $xml->{description} = { content => "This config file is used for several tests.\nIt must have a non-empty 'decription' field\nand name='TEMPLATE'. "};

    print2file( "$r->{path}/$r->{short_name}.cpp", "./$config_folder/$r->{name}.info");

    return XMLout( $xml, xmldecl => '<?xml version="1.0" encoding="UTF-8" ?>', RootName => 'test');
}

sub file2str
{
    my $file = shift;
    ###
    local $/=undef;
    open FD, "<$file" or die "Fail to open file $file!\n";
    binmode FD;
    my $str = <FD>;
    close FD;
    return $str;
}

sub print2file
{
    my $s = shift;
    my $file = shift;
    ###
    open FD, ">$file";

    print FD $s;
    close FD;
}

sub dump2file
{
    my $r = shift;
    my $file = shift;
    ###
    print2file( Dumper( $r), $file);
}

sub execute
{
    my $cmd = shift;
    ###

    print "$cmd\n";
    $command_output = `$cmd 2>&1`;
    my $code = $?;
    my $perl_err        = $code & ( ( 1 << 8) - 1);
    my $shell_err       = $code >> 8;

    $command_status = $shell_err;

    return ( $command_status, $command_output);
}

if ( scalar(@ARGV) == 0 ) {
    print "Generate tc files only for llvm_test_suite_sycl\n\n";
} elsif ( scalar(@ARGV) == 1 or scalar(@ARGV) == 2 ) {
    if ($ARGV[0] =~ /^-h/i or $ARGV[0] =~ /^--help/i) {
        print "$help_info";
        exit 0;
    }

    $feature_folder = $ARGV[0];
    $feature_folder =~ s/\/$//;
    $feature_folder = basename($feature_folder);
    if ( $feature_folder ne 'SYCL' and $feature_folder !~ /^SYCL_/ ) {
        die "Unsupported folder $feature_folder! Please make sure the folder name is 'SYCL' or starts with 'SYCL_'.\n\n$help_info";
    }

    if ( defined $ARGV[1] ) {
        my $description_file =  $ARGV[1];
        if ( -f $description_file) {
            $suite_description = file2str($description_file);
        } else {
            die "File $description_file doesn't exist!\n\n";
        }
    }

    $feature_name = $feature_folder;
    $feature_name =~ s/^SYCL_//;
    $feature_name = lc $feature_name;
    if ( $feature_folder ne 'SYCL' ) {
        $config_folder = $config_folder . '_' . $feature_name;
    }
    $suite_name = "llvm_test_suite_" . $feature_name;
    print "Generate tc files for $suite_name\n\n";
} else {
    die "Error: The number of arguments is larger than 2!\n\n$help_info";
}

main();
print "\n\nFinish the generation of $suite_name Successfully.\n";
