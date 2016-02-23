----------------------------------------------------------------------------------
-- Company: FNAL
-- Engineer: Evaldas Juska (evaldas.juska@cern.ch)
-- 
-- Create Date:    23:45:21 10/19/2015 
-- Design Name:    GLIB v2
-- Module Name:    ttc_wrapper - Behavioral 
-- Project Name:   GLIB v2
-- Target Devices: xc6vlx130t-1ff1156
-- Tool versions:  ISE  P.20131013
-- Description:    Wrapper for the TTC decoder module from BU, adds reset, LED output, and a few counters (orbit_id, bx_id, l1a_id)
--
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

library work;
use work.user_package.all;

entity ttc_wrapper is
port(

    ref_clk_i       : in std_logic;
    ttc_clk_p_i     : in std_logic;
    ttc_clk_n_i     : in std_logic;
    ttc_data_p_i    : in std_logic;
    ttc_data_n_i    : in std_logic;
    ttc_clk_o       : out std_logic; -- TTC clock
    ttc_ready_o     : out std_logic;
    l1a_o           : out std_logic; -- Level 1 Accept
    bc0_o           : out std_logic; -- Bunch counter reset
    ec0_o           : out std_logic; -- Event counter reset
    resync_o        : out std_logic; -- Resync
    hard_reset_o    : out std_logic; -- Hard reset
    single_err_o    : out std_logic; -- Single bit error
    double_err_o    : out std_logic; -- Double bit error
    led_l1a_o       : out std_logic; -- LED output for L1A
    led_clk_bc0_o   : out std_logic; -- LED output for BC0 and clock: if BC0s are being received, it will be on three times longer than it will be off; if there are no BC0s, the on period will be equal to off period
    bx_id_o         : out std_logic_vector(11 downto 0); -- BX counter (reset with BC0)
    orbit_id_o      : out std_logic_vector(15 downto 0); -- Orbit counter (wraps around and is reset with EC0)
    l1a_id_o        : out std_logic_vector(23 downto 0)  -- L1A counter (reset with EC0)

);
end ttc_wrapper;

architecture Behavioral of ttc_wrapper is

    signal ttc_rst      : std_logic := '1';
    signal ttc_rst_cnt  : integer range 0 to 67_108_863 := 0;

    signal ttc_clk      : std_logic := '0';
    signal l1a          : std_logic := '0';
    signal bc0          : std_logic := '0';
    signal ec0          : std_logic := '0';
    signal brcststr     : std_logic := '0';
    signal brcst        : std_logic_vector (7 downto 2) := (others => '0');
    
    signal bx_id        : unsigned(11 downto 0) := (others => '0');
    signal orbit_id     : unsigned(15 downto 0) := (others => '0');
    signal l1a_id       : unsigned(23 downto 0) := (others => '0');
    
begin
    
    ttc_clk_o <= ttc_clk;
    l1a_o <= l1a;
    bc0_o <= bc0;
    ec0_o <= ec0;
    
    bx_id_o <= std_logic_vector(bx_id);
    orbit_id_o <= std_logic_vector(orbit_id);
    l1a_id_o <= std_logic_vector(l1a_id);
    
    --== Instanciate the TTC decoder ==--    

    ttc_decoder_i : entity work.TTC_decoder
    port map(
        TTC_CLK_p   => ttc_clk_p_i,
        TTC_CLK_n   => ttc_clk_n_i,
        TTC_rst     => ttc_rst,
        TTC_data_p  => ttc_data_p_i,
        TTC_data_n  => ttc_data_n_i,
        TTC_CLK_out => ttc_clk,
        TTCready    => ttc_ready_o,
        L1Accept    => l1a,
        BCntRes     => bc0, -- CSC encodes BC0 as 0x4 instead of the usual 0x1
        EvCntRes    => ec0,
        SinErrStr   => single_err_o,
        DbErrStr    => double_err_o,
        BrcstStr    => brcststr,
        Brcst       => brcst
    );

    --== Reset after powerup ==--    

    process(ref_clk_i)
    begin
        if (rising_edge(ref_clk_i)) then
            if (ttc_rst_cnt = 60_000_000) then
              ttc_rst <= '0';
              ttc_rst_cnt <= 60_000_000;
            else
              ttc_rst <= '1';
              ttc_rst_cnt <= ttc_rst_cnt + 1;
            end if;
        end if;
    end process;

    --== LEDs ==--    
    
    process(ttc_clk)
        variable clk_led_countdown : integer := 0;
        variable l1a_led_countdown : integer := 0;
        variable bc0_received      : std_logic := '0';
    begin
        if (rising_edge(ttc_clk)) then
        
            -- control the bc0/clk LED
            if (clk_led_countdown < 2_500_000) then
                led_clk_bc0_o <= '0';
            else
                led_clk_bc0_o <= '1';
            end if;
            
            -- control the L1A LED
            if (l1a_led_countdown > 0) then
                led_l1a_o <= '1';
            else
                led_l1a_o <= '0';
            end if;            
                       
            -- manage the bc0/clk countdown
            -- if bc0 was received during the countdown the led will be on three times longer than off (countdown = 10_000_000), otherwise it will be the same as off period (countdown = 5_000_000)
            if ((clk_led_countdown <= 0) and (bc0_received = '0')) then
                clk_led_countdown := 5_000_000;
            elsif ((clk_led_countdown <= 0) and (bc0_received = '1')) then
                clk_led_countdown := 10_000_000;
                bc0_received := '0';
            else
                clk_led_countdown := clk_led_countdown - 1;
                bc0_received := bc0_received or bc0;
            end if;
 
            -- manage the L1A countdown
            if (l1a = '1') then
                l1a_led_countdown := 400_000;
            elsif (l1a_led_countdown > 0) then
                l1a_led_countdown := l1a_led_countdown - 1;
            else
                l1a_led_countdown := 0;
            end if;
            
        end if;
    end process;   

    --== Counters ==--    
    
    process(ttc_clk)
    begin
        if (rising_edge(ttc_clk)) then
            
            -- if EC0 then reset the counters, otherwise increment when needed
            if (ec0 = '1') then
                l1a_id <= (others => '0');
                orbit_id <= (others => '0');
            else
                -- L1A ID
                if (l1a = '1') then
                    l1a_id <= l1a_id + 1;
                end if;
                
                -- Orbit ID
                if (bc0 = '1') then
                    orbit_id <= orbit_id + 1;
                end if;
            end if;
            
            -- BX ID
            if (bc0 = '1') then
                bx_id <= (others => '0');
            else
                bx_id <= bx_id + 1;
            end if;
            
        end if;
    end process;

    --== Command decoding ==--    
    -- NOTE: this decoding is adapted to CSC TTC encoding and may not necessarily be the same for another TTC/TCDS partition
    
--    process(ttc_clk)
--    begin
--        if (rising_edge(ttc_clk)) then
--        
--            if (brcststr = '1') then
--                -- the lowest two bits are dropped by the decoder, so if you encode a command as 0xC, it will come out as 0x3!
--                case brcst is
--                    -- normally BC0 is encoded as 0x1 (in which case we should just use the bc0 output of the decoder), but CSC encodes it as 0x4 (so comes as 0x1 with two lower bits wiped away)
--                    when "00" & x"1" =>
--                        bc0 <= '1';
--                    when "00" & x"3" =>
--                        resync_o <= '1';
--                    when "00" & x"4" =>
--                        hard_reset_o <= '1';
--                    when others =>
--                        resync_o <= '0';
--                        hard_reset_o <= '0';
--                        bc0 <= '0';
--                end case;
--            else
--                resync_o <= '0';
--                hard_reset_o <= '0';
--                bc0 <= '0';
--            end if;
--        
--        end if;
--    end process;

end Behavioral;

