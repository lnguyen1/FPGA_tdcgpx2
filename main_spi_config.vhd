----------------------------------------------------------------------------------
-- Company: Quest - Stevens Institute of Technology
-- Engineer: Lac Nguen
-- 
-- Create Date:    11:11:15 1/11/2018 
-- Design Name: 
-- Module Name:    main - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library  UNISIM;
use UNISIM.vcomponents.all;
library IEEE;
	use IEEE.STD_LOGIC_1164.ALL;
   use IEEE.NUMERIC_STD.ALL;
   --use ieee.std_logic_unsigned.all;

entity init is
	port(
		
			 -- LVDS Clock to TDC
		clkout_p	: out std_logic;
		clkout_n	: out std_logic;
		clkin_p	: in  std_logic;
		clkin_n	: in  std_logic;
		
			 -- Main clock to SPI
		user_clk : in  std_logic; -- 27 MHz external clk input to FPGA
      reset	   : in  std_logic; -- hook reset to a pin and set to HIGH to have SPI data TX ready
		
          -- SPI 4 wires
  --    spi_miso : in  std_logic; -- Master in, slave out, just put high impedance since we don't read anything here, read out from LVDS
      spi_mosi : out std_logic; -- Master out, slave in, send config register values to TDC
      spi_ssn  : out std_logic := '0'; -- Slave select not, positive pulse to start, when LOW -> ready to shift of data in/out to/from device
      spi_clk  : out std_logic
    );

end init;

architecture Behavioral of init is
	-- Component differential signal for LVDS clock

	signal clock_bufin : std_logic;
	signal clock_bufout: std_logic;
	
	component IBUFDS
		generic (
			DIFF_TERM : BOOLEAN;
			IBUF_LOW_PWR : BOOLEAN;
			IOSTANDARD : string;
			USE_IBUFDISABLE : string;
			DQS_BIAS : string);
		port (
			I : in std_logic;
			IB: in std_logic;
			O : out std_logic
		);
	end component;
	
	component OBUFDS
		generic (
			DIFF_TERM : BOOLEAN;
			IBUF_LOW_PWR : BOOLEAN;
			IOSTANDARD : string;
			USE_IBUFDISABLE : string;
			DQS_BIAS : string);
		port (
			O : out std_logic;
			OB: out std_logic;
			I : in std_logic
		);
	end component;

	attribute box_type	: string;
	attribute box_type of ibufds: component is "black_box";
	attribute box_type of obufds: component is "black_box";
	
		-- Shift register
	signal shift_reg    : std_logic_vector (95 downto 0) := "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
		-- Counter for clock divider
	signal counter      : unsigned (23 downto 0);
	signal counter1      : unsigned (23 downto 0);
		-- Clock divider signal = SPI CLK
	signal clk_divided  : std_logic;
	signal config_error : boolean;
begin
-- * Generate LVDS Clock output lines into TDC * --
	clkin_inst: IBUFDS
		generic map (
			DIFF_TERM => TRUE, -- Differential Termination
			IBUF_LOW_PWR => TRUE, -- Low power (TRUE) vs. performance (FALSE) setting for referenced I/O standards
			IOSTANDARD => "DEFAULT", -- Specify the input I/O standard
			USE_IBUFDISABLE => "TRUE",
			DQS_BIAS => "FALSE"
		)
		port map (
			O  => clock_bufin,
			I  => clkin_p, -- Diff_p buffer input (connect directly to top-level port)	
			IB => clkin_n -- Diff_n buffer input (connect directly to top-level port)
		);
	
--	clkbuf_inst : ODDR2
--		generic map (
--			DDR_ALIGNMENT => "NONE",
--			INIT => '0',
--			SRTYPE => "SYNC"
--		)
--		port map (
--			Q => clock_bufout,
--			C0 => clock_bufin,
--			C1 => not clock_bufin,
--			D0 => '1',
--			D1 => '0'		
--		);
	lvds_clkout: process (user_clk)
	begin
		if rising_edge(user_clk) then
			if counter1 < 1 then
				counter1 <= counter1 + 1;
			else
				clock_bufout <= not clock_bufout;
				counter1 <= (others => '0');
			end if;
		end if;
	end process;
	
	clkout_inst: OBUFDS
		generic map (
			DIFF_TERM => TRUE, -- Differential Termination
			IBUF_LOW_PWR => TRUE, -- Low power (TRUE) vs. performance (FALSE) setting for referenced I/O standards
			IOSTANDARD => "DEFAULT", -- Specify the input I/O standard
			USE_IBUFDISABLE => "TRUE",
			DQS_BIAS => "FALSE"
		)
		port map (
			I  => clock_bufout,
			O  => clkout_p, -- Diff_p buffer input (connect directly to top-level port)	
			OB => clkout_n -- Diff_n buffer input (connect directly to top-level port)
		);

	
	-- * Clock divider to 50 MHz for SPI clock * --
		
	--clkout_p <= clock_bufout;
	spi_clkdivider : process(clock_bufin)
	begin
		if rising_edge(clock_bufin) then
			if counter < 2 then -- 200MHz/4 = 50 MHz -- NEED MORE THAN 50 MHz clock, gotta use the SYS_CLK 200 MHz
				counter <= counter + 1;
			else
				clk_divided <= not clk_divided; -- rising edge
				counter <= (others => '0');	
			end if;
		end if;
	end process;
	
	spi_clk <= clk_divided;
	
    -- * Master out slave in * --
	spi_process : process (clk_divided, reset, shift_reg)
		type config_reg is array (0 to 11)
			of std_logic_vector (7 downto 0);
		constant data : config_reg :=(
												"00110000", -- send opcode for power on reset 0x30
												"10000000", -- write config register, start with config reg 00, 0x80
												"00110001", -- config setting of config reg 00, 0x31 
														 -- STOP chn 1 active only, activate LVDS pin
												"00000001", -- config setting of config reg 01, 0x01 
														 -- STOP event internally accepted chn 1
												"00011111", -- config setting of config reg 02, 0x1F -- ref index 12 bits,
														 -- stop data bit width 20 bits, single data rate
												"01000000", -- config setting of config reg 03, 0x40 
												"00001101", -- config setting of config reg 04, 0x0D
												"00000011", -- config setting of config reg 05, 0x03
												"11001000", -- config setting of config reg 06, 0xC0 -- no LVDS pattern
												"01010011", -- config setting of config reg 07, 0x53 
														 -- 0ps data valid adjust, ref applied to refclk pin
												"10100001", -- config setting of config reg 08, 0xA1 --
												"00010011" -- config setting of config reg 09, 0x13
);
	
	begin
		shift_reg <= x"30" & x"80" & x"31" & x"01" & x"1F" & x"40" & x"0D" & x"03" & x"C0" & x"53" & x"A1" & x"13"; 
		if reset = '1' then 
			spi_ssn <= '1';
			spi_ssn <= '0'; -- Ready to transfer/receive data
				if rising_edge (clk_divided)then
					config_error <= false;
					--shift_reg(95 downto 1) <= shift_reg(94 downto 0);
					--shift_reg(0) <= '1';--
					shift_reg <= shift_reg (94 downto 0)& 'Z';
				end if;
		else 
			spi_ssn <= '1'; -- Reset interface
		end if;
	end process;
	start_measurement : process (config_error)
	begin
		shift_reg <= x"18";
		if config_error = false then
			spi_ssn <= '1';
			spi_ssn <= '0';
			shift_reg <= shift_reg (94 downto 0) &'Z';	
		end if;
	end process;
	
	spi_mosi <= shift_reg(95); -- send out msb

end Behavioral;