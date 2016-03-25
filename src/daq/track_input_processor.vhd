----------------------------------------------------------------------------------
-- Company: Texas A&M University
-- Engineer: Evaldas Juska (Evaldas.Juska@cern.ch)
-- 
-- Create Date:    14:00:00 11-Jan-2016 
-- Design Name:    GLIB v2
-- Module Name:    Track Input Processor
-- Project Name:   GLIB v2
-- Target Devices: xc6vlx130t-1ff1156
-- Tool versions:  ISE  P.20131013
-- Description:    This module buffers track data from one OH, builds events, analyses the data for consistency and provides the events to the DAQ module for merging with other chambers and shipping to AMC13
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.ipbus.all;
use work.system_package.all;
use work.user_package.all;

entity track_input_processor is
port(
    -- Reset
    reset_i                     : in std_logic;

    -- Config
    input_enable_i              : in std_logic; -- shuts off input for this module if 0

    -- FIFOs
    fifo_rd_clk_i               : in std_logic;
    infifo_dout_o               : out std_logic_vector(191 downto 0);
    infifo_rd_en_i              : in std_logic;
    infifo_empty_o              : out std_logic;
    infifo_valid_o              : out std_logic;
    infifo_underflow_o          : out std_logic;
    evtfifo_dout_o              : out std_logic_vector(59 downto 0);
    evtfifo_rd_en_i             : in std_logic;
    evtfifo_empty_o             : out std_logic;
    evtfifo_valid_o             : out std_logic;
    evtfifo_underflow_o         : out std_logic;

    -- Track data
    tk_data_link_i              : in data_link_t;
    
    -- TTS
    tts_state_o                 : out std_logic_vector(3 downto 0);
    
    -- Critical error flags
    err_infifo_full_o           : out std_logic;
    err_infifo_underflow_o      : out std_logic; -- Tried to read too many blocks from the input fifo when sending events to the DAQlink (indicates a problem in the vfat block counter)
    err_evtfifo_full_o          : out std_logic;
    err_evtfifo_underflow_o     : out std_logic; -- Tried to read too many events from the event fifo (indicates a problem in the AMC event builder)
    err_event_too_big_o         : out std_logic; -- detected an event with too many VFAT blocks (more than 4095 blocks!)
    err_vfat_block_too_small_o  : out std_logic; -- didn't get the full 14 VFAT words for some block
    err_vfat_block_too_big_o    : out std_logic; -- got more than 14 VFAT words for one block
    
    -- IPbus
    ipb_read_reg_data_o         : out std32_array_t(0 to 15);
    ipb_write_reg_data_i        : in std32_array_t(0 to 15)
);

end track_input_processor;

architecture Behavioral of track_input_processor is

    -- Constants (TODO: should be moved to package)
    constant vfat_block_marker      : std_logic_vector(47 downto 0) := x"a000c000e000";

    -- TTS
    signal tts_state                : std_logic_vector(3 downto 0) := "1000";
    signal tts_critical_error       : std_logic := '0'; -- critical error detected - RESYNC/RESET NEEDED
    signal tts_warning              : std_logic := '0'; -- overflow warning - STOP TRIGGERS
    signal tts_out_of_sync          : std_logic := '0'; -- out-of-sync - RESYNC NEEDED
    signal tts_busy                 : std_logic := '0'; -- I'm busy - NO TRIGGERS FOR NOW, PLEASE

    -- Counters
    signal cnt_corrupted_vfat       : unsigned(31 downto 0) := (others => '0');

    -- Error/warning flags (latched)
    signal err_infifo_full          : std_logic := '0';
    signal err_infifo_near_full     : std_logic := '0';
    signal err_infifo_underflow     : std_logic := '0'; -- Tried to read too many blocks from the input fifo when sending events to the DAQlink (indicates a problem in the vfat block counter)
    signal err_evtfifo_full         : std_logic := '0';
    signal err_evtfifo_near_full    : std_logic := '0';
    signal err_evtfifo_underflow    : std_logic := '0'; -- Tried to read too many events from the event fifo (indicates a problem in the AMC event builder)
    signal err_corrupted_vfat_data  : std_logic := '0'; -- detected at least one invalid VFAT block
    signal err_event_too_big        : std_logic := '0'; -- detected an event with too many VFAT blocks (more than 4095 blocks!)
    signal err_event_bigger_than_24 : std_logic := '0'; -- there was an event which had more than 24 VFAT blocks
    signal err_vfat_block_too_small : std_logic := '0'; -- didn't get the full 14 VFAT words for some block
    signal err_vfat_block_too_big   : std_logic := '0'; -- got more than 14 VFAT words for one block
    signal err_mixed_vfat_bc        : std_logic := '0'; -- different VFAT BCs found in one event
    signal err_mixed_vfat_ec        : std_logic := '0'; -- different VFAT ECs found in one event
    signal err_mixed_oh_bc          : std_logic := '0'; -- different OH BCs found in one event

    -- Input FIFO
    signal infifo_din               : std_logic_vector(191 downto 0) := (others => '0');
    signal infifo_wr_en             : std_logic := '0';
    signal infifo_full              : std_logic := '0';
    signal infifo_almost_full       : std_logic := '0';
    signal infifo_empty             : std_logic := '0';
    signal infifo_underflow         : std_logic := '0';

    -- Event FIFO
    signal evtfifo_din              : std_logic_vector(59 downto 0) := (others => '0');
    signal evtfifo_wr_en            : std_logic := '0';
    signal evtfifo_full             : std_logic := '0';
    signal evtfifo_almost_full      : std_logic := '0';
    signal evtfifo_empty            : std_logic := '0';
    signal evtfifo_underflow        : std_logic := '0';

    -- Event processor
    signal ep_vfat_block_data       : std_logic_vector(223 downto 0) := (others => '0');
    signal ep_vfat_block_en         : std_logic := '0';
    signal ep_vfat_word             : integer range 0 to 14 := 14;
    signal ep_last_ec               : std_logic_vector(7 downto 0) := (others => '0');
    signal ep_last_bc               : std_logic_vector(11 downto 0) := (others => '0');
    signal ep_first_ever_block      : std_logic := '1'; -- it's the first ever event
    signal ep_end_of_event          : std_logic := '0';
    signal ep_last_rx_data          : std_logic_vector(223 downto 0) := (others => '0');
    signal ep_last_rx_data_valid    : std_logic := '0';
    signal ep_invalid_vfat_block    : std_logic := '0';
    
    -- Event builder
    signal eb_vfat_words_64         : unsigned(11 downto 0) := (others => '0');
    signal eb_vfat_bc               : std_logic_vector(11 downto 0) := (others => '0');
    signal eb_oh_bc                 : std_logic_vector(31 downto 0) := (others => '0');
    signal eb_vfat_ec               : std_logic_vector(7 downto 0) := (others => '0');
    signal eb_counters_valid        : std_logic := '0';
    signal eb_event_num             : unsigned(23 downto 0) := x"000001";
    signal eb_event_num_short       : unsigned(7 downto 0) := x"00"; -- used to double check with VFAT EC
    
    signal eb_invalid_vfat_block    : std_logic := '0';
    signal eb_event_too_big         : std_logic := '0';
    signal eb_event_bigger_than_24  : std_logic := '0';
    signal eb_mixed_vfat_bc         : std_logic := '0';
    signal eb_mixed_vfat_ec         : std_logic := '0';
    signal eb_mixed_oh_bc           : std_logic := '0';

    -- Event processor timeout
    signal eb_timer                 : unsigned(23 downto 0) := (others => '0');
    signal eb_timeout_delay         : unsigned(23 downto 0) := x"03d090"; -- 10ms (very large)
    signal eb_timeout_flag          : std_logic := '0';
    signal eb_last_timer            : unsigned(23 downto 0) := (others => '0');
    signal eb_max_timer             : unsigned(23 downto 0) := (others => '0');

    -- Debug flags for ChipScope
    attribute MARK_DEBUG : string;
    attribute MARK_DEBUG of tk_data_link_i              : signal is "TRUE";
    attribute MARK_DEBUG of eb_timer                    : signal is "TRUE";
    attribute MARK_DEBUG of eb_last_timer               : signal is "TRUE";
    attribute MARK_DEBUG of eb_max_timer                : signal is "TRUE";
    attribute MARK_DEBUG of eb_timeout_flag             : signal is "TRUE";
    attribute MARK_DEBUG of eb_invalid_vfat_block       : signal is "TRUE";
    attribute MARK_DEBUG of eb_vfat_words_64            : signal is "TRUE";
    attribute MARK_DEBUG of eb_vfat_bc                  : signal is "TRUE";
    attribute MARK_DEBUG of eb_oh_bc                    : signal is "TRUE";
    attribute MARK_DEBUG of eb_vfat_ec                  : signal is "TRUE";
    attribute MARK_DEBUG of eb_counters_valid           : signal is "TRUE";
    attribute MARK_DEBUG of eb_event_num_short          : signal is "TRUE";
    attribute MARK_DEBUG of ep_vfat_block_en            : signal is "TRUE";
    attribute MARK_DEBUG of ep_end_of_event             : signal is "TRUE";
    attribute MARK_DEBUG of ep_last_rx_data_valid       : signal is "TRUE";
    attribute MARK_DEBUG of tts_state                   : signal is "TRUE";
    
    attribute MARK_DEBUG of infifo_din                  : signal is "TRUE";
    attribute MARK_DEBUG of infifo_wr_en                : signal is "TRUE";
    attribute MARK_DEBUG of infifo_empty                : signal is "TRUE";

    attribute MARK_DEBUG of evtfifo_din                 : signal is "TRUE";
    attribute MARK_DEBUG of evtfifo_wr_en               : signal is "TRUE";
    attribute MARK_DEBUG of evtfifo_empty               : signal is "TRUE";
    
    attribute MARK_DEBUG of fifo_rd_clk_i               : signal is "TRUE";
    attribute MARK_DEBUG of infifo_rd_en_i              : signal is "TRUE";
    attribute MARK_DEBUG of evtfifo_rd_en_i             : signal is "TRUE";

begin

    --================================--
    -- TTS
    --================================--
    
    tts_critical_error <= err_event_too_big or 
                          err_evtfifo_full or 
                          err_evtfifo_underflow or 
                          err_infifo_full or
                          err_infifo_underflow;
                          
    tts_warning <= err_infifo_near_full or err_evtfifo_near_full;
    
    tts_out_of_sync <= '0'; -- No condition for now for setting OOS at the chamber event builder level (this will be used in AMC event builder)
    
    tts_busy <= reset_i; -- not used for now except for reset at this level
                          
    tts_state <= x"8" when (input_enable_i = '0') else
                 x"4" when (tts_busy = '1') else
                 x"c" when (tts_critical_error = '1') else
                 x"2" when (tts_out_of_sync = '1') else
                 x"1" when (tts_warning = '1') else
                 x"8";

    --================================--
    -- FIFOs
    --================================--
  
    -- Input FIFO
    daq_input_fifo_inst : entity work.daq_input_fifo
    PORT MAP (
        rst => reset_i,
        wr_clk => tk_data_link_i.clk,
        rd_clk => fifo_rd_clk_i,
        din => infifo_din,
        wr_en => infifo_wr_en,
        rd_en => infifo_rd_en_i,
        dout => infifo_dout_o,
        full => infifo_full,
        almost_full => infifo_almost_full,
        empty => infifo_empty,
        almost_empty => open,
        valid => infifo_valid_o,
        underflow => infifo_underflow,
        prog_full => err_infifo_near_full
    );

    infifo_empty_o <= infifo_empty;
    infifo_underflow_o <= infifo_underflow;

    -- Event FIFO
    daq_event_fifo_inst : entity work.daq_event_fifo
    PORT MAP (
        rst => reset_i,
        wr_clk => tk_data_link_i.clk,
        rd_clk => fifo_rd_clk_i,
        din => evtfifo_din,
        wr_en => evtfifo_wr_en,
        rd_en => evtfifo_rd_en_i,
        dout => evtfifo_dout_o,
        full => evtfifo_full,
        almost_full => evtfifo_almost_full,
        empty => evtfifo_empty,
        valid => evtfifo_valid_o,
        underflow => evtfifo_underflow,
        prog_full => err_evtfifo_near_full
    );

    evtfifo_empty_o <= evtfifo_empty;
    evtfifo_underflow_o <= evtfifo_underflow;

    -- Check for underflows
    process(fifo_rd_clk_i)
    begin
        if (rising_edge(fifo_rd_clk_i)) then
            if (reset_i = '1') then
                err_infifo_underflow <= '0';
                err_evtfifo_underflow <= '0';
            else
                if (evtfifo_underflow = '1') then
                    err_evtfifo_underflow <= '1';
                end if;
                if (infifo_underflow = '1') then
                    err_infifo_underflow <= '1';
                end if;
            end if;
        end if;
    end process;

    --================================--
    -- Glue input data into VFAT blocks
    --================================--
    -- TODO: this should be merged with Input Processor later
    process(tk_data_link_i.clk)
    begin
        if (rising_edge(tk_data_link_i.clk)) then
        
            if (reset_i = '1') then
                ep_vfat_block_data <= (others => '0');
                ep_vfat_block_en <= '0';
                ep_vfat_word <= 14;
                err_vfat_block_too_big <= '0';
                err_vfat_block_too_small <= '0';
            else
                if (tk_data_link_i.data_en = '1') then
                
                    -- receiving VFAT data
                    if (ep_vfat_word > 2) then
                        ep_vfat_block_data((((ep_vfat_word - 2) * 16) - 1) downto ((ep_vfat_word - 3) * 16)) <= tk_data_link_i.data;
                        ep_vfat_word <= ep_vfat_word - 1;
                    -- receiving OH BX data
                    elsif (ep_vfat_word > 0) then
                        ep_vfat_block_data((((ep_vfat_word + 12) * 16) - 1) downto ((ep_vfat_word + 11) * 16)) <= tk_data_link_i.data;
                        ep_vfat_word <= ep_vfat_word - 1;
                    -- still receiving data even though we expect that the block should have ended already
                    else
                        err_vfat_block_too_big <= '1';
                    end if;
                    
                    -- the last word
                    if (ep_vfat_word = 1) then
                        ep_vfat_block_en <= '1';
                    else
                        ep_vfat_block_en <= '0';
                    end if;
                    
                else

                    -- get ready to read a new block
                    ep_vfat_word <= 14;
                    ep_vfat_block_en <= '0';
                
                    -- if the strobe is off and the vfat word pointer is not at 0 and not at 14 it means that it didn't finish transmitting all 14 VFAT words - not good
                    if ((ep_vfat_word /= 0) and (ep_vfat_word /= 14)) then
                        err_vfat_block_too_small <= '1';
                    end if;
                                    
                end if;
                
            end if;
        end if;
    end process;
    

    --================================--
    -- Input processor
    --================================--
    
    process(tk_data_link_i.clk)
    begin
        if (rising_edge(tk_data_link_i.clk)) then

            if (reset_i = '1') then
                ep_last_rx_data <= (others => '0');
                ep_last_rx_data_valid <= '0';
                err_infifo_full <= '0';
                infifo_din <= (others => '0');
                infifo_wr_en <= '0';
                ep_end_of_event <= '0';
                err_corrupted_vfat_data <= '0';
                cnt_corrupted_vfat <= (others => '0');
                ep_invalid_vfat_block <= '0';
                ep_last_ec <= (others => '0');
                ep_last_bc <= (others => '0');
                ep_first_ever_block <= '1';
            else

                -- fill in last data
                ep_last_rx_data <= ep_vfat_block_data; -- TOTO Optimization: instead of duplicating all the data you could only retain the OH 32bits, others you can get form infifo_din
                ep_last_rx_data_valid <= ep_vfat_block_en;
            
                if (eb_timeout_flag = '1') then
                    ep_first_ever_block <= '1';
                end if;
                
                if ((ep_vfat_block_en = '1') and (reset_i = '0')) then
                
                    -- monitor the input FIFO
                    if (infifo_full = '1') then
                        err_infifo_full <= '1';
                    end if;
                    
                    -- push to input FIFO
                    if (infifo_full = '0') then
                        infifo_din <= ep_vfat_block_data(191 downto 0);
                        infifo_wr_en <= '1';
                    end if;
                    
                    -- invalid vfat block? if yes, then just attach it to current event
                    if ((ep_vfat_block_data(191 downto 144) and x"f000f000f000") /= vfat_block_marker) then
                        ep_invalid_vfat_block <= '1';
                        ep_end_of_event <= '0'; -- a corrupt block will never be an end of event - just attach it to current event
                        err_corrupted_vfat_data <= '1';
                        cnt_corrupted_vfat <= cnt_corrupted_vfat + 1;
                    else -- valid block
                        ep_invalid_vfat_block <= '0';
                        ep_last_ec <= ep_vfat_block_data(171 downto 164);
                        ep_last_bc <= ep_vfat_block_data(187 downto 176);
                        
                        if (ep_first_ever_block = '1') then
                            ep_first_ever_block <= '0';
                        end if;
                        
--                        if ((ep_first_ever_block = '0') and (ep_last_ec /= ep_vfat_block_data(171 downto 164))) then
-- for now checking for end of event using BC, but later should use an L1A counter or OH orbit counter + OH BC (on VFAT2 EC is reset with BC0, so we can't use that for now)
                        if ((ep_first_ever_block = '0') and (eb_timeout_flag = '0') and (ep_last_bc /= ep_vfat_block_data(187 downto 176))) then
                            ep_end_of_event <= '1';
                        else
                            ep_end_of_event <= '0';
                        end if;
                        
                    end if;
                    
                -- no data
                else
                    infifo_wr_en <= '0';
                end if;
                
            end if;
        end if;
    end process;    
    
    --================================--
    -- Event Builder
    --================================--
    process(tk_data_link_i.clk)
    begin
        if (rising_edge(tk_data_link_i.clk)) then
        
            if (reset_i = '1') then
                evtfifo_din <= (others => '0');
                evtfifo_wr_en <= '0';
                eb_invalid_vfat_block <= '0';
                eb_vfat_words_64 <= (others => '0');
                eb_vfat_bc <= (others => '0');
                eb_oh_bc <= (others => '0');
                eb_vfat_ec <= (others => '0');
                eb_counters_valid <= '0';
                eb_event_num <= (others => '0');
                eb_event_num_short <= (others => '0');
                eb_mixed_vfat_bc <= '0';
                err_mixed_vfat_bc <= '0';
                eb_mixed_vfat_ec <= '0';
                err_mixed_vfat_ec <= '0';
                eb_mixed_oh_bc <= '0';
                err_mixed_oh_bc <= '0';
                eb_event_too_big <= '0';
                err_event_too_big <= '0';
                eb_event_bigger_than_24 <= '0';
                err_event_bigger_than_24 <= '0';
                err_evtfifo_full <= '0';
                eb_timer <= (others => '0');
                eb_timeout_flag <= '0';
            else
                
                if (eb_timer >= eb_timeout_delay) then
                    eb_timeout_flag <= '1';                   
                end if;
                
                -- No data coming, but we do have data in the buffer, manage the timeout timer
                if ((ep_last_rx_data_valid = '0') and (eb_vfat_words_64 /= x"000") and (eb_timeout_flag = '0')) then
                    eb_timer <= eb_timer + 1;
                end if;
                
                -- Continuation of the current event - update flags and counters
                if ((ep_last_rx_data_valid = '1') and (ep_end_of_event = '0')) then
                
                    -- collect the timer stats and reset it along with the timeout flag
                    eb_last_timer <= eb_timer;
                    if (eb_timer > eb_max_timer) then
                        eb_max_timer <= eb_timer;
                    end if; 
                    eb_timer <= (others => '0');
                    eb_timeout_flag <= '0';
                
                    -- do not write to event fifo
                    evtfifo_wr_en <= '0';

                    -- is this block a valid VFAT block?
                    if (ep_invalid_vfat_block = '1') then
                        eb_invalid_vfat_block <= '1';
                    end if;
                    
                    -- increment the word counter if the counter is not full yet
                    if (eb_vfat_words_64 < x"fff") then
                        eb_vfat_words_64 <= eb_vfat_words_64 + 3;
                    else
                        eb_event_too_big <= '1';
                        err_event_too_big <= '1';
                    end if;
                    
                    -- do we have more than 24 VFAT blocks?
                    if (eb_vfat_words_64 > x"45") then
                        eb_event_bigger_than_24 <= '1';
                        err_event_bigger_than_24 <= '1';
                    end if;
                          
                    -- if we don't have valid bc, fill them in now (this is the case of first ever vfat block or after a timeout)
                    if (eb_counters_valid = '0') then
                        eb_vfat_bc <= ep_last_rx_data(187 downto 176);
                        eb_oh_bc <= ep_last_rx_data(223 downto 192);
                        eb_vfat_ec <= ep_last_rx_data(171 downto 164);
                        eb_counters_valid <= '1';
                    else -- we do have a valid bc
                        
                        -- is the current vfat bc different than the previous (in the same event)
                        if (eb_vfat_bc /= ep_last_rx_data(187 downto 176)) then
                            eb_mixed_vfat_bc <= '1';
                            err_mixed_vfat_bc <= '1';
                        end if;
                        
                        -- is the current OH bc different than the previous (in the same event)
                        if (eb_oh_bc /= ep_last_rx_data(223 downto 192)) then
                            eb_mixed_oh_bc <= '1';
                            err_mixed_oh_bc <= '1';
                        end if;
                        
                        -- is the current VFAT ec different than the previous (in the same event)
                        if (eb_vfat_ec /= ep_last_rx_data(171 downto 164)) then
                            eb_mixed_vfat_ec <= '1';
                            err_mixed_vfat_ec <= '1';
                        end if;
                        
                    end if;
                    
                -- End of event - push to event fifo, reset the flags and populate the new event ids (event num, bx, etc)
                elsif (((ep_last_rx_data_valid = '1') and (ep_end_of_event = '1')) or (eb_timeout_flag = '1')) then
                
                    -- Push to event FIFO
                    if (evtfifo_full = '0') then
                        evtfifo_wr_en <= '1';
                        evtfifo_din <= std_logic_vector(eb_event_num) & 
                                       eb_vfat_bc & 
                                       std_logic_vector(eb_vfat_words_64) & 
                                       evtfifo_almost_full & 
                                       err_evtfifo_full & 
                                       err_infifo_full & 
                                       err_evtfifo_near_full & 
                                       err_infifo_near_full & 
                                       err_infifo_underflow &
                                       eb_event_too_big &
                                       eb_invalid_vfat_block & 
                                       eb_event_bigger_than_24 &
                                       eb_mixed_oh_bc & 
                                       eb_mixed_vfat_bc & 
                                       eb_mixed_vfat_ec;
                    else
                        err_evtfifo_full <= '1';
                    end if;

                    if (eb_timeout_flag = '0') then
                        eb_vfat_bc <= ep_last_rx_data(187 downto 176);
                        eb_oh_bc <= ep_last_rx_data(223 downto 192);
                        eb_vfat_ec <= ep_last_rx_data(171 downto 164);
                        eb_counters_valid <= '1';
                        eb_vfat_words_64 <= x"003"; -- minimum number of VFAT blocks = 1 block (3 64bit words)
                    else
                        eb_counters_valid <= '0';
                        eb_vfat_words_64 <= x"000"; -- no data yet after timeout
                    end if;
                    
                    -- Increment the event number, set bx
                    eb_event_num <= eb_event_num + 1;
                    eb_event_num_short <= eb_event_num_short + 1;
                    
                    -- reset event flags
                    eb_invalid_vfat_block <= '0';
                    eb_mixed_vfat_bc <= '0';
                    eb_mixed_vfat_ec <= '0';
                    eb_mixed_oh_bc <= '0';
                    eb_event_too_big <= '0';
                    eb_event_bigger_than_24 <= '0';
                    
                    -- reset the timeout
                    eb_timeout_flag <= '0';
                    eb_timer <= (others => '0');

                else
                
                    -- hmm
                    evtfifo_wr_en <= '0';
                    
                end if;
                
            end if;
        end if;
    end process;

    --================================--
    -- Monitoring & Control
    --================================--

    --== FIFO current status and global flags ==--
    ipb_read_reg_data_o(0) <= evtfifo_empty &             -- Event FIFO
                              err_evtfifo_near_full &
                              evtfifo_full &
                              evtfifo_underflow &
                              infifo_empty &              -- Input FIFO
                              err_infifo_near_full &
                              infifo_full &
                              infifo_underflow &
                              x"00" &
                              tts_state &
                              err_event_too_big &          -- Critical
                              err_evtfifo_full &           -- Critical
                              err_infifo_underflow &       -- Critical
                              err_infifo_full &            -- Critical
                              err_corrupted_vfat_data &    -- Corruption
                              err_vfat_block_too_big &     -- Corruption
                              err_vfat_block_too_small &   -- Corruption
                              err_event_bigger_than_24 &   -- Corruption
                              err_mixed_oh_bc &            -- Mixed OH BC
                              err_mixed_vfat_bc &          -- Mixed VFAT BC
                              err_mixed_vfat_ec &          -- Mixed VFAT EC
                              "0";
                                
    --== Corrupted VFAT counter ==--    
    ipb_read_reg_data_o(1) <= std_logic_vector(cnt_corrupted_vfat);

    --== Current event builder event number ==--
    ipb_read_reg_data_o(2) <= x"00" & std_logic_vector(eb_event_num);
        
    --== Timeout delay ==--
    ipb_read_reg_data_o(3)(23 downto 0) <= std_logic_vector(eb_timeout_delay);
    eb_timeout_delay <= unsigned(ipb_write_reg_data_i(3)(23 downto 0));

    --== Timeout stats ==--
    ipb_read_reg_data_o(7)(23 downto 0) <= std_logic_vector(eb_max_timer);
    ipb_read_reg_data_o(8)(23 downto 0) <= std_logic_vector(eb_last_timer);
    
    --== Debug: last VFAT block ==--
    ipb_read_reg_data_o(9)  <= ep_vfat_block_data(31 downto 0);
    ipb_read_reg_data_o(10) <= ep_vfat_block_data(63 downto 32);
    ipb_read_reg_data_o(11) <= ep_vfat_block_data(95 downto 64);
    ipb_read_reg_data_o(12) <= ep_vfat_block_data(127 downto 96);
    ipb_read_reg_data_o(13) <= ep_vfat_block_data(159 downto 128);
    ipb_read_reg_data_o(14) <= ep_vfat_block_data(191 downto 160);
    ipb_read_reg_data_o(15) <= ep_vfat_block_data(223 downto 192);

end Behavioral;

