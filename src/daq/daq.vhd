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
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;

library work;
use work.ipbus.all;
use work.system_package.all;
use work.user_package.all;

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
    tk_data_links_i             : in data_link_array_t(0 to number_of_optohybrids - 1);
    trig_data_links_i           : in trig_link_array_t(0 to number_of_optohybrids - 1);
    sbit_rate_i                 : in unsigned(31 downto 0);
    
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
    signal reset_daqlink_ipb    : std_logic := '0';

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
    signal tts_input_state_or   : std_logic_vector(3 downto 0);
    signal tts_critical_error   : std_logic := '0'; -- critical error detected - RESYNC/RESET NEEDED
    signal tts_warning          : std_logic := '0'; -- overflow warning - STOP TRIGGERS
    signal tts_out_of_sync      : std_logic := '0'; -- out-of-sync - RESYNC NEEDED
    signal tts_busy             : std_logic := '0'; -- I'm busy - NO TRIGGERS FOR NOW, PLEASE
    signal tts_override         : std_logic_vector(3 downto 0) := x"0"; -- this can be set via IPbus and will override the TTS state if it's not x"0" (regardless of reset_daq and daq_enable)
    
    signal tts_chmb_critical    : std_logic := '0'; -- input critical error detected - RESYNC/RESET NEEDED
    signal tts_chmb_warning     : std_logic := '0'; -- input overflow warning - STOP TRIGGERS
    signal tts_chmb_out_of_sync : std_logic := '0'; -- input out-of-sync - RESYNC NEEDED
    
    -- DAQ conf
    signal daq_enable           : std_logic := '1'; -- enable sending data to DAQLink
    signal input_mask           : std_logic_vector(23 downto 0) := x"000000";
    signal run_type             : std_logic_vector(3 downto 0) := x"0"; -- run type (set by software and included in the AMC header)
    signal run_params           : std_logic_vector(23 downto 0) := x"000000"; -- optional run parameters (set by software and included in the AMC header)
    
    -- DAQ counters
    signal cnt_sent_events      : unsigned(31 downto 0) := (others => '0');
    signal cnt_corrupted_vfat   : unsigned(31 downto 0) := (others => '0');

    -- DAQ event sending state machine
    signal daq_state            : unsigned(3 downto 0) := (others => '0');
    signal daq_curr_vfat_block  : unsigned(11 downto 0) := (others => '0');
    signal daq_curr_block_word  : integer range 0 to 2 := 0;
        
    -- IPbus registers
    type ipb_state_t is (IDLE, RSPD, RST);
    signal ipb_state                : ipb_state_t := IDLE;    
    signal ipb_reg_sel              : integer range 0 to (16 * (number_of_optohybrids + 10)) + 15; -- 16 regs for AMC evt builder and 16 regs for each chamber evt builder   
    signal ipb_read_reg_data        : std32_array_t(0 to (16 * (number_of_optohybrids + 10)) + 15); -- 16 regs for AMC evt builder and 16 regs for each chamber evt builder
    signal ipb_write_reg_data       : std32_array_t(0 to (16 * (number_of_optohybrids + 10)) + 15); -- 16 regs for AMC evt builder and 16 regs for each chamber evt builder
    
    -- L1A FIFO
    signal l1afifo_din          : std_logic_vector(51 downto 0) := (others => '0');
    signal l1afifo_wr_en        : std_logic := '0';
    signal l1afifo_rd_en        : std_logic := '0';
    signal l1afifo_dout         : std_logic_vector(51 downto 0);
    signal l1afifo_full         : std_logic;
    signal l1afifo_overflow     : std_logic;
    signal l1afifo_empty        : std_logic;
    signal l1afifo_valid        : std_logic;
    signal l1afifo_underflow    : std_logic;
    signal l1afifo_near_full    : std_logic;
    
    -- DAQ Error Flags
    signal err_l1afifo_full     : std_logic := '0';
    
    -- Timeouts
    signal dav_timer            : unsigned(23 downto 0) := (others => '0'); -- TODO: probably don't need this to be so large.. (need to test)
    signal max_dav_timer        : unsigned(23 downto 0) := (others => '0'); -- TODO: probably don't need this to be so large.. (need to test)
    signal last_dav_timer       : unsigned(23 downto 0) := (others => '0'); -- TODO: probably don't need this to be so large.. (need to test)
    signal dav_timeout          : unsigned(23 downto 0) := x"03d090"; -- 10ms (very large)
    signal dav_timeout_flags    : std_logic_vector(23 downto 0) := (others => '0'); -- inputs which have timed out
    
    ---=== AMC Event Builder signals ===---
    
    -- index of the input currently being processed
    signal e_input_idx                : integer range 0 to 23 := 0;
    
    -- word count of the event being sent
    signal e_word_count               : unsigned(19 downto 0) := (others => '0');

    -- bitmask indicating chambers with data for the event being sent
    signal e_dav_mask                 : std_logic_vector(23 downto 0) := (others => '0');
    -- number of chambers with data for the event being sent
    signal e_dav_count                : integer range 0 to 24;
           
    ---=== Chamber Event Builder signals ===---
    
    signal chamber_infifos      : chamber_infifo_rd_array_t(0 to number_of_optohybrids - 1);
    signal chamber_evtfifos     : chamber_evtfifo_rd_array_t(0 to number_of_optohybrids - 1);
    signal chmb_evtfifos_empty  : std_logic_vector(number_of_optohybrids - 1 downto 0) := (others => '1'); -- you should probably just move this flag out of the chamber_evtfifo_rd_array_t struct 
    signal chmb_evtfifos_rd_en  : std_logic_vector(number_of_optohybrids - 1 downto 0) := (others => '0'); -- you should probably just move this flag out of the chamber_evtfifo_rd_array_t struct 
    signal chmb_infifos_rd_en   : std_logic_vector(number_of_optohybrids - 1 downto 0) := (others => '0'); -- you should probably just move this flag out of the chamber_evtfifo_rd_array_t struct 
    signal chmb_tts_states      : std4_array_t(0 to number_of_optohybrids - 1);
    
    signal err_event_too_big    : std_logic;
    signal err_evtfifo_underflow: std_logic;
    
    -- Debug flags for ChipScope
    attribute MARK_DEBUG : string;
    attribute MARK_DEBUG of reset_daq           : signal is "TRUE";
    attribute MARK_DEBUG of daq_clk_bufg        : signal is "TRUE";

    attribute MARK_DEBUG of resync_i            : signal is "TRUE";
    attribute MARK_DEBUG of ttc_ready_i         : signal is "TRUE";
    attribute MARK_DEBUG of ttc_clk_i           : signal is "TRUE";
    attribute MARK_DEBUG of ttc_l1a_i           : signal is "TRUE";
    attribute MARK_DEBUG of ttc_bc0_i           : signal is "TRUE";
    attribute MARK_DEBUG of ttc_ec0_i           : signal is "TRUE";
    attribute MARK_DEBUG of ttc_bx_id_i         : signal is "TRUE";
    attribute MARK_DEBUG of ttc_orbit_id_i      : signal is "TRUE";
    attribute MARK_DEBUG of ttc_l1a_id_i        : signal is "TRUE";
    
    attribute MARK_DEBUG of dav_timer           : signal is "TRUE";
    attribute MARK_DEBUG of max_dav_timer       : signal is "TRUE";
    attribute MARK_DEBUG of last_dav_timer      : signal is "TRUE";
    attribute MARK_DEBUG of dav_timeout         : signal is "TRUE";
    attribute MARK_DEBUG of dav_timeout_flags   : signal is "TRUE";

    attribute MARK_DEBUG of daq_state           : signal is "TRUE";
    attribute MARK_DEBUG of daq_curr_vfat_block : signal is "TRUE";
    attribute MARK_DEBUG of daq_curr_block_word : signal is "TRUE";

    attribute MARK_DEBUG of daq_event_data      : signal is "TRUE";
    attribute MARK_DEBUG of daq_event_write_en  : signal is "TRUE";
    attribute MARK_DEBUG of daq_event_header    : signal is "TRUE";
    attribute MARK_DEBUG of daq_event_trailer   : signal is "TRUE";
    attribute MARK_DEBUG of daq_ready           : signal is "TRUE";
    attribute MARK_DEBUG of daq_almost_full     : signal is "TRUE";
    
    attribute MARK_DEBUG of input_mask          : signal is "TRUE";
    attribute MARK_DEBUG of e_input_idx         : signal is "TRUE";
    attribute MARK_DEBUG of e_word_count        : signal is "TRUE";
    attribute MARK_DEBUG of e_dav_mask          : signal is "TRUE";
    attribute MARK_DEBUG of e_dav_count         : signal is "TRUE";
    
    attribute MARK_DEBUG of l1afifo_dout        : signal is "TRUE";
    attribute MARK_DEBUG of l1afifo_rd_en       : signal is "TRUE";
    attribute MARK_DEBUG of l1afifo_empty       : signal is "TRUE";
    
    attribute MARK_DEBUG of chmb_evtfifos_empty : signal is "TRUE";
    attribute MARK_DEBUG of chmb_evtfifos_rd_en : signal is "TRUE";
    attribute MARK_DEBUG of chmb_infifos_rd_en  : signal is "TRUE";
    
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

begin

    -- TODO main tasks:
    --   * Handle OOS
    --   * Implement buffer status in the AMC header
    --   * TTS State aggregation
    --   * Check for VFAT and OH BX vs L1A bx mismatches
    --   * Resync handling
    --   * Stop building events if input fifo is full -- let it drain to some level and only then restart building (otherwise you're pointing to inexisting data). I guess it's better to loose some data than to have something that doesn't make any sense..

    --================================--
    -- Resets
    --================================--
    
    reset_daq <= reset_pwrup or reset_i or reset_ipb;
    reset_daqlink <= reset_pwrup or reset_i or reset_daqlink_ipb;
    
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
    -- L1A FIFO
    --================================--
    
    daq_l1a_fifo_inst : entity work.daq_l1a_fifo
    PORT MAP (
        rst => reset_daq,
        wr_clk => ttc_clk_i,
        rd_clk => daq_clk_bufg,
        din => l1afifo_din,
        wr_en => l1afifo_wr_en,
        wr_ack => open,
        rd_en => l1afifo_rd_en,
        dout => l1afifo_dout,
        full => l1afifo_full,
        overflow => l1afifo_overflow,
        almost_full => open,
        empty => l1afifo_empty,
        valid => l1afifo_valid,
        underflow => l1afifo_underflow,
        prog_full => l1afifo_near_full
    );
    
    -- fill the L1A FIFO
    process(ttc_clk_i)
    begin
        if (rising_edge(ttc_clk_i)) then
            if (reset_daq = '1') then
                err_l1afifo_full <= '0';
                l1afifo_wr_en <= '0';
            else
                if (ttc_l1a_i = '1') then
                    if (l1afifo_full = '0') then
                        l1afifo_din <= ttc_l1a_id_i & ttc_orbit_id_i & ttc_bx_id_i;
                        l1afifo_wr_en <= '1';
                    else
                        err_l1afifo_full <= '1';
                        l1afifo_wr_en <= '0';
                    end if;
                else
                    l1afifo_wr_en <= '0';
                end if;
            end if;
        end if;
    end process;
    
    --================================--
    -- Chamber Event Builders
    --================================--

    chamber_evt_builder_loop : for I in 0 to (number_of_optohybrids - 1) generate
    begin

        track_input_processors : entity work.track_input_processor
        port map
        (
            -- Reset
            reset_i                     => reset_daq,

            -- Config
            input_enable_i              => input_mask(I),

            -- FIFOs
            fifo_rd_clk_i               => daq_clk_bufg,
            infifo_dout_o               => chamber_infifos(I).dout,
            infifo_rd_en_i              => chamber_infifos(I).rd_en,
            infifo_empty_o              => chamber_infifos(I).empty,
            infifo_valid_o              => chamber_infifos(I).valid,
            infifo_underflow_o          => chamber_infifos(I).underflow,
            evtfifo_dout_o              => chamber_evtfifos(I).dout,
            evtfifo_rd_en_i             => chamber_evtfifos(I).rd_en,
            evtfifo_empty_o             => chamber_evtfifos(I).empty,
            evtfifo_valid_o             => chamber_evtfifos(I).valid,
            evtfifo_underflow_o         => chamber_evtfifos(I).underflow,

            -- Track data
            tk_data_link_i              => tk_data_links_i(I),
            
            -- TTS
            tts_state_o                 => chmb_tts_states(I),

            -- Critical error flags
            err_infifo_full_o           => open,
            err_infifo_underflow_o      => open, -- Tried to read too many blocks from the input fifo when sending events to the DAQlink (indicates a problem in the vfat block counter)
            err_evtfifo_full_o          => open,
            err_evtfifo_underflow_o     => open, -- Tried to read too many events from the event fifo (indicates a problem in the AMC event builder)
            err_event_too_big_o         => open, -- detected an event with too many VFAT blocks (more than 4095 blocks!)
            err_vfat_block_too_small_o  => open, -- didn't get the full 14 VFAT words for some block
            err_vfat_block_too_big_o    => open, -- got more than 14 VFAT words for one block
            
            -- IPbus (the first 16 regs are reserved for AMC event builder and then each chamber event builder will get 16 regs above that)
--            ipb_read_reg_data_o         => ipb_read_reg_data(((I + 1) * 16) to (((I + 2) * 16) - 1)),
--            ipb_write_reg_data_i        => ipb_write_reg_data(((I + 1) * 16) to (((I + 2) * 16) - 1))
            ipb_read_reg_data_o         => ipb_read_reg_data((I+1) * 16 to (I+1) * 16 + 15),
            ipb_write_reg_data_i        => ipb_write_reg_data((I+1) * 16 to (I+1) * 16 + 15)
        );
    
        chmb_evtfifos_empty(I) <= chamber_evtfifos(I).empty;
        chamber_evtfifos(I).rd_en <= chmb_evtfifos_rd_en(I);
        chamber_infifos(I).rd_en <= chmb_infifos_rd_en(I);
        
    end generate;
        
    --================================--
    -- TTS
    --================================--

    process (tk_data_links_i(0).clk)
    begin
        if (rising_edge(tk_data_links_i(0).clk)) then
            for I in 0 to (number_of_optohybrids - 1) loop
                tts_chmb_critical <= tts_chmb_critical or (chmb_tts_states(I)(2) and input_mask(I) and not reset_daq);
                tts_chmb_out_of_sync <= tts_chmb_out_of_sync or (chmb_tts_states(I)(1) and input_mask(I));
                tts_chmb_warning <= tts_chmb_warning or (chmb_tts_states(I)(0) and input_mask(I));
            end loop;
        end if;
    end process;

    tts_critical_error <= tts_critical_error or err_l1afifo_full or tts_chmb_critical;
    tts_out_of_sync <= tts_chmb_out_of_sync;
    tts_warning <= tts_warning or l1afifo_near_full or tts_chmb_warning;
    tts_busy <= reset_daq;

    tts_state <= tts_override when (tts_override /= x"0") else
                 x"8" when (daq_enable = '0') else
                 x"4" when (tts_busy = '1') else
                 x"c" when (tts_critical_error = '1') else
                 x"2" when (tts_out_of_sync = '1') else
                 x"1" when (tts_warning = '1') else
                 x"8";
        
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
        variable e_l1a_id                   : std_logic_vector(23 downto 0) := (others => '0');        
        variable e_bx_id                    : std_logic_vector(11 downto 0) := (others => '0');        
        variable e_orbit_id                 : std_logic_vector(15 downto 0) := (others => '0');        

        -- event chamber info; TODO: convert these to signals (but would require additional state)
        variable e_chmb_l1a_id              : std_logic_vector(23 downto 0) := (others => '0');
        variable e_chmb_bx_id               : std_logic_vector(11 downto 0) := (others => '0');
        variable e_chmb_payload_size        : unsigned(19 downto 0) := (others => '0');
        variable e_chmb_evtfifo_afull       : std_logic := '0';
        variable e_chmb_evtfifo_full        : std_logic := '0';
        variable e_chmb_infifo_full         : std_logic := '0';
        variable e_chmb_evtfifo_near_full   : std_logic := '0';
        variable e_chmb_infifo_near_full    : std_logic := '0';
        variable e_chmb_infifo_underflow    : std_logic := '0';
        variable e_chmb_invalid_vfat_block  : std_logic := '0';
        variable e_chmb_evt_too_big         : std_logic := '0';
        variable e_chmb_evt_bigger_24       : std_logic := '0';
        variable e_chmb_mixed_oh_bc         : std_logic := '0';
        variable e_chmb_mixed_vfat_bc       : std_logic := '0';
        variable e_chmb_mixed_vfat_ec       : std_logic := '0';
              
    begin
    
        if (rising_edge(daq_clk_bufg)) then
        
            if (reset_daq = '1') then
                daq_state <= x"0";
                daq_event_data <= (others => '0');
                daq_event_header <= '0';
                daq_event_trailer <= '0';
                daq_event_write_en <= '0';
                chmb_evtfifos_rd_en <= (others => '0');
                l1afifo_rd_en <= '0';
                daq_curr_vfat_block <= (others => '0');
                chmb_infifos_rd_en <= (others => '0');
                daq_curr_block_word <= 0;
                cnt_sent_events <= (others => '0');
                e_word_count <= (others => '0');
                dav_timer <= (others => '0');
                max_dav_timer <= (others => '0');
                last_dav_timer <= (others => '0');
                dav_timeout_flags <= (others => '0');
            else
            
                -- state machine for sending data
                -- state 0: idle
                -- state 1: send the first AMC header
                -- state 2: send the second AMC header
                -- state 3: send the GEM Event header
                -- state 4: send the GEM Chamber header
                -- state 5: send the payload
                -- state 6: send the GEM Chamber trailer
                -- state 7: send the GEM Event trailer
                -- state 8: send the AMC trailer
                if (daq_state = x"0") then
                
                    -- zero out everything, especially the write enable :)
                    daq_event_data <= (others => '0');
                    daq_event_header <= '0';
                    daq_event_trailer <= '0';
                    daq_event_write_en <= '0';
                    e_word_count <= (others => '0');
                    e_input_idx <= 0;
                    
                    
                    -- have an L1A and data from all enabled inputs is ready (or these inputs have timed out)
                    if (l1afifo_empty = '0' and ((input_mask and ((not chmb_evtfifos_empty) or dav_timeout_flags)) = input_mask)) then
                        if (daq_ready = '1' and daq_almost_full = '0' and daq_enable = '1') then -- everybody ready?.... GO! :)
                            -- start the DAQ state machine
                            daq_state <= x"1";
                            
                            -- fetch the data from the L1A FIFO
                            l1afifo_rd_en <= '1';
                            
                            -- set the DAV mask
                            e_dav_mask <= input_mask and ((not chmb_evtfifos_empty) and (not dav_timeout_flags));
                            
                            -- save timer stats
                            dav_timer <= (others => '0');
                            last_dav_timer <= dav_timer;
                            if ((dav_timer > max_dav_timer) and (or_reduce(dav_timeout_flags) = '0')) then
                                max_dav_timer <= dav_timer;
                            end if;
                        end if;
                    -- have an L1A, but waiting for data -- start counting the time
                    elsif (l1afifo_empty = '0') then
                        dav_timer <= dav_timer + 1;
                    end if;
                    
                    -- set the timeout flags if the timer has reached the dav_timeout value
                    if (dav_timer >= dav_timeout) then
                        dav_timeout_flags <= chmb_evtfifos_empty and input_mask;
                    end if;
                                        
                else -- lets send some data!
                
                    l1afifo_rd_en <= '0';
                    
                    ----==== send the first AMC header ====----
                    if (daq_state = x"1") then
                        
                        -- wait for the valid flag from the L1A FIFO and then populate the variables and AMC header
                        if (l1afifo_valid = '1') then
                        
                            -- fetch the L1A data
                            e_l1a_id        := l1afifo_dout(51 downto 28);
                            e_orbit_id      := l1afifo_dout(27 downto 12);
                            e_bx_id         := l1afifo_dout(11 downto 0);

                            -- send the data
                            daq_event_data <= x"00" & 
                                              e_l1a_id &   -- L1A ID
                                              e_bx_id &   -- BX ID
                                              x"fffff";
                            daq_event_header <= '1';
                            daq_event_trailer <= '0';
                            daq_event_write_en <= '1';
                            
                            -- move to the next state
                            e_word_count <= e_word_count + 1;
                            daq_state <= x"2";
                            
                        end if;
                        
                    ----==== send the second AMC header ====----
                    elsif (daq_state = x"2") then
                    
                        -- calculate the DAV count (I know it's ugly...)
                        e_dav_count <= to_integer(unsigned(e_dav_mask(0 downto 0))) + to_integer(unsigned(e_dav_mask(1 downto 1))) + to_integer(unsigned(e_dav_mask(2 downto 2))) + to_integer(unsigned(e_dav_mask(3 downto 3))) + to_integer(unsigned(e_dav_mask(4 downto 4))) + to_integer(unsigned(e_dav_mask(5 downto 5))) + to_integer(unsigned(e_dav_mask(6 downto 6))) + to_integer(unsigned(e_dav_mask(7 downto 7))) + to_integer(unsigned(e_dav_mask(8 downto 8))) + to_integer(unsigned(e_dav_mask(9 downto 9))) + to_integer(unsigned(e_dav_mask(10 downto 10))) + to_integer(unsigned(e_dav_mask(11 downto 11))) + to_integer(unsigned(e_dav_mask(12 downto 12))) + to_integer(unsigned(e_dav_mask(13 downto 13))) + to_integer(unsigned(e_dav_mask(14 downto 14))) + to_integer(unsigned(e_dav_mask(15 downto 15))) + to_integer(unsigned(e_dav_mask(16 downto 16))) + to_integer(unsigned(e_dav_mask(17 downto 17))) + to_integer(unsigned(e_dav_mask(18 downto 18))) + to_integer(unsigned(e_dav_mask(19 downto 19))) + to_integer(unsigned(e_dav_mask(20 downto 20))) + to_integer(unsigned(e_dav_mask(21 downto 21))) + to_integer(unsigned(e_dav_mask(22 downto 22))) + to_integer(unsigned(e_dav_mask(23 downto 23)));
                        
                        -- send the data
                        daq_event_data <= daq_format_version &
                                          run_type &
                                          run_params &
                                          e_orbit_id & 
                                          x"00" & 
                                          board_sn_i;
                        daq_event_header <= '0';
                        daq_event_trailer <= '0';
                        daq_event_write_en <= '1';
                        
                        -- move to the next state
                        e_word_count <= e_word_count + 1;
                        daq_state <= x"3";
                    
                    ----==== send the GEM Event header ====----
                    elsif (daq_state = x"3") then
                        
                        -- if this input doesn't have data and we're not at the last input yet, then go to the next input
                        if ((e_input_idx < number_of_optohybrids - 1) and (e_dav_mask(e_input_idx) = '0')) then 
                        
                            daq_event_write_en <= '0';
                            e_input_idx <= e_input_idx + 1;
                            
                        else

                            -- send the data
                            daq_event_data <= e_dav_mask & -- DAV mask
                                              -- buffer status (set if we've ever had a buffer overflow)
                                              x"000000" & -- TODO: implement buffer status flag
                                              --(err_event_too_big or e_chmb_evtfifo_full or e_chmb_infifo_underflow or e_chmb_infifo_full) &
                                              std_logic_vector(to_unsigned(e_dav_count, 5)) &   -- DAV count
                                              -- GLIB status
                                              "0000000" & -- Not used yet
                                              tts_state;
                            daq_event_header <= '0';
                            daq_event_trailer <= '0';
                            daq_event_write_en <= '1';
                            e_word_count <= e_word_count + 1;
                            
                            -- if we have data then read the event fifo and send the chamber data
                            if (e_dav_mask(e_input_idx) = '1') then
                            
                                -- read the first chamber event fifo
                                chmb_evtfifos_rd_en(e_input_idx) <= '1';

                                -- move to the next state
                                daq_state <= x"4";
                            
                            -- no data on this input - skip to event trailer                            
                            else
                            
                                daq_state <= x"7";
                                
                            end if;
                        
                        end if;
                    
                    ----==== send the GEM Chamber header ====----
                    elsif (daq_state = x"4") then
                    
                        -- reset the read enable
                        chmb_evtfifos_rd_en(e_input_idx) <= '0';
                        
                        -- wait for the valid flag and then fetch the chamber event data
                        if (chamber_evtfifos(e_input_idx).valid = '1') then
                        
                            e_chmb_l1a_id                       := chamber_evtfifos(e_input_idx).dout(59 downto 36);
                            e_chmb_bx_id                        := chamber_evtfifos(e_input_idx).dout(35 downto 24);
                            e_chmb_payload_size(11 downto 0)    := unsigned(chamber_evtfifos(e_input_idx).dout(23 downto 12));
                            e_chmb_evtfifo_afull                := chamber_evtfifos(e_input_idx).dout(11);
                            e_chmb_evtfifo_full                 := chamber_evtfifos(e_input_idx).dout(10);
                            e_chmb_infifo_full                  := chamber_evtfifos(e_input_idx).dout(9);
                            e_chmb_evtfifo_near_full            := chamber_evtfifos(e_input_idx).dout(8);
                            e_chmb_infifo_near_full             := chamber_evtfifos(e_input_idx).dout(7);
                            e_chmb_infifo_underflow             := chamber_evtfifos(e_input_idx).dout(6);
                            e_chmb_evt_too_big                  := chamber_evtfifos(e_input_idx).dout(5);
                            e_chmb_invalid_vfat_block           := chamber_evtfifos(e_input_idx).dout(4);
                            e_chmb_evt_bigger_24                := chamber_evtfifos(e_input_idx).dout(3);
                            e_chmb_mixed_oh_bc                  := chamber_evtfifos(e_input_idx).dout(2);
                            e_chmb_mixed_vfat_bc                := chamber_evtfifos(e_input_idx).dout(1);
                            e_chmb_mixed_vfat_ec                := chamber_evtfifos(e_input_idx).dout(0);

                            daq_curr_vfat_block <= unsigned(chamber_evtfifos(e_input_idx).dout(23 downto 12)) - 3;
                            
                            -- send the data
                            daq_event_data <= x"000000" & -- Zero suppression flags
                                              std_logic_vector(to_unsigned(e_input_idx, 5)) &    -- Input ID
                                              -- OH word count
                                              std_logic_vector(e_chmb_payload_size(11 downto 0)) &
                                              -- input status
                                              e_chmb_evtfifo_full &
                                              e_chmb_infifo_full &
                                              err_l1afifo_full &
                                              e_chmb_evt_too_big &
                                              e_chmb_evtfifo_near_full &
                                              e_chmb_infifo_near_full &
                                              l1afifo_near_full &
                                              e_chmb_evt_bigger_24 &
                                              e_chmb_invalid_vfat_block &
                                              "0" & -- OOS GLIB-VFAT
                                              "0" & -- OOS GLIB-OH
                                              "0" & -- GLIB-VFAT BX mismatch
                                              "0" & -- GLIB-OH BX mismatch
                                              x"00" & "00"; -- Not used

                            daq_event_header <= '0';
                            daq_event_trailer <= '0';
                            daq_event_write_en <= '1';
                            
                            -- move to the next state
                            e_word_count <= e_word_count + 1;
                            daq_state <= x"5";

                            -- read a block from the input fifo
                            chmb_infifos_rd_en(e_input_idx) <= '1';
                            daq_curr_block_word <= 2;
                        
                        else
                        
                            daq_event_write_en <= '0';
                            
                        end if; 

                    ----==== send the payload ====----
                    elsif (daq_state = x"5") then
                    
                        -- read the next vfat block from the infifo if we're already working with the last word, but it's not yet the last block
                        if ((daq_curr_block_word = 0) and (daq_curr_vfat_block /= x"000")) then
                            chmb_infifos_rd_en(e_input_idx) <= '1';
                            daq_curr_block_word <= 2;
                            daq_curr_vfat_block <= daq_curr_vfat_block - 3; -- this looks strange, but it's because this is not actually vfat_block but number of 64bit words of vfat data
                        -- we are done sending everything -- move on to the next state
                        elsif ((daq_curr_block_word = 0) and (daq_curr_vfat_block = x"0")) then
                            chmb_infifos_rd_en(e_input_idx) <= '0';
                            daq_state <= x"6";
                        -- we've just asserted chmb_infifos_rd_en(e_input_idx), if the valid is still 0, then just wait (make sure chmb_infifos_rd_en(e_input_idx) is 0)
                        elsif ((daq_curr_block_word = 2) and (chamber_infifos(e_input_idx).valid = '0')) then
                            chmb_infifos_rd_en(e_input_idx) <= '0';
                        -- lets move to the next vfat word
                        else
                            chmb_infifos_rd_en(e_input_idx) <= '0';
                            daq_curr_block_word <= daq_curr_block_word - 1;
                        end if;
                        
                        -- send the data!
                        if ((daq_curr_block_word < 2) or (chamber_infifos(e_input_idx).valid = '1')) then
                            daq_event_data <= chamber_infifos(e_input_idx).dout((((daq_curr_block_word + 1) * 64) - 1) downto (daq_curr_block_word * 64));
                            daq_event_header <= '0';
                            daq_event_trailer <= '0';
                            daq_event_write_en <= '1';
                            e_word_count <= e_word_count + 1;
                        else
                            daq_event_write_en <= '0';
                        end if;

                    ----==== send the GEM Chamber trailer ====----
                    elsif (daq_state = x"6") then
                        
                        -- increment the input index if it hasn't maxed out yet
                        if (e_input_idx < number_of_optohybrids - 1) then
                            e_input_idx <= e_input_idx + 1;
                        end if;
                        
                        -- if we have data for the next input or if we've reached the last input
                        if ((e_input_idx >= number_of_optohybrids - 1) or (e_dav_mask(e_input_idx + 1) = '1')) then
                        
                            -- send the data
                            daq_event_data <= x"0000" & -- OH CRC
                                              std_logic_vector(e_chmb_payload_size(11 downto 0)) & -- OH word count
                                              -- GEM chamber status
                                              err_evtfifo_underflow &
                                              "0" &  -- stuck data
                                              "00" & x"00000000";
                            daq_event_header <= '0';
                            daq_event_trailer <= '0';
                            daq_event_write_en <= '1';
                            e_word_count <= e_word_count + 1;
                                
                            -- if we have data for the next input then read the infifo and go to chamber data sending
                            if (e_dav_mask(e_input_idx + 1) = '1') then
                                chmb_evtfifos_rd_en(e_input_idx + 1) <= '1';
                                daq_state <= x"4";                            
                            else -- if next input doesn't have data we can only get here if we're at the last input, so move to the event trailer
                                daq_state <= x"7";
                            end if;
                         
                        else
                        
                            daq_event_write_en <= '0';
                            
                        end if;
                        
                    ----==== send the GEM Event trailer ====----
                    elsif (daq_state = x"7") then

                        daq_event_data <= dav_timeout_flags & -- Chamber timeout
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
                        e_word_count <= e_word_count + 1;
                        daq_state <= x"8";
                        
                    ----==== send the AMC trailer ====----
                    elsif (daq_state = x"8") then
                    
                        -- send the AMC trailer data
                        daq_event_data <= x"00000000" & e_l1a_id(7 downto 0) & x"0" & std_logic_vector(e_word_count + 1);
                        daq_event_header <= '0';
                        daq_event_trailer <= '1';
                        daq_event_write_en <= '1';
                        
                        -- go back to DAQ idle state
                        daq_state <= x"0";
                        
                        -- reset things
                        e_word_count <= (others => '0');
                        e_input_idx <= 0;
                        cnt_sent_events <= cnt_sent_events + 1;
                        dav_timeout_flags <= x"000000";
                        
                    -- hmm
                    else
                    
                        daq_state <= x"0";
                        
                    end if;
                    
                end if;

            end if;
        end if;        
    end process;

    --================================--
    -- Monitoring & Control
    --================================--
    
    --== DAQ control ==--
    ipb_read_reg_data(0)(0) <= daq_enable;
    ipb_read_reg_data(0)(2) <= reset_daqlink_ipb;
    ipb_read_reg_data(0)(3) <= reset_ipb;
    ipb_read_reg_data(0)(7 downto 4) <= tts_override;
    ipb_read_reg_data(0)(31 downto 8) <= input_mask;
    
    daq_enable <= ipb_write_reg_data(0)(0);
    reset_daqlink_ipb <= ipb_write_reg_data(0)(2);
    reset_ipb <= ipb_write_reg_data(0)(3);
    tts_override <= ipb_write_reg_data(0)(7 downto 4);
    input_mask <= ipb_write_reg_data(0)(31 downto 8);

    --== DAQ and TTS state ==--
    ipb_read_reg_data(1) <= tts_state &
                            l1afifo_empty &
                            l1afifo_near_full &
                            l1afifo_full &
                            l1afifo_underflow &
                            err_l1afifo_full &
                            x"0000" & "000" &
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
    ipb_read_reg_data(5) <= std_logic_vector(cnt_sent_events);
    
    --== DAV Timeout ==--
    ipb_read_reg_data(6)(23 downto 0) <= std_logic_vector(dav_timeout);
    dav_timeout <= unsigned(ipb_write_reg_data(6)(23 downto 0));

    --== DAV Timing stats ==--    
    ipb_read_reg_data(7)(23 downto 0) <= std_logic_vector(max_dav_timer);
    ipb_read_reg_data(8)(23 downto 0) <= std_logic_vector(last_dav_timer);

    --== SBit clusters ==--
    process(tk_data_links_i(0).clk)
    begin
        if (rising_edge(tk_data_links_i(0).clk)) then
            if (trig_data_links_i(0).data_en = '1') then
                ipb_read_reg_data(9)(30 downto 28) <= trig_data_links_i(0).data(55 downto 53);
                ipb_read_reg_data(9)(26 downto 16) <= trig_data_links_i(0).data(52 downto 42);
                ipb_read_reg_data(9)(14 downto 12) <= trig_data_links_i(0).data(41 downto 39);
                ipb_read_reg_data(9)(10 downto 0) <= trig_data_links_i(0).data(38 downto 28);
                
                ipb_read_reg_data(10)(30 downto 28) <= trig_data_links_i(0).data(27 downto 25);
                ipb_read_reg_data(10)(26 downto 16) <= trig_data_links_i(0).data(24 downto 14);
                ipb_read_reg_data(10)(14 downto 12) <= trig_data_links_i(0).data(13 downto 11);
                ipb_read_reg_data(10)(10 downto 0) <= trig_data_links_i(0).data(10 downto 0);
            end if;
            
            if (trig_data_links_i(1).data_en = '1') then    
                ipb_read_reg_data(11)(30 downto 28) <= trig_data_links_i(1).data(55 downto 53);
                ipb_read_reg_data(11)(26 downto 16) <= trig_data_links_i(1).data(52 downto 42);
                ipb_read_reg_data(11)(14 downto 12) <= trig_data_links_i(1).data(41 downto 39);
                ipb_read_reg_data(11)(10 downto 0) <= trig_data_links_i(1).data(38 downto 28);
                
                ipb_read_reg_data(12)(30 downto 28) <= trig_data_links_i(1).data(27 downto 25);
                ipb_read_reg_data(12)(26 downto 16) <= trig_data_links_i(1).data(24 downto 14);
                ipb_read_reg_data(12)(14 downto 12) <= trig_data_links_i(1).data(13 downto 11);
                ipb_read_reg_data(12)(10 downto 0) <= trig_data_links_i(1).data(10 downto 0);
            end if;
        end if;
    end process;    
    
    ipb_read_reg_data(13) <= std_logic_vector(sbit_rate_i);
    
    --== Software settable run type and run parameters ==--
    ipb_read_reg_data(15)(27 downto 24) <= run_type;
    ipb_read_reg_data(15)(23 downto 0) <= run_params;

    run_type <= ipb_write_reg_data(15)(27 downto 24);
    run_params <= ipb_write_reg_data(15)(23 downto 0);    

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
                ipb_write_reg_data(0)(31 downto 8) <= x"000001"; -- enable the first input by default
                ipb_write_reg_data(6)(23 downto 0) <= x"03d090"; -- default DAV timeout of 10ms
                
                for I in 0 to (number_of_optohybrids - 1) loop
                    ipb_write_reg_data((I+1)*16 + 3)(23 downto 0) <= x"000c35"; -- default DAV timeout of 10ms
                end loop;
            else         
                case ipb_state is
                    when IDLE =>                    
                        ipb_reg_sel <= to_integer(unsigned(ipb_mosi_i.ipb_addr(8 downto 0)));
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

