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
    
	gtx_ipb_mosi_i  : in ipb_wbus_array(0 to number_of_optohybrids - 1);
	gtx_ipb_miso_o  : out ipb_rbus_array(0 to number_of_optohybrids - 1);
    
	evt_ipb_mosi_i  : in ipb_wbus_array(0 to number_of_optohybrids - 1);
	evt_ipb_miso_o  : out ipb_rbus_array(0 to number_of_optohybrids - 1);
    
    vfat2_t1_i      : in t1_t;
    
    gtx_usr_clk_o   : out std_logic;
    tk_error_o      : out std_logic_vector(number_of_optohybrids - 1 downto 0);
    tr_error_o      : out std_logic_vector(number_of_optohybrids - 1 downto 0);
    evt_rcvd_o      : out std_logic_vector(number_of_optohybrids - 1 downto 0);
    
    tk_data_links_o : out data_link_array_t(0 to number_of_optohybrids - 1);
    trig_data_links_o: out trig_link_array_t(0 to number_of_optohybrids - 1);
   
    rx_n_i          : in std_logic_vector(3 downto 0);
    rx_p_i          : in std_logic_vector(3 downto 0);
    tx_n_o          : out std_logic_vector(3 downto 0);
    tx_p_o          : out std_logic_vector(3 downto 0)
    
);
end gtx;

architecture Behavioral of gtx is      

    --== GTX signals ==--

    signal tx_kchar     : std_logic_vector(7 downto 0);
    signal tx_data      : std_logic_vector(63 downto 0);
    
    signal rx_kchar     : std_logic_vector(7 downto 0);
    signal rx_data      : std_logic_vector(63 downto 0);
    signal rx_error     : std_logic_vector(3 downto 0);
 
    signal gtx_usr_clk  : std_logic;
    
    --== Chipscope signals ==--
    
    signal cs_ctrl0     : std_logic_vector(35 downto 0);
    signal cs_ctrl1     : std_logic_vector(35 downto 0); 
    signal cs_async_out : std_logic_vector(7 downto 0);
    signal cs_trig0     : std_logic_vector(127 downto 0);
    
begin    
    
    --=================--
    --== GTX wrapper ==--
    --=================--
    
    gtx_usr_clk_o <= gtx_usr_clk;
    
	gtx_wrapper_inst : entity work.gtx_wrapper 
    port map(
		mgt_refclk_n_i  => mgt_refclk_n_i,
		mgt_refclk_p_i  => mgt_refclk_p_i,
        ref_clk_i       => ipb_clk_i,
		reset_i         => cs_async_out(0),
		tx_kchar_i      => tx_kchar,
		tx_data_i       => tx_data,
		rx_kchar_o      => rx_kchar,
		rx_data_o       => rx_data,
		rx_error_o      => rx_error,
		usr_clk_o       => gtx_usr_clk,
		rx_n_i          => rx_n_i(3 downto 0),
		rx_p_i          => rx_p_i(3 downto 0),
		tx_n_o          => tx_n_o(3 downto 0),
		tx_p_o          => tx_p_o(3 downto 0)
	);  
   
    --================--
    --== OptoHybrid ==--
    --================--
    
    gtx_optohybrid_loop : for I in 0 to (number_of_optohybrids - 1) generate
    begin
    
        gtx_optohybrid_inst : entity work.gtx_optohybrid
        port map(
            gtx_usr_clk_i   => gtx_usr_clk,
            ipb_clk_i       => ipb_clk_i,    
            reset_i         => reset_i,    
            gtx_ipb_mosi_i  => gtx_ipb_mosi_i(I),
            gtx_ipb_miso_o  => gtx_ipb_miso_o(I),    
            evt_ipb_mosi_i  => evt_ipb_mosi_i(I),
            evt_ipb_miso_o  => evt_ipb_miso_o(I),     
            vfat2_t1_i      => vfat2_t1_i,    
            tk_error_o      => tk_error_o(I),
            tr_error_o      => tr_error_o(I),    
            evt_rcvd_o      => evt_rcvd_o(I),    
            tx_kchar_o      => tx_kchar((4 * I + 3) downto (4 * I)),
            tx_data_o       => tx_data((32 * I + 31) downto (32 * I)),    
            rx_kchar_i      => rx_kchar((4 * I + 3) downto (4 * I)),
            rx_data_i       => rx_data((32 * I + 31) downto (32 * I)),
            tk_data_link_o  => tk_data_links_o(I),
            trig_data_link_o=> trig_data_links_o(I)
        );
    
    end generate;
    
    --===============--
    --== ChipScope ==--
    --===============--
    
--    chipscope_icon_inst : entity work.chipscope_icon
--    port map(
--        control0    => cs_ctrl0,
--        control1    => cs_ctrl1
--    );
--    
--    chipscope_vio_inst : entity work.chipscope_vio
--    port map(
--        control     => cs_ctrl0,
--        async_out   => cs_async_out
--    );
--    
--    chipscope_ila_inst : entity work.chipscope_ila
--    port map(
--        control => cs_ctrl1,
--        clk     => gtx_usr_clk,
--        trig0   => cs_trig0
--    );
--    
--    cs_trig0 <= tx_data & rx_data;

end Behavioral;
