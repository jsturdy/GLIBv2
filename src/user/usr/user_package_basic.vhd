library ieee;
use ieee.std_logic_1164.all;
 
package user_package is

	--=== system options ========--
    
   constant sys_eth_p1_enable           : boolean  := false;   
   constant sys_pcie_enable             : boolean  := false;      
  
	--=== i2c master components ==--
    
	constant i2c_master_enable			: boolean  := true;
	constant auto_eeprom_read_enable    : boolean  := true;    

    --=== wishbone slaves ========--
    
	constant number_of_wb_slaves		: positive := 1;

	constant user_wb_regs               : integer  := 0;
	
    --=== ipb slaves =============--
    
	constant number_of_ipb_slaves		: positive := 5;
   
	constant ipb_gtx_forward_0          : integer  := 0;
	constant ipb_gtx_forward_1          : integer  := 1;
	constant ipb_evt_data_0             : integer  := 2;
	constant ipb_evt_data_1             : integer  := 3;
    constant ipb_counters               : integer  := 4;

    --=== gtx links =============--
    
    constant number_of_optohybrids      : integer  := 2;    
    
    --============--
    --== Common ==--
    --============--   
    
    type std_array_t is array(integer range <>) of std_logic;
    
    type std32_array_t is array(integer range <>) of std_logic_vector(31 downto 0);
        
    type std16_array_t is array(integer range <>) of std_logic_vector(15 downto 0);

    --================--
    --== T1 command ==--
    --================--
    
    type t1_t is record
        lv1a        : std_logic;
        calpulse    : std_logic;
        resync      : std_logic;
        bc0         : std_logic;
    end record;
    
    type t1_array_t is array(integer range <>) of t1_t;
	
end user_package;
   
package body user_package is
end user_package;