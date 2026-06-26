# Export Vivado WARNING/CRITICAL WARNING/ERROR messages to CSV.
#
# The script discovers all project runs, records run freshness metadata, and
# combines indented continuation lines into the message that precedes them.

set project_dir "C:/Users/2009e/npuplace"
if {[info exists argv] && [llength $argv] >= 1} {
    set project_dir [lindex $argv 0]
}

set script_dir [file dirname [file normalize [info script]]]
set out_file "$script_dir/vivado_warnings.csv"
set project_file "$project_dir/npuplace.xpr"

proc csv_escape {value} {
    regsub -all {"} $value {""} value
    regsub -all {\r|\n} $value { } value
    return "\"$value\""
}

proc safe_get_property {property object {default ""}} {
    if {[catch {get_property $property $object} value]} {
        return $default
    }
    if {$value eq ""} {
        return $default
    }
    return $value
}

proc detect_stage {run_name} {
    if {[string match "impl_*" $run_name]} {
        return "implementation"
    }
    if {$run_name eq "synth_1"} {
        return "synthesis"
    }
    if {[string match "*_synth_*" $run_name]} {
        return "ooc_synthesis"
    }
    return "unknown"
}

proc file_timestamp {path} {
    if {![file exists $path]} {
        return ""
    }
    return [clock format [file mtime $path] -format "%Y-%m-%dT%H:%M:%S%z"]
}

proc extract_signal_or_object {description} {
    foreach pattern {
        {[Pp]ort connection '([^']+)'}
        {[Ii]nput port '([^']+)'}
        {[Pp]ort '?([^' ]+)'?}
        {DSP ([^ ]+)}
        {[Cc]ell '?([^' ]+)'?}
        {[Ii]nstance '([^']+)'}
        {[Mm]odule '([^']+)'}
        {[Ss]ignal '?([^' ]+)'?}
        {[Nn]et '?([^' ]+)'?}
    } {
        if {[regexp $pattern $description -> value]} {
            return [string trimright $value {,.:;}]
        }
    }
    return ""
}

proc extract_source_file {description} {
    if {[regexp {\[([^\]]+\.(s?v|vhdl|vhd|xdc|tcl)):([0-9]+)\]} $description -> file extension line]} {
        return [list $file $line]
    }
    return [list "" ""]
}

proc is_generated_context {description source_file object} {
    set combined [string tolower "$description $source_file $object"]
    foreach marker {
        "/npuplace.gen/"
        "axi_mem_intercon"
        "processing_system7"
        "design_1_xbar"
        "/auto_pc/"
        "/auto_us/"
        "couplers"
    } {
        if {[string first $marker $combined] >= 0} {
            return 1
        }
    }
    return 0
}

proc normalize_message {description} {
    regsub -all {\s+} [string trim $description] { } description
    return $description
}

proc write_message {
    fp run_name run_status run_progress needs_refresh run_timestamp stage
    log_file log_line severity id description seen_name total_name
} {
    upvar 1 $seen_name seen_messages
    upvar 1 $total_name total_count

    set description [normalize_message $description]
    if {$description eq ""} {
        return
    }

    set unique_key "$run_name|$severity|$id|$description"
    if {[info exists seen_messages($unique_key)]} {
        return
    }
    set seen_messages($unique_key) 1

    set object [extract_signal_or_object $description]
    lassign [extract_source_file $description] source_file source_line
    set generated_context [is_generated_context $description $source_file $object]

    puts $fp [join [list \
        [csv_escape $run_name] \
        [csv_escape $run_status] \
        [csv_escape $run_progress] \
        [csv_escape $needs_refresh] \
        [csv_escape $run_timestamp] \
        [csv_escape $stage] \
        [csv_escape $log_file] \
        $log_line \
        [csv_escape $severity] \
        [csv_escape $id] \
        [csv_escape $object] \
        [csv_escape $source_file] \
        [csv_escape $source_line] \
        $generated_context \
        [csv_escape $description] \
    ] ,]
    incr total_count
}

proc parse_log {
    fp run_name run_status run_progress needs_refresh stage log_file seen_name total_name
} {
    upvar 1 $seen_name seen_messages
    upvar 1 $total_name total_count

    set run_timestamp [file_timestamp $log_file]
    set fin [open $log_file "r"]
    fconfigure $fin -encoding utf-8

    set line_no 0
    set pending 0
    set pending_line 0
    set pending_severity ""
    set pending_id ""
    set pending_description ""

    while {[gets $fin line] >= 0} {
        incr line_no

        if {[regexp {^(WARNING|CRITICAL WARNING|ERROR): \[([^\]]+)\] (.*)$} $line -> severity id description]} {
            if {$pending} {
                write_message $fp $run_name $run_status $run_progress $needs_refresh \
                    $run_timestamp $stage $log_file $pending_line $pending_severity \
                    $pending_id $pending_description seen_messages total_count
            }
            set pending 1
            set pending_line $line_no
            set pending_severity $severity
            set pending_id $id
            set pending_description $description
            continue
        }

        if {$pending && [regexp {^\s+(.+)$} $line -> continuation]} {
            append pending_description " " [string trim $continuation]
            continue
        }

        if {$pending} {
            write_message $fp $run_name $run_status $run_progress $needs_refresh \
                $run_timestamp $stage $log_file $pending_line $pending_severity \
                $pending_id $pending_description seen_messages total_count
            set pending 0
        }
    }

    if {$pending} {
        write_message $fp $run_name $run_status $run_progress $needs_refresh \
            $run_timestamp $stage $log_file $pending_line $pending_severity \
            $pending_id $pending_description seen_messages total_count
    }

    close $fin
}

proc discover_run_records {project_dir project_file} {
    set records {}
    set opened_project 0

    if {[file exists $project_file]} {
        if {[catch {open_project -quiet $project_file} project_error]} {
            puts "Project open failed; using filesystem fallback: $project_error"
        } else {
            set opened_project 1
            foreach run [get_runs -quiet] {
                set run_name [safe_get_property NAME $run $run]
                set run_dir [safe_get_property DIRECTORY $run "$project_dir/npuplace.runs/$run_name"]
                set run_status [safe_get_property STATUS $run "unknown"]
                set run_progress [safe_get_property PROGRESS $run "unknown"]
                set needs_refresh [safe_get_property NEEDS_REFRESH $run "unknown"]
                lappend records [list $run_name $run_dir $run_status $run_progress $needs_refresh]
            }
        }
    }

    if {[llength $records] == 0} {
        foreach run_dir [glob -nocomplain -types d "$project_dir/npuplace.runs/*"] {
            set run_name [file tail $run_dir]
            if {[string match ".*" $run_name]} {
                continue
            }
            lappend records [list $run_name $run_dir "unknown" "unknown" "unknown"]
        }
    }

    return [list $records $opened_project]
}

lassign [discover_run_records $project_dir $project_file] run_records opened_project

set fp [open $out_file "w"]
puts $fp "run_name,run_status,run_progress,needs_refresh,run_timestamp,stage,log_file,log_line,severity,id,signal_or_object,source_file,source_line,generated_context,message"

set total_count 0
set parsed_log_count 0
array set seen_messages {}

foreach record $run_records {
    lassign $record run_name run_dir run_status run_progress needs_refresh
    set stage [detect_stage $run_name]
    set log_files [list "$run_dir/runme.log"]

    foreach message_db [glob -nocomplain -types f "$run_dir/*.vds" "$run_dir/*.vdi"] {
        if {![string match "*.backup.vdi" $message_db]} {
            lappend log_files $message_db
        }
    }

    foreach log_file [lsort -unique $log_files] {
        if {![file exists $log_file]} {
            continue
        }
        parse_log $fp $run_name $run_status $run_progress $needs_refresh \
            $stage $log_file seen_messages total_count
        incr parsed_log_count
    }
}

close $fp
if {$opened_project} {
    close_project
}

puts "Wrote $out_file"
puts "Discovered [llength $run_records] run(s)"
puts "Parsed $parsed_log_count log/message database file(s)"
puts "Exported $total_count unique message(s)"
