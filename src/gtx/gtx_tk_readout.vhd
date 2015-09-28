----------------------------------------------------------------------------------
-- Company:        IIHE - ULB
-- Engineer:       Thomas Lenzi (thomas.lenzi@cern.ch)
-- 
-- Create Date:    14:48:50 09/21/2015 
-- Design Name:    GLIB v2
-- Module Name:    gtx_tk_readout - Behavioral 
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

entity gtx_tk_readout is
port(

	ipb_clk_i   : in std_logic;
	gtx_clk_i   : in std_logic;
	reset_i     : in std_logic;
    
	ipb_mosi_i  : in ipb_wbus;
	ipb_miso_o  : out ipb_rbus;
    
    evt_en_i     : in std_logic;
    evt_data_i   : in std_logic_vector(15 downto 0)
    
);
end gtx_tk_readout;

architecture Behavioral of gtx_tk_readout is 

    signal last_ipb_stobe   : std_logic;
    
    signal rd_en            : std_logic;
    signal rd_valid         : std_logic;
    signal rd_underflow     : std_logic;
    signal rd_data          : std_logic_vector(31 downto 0);
    
begin
    
    --== RX buffer ==--
    
    fifo8192x16_inst : entity work.fifo8192x16
    port map(
        rst         => (reset_i or (ipb_mosi_i.ipb_strobe and ipb_mosi_i.ipb_write)),
        wr_clk      => gtx_clk_i,
        wr_en       => evt_en_i,
        din         => evt_data_i,        
        rd_clk      => ipb_clk_i,
        rd_en       => rd_en,
        valid       => rd_valid,
        underflow   => rd_underflow,
        dout        => rd_data,
        full        => open,
        empty       => open
    );

    --== Buffer readout ==--

    process(ipb_clk_i)       
    begin    
        if (rising_edge(ipb_clk_i)) then      
            if (reset_i = '1') then  
                ipb_miso_o <= (ipb_ack => '0', ipb_err => '0', ipb_rdata => (others => '0'));
                last_ipb_stobe <= '0';     
                rd_en <= '0';           
            else     
                rd_en <= ((not last_ipb_stobe) and ipb_mosi_i.ipb_strobe); -- !0 and 1
                ipb_miso_o <= (ipb_ack => rd_valid, ipb_err => rd_underflow, ipb_rdata => rd_data);
                last_ipb_stobe <= ipb_mosi_i.ipb_strobe;            
            end if;        
        end if;        
    end process;

end Behavioral;

