----------------------------------------------------------------------------------
-- Company: 
-- Engineer: Evaldas Juska (Evaldas.Juska@cern.ch)
-- 
-- Create Date:    20:18:40 09/17/2015 
-- Design Name:    GLIB v2
-- Module Name:    DAQ
-- Project Name:   GLIB v2
-- Target Devices: xc6vlx130t-1ff1156
-- Tool versions:  ISE  P.20131013
-- Description:    This module buffers track data, builds events, analyses the data for consistency and ships off the events with all the needed headers and trailers to AMC13 over DAQLink
--
----------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

library work;
use work.ipbus.all;
use work.system_package.all;
use work.user_package.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity daq is
port(

    -- Reset
    reset_i                     : in std_logic;
    resync_i                    : in std_logic;

    -- Clocks
    mgt_ref_clk125_i            : in std_logic;
    clk125_i                    : in std_logic;
    ipb_clk_i                   : in std_logic;

    -- Pins
    daq_gtx_tx_pin_p            : out std_logic; 
    daq_gtx_tx_pin_n            : out std_logic; 
    daq_gtx_rx_pin_p            : in std_logic; 
    daq_gtx_rx_pin_n            : in std_logic; 

    -- TTC
    ttc_ready_i                 : in std_logic;
    ttc_clk_i                   : in std_logic;
    ttc_l1a_i                   : in std_logic;
    ttc_bc0_i                   : in std_logic;
    ttc_ec0_i                   : in std_logic;
    ttc_bx_id_i                 : in std_logic_vector(11 downto 0);
    ttc_orbit_id_i              : in std_logic_vector(15 downto 0);
    ttc_l1a_id_i                : in std_logic_vector(23 downto 0);

    -- Track data
    track_rx_clk_i              : in std_logic;
    track_rx_en_i               : in std_logic;
    track_rx_data_i             : in std_logic_vector(15 downto 0);
    
    -- IPbus
	ipb_mosi_i                  : in ipb_wbus;
	ipb_miso_o                  : out ipb_rbus;
    
    -- Other
    board_sn_i                  : in std_logic_vector(7 downto 0) -- board serial ID, needed for the header to AMC13
    
);
end daq;

architecture Behavioral of daq is

    -- Reset
    signal reset_daq            : std_logic := '1';
    signal reset_daqlink        : std_logic := '1'; -- should only be done once at powerup
    signal reset_pwrup          : std_logic := '1';
    signal reset_ipb            : std_logic := '1';

    -- Clocks
    signal daq_clk_bufg         : std_logic;

    -- DAQlink
    signal daq_event_data       : std_logic_vector(63 downto 0) := (others => '0');
    signal daq_event_write_en   : std_logic := '0';
    signal daq_event_header     : std_logic := '0';
    signal daq_event_trailer    : std_logic := '0';
    signal daq_ready            : std_logic := '0';
    signal daq_almost_full      : std_logic := '0';
    signal daq_gtx_clk          : std_logic;    
    signal daq_clock_locked     : std_logic := '0';
  
    signal daq_disper_err_cnt   : std_logic_vector(15 downto 0) := (others => '0');
    signal daq_notintable_err_cnt: std_logic_vector(15 downto 0) := (others => '0');

    -- TTS
    signal tts_state            : std_logic_vector(3 downto 0) := "1000";
    signal tts_critical_error   : std_logic := '0'; -- critical error detected - RESYNC/RESET NEEDED
    signal tts_warning          : std_logic := '0'; -- overflow warning - STOP TRIGGERS
    signal tts_out_of_sync      : std_logic := '0'; -- out-of-sync - RESYNC NEEDED
    signal tts_busy             : std_logic := '0'; -- I'm busy - NO TRIGGERS FOR NOW, PLEASE
    signal tts_override         : std_logic_vector(3 downto 0) := x"0"; -- this can be set via IPbus and will override the TTS state if it's not x"0" (regardless of reset_daq and daq_enable)
    
    -- DAQ conf
    signal daq_enable           : std_logic := '1'; -- enable sending data to DAQLink
    signal run_type             : std_logic_vector(3 downto 0) := x"0"; -- run type (set by software and included in the AMC header)
    signal run_params           : std_logic_vector(23 downto 0) := x"000000"; -- optional run parameters (set by software and included in the AMC header)
    
    -- DAQ counters
    signal cnt_sent_event       : unsigned(31 downto 0) := (others => '0');
    signal cnt_corrupted_vfat   : unsigned(31 downto 0) := (others => '0');

    -- DAQ event sending state machine
    signal daq_state            : unsigned(3 downto 0) := (others => '0');
    signal daq_curr_vfat_block  : unsigned(11 downto 0) := (others => '0');
    signal daq_curr_block_word  : integer range 0 to 2 := 0;
        
    -- IPbus registers
    type ipb_state_t is (IDLE, RSPD, RST);
    signal ipb_state                : ipb_state_t := IDLE;    
    signal ipb_reg_sel              : integer range 0 to 31;    
    signal ipb_read_reg_data        : std32_array_t(31 downto 0);
    signal ipb_write_reg_data       : std32_array_t(31 downto 0);
    
    ---=== Chamber Event Builder signals ===---
    
    signal infifo_dout          : std_logic_vector(191 downto 0);
    signal infifo_rd_en         : std_logic;
    signal infifo_empty         : std_logic;
    signal infifo_valid         : std_logic;
    signal infifo_underflow     : std_logic;
    signal evtfifo_dout         : std_logic_vector(59 downto 0);
    signal evtfifo_rd_en        : std_logic;
    signal evtfifo_empty        : std_logic;
    signal evtfifo_valid        : std_logic;
    signal evtfifo_underflow    : std_logic;
    
    signal err_event_too_big    : std_logic;
    signal err_evtfifo_underflow: std_logic;
    
    -- Debug flags for ChipScope
--    attribute MARK_DEBUG : string;
--    attribute MARK_DEBUG of reset_daq : signal is "TRUE";
--    attribute MARK_DEBUG of daq_gtx_clk : signal is "TRUE";
--    attribute MARK_DEBUG of daq_clk_bufg : signal is "TRUE";
--
--    attribute MARK_DEBUG of track_rx_clk_i : signal is "TRUE";
--    attribute MARK_DEBUG of track_rx_en_i : signal is "TRUE";
--    attribute MARK_DEBUG of track_rx_data_i : signal is "TRUE";
--    attribute MARK_DEBUG of ep_vfat_block_data : signal is "TRUE";
--    attribute MARK_DEBUG of ep_vfat_block_en : signal is "TRUE";
--
--    attribute MARK_DEBUG of infifo_din : signal is "TRUE";
--    attribute MARK_DEBUG of infifo_dout : signal is "TRUE";
--    attribute MARK_DEBUG of infifo_rd_en : signal is "TRUE";
--    attribute MARK_DEBUG of infifo_wr_en : signal is "TRUE";
--    attribute MARK_DEBUG of infifo_full : signal is "TRUE";
--    attribute MARK_DEBUG of infifo_empty : signal is "TRUE";
--    attribute MARK_DEBUG of infifo_valid : signal is "TRUE";
--    attribute MARK_DEBUG of infifo_underflow : signal is "TRUE";
--    
--    attribute MARK_DEBUG of evtfifo_din : signal is "TRUE";
--    attribute MARK_DEBUG of evtfifo_dout : signal is "TRUE";
--    attribute MARK_DEBUG of evtfifo_rd_en : signal is "TRUE";
--    attribute MARK_DEBUG of evtfifo_wr_en : signal is "TRUE";
--    attribute MARK_DEBUG of evtfifo_full : signal is "TRUE";
--    attribute MARK_DEBUG of evtfifo_empty : signal is "TRUE";
--    attribute MARK_DEBUG of evtfifo_valid : signal is "TRUE";
--    attribute MARK_DEBUG of evtfifo_underflow : signal is "TRUE";
--    
--    attribute MARK_DEBUG of ep_last_ec : signal is "TRUE";
--    attribute MARK_DEBUG of ep_last_bc : signal is "TRUE";
--    attribute MARK_DEBUG of ep_first_ever_block : signal is "TRUE";
--    attribute MARK_DEBUG of ep_end_of_event : signal is "TRUE";
--    attribute MARK_DEBUG of ep_invalid_vfat_block : signal is "TRUE";
--    
--    attribute MARK_DEBUG of eb_vfat_ec : signal is "TRUE";
--    attribute MARK_DEBUG of eb_bc : signal is "TRUE";
--    attribute MARK_DEBUG of eb_oh_bc : signal is "TRUE";
--    attribute MARK_DEBUG of eb_event_num_short : signal is "TRUE";
--    attribute MARK_DEBUG of eb_vfat_words_64 : signal is "TRUE";
--    attribute MARK_DEBUG of eb_counters_valid : signal is "TRUE";
--    
--    attribute MARK_DEBUG of eb_invalid_vfat_block : signal is "TRUE";
--    attribute MARK_DEBUG of eb_event_too_big : signal is "TRUE";
--    attribute MARK_DEBUG of eb_event_bigger_than_24 : signal is "TRUE";
--    attribute MARK_DEBUG of eb_vfat_bx_mismatch : signal is "TRUE";
--    attribute MARK_DEBUG of eb_oos_oh : signal is "TRUE";
--    attribute MARK_DEBUG of eb_vfat_oh_bx_mismatch : signal is "TRUE";
--    attribute MARK_DEBUG of eb_oos_glib_vfat : signal is "TRUE";
--    
--    attribute MARK_DEBUG of gs_corrupted_vfat_data : signal is "TRUE";
--    attribute MARK_DEBUG of daq_state : signal is "TRUE";
--    attribute MARK_DEBUG of daq_curr_vfat_block : signal is "TRUE";
--    attribute MARK_DEBUG of daq_curr_block_word : signal is "TRUE";
--
--    attribute MARK_DEBUG of daq_event_data : signal is "TRUE";
--    attribute MARK_DEBUG of daq_event_write_en : signal is "TRUE";
--    attribute MARK_DEBUG of daq_event_header : signal is "TRUE";
--    attribute MARK_DEBUG of daq_event_trailer : signal is "TRUE";
--    attribute MARK_DEBUG of daq_ready : signal is "TRUE";
--    attribute MARK_DEBUG of daq_almost_full : signal is "TRUE";

begin

    -- TODO main tasks:
    --   * Support multiple OHs
    --   * Timeouts
    --   * L1A FIFO
    --   * Tag bx and orbit based on L1A
    --   * Check for VFAT and OH BX vs L1A bx mismatches
    --   * Resync handling
    --   * Stop building events if input fifo is full -- let it drain to some level and only then restart building (otherwise you're pointing to inexisting data). I guess it's better to loose some data than to have something that doesn't make any sense..

    --================================--
    -- Resets
    --================================--
    
    reset_daq <= reset_pwrup or reset_i or reset_ipb;
    reset_daqlink <= reset_pwrup or reset_i;
    
    -- Reset after powerup
    
    process(ttc_clk_i)
        variable countdown : integer := 40_000_000; -- probably way too long, but ok for now (this is only used after powerup)
    begin
        if (rising_edge(ttc_clk_i)) then
            if (countdown > 0) then
              reset_pwrup <= '1';
              countdown := countdown - 1;
            else
              reset_pwrup <= '0';
            end if;
        end if;
    end process;

    --================================--
    -- DAQ clocks
    --================================--
    
    daq_clocks : entity work.daq_clocks
    port map
    (
        CLK_IN1            => clk125_i,
        CLK_OUT1           => daq_clk_bufg, -- 25MHz
        CLK_OUT2           => open, -- 250MHz, not used
        RESET              => reset_i,
        LOCKED             => daq_clock_locked
    );    

    --================================--
    -- Chamber Event Builders
    --================================--

    chamber_evt_builder : entity work.chamber_event_builder
    port map
    (
        -- Reset
        reset_i                     => reset_daq,

        -- Config
        input_enable_i              => '1',

        -- FIFOs
        fifo_rd_clk_i               => daq_clk_bufg,
        infifo_dout_o               => infifo_dout,
        infifo_rd_en_i              => infifo_rd_en,
        infifo_empty_o              => infifo_empty,
        infifo_valid_o              => infifo_valid,
        infifo_underflow_o          => infifo_underflow,
        evtfifo_dout_o              => evtfifo_dout,
        evtfifo_rd_en_i             => evtfifo_rd_en,
        evtfifo_empty_o             => evtfifo_empty,
        evtfifo_valid_o             => evtfifo_valid,
        evtfifo_underflow_o         => evtfifo_underflow,

        -- Track data
        track_rx_clk_i              => track_rx_clk_i,
        track_rx_en_i               => track_rx_en_i,
        track_rx_data_i             => track_rx_data_i,
        
        -- TTS
        tts_state_o                 => tts_state,

        -- Critical error flags
        err_infifo_full_o           => open,
        err_infifo_underflow_o      => open, -- Tried to read too many blocks from the input fifo when sending events to the DAQlink (indicates a problem in the vfat block counter)
        err_evtfifo_full_o          => open,
        err_evtfifo_underflow_o     => open, -- Tried to read too many events from the event fifo (indicates a problem in the AMC event builder)
        err_event_too_big_o         => open, -- detected an event with too many VFAT blocks (more than 4095 blocks!)
        err_vfat_block_too_small_o  => open, -- didn't get the full 14 VFAT words for some block
        err_vfat_block_too_big_o    => open -- got more than 14 VFAT words for one block
        
        -- IPbus
        --ipb_mosi_i                  => ipb_mosi_i,
        --ipb_miso_o                  => ipb_miso_o
    );
    
    --================================--
    -- TTS
    --================================--
    
--    tts_critical_error <= gs_event_too_big or 
--                          gs_event_fifo_full or 
--                          gs_input_fifo_underflow or 
--                          gs_input_fifo_full;
--                          
--    tts_warning <= gs_input_fifo_near_full or gs_event_fifo_near_full;
--    
--    tts_out_of_sync <= '0'; -- TODO: set this when serious OOS condition is detected (to be determined after looking at data)
--    
--    tts_busy <= reset_daq; -- not used for now (except for reset), but will be needed during resyncs (not implemented yet)
--                          
--    tts_state <= tts_override when (tts_override /= x"0") else
--                 x"8" when (daq_enable = '0') else
--                 x"4" when (tts_busy = '1') else
--                 x"c" when (tts_critical_error = '1') else
--                 x"2" when (tts_out_of_sync = '1') else
--                 x"1" when (tts_warning = '1') else
--                 x"8";
        
    --================================--
    -- DAQ Link
    --================================--

    -- DAQ Link instantiation
    daq_link : entity work.daqlink_wrapper
    port map(
        RESET_IN              => reset_daqlink,
        MGT_REF_CLK_IN        => mgt_ref_clk125_i,
        GTX_TXN_OUT           => daq_gtx_tx_pin_n,
        GTX_TXP_OUT           => daq_gtx_tx_pin_p,
        GTX_RXN_IN            => daq_gtx_rx_pin_n,
        GTX_RXP_IN            => daq_gtx_rx_pin_p,
        DATA_CLK_IN           => daq_clk_bufg,
        EVENT_DATA_IN         => daq_event_data,
        EVENT_DATA_HEADER_IN  => daq_event_header,
        EVENT_DATA_TRAILER_IN => daq_event_trailer,
        DATA_WRITE_EN_IN      => daq_event_write_en,
        READY_OUT             => daq_ready,
        ALMOST_FULL_OUT       => daq_almost_full,
        TTS_CLK_IN            => ttc_clk_i,
        TTS_STATE_IN          => tts_state,
        GTX_CLK_OUT           => daq_gtx_clk,
        ERR_DISPER_COUNT      => daq_disper_err_cnt,
        ERR_NOT_IN_TABLE_COUNT=> daq_notintable_err_cnt,
        BC0_IN                => ttc_bc0_i,
        CLK125_IN             => clk125_i
    );    
     
    --================================--
    -- Event shipping to DAQLink
    --================================--
    
    process(daq_clk_bufg)
    
        -- event info
        variable e_id                  : std_logic_vector(23 downto 0) := (others => '0');
        variable e_bx                  : std_logic_vector(11 downto 0) := (others => '0');
        variable e_payload_size        : unsigned(19 downto 0) := (others => '0');
        variable e_evtfifo_almost_full : std_logic := '0';
        variable e_evtfifo_full        : std_logic := '0';
        variable e_infifo_full         : std_logic := '0';
        variable e_evtfifo_near_full   : std_logic := '0';
        variable e_infifo_near_full    : std_logic := '0';
        variable e_infifo_underflow    : std_logic := '0';
        variable e_invalid_vfat_block  : std_logic := '0';
        variable e_event_too_big       : std_logic := '0';
        variable e_event_bigger_than_24: std_logic := '0';
        variable e_mixed_oh_bc         : std_logic := '0';
        variable e_mixed_vfat_bc       : std_logic := '0';
        variable e_mixed_vfat_ec       : std_logic := '0';
        
        -- counters
        variable word_count            : unsigned(19 downto 0) := (others => '0');
        
    begin
    
        if (rising_edge(daq_clk_bufg)) then
        
            if (reset_daq = '1') then
                daq_state <= x"0";
                daq_event_data <= (others => '0');
                daq_event_header <= '0';
                daq_event_trailer <= '0';
                daq_event_write_en <= '0';
                evtfifo_rd_en <= '0';
                daq_curr_vfat_block <= (others => '0');
                infifo_rd_en <= '0';
                daq_curr_block_word <= 0;
                cnt_sent_event <= (others => '0');
            else
            
                -- state machine for sending data
                -- state 0: idle
                -- state 1: sending the first AMC13 header
                -- state 2: sending the second AMC13 header
                -- state 3: sending the payload
                -- state 4: sending the AMC13 trailer
                if (daq_state = x"0") then
                
                    -- zero out everything, especially the write enable :)
                    daq_event_data <= (others => '0');
                    daq_event_header <= '0';
                    daq_event_trailer <= '0';
                    daq_event_write_en <= '0';
                    
                    -- if the DAQlink state is ok and the event fifo is not empty - start the DAQ state machine
                    if (evtfifo_empty = '0' and daq_ready = '1' and daq_almost_full = '0' and daq_enable = '1') then
                        daq_state <= x"1";
                        evtfifo_rd_en <= '1'; -- read in the event info
                    else
                        evtfifo_rd_en <= '0'; -- don't read unless it's a new event (DAQ is in state 0 and events are available)
                    end if;
                    
                else
                
                    evtfifo_rd_en <= '0'; -- make sure you're not reading the event fifo
                    -- lets send some data!
                    -- send the first AMC header
                    
                    if (daq_state = x"1") then
                        
                        -- wait for the evtfifo_valid flag and then populate the variables
                        if (evtfifo_valid = '1') then
                            e_id := evtfifo_dout(59 downto 36);
                            e_bx := evtfifo_dout(35 downto 24);
                            e_payload_size(11 downto 0) := unsigned(evtfifo_dout(23 downto 12));
                            e_evtfifo_almost_full := evtfifo_dout(11);
                            e_evtfifo_full        := evtfifo_dout(10);
                            e_infifo_full         := evtfifo_dout(9);
                            e_evtfifo_near_full   := evtfifo_dout(8);
                            e_infifo_near_full    := evtfifo_dout(7);
                            e_infifo_underflow    := evtfifo_dout(6);
                            e_event_too_big       := evtfifo_dout(5);
                            e_invalid_vfat_block  := evtfifo_dout(4);
                            e_event_bigger_than_24:= evtfifo_dout(3);
                            e_mixed_oh_bc         := evtfifo_dout(2);
                            e_mixed_vfat_bc       := evtfifo_dout(1);
                            e_mixed_vfat_ec       := evtfifo_dout(0);
                            
                            daq_curr_vfat_block <= unsigned(evtfifo_dout(23 downto 12)) - 3;
                        
                            daq_event_data <= x"00" & 
                                              e_id &   -- L1A ID
                                              e_bx &   -- BX ID
                                              std_logic_vector(e_payload_size + 7); -- fragment size (all VFAT payload plus 7 words of headers and trailers)
                            daq_event_header <= '1';
                            daq_event_trailer <= '0';
                            daq_event_write_en <= '1';
                            daq_state <= x"2";
                        end if;
                        
                    -- send the second AMC header
                    elsif (daq_state = x"2") then
                    
                        daq_event_data <= daq_format_version &
                                          run_type &
                                          run_params &
                                          ttc_orbit_id_i(15 downto 0) & 
                                          x"00" & 
                                          board_sn_i;
                        daq_event_header <= '0';
                        daq_event_trailer <= '0';
                        daq_event_write_en <= '1';
                        daq_state <= x"3";
                    
                    -- send the GEM Event header
                    elsif (daq_state = x"3") then
                        
                        daq_event_data <= x"000001" & -- DAV mask
                                          -- buffer status (set if we've ever had a buffer overflow)
                                          x"00000" & "000" &
                                          (err_event_too_big or e_evtfifo_full or e_infifo_underflow or e_infifo_full) &
                                          "00001" &   -- DAV count
                                          -- GLIB status
                                          "0000000" & -- Not used yet
                                          tts_state;
                        daq_event_header <= '0';
                        daq_event_trailer <= '0';
                        daq_event_write_en <= '1';
                        daq_state <= x"4";
                    
                    -- send the GEM Chamber header
                    elsif (daq_state = x"4") then

                        daq_event_data <= x"000000" & -- Zero suppression flags
                                          "00000" &    -- Input ID
                                          -- OH word count
                                          std_logic_vector(e_payload_size(11 downto 0)) &
                                          -- input status
                                          e_evtfifo_full &
                                          e_infifo_full &
                                          "0" & -- L1A fifo full
                                          e_event_too_big &
                                          e_evtfifo_near_full &
                                          e_infifo_near_full &
                                          "0" &  -- L1A fifo near full
                                          e_event_bigger_than_24 &
                                          e_invalid_vfat_block &
                                          "0" & -- OOS GLIB-VFAT
                                          "0" & -- OOS GLIB-OH
                                          "0" & -- GLIB-VFAT BX mismatch
                                          "0" & -- GLIB-OH BX mismatch
                                          x"00" & "00"; -- Not used

                        daq_event_header <= '0';
                        daq_event_trailer <= '0';
                        daq_event_write_en <= '1';
                        daq_state <= x"5";

                        -- read a block from the input fifo
                        infifo_rd_en <= '1';
                        daq_curr_block_word <= 2;
                        word_count := x"00000";

                    -- send the payload
                    elsif (daq_state = x"5") then
                    
                        -- read the next vfat block from the infifo if we're already working with the last word, but it's not yet the last block
                        if ((daq_curr_block_word = 0) and (daq_curr_vfat_block > x"0")) then
                            infifo_rd_en <= '1';
                            daq_curr_block_word <= 2;
                            daq_curr_vfat_block <= daq_curr_vfat_block - 3; -- this looks strange, but it's because this is not actually vfat_block but number of 64bit words of vfat data
                        -- we are done sending everything -- move on to the next state
                        elsif ((daq_curr_block_word = 0) and (daq_curr_vfat_block = x"0")) then
                            infifo_rd_en <= '0';
                            daq_state <= x"6";
                        -- we've just asserted infifo_rd_en, if the valid is still 0, then just wait (make sure infifo_rd_en is 0)
                        elsif ((daq_curr_block_word = 2) and (infifo_valid = '0')) then
                            infifo_rd_en <= '0';
                        -- lets move to the next vfat word
                        else
                            infifo_rd_en <= '0';
                            daq_curr_block_word <= daq_curr_block_word - 1;
                        end if;
                        
                        -- send the data!
                        if ((daq_curr_block_word < 2) or (infifo_valid = '1')) then
                            daq_event_data <= infifo_dout((((daq_curr_block_word + 1) * 64) - 1) downto (daq_curr_block_word * 64));
                            daq_event_header <= '0';
                            daq_event_trailer <= '0';
                            daq_event_write_en <= '1';
                            word_count := word_count + 1;
                        else
                            daq_event_write_en <= '0';
                        end if;

                    -- send the GEM Chamber trailer
                    elsif (daq_state = x"6") then
                    
                        daq_event_data <= x"0000" & -- OH CRC
                                          std_logic_vector(word_count(11 downto 0)) & -- OH word count
                                          -- GEM chamber status
                                          err_evtfifo_underflow &
                                          "0" &  -- stuck data
                                          "00" & x"00000000";
                        daq_event_header <= '0';
                        daq_event_trailer <= '0';
                        daq_event_write_en <= '1';
                        daq_state <= x"7";

                    -- send the GEM Event trailer
                    elsif (daq_state = x"7") then

                        daq_event_data <= x"000000" & -- Chamber timeout
                                          -- Event status (hmm)
                                          x"0" & "000" &
                                          "0" & -- GLIB OOS (different L1A IDs for different inputs)
                                          x"000000" &   -- Chamber error flag (hmm)
                                          -- GLIB status
                                          daq_almost_full &
                                          ttc_ready_i & 
                                          daq_clock_locked & 
                                          daq_ready &
                                          x"0";         -- Reserved
                        daq_event_header <= '0';
                        daq_event_trailer <= '0';
                        daq_event_write_en <= '1';
                        daq_state <= x"8";
                        
                    -- send the AMC trailer
                    elsif (daq_state = x"8") then
                    
                        daq_event_data <= x"00000000" & e_id(7 downto 0) & x"0" & std_logic_vector(word_count + 7); --& std_logic_vector(e_payload_size + 3);
                        daq_event_header <= '0';
                        daq_event_trailer <= '1';
                        daq_event_write_en <= '1';
                        daq_state <= x"0";
                        cnt_sent_event <= cnt_sent_event + 1;
                        
                    -- hmm
                    else
                    
                        daq_state <= x"0";
                        
                    end if;
                    
                end if;

            end if;
        end if;        
    end process;

    --================================--
    -- Monitoring
    --================================--
    
    --== DAQ control ==--
    ipb_read_reg_data(0)(0) <= daq_enable;
    ipb_read_reg_data(0)(3) <= reset_ipb;
    ipb_read_reg_data(0)(7 downto 4) <= tts_override;
    
    daq_enable <= ipb_write_reg_data(0)(0);
    reset_ipb <= ipb_write_reg_data(0)(3);
    tts_override <= ipb_write_reg_data(0)(7 downto 4);

    --== DAQ and TTS state ==--
    ipb_read_reg_data(1) <= tts_state &
                            x"000000" & 
                            daq_almost_full &
                            ttc_ready_i & 
                            daq_clock_locked & 
                            daq_ready;

    --== DAQLink error counters ==--
    ipb_read_reg_data(2)(15 downto 0) <= daq_notintable_err_cnt;
    ipb_read_reg_data(3)(15 downto 0) <= daq_disper_err_cnt;
    
    --== Number of received triggers (L1A ID) ==--
    ipb_read_reg_data(4) <= x"00" & ttc_l1a_id_i;

    --== Number of sent events ==--
    ipb_read_reg_data(5) <= std_logic_vector(cnt_sent_event);
    
    --== Software settable run type and run parameters ==--
    ipb_read_reg_data(15)(27 downto 24) <= run_type;
    ipb_read_reg_data(15)(23 downto 0) <= run_params;

    run_type <= ipb_write_reg_data(15)(27 downto 24);
    run_params <= ipb_write_reg_data(15)(23 downto 0);
    
    --******** registers below are input specific ********--
    
    --== FIFO current status and global flags ==--
--    ipb_read_reg_data(16) <= evtfifo_empty &             -- Event FIFO
--                            gs_event_fifo_near_full &
--                            evtfifo_full &
--                            evtfifo_underflow &
--                            infifo_empty &             -- Input FIFO
--                            gs_input_fifo_near_full &
--                            infifo_full &
--                            infifo_underflow &
--                            x"000" &
--                            gs_event_too_big &          -- Critical
--                            gs_event_fifo_full &        -- Critical
--                            gs_input_fifo_underflow &   -- Critical
--                            gs_input_fifo_full &        -- Critical
--                            gs_corrupted_vfat_data &    -- Corruption
--                            gs_vfat_block_too_big &     -- Corruption
--                            gs_vfat_block_too_small &   -- Corruption
--                            gs_event_bigger_than_24 &   -- Corruption
--                            gs_oos_oh &                 -- Out-of-sync
--                            gs_oos_glib_vfat &          -- Out-of-sync
--                            gs_oos_glib_oh &            -- Out-of-sync (might be normal for some time)
--                            gs_oos_oh_vfat;             -- Out-of-sync (normal for now)
                                
    --== Corrupted VFAT counter ==--    
--    ipb_read_reg_data(17) <= std_logic_vector(cnt_corrupted_vfat);

    --== Current event builder event number ==--
--    ipb_read_reg_data(18) <= x"00" & std_logic_vector(eb_event_num);
        
    --== Debug: last VFAT block ==--
--    ipb_read_reg_data(25) <= ep_vfat_block_data(31 downto 0);
--    ipb_read_reg_data(26) <= ep_vfat_block_data(63 downto 32);
--    ipb_read_reg_data(27) <= ep_vfat_block_data(95 downto 64);
--    ipb_read_reg_data(28) <= ep_vfat_block_data(127 downto 96);
--    ipb_read_reg_data(29) <= ep_vfat_block_data(159 downto 128);
--    ipb_read_reg_data(30) <= ep_vfat_block_data(191 downto 160);
--    ipb_read_reg_data(31) <= ep_vfat_block_data(223 downto 192);


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
                ipb_write_reg_data <= (others => (others => '0'));
                --ipb_write_reg_data(0)(0) <= '1'; -- enable DAQ by default
            else         
                case ipb_state is
                    when IDLE =>                    
                        ipb_reg_sel <= to_integer(unsigned(ipb_mosi_i.ipb_addr(4 downto 0)));
                        if (ipb_mosi_i.ipb_strobe = '1') then
                            ipb_state <= RSPD;
                        end if;
                    when RSPD =>
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

