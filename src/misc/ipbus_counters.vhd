----------------------------------------------------------------------------------
-- Company:        IIHE - ULB
-- Engineer:       Thomas Lenzi (thomas.lenzi@cern.ch)
-- 
-- Create Date:    08:37:33 07/07/2015 
-- Design Name:    GLIB v2
-- Module Name:    ipbus_counters - Behavioral 
-- Project Name:   GLIB v2
-- Target Devices: xc6vlx130t-1ff1156
-- Tool versions:  ISE  P.20131013
-- Description: 
--
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.ipbus.all;
use work.system_package.all;
use work.user_package.all;

entity ipbus_counters is
port(

	ipb_clk_i       : in std_logic;
	gtx_clk_i       : in std_logic;
    ttc_clk_i       : in std_logic;
	reset_i         : in std_logic;
    
	ipb_mosi_i      : in ipb_wbus;
	ipb_miso_o      : out ipb_rbus;
    
    ipb_i           : in ipb_wbus_array(0 to number_of_ipb_slaves - 1);
    ipb_o           : in ipb_rbus_array(0 to number_of_ipb_slaves - 1);
    
    vfat2_t1_i      : in t1_t;
    
    gtx_tk_error_i  : in std_logic_vector(1 downto 0);
    gtx_tr_error_i  : in std_logic_vector(1 downto 0)
    
);
end ipbus_counters;

architecture Behavioral of ipbus_counters is
      
    signal last_ipb_stobe   : std_logic;
    signal reg_sel          : integer range 0 to 31;
    
    signal reg_reset        : std_logic_vector(31 downto 0);
    signal reg_data         : std32_array_t(31 downto 0);
    
    signal last_strobes     : std_logic_vector(4 downto 0);
    signal last_acks        : std_logic_vector(4 downto 0);
    
begin

	reg_sel <= to_integer(unsigned(ipb_mosi_i.ipb_addr(4 downto 0)));

    --== Read process ==--

    process(ipb_clk_i)       
    begin    
        if (rising_edge(ipb_clk_i)) then      
            if (reset_i = '1') then    
                ipb_miso_o <= (ipb_ack => '0', ipb_err => '0', ipb_rdata => (others => '0'));                 
                last_ipb_stobe <= '0';               
                reg_reset <= (others => '0');           
            else         
                ipb_miso_o <= (ipb_ack => ((not last_ipb_stobe) and ipb_mosi_i.ipb_strobe), ipb_err => '0', ipb_rdata => reg_data(reg_sel));
                reg_reset(reg_sel) <= ipb_mosi_i.ipb_write and ((not last_ipb_stobe) and ipb_mosi_i.ipb_strobe);
                last_ipb_stobe <= ipb_mosi_i.ipb_strobe;    
            end if;        
        end if;        
    end process;
    
    --== Allows for strobe & ack counting ==--
    
    process(ipb_clk_i)       
    begin    
        if (rising_edge(ipb_clk_i)) then      
            if (reset_i = '1') then             
                last_strobes <= (others => '0');           
            else         
                for I in 0 to 4 loop
                    last_strobes(I) <= ipb_i(I).ipb_strobe;    
                    last_acks(I) <= ipb_o(I).ipb_ack;    
                end loop;
            end if;        
        end if;        
    end process;

    --== List of counters ==--
    
    -- 0 - 9 : IPBus strobes and acknowledgments
    
    ipb_counters_loop : for I in 0 to 4 generate
    begin
    
        ipb_counters_strobe_inst : entity work.counter port map(ref_clk_i => ipb_clk_i, reset_i => reg_reset(I), en_i => ((not last_strobes(I)) and ipb_i(I).ipb_strobe), data_o => reg_data(I));
        
        ipb_counters_ack_inst : entity work.counter port map(ref_clk_i => ipb_clk_i, reset_i => reg_reset(I + 5), en_i => ((not last_acks(I)) and ipb_o(I).ipb_ack), data_o => reg_data(I + 5));

    end generate;
    
    -- 10 - 13 : T1 counters
    
    lv1a_cnt_inst : entity work.counter port map(ref_clk_i => ttc_clk_i, reset_i => reg_reset(10), en_i => vfat2_t1_i.lv1a, data_o => reg_data(10));
    
    calpulse_cnt_inst : entity work.counter port map(ref_clk_i => ttc_clk_i, reset_i => reg_reset(11), en_i => vfat2_t1_i.calpulse, data_o => reg_data(11));
    
    resync_cnt_inst : entity work.counter port map(ref_clk_i => ttc_clk_i, reset_i => reg_reset(12), en_i => vfat2_t1_i.resync, data_o => reg_data(12));
    
    bc0_cnt_inst : entity work.counter port map(ref_clk_i => ttc_clk_i, reset_i => reg_reset(13), en_i => vfat2_t1_i.bc0, data_o => reg_data(13));
    
    -- 14 - 17 : GTX tracking & trigger errors
    
    gtx_tk_0_error_cnt_inst : entity work.counter port map(ref_clk_i => gtx_clk_i, reset_i => reg_reset(14), en_i => gtx_tk_error_i(0), data_o => reg_data(14));
    
    gtx_tk_1_error_cnt_inst : entity work.counter port map(ref_clk_i => gtx_clk_i, reset_i => reg_reset(15), en_i => gtx_tk_error_i(1), data_o => reg_data(15));
    
    gtx_tr_0_error_cnt_inst : entity work.counter port map(ref_clk_i => gtx_clk_i, reset_i => reg_reset(16), en_i => gtx_tr_error_i(0), data_o => reg_data(16));
    
    gtx_tr_1_error_cnt_inst : entity work.counter port map(ref_clk_i => gtx_clk_i, reset_i => reg_reset(17), en_i => gtx_tr_error_i(1), data_o => reg_data(17));

end Behavioral;