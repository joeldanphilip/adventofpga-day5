open! Core
open! Hardcaml
open! Signal
module HW = Hardcaml_demo_project.Day05

(* Configuration *)
let input_file = "input.txt"

(* Parse input file into (ranges, candidates) *)
let parse_input filename =
  let lines = In_channel.read_lines filename |> List.map ~f:String.strip in
  
  let raw_ranges, raw_candidates = 
    List.split_while lines ~f:(fun line -> not (String.is_empty line)) 
  in

  let ranges = 
    List.filter_map raw_ranges ~f:(fun line ->
      try Some (Scanf.sscanf line "%d-%d" (fun s e -> (s, e)))
      with _ -> None)
  in

  let candidates = 
    List.filter_map raw_candidates ~f:(fun line ->
      try Some (Int.of_string line)
      with _ -> None)
  in
  
  (ranges, candidates)

let () =
  (* 1. Setup Environment *)
  let ranges, candidates = parse_input input_file in
  let scope = Scope.create () in

  (* 2. Initialize Hardware *)
  (* The 'ranges' list is passed as a parameter to generate a specialized circuit. *)
  let create_fn inputs = HW.create scope ranges inputs in
  
  let module C = Circuit.With_interface(HW.I)(HW.O) in
  let module Sim = Cyclesim.With_interface(HW.I)(HW.O) in
  
  let sim = Sim.create create_fn in
  let inputs = Cyclesim.inputs sim in
  let outputs = Cyclesim.outputs sim in
  let step () = Cyclesim.cycle sim in

  Printf.eprintf "--- Simulation Started: Part 1 (%d candidates) ---\n" (List.length candidates);

  (* 3. Reset Sequence *)
  inputs.clear := Bits.vdd; step();
  inputs.clear := Bits.gnd; step();

  (* 4. Processing Loop *)
  List.iter candidates ~f:(fun id ->
    inputs.ingredient_id := Bits.of_int ~width:64 id;
    inputs.valid := Bits.vdd;
    step()
  );

  (* 5. Flush Pipeline *)
  (* One extra cycle ensures the final valid signal propagates to the accumulator *)
  inputs.valid := Bits.gnd;
  step();

  (* 6. Report Results *)
  let result = Bits.to_int !(outputs.total_count) in

  Printf.eprintf "Simulation finished.\n";
  Printf.eprintf "FINAL ANSWER: %d\n" result;
  Printf.eprintf "--------------------------------\n";

  (* 7. Generate Verilog *)
  let circuit = C.create_exn ~name:"day05_checker" create_fn in
  Rtl.print Verilog circuit