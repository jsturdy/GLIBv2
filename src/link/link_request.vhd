----------------------------------------------------------------------------------
-- Company:        IIHE - ULB
-- Engineer:       Thomas Lenzi (thomas.lenzi@cern.ch)
-- 
-- Create Date:    08:37:33 07/07/2015 
-- Design Name:    GLIB v2
-- Module Name:    link_request - Behavioral 
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

entity link_request is
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
end link_request;

architecture Behavioral of link_request is

    type state_t is (IDLE, RSPD, ACK, RST);
    
    signal state            : state_t;
    
    signal wr_en            : std_logic;    
    signal wr_data          : std_logic_vector(64 downto 0);  
    
    signal rd_valid         : std_logic;     
    signal rd_data          : std_logic_vector(31 downto 0); 
    
begin

    --== TX process ==--

    process(ipb_clk_i)       
    begin    
        if (rising_edge(ipb_clk_i)) then      
            if (reset_i = '1') then    
                ipb_miso_o <= (ipb_err => '0', ipb_ack => '0', ipb_rdata => (others => '0')); 
                state <= IDLE;
                wr_en <= '0';                
                wr_data <= (others => '0');             
            else         
                case state is
                    when IDLE =>    
                        if (ipb_mosi_i.ipb_strobe = '1') then
                            wr_en <= '1';
                            wr_data <= ipb_mosi_i.ipb_write & ipb_mosi_i.ipb_addr(31 downto 24) & "0000" & ipb_mosi_i.ipb_addr(19 downto 0) & ipb_mosi_i.ipb_wdata;
                            state <= RSPD;
                        end if;
                    when RSPD =>
                        wr_en <= '0';                        
                        if (ipb_mosi_i.ipb_strobe = '0') then
                            state <= IDLE;                        
                        elsif (rd_valid = '1') then
                            ipb_miso_o <= (ipb_ack => '1', ipb_err => '0', ipb_rdata => rd_data);
                            state <= RST;
                        end if;
                    when RST =>
                        ipb_miso_o.ipb_ack <= '0';
                        state <= IDLE;  
                    when others =>
                        ipb_miso_o <= (ipb_err => '0', ipb_ack => '0', ipb_rdata => (others => '0')); 
                        state <= IDLE;
                        wr_en <= '0';                
                        wr_data <= (others => '0');  
                end case;                      
            end if;        
        end if;        
    end process;
    
    --== TX buffer ==--
    
    fifo_gtx_tx_inst : entity work.fifo_gtx_tx
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
    
    fifo_gtx_rx_inst : entity work.fifo_gtx_rx
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
    
end Behavioral;