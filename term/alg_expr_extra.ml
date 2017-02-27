(******************************************************************************)
(*  _  __ * The Kappa Language                                                *)
(* | |/ / * Copyright 2010-2017 CNRS - Harvard Medical School - INRIA - IRIF  *)
(* | ' /  *********************************************************************)
(* | . \  * This file is distributed under the terms of the                   *)
(* |_|\_\ * GNU Lesser General Public License Version 3                       *)
(******************************************************************************)

let divide_expr_by_int e i =
  Locality.dummy_annot
      (Alg_expr.BIN_ALG_OP
              (Operator.DIV, e, Locality.dummy_annot (Alg_expr.CONST (Nbr.I i))))

type 'id corrected_rate_const =
  {
    num: Nbr.t ;
    den: Nbr.t ;
    var: 'id option
  }

let rec get_corrected_rate e =
  match e with
    Alg_expr.BIN_ALG_OP
      (Operator.MULT,(Alg_expr.CONST cst,_),e),_
  | Alg_expr.BIN_ALG_OP
      (Operator.MULT,e,(Alg_expr.CONST cst,_)),_
    ->
    begin
      match get_corrected_rate e with
      | None -> None
      | Some corrected_rate ->
        Some {corrected_rate with num = Nbr.mult cst corrected_rate.num}
    end
  | Alg_expr.BIN_ALG_OP
      (Operator.DIV,e,(Alg_expr.CONST cst,_)),_ ->
    begin
      match get_corrected_rate e with
      | None -> None
      | Some corrected_rate ->
        Some {corrected_rate with den = Nbr.mult cst corrected_rate.den}
    end
  | Alg_expr.BIN_ALG_OP
      (Operator.SUM,e1,e2),_ ->
    begin
      match get_corrected_rate e1 with
      | None -> None
      | Some corrected_rate1 ->
        begin
          match get_corrected_rate e2 with
          | Some corrected_rate2
            when compare corrected_rate1.var corrected_rate2.var = 0
              && Nbr.is_equal corrected_rate1.den corrected_rate2.den
            ->
            Some
              {
                corrected_rate1 with
                num = Nbr.add corrected_rate1.num corrected_rate2.num;
              }
          | Some corrected_rate2 when compare corrected_rate1.var corrected_rate2.var = 0 ->
            Some
              {
                corrected_rate1 with
                num =
                  Nbr.add
                    (Nbr.mult corrected_rate2.den corrected_rate1.num)
                    (Nbr.mult corrected_rate1.den corrected_rate2.num);
                den = Nbr.mult corrected_rate1.den corrected_rate2.den;
          }
          | None | Some _ -> None
        end
    end
  | Alg_expr.BIN_ALG_OP
      ((Operator.MULT | Operator.DIV | Operator.MINUS |
        Operator.POW | Operator.MODULO | Operator.MAX | Operator.MIN),_,_),_
  | Alg_expr.UN_ALG_OP _,_
  | Alg_expr.STATE_ALG_OP _,_
  | Alg_expr.KAPPA_INSTANCE _,_
  | Alg_expr.TOKEN_ID _,_
  | Alg_expr.IF _,_ -> None
  | Alg_expr.ALG_VAR id,_ -> Some
                    {
                      var = Some id ;
                      num = Nbr.one ;
                      den = Nbr.one }
  | Alg_expr.CONST cst,_ ->
    Some
      { var = None ;
        num = cst ;
        den = Nbr.one
      }

let print pr_var f corrected_rate_const =
  match corrected_rate_const with
  | None -> Format.fprintf f "None"
  | Some a ->
    begin
      match a.var with
      | Some _ ->
        (Format.fprintf f "(%a/%a).%a"
           Nbr.print a.num Nbr.print a.den pr_var a.var)
      | None ->
        Format.fprintf f "(%a/%a)" Nbr.print a.num Nbr.print a.den
    end

let necessarily_equal a_opt b_opt =
  match a_opt,b_opt
  with
  | None,_ | _,None -> false
  | Some a, Some b ->
    a.var = b.var
    && Nbr.is_equal (Nbr.mult a.num b.den) (Nbr.mult a.den b.num)
