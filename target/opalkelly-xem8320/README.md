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
project has been tested to work with Vivado 2023.2 on an Ubuntu 22.04
Workstation installation. First up, generate some verilog sources by executing `make` in the root directory like so:

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
si@ubuntu:target/opalkelly-xem8320$ make project
vivado -mode tcl -source scripts/create_project.tcl

****** Vivado v2023.2 (64-bit)
  **** SW Build 3865809 on Sun May  7 15:04:56 MDT 2023
  **** IP Build 3864474 on Sun May  7 20:36:21 MDT 2023
  **** SharedData Build 3865790 on Sun May 07 13:33:03 MDT 2023
    ** Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
    ** Copyright 2022-2023 Advanced Micro Devices, Inc. All Rights Reserved.

[... output suppressed ...]

# current_run -implementation [get_runs impl_1]
# puts "Successfully created project ${project_name}!"
Successfully created project xem8320-timetagger-fpgalink-reference!
# exit
INFO: [Common 17-206] Exiting Vivado [..]
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

To use the SFP+ modules and the onboard LEDs, the
[VIO1](https://docs.opalkelly.com/xem8320/leds/) &
[VIO2](https://docs.opalkelly.com/xem8320/gigabit-transceivers/) voltages need to
be enabled without a SYZYGY module connected. This project includes a script to
configure the voltage rails accordingly in SmartVIO hybrid mode. This script
must be executed from within the `host` subdirectory, as illustrated below:

``` sh
si@ubuntu:target/opalkelly-xem8320$ pushd host
si@ubuntu:target/opalkelly-xem8320/host$ python -m device_settings configure
Connected to device Opal Kelly XEM8320 with serial 0123456789!
         Product: XEM8320-AU25P
Firmware version: 1.39
   Serial Number: 0123456789
       Device ID: Opal Kelly XEM8320
Setting XEM8320_SMARTVIO_MODE to 0x01
Setting XEM8320_VIO1_VOLTAGE to 120
Setting XEM8320_VIO2_VOLTAGE to 330
Saved settings.
si@ubuntu:target/opalkelly-xem8320/host$ popd
```

These settings are only applied after a power-cycle of the XEM8320-board.

With a connected TTX with FPGA-Link Output enabled, you can now enable Channel 1
capture and observe the LED on the XEM8320 matching the input state of the TTX.

## Debug Information

The design exposes various statistics of the received tags over the OpalKelly
USB interface, which bridges onto an internal Wishbone Bus. This can be read with the following

``` sh

si@ubuntu:target/opalkelly-xem8320$ pushd host
si@ubuntu:target/opalkelly-xem8320/host$ python3 -m common.statistics
Connected to device Opal Kelly XEM8320 with serial 0123456789!
Diagnostics:
                                                          VAL
  packet_rate                          (Packets/s) :           366212
  word_rate                    (Words (128 bit)/s) :        148160066
  tag_rate                                (Tags/s) :        592640264
  received_packets                       (Packets) :        347321811
  received_words                 (Words (128 bit)) :     140517303310
  received_tags                             (Tags) :     562069718688
  size_of_last_packet     (Words (128 bit)/Packet) :              248
  packet_loss                               (bool) :                0
  invalid_packets                        (Packets) :                0
  overflowed                                 (int) :                0
  missed_tags_in_TTX                        (Tags) :                0
si@ubuntu:target/opalkelly-xem8320/host$ popd
```

You can also use `sfp.py` inside `../../host/` to observe the sfp state as follows:

``` sh
si@ubuntu:target/opalkelly-xem8320$ pushd host
si@ubuntu:target/opalkelly-xem8320/host$ python3 -m common.sfp monitor --device xem_i2c
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
si@ubuntu:target/opalkelly-xem8320$ pushd host
si@ubuntu:target/opalkelly-xem8320/host$ python3
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

If you plan to integrate your own modules into the reference design, it is strongly advised to integrate them into the [`measurement.sv`](./../../hdl/measurement.sv) module. Below is a description of some inputs of the [`measurement.sv`](./../../hdl/measurement.sv) module to which you can connect your modules. These inputs are part of of `s_axis` interface.

- **`s_axis.tagtime`**: This input signal provides the timestamp of the tags with a resolution of 1/3 picoseconds. The parameter `s_axis.WORD_WIDTH` specifies the number of tagtimes available simultaneously.
- **`s_axis.channel`**: This input signal indicates the channels associated with the tags. The channel number can range from 1 to 18 for events captured on their rising edge in the Time Tagger X, and from -18 to -1 for events captured on their falling edge in the Time Tagger X.
- **`s_axis.tvalid`**: This signal is asserted to indicate the presence of at least one valid tagtime in a clock cycle.
- **`s_axis.tkeep`**: This signal, with a width of `s_axis.WORD_WIDTH`, indicates the validity of each tagtime and its corresponding channel number through individual bits.

- **`s_axis.lowest_time_bound`**: This signal retains the previous time value. In addition to providing time information for tags, Time Tagger X can transmit supplementary data enabling the reference design to update the time information. Please note that this information is considered valid within a clock cycle only if there is no valid tag time at that particular clock cycle. In such cases, the `s_axis.tvalid` signal should be zero. Otherwise, `s_axis.tagtime` can be used instead.

Be sure to minimize alterations to the remainder of the reference design to facilitate seamless integration of future updates.

We recommend testing any modifications to the measurements using an appropriate simulation testbench. Please utilize the [`tb_timeTagGenerator.sv`](./../../tb/tb_timeTagGenerator.sv) module to generate signals for the AXI-Stream of time tags.

### Defining FPGA Module Parameters for Wishbone Interface

To effectively communicate with your FPGA modules from a PC via the Wishbone interface, it's crucial to properly define parameters within the [`ref_design_pkg.sv`](./../../hdl/ref_design_pkg.sv) file. The package inside this file, named `pkg_base_address`, houses the necessary parameters for connecting modules to the Wishbone interface. Note that you can refer to the predefined parameters for modules like `histogram.sv` or `counter.sv`, as well as the established connections with Wishbone interfaces.

Follow these steps to define parameters for each module:

- **Define Base Address**: Select a unique base address for your module, ensuring it doesn't conflict with addresses assigned to other modules. Include this base address in the `base_address` local parameter.

- **Specify Memory Size**: Determine a suitable memory size for your module, ensuring it is a power of two. This size should accommodate the required registers within the memory space. Incorporate the memory size into the `memory_space` local parameter.

- **Assign Module Name**: Select a distinct name for your module, avoiding exact matches with any signals or modules instantiated within the top module. Add this name into `wb_instances`. This name serves as an identifier for the location of the corresponding base address and memory size within the `base_address` and `memory_space` parameters. This facilitates the proper connection of the Wishbone interface to your module.

Within `pkg_base_address`, ensure consistency in parameter organization. All parameters—base address, memory size, and module name—should occupy the same position within their respective definitions.

To establish the appropriate Wishbone interface for your module, utilize `wb_array[your_module_name]` within the top module [`xem8320_reference.sv`](./hdl/xem8320_reference.sv), where `your_module_name` corresponds to the name defined in the `base-address` package. Refer to [`xem8320_reference.sv`](./hdl/xem8320_reference.sv), and [`measurement.sv`](./../../hdl/measurement.sv) modules to understand how to connect this interface to your module effectively.
