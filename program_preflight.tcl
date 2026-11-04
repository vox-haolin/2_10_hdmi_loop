# Software preflight only. No cfg_program, erase or flash commands.
set script_dir [file dirname [info script]]
set bitstream_file [file normalize [file join $script_dir generate_bitstream hdmi_loop.sbit]]
if {![file isfile $bitstream_file] || [file size $bitstream_file] == 0} {
    error "Missing or empty bitstream: $bitstream_file"
}
set bitstream_channel [open $bitstream_file rb]
set header [read $bitstream_channel 16]
close $bitstream_channel
if {[string length $header] != 16} { error "Cannot read bitstream" }
puts "PDS_PROGRAM_PATHS_OK: [file size $bitstream_file] bytes"
