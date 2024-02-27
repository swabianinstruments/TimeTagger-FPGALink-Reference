# Time Tagger FPGA Link Reference Design

This repository contains a customer reference design for the Time Tagger FPGA
link. It can be used to test the Time Tagger's FPGA link interfaces and serve as
a basis for custom designs which make use of the interfaces' high Time Tag
output data rate.

## Supported Devices

Supported Time Tagger devices:
- Time Tagger X
  - using the SFP+ 10Gbit/s Ethernet interface
  - using the QSFP+ 40Gbit/s Ethernet interface (TODO)

Supported reference design boards:
- [OpalKelly XEM8320](./target/opalkelly-xem8320) ([Vendor Website](https://opalkelly.com/products/xem8320/))
  - features a Xilinx UltraScale+ XCAU25P FPGA
  - two SFP+ receptacles onboard
  - Xilinx Vivado WebPack device, no paid license key required for 10Gbit/s Ethernet operation

More information on the individual supported boards and setup guides are
contained within the respective board target directories.

## Measurement Features
This reference design contains the following measurement feature:

### Histogram
The Histogram module enables the processing of time tags received from the Time Tagger X effectively. It is designed to measure the time differences between events in two distinct channels. The calculated time differences are then presented in a histogram, offering valuable insights into the distribution of these time differences. The resulting data can be transmitted to a PC for further analysis or be analyzed inside the FPGA using another module. Additionally, for users intending to process the histogram data within the FPGA, the Histogram module provides these statistics: weighted means, index of the bin with the largest value, and variance.

For detailed information on this module's usage and configuration, refer to the its documentation:

- [Histogram Module Documentation](histogram.md)


## Getting started

We recommend using the OpalKelly XEM8320. Please follow the direction in the
[target README](./target/opalkelly-xem8320/README.md) for getting started.

## Roadmap

This repository contains a work-in-progress, we're planning on implementing the following functionality:
- A TTX ethernet mode, removing the bandwidth limit to USB speeds (will be added in the TT release 2.17.0)
- Retransmission support for recovering from packet losses, storing partial packets in the attached DDR3 RAM
- 40GBit ethernet receiver and transmitter
- Internal TTX changes to support the full 40GBit bandwidth
- Softcore for IP management and various other tasks

## License and Disclaimer

Unless indicated otherwise, all files contained in this repository are licensed
under the terms and conditions of the BSD 3-Clause license, provided in
[`LICENSE.txt`](./LICENSE.txt) or available online under the following URL:
https://opensource.org/licenses/BSD-3-Clause

All trademarks are property of their respective owners.
