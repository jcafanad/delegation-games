(** Belnap's four-valued logic for paraconsistent reasoning.

    Truth values: T (true), F (false), B (both), N (neither)

    Theoretical foundation:
    - B represents genuine contradiction (dialetheia)
    - N represents absence of information (epistemic gap)
    - Lattice structure with join (⊔) and meet (⊓) operations
    - Negation preserves lattice properties

    This module implements the algebra now with simple types.
    Phase 2 will transition to GADTs for compile-time invariant enforcement.

    References:
    - Belnap, N. (1977). "A useful four-valued logic"
    - Priest, G. (2008). "An Introduction to Non-Classical Logic"
*)

(** Four truth values *)
type t =
  | T  (* true: classically true, no contradiction *)
  | F  (* false: classically false, no contradiction *)
  | B  (* both: true AND false, contradictory (dialetheia) *)
  | N  (* neither: neither true nor false, informational gap *)
[@@deriving sexp, compare, equal, enumerate]

(** Knowledge ordering: N ⊑ T, N ⊑ F, T ⊑ B, F ⊑ B

    Interpretation:
    - N is least informative (know nothing)
    - T and F are incomparable (different classical values)
    - B is most informative (know both)
*)
let knowledge_order a b =
  match (a, b) with
  | (N, _) -> true
  | (T, T) | (T, B) -> true
  | (F, F) | (F, B) -> true
  | (B, B) -> true
  | _ -> false

(** Truth ordering: F ⊑ N, F ⊑ T, N ⊑ B, T ⊑ B

    Interpretation:
    - F is least true (classically false)
    - N and T are incomparable
    - B is most true (true despite contradiction)
*)
let truth_order a b =
  match (a, b) with
  | (F, _) -> true
  | (N, N) | (N, B) -> true
  | (T, T) | (T, B) -> true
  | (B, B) -> true
  | _ -> false

(** Join operation (⊔) in knowledge ordering.

    Computes least upper bound: most informative common extension.
*)
let join a b =
  match (a, b) with
  | (B, _) | (_, B) -> B
  | (T, F) | (F, T) -> B  (* contradiction merges to Both *)
  | (T, _) | (_, T) -> T
  | (F, _) | (_, F) -> F
  | (N, N) -> N

(** Meet operation (⊓) in knowledge ordering.

    Computes greatest lower bound: least informative common restriction.
*)
let meet a b =
  match (a, b) with
  | (N, _) | (_, N) -> N
  | (B, x) | (x, B) -> x
  | (T, F) | (F, T) -> N  (* incompatible = no information *)
  | (T, T) -> T
  | (F, F) -> F

(** Negation operation.

    Classical negation extended to four values:
    - ¬T = F, ¬F = T (classical)
    - ¬B = B (contradiction negated is still contradiction)
    - ¬N = N (no information negated is still no information)
*)
let neg = function
  | T -> F
  | F -> T
  | B -> B
  | N -> N

(** Conjunction (∧) via meet in truth ordering *)
let conj a b =
  match (a, b) with
  | (F, _) | (_, F) -> F
  | (N, _) | (_, N) -> N
  | (T, T) -> T
  | (T, B) | (B, T) | (B, B) -> B

(** Disjunction (∨) via join in truth ordering *)
let disj a b =
  match (a, b) with
  | (T, _) | (_, T) -> T
  | (B, _) | (_, B) -> B
  | (F, F) -> F
  | (F, N) | (N, F) | (N, N) -> N

(** Implication (→) in Belnap logic.

    a → b = ¬a ∨ b (classical definition extended)

    Critical for paraconsistent logic: B → B = B (valid!)
    This prevents ex contradictione quodlibet.
*)
let impl a b =
  disj (neg a) b

(** Designated values: T and B.

    In paraconsistent logic, both T and B are "designated" (accepted as true).
    This allows reasoning with contradictions without explosion.
*)
let is_designated = function
  | T | B -> true
  | F | N -> false

(** Check if value represents contradiction *)
let is_contradictory = function
  | B -> true
  | _ -> false

(** Check if value represents informational gap *)
let is_gap = function
  | N -> true
  | _ -> false

(** Convert to classical boolean (for systems requiring bivalence).

    Projection: T,B → true; F,N → false
    This loses paraconsistent information but enables integration with
    classical systems.
*)
let to_bool = function
  | T | B -> true
  | F | N -> false

(** Prepare for GADT transition (Phase 2).

    Currently just a type alias, but structure prepares for:
      type 'a typed =
        | True  : true_t  typed
        | False : false_t typed
        | Both  : both_t  typed
        | Neither : neither_t typed
*)
type 'a typed = t

let unsafe_cast (x : t) : 'a typed = x

(** String representation for debugging *)
let to_string = function
  | T -> "T"
  | F -> "F"
  | B -> "\xe2\x8a\xa4\xe2\x8a\xa5"  (* ⊤⊥ *)
  | N -> "\xe2\x88\x85"               (* ∅ *)

(** Pretty-print with semantic interpretation *)
let pp fmt = function
  | T -> Format.fprintf fmt "T (true)"
  | F -> Format.fprintf fmt "F (false)"
  | B -> Format.fprintf fmt "B (contradictory)"
  | N -> Format.fprintf fmt "N (unknown)"
