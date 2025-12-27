# Advent of FPGA 2025 - Day 5

**Challenge:** Cafeteria (Inventory Management)  
**Language:** OCaml / [Hardcaml](https://github.com/janestreet/hardcaml)  


## Project Overview
This project provides a synthesizable hardware solution for Jane Street's Advent of Code Day 5 puzzle. The core problem involves mapping and merging integer ranges to determine "fresh" ingredients. While this is straightforward in software using standard sorting algorithms, an efficient hardware implementation requires a different approach to handle data dependencies without stalling.

My solution focuses on Part 2, implementing a custom "Sort-and-Merge" accelerator that processes the data stream in real-time using a systolic architecture.

> **Note:** While I have significant experience with Verilog and SystemVerilog, this was my first time diving into Hardcaml. It was a fun challenge to reimplement architectural concepts I know well (like systolic arrays, even though it might not be the most creative solution) using OCaml's functional paradigms.

## Design Approach
I utilized Hardcaml to implement the design via OCaml metaprogramming. This allowed for a parametric implementation where the sorting network's depth is defined by a single configuration variable (`capacity`), facilitating easy scaling without manual RTL modification.

The architecture relies on dataflow rather than control flow. Instead of a central controller managing memory access, data moves through a pipeline of processing elements where every register is active on every clock cycle.



## Part 1: Parallel Range Checker
For the first part of the challenge, the goal was to validate specific Ingredient IDs against a list of "fresh" ranges.

The hardware implementation creates a **Parallel Range Checker**. Instead of iterating through rules sequentially, the design instantiates a specific comparator for every range rule defined in the input file.

The input Ingredient ID is broadcast to all comparators simultaneously. A combinatorial reduction tree then combines the results into a single `is_fresh` boolean signal in one clock cycle.

### Synthesis Results (Artix-7)
Synthesized on Vivado 2023.2 for an Artix-7 (xc7a100t). The resource usage shows high LUT utilization due to the reduction tree, with minimal register usage.

| Resource | Used | Available | Utilization % |
| :--- | :--- | :--- | :--- |
| **Slice LUTs** | 10,606 | 63,400 | **16.73%** |
| **Registers** | 64 | 126,800 | **0.05%** |

* **Target Clock:** 200 MHz
* **Timing:** Met (WNS +0.692 ns)



## Part 2: Systolic Sort-and-Merge
To calculate the total count of valid IDs by merging overlapping ranges, the data must be sorted. I implemented a **Stream Processing Unit** composed of two pipeline stages.



### Stage 1: Linear Systolic Array
I implemented a linear array of 200 registers to handle sorting without external RAM. In every clock cycle, each register compares its value with its neighbor. If they are out of order, they swap.



This implements an Odd-Even Transposition Sort. The array guarantees the list is sorted in exactly $N$ clock cycles, providing deterministic latency for the downstream merger.

### Stage 2: Merge Pipeline
Data streams out of the array into a merge unit. First, the pipeline checks if the incoming range overlaps with the current active range. If so, they are fused. When a gap is detected between ranges, the length of the completed range is added to the total accumulator.

### Synthesis Results
Synthesizing the 200-stage systolic array utilizes a significant portion of the FPGA fabric, as it instantiates 200 physical sorting cells in parallel.

| Resource | Used | Available | Utilization % |
| :--- | :--- | :--- | :--- |
| **Slice LUTs** | 39,224 | 63,400 | **61.87%** |
| **Registers** | 26,087 | 126,800 | **20.57%** |

* **Target Clock:** 83.33 MHz
* **Timing:** Met (WNS +0.100 ns)


## Scalability
The Linear Systolic Array was selected to maximize local routing efficiency. By mapping logical processing elements directly to the distributed flip-flop fabric, the design avoids global routing congestion.

The parametric nature of the OCaml source code allows the design to scale. The register usage scales linearly with the input size (~128 registers per sorting cell), allowing for larger datasets to be processed on larger FPGAs (e.g., UltraScale+) simply by recompiling with a higher `capacity` value.



## Reproduction Instructions

To run the simulations and generate the SystemVerilog netlists, ensure **OCaml**, **Opam**, and **Hardcaml** are installed.

### 1. Setup Environment
```bash
eval $(opam env)
```
### 2. Run Part 1 (Parallel Checker)
This simulates the checker logic and outputs the synthesized Verilog to `part1_soln.v`.

```bash
dune exec bin/solve.exe > part1_soln.v
```
### 3. Run Part 2 (Accelerator)
This simulates the systolic array and merge pipeline, outputting the synthesized Verilog to `part2_soln.v`.

```bash
dune exec bin/solve_p2.exe > part2_soln.v
```

## References & Acknowledgements

Special thanks to the community members whose resources helped bridge the gap between Verilog and Hardcaml:

* **Problem Statement:** [Day 5: Cafeteria](https://adventofcode.com/2025/day/5)
* **Hardcaml Wiki & Cheatsheet:** [Hardcaml Wiki](https://ocamlstreet.gitbook.io/hardcaml-wiki) (Maintained by Hari)
* **Hardcaml Inspiration:** [MIPS CPU Project & Blog](https://www.reddit.com/r/FPGA/comments/obvo3u/hardcaml_mips_cpu_learning_project_and_blog/) (By Alexander "Sasha" Skvortsov)
