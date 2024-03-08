# OpalKelly XEM8320 QSFP Time Tagger FPGA Link Reference Project

This directory and its subdirectories constitute a reference design for the Time
Tagger FPGA Link on the OpalKelly XEM8320 FPGA board with a SZG-QSFP Module on
port E. It implements the 40Gbit/s Ethernet Time Tagger FPGA link interfaces.

## Getting Started

Building this project requires a recent Version of Vivado. The FPGA is supported
by the Standard Version, but a Xilinx `EF-DI-LAUI-SITE` IP core license is
required.  The project has been tested to work with Vivado 2023.1 on an Ubuntu
22.04 Workstation installation. First up, generate some verilog sources by
executing `make` in the root directory like so:

``` sh
si@ubuntu:$ make
mkdir -p gen_srcs/
python3 -m venv gen_srcs/pyenv/

[... output suppressed ...]

Successfully installed bitarray-2.5.1 galois-0.0.29 llvmlite-0.38.1 numba-0.55.2 numpy-1.21.6 typing-extensions-4.2.0
```

Assuming Vivado and all required tools are installed,
the Xilinx Vivado project can then be created by running:

```
si@ubuntu:target/opalkelly-xem8320-qsfp$ make project
vivado -mode tcl -source scripts/create_project.tcl
****** Vivado v2023.1 (64-bit)
  **** SW Build 3865809 on Sun May  7 15:04:56 MDT 2023
  **** IP Build 3864474 on Sun May  7 20:36:21 MDT 2023
  **** SharedData Build 3865790 on Sun May 07 13:33:03 MDT 2023
    ** Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
    ** Copyright 2022-2023 Advanced Micro Devices, Inc. All Rights Reserved.

[... output suppressed ...]

# current_run -implementation [get_runs impl_1]
# puts "Successfully created project ${project_name}!"
Successfully created project xem8320-qsfp-timetagger-fpgalink-reference!
# exit
INFO: [Common 17-206] Exiting Vivado [..]
```

The FPGA bitstream can be built from within Vivado by opening the generated
project file (`xem8320-qsfp-timetagger-fpgalink-reference.xpr`), or by running `make
all` instead of `make project`. It will be located under
`xem8320-qsfp-timetagger-fpgalink-reference.runs/impl_1/xem8320_reference_qsfp.bit`.

Once built, the bitstream can be programmed onto the FPGA either via a
compatible JTAG-adapter (such as the Xilinx Platform Cable II), or using the
integrated USB controller through the OpalKelly FrontPanel SDK. For support on
how to install the OpalKelly FrontPanel SDK, please visit the OpalKelly
website. With the SDK installed, the FPGA can be configured either via the
FrontPanel Application or from within a Python 3 environment as shown:
```
si@ubuntu:target/opalkelly-xem8320-qsfp$ python3
>>> import ok
>>> xem = ok.FrontPanel()
>>> xem.OpenBySerial()
0
>>> xem.ConfigureFPGA("xem8320-qsfp-timetagger-fpgalink-reference.runs/impl_1/xem8320_reference_qsfp.bit")
0
```

To use the onboard LEDs, the [VIO1](https://docs.opalkelly.com/xem8320/leds/)
voltage needs to be enabled without a SYZYGY module connected. This project
includes a script to configure the voltage rails accordingly in SmartVIO hybrid
mode. This script must be executed from within the `host` subdirectory, as
illustrated below:

``` sh
si@ubuntu:target/opalkelly-xem8320-qsfp$ pushd host
si@ubuntu:target/opalkelly-xem8320-qsfp/host$ python -m device_settings configure
Connected to device Opal Kelly XEM8320 with serial 0123456789!
         Product: XEM8320-AU25P
Firmware version: 1.39
   Serial Number: 0123456789
       Device ID: Opal Kelly XEM8320
Setting XEM8320_SMARTVIO_MODE to 0x01
Setting XEM8320_VIO1_VOLTAGE to 120
Setting XEM8320_VIO2_VOLTAGE to 330
Saved settings.
si@ubuntu:target/opalkelly-xem8320-qsfp/host$ popd
```

These settings are only applied after a power-cycle of the XEM8320-board.

With a connected TTX with FPGA-Link Output for QSFP enabled, you can now enable Channel 1
capture and observe the LED on the XEM8320 matching the input state of the TTX.

## Debug Information

The design exposes various statistics of the received tags over the OpalKelly
USB interface, which bridges onto an internal Wishbone Bus. This can be read with the following

``` sh

si@ubuntu:target/opalkelly-xem8320-qsfp$ pushd host
si@ubuntu:target/opalkelly-xem8320-qsfp/host$ python3 -m common.statistics
Connected to device Opal Kelly XEM8320 with serial 0123456789!
Diagnostics:
                                                          VAL
  packet_rate                          (Packets/s) :   183095
  word_rate                    (Words (128 bit)/s) :   549285
  received_packets                       (Packets) :   876845
  received_words                 (Words (128 bit)) :  2630819
  size_of_last_packet     (Words (128 bit)/Packet) :        3
  packet_loss                               (bool) :        0
  invalid_packets                        (Packets) :        0
si@ubuntu:target/opalkelly-xem8320-qsfp/host$ popd
```

You can also use `sfp.py` inside `../../host/` to observe the sfp state as follows:

``` sh
si@ubuntu:target/opalkelly-xem8320-qsfp$ pushd host
si@ubuntu:target/opalkelly-xem8320-qsfp/host$ python3 -m common.sfp monitor --device xem_i2c
Connected to device Opal Kelly XEM8320 with serial 0123456789!
Connected to the following SFP module:

Vendor:  OEM
OUI:  0x009065
Rev:  A
PN:  SFP-10G-LR
SN:  01234567890
DC:  012345
Type:  SFPSFPP (0x03)
Connector: LC (0x07)
Bitrate: 10300 MBd
Wavelength: 1310 nm
          SM    OM1    OM1    OM3    OM4
Max length:    10000 m    0 m    0 m    0 m    0 m


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
si@ubuntu:target/opalkelly-xem8320-qsfp$ pushd host
si@ubuntu:target/opalkelly-xem8320-qsfp/host$ python3
>> import ok
>>> xem = ok.FrontPanel()
>>> xem.OpenBySerial()
0
>>> import common.ok_wishbone
>>> wb = common.ok_wishbone.Wishbone(xem)
>>> user = 0x80005200
>>> wb.read(user + 0)
1
>>> wb.write(user + 8, 0x1) # Reset the state of the tag time difference detector
>>> wb.write(user + 8, 0x0)
```

The tag time difference detector contains the following registers:

| Address | Name                | Purpose                                                                               |
| ------- | ------------------- | ------------------------------------------------------------------------------------- |
|       0 | Presence Indicator  | Reads one, for detecting presence of this module                                      |
|       8 | user_control        | If a non-zero is written, the status is held in reset                                 |
|      12 | channel_select      | Determines which channel to monitor (default: 1)                                      |
|      16 | lower_bound         | The lower bound of the expected interval (default: 0x660000, 64bit)                   |
|      24 | upper_bound         | The upper bound of the expected interval (default: 0x680000, 64bit)                   |
|      32 | failed_time         | The failing time in 1/3 ps. The upper bit is set if the value is valid (64bit)        |

## Building your own design

*The reference design and the on-the-wire format are not stable and will be subject to incompatible changes with further development*

To modify this reference design for your own purposes, please take a look at
`hdl/user_sample.sv` in the top level directory.

The user sample file receives the `tagtime`s in 1/3 ps, the `channel`s (zero indexed) and the rising/falling edge for
each event. The input should only be sampled when `s_axis_tvalid` is set and only for the word where the corresponding `s_axis_tkeep` bit is set

The code inside the user sample is only there for demonstration purposes and can
be removed if so desired. Avoid modifying the rest of the reference design as
much as possible so future changes can be easily incorporated.
