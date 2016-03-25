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
-- Description:    Wrapper for the TTC decoder module from BU, adds reset, LED output, and a few counters (orbit_id, bx_id, l1a_id).
--                 It also supports AMC13 and GEM TTC decoding standards (GEM decoding is the same as CSC, at least for now)
--
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

library work;
use work.ipbus.all;
use work.system_package.all;
use work.user_package.all;

entity ttc_wrapper is
port(

    reset_i         : in std_logic;
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
    oc0_o           : out std_logic; -- Orbit counter reset
    calpulse_o      : out std_logic; -- Calibration pulse
    start_o         : out std_logic; -- Start command
    stop_o          : out std_logic; -- Stop command
    resync_o        : out std_logic; -- Resync
    hard_reset_o    : out std_logic; -- Hard reset
    single_err_o    : out std_logic; -- Single bit error
    double_err_o    : out std_logic; -- Double bit error
    led_l1a_o       : out std_logic; -- LED output for L1A
    led_clk_bc0_o   : out std_logic; -- LED output for BC0 and clock: if BC0s are being received, it will be on three times longer than it will be off; if there are no BC0s, the on period will be equal to off period
    bx_id_o         : out std_logic_vector(11 downto 0); -- BX counter (reset with BC0)
    orbit_id_o      : out std_logic_vector(15 downto 0); -- Orbit counter (wraps around and is reset with EC0)
    l1a_id_o        : out std_logic_vector(23 downto 0);  -- L1A counter (reset with EC0)

    -- IPbus
    ipb_clk_i       : in std_logic;
	ipb_mosi_i      : in ipb_wbus;
	ipb_miso_o      : out ipb_rbus

);
end ttc_wrapper;

architecture Behavioral of ttc_wrapper is

    -- reset
    signal ttc_reset            : std_logic := '1';
    signal reset_ipb            : std_logic := '0';
    signal reset_pwrup          : std_logic := '1';
    signal pwrup_reset_cnt      : integer range 0 to 67_108_863 := 0;

    -- output of the TTC decoder
    signal ttc_clk              : std_logic := '0';
    signal ttc_l1a              : std_logic := '0';
    signal brcststr             : std_logic := '0';
    signal brcst                : std_logic_vector (7 downto 2) := (others => '0');

    -- TTC commands decoded in AMC13 format
    signal amc13_bc0            : std_logic := '0';
    signal amc13_ec0            : std_logic := '0';

    -- TTC commands decoded in CSC format
    signal csc_bc0              : std_logic := '0';
    signal csc_ec0              : std_logic := '0';
    
    -- TTC command output after choosing the decoding (AMC13 or GEM) and all the control logic
    signal l1a                  : std_logic := '0';
    signal bc0                  : std_logic := '0';
    signal ec0                  : std_logic := '0';
    signal oc0                  : std_logic := '0';
    signal calpulse             : std_logic := '0';
    signal start                : std_logic := '0';
    signal stop                 : std_logic := '0';
    signal resync               : std_logic := '0';
    signal hard_reset           : std_logic := '0';
    
    -- control flags
    signal use_csc_format       : std_logic := '0';
    signal block_l1as           : std_logic := '0';
    
    -- counters
    signal bx_id                : unsigned(11 downto 0) := (others => '0');
    signal orbit_id             : unsigned(15 downto 0) := (others => '0');
    signal l1a_id               : unsigned(23 downto 0) := (others => '0');

    -- TTC Spy
    constant ttc_spy_ipb_addr   : integer := 7;
    signal ttc_spy_buffer       : std_logic_vector(31 downto 0) := (others => '1');
    signal ttc_spy_pointer      : integer range 0 to 31 := 0;
    signal ttc_spy_reset        : std_logic := '0';
    signal ttc_spy_reset_ack    : std_logic := '0';
    
    -- IPbus registers
    type ipb_state_t is (IDLE, RSPD, RST);
    signal ipb_state            : ipb_state_t := IDLE;    
    signal ipb_reg_sel          : integer range 0 to 7 := 0;
    signal ipb_read_reg_data    : std32_array_t(0 to 7) := (others => (others => '0'));
    signal ipb_write_reg_data   : std32_array_t(0 to 7) := (others => (others => '0'));

begin
     
    --== Reset ==--    
    
    ttc_reset <= reset_pwrup or reset_ipb or reset_i;

    --== TTC clock and command output ==--    
    
    ttc_clk_o    <= ttc_clk;
    l1a_o        <= '0' when ttc_reset = '1' else l1a;
    bc0_o        <= '0' when ttc_reset = '1' else bc0;
    ec0_o        <= '0' when ttc_reset = '1' else ec0;
    oc0_o        <= '0' when ttc_reset = '1' else oc0;
    calpulse_o   <= '0' when ttc_reset = '1' else calpulse;
    start_o      <= '0' when ttc_reset = '1' else start;
    stop_o       <= '0' when ttc_reset = '1' else stop;
    resync_o     <= '0' when ttc_reset = '1' else resync;
    hard_reset_o <= '0' when ttc_reset = '1' else hard_reset;
        
    -- Choose between CSC and AMC13 BC0 and EC0 decoding
    bc0         <= csc_bc0 when use_csc_format = '1' else amc13_bc0;
    ec0         <= csc_ec0 when use_csc_format = '1' else amc13_ec0;
    
    -- L1A logic (currently only block or not block)
    l1a <= ttc_l1a and (not block_l1as);

    --== Counter output ==--    
    
    bx_id_o <= std_logic_vector(bx_id);
    orbit_id_o <= std_logic_vector(orbit_id);
    l1a_id_o <= std_logic_vector(l1a_id);
    
    --== Instanciate the TTC decoder ==--    

    ttc_decoder_i : entity work.TTC_decoder
    port map(
        TTC_CLK_p   => ttc_clk_p_i,
        TTC_CLK_n   => ttc_clk_n_i,
        TTC_rst     => ttc_reset,
        TTC_data_p  => ttc_data_p_i,
        TTC_data_n  => ttc_data_n_i,
        TTC_CLK_out => ttc_clk,
        TTCready    => ttc_ready_o,
        L1Accept    => ttc_l1a,
        BCntRes     => amc13_bc0,
        EvCntRes    => amc13_ec0,
        SinErrStr   => single_err_o,
        DbErrStr    => double_err_o,
        BrcstStr    => brcststr,
        Brcst       => brcst
    );

    --== Reset after powerup ==--    

    process(ref_clk_i)
    begin
        if (rising_edge(ref_clk_i)) then
            if (pwrup_reset_cnt = 60_000_000) then
              reset_pwrup <= '0';
              pwrup_reset_cnt <= 60_000_000;
            else
              reset_pwrup <= '1';
              pwrup_reset_cnt <= pwrup_reset_cnt + 1;
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
            
            -- L1A ID: reset on EC0, otherwise increment on L1A
            if (ec0 = '1') then
                l1a_id <= (others => '0');
            elsif (l1a = '1') then
                l1a_id <= l1a_id + 1;
            end if;
            
            -- Orbit ID: reset on OC0, otherwise increment on BC0
            if (oc0 = '1') then
                orbit_id <= (others => '0');
            elsif (bc0 = '1') then
                orbit_id <= orbit_id + 1;
            end if;
            
            -- BX ID: reset on BC0, otherwise increment with every clock
            if (bc0 = '1') then
                bx_id <= (others => '0');
            else
                bx_id <= bx_id + 1;
            end if;
            
        end if;
    end process;

    --== GEM command decoding ==--    -- NOTE: this decoding is adapted from CSC TTC encoding, see here for details: https://indico.cern.ch/event/505410/session/1/contribution/3/attachments/1238215/1819227/2016-03-02_EJ_BGo_commands.pdf
    
    process(ttc_clk)
    begin
        if (rising_edge(ttc_clk)) then
            
            csc_bc0     <= '0';
            csc_ec0     <= '0';
            oc0         <= '0';
            calpulse    <= '0';
            start       <= '0';
            stop        <= '0';
            resync      <= '0';
            hard_reset  <= '0';
            
            if (brcststr = '1') then
                -- NOTE: the lowest two bits are dropped by the decoder, so if you encode a command as 0xC, it will come out as 0x3!
                case brcst is
                    -- normally BC0 is encoded as 0x1 (in which case we should just use the bc0 output of the decoder), but CSC encodes it as 0x4 (so comes as 0x1 with two lower bits wiped away)
                    when "00" & x"0" =>
                        csc_ec0 <= '1';
                        oc0 <= '1'; -- for now just squish it together with EC0 since CSC doesn't have it defined..
                    when "00" & x"1" =>
                        csc_bc0 <= '1';
                    when "00" & x"3" =>
                        resync <= '1';
                    when "00" & x"4" =>
                        hard_reset <= '1';
                    when "00" & x"5" =>
                        calpulse <= '1';
                    when "00" & x"6" =>
                        start <= '1';
                    when "00" & x"7" =>
                        stop <= '1';
                    when others =>
                end case;
                
                -- fill the spy buffer if the pointer is not yet at the last word
                if (ttc_spy_pointer <= 28) then
                    ttc_spy_buffer(ttc_spy_pointer + 3 downto ttc_spy_pointer) <= brcst(5 downto 2);
                    ttc_spy_pointer <= ttc_spy_pointer + 4;
                end if;
                
                -- reset the spy buffer (called when the buffer is read through IPBus)
                if (ttc_spy_reset = '1') then
                    ttc_spy_buffer <= (others => '1');
                    ttc_spy_pointer <= 0;
                    ttc_spy_reset_ack <= '1';
                else
                    ttc_spy_reset_ack <= '0';
                end if;
                
            end if;
        
        end if;
    end process;

    --================================--
    -- IPbus register assignments
    --================================--

    ipb_read_reg_data(0)(0)  <= use_csc_format;
    ipb_read_reg_data(0)(1)  <= block_l1as;
    ipb_read_reg_data(0)(31) <= reset_ipb;

    use_csc_format <= ipb_write_reg_data(0)(0);
    block_l1as     <= ipb_write_reg_data(0)(1);
    reset_ipb      <= ipb_write_reg_data(0)(31);

    ipb_read_reg_data(ttc_spy_ipb_addr) <= ttc_spy_buffer;

    --================================--
    -- IPbus
    --================================--

    process(ipb_clk_i)       
    begin    
        if (rising_edge(ipb_clk_i)) then      
            if (reset_i = '1') then    
                ipb_miso_o <= (ipb_ack => '0', ipb_err => '0', ipb_rdata => (others => '0'));    
                ipb_state <= IDLE;
                ipb_reg_sel <= 0;
                ttc_spy_reset <= '0';
                
                ipb_write_reg_data <= (others => (others => '0'));
                
            else
                if ((ttc_spy_reset = '1') and (ttc_spy_reset_ack = '1')) then
                    ttc_spy_reset <= '0';
                end if;
                
                case ipb_state is
                    when IDLE =>                    
                        ipb_reg_sel <= to_integer(unsigned(ipb_mosi_i.ipb_addr(8 downto 0)));
                        if (ipb_mosi_i.ipb_strobe = '1') then
                            ipb_state <= RSPD;
                        end if;
                    when RSPD =>
                        -- handle TTC spy buffer reset
                        if (ipb_reg_sel = ttc_spy_ipb_addr) then
                            ttc_spy_reset <= '1';
                        end if;
                        
                        ipb_miso_o <= (ipb_ack => '1', ipb_err => '0', ipb_rdata => ipb_read_reg_data(ipb_reg_sel));
                        if (ipb_mosi_i.ipb_write = '1') then
                            ipb_write_reg_data(ipb_reg_sel) <= ipb_mosi_i.ipb_wdata;
                        end if;
                        ipb_state <= RST;
                    when RST =>
                        ipb_miso_o.ipb_ack <= '0';
                        ipb_state <= IDLE;
                    when others => 
                        ipb_miso_o <= (ipb_ack => '0', ipb_err => '0', ipb_rdata => (others => '0'));    
                        ipb_state <= IDLE;
                        ipb_reg_sel <= 0;
                    end case;
            end if;        
        end if;        
    end process;

end Behavioral;

