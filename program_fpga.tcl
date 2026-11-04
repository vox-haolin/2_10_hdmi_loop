set script_dir [file dirname [info script]]
set bitstream_file [file normalize [file join $script_dir generate_bitstream hdmi_loop.sbit]]
if {![file isfile $bitstream_file] || [file size $bitstream_file] == 0} {
    error "Missing or empty bitstream: $bitstream_file"
}
cfg_assign_file -d 0 -f $bitstream_file
cfg_program -d 0
puts "PDS_PROGRAM_COMMAND_FINISHED"
