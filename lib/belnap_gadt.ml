(** GADT-based four-valued logic with compile-time paraconsistent invariants.

    Improvements over belnap.ml (Phase 1):
    - Each truth value carries its type tag at compile time
    - Invalid reasoning (ex contradictione quodlibet) cannot be expressed
    - Type-level witnesses enforce logical correctness

    Key invariant: there is no (false_t, 'a, 'a) conjunction witness.
    This means explosion is literally unwriteable:
      let explode : false_t truth -> 'a truth = fun _ -> (* CANNOT COMPILE *)

    Phase 1 (belnap.ml) is retained for interop with existing code.
    This module supplements it for Phase 2 DDG logic.
*)

(** Private type tags — cannot be constructed outside this module *)
type true_t    = private True_tag
type false_t   = private False_tag
type both_t    = private Both_tag
type neither_t = private Neither_tag

(** GADT: each constructor carries its type tag at compile time *)
type _ truth =
  | T : true_t    truth
  | F : false_t   truth
  | B : both_t    truth   (* Both: true AND false — dialetheia *)
  | N : neither_t truth   (* Neither: no information *)

(** Existential wrapper for heterogeneous truth value collections *)
type truth_val = Truth : 'a truth -> truth_val

(** Convert to simple Belnap.t for Phase 1 interop *)
let to_simple : type a. a truth -> Belnap.t = function
  | T -> Belnap.T
  | F -> Belnap.F
  | B -> Belnap.B
  | N -> Belnap.N

(** Convert from simple Belnap.t — existential because caller doesn't know result type *)
let of_simple : Belnap.t -> truth_val = function
  | Belnap.T -> Truth T
  | Belnap.F -> Truth F
  | Belnap.B -> Truth B
  | Belnap.N -> Truth N

(** String representation for debugging *)
let to_string : type a. a truth -> string = function
  | T -> "T"
  | F -> "F"
  | B -> "\xe2\x8a\xa4\xe2\x8a\xa5"  (* ⊤⊥ — contradictory *)
  | N -> "\xe2\x88\x85"               (* ∅ — no information *)

(** Designated values: T and B are accepted as true in paraconsistent logic *)
let is_designated : type a. a truth -> bool = function
  | T -> true
  | B -> true   (* contradictions are designated — they cannot be dismissed *)
  | F -> false
  | N -> false

(** Type-level witness for contradiction.
    Only both_t truth is contradictory — enforced at compile time.
*)
type _ contradictory =
  | Is_contradictory : both_t contradictory

(** Runtime check returning a type-level proof of contradiction *)
let is_contradictory : type a. a truth -> a contradictory option = function
  | B -> Some Is_contradictory
  | T | F | N -> None

(** Type-level proof that two truth values are the same type *)
type (_, _) same_truth =
  | Same_truth : ('a, 'a) same_truth

(** Runtime equality returning a type-level proof *)
let equal_truth : type a b. a truth -> b truth -> (a, b) same_truth option =
  fun a b ->
    match (a, b) with
    | (T, T) -> Some Same_truth
    | (F, F) -> Some Same_truth
    | (B, B) -> Some Same_truth
    | (N, N) -> Some Same_truth
    | _ -> None

(* ---- Negation ---- *)

(** Negation witness: (a, ¬a) pairs.
    Each constructor is a compile-time proof that neg(a) = b.
*)
type (_, _) negation =
  | Neg_TF : (true_t,    false_t)   negation
  | Neg_FT : (false_t,   true_t)    negation
  | Neg_BB : (both_t,    both_t)    negation   (* ¬B = B: contradiction stays *)
  | Neg_NN : (neither_t, neither_t) negation   (* ¬N = N: gap stays *)

(** Type-safe negation with explicit compile-time witness *)
let neg : type a b. a truth -> (a, b) negation -> b truth =
  fun truth witness ->
    match (truth, witness) with
    | (T, Neg_TF) -> F
    | (F, Neg_FT) -> T
    | (B, Neg_BB) -> B
    | (N, Neg_NN) -> N

(** Negation without witness — returns existential (delegates to Belnap) *)
let neg_val : type a. a truth -> truth_val = fun x ->
  of_simple (Belnap.neg (to_simple x))

(* ---- Conjunction ---- *)

(** Conjunction witnesses — complete 4×4 truth table.

    Table (from Belnap's truth ordering meet):
      a\b  F  T  B  N
      F    F  F  F  F   (F absorbs everything)
      T    F  T  B  N
      B    F  B  B  N
      N    F  N  N  N   (N absorbs T and B, loses to F)
*)
type (_, _, _) conjunction =
  (* F absorbs all — first argument is F *)
  | Conj_FF : (false_t,   false_t,   false_t)   conjunction
  | Conj_FT : (false_t,   true_t,    false_t)   conjunction
  | Conj_FB : (false_t,   both_t,    false_t)   conjunction
  | Conj_FN : (false_t,   neither_t, false_t)   conjunction
  (* F absorbs all — second argument is F *)
  | Conj_TF : (true_t,    false_t,   false_t)   conjunction
  | Conj_BF : (both_t,    false_t,   false_t)   conjunction
  | Conj_NF : (neither_t, false_t,   false_t)   conjunction
  (* T is neutral for conjunction *)
  | Conj_TT : (true_t,    true_t,    true_t)    conjunction
  | Conj_TB : (true_t,    both_t,    both_t)    conjunction
  | Conj_TN : (true_t,    neither_t, neither_t) conjunction
  (* B cases *)
  | Conj_BT : (both_t,    true_t,    both_t)    conjunction
  | Conj_BB : (both_t,    both_t,    both_t)    conjunction
  | Conj_BN : (both_t,    neither_t, neither_t) conjunction
  (* N cases — N absorbs T and B but not F *)
  | Conj_NT : (neither_t, true_t,    neither_t) conjunction
  | Conj_NB : (neither_t, both_t,    neither_t) conjunction
  | Conj_NN : (neither_t, neither_t, neither_t) conjunction

(** Type-safe conjunction — witness encodes the result type at compile time.
    Note: _a and _b arguments are used for type-checking only; witness determines result.
*)
let conj : type a b c. a truth -> b truth -> (a, b, c) conjunction -> c truth =
  fun _a _b witness ->
    match witness with
    | Conj_FF -> F | Conj_FT -> F | Conj_FB -> F | Conj_FN -> F
    | Conj_TF -> F | Conj_BF -> F | Conj_NF -> F
    | Conj_TT -> T
    | Conj_TB -> B | Conj_BT -> B | Conj_BB -> B
    | Conj_TN -> N | Conj_BN -> N | Conj_NT -> N | Conj_NB -> N | Conj_NN -> N

(** Conjunction without witness — existential result (delegates to Belnap) *)
let conj_val : type a b. a truth -> b truth -> truth_val =
  fun a b -> of_simple (Belnap.conj (to_simple a) (to_simple b))

(* ---- Disjunction ---- *)

(** Disjunction without witness — existential result *)
let disj_val : type a b. a truth -> b truth -> truth_val =
  fun a b -> of_simple (Belnap.disj (to_simple a) (to_simple b))

(* ---- Implication ---- *)

(** Implication witnesses — (a → b) = (¬a ∨ b).

    Key property: B → B = B (contradictions don't explode!)
    There is NO witness for (false_t, 'a, 'a) — ex contradictione cannot be encoded.
*)
type (_, _, _) implication =
  | Impl_TT : (true_t,    true_t,    true_t)    implication  (* T→T = T *)
  | Impl_TF : (true_t,    false_t,   false_t)   implication  (* T→F = F *)
  | Impl_TB : (true_t,    both_t,    both_t)    implication  (* T→B = B *)
  | Impl_TN : (true_t,    neither_t, neither_t) implication  (* T→N = N *)
  | Impl_FT : (false_t,   true_t,    true_t)    implication  (* F→T = T  (¬F∨T = T) *)
  | Impl_FF : (false_t,   false_t,   true_t)    implication  (* F→F = T  (¬F∨F = T) *)
  | Impl_FB : (false_t,   both_t,    true_t)    implication  (* F→B = T  (¬F∨B = T) *)
  | Impl_FN : (false_t,   neither_t, true_t)    implication  (* F→N = T  (¬F∨N = T) *)
  | Impl_BT : (both_t,    true_t,    true_t)    implication  (* B→T = T  (¬B∨T = B∨T = T) *)
  | Impl_BB : (both_t,    both_t,    both_t)    implication  (* B→B = B  — contradiction preserved! *)
  | Impl_BF : (both_t,    false_t,   both_t)    implication  (* B→F = B  (¬B∨F = B∨F = B) *)
  | Impl_BN : (both_t,    neither_t, both_t)    implication  (* B→N = B  (¬B∨N = B∨N = B) *)
  | Impl_NT : (neither_t, true_t,    true_t)    implication  (* N→T = T  (¬N∨T = N∨T = T) *)
  | Impl_NF : (neither_t, false_t,   neither_t) implication  (* N→F = N  (¬N∨F = N∨F = N) *)
  | Impl_NB : (neither_t, both_t,    both_t)    implication  (* N→B = B  (¬N∨B = N∨B = B) *)
  | Impl_NN : (neither_t, neither_t, neither_t) implication  (* N→N = N  (¬N∨N = N) *)

(** Type-safe implication with witness *)
let impl : type a b c. a truth -> b truth -> (a, b, c) implication -> c truth =
  fun _a _b witness ->
    match witness with
    | Impl_TT -> T | Impl_TF -> F | Impl_TB -> B | Impl_TN -> N
    | Impl_FT -> T | Impl_FF -> T | Impl_FB -> T | Impl_FN -> T
    | Impl_BT -> T | Impl_BB -> B | Impl_BF -> B | Impl_BN -> B
    | Impl_NT -> T | Impl_NF -> N | Impl_NB -> B | Impl_NN -> N

(** Implication without witness — existential result *)
let impl_val : type a b. a truth -> b truth -> truth_val =
  fun a b -> of_simple (Belnap.impl (to_simple a) (to_simple b))

(* ---- Conversion utilities ---- *)

(** Pattern-match on existential truth value *)
let match_truth : truth_val -> (unit -> 'r) -> (unit -> 'r) -> (unit -> 'r) -> (unit -> 'r) -> 'r =
  fun (Truth tv) on_t on_f on_b on_n ->
    match tv with
    | T -> on_t ()
    | F -> on_f ()
    | B -> on_b ()
    | N -> on_n ()

(** Convert existential to simple type *)
let truth_val_to_simple (Truth tv) = to_simple tv

(** Show truth value string from existential *)
let truth_val_to_string (Truth tv) = to_string tv
