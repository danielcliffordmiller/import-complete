#!/usr/local/bin/perl

use strict;

use List::Util qw(uniq);
use FindBin qw($Bin);
use Storable;
use File::stat;
use Cwd;

use v5.18;

# remove after testing
srand 4;

use constant symbols => 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890';

my $original_build_file = 'build.gradle';
my $lang = 'groovy';

my $tag_file = 'java-classes-tags.sql';

my $cache_file = "$Bin/cache.bin";

my $print_project_sources = {
    groovy => <<EOF,
task printProjectSources doLast {
    jar.source.files.forEach {
        println it
    }
}
EOF
    kotlin => <<EOF,
tasks.register<Jar>("printProjectSources") {
    doLast {
        project.tasks.filter { it.name == "jar" }.first().let {
            if ( it is Jar ) {
                it.source.files.forEach(::println)
            }
        }
    }
}
EOF
};

my $print_compile_jars = {
    groovy => <<EOF,
task printCompileJars doLast {
    compileJava.classpath.files.forEach { println it }
    compileTestJava.classpath.files.forEach { println it }
}
EOF
    kotlin => <<EOF,
tasks.register("printCompileJars") {
    doLast {
        project.tasks.forEach {
            if ( it is AbstractCompile ) {
                it.classpath.files.forEach(::println)
            }
        }
    }
}
EOF
};

my $list_build_dirs = {
    groovy => <<EOF,
task listBuildDirs doLast {
    tasks.findAll { it.name ==~ /^compile.*/ }.forEach {
        println it.getDestinationDir().toString()
    }
}
EOF
    kotlin => <<EOF,
tasks.register("listBuildDirs") {
    doLast {
        project.tasks.filter { it.name.matches(Regex("^compile.*")) }.forEach {
            if ( it is AbstractCompile ) {
                println(it.getDestinationDir().toString())
            }
        }
    }
}
EOF
};

my @other_jar_locations = ();
#my @other_jar_locations = qw(
#    /Library/Java/JavaVirtualMachines/jdk1.8.0_191.jdk/Contents//Home/jre/lib/rt.jar
#);

my $jdk_11_class_list = '/Library/Java/JavaVirtualMachines/adoptopenjdk-11.jdk/Contents/Home/lib/classlist';

sub load_cache() {
    my $c = {};
    eval { $c = retrieve($cache_file); };
    return $c;
}

my $cache = load_cache;

sub switch_to_kotlin() {
    $original_build_file .= ".kts";
    $lang = 'kotlin';
}

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
    return "_tmp_${rnd}_$original_build_file";
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
    my $fh;

    open $fh, '<', $original_build_file or do {
        warn "could not open '$original_build_file', trying kotlin";
        close $fh;
        switch_to_kotlin;

        open $fh, '<', $original_build_file or die "kotlin failed as well";
    };

    my $tmp = temp_file;

    while (<$fh>) {
        chomp;
        say {$tmp->{fh}} $_;
    }
    close $fh;

    print {$tmp->{fh}} "\n", $print_project_sources->{$lang};
    print {$tmp->{fh}} "\n", $print_compile_jars->{$lang};

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

    $timer = start_timer 'runtime classes... ';
    push @classes, map { s|/|.|gr } grep { m|^[^\$]+$| } qx(cat $jdk_11_class_list);
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

sub project() {
    my $path = cwd =~ s/$ENV{HOME}/~/r;
    return $path =~ s|/?$|/|r;
}

open my $fh, '>', $tag_file or die "could not open '$tag_file'";

my $s = tag_struct;

print $fh "INSERT INTO projects ( path ) VALUES ( '". project ."' );";
for my $class (keys %$s) {
    my $packages = $s->{$class};
    print $fh "INSERT INTO classes ( name ) VALUES ('". $class ."');\n";
    for my $p (@$packages) {
        print $fh "INSERT INTO packages ( name ) VALUES ('" . $p . "');";
        print $fh "INSERT INTO project_package_class (project_id,package_id,class_id) SELECT pr.id project_id, pa.id package_id, cl.id classes_id FROM projects pr JOIN packages pa JOIN classes cl WHERE pr.path = '". project . "' AND pa.name = '". $p ."' AND cl.name = '". $class ."';";
    }
}

close $fh;

store $cache, $cache_file;
