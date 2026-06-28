# Software Switch Performance Testbed

## Dependencies

This repository has been tested with
* [DPDK version 25.07](https://github.com/DPDK/dpdk/tree/v25.07)
* [Pktgen-DPDK version 24.10.03](https://github.com/kth-step/Pktgen-DPDK/tree/for_hol4p4_24.10.03)
* [The `dev_hol4p4exe` branch of HOL4P4](https://github.com/kth-step/HOL4P4/tree/dev_hol4p4exe)
* [BMv2 version `1.15.2`](https://github.com/p4lang/behavioral-model/tree/1.15.2) (in order to compile programs for BMv2, you also need [p4c](https://github.com/p4lang/p4c))
* [The `mininet-interface` branch of petr4](https://github.com/kth-step/petr4/tree/mininet-interface-noprint) (The forked version has clarified dependencies and commented out debug printing. Note also that includes from [p4c](https://github.com/p4lang/p4c) are needed for running)
on Ubuntu 26.04.

## Installation notes

The `setup_test_env.sh` uses the `linux-tools` package to ensure performance mode is set. This requires installing

```bash
sudo apt-get install linux-tools-$(uname -r)
```

Otherwise, follow the regular installation instructions for the respective repositories, with the additions/exceptions noted below.

### HOL4P4

Note that after following the regular installation instructions, in order to build a software switch from a P4 program, you need to follow the instructions [here](https://github.com/kth-step/HOL4P4/blob/dev_hol4p4exe/hol/retrofit_sem/programs/compilation/README.md).

### petr4

The `mininet-interface` branch is known to compile using version 4.09.1 of the OCaml compiler. To help find the right dependencies, use an older version of the opam repository when creating a switch for 4.09.1:

```bash
opam repository add for_petr4_mininet git+https://github.com/ocaml/opam-repository#de8a574c29db04f43ed3ba7da1be222e430c4c67 --dont-select
CC="gcc -std=gnu17" opam switch create 4.09.1 ocaml-base-compiler.4.09.1 --repos=for_petr4_mininet
eval $(opam env --switch=4.09.1)
```

In addition to listed dependencies, the `mininet-interface` branch of petr4 also requires

```bash
opam install rawlink-lwt hex
```

before running `opam install . --deps-only`. Use version 0.1.10 of p4pp.

After `make`, the a symlink will be located at `./_build/install/default/bin/petr4`. Note that this should not replace your existing petr4 used by the import tool of HOL4P4 - no need to run `make install`.

Run the switch by running something like

```bash
sudo petr4 switch -i 0@s1-eth1 -i 1@s1-eth2 -I p4include port_swap.p4
```

where you ensure `petr4` points to `./_build/install/default/bin/petr4` or similar, so that you use what you just built. Note, the above also requires the virtual network to be set up (`s1-eth1`, `s1-eth2`).


## Other dependencies

The Lua scripts run by the test scripts are located in the the [kth-step fork of Pktgen-DPDK](https://github.com/kth-step/Pktgen-DPDK); check out the `for_hol4p4_24.10.03` branch and find them in the `scripts` directory.


## Usage

First, run the `setup_test_env.sh` script on every startup (after every boot). Note that you may have issues reserving hugepages if you don't run the script right after a fresh boot: you may also try to shrink the hugepage size.

Then run e.g.

```bash
sudo ./test_hol4p4.sh /home/my_user/src/Pktgen-DPDK/
```
  
while ensuring the configuration parameters and command-line arguments of the script is what you want.

The current scripts are tailored towards a CPU with at least 4 non-hyperthreaded cores mapped to IDs 0 and up (for example, Intel Lunar Lake and Arrow Lake CPUs). Certain Intel CPUs from generations preceding Lunar Lake assign hyperthreaded cores adjacent IDs, which causes degraded performance. Check your layout with `lscpu -e` and adjust the core assignments in the scripts starting with `test_` accordingly - ideally, you want to use distinct, high-performance physical cores. For AMD CPUs, beware that the lower-numbered cores are not always the most performant. You may have to identify the highest-clocked cores manually for an ideal core assignment. Needless to say, doing anything at in the background during testing will affect results.
