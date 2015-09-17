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
    
    tx_en_o     : out std_logic;
    tx_ack_i    : in std_logic;
    tx_data_o   : out std_logic_vector(64 downto 0);
    
    rx_en_i     : in std_logic;
    rx_ack_o    : out std_logic;
    rx_data_i   : in std_logic_vector(31 downto 0)
    
);
end gtx_forward;

architecture Behavioral of gtx_forward is
    
    signal tx_en            : std_logic;    
    signal last_ipb_stobe   : std_logic;
    
    signal rx_ack           : std_logic;
    
begin

    tx_en_o <= tx_en;
    rx_ack_o <= rx_ack;

    --== TX process ==--

    process(ipb_clk_i)       
    begin    
        if (rising_edge(ipb_clk_i)) then      
            if (reset_i = '1') then                
                tx_en <= '0';                
                tx_data_o <= (others => '0');                
                last_ipb_stobe <= '0';                
            else         
                -- GTX module is free
                if (tx_en = '0' and tx_ack_i = '0') then
                    -- Request to forward
                    if (last_ipb_stobe = '0' and ipb_mosi_i.ipb_strobe = '1') then 
                        -- Format request
                        tx_en <= '1';
                        tx_data_o <= ipb_mosi_i.ipb_write & ipb_mosi_i.ipb_addr & ipb_mosi_i.ipb_wdata;
                    -- No request
                    else                    
                        tx_en <= '0';
                    end if;      
                -- GTX module sent request
                elsif (tx_en = '1' and tx_ack_i = '1') then
                    -- Reset the strobe
                    tx_en <= '0';
                end if;
                -- Keep track fo the IPBus strobe
                last_ipb_stobe <= ipb_mosi_i.ipb_strobe;            
            end if;        
        end if;        
    end process;
    
    --== RX process ==--
    
    process(ipb_clk_i)
    begin    
        if (rising_edge(ipb_clk_i)) then        
            if (reset_i = '1') then
                rx_ack <= '0';
                ipb_miso_o.ipb_err <= '0';
                ipb_miso_o.ipb_ack <= '0';
                ipb_miso_o.ipb_rdata <= (others => '0');                
            else     
--                ipb_miso_o.ipb_err <= '0';
--                ipb_miso_o.ipb_ack <= ipb_mosi_i.ipb_strobe;
--                ipb_miso_o.ipb_rdata <= x"ABCD0123";
                -- Incoming data
                if (rx_en_i = '1' and rx_ack <= '0') then
                    rx_ack <= '1';
                    -- Return to IPBus
                    ipb_miso_o.ipb_err <= '0';
                    ipb_miso_o.ipb_ack <= ipb_mosi_i.ipb_strobe;
                    ipb_miso_o.ipb_rdata <= rx_data_i;
                -- 
                elsif (rx_en_i = '0' and rx_ack <= '1') then
                    rx_ack <= '0';
                    ipb_miso_o.ipb_ack <= '0';    
                -- No data
                else
                    ipb_miso_o.ipb_ack <= '0';      
                end if;
            end if;
        end if;
    end process;      
    
end Behavioral;