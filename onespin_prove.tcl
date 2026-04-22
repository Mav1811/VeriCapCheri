# Change working directory to the directory of the script
set SCRIPT_LOCATION [file dirname [file normalize [info script]]]
cd $SCRIPT_LOCATION

# Restart
set_mode setup
delete_design -both
remove_server -all

# Change style from name/name to name.name
set_session_option -naming_style sv



# Load the file(s) by using the SystemVerilog standard 2001
read_verilog -golden -version 2001 {
    mkCapChecker_Top.v
    FIFO2.v    
    
}


elaborate    -golden
compile      -golden
set_mode mv

read_sva fv_capchecker.sv Encoder.sv


#set_reset_sequence -golden rst=1

# Uncomment this line when formulating your properties
# check -all [get_assertions]
