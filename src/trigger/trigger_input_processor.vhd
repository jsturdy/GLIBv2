----------------------------------------------------------------------------------
-- Company: 
-- Engineer: Evaldas Juska (Evaldas.Juska@cern.ch)
-- 
-- Create Date:    12:00:00 02/26/2016
-- Design Name:    GLIB v2
-- Module Name:    Trigger Input Processor
-- Project Name:   GLIB v2
-- Target Devices: xc6vlx130t-1ff1156
-- Tool versions:  ISE  P.20131013
-- Description:    This module is responsible for processing trigger (sbit) link data, doing preliminary checks, buffering, matching to L1A and pushing to a FIFO for readout
--
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;

library work;
use work.ipbus.all;
use work.system_package.all;
use work.user_package.all;

entity trigger_input_processor is
port(
    trig_link           : in trig_link_t
);
end trigger_input_processor;

architecture Behavioral of trigger_input_processor is

begin


end Behavioral;

