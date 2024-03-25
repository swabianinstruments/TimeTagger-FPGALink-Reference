# FPGA Counter Module Interaction Guide

The FPGA counter module documentation provides a detailed overview of its interfacing and functionalities. This module is instrumental in quantifying event occurrences across the channels of the Time Tagger X. Engineered for continuous measurement, it offers valuable insights into the activity levels observed within each input channel. It utilizes a virtual channel system, capable of combining various input channels from the Time Tagger X into a maximum of 16 virtual channels for analysis. Detailed insights into the utilization of this capability will be provided in the subsequent sections.

Interaction with the counter module within the FPGA can be achieved through two methods:

- Using the provided Python class [`counter.py`](./host/counter.py).
- Utilizing a custom FPGA module of your own.

During bitstream generation, only one of these options is synthesized. It's important to note that, for the provided bitstreams, access to the counter is available through the Python script. If your intention is to process the counter data inside the PC, you should do it using the provided Python class, which will be discussed in the following sections.


On the other hand, if your goal is to process the counter data within the FPGA, you should set the `WISHBONE_INTERFACE_EN` parameter of [`counter_wrapper.sv`](./hdl/counter_wrapper.sv) to **zero** during the instantiation. You should also transmit the appropriate configuration from your module to the counter module. For further information on how to interface with the module, please refer to the detailed information provided inside the [`countrate.sv`](./hdl/countrate.sv) and [`counter_wrapper.sv`](./hdl/counter_wrapper.sv) files.

The following sections will guide you through interacting with the FPGA counter module using the dedicated class.

## Initialization
To initiate the use of the counter module, start by downloading the **target** bitstream into the FPGA. Following this, create a Wishbone and Counter instance:
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
>>> import common.counter as CNT
>>> counter = CNT.Counter(wb)
```

It should be noted that the second argument of the `counter` object constructor is `capture_size`, which defaults to 10000. This parameter determines the size of captured data for each channel. If more data is received over time, the old data will be replaced by the new data. Therefore, please specify your desired `capture_size` when creating the object.

## Configuration

### Configuring the Counter Module

The `set_lut_channels` method allows you to define how the counter module combines input channels from the Time Tagger X system. It takes a Python dictionary as input, where:

- **Keys**: Represent virtual channels within the Counter FPGA module (range: 0 to number of desired channels - 1).
- **Values**: Specify the input channel(s) from the Time Tagger X to be combined into a single virtual channel.

### Configuration Requirements:

- **Unique Channel IDs**: Keys in the dictionary must be unique and within the valid range (0 to 15, for a maximum of 16 channels).
- **Consecutive Keys**: Keys should be specified in consecutive order. For example, for 6 virtual channels, keys must range from 0 to 5.

### Example Configuration:

``` sh
>>> channels = {
...    0: list(range(1, 4)),   # Combine channels 1, 2, and 3 from Time Tagger X
...    1: [6, 7],              # Combine channels 6 and 7 from Time Tagger X
...    2: -5,                  # Use channel -5 from Time Tagger X directly
...    3: [-8, 8],             # Combine channels -8 and 8 from Time Tagger X
...    4: 10,                  # Use channel 10 from Time Tagger X directly
...    5: 12                   # Use channel 12 from Time Tagger X directly
... }

>>> counter.set_lut_channels(channels)
>>> print(counter.get_lut_channels())  # Verify the configuration

```

In this configuration, channel inputs 1 to 3 from the Time Tagger X are combined to form virtual channel 0 in the counter module. Similarly, other channel mappings are defined.

### Default Configuration:

If you don't provide any configuration (`counter.set_lut_channels()`), channels 1 to 16 from the Time Tagger X are automatically mapped to virtual channels 0 to 15 in the counter module, utilizing all available virtual channels.

### Window Size:

The `set_window_size` method defines the size of the windows used for counting events within the specified channels. The window size is specified in units of 1/3 picoseconds (ps). For example, `counter.set_window_size(3000000000)` sets the window size to 1 millisecond (ms).

``` sh
>>> counter.set_window_size(3000000000) # Configure a window size of 1 millisecond
```

## Start Measurement
Once you've configured the desired channels and window size, you can initiate the measurement process using the `start_measurement` method.

``` sh
>>> counter.start_measurement()
```

## Reading Data

### Data Acquisition and FIFO Management

As previously mentioned, the FPGA counter module continuously accumulates counts for each channel within user-defined intervals determined by the window size. An internal `FIFO` within the FPGA acts as a buffer, capable of storing up to 8,192 (8K) counter values. All calculated counts are stored in this `FIFO` for retrieval.

The `read_data` method provides access to this data. By calling this method, you can access the latest counter values through the `data_array` attribute. This `data_array` is a two-dimensional array where each row represents a virtual channel.

``` sh
>>> counter.read_data()
```

### Importance of Regular Data Readout

To ensure you capture all data, it's crucial to call the `read_data` method regularly to empty the `FIFO`. The data rate at which you read data from the FPGA should ideally be higher than the data rate at which the FPGA counter module generates data.

### Handling Readout Rates

Both the FPGA and the provided Python class can accommodate scenarios where your readout rate differs from the counter module's output rate.

- **Slower Readout**: If your data readout rate is slower than the module's data generation rate, the `FIFO` will eventually overflow, leading to data loss. In such cases, the FPGA will inform the PC about the number of missed counts during the next data readout. The Counter Python class will then populate the corresponding locations in the `data_array` with `"NaN"` (Not a Number) values to indicate missing data.

- **Faster Readout**: Conversely, if you call `read_data` too frequently (faster than the module's output rate), the `FIFO` might become empty before you attempt to read the expected number of samples. In this case, the FPGA will send dummy data, which the Python method will discard.

### Recommendation for Optimal Data Acquisition

To maximize efficiency and avoid wasting readback bandwidth, it's highly recommended to configure your data readout rate to be slightly higher than the FPGA counter module's data rate.

### Example Scenario

Consider a scenario where you have 6 virtual channels and a window size of 1 millisecond (ms). With this configuration, the `FIFO` will approach its full capacity after approximately 1.365 seconds. Therefore, for this specific case, it's recommended to call the read_data method at least every second to ensure timely data retrieval and prevent data loss.

## Initiating New Measurement
To start a new measurement:

- **Configure the measurement**: Set up the desired settings using the `set_lut_channels` method. This will reset the FPGA counter module and clear any previously captured data.
- **Set the window size**: Define the timeframe for your measurement by specifying the window size.
- **Start the measurement**: Once configured, initiate the measurement process by calling the `start_measurement` method.

## Resetting FPGA Counter module
When you instantiate a Counter object, it automatically initiates the reset of the FPGA counter module. Additionally, you have the option to reset this module during runtime by utilizing the `reset_FPGA_module()` method.
``` sh
>>> counter.reset_FPGA_module()
```
## Adding Another Counter Module
To add another instantiation of the counter module to the FPGA project, follow these steps:

- Define a `base_address` in the FPGA project for the new module.
- Assign the `base_address` parameter during the creation of the object for the new Counter.

To integrate another counter module into the FPGA project, make sure to connect the correct Wishbone interface to your counter module in the FPGA. The provided Python class checks for the correct module connection during initialization. Please note that you can find instructions regarding adding a new module in each target README.
