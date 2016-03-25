----------------------------------------------------------------------------------
-- Company:        IIHE - ULB
-- Engineer:       Thomas Lenzi (thomas.lenzi@cern.ch)
-- 
-- Create Date:    08:37:33 07/07/2015 
-- Design Name:    GLIB v2
-- Module Name:    gtx_optohybrid - Behavioral 
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
use work.ipbus.all;
use work.system_package.all;
use work.user_package.all;

entity gtx_optohybrid is
port(

    gtx_usr_clk_i   : in std_logic;
    ipb_clk_i       : in std_logic;
    
    reset_i         : in std_logic;
    
	gtx_ipb_mosi_i  : in ipb_wbus;
	gtx_ipb_miso_o  : out ipb_rbus;
    
	evt_ipb_mosi_i  : in ipb_wbus;
	evt_ipb_miso_o  : out ipb_rbus;
    
    vfat2_t1_i      : in t1_t;
    
    tk_error_o      : out std_logic;
    tr_error_o      : out std_logic;
    evt_rcvd_o      : out std_logic;
    
    tx_kchar_o      : out std_logic_vector(3 downto 0);
    tx_data_o       : out std_logic_vector(31 downto 0);
    
    rx_kchar_i      : in std_logic_vector(3 downto 0);
    rx_data_i       : in std_logic_vector(31 downto 0);

    tk_data_link_o  : out data_link_t;
    trig_data_link_o: out trig_link_t
    
);
end gtx_optohybrid;

architecture Behavioral of gtx_optohybrid is      
    
    --== GTX requests ==--
    
    signal g2o_req_en       : std_logic;
    signal g2o_req_valid    : std_logic;
    signal g2o_req_data     : std_logic_vector(64 downto 0);
    
    signal o2g_req_en       : std_logic;
    signal o2g_req_data     : std_logic_vector(31 downto 0);
    signal o2g_req_error    : std_logic;    
    
    --== Tracking data ==--
    
    signal evt_en           : std_logic;
    signal evt_data         : std_logic_vector(15 downto 0);
    
begin  
        
    --==========================--
    --== SFP TX Trigger link ==--
    --==========================--
       
    link_tx_trigger_inst : entity work.link_tx_trigger
    port map(
        gtx_clk_i   => gtx_usr_clk_i,   
        reset_i     => reset_i,           
        vfat2_t1_i  => vfat2_t1_i,          
        tx_kchar_o  => tx_kchar_o(3 downto 2),   
        tx_data_o   => tx_data_o(31 downto 16)        
    );  
    
    --=========================--
    --== SFP RX Trigger Link ==--
    --=========================--
    
    link_rx_trigger_inst : entity work.link_rx_trigger
    port map(
        gtx_clk_i           => gtx_usr_clk_i,   
        reset_i             => reset_i,  
        tr_error_o          => tr_error_o,        
        rx_kchar_i          => rx_kchar_i(3 downto 2),   
        rx_data_i           => rx_data_i(31 downto 16),
        clusters_data_o     => trig_data_link_o.data,
        clusters_valid_o    => trig_data_link_o.data_en
    );
    
    --==========================--
    --== SFP TX Tracking link ==--
    --==========================--
       
    link_tx_tracking_inst : entity work.link_tx_tracking
    port map(
        gtx_clk_i   => gtx_usr_clk_i,   
        reset_i     => reset_i,           
        vfat2_t1_i  => vfat2_t1_i,        
        req_en_o    => g2o_req_en,   
        req_valid_i => g2o_req_valid,   
        req_data_i  => g2o_req_data,           
        tx_kchar_o  => tx_kchar_o(1 downto 0),   
        tx_data_o   => tx_data_o(15 downto 0)        
    );  
    
    --==========================--
    --== SFP RX Tracking link ==--
    --==========================--

    tk_data_link_o.clk <= gtx_usr_clk_i;
    tk_data_link_o.data_en <= evt_en;
    tk_data_link_o.data <= evt_data;
       
    link_rx_tracking_inst : entity work.link_rx_tracking
    port map(
        gtx_clk_i   => gtx_usr_clk_i,   
        reset_i     => reset_i,           
        req_en_o    => o2g_req_en,   
        req_data_o  => o2g_req_data,   
        evt_en_o    => evt_en,
        evt_data_o  => evt_data,
        tk_error_o  => tk_error_o,
        evt_rcvd_o  => evt_rcvd_o,
        rx_kchar_i  => rx_kchar_i(1 downto 0),   
        rx_data_i   => rx_data_i(15 downto 0)        
    );
    
    --============================--
    --== GTX request forwarding ==--
    --============================--
    
    link_request_inst : entity work.link_request
    port map(
        ipb_clk_i   => ipb_clk_i,
        gtx_clk_i   => gtx_usr_clk_i,
        reset_i     => reset_i,        
        ipb_mosi_i  => gtx_ipb_mosi_i,
        ipb_miso_o  => gtx_ipb_miso_o,        
        tx_en_i     => g2o_req_en,
        tx_valid_o  => g2o_req_valid,
        tx_data_o   => g2o_req_data,        
        rx_en_i     => o2g_req_en,
        rx_data_i   => o2g_req_data        
    ); 

    --================================--
    --== Tracking data buffer IPBus ==--
    --================================--
    
	link_tkdata_inst : entity work.link_tkdata 
    port map(
		ipb_clk_i   => ipb_clk_i,
		gtx_clk_i   => gtx_usr_clk_i,
		reset_i     => reset_i,
		ipb_mosi_i  => evt_ipb_mosi_i,
		ipb_miso_o  => evt_ipb_miso_o,
		evt_en_i    => evt_en,
		evt_data_i  => evt_data
	);
 
end Behavioral;
