# Software Switch Performance Testbed

## Dependencies

This repository has been tested with
* [DPDK version 26.03.0](https://github.com/DPDK/dpdk/tree/v26.03)
* [Pktgen-DPDK version 26.03.0](https://github.com/pktgen/Pktgen-DPDK/tree/pktgen-26.03.0)
* [The `dev_hol4p4exe` branch of HOL4P4](https://github.com/kth-step/HOL4P4/tree/dev_hol4p4exe)
* [BMv2 version `1.15.2`](https://github.com/p4lang/behavioral-model/tree/1.15.2) (in order to compile programs for BMv2, you also need [p4c](https://github.com/p4lang/p4c))
* [The `mininet-interface` branch of petr4](https://github.com/verified-network-toolchain/petr4/tree/mininet-interface)


## Installation notes

The `setup_test_env.sh` uses the `linux-tools` package to set performance mode from the command line. This requires installing

```bash
sudo apt-get install linux-tools-$(uname -r)
```

Otherwise, follow the regular installation instructions for the respective repositories, with the additions/exceptions noted below.

### HOL4P4

Note that after following the regular installation instructions, in order to build a software switch from a P4 program, you need to follow the instructions [here](https://github.com/kth-step/HOL4P4/blob/dev_hol4p4exe/hol/retrofit_sem/programs/compilation/README.md).

### petr4

The `mininet-interface` branch is known to compile using version 4.09.1 of the OCaml compiler. This may not be listed by opam, so add the official archive:

```bash
opam repo add archive git+https://github.com/ocaml/opam-repository-archive
```

In addition to listed dependencies, the `mininet-interface` branch of petr4 also requires

```bash
opam install rawlink-lwt cohttp-lwt-unix hex
```

as well as changing `rawlink.lwt` to `rawlink-lwt` in the `bin/dune` file.

After `make`, the a symlink will be located at `./_build/install/default/bin/petr4`. Note that this should not replace your existing petr4 (used by the import tool of HOL4P4) - no need to run `make install`.

Run the switch by running something like

```bash
sudo petr4 switch -i 0@s1-eth1 -i 1@s1-eth2 -I p4include conditional.p4
```

where you ensure `petr4` points to `./_build/install/default/bin/petr4` or similar, so that you use what you just built.  Note, the above also requires the virtual network to be set up (`s1-eth1`, `s1-eth2`).


## Other dependencies

The Lua scripts run by the test scripts can be found in the the [kth-step fork of Pktgen-DPDK](https://github.com/kth-step/Pktgen-DPDK); check out the `for_hol4p4` branch find them in the `scripts` directory.


## Usage

First, run the `setup_test_env.sh` script on every startup (after every boot). Note that you may have issues reserving hugepages if you don't run the script right after a fresh boot: you may also try to shrink the hugepage size.

Then run e.g.

```bash
sudo ./test_hol4p4.sh /home/my_user/src/Pktgen-DPDK/
```
  
while ensuring the configuration parameters and command-line arguments of the script is what you want.