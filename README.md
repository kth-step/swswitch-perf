# Software Switch Performance Testbed

## HOL4P4, BMv2 Setup

Follow the regular installation instructions.

This repository has been tested with the `dev_hol4p4exe` branch of HOL4P4 and the `1.15.2` tag of [BMv2](https://github.com/p4lang/behavioral-model).

## DPDK, Pktgen-DPDK Setup

This repository has been tested with the `v26.03` tag of [DPDK](https://github.com/DPDK/dpdk) and the `pktgen-26.03.0` tag of [Pktgen-DPDK](https://github.com/pktgen/Pktgen-DPDK).

The Lua scripts can be found in the the [kth-step fork](https://github.com/kth-step/Pktgen-DPDK) of Pktgen-DPDK; check out the `for_hol4p4` branch and follow the regular installation instructions.

First, run the `setup_test_env.sh` script on every startup (after every boot). Note that you may have issues reserving hugepages if you don't run the script right after a fresh boot: you may also try to shrink the hugepage size.

Then run e.g.

```bash
sudo ./test_hol4p4.sh /home/my_user/src/Pktgen-DPDK/
```
  
while ensuring the configuration parameters and command-line arguments of the script is what you want.

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
