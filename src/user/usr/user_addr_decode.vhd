library IEEE;
use IEEE.STD_LOGIC_1164.all;
use ieee.numeric_std.all;
use work.ipbus.all;
use work.user_package.all;

package user_addr_decode is

	function user_wb_addr_sel (signal addr : in std_logic_vector(31 downto 0)) return integer;
	function user_ipb_addr_sel(signal addr : in std_logic_vector(31 downto 0)) return integer;

end user_addr_decode;

package body user_addr_decode is

	function user_ipb_addr_sel(signal addr : in std_logic_vector(31 downto 0)) return integer is
		variable sel : integer;
	begin
		if    std_match(addr, "0100----00000000----------------") then sel := ipb_gtx_forward_0;
		elsif std_match(addr, "0100----00010000----------------") then sel := ipb_gtx_forward_1;
		elsif std_match(addr, "010100000000000000000000000000--") then sel := ipb_evt_data_0;
		elsif std_match(addr, "010100000001000000000000000000--") then sel := ipb_evt_data_1;
		elsif std_match(addr, "011000000000000000000000--------") then sel := ipb_counters;
		elsif std_match(addr, "01110000000000000000000---------") then sel := ipb_daq;
		elsif std_match(addr, "01111000000000000000000---------") then sel := ipb_trigger;
		elsif std_match(addr, "01111100000000000000000000000---") then sel := ipb_ttc;
		else sel := 99;
		end if;
		return sel;
	end user_ipb_addr_sel;

   function user_wb_addr_sel(signal addr : in std_logic_vector(31 downto 0)) return integer is
		variable sel : integer;
   begin
		if   std_match(addr, "100000000000000000000000--------") then  	sel := user_wb_regs;
		else sel := 99;
		end if;
		return sel;
	end user_wb_addr_sel; 

end user_addr_decode;