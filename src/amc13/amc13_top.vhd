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

library work;

entity amc13_top is
port( 
    ref_clk_i   : in std_logic;
    ttc_clk_p   : in  std_logic;
    ttc_clk_n   : in  std_logic;
    ttc_data_p  : in  std_logic;
    ttc_data_n  : in  std_logic;
    ttc_clk     : out  std_logic;
    ttcready    : out  std_logic;
    l1accept    : out  std_logic;
    bcntres     : out  std_logic;
    evcntres    : out  std_logic;
    sinerrstr   : out  std_logic;
    dberrstr    : out  std_logic;
    brcststr    : out  std_logic;
    brcst       : out  std_logic_vector (7 downto 2)
);
end amc13_top;

architecture Behavioral of amc13_top is
    
    signal ttc_rst      : std_logic;
    signal ttc_rst_cnt  : integer range 0 to 67_108_863;
    
begin

    ttc_decoder_inst : entity work.ttc_decoder 
    port map(
        ttc_clk_p   => ttc_clk_p,
        ttc_clk_n   => ttc_clk_n,
        ttc_rst     => ttc_rst,
        ttc_data_p  => ttc_data_p,
        ttc_data_n  => ttc_data_n,
        ttc_clk_out => ttc_clk,
        ttcready    => ttcready,
        l1accept    => l1accept,
        bcntres     => bcntres,
        evcntres    => evcntres,
        sinerrstr   => sinerrstr,
        dberrstr    => dberrstr,
        brcststr    => brcststr,
        brcst       => brcst
    );
    
    process(ref_clk_i)
    begin
        if (rising_edge(ref_clk_i)) then
            if (ttc_rst_cnt = 60_000_000) then
              ttc_rst <= '0';
              ttc_rst_cnt <= 60_000_000;
            else
              ttc_rst <= '1';
              ttc_rst_cnt <= ttc_rst_cnt + 1;
            end if;
        end if;
    end process;
        
end Behavioral;

