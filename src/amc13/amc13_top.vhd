----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    15:51:51 06/17/2013 
-- Design Name: 
-- Module Name:    amc13_top - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
library UNISIM;
use UNISIM.VComponents.all;

entity amc13_top is
    Port ( TTC_CLK_p  : in  STD_LOGIC;
           TTC_CLK_n  : in  STD_LOGIC;
           TTC_data_p : in  STD_LOGIC;
           TTC_data_n : in  STD_LOGIC;
           TTC_CLK   : out  STD_LOGIC;
           TTCready  : out  STD_LOGIC;
           L1Accept  : out  STD_LOGIC;
           BCntRes   : out  STD_LOGIC;
           EvCntRes  : out  STD_LOGIC;
           SinErrStr : out  STD_LOGIC;
           DbErrStr  : out  STD_LOGIC;
           BrcstStr  : out  STD_LOGIC;
           Brcst     : out  STD_LOGIC_VECTOR (7 downto 2));
end amc13_top;

architecture Behavioral of amc13_top is
	COMPONENT TTC_decoder
	PORT(
		TTC_CLK_p  : IN std_logic;
		TTC_CLK_n  : IN std_logic;
		TTC_data_p : IN std_logic;
		TTC_data_n : IN std_logic;          
		Clock40   : OUT std_logic;
		TTCready  : OUT std_logic;
		L1Accept  : OUT std_logic;
		BCntRes   : OUT std_logic;
		EvCntRes  : OUT std_logic;
		SinErrStr : OUT std_logic;
		DbErrStr  : OUT std_logic;
		BrcstStr  : OUT std_logic;
		Brcst     : OUT std_logic_vector(7 downto 2)
		);
	END COMPONENT;
signal Clock40 : std_logic;
begin
Inst_TTC_decoder: TTC_decoder PORT MAP(
		TTC_CLK_p  => TTC_CLK_p,
		TTC_CLK_n  => TTC_CLK_n,
		TTC_data_p => TTC_data_p,
		TTC_data_n => TTC_data_n,
	--	Clock40   => Clock40,
		Clock40   => TTC_CLK,
		TTCready  => TTCready,
		L1Accept  => L1Accept,
		BCntRes   => BCntRes,
		EvCntRes  => EvCntRes,
		SinErrStr => SinErrStr,
		DbErrStr  => DbErrStr,
		BrcstStr  => BrcstStr,
		Brcst     => Brcst
	);
--ODDR_inst : ODDR
--   generic map(
--      DDR_CLK_EDGE => "OPPOSITE_EDGE", -- "OPPOSITE_EDGE" or "SAME_EDGE" 
--      INIT => '0',   -- Initial value for Q port ('1' or '0')
--      SRTYPE => "SYNC") -- Reset Type ("ASYNC" or "SYNC")
--   port map (
--      Q => TTC_CLK,   -- 1-bit DDR output
--      C => Clock40,    -- 1-bit clock input
--      CE => '1',  -- 1-bit clock enable input
--      D1 => '1',  -- 1-bit data input (positive edge)
--      D2 => '0',  -- 1-bit data input (negative edge)
--      R => '0',    -- 1-bit reset input
--      S => '0'     -- 1-bit set input
--   );


end Behavioral;

