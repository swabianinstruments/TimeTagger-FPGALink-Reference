# FPGA Combinations Module Interaction Guide

Combinations module is tailored to identify and record different sets of events occurring on distinct virtual channels. It processes events detected by Time Tagger X across up to 16 virtual channels. Each virtual channel can denote either a single channel or multiple channels on Time Tagger X. Specifically, a potential combination is identified when an event occurs in a channel with no events for at least one defined guard time before it. The module collects all timestamps within the specified time window from the first event. Virtual channels corresponding to these timestamps are considered as potential combination members. The combination is verified if no additional events are detected in an extra guard time from the last timestamp.

The user can access either the identified combinations or their corresponding calculated histogram. To achieve this, two dedicated memories are used inside the FPGA. One memory functions as a FIFO, capable of storing up to 8,192 (8K) identified combinations. Each virtual channel is represented by a single bit in the 16 least significant bits (LSB), indicating whether events have occurred on that virtual channel. For instance, in a setup with 16 virtual channels, a combination like `0x8023` would indicate events on virtual channels 1, 2, 6, and 16. Overflow occurrence is reported via the remaining most significant bits (MSB). To prevent FIFO overflow and data loss, the read-out data rate must exceed the rate at which combinations are identified. The Combinations module is equipped with a filter to define the minimum and maximum number of events in a combination, which can help manage overflow. The second Memory inside the Combinations module stores the number of times each combination has been identified as a histogram. With a depth of $2^{16}$, it can store histogram information for combinations of up to 16 virtual channels. Each bin in this histogram is 32 bits in size. Reading the histogram data in a timely manner is essential to ensure that no overflow occurs in any bin.

The Combinations module can be controlled and accessed by a PC using USB 3.0 or by another module in the FPGA (standalone) as following. However, only one mode can be operational at a time, requiring a new bitfile to switch between modes.
A Python class [`combinations.py`](./host/combinations.py) is provided for the PC based usage. If analyzing the combinations data on the PC is required, it is recommended to make use of the Python class provided, with more details to follow in the upcoming sections.

For further information on how to interface with the module, please refer to the detailed information provided inside the [`combination.sv`](./hdl/combination/combination.sv).

The following sections will guide you through interacting with the FPGA Combinations module using the dedicated class.

## Bitfile generation

Setting `WISHBONE_INTERFACE_EN` in the RTL design [`combination.sv`](./hdl/combination/combination.sv) will generate the PC-based mode, while resetting it will produce the standalone mode. Since this python class interacts via USB, please ensure that your bitfile is generated with `WISHBONE_INTERFACE_EN = 1`. The bitfiles in the git repository are generated in this mode.

## Initialization

To initiate the use of the Combinations module, start by downloading the **target** bitstream into the FPGA. Following this, create a Wishbone and Combinations instance:

``` sh
si@ubuntu:$ pushd target/opalkelly-xem8320/host
si@ubuntu:target/opalkelly-xem8320/host$ python3
>>> import ok
>>> xem = ok.FrontPanel()
>>> xem.OpenBySerial()
0
>>> xem.ConfigureFPGA("../../../xem8320_reference.bit")
0
>>> import common.ok_wishbone as WB
>>> wb = WB.Wishbone(xem)
>>> import common.combinations as COMB
>>> combinations = COMB.Combinations(wb)
```

## Configuration

To ensure the correct configuration of the Combinations, configure the channel selector, window, filter, and readout mode as follows.

### Configuring the channel selector

The `set_lut_channels` method allows you to define how the Combinations module combines input channels from the Time Tagger X system. It takes a Python dictionary as input, where:

- **Keys**: Represent virtual channels within the Combinations FPGA module (range: 0 to number of desired channels - 1).
- **Values**: Specify the input channel(s) from the Time Tagger X to be combined into a single virtual channel.

#### Configuration Requirements

- **Unique Channel IDs**: Keys in the dictionary must be unique and within the valid range (0 to 15, for a maximum of 16 channels).
- **Consecutive Keys**: Keys should be specified in consecutive order. For example, for 6 virtual channels, keys must range from 0 to 5.

#### Example Configuration of Channel Selector

``` sh
>>> channels = {
...    0: list(range(1, 4)),   # Combine channels 1, 2, and 3 from Time Tagger X
...    1: [6, 7],              # Combine channels 6 and 7 from Time Tagger X
...    2: -5,                  # Use channel -5 from Time Tagger X directly
...    3: [-8, 8],             # Combine channels -8 and 8 from Time Tagger X
...    4: 10,                  # Use channel 10 from Time Tagger X directly
...    5: 12                   # Use channel 12 from Time Tagger X directly
... }

>>> combinations.set_channel_selector(channels)
>>> print(combinations.get_lut_channels())  # Verify the configuration
```

In this configuration, channel inputs 1 to 4 from the Time Tagger X are combined to form virtual channel 0 in the Combinations module. Similarly, other channel mappings are defined.

#### Default Configuration

If you don't provide any configuration (`combinations.set_channel_selector()`), channels 1 to 16 from the Time Tagger X are automatically mapped to virtual channels 0 to 15 in the Combinations module.

### Configuring Window, Filter, and Readout Mode

The `set_config` method is used to set the `window` parameter, which represents the size of the combination window. This parameter is specified in units of 1/3 picoseconds (ps). The `set_config` method is also utilized to configure the filter parameters, `filter_max` and `filter_min`, which specify the maximum and minimum number of channels within a combination, respectively.

``` sh
>>> combinations.set_config(window = 300, filter_max = 5, filter_min = 3)
```

In this configuration, any 3, 4, or 5 virtual channels with events within the range of 100 ps is identified as a combination.

The next step involves selecting whether the intended data source is a histogram (`"histogram"`) or a stream of combinations (`"combination"`) by using the `select_data_source` method.

``` sh
>>> combinations.select_data_source("histogram")
```

## Capture Enable

To proceed, activate the `capture_enable` by invoking the `set_capture_enable` method. Setting it to **zero** will deactivate the capture, while any other value will result in the processing of received time tags.

``` sh
>>> combinations.set_capture_enable("True")
```

## Reading Combinations

Start reading from the Combinations module by passing `"True"` to `read_data` method as following.

``` sh
>>> combinations.read_data("True")
```

## Resetting FPGA Combinations module

A reset method`reset_FPGA_module` is available for users who wish to reset the entire Combinations module. When triggered, all processed combinations will be reset.

``` sh
>>> combination.reset_FPGA_module()
```

## Adding Another Combinations module

To add another instantiation of the Combinations module to the FPGA project, follow these steps:

- Define a `base_address` in the FPGA project for the new module.
- Assign the `base_address` parameter during the creation of the object for the new Combinations.

To integrate another Combinations module into the FPGA project, make sure to connect the correct Wishbone interface to your Combinations module in the FPGA. The provided Python class checks for the correct module connection during initialization. Please note that you can find instructions regarding adding a new module in each target README.
