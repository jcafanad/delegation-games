(** Analysis metrics for DDG dialogue traces.

    EPISTEMOLOGICAL WARNING:
    These metrics measure argumentation structure, NOT optimization efficiency.
    Do NOT compute:
    - Mean reward (DDG has no rewards)
    - PSD (DDG has no success/failure binary)
    - Regret (DDG has no optimal baseline to compare against)

    The shift in research question:
    - NOT: "Is DDG more efficient than DIG?"  (incommensurable)
    - BUT: "Does DDG reveal contradictions that DIG/DEC make invisible?"
    - AND: "How does network topology shape where contradictions surface?"

    Metrics defined here answer the DDG research questions:
    - contradiction_coverage: how often does deliberation find B states?
    - mean_argument_depth: how deep into the network do arguments travel?
    - defeater_diversity: how many distinct defeaters does the network surface?
    - resolution_profile: distribution of T/F/B/N outcomes
    - path_analysis: where in the network do contradictions typically land?
*)

open Core
open Delegation_games
open Core_types
open Belnap_gadt
open Protocol_ddg

(** Outcome classification for a single trace *)
type outcome =
  | Accepted       (* Truth T: argument accepted without contradiction *)
  | Rejected       (* Truth F: argument defeated *)
  | Contradicted   (* Truth B: genuine dialectical contradiction — DDG's key finding *)
  | Unknown        (* Truth N: insufficient information *)
[@@deriving sexp]

let classify_outcome trace =
  match trace.final_evaluation with
  | Truth T -> Accepted
  | Truth F -> Rejected
  | Truth B -> Contradicted
  | Truth N -> Unknown

(** Contradiction coverage: fraction of traces that end in B state.

    This is DDG's primary metric. High contradiction coverage indicates
    the network successfully maps structural contradictions.

    Interpretation:
    - Low (~5%): contradictions are rare or topology doesn't surface them
    - Medium (15-30%): healthy dialectical engagement
    - High (>50%): pervasive contradiction — may indicate structural crisis
*)
let contradiction_coverage traces =
  if List.is_empty traces then 0.
  else
    let n_contradicted =
      List.count traces ~f:(fun t ->
        match classify_outcome t with
        | Contradicted -> true
        | _ -> false)
    in
    Float.of_int n_contradicted /. Float.of_int (List.length traces)

(** Acceptance rate: fraction of traces ending in T.

    Note: in DDG, a high acceptance rate does NOT mean "success" in
    the DIG/DEC sense. It may mean the network is not surfacing real
    contradictions (theoretical concern: topology too shallow).
*)
let acceptance_rate traces =
  if List.is_empty traces then 0.
  else
    let n_accepted =
      List.count traces ~f:(fun t ->
        match classify_outcome t with
        | Accepted -> true
        | _ -> false)
    in
    Float.of_int n_accepted /. Float.of_int (List.length traces)

(** Mean argument depth: average path length across all traces.

    Longer paths mean arguments penetrate deeper into the network
    before resolution, engaging more structural positions.

    Interpretation:
    - Shallow (1-2): contradictions surface immediately (local, superficial)
    - Medium (3-5): arguments traverse meaningful network distance
    - Deep (>5): contradictions require extensive deliberation to surface
*)
let mean_argument_depth traces =
  if List.is_empty traces then 0.
  else
    let total = List.sum (module Int) traces ~f:(fun t -> List.length t.path) in
    Float.of_int total /. Float.of_int (List.length traces)

(** Defeater diversity: number of distinct defeaters across all traces.

    Measures the richness of the contradiction space the network surfaces.
    High diversity means the network maps many distinct structural tensions.

    Low diversity could indicate:
    - Topology is too uniform (same defeaters seen everywhere)
    - Framework is too simple (same heuristic applied everywhere)
*)
let defeater_diversity traces =
  traces
  |> List.concat_map ~f:(fun t -> t.defeaters_found)
  |> List.dedup_and_sort ~compare:String.compare
  |> List.length

(** Resolution profile: count of each outcome type.

    Returns (accepted, rejected, contradicted, unknown) counts.
*)
let resolution_profile traces =
  List.fold traces
    ~init:(0, 0, 0, 0)
    ~f:(fun (a, r, c, u) trace ->
      match classify_outcome trace with
      | Accepted     -> (a+1, r,   c,   u  )
      | Rejected     -> (a,   r+1, c,   u  )
      | Contradicted -> (a,   r,   c+1, u  )
      | Unknown      -> (a,   r,   c,   u+1))

(** Path analysis: which agents appear most often in contradiction paths.

    High-frequency agents in B traces are "contradiction hubs" —
    structurally positioned at the interface of competing demands.
    In Páramo terms: agents mediating between extraction and resistance.
*)
let contradiction_hubs traces =
  traces
  |> List.filter ~f:(fun t ->
       match classify_outcome t with
       | Contradicted -> true
       | _ -> false)
  |> List.concat_map ~f:(fun t -> t.path)
  |> List.sort_and_group ~compare:Agent_id.compare
  |> List.map ~f:(fun group ->
       let agent_id = List.hd_exn group in
       (agent_id, List.length group))
  |> List.sort ~compare:(fun (_, c1) (_, c2) -> Int.compare c2 c1)

(** Print a summary of DDG analysis results.

    Includes the epistemological warning that results cannot be
    compared to DIG/DEC metrics.
*)
let print_summary ~protocol_name traces =
  let n = List.length traces in
  let (a, r, c, u) = resolution_profile traces in
  let hubs = contradiction_hubs traces in

  printf "\n=== %s Analysis ===\n" protocol_name;
  printf "Trials: %d\n" n;
  printf "\nOutcome distribution:\n";
  printf "  Accepted (T):     %d (%.1f%%)\n" a
    (Float.of_int a /. Float.of_int n *. 100.);
  printf "  Rejected (F):     %d (%.1f%%)\n" r
    (Float.of_int r /. Float.of_int n *. 100.);
  printf "  Contradicted (B): %d (%.1f%%)\n" c
    (Float.of_int c /. Float.of_int n *. 100.);
  printf "  Unknown (N):      %d (%.1f%%)\n" u
    (Float.of_int u /. Float.of_int n *. 100.);
  printf "\nDialectical metrics:\n";
  printf "  Contradiction coverage: %.1f%%\n"
    (contradiction_coverage traces *. 100.);
  printf "  Mean argument depth:    %.1f hops\n"
    (mean_argument_depth traces);
  printf "  Defeater diversity:     %d unique defeaters\n"
    (defeater_diversity traces);
  if not (List.is_empty hubs) then begin
    printf "\nContradiction hubs (top 3):\n";
    List.take hubs 3
    |> List.iter ~f:(fun (id, count) ->
         printf "  Agent %d: %d contradiction traces\n"
           (Agent_id.to_int id) count)
  end;
  printf "\n⚠  DDG results are INCOMMENSURABLE with DIG/DEC metrics.\n";
  printf "   Research question: which contradictions does optimization erase?\n\n"
