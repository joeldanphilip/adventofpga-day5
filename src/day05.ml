open! Core
open! Hardcaml
open! Signal

module I = struct
  type 'a t = {
    clock : 'a;
    clear : 'a;
    ingredient_id : 'a[@bits 64];
    valid : 'a;
  } [@@deriving sexp_of, hardcaml]
end

module O = struct
  type 'a t = {
    is_fresh : 'a;
    total_count : 'a[@bits 64];
  } [@@deriving sexp_of, hardcaml]
end

(* Logic to check if a signal 'v' is within [min_val, max_val] (inclusive). 
   We zero-extend signals by 1 bit to ensure robust unsigned comparison. *)
let is_within_range v (min_val, max_val) =
  let width = width v in
  let uresize s = uresize s (width + 1) in
  
  let v_u = uresize v in
  let min_u = uresize (of_int ~width min_val) in
  let max_u = uresize (of_int ~width max_val) in
  
  (v_u >=: min_u) &: (v_u <=: max_u)

let create (_scope : Scope.t) (ranges : (int * int) list) (i : Signal.t I.t) =
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.clear () in

  (* 1. Parallel Range Checkers
     Map the list of static ranges to a list of hardware comparators. *)
  let range_checks = 
    List.map ranges ~f:(fun range -> is_within_range i.ingredient_id range)
  in

  (* 2. Reduction Tree
     Combine all checks with OR. If the ID matches ANY range, it is valid. *)
  let is_fresh = 
    if List.is_empty range_checks then gnd 
    else reduce ~f:(|:) range_checks 
  in

  (* 3. Accumulator
     Increment the total count only when the input is valid AND matches a range. *)
  let increment = is_fresh &: i.valid in
  let total_count = 
    reg_fb spec ~enable:increment ~width:64 ~f:(fun c -> c +:. 1) 
  in

  { O.is_fresh; total_count }