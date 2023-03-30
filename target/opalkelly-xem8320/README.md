# OpalKelly XEM8320 Time Tagger FPGA Link Reference Project

This directory and its subdirectories constitute a reference design for the Time
Tagger FPGA Link on the OpalKelly XEM8320 FPGA board. It implements the 10Gbit/s
Ethernet Time Tagger FPGA link interfaces.

Please note the following from OpalKelly:

*Hot Plugging is Not Supported*

While the SFP standard does support hot plugging of SFP+ modules, this is NOT SUPPORTED by the Artix UltraScale+ FPGA or the XEM8320.

Only insert or remove modules when power to the platform is turned off.

## Getting Started

Building this project requires a recent Version of Vivado. The chip is
included in the Standard Edition, so no paid Vivado-license is required. The
project has been tested to work with Vivado 2022.2 on an Ubuntu 20.04
Workstation installation.  Assuming Vivado and all required tools are installed,
the Xilinx Vivado project can be created by running:

```
si@ubuntu:target/opalkelly-xem8320$ make project
vivado -mode tcl -source scripts/create_project.tcl

****** Vivado v2022.1 (64-bit)
  **** SW Build 3526262 on Mon Apr 18 15:47:01 MDT 2022
  **** IP Build 3524634 on Mon Apr 18 20:55:01 MDT 2022
    ** Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.

[... output suppressed ...]

# current_run -implementation [get_runs impl_1]
# puts "Successfully created project ${project_name}!"
Successfully created project xem8320-timetagger-fpgalink-reference!
# exit
INFO: [Common 17-206] Exiting Vivado at Thu Aug 18 17:06:44 2022...
```

The FPGA bitstream can be built from within Vivado by opening the generated
project file (`xem8320-timetagger-fpgalink-reference.xpr`), or by running `make
all` instead of or after `make project`. It will be located under
`xem8320-timetagger-fpgalink-reference.runs/impl_1/xem8320_reference.bit`.

Once built, the bitstream can be programmed onto the FPGA either via a
compatible JTAG-adapter (such as the Xilinx Platform Cable II), or using the
integrated USB controller through the OpalKelly FrontPanel SDK. For support on
how to install the OpalKelly FrontPanel SDK, please visit the OpalKelly
website. With the SDK installed, the FPGA can be configured either via the
FrontPanel Application or from within a Python 3 environment as shown:
```
si@ubuntu:target/opalkelly-xem8320$ python3
>>> import ok
>>> xem = ok.FrontPanel()
>>> xem.OpenBySerial()
0
>>> xem.ConfigureFPGA("xem8320-timetagger-fpgalink-reference.runs/impl_1/xem8320_reference.bit")
0
```

To use the SFP+ modules and the onboard LEDs, the [VIO1](https://docs.opalkelly.com/xem8320/leds/) & [VIO2](https://docs.opalkelly.com/xem8320/gigabit-transceivers/) voltage need to be enabled without a connected SYZYGY module, . This project includes a script to configure the voltage rails accordingly in SmartVIO hybrid mode. This script must be executed from within the `host` subdirectory, as illustrated below:

``` sh
si@ubuntu:target/opalkelly-xem8350$ pushd host
si@ubuntu:target/opalkelly-xem8350/host$ python -m device_settings configure
Connected to device Opal Kelly XEM8320 with serial 0123456789!
         Product: XEM8320-AU25P
Firmware version: 1.39
   Serial Number: 0123456789
       Device ID: Opal Kelly XEM8320
Setting XEM8320_SMARTVIO_MODE to 0x01
Setting XEM8320_VIO1_VOLTAGE to 120
Setting XEM8320_VIO2_VOLTAGE to 330
Saved settings.
si@ubuntu:target/opalkelly-xem8350/host$ popd
```

These settings are only applied after a power-cycle of the XEM8320-board.

With a connected TTX with FPGA-Link Output enabled, you can now enable Channel 1
capture and observe the LED on the XEM8320 matching the input state of the TTX.

## Debug Information
The design exposes various statistics of the received tags over the OpalKelly
USB interface, which bridges onto an internal Wishbone Bus. This can be read with the following

``` sh

si@ubuntu:target/opalkelly-xem8350$ pushd host
si@ubuntu:target/opalkelly-xem8350/host$ python3 -m common.statistics
Connected to device Opal Kelly XEM8320 with serial 0123456789!
Diagnostics:
                                                          VAL
  packet_rate                          (Packets/s) :   183095
  word_rate                    (Words (256 bit)/s) :   549285
  received_packets                       (Packets) :   876845
  received_words                 (Words (256 bit)) :  2630819
  size_of_last_packet     (Words (256 bit)/Packet) :        3
  packet_loss                               (bool) :        0
  invalid_packets                        (Packets) :        0
si@ubuntu:target/opalkelly-xem8350/host$ popd
```

You can also use `sfp.py` inside `../../host/` to observe the sfp state as follows:

``` sh
si@ubuntu:target/opalkelly-xem8350$ pushd host
si@ubuntu:target/opalkelly-xem8350/host$ python3 -m common.sfp monitor --device xem_i2c
Connected to device Opal Kelly XEM8320 with serial 0123456789!
Connected to the following SFP module:

Vendor:		OEM
OUI:		0x009065
Rev:		A
PN:		SFP-10G-LR
SN:		01234567890
DC:		012345
Type:		SFPSFPP (0x03)
Connector:	LC (0x07)
Bitrate:	10300 MBd
Wavelength:	1310 nm
		        SM    OM1    OM1    OM3    OM4
Max length:	   10000 m    0 m    0 m    0 m    0 m


Diagnostics:
                             VAL      +ER      +WR      -WR      -ER
  temp         (degC) :   22.137   80.000   70.000   -5.000  -15.000
  vcc             (V) :    3.253    3.630    3.465    3.135    2.970
  tx_bias        (mA) :   24.000  110.000  100.000   10.000    5.000
  tx_power       (mW) :    0.551    1.778    1.122    0.151    0.096
  rx_power       (mW) :    0.000    1.778    1.122    0.036    0.023
  laser_temp   (degC) :   -0.004    0.000    0.000    0.000    0.000
  tec            (mA) :   -0.100    0.000    0.000    0.000    0.000
```

The on-board LEDs serve three functions: D1 and D2 represent the state of
channel 1 and 2 on the TimeTagger, D3-D5 are the upper bits of the count of
received tags. D6 gets set when the time between two events on Channel 1 exceeds
the usual range of the default TimeTagger test signal, ensuring that tags are
received correctly.

The tag time difference detector can also be accessed via wishbone:

``` sh
si@ubuntu:target/opalkelly-xem8350$ pushd host
si@ubuntu:target/opalkelly-xem8350/host$ python3
>> import ok
>>> xem = ok.FrontPanel()
>>> xem.OpenBySerial()
0
>>> import common.xem_wishbone
>>> wb = common.xem_wishbone.XEMWishbone(xem)
>>> user = 0b1010010 << 8
>>> wb.read(user + 0)
1
>>> wb.write(user + 4, 0x1) # Reset the state of the tag time difference detector
>>> wb.write(user + 4, 0x0)
```

The tag time difference detector contains the following registers:

| Address | Name                | Purpose                                                                               |
| ------- | ------------------- | ------------------------------------------------------------------------------------- |
|       0 | Presence Indicator  | Reads one, for detecting presence of this module                                      |
|       4 | user_control        | If a non-zero is written, the status is held in reset                                 |
|       8 | channel_select      | Determines which channel to monitor (default: 0)                                      |
|      12 | lower_bound         | The lower bound of the expected interval (default: 0x19000)                           |
|      16 | upper_bound         | The upper bound of the expected interval (default: 0x20000)                           |
|      20 | failed_time         | The failing time in 1/3 ps. The upper bit is set if the value is valid                |

## Building your own design

To modify this reference design for your own purposes, please take a look at
`hdl/user_sample.sv` in the top level directory.

The incoming data is converted with the `si_tag_converter` module, that
computes the `tagtime` in 1/3 ps, the channel and the rising/falling edge for
each event. The output should only be sampled if `valid tag` is set.

The code below the `si_tag_converter` module instantiation is part of the sample
design and can be removed if so desired.
