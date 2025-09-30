# Software Switch Performance Testbed

## HOL4P4, BMv2 Setup

Follow the regular installation instructions.

## DPDK Setup

Clone the [kth-step fork](https://github.com/kth-step/Pktgen-DPDK) of Pktgen-DPDK, check out the `for_hol4p4` branch and follow the regular installation instructions.

Setup hugepages on every startup:

```bash
sudo python3 dpdk-hugepages.py -p 1G --setup 2G
```

Then run e.g.

```bash
sudo ./test_hol4p4.sh
```
  
while ensuring the configuration parameters of the script is what you want.

## petr4 Setup

Clone the regular `petr4` repository and check out the `mininet-interface` branch, first install as usual.

The `mininet-interface` branch requires also to do

```bash
opam install rawlink-lwt cohttp-lwt-unix hex
```

on top of regular installation instructions, as well as changing `rawlink.lwt` to `rawlink-lwt` in the `bin/dune` file.

After `make`, the a symlink will be located at `./_build/install/default/bin/petr4`. It doesn't seem to replace the existing one, that requires `make install`.

Run the switch by running something like

```bash
sudo petr4 switch -i 0@s1-eth1 -i 1@s1-eth2 -I p4include conditional.p4
```

Note, this needs the virtual network to be set up (`s1-eth1`, `s1-eth2`).
