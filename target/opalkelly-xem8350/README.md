# OpalKelly XEM8350-KU060 with BRK8350 Time Tagger FPGA Link Reference Project

This directory and its subdirectories constitute a reference design for the Time
Tagger FPGA Link on the OpalKelly XEM8350-KU060 FPGA board, in conjuction with
the corresponding BRK8350 breakout board. It implements the 10Gbit/s Ethernet
and 40Gbit/s Ethernet Time Tagger FPGA link interfaces.

Please note that usage of the 40Gbit/s Ethernet-based interface utilizes
Xilinx's [40G/50G Ethernet
Subsystem](https://www.xilinx.com/products/intellectual-property/ef-di-50gemac.html)
IP core and requires an appropriate `l_eth_baser` license key. The
Vivado-integrated "Design Linking" license for this core cannot be used to
generate a bitstream and thus is insufficient to test the design on a proper
FPGA board.

## Getting Started

Building this project requires a licensed version of Xilinx Vivado; the XCKU060
is not a WebPack-compatible FPGA. The project has been tested to work with
Vivado 2020.2 on an Ubuntu 20.04 Workstation installation. Assuming Vivado and
all required tools are installed, the Xilinx Vivado project can be created by
running:

```
si@ubuntu:target/opalkelly-xem8350$ make project
vivado -mode tcl -source scripts/create_project.tcl

****** Vivado v2020.2 (64-bit)
  **** SW Build 3064766 on Wed Nov 18 09:12:47 MST 2020
  **** IP Build 3064653 on Wed Nov 18 14:17:31 MST 2020
    ** Copyright 1986-2020 Xilinx, Inc. All Rights Reserved.

[... output suppressed ...]

# current_run -implementation [get_runs impl_1]
# puts "Successfully created project ${project_name}!"
Successfully created project xem8350-timetagger-fpgalink-reference!
# exit
INFO: [Common 17-206] Exiting Vivado at Wed Aug  3 15:07:01 2022...
```

You may observe warnings such as the following:

```
WARNING: [IP_Flow 19-650] IP license key 'l_eth_baser@2020.11' is enabled with a Hardware_Evaluation license.
WARNING: [IP_Flow 19-650] IP license key 'l_eth_baser@2020.11' is enabled with a Hardware_Evaluation license.
WARNING: [IP_Flow 19-650] IP license key 'l_eth_baser@2020.11' is enabled with a Hardware_Evaluation license.
WARNING: [IP_Flow 19-650] IP license key 'l_eth_basekr@2020.11' is enabled with a Design_Linking license.
WARNING: [IP_Flow 19-650] IP license key 'l_eth_basekr@2020.11' is enabled with a Design_Linking license.
WARNING: [IP_Flow 19-650] IP license key 'l_eth_basekr@2020.11' is enabled with a Design_Linking license.
[...]
```

Depending on whether or not you have a Design Linking / Hardware Evaluation or
proper license for the `l_eth_baser`, and whether the 40Gbit/s Ethernet
interface shall be integrated into the design, these warnings can be an
indication of missing licenses. The 40Gbit/s Ethernet interface requires only
the `l_eth_baser` license key. A production design must use a proper License,
for more information visit the [40G/50G Ethernet Subsystem order & licensing
page](https://www.xilinx.com/products/intellectual-property/ef-di-50gemac/ef-di-50gemac-order.html).

The FPGA bitstream can be built from within Vivado by opening the generated
project file (`xem8350-timetagger-fpgalink-reference.xpr`), or by running `make
all` instead of or after `make project`. It will be located under
`xem8350-timetagger-fpgalink-reference.runs/impl_1/xem8350_reference.bit`.

Once built, the bitstream can be programmed onto the FPGA either via a
compatible JTAG-adapter (such as the Xilinx Platform Cable II), or using the
integrated USB controller through the OpalKelly FrontPanel SDK. For support on
how to install the OpalKelly FrontPanel SDK, please visit the OpalKelly
website. With the SDK installed, the FPGA can be configured from within a Python
3 environment as shown:

```
si@ubuntu:target/opalkelly-xem8350$ python3
>>> import ok
>>> xem = ok.FrontPanel()
>>> xem.OpenBySerial()
0
>>> xem.ConfigureFPGA("xem8350-timetagger-fpgalink-reference.runs/impl_1/xem8350_reference.bit")
0
```

The XEM8350 board integrates a Skyworks Si5338B PLL which synthesizes the
transceiver clock required for both 10Gbit/s Ethernet and 40Gbit/s Ethernet
operation. This PLL chip can be configured via an I2C interface. The reference
design includes an I2C to Wishbone core, connected to a Wishbone bus in the
FPGA, which in turn is accessible through the OpalKelly FrontPanel USB
interface. The PLL does not feature user-programmable nonvolatile memory and
must be programmed after every power-cycle or FPGA configuration. This project
includes a script to configure the PLL to provide a 156.25MHz reference clock
frequency to the FPGA transceivers. This script must be executed from within the
`host` subdirectory, as illustrated below:

```
si@ubuntu:target/opalkelly-xem8350$ pushd host
si@ubuntu:target/opalkelly-xem8350/host$ python3 -m si5338b_pll \
    --device xem_i2c \
    --xem-bitstream ../xem8350-timetagger-fpgalink-reference.runs/impl_1/xem8350_reference.bit \
    --input-csv ../config/xem8350-si5338-b10680-gm-v0-15625xcvrclk.csv \
    flash
Connected to device Opal Kelly XEM8350 with serial 0123456789!
Configuring FPGA using bitstream "../xem8350-timetagger-fpgalink-reference.runs/impl_1/xem8350_reference.bit", please wait...
Last 2 digits of PLL part number: 38
Device revision ID: 0x01
Flashing ../config/xem8350-si5338-b10680-gm-v0-15625xcvrclk.csv to PLL, please wait.
Done. PLL has acquired lock with new configuration.
si@ubuntu:target/opalkelly-xem8350/host$ popd
```

When the `--xem-bitstream` argument is not supplied, the FPGA will not be
reconfigured and the currently running bitstream will be used to configure the
PLL.

Once the PLL is configured, the transceivers can be initialized. For the
10Gbit/s transceiver connected to lane 2 of the QSFP+ port 2, this works as
follows:

```
si@ubuntu:target/opalkelly-xem8350$ pushd host
si@ubuntu:target/opalkelly-xem8350/host$ python3
>>> import ok
>>> xem = ok.FrontPanel()
>>> xem.OpenBySerial()
0
>>> assert xem.IsFrontPanelEnabled() == 1
>>> import common.xem_wishbone
>>> wb = common.xem_wishbone.XEMWishbone(xem)
>>> xcvr_10g = 0b10101 << 8
>>> bin(wb.read(xcvr_10g | 0x4)) # 0x4 = transceiver_status register
'0b10000000011'
# bit 0x00 = 1 -> Transceiver Power Good
# bit 0x01 = 1 -> Transceiver in Reset
# bit 0x02 = 0 -> Transceiver TX PMA Reset Not Done
# bit 0x03 = 0 -> Transceiver TX PRGDIV Reset Not Done
# bit 0x04 = 0 -> Transceiver TX Reset Not Done
# bit 0x05 = 0 -> Transceiver RX PMA Reset Not Done
# bit 0x06 = 0 -> Transceiver RX PRGDIV Reset Not Done
# bit 0x07 = 0 -> Transceiver RX Reset Not Done
# bit 0x08 = 0 -> Transceiver Userclk TX Not Active
# bit 0x09 = 0 -> Transceiver Userclk RX Not Active
# bit 0x0A = 1 -> External PLL Locked (const 1 in this design)
# bit 0x0B = 0 -> Transceiver QPLL Not Locked
# bit 0x0C = 0 -> Transceiver RX CDR Not Stable
>>> wb.write(xcvr_10g | 0x8, 1) # 0x8 = transceiver_control register
# bit 0x01 = 1 -> Transceiver Enable (release reset)
>>> bin(wb.read(xcvr_10g | 0x4))
'0b111111111101'
# bit 0x00 = 1 -> Transceiver Power Good
# bit 0x01 = 0 -> Transceiver Not in Reset
# bit 0x02 = 1 -> Transceiver TX PMA Reset Done
# bit 0x03 = 1 -> Transceiver TX PRGDIV Reset Done
# bit 0x04 = 1 -> Transceiver TX Reset Done
# bit 0x05 = 1 -> Transceiver RX PMA Reset Done
# bit 0x06 = 1 -> Transceiver RX PRGDIV Reset Done
# bit 0x07 = 1 -> Transceiver RX Reset Done
# bit 0x08 = 1 -> Transceiver Userclk TX Active
# bit 0x09 = 1 -> Transceiver Userclk RX Active
# bit 0x0A = 1 -> External PLL Locked (const 1 in this design)
# bit 0x0B = 1 -> Transceiver QPLL Locked
```
