----------------------------------------------------------------------------------
-- Company:        IIHE - ULB
-- Engineer:       Thomas Lenzi (thomas.lenzi@cern.ch)
-- 
-- Create Date:    08:37:33 07/07/2015 
-- Design Name:    GLIB v2
-- Module Name:    gtx - Behavioral 
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

entity gtx is
port(

    mgt_refclk_n_i  : in std_logic;
    mgt_refclk_p_i  : in std_logic;
    
    ipb_clk_i       : in std_logic;
    
    reset_i         : in std_logic;
    
	ipb_mosi_i      : in ipb_wbus;
	ipb_miso_o      : out ipb_rbus;
   
    rx_n_i          : in std_logic_vector(3 downto 0);
    rx_p_i          : in std_logic_vector(3 downto 0);
    tx_n_o          : out std_logic_vector(3 downto 0);
    tx_p_o          : out std_logic_vector(3 downto 0)
    
);
end gtx;

architecture Behavioral of gtx is      

    --== GTX signals ==--

    signal gtx_tx_kchar     : std_logic_vector(7 downto 0);
    signal gtx_tx_data      : std_logic_vector(63 downto 0);
    
    signal gtx_rx_kchar     : std_logic_vector(7 downto 0);
    signal gtx_rx_data      : std_logic_vector(63 downto 0);
    signal gtx_rx_error     : std_logic_vector(3 downto 0);
 
    signal gtx_usr_clk      : std_logic;
    
    --== GTX requests ==--
    
    signal fwd_req_en       : std_logic;
    signal fwd_req_valid    : std_logic;
    signal fwd_req_data     : std_logic_vector(64 downto 0);
    
    signal fwd_res_en       : std_logic;
    signal fwd_res_data     : std_logic_vector(31 downto 0);
    
    --== Chipscope signals ==--
    
    signal cs_ctrl0         : std_logic_vector(35 downto 0);
    signal cs_ctrl1         : std_logic_vector(35 downto 0); 
    signal cs_async_out     : std_logic_vector(7 downto 0);
    signal cs_trig0         : std_logic_vector(31 downto 0);
    signal cs_trig1         : std_logic_vector(31 downto 0);
    
begin    
    
    --=================--
    --== GTX wrapper ==--
    --=================--
    
	gtx_wrapper_inst : entity work.gtx_wrapper 
    port map(
		mgt_refclk_n_i  => mgt_refclk_n_i,
		mgt_refclk_p_i  => mgt_refclk_p_i,
		reset_i         => reset_i,
		tx_kchar_i      => gtx_tx_kchar,
		tx_data_i       => gtx_tx_data,
		rx_kchar_o      => gtx_rx_kchar,
		rx_data_o       => gtx_rx_data,
		rx_error_o      => gtx_rx_error,
		usr_clk_o       => gtx_usr_clk,
		rx_n_i          => rx_n_i(3 downto 0),
		rx_p_i          => rx_p_i(3 downto 0),
		tx_n_o          => tx_n_o(3 downto 0),
		tx_p_o          => tx_p_o(3 downto 0)
	);   
    
    --==========================--
    --== SFP TX Tracking link ==--
    --==========================--
       
    gtx_tx_tracking_inst : entity work.gtx_tx_tracking
    port map(
        gtx_clk_i   => gtx_usr_clk,   
        reset_i     => reset_i,           
        req_en_o    => fwd_req_en,   
        req_valid_i => fwd_req_valid,   
        req_data_i  => fwd_req_data,           
        tx_kchar_o  => gtx_tx_kchar(1 downto 0),   
        tx_data_o   => gtx_tx_data(15 downto 0)        
    );  
    
    --==========================--
    --== SFP RX Tracking link ==--
    --==========================--
       
    gtx_rx_tracking_inst : entity work.gtx_rx_tracking
    port map(
        gtx_clk_i   => gtx_usr_clk,   
        reset_i     => reset_i,           
        req_en_o    => fwd_res_en,   
        req_data_o  => fwd_res_data,           
        rx_kchar_i  => gtx_rx_kchar(1 downto 0),   
        rx_data_i   => gtx_rx_data(15 downto 0)        
    );
    
    --============================--
    --== GTX request forwarding ==--
    --============================--
    
    gtx_forward_inst : entity work.gtx_forward
    port map(
        ipb_clk_i   => ipb_clk_i,
        gtx_clk_i   => gtx_usr_clk,
        reset_i     => reset_i,        
        ipb_mosi_i  => ipb_mosi_i,
        ipb_miso_o  => ipb_miso_o,        
        tx_en_i     => fwd_req_en,
        tx_valid_o  => fwd_req_valid,
        tx_data_o   => fwd_req_data,        
        rx_en_i     => fwd_res_en,
        rx_data_i   => fwd_res_data        
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
        clk     => gtx_usr_clk,
        trig0   => cs_trig0,
        trig1   => cs_trig1
    );
    
    cs_trig0 <= gtx_rx_data(15 downto 0) & gtx_tx_data(15 downto 0);
    cs_trig1(4 downto 0) <= (
        0 => ipb_mosi_i.ipb_strobe, 
        1 => fwd_req_en,
        2 => fwd_req_valid, 
        3 => fwd_res_en,
        4 => '0'
    );
    cs_trig1(8 downto 5) <= fwd_req_data(3 downto 0);
    cs_trig1(12 downto 9) <= fwd_res_data(3 downto 0);
    cs_trig1(31 downto 13) <= (others => '0');
end Behavioral;
