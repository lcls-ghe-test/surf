-------------------------------------------------------------------------------
-- Title      : 
-------------------------------------------------------------------------------
-- File       : GLinkGtp7FixedLatWrapper.vhd
-- Author     : Larry Ruckman  <ruckman@slac.stanford.edu>
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2014-02-04
-- Last update: 2014-02-04
-- Platform   : 
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- Copyright (c) 2014 SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.StdRtlPkg.all;
use work.GlinkPkg.all;

library unisim;
use unisim.vcomponents.all;

entity GLinkGtp7FixedLatWrapper is
   generic (
      -- Select Master or Slave
      MASTER_SEL_G          : boolean              := true;
      RX_CLK_SEL_G          : boolean              := true;
      -- GLink Settings
      FLAGSEL_G             : boolean              := false;
      -- Simulation Generics
      TPD_G                 : time                 := 1 ns;
      SIM_GTRESET_SPEEDUP_G : string               := "FALSE";
      SIM_VERSION_G         : string               := "4.0";
      SIMULATION_G          : boolean              := false;
      -- Quad PLL Configurations
      QPLL_FBDIV_IN_G       : integer range 1 to 5 := 4;
      QPLL_FBDIV_45_IN_G    : integer range 4 to 5 := 5;
      QPLL_REFCLK_DIV_IN_G  : integer range 1 to 2 := 1;
      -- MMCM Configurations
      MMCM_CLKIN_PERIOD_G   : real                 := 8.000;
      MMCM_CLKFBOUT_MULT_G  : real                 := 8.000;
      MMCM_GTCLK_DIVIDE_G   : real                 := 8.000;
      MMCM_TXCLK_DIVIDE_G   : natural              := 8;
      -- MGT Configurations
      RXOUT_DIV_G           : integer              := 2;
      TXOUT_DIV_G           : integer              := 2;
      RX_CLK25_DIV_G        : integer              := 5;    -- Set by wizard
      TX_CLK25_DIV_G        : integer              := 5;    -- Set by wizard
      PMA_RSV_G             : bit_vector           := x"00000333";  -- Set by wizard
      RX_OS_CFG_G           : bit_vector           := "0001111110000";  -- Set by wizard
      RXCDR_CFG_G           : bit_vector           := x"0000107FE206001041010";  -- Set by wizard
      RXLPM_INCM_CFG_G      : bit                  := '1';  -- Set by wizard
      RXLPM_IPCM_CFG_G      : bit                  := '0';  -- Set by wizard
      TX_PLL_G              : string               := "PLL0";
      RX_PLL_G              : string               := "PLL1");           
   port (
      -- Manual Reset
      extRst    : in  sl;
      -- Status and Clock Signals
      txPllLock : out sl;
      rxPllLock : out sl;
      txReady   : out sl;
      rxReady   : out sl;
      txClk     : out sl;
      rxClk     : out sl;
      stableClk : out sl;
      -- G-Link Signals
      gLinkTx   : in  GLinkTxType;
      gLinkRx   : out GLinkRxType;
      -- GT loopback control
      loopback  : in  slv(2 downto 0);  -- GT Serial Loopback Control      
      -- GT Pins
      gtClkP    : in  sl;
      gtClkN    : in  sl;
      gtTxP     : out sl;
      gtTxN     : out sl;
      gtRxP     : in  sl;
      gtRxN     : in  sl);  
end GLinkGtp7FixedLatWrapper;

architecture rtl of GLinkGtp7FixedLatWrapper is

   signal gtClk,
      gtClkDiv2,
      stableClock,
      stableRst,
      locked,
      clkOut0,
      clkOut1,
      clkFbIn,
      clkFbOut,
      txClock,
      txRst,
      rxClock,
      rxRecClk, : sl := '0';
   signal pllRefClk,
      qPllOutClk,
      qPllOutRefClk,
      qPllLock,
      pllLockDetClk,
      qPllRefClkLost,
      qPllReset,
      gtQPllReset : slv(1 downto 0);

begin

   -- Set the status outputs
   txPllLock <= ite((TX_PLL_G = "PLL0"), qPllLock(0), qPllLock(1));
   rxPllLock <= ite((RX_PLL_G = "PLL0"), qPllLock(0), qPllLock(1));
   txClk     <= txClock;
   rxClk     <= rxClock;
   stableClk <= stableClock;

   -- GT Reference Clock
   IBUFDS_GTE2_Inst : IBUFDS_GTE2
      port map (
         I     => gtClkP,
         IB    => gtClkN,
         CEB   => '0',
         ODIV2 => gtClkDiv2,
         O     => open);

   BUFG_G : BUFG
      port map (
         I => gtClkDiv2,
         O => stableClock);

   -- Power Up Reset      
   PwrUpRst_Inst : entity work.PwrUpRst
      port map (
         arst   => extRst,
         clk    => stableClock,
         rstOut => stableRst);

   mmcm_adv_inst : MMCME2_ADV
      generic map(
         BANDWIDTH            => "LOW",
         CLKOUT4_CASCADE      => false,
         COMPENSATION         => "ZHOLD",
         STARTUP_WAIT         => false,
         DIVCLK_DIVIDE        => 1,
         CLKFBOUT_MULT_F      => MMCM_CLKFBOUT_MULT_G,
         CLKFBOUT_PHASE       => 0.000,
         CLKFBOUT_USE_FINE_PS => false,
         CLKOUT0_DIVIDE_F     => MMCM_GTCLK_DIVIDE_G,
         CLKOUT0_PHASE        => 0.000,
         CLKOUT0_DUTY_CYCLE   => 0.500,
         CLKOUT0_USE_FINE_PS  => false,
         CLKOUT1_DIVIDE       => MMCM_TXCLK_DIVIDE_G,
         CLKOUT1_PHASE        => 0.000,
         CLKOUT1_DUTY_CYCLE   => 0.500,
         CLKOUT1_USE_FINE_PS  => false,
         CLKIN1_PERIOD        => MMCM_CLKIN_PERIOD_G,
         REF_JITTER1          => 0.006)
      port map(
         -- Output clocks
         CLKFBOUT     => clkFbOut,
         CLKFBOUTB    => open,
         CLKOUT0      => clkOut0,
         CLKOUT0B     => open,
         CLKOUT1      => clkOut1,
         CLKOUT1B     => open,
         CLKOUT2      => open,
         CLKOUT2B     => open,
         CLKOUT3      => open,
         CLKOUT3B     => open,
         CLKOUT4      => open,
         CLKOUT5      => open,
         CLKOUT6      => open,
         -- Input clock control
         CLKFBIN      => clkFbIn,
         CLKIN1       => ite(MASTER_SEL_G, stableClock, rxClock),
         CLKIN2       => '0',
         -- Tied to always select the primary input clock
         CLKINSEL     => '1',
         -- Ports for dynamic reconfiguration
         DADDR        => (others => '0'),
         DCLK         => '0',
         DEN          => '0',
         DI           => (others => '0'),
         DO           => open,
         DRDY         => open,
         DWE          => '0',
         -- Ports for dynamic phase shift
         PSCLK        => '0',
         PSEN         => '0',
         PSINCDEC     => '0',
         PSDONE       => open,
         -- Other control and status signals
         LOCKED       => locked,
         CLKINSTOPPED => open,
         CLKFBSTOPPED => open,
         PWRDWN       => '0',
         RST          => stableRst);

   BUFH_1 : BUFH
      port map (
         I => clkFbOut,
         O => clkFbIn); 

   BUFG_2 : BUFG
      port map (
         I => clkOut0,
         O => gtClk); 

   BUFG_3 : BUFG
      port map (
         I => clkOut1,
         O => txClock);  

   txRst <= stableRst;

   -- PLL0 Port Mapping
   pllRefClk(0)     <= gtClk when((MASTER_SEL_G = true) or (TX_PLL_G = "PLL0")) else stableClock;
   pllLockDetClk(0) <= stableClock;
   qPllReset(0)     <= stableRst or gtQPllReset(0);

   -- PLL1 Port Mapping
   pllRefClk(1)     <= gtClk    when((MASTER_SEL_G = true) or (TX_PLL_G = "PLL1")) else stableClock;
   pllLockDetClk(1) <= stableClock;
   qPllReset(1)     <= stableRst or gtQPllReset(1);
   rxClock          <= rxRecClk when(RX_CLK_SEL_G = true)                          else txClock;

   Quad_Pll_Inst : entity work.Gtp7QuadPll
      generic map (
         PLL0_REFCLK_SEL_G    => "111",
         PLL0_FBDIV_IN_G      => QPLL_FBDIV_IN_G,
         PLL0_FBDIV_45_IN_G   => QPLL_FBDIV_45_IN_G,
         PLL0_REFCLK_DIV_IN_G => QPLL_REFCLK_DIV_IN_G,
         PLL1_REFCLK_SEL_G    => "111",
         PLL1_FBDIV_IN_G      => QPLL_FBDIV_IN_G,
         PLL1_FBDIV_45_IN_G   => QPLL_FBDIV_45_IN_G,
         PLL1_REFCLK_DIV_IN_G => QPLL_REFCLK_DIV_IN_G)         
      port map (
         qPllRefClk     => pllRefClk,
         qPllOutClk     => qPllOutClk,
         qPllOutRefClk  => qPllOutRefClk,
         qPllLock       => qPllLock,
         qPllLockDetClk => pllLockDetClk,
         qPllRefClkLost => qPllRefClkLost,
         qPllReset      => qPllReset);                   

   GLinkGtp7FixedLat_Inst : entity work.GLinkGtp7FixedLat
      generic map (
         -- Simulation Settings
         TPD_G                 => TPD_G,
         SIM_GTRESET_SPEEDUP_G => SIM_GTRESET_SPEEDUP_G,
         SIM_VERSION_G         => SIM_VERSION_G,
         SIMULATION_G          => SIMULATION_G,
         -- GLink Settings
         FLAGSEL_G             => FLAGSEL_G,
         -- CDR Settings -
         RXOUT_DIV_G           => RXOUT_DIV_G,
         TXOUT_DIV_G           => TXOUT_DIV_G,
         RX_CLK25_DIV_G        => RX_CLK25_DIV_G,
         TX_CLK25_DIV_G        => TX_CLK25_DIV_G,
         RX_OS_CFG_G           => RX_OS_CFG_G,
         RXCDR_CFG_G           => RXCDR_CFG_G,
         RXLPM_INCM_CFG_G      => RXLPM_INCM_CFG_G,
         RXLPM_IPCM_CFG_G      => RXLPM_IPCM_CFG_G,
         -- Configure PLL sources
         TX_PLL_G              => TX_PLL_G,
         RX_PLL_G              => RX_PLL_G)
      port map (
         -- TX Signals
         gLinkTx          => gLinkTx,
         txClk            => txClock,
         txRst            => txRst,
         txReady          => txReady,
         -- RX Signals
         gLinkRx          => gLinkRx,
         rxClk            => rxClock,
         rxRecClk         => rxRecClk,
         rxRst            => extRst,
         rxMmcmRst        => open,
         rxMmcmLocked     => locked,
         rxReady          => rxReady,
         -- MGT Clocking
         stableClk        => stableClock,
         gtCPllRefClk     => gtCPllRefClk,
         gtCPllLock       => gtCPllLock,
         gtQPllRefClk     => qPllOutRefClk,
         gtQPllClk        => qPllOutClk,
         gtQPllLock       => qPllLock,
         gtQPllRefClkLost => qPllRefClkLost,
         gtQPllReset      => gtQPllReset,
         -- MGT loopback control
         loopback         => loopback,
         -- MGT Serial IO
         gtTxP            => gtTxP,
         gtTxN            => gtTxN,
         gtRxP            => gtRxP,
         gtRxN            => gtRxN);            

end rtl;