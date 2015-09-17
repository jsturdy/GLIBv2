----------------------------------------------------------------------------------
-- Company:        IIHE - ULB
-- Engineer:       Thomas Lenzi (thomas.lenzi@cern.ch)
-- 
-- Create Date:    08:37:33 07/07/2015 
-- Design Name:    GLIB v2
-- Module Name:    gtx_tx_tracking - Behavioral 
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

entity gtx_tx_tracking is
port(

    ref_clk_i   : in std_logic;    
    reset_i     : in std_logic;
    
    req_en_i    : in std_logic;
    req_ack_o   : out std_logic;
    req_data_i  : in std_logic_vector(64 downto 0);
    
    tx_kchar_o  : out std_logic_vector(1 downto 0);
    tx_data_o   : out std_logic_vector(15 downto 0)
    
);
end gtx_tx_tracking;

architecture Behavioral of gtx_tx_tracking is    

    type state_t is (COMMA, HEADER, ADDRESS_0, ADDRESS_1, DATA_0, DATA_1);
    
    signal state    : state_t;
    
    signal req_ack  : std_logic;
    signal req_data : std_logic_vector(79 downto 0);

begin  

    req_ack_o <= req_ack;

    -- Cycle between states

    process(ref_clk_i)
    begin
        if (rising_edge(ref_clk_i)) then
            if (reset_i = '1') then
                state <= COMMA;
            else
                case state is
                    when COMMA => state <= HEADER;
                    when HEADER => state <= ADDRESS_0;
                    when ADDRESS_0 => state <= ADDRESS_1;
                    when ADDRESS_1 => state <= DATA_0;
                    when DATA_0 => state <= DATA_1;
                    when DATA_1 => state <= COMMA;
                    when others => state <= HEADER;
                end case;
            end if;
        end if;
    end process;
    
    -- Forward data
    
    process(ref_clk_i)
    begin
        if (rising_edge(ref_clk_i)) then
            if (reset_i = '1') then
                tx_kchar_o <= "00";
                tx_data_o <= (others => '0');
                req_ack <= '0';
                req_data <= (others => '0');
            else
                -- Reset the acknowledgment whenever it has been seen
                if (req_en_i = '0' and req_ack = '1') then
                    req_ack <= '0';
                end if;
                -- Handle the data
                case state is
                    -- Send a comma and look for valid data to send
                    when COMMA => 
                        -- Request data
                        if (req_en_i = '1' and req_ack = '0') then
                            req_ack <= '1';
                            req_data <= "100000000000000" & req_data_i;
                        else
                            req_data <= (others => '0');
                        end if;
                        -- Data on the link
                        tx_kchar_o <= "01";
                        tx_data_o <= x"00BC";
                    -- Header data
                    when HEADER => 
                        tx_kchar_o <= "00";
                        tx_data_o <= req_data(79 downto 64);
                    when ADDRESS_0 => 
                        tx_kchar_o <= "00";
                        tx_data_o <= req_data(63 downto 48);
                    when ADDRESS_1 =>
                        tx_kchar_o <= "00";
                        tx_data_o <= req_data(47 downto 32);
                    when DATA_0 =>
                        tx_kchar_o <= "00";
                        tx_data_o <= req_data(31 downto 16);
                    when DATA_1 =>
                        tx_kchar_o <= "00";
                        tx_data_o <= req_data(15 downto 0);
                    when others =>
                        tx_kchar_o <= "00";
                        tx_data_o <= (others => '0');
                        req_ack <= '0';
                        req_data <= (others => '0');
                end case;
            end if;
        end if;
    end process;
    
end Behavioral;
