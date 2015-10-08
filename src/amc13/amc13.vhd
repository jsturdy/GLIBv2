----------------------------------------------------------------------------------
-- Company: EDF Boston University
-- Engineer: Shouxiang Wu 
-- 
-- Create Date:    14:53:20 05/24/2010 
-- Design Name: 
-- Module Name:    TTC_decoder - Behavioral 
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
-- TTC Hamming encoding
-- hmg[0] = d[0]^d[1]^d[2]^d[3];
-- hmg[1] = d[0]^d[4]^d[5]^d[6];
-- hmg[2] = d[1]^d[2]^d[4]^d[5]^d[7];
-- hmg[3] = d[1]^d[3]^d[4]^d[6]^d[7];
-- hmg[4] = d[0]^d[2]^d[3]^d[5]^d[6]^d[7];
--
-- As no detailed timing of TTCrx chip is available, L1A may need to add several clocks of delay pending test results -- May 27 2010
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.std_logic_misc.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
library UNISIM;
use UNISIM.VComponents.all;

entity TTC_decoder is
    Port ( TTC_CLK_p : in  STD_LOGIC;
           TTC_CLK_n : in  STD_LOGIC;
           TTC_data_p : in  STD_LOGIC;
           TTC_data_n : in  STD_LOGIC;
           Clock40 : out  STD_LOGIC;
           TTCready : out  STD_LOGIC;
           L1Accept : out  STD_LOGIC;
           BCntRes : out  STD_LOGIC;
           EvCntRes : out  STD_LOGIC;
           SinErrStr : out  STD_LOGIC;
           DbErrStr : out  STD_LOGIC;
           BrcstStr : out  STD_LOGIC;
           Brcst : out  STD_LOGIC_VECTOR (7 downto 2));
end TTC_decoder;

architecture Behavioral of TTC_decoder is
constant Coarse_Delay: std_logic_vector(3 downto 0) := x"0";
signal TTC_CLK_in : std_logic := '0';
signal TTC_CLK_dcm : std_logic := '0';
signal TTC_CLK : std_logic := '0';
signal DCM_DO : std_logic_vector(15 downto 0) := (others => '0');
signal CLKFB_dcm : std_logic := '0';
signal CLKFB : std_logic := '0';
signal TTC_data_in : std_logic := '0';
signal TTC_data : std_logic_vector(1 downto 0) := (others => '0');
signal L1A : std_logic := '0';
signal sr : std_logic_vector(12 downto 0) := (others => '0');
signal rec_cntr : std_logic_vector(5 downto 0) := (others => '0');
signal rec_cmd : std_logic := '0';
signal FMT : std_logic := '0';
signal brcst_str : std_logic_vector(3 downto 0) := (others => '0');
signal brcst_data : std_logic_vector(7 downto 0) := (others => '0');
signal brcst_syn : std_logic_vector(4 downto 0) := (others => '0');
signal frame_err : std_logic := '0';
signal single_err : std_logic := '0';
signal double_err : std_logic := '0';
signal EvCntReset : std_logic := '0';
signal BCntReset : std_logic := '0';
--signal brcst_cmd : std_logic_vector(13 downto 0) := (others => '0');
begin
Clock40 <= TTC_CLK;

i_TTC_CLK_in: ibufds generic map(DIFF_TERM => TRUE,IOSTANDARD => "LVDS_25") port map(i => TTC_CLK_p, ib => TTC_CLK_n, o => TTC_CLK_in);
i_TTC_data_in: ibufds generic map(DIFF_TERM => TRUE,IOSTANDARD => "LVDS_25") port map(i => TTC_data_p, ib => TTC_data_n, o => TTC_data_in);
i_DCM_TTC_CLK : DCM_ADV
   generic map (
      CLKIN_PERIOD => 24.95, -- Specify period of input clock in ns from 1.25 to 1000.00
      CLKOUT_PHASE_SHIFT => "FIXED", -- Specify phase shift mode of NONE or FIXED
      DESKEW_ADJUST => "SOURCE_SYNCHRONOUS", -- SOURCE_SYNCHRONOUS, SYSTEM_SYNCHRONOUS or
      PHASE_SHIFT => -10, -- Amount of fixed phase shift from -255 to 1023
      STARTUP_WAIT => FALSE) -- Delay configuration DONE until DCM LOCK, TRUE/FALSE
   port map (
      CLK0 => TTC_CLK_dcm,         -- 0 degree DCM CLK ouptput
      CLKFB => TTC_CLK,       -- DCM clock feedback
      CLKIN => TTC_CLK_in,       -- Clock input (from IBUFG, BUFG or DCM)
      LOCKED => TTCready,     -- DCM LOCK status output
      DO => DCM_DO,             -- 16-bit data output for Dynamic Reconfiguration Port (DRP)
      RST => DCM_DO(1)            -- DCM asynchronous reset input
   );
i_TTC_CLK_buf: bufg port map(i => TTC_CLK_dcm, o => TTC_CLK);
i_TTC_data : IDDR 
   generic map (
      DDR_CLK_EDGE => "SAME_EDGE", -- "OPPOSITE_EDGE", "SAME_EDGE" 
                                       -- or "SAME_EDGE_PIPELINED" 
      INIT_Q1 => '0', -- Initial value of Q1: '0' or '1'
      INIT_Q2 => '0', -- Initial value of Q2: '0' or '1'
      SRTYPE => "SYNC") -- Set/Reset type: "SYNC" or "ASYNC" 
   port map (
      Q1 => TTC_data(0), -- 1-bit output for positive edge of clock 
      Q2 => TTC_data(1), -- 1-bit output for negative edge of clock
      C => TTC_CLK,   -- 1-bit clock input
      CE => '1', -- 1-bit clock enable input
      D => TTC_data_in,   -- 1-bit DDR data input
      R => '0',   -- 1-bit reset
      S => '0'    -- 1-bit set
      );
process(TTC_CLK)
begin
	if(TTC_CLK'event and TTC_CLK = '1')then
		L1A <= TTC_data(0);
		if(rec_cmd = '0')then
			rec_cntr <= (others => '0');
		else
			rec_cntr <= rec_cntr + 1;
		end if;
		if(rec_cntr(5 downto 3) = "101" or (FMT = '0' and rec_cntr(3 downto 0) = x"d"))then
			rec_cmd <= '0';
		elsif(TTC_data(1) = '0')then
			rec_cmd <= '1';
		end if;
		if(or_reduce(rec_cntr) = '0')then
			FMT <= TTC_data(1);
		end if;
		sr <= sr(11 downto 0) & TTC_data(1);
		if(FMT = '0' and rec_cntr(3 downto 0) = x"e")then
			brcst_data <= sr(12 downto 5);
			brcst_syn(0) <= sr(0) xor sr(5) xor sr(6) xor sr(7) xor sr(8);
			brcst_syn(1) <= sr(1) xor sr(5) xor sr(9) xor sr(10) xor sr(11);
			brcst_syn(2) <= sr(2) xor sr(6) xor sr(7) xor sr(9) xor sr(10) xor sr(12);
			brcst_syn(3) <= sr(3) xor sr(6) xor sr(8) xor sr(9) xor sr(11) xor sr(12);
			brcst_syn(4) <= xor_reduce(sr);
			frame_err <= TTC_data(0);
			brcst_str(0) <= '1';
		else
			brcst_str(0) <= '0';
		end if;
		brcst_str(1) <= brcst_str(0);
		single_err <= xor_reduce(brcst_syn) and not frame_err;
		if((or_reduce(brcst_syn) = '1' and xor_reduce(brcst_syn) = '0') or frame_err = '1')then
			double_err <= '1';
		else
			double_err <= '0';
		end if;
		SinErrStr <= single_err and brcst_str(1);
		DbErrStr <= double_err and brcst_str(1);
		brcst_str(2) <= brcst_str(1) and not double_err;
		if(brcst_syn(3 downto 0) = x"c")then
			Brcst(7) <= not brcst_data(7);
		else
			Brcst(7) <= brcst_data(7);
		end if;
		if(brcst_syn(3 downto 0) = x"a")then
			Brcst(6) <= not brcst_data(6);
		else
			Brcst(6) <= brcst_data(6);
		end if;
		if(brcst_syn(3 downto 0) = x"6")then
			Brcst(5) <= not brcst_data(5);
		else
			Brcst(5) <= brcst_data(5);
		end if;
		if(brcst_syn(3 downto 0) = x"e")then
			Brcst(4) <= not brcst_data(4);
		else
			Brcst(4) <= brcst_data(4);
		end if;
		if(brcst_syn(3 downto 0) = x"9")then
			Brcst(3) <= not brcst_data(3);
		else
			Brcst(3) <= brcst_data(3);
		end if;
		if(brcst_syn(3 downto 0) = x"5")then
			Brcst(2) <= not brcst_data(2);
		else
			Brcst(2) <= brcst_data(2);
		end if;
		if(brcst_syn(3 downto 0) = x"d")then
			EvCntReset <= not brcst_data(1);
		else
			EvCntReset <= brcst_data(1);
		end if;
		if(brcst_syn(3 downto 0) = x"3")then
			BCntReset <= not brcst_data(0);
		else
			BCntReset <= brcst_data(0);
		end if;
		BCntRes <= brcst_str(3) and BCntReset;
		EvCntRes <= brcst_str(3) and EvCntReset;
		BrcstStr <= brcst_str(3);
	end if;
end process;
i_L1Accept : SRL16E
   port map (
      Q => L1Accept,       -- SRL data output
      A0 => Coarse_Delay(0),     -- Select[0] input
      A1 => Coarse_Delay(1),     -- Select[1] input
      A2 => Coarse_Delay(2),     -- Select[2] input
      A3 => Coarse_Delay(3),     -- Select[3] input
      CE => '1',     -- Clock enable input
      CLK => TTC_CLK,   -- Clock input
      D => L1A        -- SRL data input
   );
i_brcst_str3 : SRL16E
   port map (
      Q => brcst_str(3),       -- SRL data output
      A0 => Coarse_Delay(0),     -- Select[0] input
      A1 => Coarse_Delay(1),     -- Select[1] input
      A2 => Coarse_Delay(2),     -- Select[2] input
      A3 => Coarse_Delay(3),     -- Select[3] input
      CE => '1',     -- Clock enable input
      CLK => TTC_CLK,   -- Clock input
      D => brcst_str(2)        -- SRL data input
   );
end Behavioral;
