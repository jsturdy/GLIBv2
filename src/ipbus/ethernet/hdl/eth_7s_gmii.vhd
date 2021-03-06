-- Contains the instantiation of the Xilinx MAC IP plus the GMII PHY interface
--
-- Do not change signal names in here without corresponding alteration to the timing contraints file
--
-- Dave Newbold, April 2011
--
-- $Id$

library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.VComponents.all;

use work.emac_hostbus_decl.all;

entity eth_7s_gmii is
	port(
		clk125: in std_logic;
		clk200: in std_logic;
		rst: in std_logic;
		gmii_gtx_clk: out std_logic;
		gmii_txd: out std_logic_vector(7 downto 0);
		gmii_tx_en: out std_logic;
		gmii_tx_er: out std_logic;
		gmii_rx_clk: in std_logic;
		gmii_rxd: in std_logic_vector(7 downto 0);
		gmii_rx_dv: in std_logic;
		gmii_rx_er: in std_logic;
		tx_data: in std_logic_vector(7 downto 0);
		tx_valid: in std_logic;
		tx_last: in std_logic;
		tx_error: in std_logic;
		tx_ready: out std_logic;
		rx_data: out std_logic_vector(7 downto 0);
		rx_valid: out std_logic;
		rx_last: out std_logic;
		rx_error: out std_logic;
		hostbus_in: in emac_hostbus_in := ('0', "00", "0000000000", X"00000000", '0', '0', '0');
		hostbus_out: out emac_hostbus_out
	);

end eth_7s_gmii;

architecture rtl of eth_7s_gmii is

	COMPONENT tri_mode_eth_mac_v5_4
	  PORT (
		 glbl_rstn : IN STD_LOGIC;
		 rx_axi_rstn : IN STD_LOGIC;
		 tx_axi_rstn : IN STD_LOGIC;
		 rx_axi_clk : IN STD_LOGIC;
		 rx_reset_out : OUT STD_LOGIC;
		 rx_axis_mac_tdata : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		 rx_axis_mac_tvalid : OUT STD_LOGIC;
		 rx_axis_mac_tlast : OUT STD_LOGIC;
		 rx_axis_mac_tuser : OUT STD_LOGIC;
		 rx_statistics_vector : OUT STD_LOGIC_VECTOR(27 DOWNTO 0);
		 rx_statistics_valid : OUT STD_LOGIC;
		 tx_axi_clk : IN STD_LOGIC;
		 tx_reset_out : OUT STD_LOGIC;
		 tx_axis_mac_tdata : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		 tx_axis_mac_tvalid : IN STD_LOGIC;
		 tx_axis_mac_tlast : IN STD_LOGIC;
		 tx_axis_mac_tuser : IN STD_LOGIC;
		 tx_axis_mac_tready : OUT STD_LOGIC;
		 tx_ifg_delay : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		 tx_statistics_vector : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
		 tx_statistics_valid : OUT STD_LOGIC;
		 pause_req : IN STD_LOGIC;
		 pause_val : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
		 speed_is_100 : OUT STD_LOGIC;
		 speed_is_10_100 : OUT STD_LOGIC;
		 gmii_txd : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		 gmii_tx_en : OUT STD_LOGIC;
		 gmii_tx_er : OUT STD_LOGIC;
		 gmii_rxd : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		 gmii_rx_dv : IN STD_LOGIC;
		 gmii_rx_er : IN STD_LOGIC;
		 rx_mac_config_vector : IN STD_LOGIC_VECTOR(79 DOWNTO 0);
		 tx_mac_config_vector : IN STD_LOGIC_VECTOR(79 DOWNTO 0)
	  );
	END COMPONENT;
	
	COMPONENT mac_fifo_axi4
	  PORT (
		 m_aclk : IN STD_LOGIC;
		 s_aclk : IN STD_LOGIC;
		 s_aresetn : IN STD_LOGIC;
		 s_axis_tvalid : IN STD_LOGIC;
		 s_axis_tready : OUT STD_LOGIC;
		 s_axis_tdata : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		 s_axis_tlast : IN STD_LOGIC;
		 s_axis_tuser : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
		 m_axis_tvalid : OUT STD_LOGIC;
		 m_axis_tready : IN STD_LOGIC;
		 m_axis_tdata : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		 m_axis_tlast : OUT STD_LOGIC;
		 m_axis_tuser : OUT STD_LOGIC_VECTOR(0 DOWNTO 0)
	  );
	END COMPONENT;

	signal rx_clk, rx_clk_io: std_logic;
	signal txd_e, rxd_r: std_logic_vector(7 downto 0);
	signal tx_en_e, tx_er_e, rx_dv_r, rx_er_r: std_logic;
	signal gmii_rxd_del: std_logic_vector(7 downto 0);
	signal gmii_rx_dv_del, gmii_rx_er_del: std_logic;

	attribute IODELAY_GROUP: string;
	attribute IODELAY_GROUP of idelayctrl0: label is "iodel_gmii_rx";
	attribute IODELAY_GROUP of iodelay_dv: label is "iodel_gmii_rx";
	attribute IODELAY_GROUP of iodelay_er: label is "iodel_gmii_rx";
	
	signal rx_data_e: std_logic_vector(7 downto 0);
	signal rx_valid_e, rx_last_e, rx_user_e, rx_rst, rstn: std_logic;
	signal rx_user_f, rx_user_ef: std_logic_vector(0 downto 0);

begin

	idelayctrl0: idelayctrl port map(
		refclk => clk200,
		rst => rst
	); -- V5/6 delay element controller

	bufio0: bufio port map(
		i => gmii_rx_clk,
		o => rx_clk_io
	);
	
	bufr0: bufr port map(
		i => gmii_rx_clk,
		o => rx_clk,
		ce => '1',
		clr => '0'
	);
	
	iodelgen: for i in 7 downto 0 generate
		attribute IODELAY_GROUP of iodelay: label is "iodel_gmii_rx";
	begin

		iodelay: idelaye2
			generic map(
				IDELAY_TYPE => "FIXED"
			)
			port map(
				idatain => gmii_rxd(i),
				dataout => gmii_rxd_del(i),
				ce => '0',
				inc => '0',
				ld => '0',
				ldpipeen => '0',
				regrst => '0',
				c => '0',
				cinvctrl => '0',
				cntvaluein => (others => '0'),
				datain => '0'
			); -- Delay element for phase alignment
	
	end generate;
	
	iodelay_dv: idelaye2
		generic map(
			IDELAY_TYPE => "FIXED"
		)
		port map(
			idatain => gmii_rx_dv,
			dataout => gmii_rx_dv_del,
			ce => '0',
			inc => '0',
			ld => '0',
			ldpipeen => '0',
			regrst => '0',
			c => '0',
			cinvctrl => '0',
			cntvaluein => (others => '0'),
			datain => '0'
		); -- Delay element on rx clock for phase alignment
		
	iodelay_er: idelaye2
		generic map(
			IDELAY_TYPE => "FIXED"
		)
		port map(
			idatain => gmii_rx_er,
			dataout => gmii_rx_er_del,
			ce => '0',
			inc => '0',
			ld => '0',
			ldpipeen => '0',
			regrst => '0',
			c => '0',
			cinvctrl => '0',
			cntvaluein => (others => '0'),
			datain => '0'
		); -- Delay element for phase alignment

	process(rx_clk_io) -- FFs for incoming GMII data (need to be IOB FFs)
	begin
		if rising_edge(rx_clk_io) then
			rxd_r <= gmii_rxd_del;
			rx_dv_r <= gmii_rx_dv_del;
			rx_er_r <= gmii_rx_er_del;
		end if;
	end process;

	process(clk125) -- FFs for outgoing GMII data (need to be IOB FFs)
	begin
		if rising_edge(clk125) then
			gmii_txd <= txd_e;
			gmii_tx_en <= tx_en_e;
			gmii_tx_er <= tx_er_e;
		end if;
	end process;
	
	oddr0: oddr port map(
		q => gmii_gtx_clk,
		c => clk125,
		ce => '1',
		d1 => '0',
		d2 => '1',
		r => '0',
		s => '0'
	); -- DDR register for clock forwarding

	rstn <= not rst;

	emac0: tri_mode_eth_mac_v5_4 port map(
		glbl_rstn => rstn,
		rx_axi_rstn => '1',
		tx_axi_rstn => '1',
		rx_axi_clk => rx_clk,
		rx_reset_out => open,
		rx_axis_mac_tdata => rx_data_e,
		rx_axis_mac_tvalid => rx_valid_e,
		rx_axis_mac_tlast => rx_last_e,
		rx_axis_mac_tuser => rx_user_e,
		rx_statistics_vector => open,
		rx_statistics_valid => open,
		tx_axi_clk => clk125,
		tx_reset_out => open,
		tx_axis_mac_tdata => tx_data,
		tx_axis_mac_tvalid => tx_valid,
		tx_axis_mac_tlast => tx_last,
		tx_axis_mac_tuser => tx_error,
		tx_axis_mac_tready => tx_ready,
		tx_ifg_delay => X"00",
		tx_statistics_vector => open,
		tx_statistics_valid => open,
		pause_req => '0',
		pause_val => X"0000",
		speed_is_100 => open,
		speed_is_10_100 => open,
		gmii_txd => txd_e,
		gmii_tx_en => tx_en_e,
		gmii_tx_er => tx_er_e,
		gmii_rxd => rxd_r,
		gmii_rx_dv => rx_dv_r,
		gmii_rx_er => rx_er_r,
		rx_mac_config_vector => X"0000_0000_0000_0000_0812",
		tx_mac_config_vector => X"0000_0000_0000_0000_0012"
	);
	
	rx_user_ef(0) <= rx_user_e;
	rx_error <= rx_user_f(0);
	
	process(rx_clk)
	begin
		if rising_edge(rx_clk) then
			rx_rst <= not rst;
		end if;
	end process;
	
	fifo: mac_fifo_axi4 port map(
		m_aclk => clk125,
		s_aclk => rx_clk,
		s_aresetn => rx_rst,
		s_axis_tvalid => rx_valid_e,
		s_axis_tready => open,
		s_axis_tdata => rx_data_e,
		s_axis_tlast => rx_last_e,
		s_axis_tuser => rx_user_ef,
		m_axis_tvalid => rx_valid,
		m_axis_tready => '1',
		m_axis_tdata => rx_data,
		m_axis_tlast => rx_last,
		m_axis_tuser => rx_user_f
	); -- Clock domain crossing FIFO

	hostbus_out.hostrddata <= (others => '0');
	hostbus_out.hostmiimrdy <= '0';

end rtl;
