#!/usr/bin/env bash
#
# Runs the installed aiolos binary on input files kept in ./wrk/, and collects
# the results of every run into its own timestamped subfolder.
#
#   ./run-aiolos.sh -p myrun.par -s myrun.spc
#
# Why this script exists: aiolos has to be started from the repository root
# (it opens the opacity tables as the literal relative path inputdata/<name>
# and never checks that the file opened, so a wrong working directory means a
# segfault with no error message), it reads its input files from whatever -dir
# points at, and it writes its ~150 output files straight back into that same
# directory. This wrapper does the bookkeeping and refuses to start when
# something is not as it should be.
#
# Run ./run-aiolos.sh -h for the full usage.

# No `set -e`: a failed simulation is a normal code path here, because the
# output files still have to be collected afterwards. Errors are reported
# explicitly through die() instead.
set -u
set -o pipefail

# An unmatched glob must expand to nothing rather than to itself, both for the
# leftover check and for the move at the end.
shopt -s nullglob
shopt -u dotglob

me=${0##*/}

# Where the user keeps their own parameter and species files.
wrkdir="./wrk"

# Default CMake preset, i.e. which build of the binary to run.
preset="macos-arm64"

parfile=""
spcfile=""
extra=()

# State shared with the finish() trap below. run_status and mark start out
# meaning "failed", so that an interrupted run is reported as one: on Ctrl-C
# the trap runs, but the lines that would set them never execute.
run_status=1
mark="FAILED"
results=""
finished=""

say()
{
    printf '%s\n' "$*"
}

warn()
{
    printf '%s: warning: %s\n' "$me" "$*" >&2
}

die()
{
    printf '%s: error: %s\n' "$me" "$*" >&2
    exit 1
}

usage()
{
    cat <<EOF
Usage: $me -p <file.par> -s <file.spc> [-c <cmake-preset>] [-- <aiolos flags>]
       $me -h

Runs ./install/<preset>/bin/aiolos on the input files in $wrkdir/ and moves the
resulting *.dat files into $wrkdir/results-<date>-<time>/ together with a copy
of the two input files and a run.log of everything the simulation printed.

Options:
  -p, --par <file.par>   parameter file, required. A bare file name: the script
                         looks for it inside $wrkdir/
  -s, --spc <file.spc>   species file, required. Also a bare file name
  -c, --cmake-preset <name>
                         CMake preset whose build to run, i.e. the binary
                         ./install/<name>/bin/aiolos. Default: $preset
  -h, --help             this text
  --                     everything after this is passed on to aiolos itself,
                         for example: -- -debug 2 -n 8 -war 1
                         (-dir, -par and -spc are set by this script)

Must be run from the aiolos repository root, because that is where aiolos
itself has to be started from.

Exit status: 1 if this script refused to run; otherwise the exit status of
aiolos itself (0 on success, 5 for a missing .par or a malformed .spc).
Note that aiolos also exits 0 when it ends in a soft crash; the script detects
that separately and names the results folder results-<date>-<time>-CRASH.
EOF
}

# Returns the preset name that matches the machine this script is running on,
# or nothing if there is no preset for it. Only used to make error messages
# more helpful.
preset_for_this_machine()
{
    case "$(uname -s)" in
        Darwin)
            case "$(uname -m)" in
                arm64|aarch64) printf 'macos-arm64' ;;
            esac
            ;;
        Linux)
            case "$(uname -m)" in
                aarch64|arm64) printf 'linux-arm64' ;;
                x86_64)        printf 'linux-x64' ;;
            esac
            ;;
    esac
}

#
# Collects the output files and marks the run, on every way out of this script:
# a normal end, a failure, and a Ctrl-C. Installed as an EXIT trap once the
# results folder exists. Bash runs an EXIT trap on SIGINT and SIGTERM too, so
# no separate INT/TERM trap is needed - and adding one would make this run
# twice. $? is 0 in here even after a Ctrl-C, which is why the outcome is
# tracked in run_status/mark instead.
#
finish()
{
    # Called once, even if bash decides to call the trap again.
    [ -n "$finished" ] && return 0
    finished="yes"

    # A second Ctrl-C must not interrupt the move half way through.
    trap '' INT

    # Nothing was created yet, so there is nothing to collect.
    [ -n "$results" ] || return 0

    # Marked before the output is moved, so that every message names the same
    # folder as the one the results end up in.
    if [ -n "$mark" ]
    then
        if mv -- "$results" "$results-$mark" 2>/dev/null
        then
            results="$results-$mark"
        else
            # Renaming can lose to an editor or a file manager holding the
            # folder open, so leave the marker inside it instead.
            : > "$results/$mark"
        fi
    fi

    # The footer is written by the main body once aiolos has returned, so its
    # absence means this run never got that far.
    if [ -f "$results/run.log" ] && ! grep -q -F -e '# aiolos exited' -- "$results/run.log"
    then
        printf '\n# interrupted before aiolos finished\n' >> "$results/run.log"
        say "The run was interrupted before it finished."
    fi

    local dat
    dat=("$wrkdir"/*.dat)
    if [ "${#dat[@]}" -gt 0 ]
    then
        if mv -- "${dat[@]}" "$results/"
        then
            say "Moved ${#dat[@]} output file(s) into $results/"
        else
            warn "could not move the output files out of $wrkdir/ into $results/."
            warn "Move them by hand, otherwise the next run will refuse to start."
        fi
    else
        say "The simulation did not produce any .dat files."
    fi

    say "Results are in $results/"
}

#
# Command line
#
# Parsed by hand rather than with getopts, because getopts takes an unknown
# long option apart letter by letter and silently forwards stray arguments,
# which makes for baffling error messages.
#
while [ $# -gt 0 ]
do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -p|--par)
            [ $# -ge 2 ] || die "-p needs the name of a parameter file, for example: -p myrun.par"
            parfile="$2"
            shift 2
            ;;
        -s|--spc)
            [ $# -ge 2 ] || die "-s needs the name of a species file, for example: -s myrun.spc"
            spcfile="$2"
            shift 2
            ;;
        -c|--cmake-preset)
            [ $# -ge 2 ] || die "-c needs the name of a CMake preset, for example: -c linux-arm64"
            preset="$2"
            shift 2
            ;;
        --)
            shift
            extra=("$@")
            break
            ;;
        -*)
            die "unknown option '$1'.
This script takes -p (--par), -s (--spc) and -c (--cmake-preset).
Flags meant for the simulation itself go after a '--', like this:
  ./$me -p myrun.par -s myrun.spc -- -debug 2 -n 8"
            ;;
        *)
            die "unexpected argument '$1'.
Input files are given with -p and -s, like this:
  ./$me -p myrun.par -s myrun.spc"
            ;;
    esac
done

#
# 1. Are we in the right place?
#
# The name of the folder is what the user was told to check, but the files are
# what actually matter, and a checkout is not always named "aiolos" (in a
# container it is often mounted somewhere else entirely).
#
if [ "${PWD##*/}" != "aiolos" ] \
    && ! { [ -f "aiolos.h" ] && [ -f "CMakeLists.txt" ] && [ -d "inputdata" ]; }
then
    die "this does not look like the aiolos repository.
Current directory: $PWD
Start the script from the repository root, the folder that holds aiolos.h,
CMakeLists.txt and inputdata/:
  cd /path/to/aiolos
  ./$me -p myrun.par -s myrun.spc
aiolos itself reads inputdata/ relative to the current directory, which is why
this matters."
fi

#
# 2. Is there a binary to run?
#
binary="./install/$preset/bin/aiolos"
if [ ! -f "$binary" ] && [ -f "$binary.exe" ]
then
    binary="$binary.exe"
fi

if [ ! -f "$binary" ]
then
    installed=(./install/*/bin/aiolos ./install/*/bin/aiolos.exe)
    message="there is no aiolos binary at $binary, so the project has not been
built and installed for the preset '$preset' yet. Build it with:
  cmake --preset $preset
  cmake --build --preset $preset"
    if [ "${#installed[@]}" -gt 0 ]
    then
        message="$message

Binaries that are installed right now:"
        for one in "${installed[@]}"
        do
            message="$message
  $one"
        done
        message="$message
Pick one of those presets with -c, for example: -c $(printf '%s' "${installed[0]}" | sed -e 's|^\./install/||' -e 's|/bin/aiolos.*$||')"
    fi
    die "$message"
fi
[ -x "$binary" ] || die "$binary is not executable.
Fix it with: chmod +x $binary"

#
# 3. Is there a working folder, with the input files in it?
#
[ -d "$wrkdir" ] || die "there is no $wrkdir/ folder.
Create it and put your parameter and species files in there:
  mkdir wrk
  cp test_files/planet_spherical.par test_files/mix3.spc wrk/"

[ -n "$parfile" ] || die "no parameter file given.
Name one with -p, for example: -p myrun.par
It has to be a file inside $wrkdir/ ($me -h explains why)."
[ -n "$spcfile" ] || die "no species file given.
Name one with -s, for example: -s myrun.spc
It has to be a file inside $wrkdir/ ($me -h explains why)."

# aiolos builds its input paths by gluing -dir and the file name together and
# it has no notion of paths at all, so a path here would look for the file in
# the wrong place and would also rename every output file.
case "$parfile" in
    */*|*\\*) die "-p takes a plain file name, not a path, but got '$parfile'.
The file has to be inside $wrkdir/, and you name it like this:
  -p ${parfile##*/}" ;;
esac
case "$spcfile" in
    */*|*\\*) die "-s takes a plain file name, not a path, but got '$spcfile'.
The file has to be inside $wrkdir/, and you name it like this:
  -s ${spcfile##*/}" ;;
esac

# "default.spc" is a magic value: aiolos treats it as "no species file was
# given on the command line" and takes SPECIES_FILE from the parameter file
# instead, which would quietly run a different mixture than the one asked for.
[ "$spcfile" != "default.spc" ] || die "'default.spc' cannot be used with -s.
aiolos reads that name as \"no species file was given\" and takes SPECIES_FILE
from the parameter file instead. Rename your file, to myrun.spc for instance,
and pass that."

missing=()
[ -f "$wrkdir/$parfile" ] || missing+=("$wrkdir/$parfile")
[ -f "$wrkdir/$spcfile" ] || missing+=("$wrkdir/$spcfile")
if [ "${#missing[@]}" -gt 0 ]
then
    message="input file(s) not found:"
    for one in "${missing[@]}"
    do
        message="$message
  $one"
    done
    die "$message
Both the parameter file and the species file have to sit inside $wrkdir/."
fi

# Flags this script sets itself must not be given twice.
if [ "${#extra[@]}" -gt 0 ]
then
    for one in "${extra[@]+"${extra[@]}"}"
    do
        case "$one" in
            -dir|-par|-spc) die "'$one' is set by this script and cannot be passed after '--'.
Use -p and -s for the input files; the working folder is always $wrkdir/." ;;
        esac
    done
fi

#
# 4. Is the working folder free of an earlier run?
#
# Only the folder itself is looked at, not the results-* subfolders, so results
# kept from earlier runs are fine where they are.
#
leftovers=("$wrkdir"/*.dat)
if [ "${#leftovers[@]}" -gt 0 ]
then
    message="$wrkdir/ still holds ${#leftovers[@]} .dat file(s) from an earlier run:"
    for one in "${leftovers[@]:0:5}"
    do
        message="$message
  $one"
    done
    [ "${#leftovers[@]}" -gt 5 ] && message="$message
  ... and $(( ${#leftovers[@]} - 5 )) more"
    die "$message
Move them into a folder of their own, or delete them, and run this again. A
finished run leaves nothing behind in $wrkdir/, so these are the remains of one
that was interrupted or was started by hand."
fi

#
# Checks that only warn. Each of these is something that aiolos either does not
# diagnose at all or reports in a way that points nowhere near the cause.
#
case "$parfile" in
    *.par) ;;
    *) warn "'$parfile' does not look like a parameter file (-p expects a *.par)." ;;
esac
case "$spcfile" in
    *.spc) ;;
    *) warn "'$spcfile' does not look like a species file (-s expects a *.spc)." ;;
esac

# aiolos names its output files after the part of the parameter file name
# before the *first* dot, so "run.v2.par" and "run.par" would write on top of
# each other.
parstem="${parfile%.par}"
case "$parstem" in
    *.*) warn "'$parfile' has a dot in its name besides the extension, so the output
         files will be named output_${parstem%%.*}_... and can collide with those
         of another run. A name without extra dots avoids that." ;;
esac

# aiolos looks for the key as a substring anywhere in the file, comments
# included, and refuses to start when it finds two of them.
species_lines=$(grep -c -F -e 'SPECIES_FILE' -- "$wrkdir/$parfile" 2>/dev/null || true)
if [ "${species_lines:-0}" -gt 1 ]
then
    warn "$parfile mentions SPECIES_FILE on $species_lines lines. aiolos counts
         commented-out lines as definitions too and will stop with \"defined more
         than once\" (exit 5). Delete the stale lines."
elif [ "${species_lines:-0}" -eq 1 ]
then
    species_in_par=$(awk '/SPECIES_FILE/ { print $2; exit }' "$wrkdir/$parfile")
    if [ -n "${species_in_par:-}" ] && [ "$species_in_par" != "$spcfile" ]
    then
        warn "$parfile says SPECIES_FILE $species_in_par, but -s says $spcfile.
         The command line wins silently, so the run will use $spcfile."
    fi
fi

# Columns 8 and 9 of a species row are mandatory but nothing says so: a short
# row makes aiolos throw from std::stod and exit 5 without naming the file.
# Counted the way aiolos counts, which is splitting on single spaces and
# throwing the empty pieces away - so a row held together by tabs counts as one
# column here, exactly as it does there, and shows up as short.
short_rows=$(awk '
    /^@/ {
        columns = 0
        pieces = split($0, piece, / /)
        for (i = 1; i <= pieces; i++)
        {
            if (piece[i] != "") columns++
        }
        if (columns < 10) short++
    }
    END { print short+0 }' "$wrkdir/$spcfile")
if [ "$short_rows" -gt 0 ]
then
    warn "$short_rows row(s) in $spcfile have fewer than 10 columns. The last two
         (is_dust_like and the opacity file) are mandatory even though nothing in
         the file format says so, and aiolos reads past the end of the row: it
         either stops with exit 5 or segfaults, without naming the file either
         way. Tabs are a common cause, as aiolos separates columns on spaces
         only."
fi

# The opacity file named in the last column is opened as inputdata/<name>,
# unchecked, so a typo there is a segfault rather than an error message. The
# 11th column is only a file name for opacity model K; several of the shipped
# species files have something else there, hence the test for a dot.
for one in $(awk '/^@/ && NF >= 10 { print $10; if (NF >= 11 && $11 ~ /\./) print $11 }' "$wrkdir/$spcfile" | sort -u)
do
    [ -f "inputdata/$one" ] || warn "$spcfile names the opacity file '$one', but inputdata/$one does not
         exist. Depending on the opacity model aiolos may open it without
         checking and then segfault."
done

#
# 5. Somewhere to put the results
#
# The folder is created rather than reused, because two runs must never end up
# mixing their output together. Runs started within the same second - which is
# what a loop over several parameter files does - get a counted suffix instead
# of being turned away.
#
stamp=$(date +%Y-%m-%d-%H%M%S)
results="$wrkdir/results-$stamp"
attempt=1
while ! mkdir -- "$results" 2>/dev/null
do
    [ -d "$results" ] || die "could not create the results folder $results/.
Check that $wrkdir/ is writable."
    attempt=$(( attempt + 1 ))
    [ "$attempt" -le 99 ] || die "could not find a free name for the results folder next to
$wrkdir/results-$stamp/."
    results="$wrkdir/results-$stamp-$attempt"
done

# From here on every way out of the script has to collect the output files.
trap finish EXIT

cp -- "$wrkdir/$parfile" "$wrkdir/$spcfile" "$results/" \
    || warn "could not copy the input files into $results/."

#
# 6. Run it
#
cmd=("$binary" -dir "$wrkdir/" -par "$parfile" -spc "$spcfile" "${extra[@]+"${extra[@]}"}")

runlog="$results/run.log"
{
    printf '# aiolos run started %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf '# repository root: %s\n' "$PWD"
    printf '# git commit: %s\n' "$(git rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
    printf '# command:'
    printf ' %q' "${cmd[@]}"
    printf '\n\n'
} > "$runlog"

say "Running: ${cmd[*]}"
say "Output of the run is also written to $runlog"
say ""

# Line-buffer the output where the tooling for it exists, so that the log is
# complete even if the simulation dies on a signal. GNU only, hence optional.
buffered=()
command -v stdbuf >/dev/null 2>&1 && buffered=(stdbuf -oL -eL)

"${buffered[@]+"${buffered[@]}"}" "${cmd[@]}" 2>&1 | tee -a -- "$runlog"
# Has to be the very next line: even a plain assignment resets PIPESTATUS.
run_status=${PIPESTATUS[0]}

printf '\n# aiolos exited with status %s at %s\n' \
    "$run_status" "$(date '+%Y-%m-%d %H:%M:%S')" >> "$runlog"

#
# 7. What happened?
#
say ""
if [ "$run_status" -eq 0 ]
then
    # A soft crash (a negative or NaN temperature, or a negative J) writes the
    # final snapshot and exits 0 like a successful run does, so the exit status
    # alone cannot be trusted.
    if grep -q -F -e '>>> CRASH <<<' -- "$runlog"
    then
        mark="CRASH"
        warn "the simulation ended in a crash, even though it exited cleanly:"
        grep -F -e '>>> CRASH <<<' -- "$runlog" >&2
        warn "The t-1 snapshot is a crash dump, not a finished state."
    else
        mark=""
        say "The simulation finished successfully."
    fi
else
    mark="FAILED"
    say "The simulation failed with exit status $run_status."
    case "$run_status" in
        2)   say "A command line flag was given without its value." ;;
        5)   say "Usually a parameter file that cannot be read, a parameter defined twice in
it, or a species file with a malformed row - every @ row needs all 10 columns.
What it printed is in the run.log of the results folder named below." ;;
        126|127)
             say "The binary could not be executed at all. It was most likely built for a
different operating system or processor than this one."
             suggestion="$(preset_for_this_machine)"
             if [ -n "$suggestion" ] && [ "$suggestion" != "$preset" ]
             then
                 say "For this machine, build and use the '$suggestion' preset:
  cmake --preset $suggestion
  cmake --build --preset $suggestion
  ./$me -c $suggestion -p $parfile -s $spcfile"
             fi
             ;;
        139) say "The simulation segfaulted. Early in a run that is usually an input file that
could not be opened, or a species row with fewer than 10 columns - aiolos
checks neither. The end of the run.log in the results folder named below shows
how far it got." ;;
        *)   say "What it printed is in the run.log of the results folder named below." ;;
    esac
fi

# The output files are collected by the EXIT trap, so that an interrupted run
# leaves the working folder just as tidy as a finished one.
exit "$run_status"
