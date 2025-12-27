open! Core
open! Hardcaml
open! Signal
module HW = Hardcaml_demo_project.Day05_p2

(* Configuration *)
let input_file = "input.txt"
let max_sim_cycles = 5000

let parse_input filename =
  In_channel.read_lines filename
  |> List.filter_map ~f:(fun line ->
       if String.contains line '-' then
         try Some (Scanf.sscanf line "%d-%d" (fun s e -> (s, e)))
         with _ -> None
       else None)

let () =
  (* Setup simulation environment *)
  let ranges = parse_input input_file in
  let scope = Scope.create () in

  (* Initialize hardware and simulator *)
  let module C = Circuit.With_interface(HW.I)(HW.O) in
  let create_fn i = HW.create scope i in
  
  let module Sim = Cyclesim.With_interface(HW.I)(HW.O) in
  let sim = Sim.create create_fn in

  let vcd_out = Out_channel.create "day05_accelerator.vcd" in
  let sim = Hardcaml.Vcd.wrap vcd_out sim in

  let inputs = Cyclesim.inputs sim in
  let outputs = Cyclesim.outputs sim in
  let step () = Cyclesim.cycle sim in

  Printf.eprintf "--- Hardware Simulation Started (%d ranges) ---\n" (List.length ranges);

  (* 1. Reset Phase *)
  inputs.clear := Bits.vdd; step();
  inputs.clear := Bits.gnd; step();

  (* 2. Load Phase: Stream ranges into the systolic array *)
  Printf.eprintf "State: Loading Data...\n";
  inputs.start_processing := Bits.gnd;
  
  List.iter ranges ~f:(fun (s, e) ->
    inputs.wr_enable := Bits.vdd;
    inputs.wr_start := Bits.of_int ~width:64 s;
    inputs.wr_end := Bits.of_int ~width:64 e;
    step()
  );
  
  (* Stop writing *)
  inputs.wr_enable := Bits.gnd;
  step();

  (* 3. Process Phase: Pulse start to begin Sort & Merge *)
  Printf.eprintf "State: Sorting and Merging...\n";
  inputs.start_processing := Bits.vdd; 
  step();
  inputs.start_processing := Bits.gnd;

  (* 4. Wait for Completion *)
  let cycles = ref 0 in
  while Bits.is_gnd !(outputs.done_flag) && !cycles < max_sim_cycles do
    step();
    incr cycles
  done;

  (* 5. Results *)
  let raw_result = Bits.to_int !(outputs.result) in
  let final_answer = raw_result - 1 in

  Printf.eprintf "Simulation finished in %d cycles.\n" !cycles;
  Printf.eprintf "Raw Output:   %d\n" raw_result;
  Printf.eprintf "Final Answer: %d\n" final_answer;

  Out_channel.close vcd_out;
  Printf.eprintf "Waveform saved to day05_accelerator.vcd\n";

  (* Generate Synthesizable Verilog to stdout *)
  let circuit = C.create_exn ~name:"sorter_and_merger" create_fn in
  Rtl.print Verilog circuit