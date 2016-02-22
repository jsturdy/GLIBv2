----------------------------------------------------------------------------------
-- Company:        IIHE - ULB
-- Engineer:       Thomas Lenzi (thomas.lenzi@cern.ch)
-- 
-- Create Date:    08:37:33 07/07/2015 
-- Design Name:    GLIB v2
-- Module Name:    fifo - Behavioral 
-- Project Name:   GLIB v2
-- Target Devices: xc6vlx130t-1ff1156
-- Tool versions:  ISE  P.20131013
-- Description: 
--
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.ipbus.all;
use work.system_package.all;
use work.user_package.all;

entity fifo is
port(

    rst             : in std_logic;
    wr_clk          : in std_logic;
    rd_clk          : in std_logic;
    din             : in std_logic_vector(15 downto 0);
    wr_en           : in std_logic;
    rd_en           : in std_logic;
    dout            : out std_logic_vector(31 downto 0);
    full            : out std_logic;
    empty           : out std_logic;
    valid           : out std_logic;
    underflow       : out std_logic;
    rd_data_count   : out std_logic_vector(16 downto 0)
    
);
end fifo;

architecture Behavioral of fifo is
    
    signal fifo_0_rd_en     : std_logic;
    signal fifo_0_dout      : std_logic_vector(31 downto 0);
    signal fifo_0_full      : std_logic;
    signal fifo_0_empty     : std_logic;
    signal fifo_0_valid     : std_logic;
    signal fifo_0_underflow : std_logic;
    signal fifo_0_count     : std_logic_vector(16 downto 0);
    
    signal fifo_1_rd_en     : std_logic;
    signal fifo_1_dout      : std_logic_vector(31 downto 0);
    signal fifo_1_full      : std_logic;
    signal fifo_1_empty     : std_logic;
    signal fifo_1_valid     : std_logic;
    signal fifo_1_underflow : std_logic;
    signal fifo_1_count     : std_logic_vector(16 downto 0);
    
    signal fifo_2_rd_en     : std_logic;
    signal fifo_2_dout      : std_logic_vector(31 downto 0);
    signal fifo_2_full      : std_logic;
    signal fifo_2_empty     : std_logic;
    signal fifo_2_valid     : std_logic;
    signal fifo_2_underflow : std_logic;
    signal fifo_2_count     : std_logic_vector(16 downto 0);
    
    signal fifo_3_full      : std_logic;
    signal fifo_3_empty     : std_logic;
    signal fifo_3_count     : std_logic_vector(16 downto 0);
    
begin
    
    full <= fifo_0_full and fifo_1_full and fifo_2_full and fifo_3_full;
    empty <= fifo_0_empty and fifo_1_empty and fifo_2_empty and fifo_3_empty;
    
    rd_data_count <= std_logic_vector(unsigned(fifo_0_count) + unsigned(fifo_1_count) + unsigned(fifo_2_count) + unsigned(fifo_3_count));
    
    fifo_tk_gtx_inst : entity work.fifo_tk_gtx
    port map(
        rst             => rst,
        wr_clk          => wr_clk,
        rd_clk          => wr_clk,
        din             => din,
        wr_en           => wr_en,
        rd_en           => fifo_0_rd_en,
        dout            => fifo_0_dout,
        full            => fifo_0_full,
        empty           => fifo_0_empty,
        valid           => fifo_0_valid,
        underflow       => fifo_0_underflow,
        rd_data_count   => fifo_0_count(12 downto 0)
    );
    
    fifo_tk_large_0_inst : entity work.fifo_tk_large
    port map (
        rst             => rst,   
        wr_clk          => wr_clk,
        rd_clk          => wr_clk,     
        din             => fifo_0_dout,
        wr_en           => fifo_0_valid,
        rd_en           => fifo_1_rd_en,
        dout            => fifo_1_dout,
        full            => fifo_1_full,
        empty           => fifo_1_empty,
        valid           => fifo_1_valid,
        underflow       => fifo_1_underflow,
        rd_data_count   => fifo_1_count(13 downto 0)   
    );
    
    fifo_tk_large_1_inst : entity work.fifo_tk_large
    port map (
        rst             => rst,   
        wr_clk          => wr_clk,
        rd_clk          => wr_clk,      
        din             => fifo_1_dout,
        wr_en           => fifo_1_valid,
        rd_en           => fifo_2_rd_en,
        dout            => fifo_2_dout,
        full            => fifo_2_full,
        empty           => fifo_2_empty,
        valid           => fifo_2_valid,
        underflow       => fifo_2_underflow,
        rd_data_count   => fifo_2_count(13 downto 0)   
    );
        
    fifo_tk_large_2_inst : entity work.fifo_tk_large
    port map (
        rst             => rst,   
        wr_clk          => wr_clk,
        rd_clk          => rd_clk,       
        din             => fifo_2_dout,
        wr_en           => fifo_2_valid,
        rd_en           => rd_en,
        dout            => dout,
        full            => fifo_3_full,
        empty           => fifo_3_empty,
        valid           => valid,
        underflow       => underflow,
        rd_data_count   => fifo_3_count(13 downto 0)   
    );

    process(wr_clk) 
    begin
        if (rising_edge(wr_clk)) then
            if (rst = '1') then            
                fifo_0_rd_en <= '0';
                fifo_1_rd_en <= '0';
                fifo_2_rd_en <= '0';
            else
                fifo_0_rd_en <= (not fifo_1_full) and (not fifo_0_rd_en) and (not fifo_0_valid);
                fifo_1_rd_en <= (not fifo_2_full) and (not fifo_1_rd_en) and (not fifo_1_valid);
                fifo_2_rd_en <= (not fifo_3_full) and (not fifo_2_rd_en) and (not fifo_2_valid);
            end if;
        end if;
    end process;
    
end Behavioral;