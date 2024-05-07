# Time Tagger FPGA Link Reference Design

This repository contains a customer reference design for the Time Tagger FPGA
link. It can be used to test the Time Tagger's FPGA link interfaces and serve as
a basis for custom designs which make use of the interfaces' high Time Tag
output data rate.

## Supported Devices

Supported Time Tagger devices:

- Time Tagger X
  - using the SFP+ 10Gbit/s Ethernet interface
  - using the QSFP+ 40Gbit/s Ethernet interface

Supported reference design boards:

- [OpalKelly XEM8320](./target/opalkelly-xem8320) ([Vendor Website](https://opalkelly.com/products/xem8320/))
  - features a Xilinx UltraScale+ XCAU25P FPGA
  - two SFP+ receptacles onboard
  - Xilinx Vivado WebPack device, no paid license key required for 10Gbit/s Ethernet operation

More information on the individual supported boards and setup guides are
contained within the respective board target directories.

## Measurement Features

This reference design contains the following measurement features:

### Histogram

The Histogram module enables the processing of time tags received from the Time Tagger X effectively. It is designed to measure the time differences between events in two distinct channels. The calculated time differences are then presented in a histogram, offering valuable insights into the distribution of these time differences. The resulting data can be transmitted to a PC for further analysis or be analyzed inside the FPGA using another module. Additionally, for users intending to process the histogram data within the FPGA, the Histogram module provides these statistics: weighted means, index of the bin with the largest value, and variance.

### Counter

The Counter module is designed to measure the number of tags received in each channel continuously. Time Tagger X, equipped with multiple input channels, detects events on each channel independently. The event times are then organized into time tags and transmitted to the FPGA module containing the Counter module. This module reports the number of tags for each channel within defined intervals, offering a quantitative measure of event occurrences over time. This periodic information is valuable for understanding the activity levels in individual channels.

For detailed information on the usage and configuration of the modules, refer to the their documentation:

- [Histogram Module Documentation](histogram.md)
- [Counter Module Documentation](counter.md)

## Simulation Features

This project comprises a toolbox designed for convenient simulation of measurements. The [`tb_timeTagGenerator.sv`](./tb/tb_timeTagGenerator.sv) module encapsulates the complete functionality of the Time Tagger X and the recipient aspect of this reference design. Thus, the physical inputs of the Time Tagger can be simulated, for instance, using System Verilog delay statements. This facilitates rapid development of new measurements.

All measurements can be simulated with a nearly realistic dataset:

- The Histogram measurement is assessed through a fluorescence lifetime experiment.
- The Counter measurement is assessed via a dynamic light scattering experiment.
- The Combination measurement is assessed using a boson sampling experiment.

For a simpler demonstration of how to utilize the simulation toolbox, please refer to [`tb_user_sample.sv`](./tb/tb_user_sample.sv).

## Getting started

First up, clone the reference design repository:

``` sh
$ git clone --recursive https://github.com/swabianinstruments/TimeTagger-FPGALink-Reference.git
```

We recommend using the OpalKelly XEM8320 for development. Please follow the direction in the
[target README](./target/opalkelly-xem8320/README.md) for getting started with this target.

## Roadmap

This repository contains a work-in-progress, we're planning on implementing the following functionality:
- Retransmission support for recovering from packet losses, storing partial packets in the attached DDR3 RAM
- Softcore for IP management and various other tasks

## Pre-commit hook

To ensure that your contributions pass our internal formatting CI, you can add the following hook:

``` sh
ln -s ../../.pre-commit-hook.sh .git/hooks/pre-commit
```

## License and Disclaimer

Unless indicated otherwise, all files contained in this repository are licensed
under the terms and conditions of the BSD 3-Clause license, provided in
[`LICENSE.txt`](./LICENSE.txt) or available online under the following URL:
<https://opensource.org/licenses/BSD-3-Clause>

All trademarks are property of their respective owners.
