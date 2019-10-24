#!/usr/local/bin/perl

use strict;

use JSON::PP;
use List::Util qw(uniq);
use FindBin qw($Bin);
use Storable;
use File::stat;

use v5.18;

# remove after testing
srand 4;

use constant symbols => 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890';

my $original_build_file = 'build.gradle';

my $tag_file = 'java-classes-tags.json';

my $cache_file = "$Bin/cache.bin";

my $print_project_sources = <<EOF;
task printProjectSources doLast {
    jar.source.files.forEach {
        println it
    }
}
EOF

my $print_compile_jars = <<EOF;
task printCompileJars doLast {
    compileJava.classpath.files.forEach { println it }
    compileTestJava.classpath.files.forEach { println it }
}
EOF

my $list_build_dirs = <<EOF;
task listBuildDirs doLast {
    tasks.findAll { it.name ==~ /^compile.*/ }.forEach {
        println it.getDestinationDir().toString()
    }
}
EOF

my @other_jar_locations = qw(
    /Library/Java/JavaVirtualMachines/jdk1.8.0_191.jdk/Contents//Home/jre/lib/rt.jar
);

sub load_cache() {
    my $c = {};
    eval { $c = retrieve($cache_file); };
    return $c;
}

my $cache = load_cache;

sub start_timer($) {
    my $text = shift;
    my $time = time;
    print $text;
    return sub {
        say "- " . (time - $time) . "s";
    }
}

sub random_tmp_file_name() {
    my @s = split // => symbols;
    my $rnd = join '' => map { $s[ int rand length symbols ] } (1 .. 8);
    return "_tmp_${rnd}_build.gradle";
}

sub temp_file() {
    my $name = random_tmp_file_name;
    open my $fh, '>', $name or die "could not open '$name'";
    return {
        fh   => $fh,
        name => $name
    };
}

sub build_file() {
    my $tmp = temp_file;

    open my $fh, '<', $original_build_file or die "could not open '$original_build_file'";
    while (<$fh>) {
        chomp;
        say {$tmp->{fh}} $_;
    }
    close $fh;

    print {$tmp->{fh}} "\n", $print_project_sources;
    print {$tmp->{fh}} "\n", $print_compile_jars;

    close $tmp->{fh};

    return $tmp->{name};

}

sub classes_from_jar {
    my $jar = shift;

    if (exists $cache->{jars}{$jar} && $cache->{jars}{$jar}{time} > stat($jar)->mtime) {
        return @{ $cache->{jars}{$jar}{data} };
    }

    my @a = qx(jar tf $jar);
    chomp @a;
    $cache->{jars}{$jar} = { data => \@a, time => time };
    return @a;
}

sub tag_struct() {
    my $build_file = build_file;
    my $timer;

    $timer = start_timer "printProjectSources... ";
    my @local = qx(./gradlew --quiet --console=plain --build-file=$build_file printProjectSources);
    chomp @local;
    $timer->();

    $timer = start_timer "printCompileJars... ";
    my @jars = qx(./gradlew --quiet --console=plain --build-file=$build_file printCompileJars);
    chomp @jars;
    $timer->();

    unlink $build_file;

    push @jars, @other_jar_locations;

    $timer = start_timer "processing local... ";
    my @classes = map { s|/|.|gr }
        map { s|^.*build/classes/[^/]+/main/([^\.]+)\.class$|\1|r }
        grep { m|^[^\$]+\.class$| } @local;
    $timer->();

    $timer = start_timer "loading jars... ";
    push @classes, map { s|/|.|gr }
        map { s/\.class$//r }
        grep { m|^[^\$]+\.class$| }
        map { classes_from_jar($_) }
        grep { /\.jar$/ } @jars;
    $timer->();

    $timer = start_timer "building tree... ";
    my %h;
    foreach (uniq @classes) {
        /^(.*)\.(.*)$/ && do {
            $h{$2} = [] unless exists $h{$2};
            push @{$h{$2}}, $1;
        };
    }
    $timer->();

    return \%h;

}

open my $fh, '>', $tag_file or die "could not open '$tag_file'";
say $fh encode_json tag_struct;
close $fh;

store $cache, $cache_file;
