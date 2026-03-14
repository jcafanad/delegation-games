(** FFI to chuaque paraconsistent logic module.

    Uses a simple subprocess/JSON string interface — no external JSON library.
    Phase 2 will add a type-safe GADT version (chuaque_interface.ml).

    Integration:
    - Converts delegation chains to JSON atoms
    - Calls Python chuaque module via subprocess
    - Parses Belnap valuations from the response
    - Gracefully falls back when Python/chuaque is unavailable

    Requirements:
    - Python 3 in PATH
    - contra-value/chuaque in PYTHONPATH (optional; falls back to passthrough)
*)

open Core
open Core_types
open Agent
open Belnap

(** An atom sent to / received from chuaque *)
type atom = {
  agent: int;
  proposition: string;
  valuation: Belnap.t;
}
[@@deriving sexp]

(** Belnap ↔ chuaque string conversions *)
let belnap_to_string = function
  | T -> "T" | F -> "F" | B -> "B" | N -> "N"

let belnap_of_string = function
  | "T" -> T | "F" -> F | "B" -> B | "N" -> N
  | s   -> failwith (sprintf "Unknown Belnap value from chuaque: %s" s)

(** Serialize a single atom to a JSON object string *)
let atom_to_json atom =
  sprintf {|{"agent": %d, "proposition": "%s", "valuation": "%s"}|}
    atom.agent
    atom.proposition
    (belnap_to_string atom.valuation)

(** Serialize a list of atoms to a JSON array string *)
let atoms_to_json atoms =
  sprintf "[%s]" (List.map atoms ~f:atom_to_json |> String.concat ~sep:", ")

(** Extract all Belnap valuations from a JSON response string.

    Tokenises by splitting on '"' and scans for the pattern:
      "valuation"  ": "  "X"
    This avoids any JSON library while being robust to key ordering.
*)
let extract_valuations json_str =
  let tokens = String.split json_str ~on:'"' in
  let rec find = function
    | []                          -> []
    | "valuation" :: _sep :: v :: rest ->
        let bv =
          match String.strip v with
          | "T" -> Some T | "F" -> Some F | "B" -> Some B | "N" -> Some N
          | _   -> None
        in
        (match bv with Some b -> b :: find rest | None -> find rest)
    | _ :: tl                     -> find tl
  in
  find tokens

(** Python helper script — written to a temp file and executed.
    Falls back to passthrough if chuaque is not importable.
*)
let python_helper_script = {|
import json, sys

try:
    from chuaque import evaluate_atoms
    with open(sys.argv[1], 'r') as f:
        atoms = json.load(f)
    result = evaluate_atoms(atoms)
    print(json.dumps(result))
except ImportError:
    # chuaque not available: return atoms unchanged as passthrough
    with open(sys.argv[1], 'r') as f:
        print(f.read())
except Exception as e:
    sys.stderr.write(f"chuaque error: {e}\n")
    with open(sys.argv[1], 'r') as f:
        print(f.read())
|}

(** Call the chuaque Python module via subprocess.
    Returns the raw JSON response string, or None on failure.
*)
let call_chuaque_subprocess atoms =
  let json_input  = atoms_to_json atoms in
  let input_file  = Stdlib.Filename.temp_file "chuaque_in"  ".json" in
  let script_file = Stdlib.Filename.temp_file "chuaque_run" ".py"  in
  let cleanup ()  =
    (try Stdlib.Sys.remove input_file  with _ -> ());
    (try Stdlib.Sys.remove script_file with _ -> ())
  in
  try
    Out_channel.write_all input_file  ~data:json_input;
    Out_channel.write_all script_file ~data:python_helper_script;
    let cmd = sprintf "python3 %s %s 2>/dev/null" script_file input_file in
    let ic = Core_unix.open_process_in cmd in
    let output = In_channel.input_all ic in
    let _ = Core_unix.close_process_in ic in
    cleanup ();
    if String.is_empty (String.strip output) then None
    else Some output
  with exn ->
    cleanup ();
    eprintf "chuaque_ffi: subprocess failed: %s\n%!" (Exn.to_string exn);
    None

(** Convert a delegation chain to a list of atoms.

    Chain [a0, a1, ..., ak]:
    - Each agent aᵢ (i < k) gets proposition "delegates_to_<aᵢ₊₁>", valuation T
    - Terminal agent ak gets proposition "executes", valuation T

    Phase 2 will assign richer valuations (B for oscillating agents, etc.)
*)
let chain_to_atoms ~registry chain =
  let n = List.length chain in
  List.filter_mapi chain ~f:(fun i agent_id ->
    match Agent_registry.get registry agent_id with
    | None -> None
    | Some _agent ->
        let proposition, valuation =
          if i = n - 1 then
            ("executes", T)
          else
            let next_id = List.nth_exn chain (i + 1) in
            (sprintf "delegates_to_%d" (Agent_id.to_int next_id), T)
        in
        Some { agent = Agent_id.to_int agent_id; proposition; valuation })

(** Evaluate a delegation chain via chuaque.

    Returns:
    - Some valuations: list of Belnap values from chuaque (one per atom)
    - None: chuaque unavailable or call failed (caller should fall back)
*)
let evaluate_chain ~registry chain =
  let atoms    = chain_to_atoms ~registry chain in
  let response = call_chuaque_subprocess atoms in
  Option.map response ~f:extract_valuations

(** Check whether chuaque is callable on this system.
    Useful for graceful degradation at startup.
*)
let is_available () =
  match call_chuaque_subprocess [] with
  | Some _ -> true
  | None   -> false

(* ---- Argument-level FFI (used by DDG argumentation frameworks) ---- *)

(** Python script for evaluating a single structured argument.
    Returns a single Belnap value: "T", "F", "B", or "N".
*)
let argument_eval_script = {|
import json, sys

try:
    from chuaque import evaluate_argument
    with open(sys.argv[1], 'r') as f:
        arg = json.load(f)
    result = evaluate_argument(arg)
    print(result)
except ImportError:
    # chuaque not available: use simple defeater-count heuristic
    with open(sys.argv[1], 'r') as f:
        arg = json.load(f)
    n_grounds   = len(arg.get('grounds',   []))
    n_defeaters = len(arg.get('defeaters', []))
    if n_defeaters == 0:
        print("T")
    elif n_defeaters > n_grounds:
        print("F")
    elif n_defeaters == n_grounds:
        print("B")
    else:
        print("T")
except Exception as e:
    sys.stderr.write(f"chuaque error: {e}\n")
    print("N")
|}

(** Python script for querying defeaters for a given argument. *)
let defeater_query_script = {|
import json, sys

try:
    from chuaque import find_defeaters
    with open(sys.argv[1], 'r') as f:
        query = json.load(f)
    defeaters = find_defeaters(query['claim'], query['grounds'])
    print(json.dumps(defeaters))
except ImportError:
    print("[]")
except Exception as e:
    sys.stderr.write(f"chuaque error: {e}\n")
    print("[]")
|}

(** Run a Python script with a JSON input file.
    Returns stdout stripped, or None on failure.
*)
let run_python_with_json ~script ~json_input =
  let input_file  = Stdlib.Filename.temp_file "chuaque_arg" ".json" in
  let script_file = Stdlib.Filename.temp_file "chuaque_py"  ".py"  in
  let cleanup () =
    (try Stdlib.Sys.remove input_file  with _ -> ());
    (try Stdlib.Sys.remove script_file with _ -> ())
  in
  try
    Out_channel.write_all input_file  ~data:json_input;
    Out_channel.write_all script_file ~data:script;
    let cmd = sprintf "python3 %s %s 2>/dev/null" script_file input_file in
    let ic  = Core_unix.open_process_in cmd in
    let out = In_channel.input_all ic in
    let _   = Core_unix.close_process_in ic in
    cleanup ();
    let stripped = String.strip out in
    if String.is_empty stripped then None else Some stripped
  with exn ->
    cleanup ();
    eprintf "chuaque_ffi: subprocess failed: %s\n%!" (Exn.to_string exn);
    None

(** Evaluate a single argument JSON string.
    Returns "T", "F", "B", "N", or None on failure.
*)
let evaluate_argument json_arg_str : string option =
  run_python_with_json ~script:argument_eval_script ~json_input:json_arg_str

(** Query chuaque for defeaters of an argument given claim and grounds.
    Returns a list of defeater strings, or None if chuaque unavailable.
*)
let query_defeaters ~claim ~grounds : string list option =
  let json_string s = sprintf "%S" s in
  let grounds_json =
    sprintf "[%s]"
      (List.map grounds ~f:json_string |> String.concat ~sep:", ")
  in
  let json_input =
    sprintf {|{"claim": %S, "grounds": %s}|} claim grounds_json
  in
  match run_python_with_json ~script:defeater_query_script ~json_input with
  | None -> None
  | Some response ->
      (* Parse JSON array of strings: ["defeater1", "defeater2", ...] *)
      let tokens = String.split response ~on:'"' in
      let rec collect = function
        | [] | [_] -> []
        | _ :: s :: rest when not (String.is_empty (String.strip s)) ->
            (* Skip structural tokens like [, ], , *)
            if String.for_all (String.strip s) ~f:(fun c ->
                 Char.(c = '[' || c = ']' || c = ',' || c = ' ')) then
              collect rest
            else
              s :: collect rest
        | _ :: rest -> collect rest
      in
      (* Filter out empty strings and structural JSON *)
      let defeaters =
        collect tokens
        |> List.filter ~f:(fun s ->
             let stripped = String.strip s in
             not (String.is_empty stripped)
             && not (String.for_all stripped ~f:(fun c ->
                       Char.(c = '[' || c = ']' || c = ','))))
      in
      Some defeaters
