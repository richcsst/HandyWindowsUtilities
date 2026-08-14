#!/usr/bin/perl

# Music cleaner and organizer

use strict;
use utf8;
use warnings;
use File::Spec;
use File::Copy qw(copy);
use File::Path qw(make_path remove_tree);
use Term::ANSIColor qw(:constants colored);
use Time::HiRes qw(time sleep);
use Parallel::ForkManager;
use File::Find;
use Cwd qw(cwd);

# Force autoflush
$| = 1;

# Enable ANSI color/cursor support on Windows console
if ($^O eq 'MSWin32') {
    system('');
}

# --- Configuration ---
my $detected_cores = detect_cpu_cores();
my $MAX_WORKERS    = $detected_cores;
my $source_dir     = cwd(); # Dynamically targets the user's current working directory
my $dest_dir       = File::Spec->catdir($source_dir, "Processed");

my %FORMAT_PRIORITY = (
    'flac' => 1,
    'wav'  => 2,
    'm4a'  => 3,
    'aac'  => 4,
    'mp3'  => 5,
    'wma'  => 6,
);

# Global cursor save/restore sequence pair
my ($SAVE_CURSOR, $RESTORE_CURSOR) = get_cursor_save_restore_sequences();

# Detect UTF-8 capability and enable UTF-8 output handle if supported
my $CAN_UTF8 = detect_utf8_support();
my ($NOTE_LEFT, $NOTE_RIGHT) = $CAN_UTF8 ? ("\x{266A} ", " \x{266B}") : ("", "");

sub get_cursor_save_restore_sequences {
    # If explicitly running under Windows Terminal, xterm, or modern color terms
    if ($^O eq 'MSWin32' || $ENV{WT_SESSION} || ($ENV{TERM} && $ENV{TERM} =~ /xterm|vt100|rxvt|screen|tmux|linux/i)) {
        # DEC Save/Restore (\e7 / \e8) is the most universally supported sequence set across FreeBSD, macOS, Linux, and Windows
        return ("\e7", "\e8");
    }

    # Standard ANSI CSI fallback (\e[s / \e[u)
    return ("\e[s", "\e[u");
}

# Rule 1: Clean destination directory if it exists, then recreate
if (-d $dest_dir) {
    remove_tree($dest_dir, { keep_root => 1 })
        or die "Failed to clear contents of '$dest_dir': $!\n";
} else {
    make_path($dest_dir) or die "Failed to create '$dest_dir': $!\n";
}

# Build list of top-level directories in cwd for artist folder matching (ignoring 'Processed')
opendir(my $dh_root, $source_dir) or die "Cannot read '$source_dir': $!\n";
my %root_subdirs = map { lc($_) => $_ } grep { -d File::Spec->catdir($source_dir, $_) && $_ !~ /^\./ && lc($_) ne 'processed' } readdir($dh_root);
closedir($dh_root);

my $has_artist_subdirs = (scalar(keys %root_subdirs) > 0) ? 1 : 0;

# Global aggregated stats
my %stats = (
    scanned           => 0,
    processed         => 0,
    underscores_fixed => 0,
    spaces_fixed      => 0,
    capitalized       => 0,
    duplicates_skipped=> 0,
    ignored           => 0,
    files_relocated   => 0,
);

my @report_duplicates;
my @report_capitalized;
my @report_underscores;
my @report_spaces;
my @ignored_files;

sub hide_cursor { print "\e[?25l"; }
sub show_cursor { print "\e[?25h"; }

$SIG{INT}  = sub { show_cursor(); exit 1; };
$SIG{TERM} = sub { show_cursor(); exit 1; };

print "\e[2J";
draw_dashboard("Scanning directory (Root first, then subdirectories)...");

# Gather all files (Root files first, then subdirectories)
my @root_files;
my @subdir_files;

find({
    wanted => sub {
        my $path = $File::Find::name;

        return if -d $path;

        my $rel_path = File::Spec->abs2rel($path, $source_dir);
        return if $rel_path =~ /^Processed[\/\\\\]/i;

        my ($volume, $directories, $filename) = File::Spec->splitpath($rel_path);

        if ($filename =~ /\.pl$/i) {
            push @ignored_files, { name => $rel_path, reason => "Perl source file (.pl)" };
            $stats{ignored}++;
            return;
        }

        my $record = {
            rel_path => $rel_path,
            rel_dir  => $directories,
            filename => $filename,
            is_root  => ($directories eq '' || $directories eq '.' || $directories eq './' || $directories eq '.\\') ? 1 : 0,
        };

        if ($record->{is_root}) {
            push @root_files, $record;
        } else {
            push @subdir_files, $record;
        }
    },
    no_chdir => 1,
}, $source_dir);

# Ensure root files process FIRST before subdirectories
my @files_to_process = (@root_files, @subdir_files);

$stats{scanned} = scalar(@files_to_process) + $stats{ignored};
draw_dashboard("Distributing work across $MAX_WORKERS workers...");

# Setup ForkManager
my $pm = Parallel::ForkManager->new($MAX_WORKERS);

my %target_groups;
$pm->run_on_finish(sub {
    my ($pid, $exit_code, $ident, $exit_signal, $core_dump, $data_ref) = @_;
    return unless defined $data_ref;

    if ($data_ref->{ignored}) {
        push @ignored_files, @{$data_ref->{ignored}};
        $stats{ignored} += scalar(@{$data_ref->{ignored}});
    }

    for my $group_key (keys %{$data_ref->{groups}}) {
        push @{$target_groups{$group_key}}, @{$data_ref->{groups}{$group_key}};
    }
});

my $total_files = scalar(@files_to_process);
my $chunk_size  = int(($total_files + $MAX_WORKERS - 1) / $MAX_WORKERS);

for (my $w = 0; $w < $MAX_WORKERS; $w++) {
    my $start = $w * $chunk_size;
    last if $start >= $total_files;
    my $end = $start + $chunk_size - 1;
    $end = $total_files - 1 if $end >= $total_files;

    my @batch = @files_to_process[$start .. $end];

    $pm->start and next;

    my %local_data = ( ignored => [], groups => {} );

    for my $file_info (@batch) {
        my $filename = $file_info->{filename};
        my $rel_path = $file_info->{rel_path};
        my $rel_dir  = $file_info->{rel_dir};

        my $filepath = File::Spec->catfile($source_dir, $rel_path);

        if (-s $filepath == 0) {
            push @{$local_data{ignored}}, { name => $rel_path, reason => "0-byte empty file" };
            next;
        }

        my ($raw_base, $raw_ext) = $filename =~ /^(.*)\.([^.]+)$/;
        unless (defined $raw_base && defined $raw_ext) {
            push @{$local_data{ignored}}, { name => $rel_path, reason => "No extension found" };
            next;
        }

        my $ext = lc($raw_ext);
        unless (exists $FORMAT_PRIORITY{$ext}) {
            push @{$local_data{ignored}}, { name => $rel_path, reason => "Unsupported extension (.$ext)" };
            next;
        }

        my @dir_parts = File::Spec->splitdir($rel_dir);
        @dir_parts = grep { $_ ne '' && $_ ne '.' } @dir_parts;

        # --- Transformations ---
        my $work_base = $raw_base;
        my ($had_underscores, $had_concentric_spaces, $was_capitalized, $was_relocated) = (0, 0, 0, 0);

        # 1. Strip everything before and including track numbers
        $work_base =~ s/^.*?\s+-\s+\d{1,3}\s+-\s+//;

        # 2. Remove leading standalone numbers
        $work_base =~ s/^\d+//;

        # 3. Remove "CD s"
        $work_base =~ s/^CD\s*\d*\s*//i;

        # 4. Remove leading non-alpha
        $work_base =~ s/^[^a-zA-Z]+//;

        # 5. Remove trailing tags
        $work_base =~ s/(?:KROK|PEG|VID|UNK|TJM|CR|lc-)$//i;

        # 6. Underscores to spaces
        if ($work_base =~ /_/) {
            $had_underscores = 1;
            $work_base =~ s/_/ /g;
        }

        # 7. & to and
        $work_base =~ s/&/and/g;

        # 8. Concentric spaces
        if ($work_base =~ / {2,}/) {
            $had_concentric_spaces = 1;
            $work_base =~ s/ {2,}/ /g;
        }

        # 9. Trim
        $work_base =~ s/^\s+|\s+$//g;

        # 10. Capitalization
        my $before_cap = $work_base;
        $work_base = lc($work_base);
        $work_base =~ s/\b([a-z])/\U$1/g;
        if ($work_base ne $before_cap) {
            $was_capitalized = 1;
        }

        # 11. Fix unbalanced opening parentheses
        my $open_count  = () = $work_base =~ /\(/g;
        my $close_count = () = $work_base =~ /\)/g;
        if ($open_count > $close_count) {
            $work_base .= ')' x ($open_count - $close_count);
        }

        # --- LATE PRIORITY RULES ---

        # 12. Remove duration/length patterns
        $work_base =~ s/\s+\d{1,2}\.\d{2}\s+/ /g;

        # 13. Remove Parent and Grandparent directory names
        for my $dir_name (@dir_parts) {
            next if $dir_name eq '' || $dir_name eq '.';
            my $quoted_dir = quotemeta($dir_name);
            $work_base =~ s/(?:\s+-\s+|\s+|_)*$quoted_dir(?:\s+-\s+|\s+|_)*//gi;
        }

        # Re-trim and cleanup
        $work_base =~ s/ {2,}/ /g;
        $work_base =~ s/^\s+|\s+$//g;
        $work_base =~ s/^[^a-zA-Z]+//;

        # --- ROOT SPECIAL SUBDIRECTORY MATCHING ---
        my $final_rel_dir = $rel_dir;

        if ($file_info->{is_root}) {
            if ($work_base =~ /^(.+?)\s+-\s+(.+)$/) {
                my $artist_prefix = $1;
                my $song_title    = $2;
                my $lookup_key    = lc($artist_prefix);

                # STRICT CHECK: Only redirect if the directory ALREADY exists in cwd
                if (exists $root_subdirs{$lookup_key}) {
                    $final_rel_dir = $root_subdirs{$lookup_key};
                    $work_base     = $song_title; # Strip artist prefix
                    $was_relocated = 1;
                }
            }
        }

        # Re-clean base title after splitting artist prefix
        $work_base =~ s/^\s+|\s+$//g;
        $work_base =~ s/^[^a-zA-Z]+//;

        # Group key scope for deduplication across matching target paths
        my $group_key = File::Spec->catfile($final_rel_dir, $work_base);

        push @{$local_data{groups}{$group_key}}, {
            orig_file   => $rel_path,
            orig_path   => $filepath,
            rel_dir     => $final_rel_dir,
            target_base => $work_base,
            ext         => $ext,
            priority    => $FORMAT_PRIORITY{$ext},
            underscores => $had_underscores,
            spaces      => $had_concentric_spaces,
            capitalized => $was_capitalized,
            relocated   => $was_relocated,
        };
    }

    $pm->finish(0, \%local_data);
}

$pm->wait_all_children;

# --- Perform Copy Operations & Format Priority ---
draw_dashboard("Applying format priorities and copying...");

my $last_ui_update = time();

for my $group_key (sort keys %target_groups) {
    my @candidates = @{ $target_groups{$group_key} };

    # Sort candidates (Format priority > File size tie-breaker)
    @candidates = sort {
        $a->{priority} <=> $b->{priority}
        ||
        (-s $b->{orig_path}) <=> (-s $a->{orig_path})
    } @candidates;

    my $winner = shift @candidates;

    # Construct target folder inside Processed/
    my $target_subdir = File::Spec->catdir($dest_dir, $winner->{rel_dir});
    unless (-d $target_subdir) {
        make_path($target_subdir) or warn "Failed to create directory '$target_subdir': $!\n";
    }

    my $dest_filename = "$winner->{target_base}.$winner->{ext}";
    my $dest_path     = File::Spec->catfile($target_subdir, $dest_filename);

    copy($winner->{orig_path}, $dest_path);
    $stats{processed}++;

    $stats{underscores_fixed}++ if $winner->{underscores};
    $stats{spaces_fixed}++      if $winner->{spaces};
    $stats{capitalized}++       if $winner->{capitalized};
    $stats{files_relocated}++   if $winner->{relocated};

    for my $dup (@candidates) {
        $stats{duplicates_skipped}++;

        my $reason;
        if ($dup->{priority} == $winner->{priority}) {
            my $win_bytes = -s $winner->{orig_path};
            my $dup_bytes = -s $dup->{orig_path};
            $reason = sprintf("Smaller file (%d bytes) than winner (%d bytes) [same .%s format]", $dup_bytes, $win_bytes, $winner->{ext});
        } else {
            $reason = "Lower priority (.$dup->{ext}) than winner (.$winner->{ext})";
        }

        push @report_duplicates, "$dup->{orig_file} [Skipped: $reason]";
    }

    if (time() - $last_ui_update > 0.05) {
        draw_dashboard_fields_only("Copying files to '$dest_dir'...");
        $last_ui_update = time();
    }
}

draw_dashboard("Processing Complete!");

# --- FINAL SUMMARY REPORT ---
print "\n\n";
print colored("=================================================================\n", 'magenta');
print colored("                        PROCESSING COMPLETE                      \n", 'bold white');
print colored("=================================================================\n\n", 'magenta');

printf(" %-35s : %s\n", "Total Files Scanned",       colored(sprintf("%6d", $stats{scanned}),            'bold white'));
printf(" %-35s : %s\n", "Files Copied (Processed)",    colored(sprintf("%6d", $stats{processed}),          'bold green'));
printf(" %-35s : %s\n", "Duplicates Skipped",         colored(sprintf("%6d", $stats{duplicates_skipped}), 'bold yellow'));
printf(" %-35s : %s\n", "Ignored Files",              colored(sprintf("%6d", $stats{ignored}),            'bold red'));
print colored("-----------------------------------------------------------------\n", 'bright_black');
printf(" %-35s : %s\n", "Underscores Converted",       colored(sprintf("%6d", $stats{underscores_fixed}), 'cyan'));
printf(" %-35s : %s\n", "Concentric Spaces Fixed",    colored(sprintf("%6d", $stats{spaces_fixed}),      'cyan'));
printf(" %-35s : %s\n", "Names Capitalized",          colored(sprintf("%6d", $stats{capitalized}),       'cyan'));

if ($has_artist_subdirs) {
    printf(" %-35s : %s\n", "Root Files Moved to Artist", colored(sprintf("%6d", $stats{files_relocated}), 'bright_cyan'));
}

print colored("=================================================================\n", 'magenta');
print colored("Done. All processed files copied to '$dest_dir'.\n\n", 'bold green');

sub draw_dashboard {
    my ($status) = @_;

    hide_cursor();

    print "\e[1;1H";
    print colored("=================================================================\n", 'green');

    my $title_text = sprintf("%sMUSIC FILE PROCESSOR (%d-Worker Parallel Edition)%s", $NOTE_LEFT, $MAX_WORKERS, $NOTE_RIGHT);
    
    # Calculate padding based on character count rather than byte length
    my $total_width = 65;
    my $pad_left    = int(($total_width - length($title_text)) / 2);
    my $padded_title = (' ' x $pad_left) . $title_text;

    printf("%s\n", colored(sprintf("%-65s", $padded_title), 'bold white'));

    print colored("=================================================================\n", 'green');
    print colored(" Status: ", 'bold yellow') . sprintf("%-45s", $status) . "\e[K\n";
    print colored("-----------------------------------------------------------------\n", 'cyan');
    printf(" %-35s : %s\n", "Total Files Scanned",       colored(sprintf("%6d", $stats{scanned}),            'bold white'));
    printf(" %-35s : %s\n", "Files Copied (Processed)",    colored(sprintf("%6d", $stats{processed}),          'bold green'));
    printf(" %-35s : %s\n", "Duplicates Skipped",         colored(sprintf("%6d", $stats{duplicates_skipped}), 'bold yellow'));
    printf(" %-35s : %s\n", "Ignored Files",              colored(sprintf("%6d", $stats{ignored}),            'bold red'));
    print colored("-----------------------------------------------------------------\n", 'bright_black');
    printf(" %-35s : %s\n", "Underscores Converted",       colored(sprintf("%6d", $stats{underscores_fixed}), 'cyan'));
    printf(" %-35s : %s\n", "Concentric Spaces Fixed",    colored(sprintf("%6d", $stats{spaces_fixed}),      'cyan'));
    printf(" %-35s : %s\n", "Names Capitalized",          colored(sprintf("%6d", $stats{capitalized}),       'cyan'));

    # Dynamically display relocation count if artist subdirectories exist in cwd
    if ($has_artist_subdirs) {
        printf(" %-35s : %s\n", "Root Files Moved to Artist", colored(sprintf("%6d", $stats{files_relocated}), 'bright_cyan'));
    }

    print colored("=================================================================\n", 'green');

    show_cursor();
}

sub detect_cpu_cores {
    my $cores;

    if ($^O eq 'MSWin32') {
        my $wmic = `wmic cpu get NumberOfCores 2>NUL`;
        if ($wmic) {
            my @lines = grep { /\d+/ } split(/\r?\n/, $wmic);
            my $sum = 0;
            $sum += $_ for grep { s/\D+//g; $_ } @lines;
            $cores = $sum if $sum > 0;
        }

        if (!$cores) {
            my $ps = `powershell -NoProfile -Command "(Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfCores -Sum).Sum" 2>NUL`;
            chomp($ps) if $ps;
            $cores = $ps if defined $ps && $ps =~ /^\d+$/ && $ps > 0;
        }
    } elsif ($^O eq 'linux') {
        if (open my $fh, '<', '/proc/cpuinfo') {
            my %physical_cores;
            my ($current_phys_id, $current_core_id) = (0, 0);

            while (my $line = <$fh>) {
                if ($line =~ /^physical id\s*:\s*(\d+)/) {
                    $current_phys_id = $1;
                }
                elsif ($line =~ /^core id\s*:\s*(\d+)/) {
                    $current_core_id = $1;
                    $physical_cores{"$current_phys_id:$current_core_id"} = 1;
                }
            }
            close $fh;

            my $count = scalar(keys %physical_cores);
            $cores = $count if $count > 0;
        }
    } elsif ($^O eq 'darwin') {
        my $sysctl = `sysctl -n hw.physicalcpu 2>/dev/null`;
        chomp($sysctl) if $sysctl;
        $cores = $sysctl if defined $sysctl && $sysctl =~ /^\d+$/ && $sysctl > 0;
    } elsif ($^O eq 'freebsd') {
        my $sysctl = `sysctl -n kern.smp.cores 2>/dev/null`;
        chomp($sysctl) if $sysctl;
        $cores = $sysctl if defined $sysctl && $sysctl =~ /^\d+$/ && $sysctl > 0;
    }

    $cores ||= 2;

    return $cores;
}

sub draw_dashboard_fields_only {
    my ($status) = @_;

    # Use cross-platform safe cursor save sequence (\e7 or \e[s)
    print $SAVE_CURSOR;
    hide_cursor();

    print "\e[4;10H" . sprintf("%-54s", $status) . "\e[K";
    print "\e[6;40H" . colored(sprintf("%6d", $stats{scanned}),            'bold white');
    print "\e[7;40H" . colored(sprintf("%6d", $stats{processed}),          'bold green');
    print "\e[8;40H" . colored(sprintf("%6d", $stats{duplicates_skipped}), 'bold yellow');
    print "\e[9;40H" . colored(sprintf("%6d", $stats{ignored}),            'bold red');

    print "\e[11;40H" . colored(sprintf("%6d", $stats{underscores_fixed}), 'cyan');
    print "\e[12;40H" . colored(sprintf("%6d", $stats{spaces_fixed}),      'cyan');
    print "\e[13;40H" . colored(sprintf("%6d", $stats{capitalized}),       'cyan');

    if ($has_artist_subdirs) {
        print "\e[14;40H" . colored(sprintf("%6d", $stats{files_relocated}), 'bright_cyan');
    }

    # Use cross-platform safe cursor restore sequence (\e8 or \e[u)
    print $RESTORE_CURSOR;
    show_cursor();
}

sub detect_utf8_support {
    my $is_utf8 = 0;

    # 1. Check Windows Environment
    if ($^O eq 'MSWin32') {
        if ($ENV{WT_SESSION}) {
            $is_utf8 = 1;
        } else {
            my $cp = `chcp 2>NUL`;
            $is_utf8 = 1 if $cp && $cp =~ /65001/;
        }
    }

    # 2. Check Standard Unix/Linux/macOS/BSD Locale Environment
    unless ($is_utf8) {
        for my $env_var (qw(LC_ALL LC_CTYPE LANG)) {
            if ($ENV{$env_var} && $ENV{$env_var} =~ /utf-?8/i) {
                $is_utf8 = 1;
                last;
            }
        }
    }

    # Enable UTF-8 encoding layer on STDOUT to silence wide character warnings
    if ($is_utf8) {
        binmode(STDOUT, ':encoding(UTF-8)');
    }

    return $is_utf8;
}

