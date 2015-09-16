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

    --== SFP GTX signals ==--

    signal sfp_tx_kchar : std_logic_vector(3 downto 0);
    signal sfp_tx_data  : std_logic_vector(31 downto 0);
    
    signal sfp_rx_kchar : std_logic_vector(3 downto 0);
    signal sfp_rx_data  : std_logic_vector(31 downto 0);
    signal sfp_rx_error : std_logic_vector(1 downto 0);
 
    signal sfp_usr_clk  : std_logic;
    
    --== OptoHybrid ==--
    
    signal oh_req_en    : std_logic;
    signal oh_req_ack   : std_logic;
    signal oh_req_data  : std_logic_vector(64 downto 0);
    
    --== Chipscope signals ==--
    
    signal cs_ctrl0     : std_logic_vector(35 downto 0);
    signal cs_ctrl1     : std_logic_vector(35 downto 0); 
    signal cs_async_out : std_logic_vector(7 downto 0);
    signal cs_trig0     : std_logic_vector(31 downto 0);
    signal cs_trig1     : std_logic_vector(31 downto 0);
              
begin
    
    --==================--
    -- IP & MAC address --
    --==================--

    ip_addr_o <= x"c0a800a" & amc_slot_i;  -- 192.168.0.[160:175]
    mac_addr_o <= x"080030F100a" & amc_slot_i;  -- 08:00:30:F1:00:0[A0:AF] 

    user_v6_led_o <= "10";
    
    --=============--
    --== SFP GTX ==--
    --=============--
    
	sfp_gtx_wrapper_inst : entity work.sfp_gtx_wrapper 
    port map(
		mgt_refclk_n_i  => cdce_out1_n,
		mgt_refclk_p_i  => cdce_out1_p,
		reset_i         => '0',
		tx_kchar_i      => sfp_tx_kchar,
		tx_data_i       => sfp_tx_data,
		rx_kchar_o      => sfp_rx_kchar,
		rx_data_o       => sfp_rx_data,
		rx_error_o      => sfp_rx_error,
		usr_clk_o       => sfp_usr_clk,
		rx_n_i          => sfp_rx_n(1 to 2),
		rx_p_i          => sfp_rx_p(1 to 2),
		tx_n_o          => sfp_tx_n(1 to 2),
		tx_p_o          => sfp_tx_p(1 to 2)
	);    
    
    sfp_gtx_tx_tracking_inst : entity work.sfp_gtx_tx_tracking
    port map(
        ref_clk_i   => sfp_usr_clk,   
        reset_i     => reset_i,           
        req_en_i    => oh_req_en,   
        req_ack_o   => oh_req_ack,   
        req_data_i  => oh_req_data,           
        tx_kchar_o  => sfp_tx_kchar(1 downto 0),   
        tx_data_o   => sfp_tx_data(15 downto 0)        
    );
    
    --================--
    --== OptoHybrid ==--
    --================--
    
    oh_forward_inst : entity work.oh_forward
    port map(
        ipb_clk_i   => ipb_clk_i,
        gtx_clk_i   => sfp_usr_clk,
        reset_i     => reset_i,        
        ipb_mosi_i  => ipb_mosi_i(ipb_oh_forward),
        ipb_miso_o  => ipb_miso_o(ipb_oh_forward),        
        tx_en_o     => oh_req_en,
        tx_ack_i    => oh_req_ack,
        tx_data_o   => oh_req_data,        
        rx_en_i     => '0',
        rx_ack_o    => open,
        rx_data_i   => (others => '0')        
    );

    --===============--
    --== ChipScope ==--
    --===============--
    
    chipscope_icon_inst : entity work.chipscope_icon
    port map(
        control0    => cs_ctrl0,
        control1    => cs_ctrl1
    );
    
    chipscope_vio_inst : entity work.chipscope_vio
    port map(
        control     => cs_ctrl0,
        async_out   => cs_async_out
    );
    
    chipscope_ila_inst : entity work.chipscope_ila
    port map(
        control => cs_ctrl1,
        clk     => sfp_usr_clk,
        trig0   => cs_trig0,
        trig1   => cs_trig1
    );
    
    cs_trig0 <= sfp_rx_data(15 downto 0) & sfp_tx_data(15 downto 0);
    cs_trig1 <= (
        0 => ipb_mosi_i(ipb_oh_forward).ipb_strobe, 
        1 => oh_req_en,
        2 => oh_req_ack, 
        others => '0'
    );
    
end user_logic_arch;