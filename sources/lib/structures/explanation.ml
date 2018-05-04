(******************************************************************************)
(*                                                                            *)
(*     The Alt-Ergo theorem prover                                            *)
(*     Copyright (C) 2006-2013                                                *)
(*                                                                            *)
(*     Sylvain Conchon                                                        *)
(*     Evelyne Contejean                                                      *)
(*                                                                            *)
(*     Francois Bobot                                                         *)
(*     Mohamed Iguernelala                                                    *)
(*     Stephane Lescuyer                                                      *)
(*     Alain Mebsout                                                          *)
(*                                                                            *)
(*     CNRS - INRIA - Universite Paris Sud                                    *)
(*                                                                            *)
(*     This file is distributed under the terms of the Apache Software        *)
(*     License version 2.0                                                    *)
(*                                                                            *)
(*  ------------------------------------------------------------------------  *)
(*                                                                            *)
(*     Alt-Ergo: The SMT Solver For Software Verification                     *)
(*     Copyright (C) 2013-2017 --- OCamlPro SAS                               *)
(*                                                                            *)
(*     This file is distributed under the terms of the Apache Software        *)
(*     License version 2.0                                                    *)
(*                                                                            *)
(******************************************************************************)

open Format
open Options

module F = Formula

type dep = Form of Formula.t | Name of string

type exp =
  | Literal of Satml_types.Atom.atom
  | Fresh of int
  | Bj of F.t
  | Dep of dep


let compare_dep dep1 dep2 =
  match dep1, dep2 with 
  | Form f0, Form f1 ->  Formula.compare f0 f1
  | Name s0, Name s1 -> String.compare s0 s1
  | Form f, Name s -> -1
  | Name s, Form f -> 1

module S =
  Set.Make
    (struct
      type t = exp
      let compare a b = match a,b with
	| Fresh i1, Fresh i2 -> i1 - i2
	| Literal a  , Literal b   -> Satml_types.Atom.cmp_atom a b
        | Dep e1  , Dep e2   -> compare_dep e1 e2
        | Bj e1   , Bj e2    -> Formula.compare e1 e2

	| Literal _, _ -> -1
	| _, Literal _ -> 1

	| Fresh _, _ -> -1
	| _, Fresh _ -> 1

        | Dep _, _ -> 1
        | _, Dep _ -> -1

     end)

let is_empty t = S.is_empty t

type t = S.t

let empty = S.empty

let union s1 s2 =
  if s1 == s2 then s1 else S.union s1 s2

let singleton e = S.singleton e

let mem e s = S.mem e s

let remove e s =
  if S.mem e s then S.remove e s
  else raise Not_found

let iter_atoms f s = S.iter f s

let fold_atoms f s acc = S.fold f s acc

(* TODO : XXX : We have to choose the smallest ??? *)
let merge s1 s2 = s1

let fresh_exp =
  let r = ref (-1) in
  fun () ->
    incr r;
    Fresh !r

let remove_fresh fe s =
  if S.mem fe s then Some (S.remove fe s)
  else None

let add_fresh fe s = S.add fe s

let print fmt ex =
  if Options.debug_explanations () then begin
    fprintf fmt "{";
    S.iter (function
      | Literal a -> fprintf fmt "{Literal:%a}, " Satml_types.Atom.pr_atom a
      | Fresh i -> Format.fprintf fmt "{Fresh:%i}" i;
      | Dep (Form f) -> Format.fprintf fmt "{Dep of Form :%a}" Formula.print f
      | Dep (Name s) -> Format.fprintf fmt "{Dep of Name :%s}" s
      | Bj f -> Format.fprintf fmt "{BJ:%a}" Formula.print f
    ) ex;
    fprintf fmt "}"
  end

let print_proof fmt s =
  S.iter
    (fun e -> match e with
      | Dep (Form f) -> Format.fprintf fmt "  %a@." F.print f
      | Dep (Name s) -> Format.fprintf fmt "  %s@." s
      | Bj f -> assert false (* XXX or same as Dep ? *)
      | Fresh i -> assert false
      | Literal a -> assert false
    ) s

let dep_formulas_of s =
  S.fold (fun e acc ->
    match e with
    | Dep d -> d :: acc
    | _ -> assert false (*TODO*)
  ) s []

let get_formulas_of s =
  S.fold (fun e acc ->
    match e with
    | Dep (Form f) | Bj f -> F.Set.add f acc
    | Dep (Name s) -> acc
    | Fresh _ -> acc
    | Literal a -> assert false (*TODO*)
  ) s F.Set.empty

let bj_formulas_of s =
  S.fold (fun e acc ->
    match e with
      | Bj f -> F.Set.add f acc
      | Dep _ | Fresh _ -> acc
      | Literal a -> assert false (*TODO*)
  ) s F.Set.empty

let rec literals_of_acc lit fs f acc = match F.view f with
  | F.Literal _ ->
    if lit then f :: acc else acc
  | F.Unit (f1,f2) ->
    let acc = literals_of_acc false fs f1 acc in
    literals_of_acc false fs f2 acc
  | F.Clause (f1, f2, _) ->
    let acc = literals_of_acc true fs f1 acc in
    literals_of_acc true fs f2 acc
  | F.Lemma _ ->
    acc
  | F.Skolem {F.main = f1} | F.Let {F.let_f = f1} ->
    literals_of_acc true fs f1 acc

let literals_of ex =
  let fs  = get_formulas_of ex in
  F.Set.fold (literals_of_acc true fs) fs []

module MI = Map.Make (struct type t = int let compare = compare end)

let literals_ids_of ex =
  List.fold_left (fun acc f ->
    let i = F.id f in
    let m = try MI.find i acc with Not_found -> 0 in
    MI.add i (m + 1) acc
  ) MI.empty (literals_of ex)


let make_deps sf =
  Formula.Set.fold (fun l acc -> S.add (Bj l) acc) sf S.empty

let has_no_bj s =
  try S.iter (function Bj _ -> raise Exit | _ -> ())s; true
  with Exit -> false

let compare = S.compare

let subset = S.subset
