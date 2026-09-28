
#!/usr/bin/env perl

use strict;
use warnings;
use File::Find;
use File::Spec;
use File::Path qw(make_path);
use Getopt::Long;

my $root = ".";
my $dry_run = 0;

GetOptions(
    "dir=s"   => \$root,
    "dry-run" => \$dry_run,
) or die "Usage: perl validator.pl --dir DIRECTORY [--dry-run]\n";

die "Directory not found: $root\n" unless -d $root;

$root = File::Spec->rel2abs($root);

# Naming conventions for each directory
my %rules = (
    src  => qr/^(?!.*_tb\.sv$)[a-z][a-z0-9_]*\.sv$/,
    tb   => qr/^[a-z][a-z0-9_]*_tb\.sv$/,
    sim  => qr/^[a-z][a-z0-9_]*\.do$/,
    docs => qr/^README\.md$/,
);

# Required project files
my @required = (
    "src/alu.sv",
    "tb/alu_tb.sv",
    "sim/run.do",
    "docs/README.md",
);

my (@files, @valid, @errors, @moved);

# Exclude the validation script
my $script = File::Spec->rel2abs($0);

# Scan files only inside the specified repository
find(
    {
        no_chdir => 1,
        wanted => sub {
            return unless -f $File::Find::name;

            my $path = File::Spec->rel2abs(
                $File::Find::name
            );

            return if $path eq $script;

            my $relative = File::Spec->abs2rel(
                $path, $root
            );

            $relative =~ s{\\}{/}g;
            push @files, $relative;
        },
    },
    $root
);

# Validate files and move misplaced files
for my $file (@files) {
    my ($name) = $file =~ m{([^/]+)$};

    my @matching_dirs = grep {
        $name =~ $rules{$_}
    } sort keys %rules;

    if (@matching_dirs == 0) {
        push @errors, "Invalid filename: $file";
        next;
    }

    if (@matching_dirs > 1) {
        push @errors, "Ambiguous filename: $file";
        next;
    }

    my $expected_dir = $matching_dirs[0];
    my $expected_path = "$expected_dir/$name";

    # File is already in the correct location
    if ($file eq $expected_path) {
        push @valid, $file;
        next;
    }

    my $source = File::Spec->catfile(
        $root, split m{/}, $file
    );

    my $destination = File::Spec->catfile(
        $root, $expected_dir, $name
    );

    # Prevent overwriting existing files
    if (-e $destination) {
        push @errors,
            "Destination already exists: $expected_path " .
            "(source: $file)";
        next;
    }

    # Preview the move without modifying files
    if ($dry_run) {
        push @moved,
            "$file -> $expected_path (dry run)";
        next;
    }

    # Create destination directory inside the repository
    my $destination_dir = File::Spec->catdir(
        $root, $expected_dir
    );

    unless (-d $destination_dir) {
        unless (eval {
            make_path($destination_dir);
            1;
        }) {
            push @errors,
                "Cannot create directory $expected_dir: $@";
            next;
        }
    }

    # Move the file within the repository
    if (rename($source, $destination)) {
        push @moved, "$file -> $expected_path";
        push @valid, $expected_path;
    } else {
        push @errors, "Failed to move $file: $!";
    }
}

# Check required files, including planned moves in dry-run mode
my %available = map { $_ => 1 } @valid;

if ($dry_run) {
    for my $move (@moved) {
        if ($move =~ / -> (.+) \(dry run\)$/) {
            $available{$1} = 1;
        }
    }
}

for my $required (@required) {
    next if $available{$required};

    my $path = File::Spec->catfile(
        $root, split m{/}, $required
    );

    unless (-f $path) {
        push @errors, "Missing required file: $required";
    }
}

# Display validation report
print "\n=== DIRECTORY VALIDATION REPORT ===\n";
print "Directory: $root\n";
print "Mode: ", $dry_run ? "DRY RUN" : "AUTOMATIC", "\n";
print "Total files: ", scalar(@files), "\n";
print "Valid files: ", scalar(@valid), "\n";
print "Files moved: ", scalar(@moved), "\n";
print "Errors: ", scalar(@errors), "\n";

print "\n--- VALID FILES ---\n";
print "$_\n" for @valid;

print "\n--- MOVED FILES ---\n";
print "$_\n" for @moved;
print "No files moved.\n" unless @moved;

print "\n--- ERRORS ---\n";
if (@errors) {
    print "$_\n" for @errors;
} else {
    print "No errors found.\n";
}

print "\n=== VALIDATION COMPLETE ===\n";
