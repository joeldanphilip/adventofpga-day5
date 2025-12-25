open! Core
open! Hardcaml
open! Signal

module Config = struct
  let capacity = 200
  let data_width = 64
end

module I = struct
  type 'a t =
    { clock : 'a
    ; clear : 'a
    ; wr_enable : 'a
    ; wr_start : 'a[@bits Config.data_width]
    ; wr_end : 'a[@bits Config.data_width]
    ; start_processing : 'a
    }
  [@@deriving sexp_of, hardcaml]
end

module O = struct
  type 'a t =
    { result : 'a[@bits Config.data_width]
    ; done_flag : 'a
    ; state_debug : 'a[@bits 2]
    }
  [@@deriving sexp_of, hardcaml]
end

(* Unsigned comparison helpers *)
let u_compare op a b =
  let w = max (width a) (width b) + 1 in
  op (uresize a w) (uresize b w)
;;

let ugt = u_compare (>:)
let ule = u_compare (<=:)
let uge = u_compare (>=:)

module States = struct
  let loading = of_int ~width:2 0
  let sorting = of_int ~width:2 1
  let merging = of_int ~width:2 2
  let done_ = of_int ~width:2 3
end

let create _scope (i : Signal.t I.t) =
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.clear () in

  (* --- State Machine --- *)
  let current_state = wire 2 in
  let state_reg = reg spec ~enable:vdd current_state in

  let is_loading = state_reg ==: States.loading in
  let is_sorting = state_reg ==: States.sorting in
  let is_merging = state_reg ==: States.merging in
  let is_done = state_reg ==: States.done_ in

  (* Timers to control state transitions *)
  let sort_timer = reg_fb spec ~enable:is_sorting ~width:16 ~f:(fun c -> c +:. 1) in
  let sort_done = uge sort_timer (of_int ~width:16 Config.capacity) in

  let stream_idx = reg_fb spec ~enable:is_merging ~width:16 ~f:(fun c -> c +:. 1) in
  let stream_done = uge stream_idx (of_int ~width:16 Config.capacity) in

  let next_state_val =
    mux
      state_reg
      [ mux2 i.start_processing States.sorting States.loading
      ; mux2 sort_done States.merging States.sorting
      ; mux2 stream_done States.done_ States.merging
      ; States.done_
      ]
  in
  current_state <== next_state_val;

  (* --- Systolic Sorting Array --- *)
  (* A linear array of registers that performs an odd-even transposition sort. *)
  let reg_starts = List.init Config.capacity ~f:(fun _ -> wire Config.data_width) in
  let reg_ends = List.init Config.capacity ~f:(fun _ -> wire Config.data_width) in

  let q_starts = List.map reg_starts ~f:(fun w -> reg spec ~enable:vdd w) in
  let q_ends = List.map reg_ends ~f:(fun w -> reg spec ~enable:vdd w) in

  List.iteri (List.zip_exn reg_starts reg_ends) ~f:(fun idx (next_s, next_e) ->
    let my_s = List.nth_exn q_starts idx in
    let my_e = List.nth_exn q_ends idx in

    (* Load Mode: Shift in new data from the input port *)
    let load_s, load_e =
      if idx = 0
      then i.wr_start, i.wr_end
      else List.nth_exn q_starts (idx - 1), List.nth_exn q_ends (idx - 1)
    in

    (* Sort Mode: Compare with neighbors and swap if out of order *)
    let phase_odd = lsb sort_timer in
    let left_s, left_e =
      if idx > 0
      then List.nth_exn q_starts (idx - 1), List.nth_exn q_ends (idx - 1)
      else my_s, my_e
    in
    let right_s, right_e =
      if idx < Config.capacity - 1
      then List.nth_exn q_starts (idx + 1), List.nth_exn q_ends (idx + 1)
      else my_s, my_e
    in

    let swap_with_right = ugt my_s right_s in
    let swap_with_left = ugt left_s my_s in
    let is_even_idx = idx % 2 = 0 in

    let sort_s, sort_e =
      match is_even_idx with
      | true ->
        ( mux2
            phase_odd
            (mux2 swap_with_left left_s my_s)
            (mux2 swap_with_right right_s my_s)
        , mux2
            phase_odd
            (mux2 swap_with_left left_e my_e)
            (mux2 swap_with_right right_e my_e) )
      | false ->
        ( mux2
            phase_odd
            (mux2 swap_with_right right_s my_s)
            (mux2 swap_with_left left_s my_s)
        , mux2
            phase_odd
            (mux2 swap_with_right right_e my_e)
            (mux2 swap_with_left left_e my_e) )
    in

    let final_s =
      mux2 (is_loading &: i.wr_enable) load_s (mux2 is_sorting sort_s my_s)
    in
    let final_e =
      mux2 (is_loading &: i.wr_enable) load_e (mux2 is_sorting sort_e my_e)
    in
    next_s <== final_s;
    next_e <== final_e);

  (* --- Merge Pipeline --- *)
  (* Consumes sorted data from the array and merges overlapping ranges. *)
  let curr_merged_s_in = wire Config.data_width in
  let curr_merged_e_in = wire Config.data_width in
  let total_acc_in = wire Config.data_width in
  let is_tracking_in = wire 1 in

  let curr_merged_s = reg spec ~enable:vdd curr_merged_s_in in
  let curr_merged_e = reg spec ~enable:vdd curr_merged_e_in in
  let total_acc = reg spec ~enable:vdd total_acc_in in
  let is_tracking = reg spec ~enable:vdd is_tracking_in in

  (* Select the next sorted range from the array *)
  let current_s_out = mux stream_idx q_starts in
  let current_e_out = mux stream_idx q_ends in

  let next_possible_end = curr_merged_e +:. 1 in
  let overlaps = ule current_s_out next_possible_end in

  (* State updates *)
  let next_tracking = mux2 is_merging vdd (mux2 stream_done gnd is_tracking) in

  (* Extend the current range if it overlaps, otherwise start a new one *)
  let next_merged_s =
    mux2 (is_tracking &: overlaps) curr_merged_s current_s_out
  in
  let next_merged_e =
    mux2
      (is_tracking &: overlaps)
      (mux2 (ugt current_e_out curr_merged_e) current_e_out curr_merged_e)
      current_e_out
  in

  (* Accumulate total length when a range is finalized (gap detected) *)
  let range_len = (curr_merged_e -: curr_merged_s) +:. 1 in
  let should_add = is_merging &: is_tracking &: (~:overlaps |: stream_done) in
  let next_total = mux2 should_add (total_acc +: range_len) total_acc in

  (* Feedback assignments *)
  curr_merged_s_in <== mux2 is_merging next_merged_s curr_merged_s;
  curr_merged_e_in <== mux2 is_merging next_merged_e curr_merged_e;
  is_tracking_in <== next_tracking;
  total_acc_in <== next_total;

  { O.result = total_acc; done_flag = is_done; state_debug = state_reg }
;;