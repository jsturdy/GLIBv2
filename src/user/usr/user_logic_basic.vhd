library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

--! system packages
use work.system_flash_sram_package.all;
use work.system_pcie_package.all;
use work.system_package.all;
use work.fmc_package.all;
use work.wb_package.all;
use work.ipbus.all;

--! user packages
use work.user_package.all;
use work.user_version_package.all;

entity user_logic is
port(
    --================================--
    -- USER MGT REFCLKs
    --================================--
    -- BANK_112(Q0):  
    clk125_1_p                  : in std_logic;              
    clk125_1_n                  : in std_logic;            
    cdce_out0_p                 : in std_logic;            
    cdce_out0_n                 : in std_logic;           
    -- BANK_113(Q1):                 
    fmc2_clk0_m2c_xpoint2_p     : in std_logic;
    fmc2_clk0_m2c_xpoint2_n     : in std_logic;
    cdce_out1_p                 : in std_logic;       
    cdce_out1_n                 : in std_logic;         
    -- BANK_114(Q2):                 
    pcie_clk_p                  : in std_logic;               
    pcie_clk_n                  : in std_logic;              
    cdce_out2_p                 : in std_logic;              
    cdce_out2_n                 : in std_logic;              
    -- BANK_115(Q3):                 
    clk125_2_i                  : in std_logic;              
    fmc1_gbtclk1_m2c_p          : in std_logic;     
    fmc1_gbtclk1_m2c_n          : in std_logic;     
    -- BANK_116(Q4):                 
    fmc1_gbtclk0_m2c_p          : in std_logic;      
    fmc1_gbtclk0_m2c_n          : in std_logic;      
    cdce_out3_p                 : in std_logic;          
    cdce_out3_n                 : in std_logic;            
    --================================--
    -- USER FABRIC CLOCKS
    --================================--
    xpoint1_clk3_p              : in std_logic;           
    xpoint1_clk3_n              : in std_logic;           
    ------------------------------------  
    cdce_out4_p                 : in std_logic;                
    cdce_out4_n                 : in std_logic;              
    ------------------------------------
    amc_tclkb_o                 : out std_logic;
    ------------------------------------      
    fmc1_clk0_m2c_xpoint2_p     : in std_logic;
    fmc1_clk0_m2c_xpoint2_n     : in std_logic;
    fmc1_clk1_m2c_p             : in std_logic;    
    fmc1_clk1_m2c_n             : in std_logic;    
    fmc1_clk2_bidir_p           : in std_logic;    
    fmc1_clk2_bidir_n           : in std_logic;    
    fmc1_clk3_bidir_p           : in std_logic;    
    fmc1_clk3_bidir_n           : in std_logic;    
    ------------------------------------
    fmc2_clk1_m2c_p             : in std_logic;        
    fmc2_clk1_m2c_n             : in std_logic;        
    --================================--
    -- GBT PHASE MONITORING MGT REFCLK
    --================================--
    cdce_out0_gtxe1_o           : out std_logic;            
    cdce_out3_gtxe1_o           : out std_logic;  
    --================================--
    -- AMC PORTS
    --================================--
    amc_port_tx_p               : out std_logic_vector(1 to 15);
    amc_port_tx_n               : out std_logic_vector(1 to 15);
    amc_port_rx_p               : in std_logic_vector(1 to 15);
    amc_port_rx_n               : in std_logic_vector(1 to 15);
    ------------------------------------
    amc_port_tx_out             : out std_logic_vector(17 to 20);    
    amc_port_tx_in              : in std_logic_vector(17 to 20);        
    amc_port_tx_de              : out std_logic_vector(17 to 20);    
    amc_port_rx_out             : out std_logic_vector(17 to 20);    
    amc_port_rx_in              : in std_logic_vector(17 to 20);    
    amc_port_rx_de              : out std_logic_vector(17 to 20);    
    --================================--
    -- SFP QUAD
    --================================--
    sfp_tx_p                    : out std_logic_vector(1 to 4);
    sfp_tx_n                    : out std_logic_vector(1 to 4);
    sfp_rx_p                    : in std_logic_vector(1 to 4);
    sfp_rx_n                    : in std_logic_vector(1 to 4);
    sfp_mod_abs                 : in std_logic_vector(1 to 4);        
    sfp_rxlos                   : in std_logic_vector(1 to 4);        
    sfp_txfault                 : in std_logic_vector(1 to 4);                
    --================================--
    -- FMC1
    --================================--
    fmc1_tx_p                   : out std_logic_vector(1 to 4);
    fmc1_tx_n                   : out std_logic_vector(1 to 4);
    fmc1_rx_p                   : in std_logic_vector(1 to 4);
    fmc1_rx_n                   : in std_logic_vector(1 to 4);
    ------------------------------------
    fmc1_io_pin                 : inout fmc_io_pin_type;
    ------------------------------------
    fmc1_clk_c2m_p              : out std_logic_vector(0 to 1);
    fmc1_clk_c2m_n              : out std_logic_vector(0 to 1);
    fmc1_present_l              : in std_logic;
    --================================--
    -- FMC2
    --================================--
    fmc2_io_pin                 : inout fmc_io_pin_type;
    ------------------------------------
    fmc2_clk_c2m_p              : out std_logic_vector(0 to 1);
    fmc2_clk_c2m_n              : out std_logic_vector(0 to 1);
    fmc2_present_l              : in std_logic;
    --================================--      
    -- SYSTEM GBE   
    --================================--      
    sys_eth_amc_p1_tx_p         : in std_logic;    
    sys_eth_amc_p1_tx_n         : in std_logic;    
    sys_eth_amc_p1_rx_p         : out std_logic;    
    sys_eth_amc_p1_rx_n         : out std_logic;    
    ------------------------------------
    user_mac_syncacqstatus_i    : in std_logic_vector(0 to 3);
    user_mac_serdes_locked_i    : in std_logic_vector(0 to 3);
    --================================--                                           
    -- SYSTEM PCIe                                                                   
    --================================--   
    sys_pcie_mgt_refclk_o       : out std_logic;      
    user_sys_pcie_dma_clk_i     : in std_logic;      
    ------------------------------------
    sys_pcie_amc_tx_p           : in std_logic_vector(0 to 3);    
    sys_pcie_amc_tx_n           : in std_logic_vector(0 to 3);    
    sys_pcie_amc_rx_p           : out std_logic_vector(0 to 3);    
    sys_pcie_amc_rx_n           : out std_logic_vector(0 to 3);    
    ------------------------------------
    user_sys_pcie_slv_o         : out R_slv_to_ezdma2;                                           
    user_sys_pcie_slv_i         : in R_slv_from_ezdma2;                                    
    user_sys_pcie_dma_o         : out R_userDma_to_ezdma2_array  (1 to 7);                               
    user_sys_pcie_dma_i         : in R_userDma_from_ezdma2_array(1 to 7);               
    user_sys_pcie_int_o         : out R_int_to_ezdma2;                                           
    user_sys_pcie_int_i         : in R_int_from_ezdma2;                                     
    user_sys_pcie_cfg_i         : in R_cfg_from_ezdma2;                                        
    --================================--
    -- SRAMs
    --================================--
    user_sram_control_o         : out userSramControlR_array(1 to 2);
    user_sram_addr_o            : out array_2x21bit;
    user_sram_wdata_o           : out array_2x36bit;
    user_sram_rdata_i           : in array_2x36bit;
    ------------------------------------
    sram1_bwa                   : out std_logic;  
    sram1_bwb                   : out std_logic;  
    sram1_bwc                   : out std_logic;  
    sram1_bwd                   : out std_logic;  
    sram2_bwa                   : out std_logic;  
    sram2_bwb                   : out std_logic;  
    sram2_bwc                   : out std_logic;  
    sram2_bwd                   : out std_logic;    
    --================================--               
    -- CLK CIRCUITRY              
    --================================--    
    fpga_clkout_o               : out std_logic;    
    ------------------------------------
    sec_clk_o                   : out std_logic;    
    ------------------------------------
    user_cdce_locked_i          : in std_logic;
    user_cdce_sync_done_i       : in std_logic;
    user_cdce_sel_o             : out std_logic;
    user_cdce_sync_o            : out std_logic;
    --================================--  
    -- USER BUS  
    --================================--       
    wb_miso_o                   : out wb_miso_bus_array(0 to number_of_wb_slaves - 1);
    wb_mosi_i                   : in wb_mosi_bus_array(0 to number_of_wb_slaves - 1);
    ------------------------------------
    ipb_clk_i                   : in std_logic;
    ipb_miso_o                  : out ipb_rbus_array(0 to number_of_ipb_slaves - 1);
    ipb_mosi_i                  : in ipb_wbus_array(0 to number_of_ipb_slaves - 1);   
    --================================--
    -- VARIOUS
    --================================--
    reset_i                     : in std_logic;        
    user_clk125_i               : in std_logic;       
    user_clk200_i               : in std_logic;       
    ------------------------------------   
    sn                          : in std_logic_vector(7 downto 0);       
    ------------------------------------   
    amc_slot_i                  : in std_logic_vector( 3 downto 0);
    mac_addr_o                  : out std_logic_vector(47 downto 0);
    ip_addr_o                   : out std_logic_vector(31 downto 0);
    ------------------------------------    
    user_v6_led_o               : out std_logic_vector(1 to 2)
);                             
end user_logic;
                            
architecture user_logic_arch of user_logic is        

    --== GTX signals ==--
    
    signal gtx_usr_clk  : std_logic;
    signal gtx_tk_error : std_logic_vector(1 downto 0);
    signal gtx_tr_error : std_logic_vector(1 downto 0);
    signal gtx_evt_rcvd : std_logic_vector(1 downto 0);

    --== TTC signals ==--

    signal ttc_ready    : std_logic;
    signal ttc_clk      : std_logic;
    signal ttc_l1a      : std_logic;
    signal ttc_bc0      : std_logic;
    signal ttc_ec0      : std_logic;
    signal ttc_calpulse : std_logic;
    signal ttc_resync   : std_logic;
    
    signal ttc_bx_id    : std_logic_vector(11 downto 0);
    signal ttc_orbit_id : std_logic_vector(15 downto 0);
    signal ttc_l1a_id   : std_logic_vector(23 downto 0);
    
    signal vfat2_t1     : t1_t;
    
    --== IPBus buffer for counting ==--    
    
    signal ipb_miso     : ipb_rbus_array(0 to number_of_ipb_slaves - 1);
    
    --== DAQ signals ==--    
    
    signal tk_data_links        : data_link_array_t(0 to number_of_optohybrids - 1);
    signal trig_data_links      : trig_link_array_t(0 to number_of_optohybrids - 1);
    
    signal sbit_rate            : unsigned(31 downto 0) := (others => '0');
    
begin
    
    --==================--
    -- IP & MAC address --
    --==================--

    ip_addr_o <= x"c0a800a" & amc_slot_i;  -- 192.168.0.[160:175]
    mac_addr_o <= x"080030F100a" & amc_slot_i;  -- 08:00:30:F1:00:0[A0:AF] 
    
    --ip_addr_o <= x"898A73B9"; -- 137.138.115.185
    --mac_addr_o <= x"080030F100A1"; -- 08:00:30:F1:00:A1 

    
    ipb_miso_o <= ipb_miso;
    
    --=========--
    --== GTX ==--
    --=========--
    
	gtx_inst : entity work.gtx 
    port map(
		mgt_refclk_n_i  => cdce_out1_n,
		mgt_refclk_p_i  => cdce_out1_p,
        ipb_clk_i       => ipb_clk_i,
		reset_i         => reset_i,
        gtx_ipb_mosi_i  => ipb_mosi_i(ipb_gtx_forward_0 to ipb_gtx_forward_1),
        gtx_ipb_miso_o  => ipb_miso(ipb_gtx_forward_0 to ipb_gtx_forward_1), 
        evt_ipb_mosi_i  => ipb_mosi_i(ipb_evt_data_0 to ipb_evt_data_1),
        evt_ipb_miso_o  => ipb_miso(ipb_evt_data_0 to ipb_evt_data_1), 
        gtx_usr_clk_o   => gtx_usr_clk,
        tk_error_o      => gtx_tk_error,
        tr_error_o      => gtx_tr_error,
        evt_rcvd_o      => gtx_evt_rcvd,
        vfat2_t1_i      => vfat2_t1,
		rx_n_i          => sfp_rx_n(1 to 4),
		rx_p_i          => sfp_rx_p(1 to 4),
		tx_n_o          => sfp_tx_n(1 to 4),
		tx_p_o          => sfp_tx_p(1 to 4),
        tk_data_links_o => tk_data_links,
        trig_data_links_o => trig_data_links
	);
    
    --================================--
    -- TTC signal handling 	
    --================================--
    
    ttc_inst : entity work.ttc_wrapper
    port map(
        reset_i         => reset_i,
        ref_clk_i       => user_clk125_i,
        ttc_clk_p_i     => xpoint1_clk3_p,
        ttc_clk_n_i     => xpoint1_clk3_n,
        ttc_data_p_i    => amc_port_rx_p(3),
        ttc_data_n_i    => amc_port_rx_n(3),
        ttc_clk_o       => ttc_clk,
        ttc_ready_o     => ttc_ready,
        l1a_o           => ttc_l1a,
        bc0_o           => ttc_bc0,
        ec0_o           => ttc_ec0,
        oc0_o           => open,
        calpulse_o      => ttc_calpulse,
        start_o         => open,
        stop_o          => open,
        resync_o        => ttc_resync,
        hard_reset_o    => open,
        single_err_o    => open,
        double_err_o    => open,
        led_l1a_o       => user_v6_led_o(2),
        led_clk_bc0_o   => open, --user_v6_led_o(1),
        bx_id_o         => ttc_bx_id,
        orbit_id_o      => ttc_orbit_id,
        l1a_id_o        => ttc_l1a_id,

        -- IPbus
        ipb_clk_i       => ipb_clk_i,
        ipb_mosi_i      => ipb_mosi_i(ipb_ttc),
        ipb_miso_o      => ipb_miso(ipb_ttc)
        
    );    
    
    vfat2_t1.lv1a <= ttc_l1a;
    --vfat2_t1.resync <= ttc_resync;
    vfat2_t1.bc0 <= ttc_bc0;
    vfat2_t1.calpulse <= ttc_calpulse;
    
    fpga_clkout_o <= ttc_clk;
        
    --==========--
    --    DAQ   --
    --==========--
    
    daq : entity work.daq
    port map
    (
        -- Reset
        reset_i                     => reset_i,
        resync_i                    => ttc_resync,
        
        -- Clocks
        mgt_ref_clk125_i            => clk125_2_i,
        clk125_i                    => user_clk125_i,
        ipb_clk_i                   => ipb_clk_i,

        -- Pins
        daq_gtx_tx_pin_p            => amc_port_tx_p(1),
        daq_gtx_tx_pin_n            => amc_port_tx_n(1),
        daq_gtx_rx_pin_p            => amc_port_rx_p(1),
        daq_gtx_rx_pin_n            => amc_port_rx_n(1),

        -- TTC
        ttc_ready_i                 => ttc_ready,
        ttc_clk_i                   => ttc_clk,
        ttc_l1a_i                   => ttc_l1a,
        ttc_bc0_i                   => ttc_bc0,
        ttc_ec0_i                   => ttc_ec0,
        ttc_bx_id_i                 => ttc_bx_id,
        ttc_orbit_id_i              => ttc_orbit_id,
        ttc_l1a_id_i                => ttc_l1a_id,

        -- Track data
        tk_data_links_i             => tk_data_links,
        trig_data_links_i           => trig_data_links,
        sbit_rate_i                 => sbit_rate,
        
        -- IPbus
        ipb_mosi_i                  => ipb_mosi_i(ipb_daq),
        ipb_miso_o                  => ipb_miso(ipb_daq), 

        -- Other
        board_sn_i                  => sn
    );
    
    trigger: entity work.trigger
    port map
    (
        -- resets
        reset_i                     => reset_i,
        
        -- inputs
        trig_data_links_i           => trig_data_links,

        -- TTC
        ttc_clk_i                   => ttc_clk,
        ttc_l1a_i                   => ttc_l1a,

        -- Outputs
        trig_led_o                  => user_v6_led_o(1),
        
        -- IPbus
        ipb_clk_i                   => ipb_clk_i,
        ipb_mosi_i                  => ipb_mosi_i(ipb_trigger),
        ipb_miso_o                  => ipb_miso(ipb_trigger)
    );
    
    -- blink an LED whenever we have at least one valid SBit cluster
    -- also count the rate of the sbits
    process(tk_data_links(0).clk)
        variable sbit_led_countdown  : integer := 0;
        variable sbit_rate_countdown : integer := 0;
        variable valid_sbit : std_logic;
    begin
        if (rising_edge(tk_data_links(0).clk)) then
            
            -- find valid sbit signal
            if ((trig_data_links(0).data_en = '1') or (trig_data_links(1).data_en = '1')) then
                valid_sbit := (not (trig_data_links(0).data(9) and trig_data_links(0).data(10) and trig_data_links(0).data(23) and trig_data_links(0).data(24) and trig_data_links(0).data(37) and trig_data_links(0).data(38) and trig_data_links(0).data(51) and trig_data_links(0).data(52)))
                           or (not (trig_data_links(1).data(9) and trig_data_links(1).data(10) and trig_data_links(1).data(23) and trig_data_links(1).data(24) and trig_data_links(1).data(37) and trig_data_links(1).data(38) and trig_data_links(1).data(51) and trig_data_links(1).data(52)));
            else
                valid_sbit := '0';
            end if;
            
            -- LED countdown
            if (valid_sbit = '1') then
                sbit_led_countdown := 1_600_000;
            elsif (sbit_led_countdown > 0) then
                sbit_led_countdown := sbit_led_countdown - 1;
            else
                sbit_led_countdown := 0;
            end if;
            
            -- calculate the rate
            if (sbit_rate_countdown > 0) then
                if (valid_sbit = '1') then
                    sbit_rate <= sbit_rate + 1;
                end if;
                sbit_rate_countdown := sbit_rate_countdown - 1;
            else
                sbit_rate <= (others => '0');
                sbit_rate_countdown := 1_600_000_000;
            end if;
            
            -- led state
            if (sbit_led_countdown > 0) then
                user_v6_led_o(1) <= '1';
            else
                user_v6_led_o(1) <= '0';
            end if;            
            
        end if;
    end process;

    --==========--
    -- Counters --
    --==========--
    
	ipbus_counters_inst : entity work.ipbus_counters 
    port map(
		ipb_clk_i       => ipb_clk_i,
		gtx_clk_i       => gtx_usr_clk,
		ttc_clk_i       => ttc_clk,
		reset_i         => reset_i,
		ipb_mosi_i      => ipb_mosi_i(ipb_counters),
		ipb_miso_o      => ipb_miso(ipb_counters),
		ipb_i           => ipb_mosi_i,
		ipb_o           => ipb_miso,
		vfat2_t1_i      => vfat2_t1,
		gtx_tk_error_i  => gtx_tk_error,
		gtx_tr_error_i  => gtx_tr_error,
        gtx_evt_rcvd_i  => gtx_evt_rcvd
	);
    
end user_logic_arch;
