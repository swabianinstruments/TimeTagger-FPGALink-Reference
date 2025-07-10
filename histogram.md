# FPGA Histogram Module Interaction Guide

Welcome to the documentation for interfacing with the FPGA Histogram Module, dedicated to calculating time differences between events in two distinct channels and organizing the results into a histogram. Within this module, we specifically compute the time difference of tags received over `click_channel` and the last received time tag over `start_channel`. In the event of receiving a time tag over the `start_channel`, subsequent calculations are based on the most recent time tag received over that `start_channel`. This fundamental process forms the basis for generating informative histogram based on temporal relationships between events in the specified channels.

Interaction with the histogram module within the FPGA can be achieved through two methods:

- Using the provided Python class [`histogram.py`](./host/histogram.py).
- Utilizing a custom FPGA module of your own.

During bitstream generation, only one of these options is synthesized. It's important to note that, for the provided bitstreams, access to the histogram is available through the Python script. If your intention is to process the histogram data inside the PC, you should do it using the provided Python class, which will be discussed in the following sections.


On the other hand, if your goal is to process the histogram data within the FPGA, you should set the `WISHBONE_INTERFACE_EN` parameter of [`histogram.sv`](./hdl/histogram/histogram.sv) to **zero** during the instantiation. You should also transmit the appropriate configuration from your module to the histogram module. For further information on how to interface with the module, please refer to the detailed information provided inside the [`histogram.sv`](./hdl/histogram/histogram.sv) and [`histogram.sv`](./hdl/histogram/histogram.sv) files. It's noteworthy that if you choose to interface with the histogram module using your own module, you will also receive statistics such as weighted means, the index of the bin with the largest value, and variance.

The following sections will guide you through interacting with the histogram module using the dedicated class.

## Initialization
To initiate the use of the Histogram module, start by downloading the **target** bitstream into the FPGA. Following this, create a Wishbone and Histogram instance:
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
>>> import common.histogram as HIST
>>> histogram = HIST.Histogram(wb)
```


## Configuration
Configure the Histogram module by setting the `start_channel` and `click_channel` using the `set_config` method. The method takes three parameters:

- `start_channel`: The start channel for the measurement.
- `click_channel`: The click channel for the measurement.
- `shift` (optional): Shift value for scaling the resolution. Default is 0.

``` sh
>>> histogram.set_config(start_channel=1, click_channel=2, shift=5)
```

Please note that the FPGA histogram has a size of 4096 with a bin resolution of 1/3 ps. The `shift` parameter is employed to scale the bin resolution by a factor of $2^{shift}$. For example, setting the shift parameter to 5 would result in a resolution of each bin being $\frac{32}{3}$ ps.

NOTE:

- The last bin count contains all events otherwise exceeding the FPGA histogram size.


## Reading Data

During runtime, the Histogram module allows you to read the histogram information using the `read_data` method. After calling this method, you can access the result through the `data_array` attribute. The method also takes an optional `reset` parameter, which is `False` by default. If set to `True`, it terminates the measurement for the current configuration.

``` sh
>>> histogram.read_data()
>>> result_data = histogram.data_array
```
If reset is set to `True`, the measurement for the current configuration is terminated, and you can set a new configuration for the next measurement.

## Accessing Previous Configuration Results
If a new configuration is set without terminating the previous measurement, the result of the previous configuration is stored in the `prev_data_array` attribute. This allows you to access the final result of the last measurement while the next one has started.

``` sh
>>> previous_results = histogram.prev_data_array
```
## Resetting FPGA Histogram module
When you instantiate a Histogram object, it automatically initiates the reset of the FPGA Histogram Module. Additionally, you have the option to reset this module during runtime by utilizing the `reset_FPGA_module()` method.
``` sh
>>> histogram.reset_FPGA_module()
```
## Adding Another Histogram Module
To add another instantiation of the Histogram module to the FPGA project, follow these steps:

- Define a `base_address` in the FPGA project for the new module.
- Assign the `base_address` parameter during the creation of the object for the new Histogram.

To integrate another histogram module into the FPGA project, make sure to connect the correct Wishbone interface to your Histogram module in the FPGA. The provided Python class checks for the correct module connection during initialization. Please note that you can find instructions regarding adding a new module in each target README.
