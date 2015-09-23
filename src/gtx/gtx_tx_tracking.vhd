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

    gtx_clk_i       : in std_logic;    
    reset_i         : in std_logic;
    
    req_en_o        : out std_logic;
    req_valid_i     : in std_logic;
    req_data_i      : in std_logic_vector(64 downto 0);
    
    tx_kchar_o      : out std_logic_vector(1 downto 0);
    tx_data_o       : out std_logic_vector(15 downto 0)
    
);
end gtx_tx_tracking;

architecture Behavioral of gtx_tx_tracking is    

    type state_t is (COMMA, HEADER, ADDR_0, ADDR_1, DATA_0, DATA_1);
    
    signal state        : state_t;
    
    signal req_header   : std_logic_vector(15 downto 0);
    signal req_data     : std_logic_vector(63 downto 0);

begin  

    --== Transitions between states ==--

    process(gtx_clk_i)
    begin
        if (rising_edge(gtx_clk_i)) then
            if (reset_i = '1') then
                state <= COMMA;
            else
                case state is
                    when COMMA => state <= HEADER;
                    when HEADER => state <= ADDR_0;
                    when ADDR_0 => state <= ADDR_1;
                    when ADDR_1 => state <= DATA_0;
                    when DATA_0 => state <= DATA_1;
                    when DATA_1 => state <= COMMA;
                    when others => state <= COMMA;
                end case;
            end if;
        end if;
    end process;

    --== Request new data ==--

    process(gtx_clk_i)
    begin
        if (rising_edge(gtx_clk_i)) then
            if (reset_i = '1') then
                req_en_o <= '0';
            else
                case state is         
                    when DATA_0 => req_en_o <= '1';
                    when others => req_en_o <= '0';
                end case;
            end if;
        end if;
    end process; 

    --== Handle new data ==--

    process(gtx_clk_i)
    begin
        if (rising_edge(gtx_clk_i)) then
            if (reset_i = '1') then
                req_header <= (others => '0');
                req_data <= (others => '0');
            else
                case state is         
                    when COMMA => 
                        if (req_valid_i = '1') then
                            req_header <= "100000000000000" & req_data_i(64);
                            req_data <= req_data_i(63 downto 0);
                        else
                            req_header <= (others => '0');
                            req_data <= (others => '0');
                        end if;
                    when others => null;
                end case;
            end if;
        end if;
    end process; 
        
    --== Send data ==--    
    
    process(gtx_clk_i)
    begin
        if (rising_edge(gtx_clk_i)) then
            if (reset_i = '1') then
                tx_kchar_o <= "00";
                tx_data_o <= x"0000";
            else
                case state is
                    when COMMA => 
                        tx_kchar_o <= "01";
                        tx_data_o <= x"00BC";
                    when HEADER => 
                        tx_kchar_o <= "00";
                        tx_data_o <= req_header;
                    when ADDR_0 => 
                        tx_kchar_o <= "00";
                        tx_data_o <= req_data(63 downto 48);
                    when ADDR_1 => 
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
                        tx_data_o <= x"0000";
                end case;
            end if;
        end if;
    end process;   
    
end Behavioral;
