----------------------------------------------------------------------------------
-- Company:        IIHE - ULB
-- Engineer:       Thomas Lenzi (thomas.lenzi@cern.ch)
-- 
-- Create Date:    08:37:33 07/07/2015 
-- Design Name:    GLIB v2
-- Module Name:    link_rx_trigger - Behavioral 
-- Project Name:   GLIB v2
-- Target Devices: xc6vlx130t-1ff1156
-- Tool versions:  ISE  P.20131013
-- Description: 
--
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity link_rx_trigger is
port(

    gtx_clk_i       : in std_logic;    
    reset_i         : in std_logic;
    
    tr_error_o      : out std_logic;
    
    rx_kchar_i      : in std_logic_vector(1 downto 0);
    rx_data_i       : in std_logic_vector(15 downto 0);
    
    clusters_data_o : out std_logic_vector(55 downto 0);
    clusters_valid_o: out std_logic
    
);
end link_rx_trigger;

architecture Behavioral of link_rx_trigger is    

    type state_t is (COMMA, DATA_0, DATA_1, DATA_2);    
    
    signal state    : state_t;
    
    signal tr_error : std_logic;

begin  

    tr_error_o <= tr_error;
    
    --== STATE ==--

    process(gtx_clk_i)
    begin
        if (rising_edge(gtx_clk_i)) then
            if (reset_i = '1') then
                state <= COMMA;
            else
                case state is
                    when COMMA =>
                        if (rx_kchar_i = "01" and rx_data_i(7 downto 0) = x"BC") then
                            state <= DATA_0;
                        end if;
                    when DATA_0 => state <= DATA_1;
                    when DATA_1 => state <= DATA_2;
                    when DATA_2 => state <= COMMA;
                    when others => state <= COMMA;
                end case;
            end if;
        end if;
    end process;
    
    --== ERROR ==--

    process(gtx_clk_i)
    begin
        if (rising_edge(gtx_clk_i)) then
            if (reset_i = '1') then
                tr_error <= '0';
                clusters_valid_o <= '0';
                clusters_data_o <= (others => '0');
            else
                case state is
                    when COMMA =>
                        if (rx_kchar_i = "01" and rx_data_i(7 downto 0) = x"BC") then
                            tr_error <= '0';
                            clusters_data_o(55 downto 48) <= rx_data_i(15 downto 8);
                        else
                            tr_error <= '1';
                        end if;
                        clusters_valid_o <= '0';
                    when DATA_0 =>
                        clusters_data_o(47 downto 32) <= rx_data_i;
                        clusters_valid_o <= '0';
                    when DATA_1 =>
                        clusters_data_o(31 downto 16) <= rx_data_i;
                        clusters_valid_o <= '0';
                    when DATA_2 =>
                        clusters_data_o(15 downto 0) <= rx_data_i;
                        if (tr_error = '0') then
                            clusters_valid_o <= '1';
                        else
                            clusters_valid_o <= '0';
                        end if;
                    when others => tr_error <= '0';
                end case;
            end if;
        end if;
    end process;
    
end Behavioral;
