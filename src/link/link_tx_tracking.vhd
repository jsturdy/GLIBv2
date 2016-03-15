----------------------------------------------------------------------------------
-- Company:        IIHE - ULB
-- Engineer:       Thomas Lenzi (thomas.lenzi@cern.ch)
-- 
-- Create Date:    08:37:33 07/07/2015 
-- Design Name:    GLIB v2
-- Module Name:    link_tx_tracking - Behavioral 
-- Project Name:   GLIB v2
-- Target Devices: xc6vlx130t-1ff1156
-- Tool versions:  ISE  P.20131013
-- Description: 
--
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

library work;
use work.user_package.all;

entity link_tx_tracking is
port(

    gtx_clk_i       : in std_logic;    
    reset_i         : in std_logic;    
    
    vfat2_t1_i      : in t1_t;
    
    req_en_o        : out std_logic;
    req_valid_i     : in std_logic;
    req_data_i      : in std_logic_vector(64 downto 0);
    
    tx_kchar_o      : out std_logic_vector(1 downto 0);
    tx_data_o       : out std_logic_vector(15 downto 0)
    
);
end link_tx_tracking;

architecture Behavioral of link_tx_tracking is    

    type state_t is (FRAME_BEGIN, ADDR_0, ADDR_1, DATA_0, FRAME_MIDDLE, DATA_1, CRC, FRAME_END);
    
    signal state        : state_t;
    
    signal req_valid    : std_logic;
    signal req_data     : std_logic_vector(64 downto 0);
    signal req_crc      : std_logic_vector(15 downto 0);

begin  

    --== STATE ==--

    process(gtx_clk_i)
    begin
        if (rising_edge(gtx_clk_i)) then
            if (reset_i = '1') then
                state <= FRAME_BEGIN;
            else
                case state is
                    when FRAME_BEGIN => state <= ADDR_0;
                    when ADDR_0 => state <= ADDR_1;
                    when ADDR_1 => state <= DATA_0;
                    when DATA_0 => state <= FRAME_MIDDLE;
                    when FRAME_MIDDLE => state <= DATA_1;
                    when DATA_1 => state <= CRC;
                    when CRC => state <= FRAME_END;
                    when FRAME_END => state <= FRAME_BEGIN;
                    when others => state <= FRAME_BEGIN;
                end case;
            end if;
        end if;
    end process;

    --== REQUEST ==--

    process(gtx_clk_i)
    begin
        if (rising_edge(gtx_clk_i)) then
            if (reset_i = '1') then
                req_en_o <= '0';
                req_valid <= '0';
                req_data <= (others => '0');
                req_crc <= (others => '0');
            else
                case state is   
                    when FRAME_END => 
                        req_en_o <= '0';
                        req_valid <= req_valid_i;
                        req_data <= req_data_i;
                        req_crc <= req_data_i(63 downto 48) xor req_data_i(47 downto 32) xor req_data_i(31 downto 16) xor req_data_i(15 downto 0);
                    when DATA_1 => req_en_o <= '1';
                    when others => req_en_o <= '0';
                end case;
            end if;
        end if;
    end process; 
        
    --== SEND ==--    
    
    process(gtx_clk_i)
    begin
        if (rising_edge(gtx_clk_i)) then
            if (reset_i = '1') then
                tx_kchar_o <= "00";
                tx_data_o <= x"0000";
            else
                case state is
                    when FRAME_BEGIN => 
                        tx_kchar_o <= "01";
                        tx_data_o <= vfat2_t1_i.lv1a & vfat2_t1_i.calpulse & vfat2_t1_i.resync & vfat2_t1_i.bc0 & req_valid & req_data(64) & "11" & x"BC";
                    when ADDR_0 =>  
                        tx_kchar_o <= "00";
                        tx_data_o <= req_data(63 downto 48);
                    when ADDR_1 => 
                        tx_kchar_o <= "00";
                        tx_data_o <= req_data(47 downto 32);
                    when DATA_0 => 
                        tx_kchar_o <= "00";
                        tx_data_o <= req_data(31 downto 16);
                    when FRAME_MIDDLE => 
                        tx_kchar_o <= "01";
                        tx_data_o <= vfat2_t1_i.lv1a & vfat2_t1_i.calpulse & vfat2_t1_i.resync & vfat2_t1_i.bc0 & x"0BC";                        
                    when DATA_1 => 
                        tx_kchar_o <= "00";
                        tx_data_o <= req_data(15 downto 0);
                    when CRC =>
                        tx_kchar_o <= "00";
                        tx_data_o <= req_crc;
                    when FRAME_END =>
                        tx_kchar_o <= "00";
                        tx_data_o <= x"0000";                    
                    when others => 
                        tx_kchar_o <= "00";
                        tx_data_o <= x"0000";
                end case;
            end if;
        end if;
    end process;   
    
end Behavioral;
