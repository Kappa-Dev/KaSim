(******************************************************************************)
(*  _  __ * The Kappa Language                                                *)
(* | |/ / * Copyright 2010-2017 CNRS - Harvard Medical School - INRIA - IRIF  *)
(* | ' /  *********************************************************************)
(* | . \  * This file is distributed under the terms of the                   *)
(* |_|\_\ * GNU Lesser General Public License Version 3                       *)
(******************************************************************************)

let float_is_zero x =
  match classify_float x with
  | FP_zero -> true
  | FP_normal | FP_subnormal |FP_infinite | FP_nan -> false

let pow x n =
  assert (n >= 0);
  let rec aux x n acc =
    if n = 0 then acc
    else aux x (pred n) (x*acc) in
  aux x n 1

let pow64 x n =
  assert (n >= Int64.zero);
  let rec aux x n acc =
    if n = Int64.zero then acc
    else aux x (Int64.pred n) (Int64.mul x acc) in
  aux x n Int64.one

let read_input () =
  let rec parse acc input =
    match Stream.next input with
    | '\n' -> acc
    | c -> parse (Printf.sprintf "%s%c" acc c) input in
  try
    let user_input = Stream.of_channel stdin in
    parse "" user_input
  with
  | Stream.Failure -> invalid_arg "Tools.Read_input: cannot read stream"

let not_an_id s =
  try
    String.iter
      (fun c ->
         let i = int_of_char c in
         if i < 48 || i > 122 ||
            (i > 57 && (i < 65 || (i > 90 && i <> 95 && i < 97)))
         then raise Not_found)
      s;
    false
  with Not_found -> true

let unsome default = function
  | None -> default
  | Some a -> a

let option_map f = function
  | Some x -> Some (f x)
  | None -> None

let array_fold_left_mapi f x a =
  let y = ref x in
  let o = Array.init (Array.length a)
      (fun i -> let (y',out) = f i !y a.(i) in
        let () = y := y' in
        out) in
  (!y,o)

let array_map_of_list f l =
  let len = List.length l in
  let rec fill i v = function
    | [] -> ()
    | x :: l ->
      Array.unsafe_set v i (f x);
      fill (succ i) v l in
  match l with
  | [] -> [||]
  | x :: l ->
    let ans = Array.make len (f x) in
    let () = fill 1 ans l in
    ans

let array_rev_of_list = function
  | [] -> [||]
  | h :: t ->
    let l = succ (List.length t) in
    let out = Array.make l h in
    let rec fill i = function
      | [] -> assert (i= -1)
      | h' :: t' ->
        let () = Array.unsafe_set out i h' in
        fill (pred i) t' in
    let () = fill (l - 2) t in
    out

let array_fold_lefti f x a =
  let y = ref x in
  let () = Array.iteri (fun i e -> y := f i !y e) a in
  !y

let array_fold_left2i  f x a1 a2 =
  let l = Array.length a1 in
  if l <> Array.length a2 then raise (Invalid_argument "array_fold_left2i")
  else array_fold_lefti (fun i x e -> f i x e a2.(i)) x a1

let array_filter f a =
  array_fold_lefti (fun i acc x -> if f i x then i :: acc else acc) [] a

let array_min_equal_not_null l1 l2 =
  if Array.length l1 <> Array.length l2 then None
  else
    let rec f j =
      if j = Array.length l1 then Some ([],[])
      else
        let (nb1,ag1) = l1.(j) in
        let (nb2,ag2) = l2.(j) in
        if nb1 <> nb2 then None
        else if nb1 = 0 then f (succ j)
        else
          let rec aux i va out =
            if i = Array.length l1 then Some out
            else
              let (nb1,ag1) = l1.(i) in
              let (nb2,ag2) = l2.(i) in
              if nb1 <> nb2 then None
              else if nb1 > 0 && nb1 < va then aux (succ i) nb1 (ag1,ag2)
              else aux (succ i) va out in
          aux (succ j) nb1 (ag1,ag2) in
    f 0

let iteri f i =
  let rec aux j = if j < i then let () = f j in aux (succ j) in
  aux 0

let rec recti f x i =
  if 0 < i then let i' = pred i in recti f (f x i') i' else x

let min_pos_int_not_zero (keya,dataa) (keyb,datab) =
  if keya = 0 then keyb,datab
  else if keyb = 0 then keya,dataa
  else if compare keya keyb > 0 then keyb,datab
  else keya,dataa

let max_pos_int_not_zero (keya,dataa) (keyb,datab) =
  if compare keya keyb > 0 then keya,dataa else keyb,datab
