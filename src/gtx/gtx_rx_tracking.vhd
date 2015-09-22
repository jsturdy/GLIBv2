----------------------------------------------------------------------------------
-- Company:        IIHE - ULB
-- Engineer:       Thomas Lenzi (thomas.lenzi@cern.ch)
-- 
-- Create Date:    08:37:33 07/07/2015 
-- Design Name:    GLIB v2
-- Module Name:    gtx_rx_tracking - Behavioral 
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

entity gtx_rx_tracking is
port(

    gtx_clk_i       : in std_logic;    
    reset_i         : in std_logic;
    
    req_en_o        : out std_logic;
    req_data_o      : out std_logic_vector(31 downto 0);
    req_error_o     : out std_logic;
    
    tk_en_o         : out std_logic;
    tk_data_o       : out std_logic_vector(15 downto 0);
    
    rx_kchar_i      : in std_logic_vector(1 downto 0);
    rx_data_i       : in std_logic_vector(15 downto 0)
    
);
end gtx_rx_tracking;

architecture Behavioral of gtx_rx_tracking is    

    type state_t is (COMMA, HEADER, TK_DATA, DATA_0, DATA_1);
    
    signal state        : state_t;
    
    signal tk_counter   : integer range 0 to 287;
    
    signal req_header   : std_logic_vector(15 downto 0);
    signal req_data     : std_logic_vector(31 downto 0);

begin  
    
    --== Transitions between states ==--

    process(gtx_clk_i)
    begin
        if (rising_edge(gtx_clk_i)) then
            if (reset_i = '1') then
                state <= COMMA;
                tk_counter <= 0;
            else
                case state is
                    when COMMA =>
                        if (rx_kchar_i = "01" and rx_data_i = x"00BC") then
                            state <= HEADER;
                        end if;
                    when HEADER => 
                        state <= TK_DATA;
                        tk_counter <= 0;
                    when TK_DATA =>
                        if (tk_counter = 287) then
                            state <= DATA_0;
                        else
                            tk_counter <= tk_counter + 1;
                        end if;
                    when DATA_0 => state <= DATA_1;
                    when DATA_1 => state <= COMMA;
                    when others => 
                        state <= COMMA;
                        tk_counter <= 0;
                end case;
            end if;
        end if;
    end process;
    
    --== Detect errors on the link ==--    
    
    process(gtx_clk_i)
    begin
        if (rising_edge(gtx_clk_i)) then
            if (reset_i = '1') then
                req_error_o <= '0';
            else
                case state is
                    when COMMA =>
                        if (rx_kchar_i = "01" and rx_data_i = x"00BC") then
                            req_error_o <= '0';
                        else
                            req_error_o <= '1';
                        end if;
                    when others => req_error_o <= '0';
                end case;
            end if;
        end if;
    end process;
    
    --== Receive data ==--
    
    process(gtx_clk_i)
    begin
        if (rising_edge(gtx_clk_i)) then
            if (reset_i = '1') then
                req_header <= (others => '0');
                req_data <= (others => '0');
            else
                case state is                    
                    when HEADER => req_header <= rx_data_i;
                    when DATA_0 => req_data(31 downto 16) <= rx_data_i;
                    when DATA_1 => req_data(15 downto 0) <= rx_data_i;
                    when others => null;
                end case;
            end if;
        end if;
    end process;   
    
    --== Forward valid data ==--    

    process(gtx_clk_i)
    begin
        if (rising_edge(gtx_clk_i)) then
            if (reset_i = '1') then
                req_en_o <= '0';
                req_data_o <= (others => '0');
            else
                case state is
                    when COMMA =>            
                        req_en_o <= req_header(15);
                        req_data_o <= req_data(31 downto 0);
                    when others => req_en_o <= '0';
                end case;                
            end if;
        end if;
    end process;
    
    --== Forward tracking data ==--
    
    process(gtx_clk_i)
    begin
        if (rising_edge(gtx_clk_i)) then
            if (reset_i = '1') then
                tk_en_o <= '0';
                tk_data_o <= (others => '0');
            else
                case state is                    
                    when TK_DATA =>
                        tk_en_o <= req_header(14);
                        tk_data_o <= rx_data_i;
                    when others => tk_en_o <= '0';
                end case;
            end if;
        end if;
    end process;   
    
end Behavioral;
