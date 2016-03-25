----------------------------------------------------------------------------------
-- Company: 
-- Engineer: Evaldas Juska (Evaldas.Juska@cern.ch)
-- 
-- Create Date:    12:00:00 02/26/2016
-- Design Name:    GLIB v2
-- Module Name:    Trigger
-- Project Name:   GLIB v2
-- Target Devices: xc6vlx130t-1ff1156
-- Tool versions:  ISE  P.20131013
-- Description:    This module is responsible for processing all trigger links and making trigger decission
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

entity trigger is
port(

    -- resets
    reset_i                     : in std_logic;

    -- inputs
    trig_data_links_i           : in trig_link_array_t(0 to number_of_optohybrids - 1);

    -- TTC
    ttc_clk_i                   : in std_logic;
    ttc_l1a_i                   : in std_logic;

    -- Outputs
    trig_led_o                  : out std_logic;
    
    -- IPbus
    ipb_clk_i                   : in std_logic;
	ipb_mosi_i                  : in ipb_wbus;
	ipb_miso_o                  : out ipb_rbus

);
end trigger;

architecture Behavioral of trigger is

begin


end Behavioral;

