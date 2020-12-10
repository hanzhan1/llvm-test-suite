use strict;
use warnings;

BEGIN
{
    use lib $ENV{ICS_PERLLIB};
}

use File::Basename;
use File::Spec;

use XML::Simple;
use Data::Dumper;
local $Data::Dumper::Sortkeys = 1;
local $Data::Dumper::Terse = 1;
local $Data::Dumper::Indent = 1;

my $cmake = "/rdrive/ics/itools/pkgtools/cmake/v_3_4_3/efi2_rhxx/bin/cmake";
$cmake = "cmake";

my $command_status = 0;
my $command_output = "";

my $test_suite_repo = "/export/users/$ENV{USER}/llvm-test-suite.orig";
my $test_suite_repo_rev = '';
my $test_suite_repo_date = '';

my $lit = "/rdrive/ref/lit/lit.py";

my $tmp_dir = './tmp';

sub main
{
    $test_suite_repo = File::Spec->rel2abs($test_suite_repo);

    prepare_src();
    do_cmake();

    execute("cd $tmp_dir && find -name '*.test'");
    my @list = split( "\n", $command_output);
    execute("mkdir config");
    my $all_passed = 0;

    my $tests = {};
    foreach my $t (@list)
    {
        my $path;
        if ( $t =~ /(.*)\.test$/)
        {
            $path = $1;
        }
        else
        {
            die "Wrong regexp";
        }

        $path =~ s/^\.\///;
        my $name = $path;
        my $short_name = basename( $path);
        $path = dirname( $path);
        $name =~ s/[\/\/\-\.]/_/g;
        $name = lc $name;
        my $r = { name => $name, path => $path, fullpath =>"llvm-test-suite/$path/$short_name.test", short_name => $short_name};

        $tests->{ $name} = $r;

        print( Dumper( $r));
        if ($name =~ "bitcode")
        {
            my $xml_text = gen_test_bitcode( $r);
            print2file( $xml_text, "./config/TEMPLATE_llvm_test_suite_bitcode.xml");
        } else 
        {
            my $xml_text = gen_test( $r);
            print2file( $xml_text, "./config/TEMPLATE_llvm_test_suite.xml");
        } 
    }

    print2file( gen_suite( $tests), "llvm_test_suite.xml");
#    print Dumper( $tests);
    print scalar keys %{ $tests};
    print ( "\nAll_passed:$all_passed\n");

}

sub prepare_src
{
    execute( "cd $test_suite_repo && git log -1 ./ && cd - > /dev/null");

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
    my $descr = "Port of llvm-test-suite.\n";
    $descr .= "Suite is autogenerated by suite_generator.pl that you can find in the root dir of suite\n";
    $descr .= "Sources repo git-amr-2.devtools.intel.com/gerrit/icl_tst-llvm-project-llvm-test-suite\n";
    $descr .= "Last Changed Revision: $test_suite_repo_rev $test_suite_repo_date\n";
    $descr .= "More details: http://llvm.org/docs/TestingGuide.html#test-suite-quickstart";

    $xml->{description} = { content => $descr};
    $xml->{files}       = { file => [ { path => 'cmake'}, { path => 'tools'}, { path => 'CMakeLists.txt'}, { path => 'HashProgramOutput.sh'}, { path => 'litsupport'}, { path => 'lit.cfg'}, { path => 'lit.site.cfg.in'}, { path => 'Bitcode'}, { path => 'MicroBenchmarks'}, { path => 'MultiSource'}, { path => 'SingleSource'}, { path => '$INFO_TDRIVE/ref/lit'}, { path => 'config'}, { path => 'suite_generator.pl'}]};

    my $pre_xml_file = "/rdrive/tests/mainline/CT-SpecialTests/llvm-test-suite/llvm_test_suite.xml";
    open my $fh, '<', $pre_xml_file or die "Could not open '$pre_xml_file'!\n";
    my @strings = ();
    while (my $line = <$fh>) {
        chomp $line;
        push(@strings, $line)
    }

    foreach my $testname ( sort keys %{ $tests})
    {
        my @pre_xml = ();
        @pre_xml = grep /testName="\Q$testname\E"/, @strings;
        my $pre_xml_name = "";
        if (@pre_xml != 0 and $pre_xml[0] =~ m/configFile="([^\s]*\.xml)"/) {
            $pre_xml_name = $1;
            push @{ $xml->{tests}{test}}, { configFile => "$pre_xml_name", testName => $testname};
            my $pre_xml_file = basename($pre_xml_name);
            if (! -f "config/$pre_xml_file") {
                copy("/rdrive/tests/mainline/CT-SpecialTests/llvm-test-suite/$pre_xml_name", "./config/") or die "copy failed: $!";
            }
        } elsif ($testname =~ "bitcode") {
            push @{ $xml->{tests}{test}}, { configFile => "config/TEMPLATE_llvm_test_suite_bitcode.xml", testName => $testname}; 
        } else {
            push @{ $xml->{tests}{test}}, { configFile => "config/TEMPLATE_llvm_test_suite.xml", testName => $testname}; 
        }
    }

    return XMLout( $xml, xmldecl => '<?xml version="1.0" encoding="UTF-8" ?>', RootName => 'suite');
}

sub gen_test
{
    my $r = shift;
    my $xml = {};
    $xml->{driverID} = 'llvm_test_suite';
    $xml->{name}     = 'TEMPLATE';
    $xml->{description} = { content => "This config file is used for several tests.\nIt must have a non-empty 'decription' field\nand name='TEMPLATE'. "};

    print2file( "$r->{path}/$r->{short_name}.test", "./config/$r->{name}.info");
    execute("git add ./config/$r->{name}.info");

    return XMLout( $xml, xmldecl => '<?xml version="1.0" encoding="UTF-8" ?>', RootName => 'test');
}

sub gen_test_bitcode
{
    my $r = shift;
    my $xml = {};
    $xml->{driverID} = 'llvm_test_suite';
    $xml->{name}     = 'TEMPLATE';
    $xml->{description} = { content => "This config file is used for several tests.\na separate config file for the llvm bitcode tests,\nonly xmain and clang compilers understand it."};
    
    push @{ $xml->{rules}{platformRule}}, { compiler => ".*clang.*", runOnThisPlatform => "true"}; 
    push @{ $xml->{rules}{platformRule}}, { compiler => ".*xmain.*", runOnThisPlatform => "true"}; 
    push @{ $xml->{rules}{platformRule}}, { compiler => ".*icx.*",   runOnThisPlatform => "true"}; 
    
    print2file( "$r->{path}/$r->{short_name}.test", "./config/$r->{name}.info");
    execute("git add ./config/$r->{name}.info");

    return XMLout( $xml, xmldecl => '<?xml version="1.0" encoding="UTF-8" ?>', RootName => 'test');
}


sub do_build
{
    my $r = shift;
    ###
    execute( "cd ./tmp/$r->{path} && make $r->{short_name}");
    return $command_status;
}

sub do_run
{
    my $r = shift;
    ###
    execute( "cd ./tmp/$r->{path} && python $lit $r->{short_name}.test");
    return $command_status;
}


sub do_cmake
{
    execute( "rm -rf $tmp_dir ; mkdir $tmp_dir");

    execute( "cd $tmp_dir && CC=clang CXX=clang++ $cmake $test_suite_repo");

    print $command_output;

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
main();