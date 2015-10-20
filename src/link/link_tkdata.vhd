----------------------------------------------------------------------------------
-- Company:        IIHE - ULB
-- Engineer:       Thomas Lenzi (thomas.lenzi@cern.ch)
-- 
-- Create Date:    14:48:50 09/21/2015 
-- Design Name:    GLIB v2
-- Module Name:    link_tkdata - Behavioral 
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

entity link_tkdata is
port(

	ipb_clk_i   : in std_logic;
	gtx_clk_i   : in std_logic;
	reset_i     : in std_logic;
    
	ipb_mosi_i  : in ipb_wbus;
	ipb_miso_o  : out ipb_rbus;
    
    evt_en_i     : in std_logic;
    evt_data_i   : in std_logic_vector(15 downto 0)
    
);
end link_tkdata;

architecture Behavioral of link_tkdata is 

    type state_t is (IDLE, RSPD, RST);
    
    signal state            : state_t;
    
    signal rd_en            : std_logic;
    signal rd_reset         : std_logic;
    signal rd_valid         : std_logic;
    signal rd_underflow     : std_logic;
    signal rd_data          : std_logic_vector(31 downto 0);
    signal rd_data_count    : std_logic_vector(16 downto 0);
    signal rd_full          : std_logic;
    signal rd_empty         : std_logic;
    
begin
    
    --== RX buffer ==--
    
    fifo_inst : entity work.fifo
    port map(
        rst             => (reset_i or rd_reset),
        wr_clk          => gtx_clk_i,
        wr_en           => evt_en_i,
        din             => evt_data_i,        
        rd_clk          => ipb_clk_i,
        rd_en           => rd_en,
        valid           => rd_valid,
        underflow       => rd_underflow,
        dout            => rd_data,
        rd_data_count   => rd_data_count,
        full            => rd_full,
        empty           => rd_empty
    );

    --== Buffer readout ==--

    process(ipb_clk_i)       
    begin    
        if (rising_edge(ipb_clk_i)) then      
            if (reset_i = '1') then  
                ipb_miso_o <= (ipb_ack => '0', ipb_err => '0', ipb_rdata => (others => '0'));
                state <= IDLE;  
                rd_en <= '0';    
                rd_reset <= '0';                
            else     
                case state is
                    when IDLE =>    
                        if (ipb_mosi_i.ipb_strobe = '1') then
                            case ipb_mosi_i.ipb_addr(1 downto 0) is
                                when "00" =>                                
                                    if (ipb_mosi_i.ipb_write = '1') then
                                        ipb_miso_o <= (ipb_ack => '1', ipb_err => '0', ipb_rdata => (others => '0'));
                                        rd_reset <= '1';
                                        state <= RST;
                                    else
                                        rd_en <= '1';
                                        state <= RSPD;
                                    end if;
                                when "01" => 
                                   ipb_miso_o <= (ipb_ack => '1', ipb_err => '0', ipb_rdata => x"000" & "000" & rd_data_count);
                                   state <= RST;
                                when "10" => 
                                   ipb_miso_o <= (ipb_ack => '1', ipb_err => '0', ipb_rdata => (0 => rd_full, others => '0'));
                                   state <= RST;
                                when "11" => 
                                   ipb_miso_o <= (ipb_ack => '1', ipb_err => '0', ipb_rdata => (0 => rd_empty, others => '0'));
                                   state <= RST;
                                when others => 
                                    ipb_miso_o <= (ipb_ack => '0', ipb_err => '0', ipb_rdata => (others => '0'));
                                    rd_en <= '0';  
                            end case;
                        end if;                      
                    when RSPD =>
                        rd_en <= '0';
                        if (ipb_mosi_i.ipb_strobe = '0') then
                            state <= IDLE;
                        elsif (rd_valid = '1') then
                            ipb_miso_o <= (ipb_ack => '1', ipb_err => '0', ipb_rdata => rd_data);
                            state <= RST;                            
                        elsif (rd_underflow = '1') then
                            ipb_miso_o <= (ipb_ack => '0', ipb_err => '1', ipb_rdata => (others => '0'));
                            state <= RST;
                        end if;
                    when RST =>
                        ipb_miso_o.ipb_ack <= '0';
                        ipb_miso_o.ipb_err <= '0';
                        rd_reset <= '0';
                        state <= IDLE;  
                    when others =>
                        ipb_miso_o <= (ipb_ack => '0', ipb_err => '0', ipb_rdata => (others => '0'));
                        state <= IDLE;    
                        rd_en <= '0';  
                        rd_reset <= '0'; 
                end case;
            end if;        
        end if;        
    end process;

end Behavioral;
