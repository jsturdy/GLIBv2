----------------------------------------------------------------------------------
-- Company:        IIHE - ULB
-- Engineer:       Thomas Lenzi (thomas.lenzi@cern.ch)
-- 
-- Create Date:    08:37:33 07/07/2015 
-- Design Name:    GLIB v2
-- Module Name:    gtx_forward - Behavioral 
-- Project Name:   GLIB v2
-- Target Devices: xc6vlx130t-1ff1156
-- Tool versions:  ISE  P.20131013
-- Description: 
--
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.ipbus.all;
use work.system_package.all;
use work.user_package.all;

entity gtx_forward is
port(

	ipb_clk_i   : in std_logic;
	gtx_clk_i   : in std_logic;
	reset_i     : in std_logic;
    
	ipb_mosi_i  : in ipb_wbus;
	ipb_miso_o  : out ipb_rbus;
    
    tx_en_i     : in std_logic;
    tx_valid_o  : out std_logic;
    tx_data_o   : out std_logic_vector(64 downto 0);
    
    rx_en_i     : in std_logic;
    rx_data_i   : in std_logic_vector(31 downto 0)
    
);
end gtx_forward;

architecture Behavioral of gtx_forward is
    
    signal wr_en            : std_logic;    
    signal wr_data          : std_logic_vector(64 downto 0);    
    signal last_ipb_stobe   : std_logic;
    
    signal rd_valid         : std_logic;    
    signal rd_data          : std_logic_vector(31 downto 0); 
    
begin

    --== TX process ==--

    process(ipb_clk_i)       
    begin    
        if (rising_edge(ipb_clk_i)) then      
            if (reset_i = '1') then                
                wr_en <= '0';                
                wr_data <= (others => '0');                
                last_ipb_stobe <= '0';                
            else         
                wr_en <= ((not last_ipb_stobe) and ipb_mosi_i.ipb_strobe);
                wr_data <= ipb_mosi_i.ipb_write & ipb_mosi_i.ipb_addr(31 downto 24) & "0000" & ipb_mosi_i.ipb_addr(19 downto 0) & ipb_mosi_i.ipb_wdata;
                last_ipb_stobe <= ipb_mosi_i.ipb_strobe;            
            end if;        
        end if;        
    end process;
    
    --== TX buffer ==--
    
    fifo16x65_inst : entity work.fifo16x65
    port map(
        rst     => reset_i,
        wr_clk  => ipb_clk_i,
        wr_en   => wr_en,
        din     => wr_data,        
        rd_clk  => gtx_clk_i,
        rd_en   => tx_en_i,
        valid   => tx_valid_o,
        dout    => tx_data_o,
        full    => open,
        empty   => open
    );
    
    --== Process inbetween is handled by the optical link ==--

    --== RX buffer ==--
    
    fifo16x32_inst : entity work.fifo16x32
    port map(
        rst     => reset_i,
        wr_clk  => gtx_clk_i,
        wr_en   => rx_en_i,
        din     => rx_data_i,        
        rd_clk  => ipb_clk_i,
        rd_en   => '1',
        valid   => rd_valid,
        dout    => rd_data,
        full    => open,
        empty   => open
    );
    
    --== RX process ==--
    
    process(ipb_clk_i)
    begin    
        if (rising_edge(ipb_clk_i)) then        
            if (reset_i = '1') then
                ipb_miso_o <= (ipb_err => '0', ipb_ack => '0', ipb_rdata => (others => '0'));                
            else                               
                ipb_miso_o <= (ipb_err => '0', ipb_ack => (ipb_mosi_i.ipb_strobe and rd_valid), ipb_rdata => rd_data);
            end if;
        end if;
    end process;  
    
end Behavioral;