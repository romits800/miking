(*
   Miking is licensed under the MIT license.
   Copyright (C) David Broman. See file LICENSE.txt

   The main experiment platform for parallelization.
   Main contributer: Romy Tsoupidi
*)


open Utils
open Ustring.Op
open Printf
open Ast
open Msg
open Printf
open Pprint
(* open Lazy *)

(* open Unix *)

let prog_argv = ref []          (* Argv for the program that is executed *)

(* type delayedmap = { lab: int; dm: dmap} *)

let get_time () =
    Unix.gettimeofday()
                    
(* let dm = ref {lab=0; dm=DelayedMap.empty} *)
(* let dmready = ref DelayedMap.empty *)



(* let eval_dt f t env l =
 *   let tm = f env t in
 *   dmready := DelayedMap.add l (Atomic.make t) !dmready *)
      

(* let find_ready l =
 *   try
 *     Some (Atomic.get (DelayedMap.find l !dmready))
 *   with Not_found -> None *)

module DelayedMap = Map.Make(struct type t = tm Domain.t
                              let compare = compare end)
          
type dmap = tm option DelayedMap.t 
              

          
let delayedmap = Atomic.make DelayedMap.empty

let find_dm d =
  let dm = Atomic.get delayedmap in
  DelayedMap.find d dm

let rec add_dm d tm =
  let dm = Atomic.get delayedmap in
  let dm' = DelayedMap.add d tm dm in
  match (Atomic.compare_and_set delayedmap dm dm')
  with
    true -> ()
  | false -> add_dm d tm


let count = ref 0

let inc_count () =
  count := !count + 1

let set_count_zero () =
  count := 0


let max_num_threads = ref 6

let set_max_threads mt =
  max_num_threads := mt


let count_threads = Atomic.make 0

let get_count_threads () = Atomic.get count_threads

let set_count_threads num =
  Atomic.set count_threads num

let rec inc_count_threads () =
  let oldv = Atomic.get count_threads in
  let newv = oldv + 1 in
  if newv <= !max_num_threads then (
    match (Atomic.compare_and_set count_threads oldv newv)
    with
    | true -> Some newv
    | false -> inc_count_threads()
  )
  else None

let rec dec_count_threads () =
  let oldv = Atomic.get count_threads in
  let newv = oldv - 1 in
  if newv <= !max_num_threads then (
    match (Atomic.compare_and_set count_threads oldv newv)
    with
    | true -> Some newv
    | false -> dec_count_threads()
  )
  else None

let insert_dt f t =
  match inc_count_threads() with
    None -> None
  | Some id ->
     let d = Domain.spawn (fun () -> f t) in                (* printf "Threads created %d\n" (get_count_threads () ); *)
     (* let d = insert_dt (fun t -> eval env t) t2  in *)
     add_dm d None;
                   (* TmConst (fi, CDelayed (f, d, id)) *)
     Some (d,id)

let get_dt d =
  match find_dm d with
  | None ->
     let res = Domain.join d in
     add_dm d (Some res);
     (* dec_count_threads(); *)
     res
  | Some tm -> tm

(* let rec dec_count_threads () = *)
(*   let oldv = Atomic.get count_threads in *)
(*   let newv = oldv - 1 in *)
(*   match (Atomic.compare_and_set count_threads oldv newv) *)
(*   with *)
(*   | true -> () *)
(*   | false -> dec_count_threads() *)

(* let find_dt l =
 *   try
 *     Some (Atomic.get (DelayedMap.find l !dm.dm))
 *   with Not_found -> None *)


(* let readymap = ref DelayedMap.empty *)


(* Debug options *)
let enable_debug_normalize = false
let enable_debug_normalize_env = false
let enable_debug_readback = false
let enable_debug_readback_env = false
let enable_debug_eval = false
let enable_debug_eval_env = false
let enable_debug_after_peval = false

(* Evaluation of atoms. This is changed depending on the DSL *)
let empty_eval_atom fi id tms v = v
let eval_atom = ref empty_eval_atom


(* Traditional map function on unified collection (UC) types *)
let rec ucmap f uc = match uc with
  | UCLeaf(tms) -> UCLeaf(List.map f tms)
  | UCNode(uc1,uc2) -> UCNode(ucmap f uc1, ucmap f uc2)


(* Print out error message when a unit test fails *)
let unittest_failed fi t1 t2=
  uprint_endline
    (match fi with
    | Info(filename,l1,_,_,_) -> us"\n ** Unit test FAILED on line " ^.
        us(string_of_int l1) ^. us" **\n    LHS: " ^. (pprint false t1) ^.
        us"\n    RHS: " ^. (pprint false t2)
    | NoInfo -> us"Unit test FAILED ")

(* Add pattern variables to environment. Used in the debruijn function *)
let rec patvars env pat =
  match pat with
  | PatIdent(_,x) -> x::env
  | PatChar(_,_) -> env
  | PatUC(fi,p::ps,o,u) -> patvars (patvars env p) (PatUC(fi,ps,o,u))
  | PatUC(fi,[],o,u) -> env
  | PatBool(_,_) -> env
  | PatInt(_,_) -> env
  | PatConcat(_,p1,p2) -> patvars (patvars env p1) p2


(* Convert a term into de Bruijn indices *)
let rec debruijn env t =
  match t with
  | TmVar(fi,x,_,_) ->
    let rec find env n = match env with
      | y::ee -> if y =. x then n else find ee (n+1)
      | [] -> raise_error fi ("Unknown variable '" ^ Ustring.to_utf8 x ^ "'")
    in TmVar(fi,x,find env 0,false)
  | TmLam(fi,x,t1) -> TmLam(fi,x,debruijn (x::env) t1)
  | TmClos(fi,x,t1,env1,_) -> failwith "Closures should not be available."
  | TmApp(fi,t1,t2) -> TmApp(fi,debruijn env t1,debruijn env t2)
  | TmConst(_,_) -> t
  | TmFix(_) -> t
  | TmPEval(_) -> t
  | TmNow(_) -> t
  | TmLater(_,_) -> t
  | TmIfexp(_,_,_) -> t
  | TmChar(_,_) -> t
  | TmExprSeq(fi,t1,t2) -> TmExprSeq(fi,debruijn env t1,debruijn env t2)
  | TmUC(fi,uct,o,u) -> TmUC(fi, UCLeaf(List.map (debruijn env) (uct2list uct)),o,u)
  | TmUtest(fi,t1,t2,tnext)
      -> TmUtest(fi,debruijn env t1,debruijn env t2,debruijn env tnext)
  | TmMatch(fi,t1,cases) ->
      TmMatch(fi,debruijn env t1,
               List.map (fun (Case(fi,pat,tm)) ->
                 Case(fi,pat,debruijn (patvars env pat) tm)) cases)
  | TmNop -> t


(* Check if two value terms are equal *)
let rec val_equal v1 v2 =
  match v1,v2 with
  | TmChar(_,n1),TmChar(_,n2) -> n1 = n2
  | TmConst(_,c1),TmConst(_,c2) -> c1 = c2
  | TmUC(_,t1,o1,u1),TmUC(_,t2,o2,u2) ->
      let rec eql lst1 lst2 = match lst1,lst2 with
        | l1::ls1,l2::ls2 when val_equal l1 l2 -> eql ls1 ls2
        | [],[] -> true
        | _ -> false
      in o1 = o2 && u1 = u2 && eql (uct2revlist t1) (uct2revlist t2)
  | TmNop,TmNop -> true
  | _ -> false

let ustring2uctstring s =
  let ls = List.map (fun i -> TmChar(NoInfo,i)) (ustring2list s) in
  TmUC(NoInfo,UCLeaf(ls),UCOrdered,UCMultivalued)


(* Update all UC to have the form of lists *)
let rec make_tm_for_match tm =
  let rec mklist uc acc =
    match uc with
    | UCNode(uc1,uc2) -> (mklist uc2 (mklist uc1 acc))
    | UCLeaf(lst) -> (List.map make_tm_for_match lst)::acc
  in
  let rec mkuclist lst acc =
    match lst with
    | x::xs -> mkuclist xs (UCNode(UCLeaf(x),acc))
    | [] -> acc
  in
  match tm with
  | TmUC(fi,uc,o,u) ->
    TmUC(fi,mkuclist (mklist uc []) (UCLeaf([])),o,u)
  | _ -> tm

(* Check if a UC struct has zero length *)
let rec uctzero uct =
  match uct with
  | UCNode(n1,n2) -> (uctzero n1) && (uctzero n2)
  | UCLeaf([]) -> true
  | UCLeaf(_) -> false


(* Matches a pattern against a value and returns a new environment
   Notes:
    - final is used to detect if a sequence be checked to be complete or not *)
let rec eval_match env pat t final =
    match pat,t with
  | PatIdent(_,x1),v -> Some(v::env,TmNop)
  | PatChar(_,c1),TmChar(_,c2) -> if c1 = c2 then Some(env,TmNop) else None
  | PatChar(_,_),_ -> None
  | PatUC(fi1,p::ps,o1,u1),TmUC(fi2,UCLeaf(t::ts),o2,u2) ->
    (match eval_match env p t true with
    | Some(env,_) ->
      eval_match env (PatUC(fi1,ps,o1,u1)) (TmUC(fi2,UCLeaf(ts),o2,u2)) final
    | None -> None)
  | PatUC(fi1,p::ps,o1,u1),TmUC(fi2,UCLeaf([]),o2,u2) -> None
  | PatUC(fi1,p::ps,o1,u1),TmUC(fi2,UCNode(UCLeaf(t::ts),t2),o2,u2) ->
    (match eval_match env p t true with
    | Some(env,_) ->
      eval_match env (PatUC(fi1,ps,o1,u1))
        (TmUC(fi2,UCNode(UCLeaf(ts),t2),o2,u2)) final
    | None -> None)
  | PatUC(fi1,p::ps,o1,u1),TmUC(fi2,UCNode(UCLeaf([]),t2),o2,u2) ->
      eval_match env pat (TmUC(fi2,t2,o2,u2)) final
  | PatUC(fi1,[],o1,u1),TmUC(fi2,uct,_,_) when uctzero uct && final -> Some(env,TmNop)
  | PatUC(fi1,[],o1,u1),t when not final-> Some(env,t)
  | PatUC(fi1,lst,o1,u2),t -> None
  | PatBool(_,b1),TmConst(_,CBool(b2)) -> if b1 = b2 then Some(env,TmNop) else None
  | PatBool(_,_),_ -> None
  | PatInt(fi,i1),TmConst(_,CInt(i2)) -> if i1 = i2 then Some(env,TmNop) else None
  | PatInt(_,_),_ -> None
  | PatConcat(_,PatIdent(_,x),p2),_ ->
      failwith "Pattern variable first is not part of Ragnar--"
  | PatConcat(_,p1,p2),t1 ->
    (match eval_match env p1 t1 false with
    | Some(env,t2) -> eval_match env p2 t2 (final && true)
    | None -> None)

let fail_constapp fi = raise_error fi "Incorrect application "

(* Debug function used in the PE readback function *)
let debug_readback env n t =
  if enable_debug_readback then
    (printf "\n-- readback --   n=%d  \n" n;
     uprint_endline (pprint true t);
     if enable_debug_readback_env then
        uprint_endline (pprint_env env))
  else ()

(* Debug function used in the PE normalize function *)
let debug_normalize env n t =
  if enable_debug_normalize then
    (printf "\n-- normalize --   n=%d" n;
     uprint_endline (pprint true t);
     if enable_debug_normalize_env then
        uprint_endline (pprint_env env))
  else ()

(* Debug function used in the eval function *)
let debug_eval env t =
  if enable_debug_eval then
    (printf "\n-- eval -- \n";
  uprint_endline (pprint true t);
  if enable_debug_eval_env then
    uprint_endline (pprint_env env))
  else ()

(* Debug function used after partial evaluation *)
let debug_after_peval t =
  if enable_debug_after_peval then
    (printf "\n-- after peval --  \n";
     uprint_endline (pprint true t);
     t)
  else t


(* Mapping between named builtin functions (intrinsics) and the
   correspond constants *)
let builtin =
  [("not",Cnot);("and",Cand(None));("or",Cor(None));
   ("addi",Caddi(None));("subi",Csubi(None));("muli",Cmuli(None));
   ("divi",Cdivi(None));("modi",Cmodi(None));("negi",Cnegi);
   ("lti",Clti(None));("leqi",Cleqi(None));("gti",Cgti(None));("geqi",Cgeqi(None));
   ("eqi",Ceqi(None));("neqi",Cneqi(None));
   ("slli",Cslli(None));("srli",Csrli(None));("srai",Csrai(None));
   ("addf",Caddf(None));("subf",Csubf(None));("mulf",Cmulf(None));
   ("divf",Cdivf(None));("negf",Cnegf);
   ("add",Cadd(TNone));("sub",Csub(TNone));("mul",Cmul(TNone));
   ("div",Cdiv(TNone));("neg",Cneg);
   ("dstr",CDStr);("dprint",CDPrint);("print",CPrint);("argv",CArgv);
   ("concat",CConcat(None))]



(* Evaluates a constant application. This is the standard delta function
   delta(c,v) with the exception that it returns an expression and not
   a value. This is why the returned value is evaluated in the eval() function.
   The reason for this is that if-expressions return expressions
   and not values. *)
let delta c v  =
  match c,v with
    | Clater(None), TmConst(fi, CFloat(f)) ->
       TmConst(fi, Clater(Some(f)))
    | Clater(None), t  -> fail_constapp (tm_info t)
    | Clater(_), t -> fail_constapp (tm_info t) 
    (* | Cnow, TmConst(fi, CDelayed(f,l,env)) ->
     *    Domain.join l *)
    | Cnow, t ->  fail_constapp (tm_info t)
    | CDelayed(f,l,env),t-> fail_constapp (tm_info t) 
    (* MCore boolean intrinsics *)
    | CBool(_),t -> fail_constapp (tm_info t)

    | Cnot,TmConst(fi,CBool(v)) -> TmConst(fi,CBool(not v))
    | Cnot,t ->  fail_constapp (tm_info t)

    | Cand(None),TmConst(fi,CBool(v)) -> TmConst(fi,Cand(Some(v)))
    | Cand(Some(v1)),TmConst(fi,CBool(v2)) -> TmConst(fi,CBool(v1 && v2))
    | Cand(None),t | Cand(Some(_)),t  ->   fail_constapp (tm_info t)

    | Cor(None),TmConst(fi,CBool(v)) -> TmConst(fi,Cor(Some(v)))
    | Cor(Some(v1)),TmConst(fi,CBool(v2)) -> TmConst(fi,CBool(v1 || v2))
    | Cor(None),t | Cor(Some(_)),t  -> fail_constapp (tm_info t)

    (* MCore integer intrinsics *)
    | CInt(_),t -> fail_constapp (tm_info t)

    | Caddi(None),TmConst(fi,CInt(v)) -> TmConst(fi,Caddi(Some(v)))
    | Caddi(Some(v1)),TmConst(fi,CInt(v2)) -> TmConst(fi,CInt(v1 + v2))
    | Caddi(None),t | Caddi(Some(_)),t  ->
         let s1 = pprint true t in
         printf "T %s\n%!" (Ustring.to_utf8 s1);
failwith("Addi"); fail_constapp (tm_info t)

    | Csubi(None),TmConst(fi,CInt(v)) -> TmConst(fi,Csubi(Some(v)))
    | Csubi(Some(v1)),TmConst(fi,CInt(v2)) -> TmConst(fi,CInt(v1 - v2))
    | Csubi(None),t | Csubi(Some(_)),t  ->  fail_constapp (tm_info t)

    | Cmuli(None),TmConst(fi,CInt(v)) -> TmConst(fi,Cmuli(Some(v)))
    | Cmuli(Some(v1)),TmConst(fi,CInt(v2)) -> TmConst(fi,CInt(v1 * v2))
    | Cmuli(None),t | Cmuli(Some(_)),t  -> fail_constapp (tm_info t)

    | Cdivi(None),TmConst(fi,CInt(v)) -> TmConst(fi,Cdivi(Some(v)))
    | Cdivi(Some(v1)),TmConst(fi,CInt(v2)) -> TmConst(fi,CInt(v1 / v2))
    | Cdivi(None),t | Cdivi(Some(_)),t  ->fail_constapp (tm_info t)

    | Cmodi(None),TmConst(fi,CInt(v)) -> TmConst(fi,Cmodi(Some(v)))
    | Cmodi(Some(v1)),TmConst(fi,CInt(v2)) -> TmConst(fi,CInt(v1 mod v2))
    | Cmodi(None),t | Cmodi(Some(_)),t  -> fail_constapp (tm_info t)

    | Cnegi,TmConst(fi,CInt(v)) -> TmConst(fi,CInt((-1)*v))
    | Cnegi,t ->  fail_constapp (tm_info t)

    | Clti(None),TmConst(fi,CInt(v)) -> TmConst(fi,Clti(Some(v)))
    | Clti(Some(v1)),TmConst(fi,CInt(v2)) -> TmConst(fi,CBool(v1 < v2))
    | Clti(None),t | Clti(Some(_)),t  -> fail_constapp (tm_info t)

    | Cleqi(None),TmConst(fi,CInt(v)) -> TmConst(fi,Cleqi(Some(v)))
    | Cleqi(Some(v1)),TmConst(fi,CInt(v2)) -> TmConst(fi,CBool(v1 <= v2))
    | Cleqi(None),t | Cleqi(Some(_)),t  -> fail_constapp (tm_info t)

    | Cgti(None),TmConst(fi,CInt(v)) -> TmConst(fi,Cgti(Some(v)))
    | Cgti(Some(v1)),TmConst(fi,CInt(v2)) -> TmConst(fi,CBool(v1 > v2))
    | Cgti(None),t | Cgti(Some(_)),t  -> fail_constapp (tm_info t)

    | Cgeqi(None),TmConst(fi,CInt(v)) -> TmConst(fi,Cgeqi(Some(v)))
    | Cgeqi(Some(v1)),TmConst(fi,CInt(v2)) -> TmConst(fi,CBool(v1 >= v2))
    | Cgeqi(None),t | Cgeqi(Some(_)),t  -> fail_constapp (tm_info t)

    | Ceqi(None),TmConst(fi,CInt(v)) -> TmConst(fi,Ceqi(Some(v)))
    | Ceqi(Some(v1)),TmConst(fi,CInt(v2)) -> TmConst(fi,CBool(v1 = v2))
    | Ceqi(None),t | Ceqi(Some(_)),t  ->  fail_constapp (tm_info t)

    | Cneqi(None),TmConst(fi,CInt(v)) -> TmConst(fi,Cneqi(Some(v)))
    | Cneqi(Some(v1)),TmConst(fi,CInt(v2)) -> TmConst(fi,CBool(v1 <> v2))
    | Cneqi(None),t | Cneqi(Some(_)),t  ->  fail_constapp (tm_info t)

    | Cslli(None),TmConst(fi,CInt(v)) -> TmConst(fi,Cslli(Some(v)))
    | Cslli(Some(v1)),TmConst(fi,CInt(v2)) -> TmConst(fi,CInt(v1 lsl v2))
    | Cslli(None),t | Cslli(Some(_)),t  -> fail_constapp (tm_info t)

    | Csrli(None),TmConst(fi,CInt(v)) -> TmConst(fi,Csrli(Some(v)))
    | Csrli(Some(v1)),TmConst(fi,CInt(v2)) -> TmConst(fi,CInt(v1 lsr v2))
    | Csrli(None),t | Csrli(Some(_)),t  -> fail_constapp (tm_info t)

    | Csrai(None),TmConst(fi,CInt(v)) -> TmConst(fi,Csrai(Some(v)))
    | Csrai(Some(v1)),TmConst(fi,CInt(v2)) -> TmConst(fi,CInt(v1 asr v2))
    | Csrai(None),t | Csrai(Some(_)),t  -> fail_constapp (tm_info t)

    (* MCore intrinsic: Floating-point number constant and operations *)
    | CFloat(_),t ->  fail_constapp (tm_info t)

    | Caddf(None),TmConst(fi,CFloat(v)) -> TmConst(fi,Caddf(Some(v)))
    | Caddf(Some(v1)),TmConst(fi,CFloat(v2)) -> TmConst(fi,CFloat(v1 +. v2))
    | Caddf(None),t | Caddf(Some(_)),t  ->  fail_constapp (tm_info t)

    | Csubf(None),TmConst(fi,CFloat(v)) -> TmConst(fi,Csubf(Some(v)))
    | Csubf(Some(v1)),TmConst(fi,CFloat(v2)) -> TmConst(fi,CFloat(v1 -. v2))
    | Csubf(None),t | Csubf(Some(_)),t  -> fail_constapp (tm_info t)

    | Cmulf(None),TmConst(fi,CFloat(v)) -> TmConst(fi,Cmulf(Some(v)))
    | Cmulf(Some(v1)),TmConst(fi,CFloat(v2)) -> TmConst(fi,CFloat(v1 *. v2))
    | Cmulf(None),t | Cmulf(Some(_)),t  -> fail_constapp (tm_info t)

    | Cdivf(None),TmConst(fi,CFloat(v)) -> TmConst(fi,Cdivf(Some(v)))
    | Cdivf(Some(v1)),TmConst(fi,CFloat(v2)) -> TmConst(fi,CFloat(v1 /. v2))
    | Cdivf(None),t | Cdivf(Some(_)),t  -> fail_constapp (tm_info t)

    | Cnegf,TmConst(fi,CFloat(v)) -> TmConst(fi,CFloat((-1.0)*.v))
    | Cnegf,t -> fail_constapp (tm_info t)

    (* Mcore intrinsic: Polymorphic integer and floating-point numbers *)

    | Cadd(TNone),TmConst(fi,CInt(v)) -> TmConst(fi,Cadd(TInt(v)))
    | Cadd(TNone),TmConst(fi,CFloat(v)) -> TmConst(fi,Cadd(TFloat(v)))
    | Cadd(TInt(v1)),TmConst(fi,CInt(v2)) -> TmConst(fi,CInt(v1 + v2))
    | Cadd(TFloat(v1)),TmConst(fi,CFloat(v2)) -> TmConst(fi,CFloat(v1 +. v2))
    | Cadd(TFloat(v1)),TmConst(fi,CInt(v2)) -> TmConst(fi,CFloat(v1 +. (float_of_int v2)))
    | Cadd(TInt(v1)),TmConst(fi,CFloat(v2)) -> TmConst(fi,CFloat((float_of_int v1) +. v2))
    | Cadd(_),t ->  fail_constapp (tm_info t)

    | Csub(TNone),TmConst(fi,CInt(v)) -> TmConst(fi,Csub(TInt(v)))
    | Csub(TNone),TmConst(fi,CFloat(v)) -> TmConst(fi,Csub(TFloat(v)))
    | Csub(TInt(v1)),TmConst(fi,CInt(v2)) -> TmConst(fi,CInt(v1 - v2))
    | Csub(TFloat(v1)),TmConst(fi,CFloat(v2)) -> TmConst(fi,CFloat(v1 -. v2))
    | Csub(TFloat(v1)),TmConst(fi,CInt(v2)) -> TmConst(fi,CFloat(v1 -. (float_of_int v2)))
    | Csub(TInt(v1)),TmConst(fi,CFloat(v2)) -> TmConst(fi,CFloat((float_of_int v1) -. v2))
    | Csub(_),t -> fail_constapp (tm_info t)

    | Cmul(TNone),TmConst(fi,CInt(v)) -> TmConst(fi,Cmul(TInt(v)))
    | Cmul(TNone),TmConst(fi,CFloat(v)) -> TmConst(fi,Cmul(TFloat(v)))
    | Cmul(TInt(v1)),TmConst(fi,CInt(v2)) -> TmConst(fi,CInt(v1 * v2))
    | Cmul(TFloat(v1)),TmConst(fi,CFloat(v2)) -> TmConst(fi,CFloat(v1 *. v2))
    | Cmul(TFloat(v1)),TmConst(fi,CInt(v2)) -> TmConst(fi,CFloat(v1 *. (float_of_int v2)))
    | Cmul(TInt(v1)),TmConst(fi,CFloat(v2)) -> TmConst(fi,CFloat((float_of_int v1) *. v2))
    | Cmul(_),t -> fail_constapp (tm_info t)

    | Cdiv(TNone),TmConst(fi,CInt(v)) -> TmConst(fi,Cdiv(TInt(v)))
    | Cdiv(TNone),TmConst(fi,CFloat(v)) -> TmConst(fi,Cdiv(TFloat(v)))
    | Cdiv(TInt(v1)),TmConst(fi,CInt(v2)) -> TmConst(fi,CInt(v1 / v2))
    | Cdiv(TFloat(v1)),TmConst(fi,CFloat(v2)) -> TmConst(fi,CFloat(v1 /. v2))
    | Cdiv(TFloat(v1)),TmConst(fi,CInt(v2)) -> TmConst(fi,CFloat(v1 /. (float_of_int v2)))
    | Cdiv(TInt(v1)),TmConst(fi,CFloat(v2)) -> TmConst(fi,CFloat((float_of_int v1) /. v2))
    | Cdiv(_),t -> fail_constapp (tm_info t)

    | Cneg,TmConst(fi,CFloat(v)) -> TmConst(fi,CFloat((-1.0)*.v))
    | Cneg,TmConst(fi,CInt(v)) -> TmConst(fi,CInt((-1)*v))
    | Cneg,t -> fail_constapp (tm_info t)

    (* MCore debug and stdio intrinsics *)
    | CDStr, t -> ustring2uctstring (pprint true t)
    | CDPrint, t -> uprint_endline (pprint true t);TmNop
    | CPrint, t ->
      (match t with
      | TmUC(_,uct,_,_) ->
        uct2list uct |> uc2ustring |> list2ustring |> Ustring.to_utf8
      |> printf "%s"; TmNop
      | _ -> raise_error (tm_info t) "Cannot print value with this type")
    | CArgv,_ ->
      let lst = List.map (fun x -> ustring2uctm NoInfo (us x)) (!prog_argv)
      in TmUC(NoInfo,UCLeaf(lst),UCOrdered,UCMultivalued)
    | CConcat(None),t -> TmConst(NoInfo,CConcat((Some t)))
    | CConcat(Some(TmUC(l,t1,o1,u1))),TmUC(_,t2,o2,u2)
      when o1 = o2 && u1 = u2 -> TmUC(l,UCNode(t1,t2),o1,u1)
    | CConcat(Some(tm1)),TmUC(l,t2,o2,u2) -> TmUC(l,UCNode(UCLeaf([tm1]),t2),o2,u2)
    | CConcat(Some(TmUC(l,t1,o1,u1))),tm2 -> TmUC(l,UCNode(t1,UCLeaf([tm2])),o1,u1)
    | CConcat(Some(_)),t -> fail_constapp (tm_info t)

    (* Ragnar polymorphic functions, special case for Ragnar in the boot interpreter.
       These functions should be defined using well-defined ad-hoc polymorphism
       in the real Ragnar compiler. *)
    | CPolyEq(None),t -> TmConst(NoInfo,CPolyEq((Some(t))))
    | CPolyEq(Some(TmConst(_,c1))),TmConst(_,c2) -> TmConst(NoInfo,CBool(c1 = c2))
    | CPolyEq(Some(TmChar(_,v1))),TmChar(_,v2) -> TmConst(NoInfo,CBool(v1 = v2))
    | CPolyEq(Some(TmUC(_,_,_,_) as v1)),(TmUC(_,_,_,_) as v2) -> TmConst(NoInfo,CBool(val_equal v1 v2))
    | CPolyEq(Some(_)),t  -> fail_constapp (tm_info t)

    | CPolyNeq(None),t -> TmConst(NoInfo,CPolyNeq(Some(t)))
    | CPolyNeq(Some(TmConst(_,c1))),TmConst(_,c2) -> TmConst(NoInfo,CBool(c1 <> c2))
    | CPolyNeq(Some(TmChar(_,v1))),TmChar(_,v2) -> TmConst(NoInfo,CBool(v1 <> v2))
    | CPolyNeq(Some(TmUC(_,_,_,_) as v1)),(TmUC(_,_,_,_) as v2) -> TmConst(NoInfo,CBool(not (val_equal v1 v2)))
    | CPolyNeq(Some(_)),t  -> fail_constapp (tm_info t)

    (* Atom - an untyped lable that can be used to implement
       domain specific constructs *)
    | CAtom(id,tms),t -> !eval_atom (tm_info t) id tms t



(* Optimize away constant applications (mul with 0 or 1, add with 0 etc.) *)
let optimize_const_app fi v1 v2 =
  match v1,v2 with
  (*|   0 * x  ==>  0   |*)
  | TmConst(_,Cmuli(Some(0))),v2 -> TmConst(fi,CInt(0))
  (*|   1 * x  ==>  x   |*)
  | TmConst(_,Cmuli(Some(1))),v2 -> v2
  (*|   0 + x  ==>  x   |*)
  | TmConst(_,Caddi(Some(0))),v2 -> v2
  (*|   0 * x  ==>  0   |*)
  | TmApp(_,TmConst(_,Cmuli(None)),TmConst(_,CInt(0))),vv1 -> TmConst(fi,CInt(0))
  (*|   1 * x  ==>  x   |*)
  | TmApp(_,TmConst(_,Cmuli(None)),TmConst(_,CInt(1))),vv1 -> vv1
  (*|   0 + x  ==>  x   |*)
  | TmApp(_,TmConst(_,Caddi(None)),TmConst(_,CInt(0))),vv1 -> vv1
  (*|   x * 0  ==>  0   |*)
  | TmApp(_,TmConst(_,Cmuli(None)),vv1),TmConst(_,CInt(0)) -> TmConst(fi,CInt(0))
  (*|   x * 1  ==>  x   |*)
  | TmApp(_,TmConst(_,Cmuli(None)),vv1),TmConst(_,CInt(1)) -> vv1
  (*|   x + 0  ==>  x   |*)
  | TmApp(_,TmConst(_,Caddi(None)),vv1),TmConst(_,CInt(0)) -> vv1
  (*|   x - 0  ==>  x   |*)
  | TmApp(_,TmConst(_,Csubi(None)),vv1),TmConst(_,CInt(0)) -> vv1
  (*|   x op y  ==>  res(x op y)   |*)
  | TmConst(fi1,c1),(TmConst(fi2,c2) as tt)-> delta c1 tt
  (* No optimization *)
  | vv1,vv2 -> TmApp(fi,vv1,vv2)


(* The readback function is the second pass of the partial evaluation.
   It removes symbols for the term. If this is the complete version,
   this is the final pass before JIT *)
let rec readback env n t =
  debug_readback env n t;
  match t with
  (* Variables using debruijn indices. Need to evaluate because fix point. *)
  | TmVar(fi,x,k,false) -> readback env n (List.nth env k)
  (* Variables as PE symbol. Convert symbol to de bruijn index. *)
  | TmVar(fi,x,k,true) -> TmVar(fi,x,n-k,false)
  (* Lambda *)
  | TmLam(fi,x,t1) -> TmLam(fi,x,readback (TmVar(fi,x,n+1,true)::env) (n+1) t1)
  (* Normal closure *)
  | TmClos(fi,x,t1,env2,false) -> t
  (* PE closure *)
  | TmClos(fi,x,t1,env2,true) ->
      TmLam(fi,x,readback (TmVar(fi,x,n+1,true)::env2) (n+1) t1)
  (* Application *)
  | TmApp(fi,t1,t2) -> optimize_const_app fi (readback env n t1) (readback env n t2)
  (* Constant, fix, and PEval  *)
  | TmConst(_,_) | TmFix(_) | TmPEval(_) -> t
  | TmLater(_,_) | TmNow(_) -> t
  (* If expression *)
  | TmIfexp(fi,x,Some(t3)) -> TmIfexp(fi,x,Some(readback env n t3))
  | TmIfexp(fi,x,None) -> TmIfexp(fi,x,None)
  (* Other old, to remove *)
  | TmChar(_,_) -> t
  | TmExprSeq(fi,t1,t2) ->
      TmExprSeq(fi,readback env n t1, readback env n t2)
  | TmUC(fi,uct,o,u) -> t
  | TmUtest(fi,t1,t2,tnext) ->
      TmUtest(fi,readback env n t1, readback env n t2,tnext)
  | TmMatch(fi,t1,cases) ->
      TmMatch(fi,readback env n t1,cases)
  | TmNop -> t




(* The function normalization function that leaves symbols in the
   term. These symbols are then removed using the readback function.
   'env' is the environment, 'n' the lambda depth number, 'm'
   the number of lambdas that we can go under, and
   't' the term. *)
let rec normalize env n t =
  debug_normalize env n t;
  match t with
  (* Variables using debruijn indices. *)
  | TmVar(fi,x,n,false) -> normalize env n (List.nth env n)
  (* PEMode variable (symbol) *)
  | TmVar(fi,x,n,true) -> t
  (* Lambda and closure conversions to PE closure *)
  | TmLam(fi,x,t1) -> TmClos(fi,x,t1,env,true)
  (* Closures, both PE and non PE *)
  | TmClos(fi,x,t2,env2,pemode) -> t
  (* Application: closures and delta  *)
  | TmApp(fi,t1,t2) ->
    (match normalize env n t1 with
    (* Closure application (PE on non PE) TODO: use affine lamba check *)
    | TmClos(fi,x,t3,env2,_) ->
         normalize ((normalize env n t2)::env2) n t3
    (* Constant application using the delta function *)
    | TmConst(fi1,c1) ->
        (match normalize env n t2 with
        | TmConst(fi2,c2) as tt->  delta c1 tt
        | nf -> TmApp(fi,TmConst(fi1,c1),nf))
    (* Partial evaluation *)
    | TmPEval(fi) ->
      (match normalize env n t2 with
      | TmClos(fi2,x,t2,env2,pemode) ->
          let pesym = TmVar(NoInfo,us"",n+1,true) in
          let t2' = (TmApp(fi,TmPEval(fi),t2)) in
          TmClos(fi2,x,normalize (pesym::env2) (n+1) t2',env2,true)
      | v2 -> v2)
    (* If-expression *)
    | TmIfexp(fi2,x1,x2) ->
      (match x1,x2,normalize env n t2 with
      | None,None,TmConst(fi3,CBool(b)) -> TmIfexp(fi2,Some(b),None)
      | Some(b),Some(TmClos(_,_,t3,env3,_)),TmClos(_,_,t4,env4,_) ->
        if b then normalize (TmNop::env3) n t3 else normalize (TmNop::env4) n t4
      | Some(b),_,(TmClos(_,_,t3,_,_) as v3) -> TmIfexp(fi2,Some(b),Some(v3))
      | _,_,v2 -> TmApp(fi,TmIfexp(fi2,x1,x2),v2))
    (* Fix *)
    | TmFix(fi2) ->
       (match normalize env n t2 with
       | TmClos(fi,x,t3,env2,_) as tt ->
           normalize ((TmApp(fi,TmFix(fi2),tt))::env2) n t3
       | v2 -> TmApp(fi,TmFix(fi2),v2))
    (* Stay in normalized form *)
    | v1 -> TmApp(fi,v1,normalize env n t2))
  (* Constant, fix, and Peval  *)
  | TmConst(_,_) | TmFix(_) | TmPEval(_) -> t
  | TmLater(_) | TmNow(_) -> t
  (* If expression *)
  | TmIfexp(_,_,_) -> t  (* TODO!!!!!! *)
  (* Other old, to remove *)
  | TmChar(_,_) -> t
  | TmExprSeq(fi,t1,t2) ->
      TmExprSeq(fi,normalize env n t1, normalize env n t2)
  | TmUC(fi,uct,o,u) -> t
  | TmUtest(fi,t1,t2,tnext) ->
      TmUtest(fi,normalize env n t1,normalize env n t2,tnext)
  | TmMatch(fi,t1,cases) ->
      TmMatch(fi,normalize env n t1,cases)
  | TmNop -> t




(* Define the file slash, to make it platform independent *)
let sl = if Sys.win32 then "\\" else "/"

(* Add a slash at the end "\\" or "/" if not already available *)
let add_slash s =
  if String.length s = 0 || (String.sub s (String.length s - 1) 1) <> sl
  then s ^ sl else s

(* Expand a list of files and folders into a list of file names *)
let files_of_folders lst = List.fold_left (fun a v ->
  if Sys.is_directory v then
    (Sys.readdir v
        |> Array.to_list
        |> List.filter (fun x -> not (String.length x >= 1 && String.get x 0 = '.'))
        |> List.map (fun x -> (add_slash v) ^ x)
        |> List.filter (fun x -> not (Sys.is_directory x))
    ) @ a
  else v::a
) [] lst


    
  
(*   (\* count_threads := !count_threads + 1 *\) *)

(* let dec_count_threads () = *)
(*   Atomic.set count_threads ((Atomic.get count_threads) - 1) *)
(*   (\* count_threads := !count_threads - 1 *\) *)


  (* !count_threads *)

(* Main evaluation loop of a term. Evaluates using big-step semantics *)
let rec eval env t =
  debug_eval env t;
  match t with
  (* Variables using debruijn indices. Need to evaluate because fix point. *)
  | TmVar(fi,x,n,_) -> eval env  (List.nth env n)
  (* Lambda and closure conversions *)
  | TmLam(fi,x,t1) -> TmClos(fi,x,t1,env,false)
  | TmClos(fi,x,t1,env2,_) -> t
  (* Application *)
  | TmConst(_,CDelayed(f,d,id)) ->
     ((* try *)
       (* printf "Threads cdelayd %d %d\n%!" id (get_count_threads () ); *)
       get_dt d
     )
         
  | TmApp(fi,t1,t2) ->
     (match eval env t1 with
      (* Closure application *)
      | TmClos(fi,x,TmConst(fii, CDelayed (f, d, id)),env2,_) ->
         (* let tn = eval env t2 in *)
         (* eval (tn::env2) t3 *)
         let t1' = get_dt d in
         eval env (TmApp(fi,t1',t2))
     | TmClos(fi,x,t3,env2,_) ->
         let tn = eval env t2 in
         eval (tn::env2) t3
      (* Constant application using the delta function *)
      | TmConst(_,Clater(Some f)) ->
         (
           match insert_dt (fun t -> eval env t) t2  with
             None -> eval env t2
           | Some (d, id) ->
              TmClos(fi,us"_", TmConst (fi, CDelayed (f, d, id)), env, false) 
         )
       (* (match eval env t2 with
           * | TmClos(fi, s, t2, env,_) ->
           *    let l = insert_dt (fun t2 -> eval (TmNop::env) t2) t2  in
           *    TmConst(fi, CDelayed (f, l, env))
           * | v2 -> delta (Clater (Some f)) v2) *)
      | TmConst(fi,c) ->
         let t2' = 
           (match (eval env t2) with
           | TmClos(fi,x,TmConst(fii, CDelayed (f, d, id)),env2,_) ->
              (* let tn = eval env t2 in *)
              (* eval (tn::env2) t3 *)
              get_dt d
           | t2' -> t2'
           )
         in
           delta c t2'
      (* Partial evaluation *)
      | TmPEval(fi2) -> normalize env 0 (TmApp(fi,TmPEval(fi2),t2))
                        |> readback env 0 |> debug_after_peval |> eval env
       (* Fix *)
      | TmFix(fi) ->
         (match eval env t2 with
          | TmClos(fi,x,t3,env2,_) as tt -> eval ((TmApp(fi,TmFix(fi),tt))::env2) t3
          | _ -> failwith "Incorrect CFix")
      (* If-expression *)
      | TmIfexp(fi,x1,x2) ->
         (match x1,x2,eval env t2 with
          | None,None,TmConst(fi,CBool(b)) -> TmIfexp(fi,Some(b),None)
          | Some(b),Some(TmClos(_,_,t3,env3,_)),TmClos(_,_,t4,env4,_) ->
             if b then eval (TmNop::env3) t3 else eval (TmNop::env4) t4
          | Some(b),_,(TmClos(_,_,t3,_,_) as v3) -> TmIfexp(fi,Some(b),Some(v3))
          | _ -> raise_error fi "Incorrect if-expression in the eval function.")
      | _ ->
         (* let s1 = pprint true ttt in *)
         (* printf "T %s\n%!" (Ustring.to_utf8 s1); *)
         raise_error fi "Application to a non closure value.")
  | TmConst(_,_) | TmFix(_) | TmPEval(_) -> t
  | TmLater(_) | TmNow(_) ->  t
  (* If expression *)
  | TmIfexp(fi,_,_) -> t
  (* The rest *)
  | TmChar(_,_) -> t
  | TmExprSeq(_,t1,t2) -> let _ = eval env t1 in eval env t2
  | TmUC(fi,uct,o,u) -> TmUC(fi,ucmap (eval env) uct,o,u)
  | TmUtest(fi,t1,t2,tnext) ->
    if !utest then begin
      let (v1,v2) = ((eval env t1),(eval env t2)) in
        if val_equal v1 v2 then
         (printf "."; utest_ok := !utest_ok + 1)
       else (
        unittest_failed fi v1 v2;
        utest_fail := !utest_fail + 1;
        utest_fail_local := !utest_fail_local + 1)
     end;
    eval env tnext
  | TmMatch(fi,t1,cases) -> (
     let v1 = make_tm_for_match (eval env t1) in
     let rec appcases cases =
       match cases with
       | Case(_,p,t)::cs ->
          (match eval_match env p v1 true with
         | Some(env,_) -> eval env t
         | None -> appcases cs)
       | [] -> raise_error fi  "Match error"
     in
      appcases cases)
  | TmNop -> t




type tree = Node of (tree * int) * (tree * int) | Lam of tree * int | Leaf

(* Main evaluation loop of a term. Evaluates using big-step semantics *)
let rec preeval t =
  match t with
  | TmApp(fi,t1,t2) ->

     let (trl, nl) = preeval t1 in
     let (trr, nr) = preeval t2 in
     (Node((trl,nl),(trr,nr)), (nl + nr + 1))
  | TmClos(fi,x,t1,_,_)
    | TmLam(fi,x,t1) ->
     let (tr, n) = preeval t1 in
     (Lam (tr,n), n)
  | TmVar(fi,x,n,_) -> (Leaf, 1)
  (* Lambda and closure conversions *)
  | _ ->
     (Leaf, 1)

let rec inbuildin envlist x =
  match envlist with
    l::ls when l = (Ustring.to_utf8 x) -> true
  | l::ls -> inbuildin ls x
  | [] -> false
  

let rec insertparr t n na l envlist =
  match t with
  | TmApp(fi,TmFix(c),t2) ->
     let (nna, nn,nt,nl) = insertparr t2 n na l envlist in
     (nna, nn, TmApp(fi,TmFix(c),nt), nl)
  | TmApp(fi,TmVar(fii,x,num,sth),t2) when (inbuildin envlist x) ->
     let (nna, nn,nt,nl) = insertparr t2 n na l envlist in
     (nna, nn, TmApp(fi,TmVar(fii,x,num,sth),nt), nl)
  | TmApp(fi,TmConst(fii,c),t2) ->
     let (nna,nn,nt,nl) = insertparr t2 n na l envlist in
     (nna, nn, TmApp(fi,TmConst(fii,c),nt), nl)
  | TmApp(fi,TmIfexp(fii,b,e),t2)  ->
     let (nna,nn,nt,nl) = insertparr t2 n na l envlist in
     (nna, nn, TmApp(fi,TmIfexp(fii,b,e),nt), nl)
  | TmApp(fi,t1,TmLam(fii,x,t2)) when x = us "_" ->
     let (nal, nl,t1',l1) = insertparr t1 n na l envlist in
     let (nar, nr,t2',l2) = insertparr t2 nl nal l1 envlist in
     (nar, nr, TmApp(fi,t1', TmLam(fii,x,t2')), l2)
  | TmApp(fi,t1,t2) ->
    let (nal, nl,t1',l1) = insertparr t1 n na l envlist in
    let (nar, nr,t2',l2) = insertparr t2 nl nal l1 envlist in
    let n' = nr + 1 in
    let na' = if nr != nl then (inc_count(); nar + 1) else nar in
    (* printf "Nr Nl: %d %d\n%!" nr nl ; *)
    let l',t2'' =
      match l2 with
        li::ls when (li = na') &&  nr != nl ->
          (
           (ls, TmApp(fi,TmConst(fi, Clater(Some 0.1)), t2'))
          )
      | _ -> (l2, t2')
    in
    (na',n',TmApp(fi,t1',t2''),l')
  (* Lambda and closure conversions *)
  | TmClos(fi,x,t1,env,sth) ->
     let (nna, nn,nt,nl) = insertparr t1 n na l envlist in
     (nna, nn, TmClos(fi,x,nt,env,sth), nl)
  | TmLam(fi,x,t1) ->
     let (nna, nn,nt,nl) = insertparr t1 n na l envlist in
     (nna, nn, TmLam(fi,x,nt), nl)       
  | _ -> (na, n,t,l)


let draw tree =
  let rec print indent tree =
    match tree with
       Leaf -> 
        printf "%s%d\n" indent 1
     | Lam (tree, n) ->
        printf "%sllll\n" indent;
        print (indent) tree;
        printf "%sllll\n" indent;
     | Node ((left, nl), (right, nr)) ->
        printf "%s----\n" indent;
        print (indent ^ "| ") left;
        printf "%s(%d,%d)\n" indent nl nr;
        print (indent ^ "| ") right;
        printf "%s----\n" indent
  in
  print "" tree
        
(* let rec print_tree tree =
 *   match tr with
 *   | Node ((tl,nl),(tr,nr)) ->
 *      printf "%d--------------%d\n" nl nr
 *        print_tree tl;
 *      print_tree tr;
 *   | Leaf ->
 *      printf "" *)
     
let evalprog filename list  =
  if !utest then printf "%s: " filename;
  utest_fail_local := 0;
  let fs1 = open_in filename in
  let tablength = 8 in
  begin try
      let t =
        Lexer.init (us filename) tablength;
        fs1 |> Ustring.lexing_from_channel
        |> Parser.main Lexer.main
        |> debruijn (builtin |> List.split |> fst |> List.map us)
      in
      let env =
        builtin |> List.split |> snd |> List.map (fun x -> TmConst(NoInfo,x))
      in
      let envlist =
        builtin |> List.split |> fst
      in

      t |> preeval |> (fun x -> ()); (* |> fst |> draw; *)

      let s1 = pprint true t in
      printf "%s\n%!" (Ustring.to_utf8 s1);

      set_count_zero ();
      set_count_threads 0;
      
      let (_,_,t,_) = insertparr t 0 0 (List.sort compare list) envlist in

      let s2 = pprint true t in
      printf "%s\n%!" (Ustring.to_utf8 s2);
      
      let t1 = get_time() in
      t |> eval env |> fun _ -> ();
      let t2 = get_time() in
      printf "\nNo Applications %d\n No Domains %d\nElapsed time %f\n%!" (!count) (Atomic.get count_threads) (t2 -. t1)      
    with
    | Lexer.Lex_error m ->
      if !utest then (
        printf "\n ** %s" (Ustring.to_utf8 (Msg.message2str m));
        utest_fail := !utest_fail + 1;
        utest_fail_local := !utest_fail_local + 1)
      else
        fprintf stderr "%s\n" (Ustring.to_utf8 (Msg.message2str m))
    | Error m ->
      if !utest then (
        printf "\n ** %s" (Ustring.to_utf8 (Msg.message2str m));
        utest_fail := !utest_fail + 1;
        utest_fail_local := !utest_fail_local + 1)
      else
        fprintf stderr "%s\n" (Ustring.to_utf8 (Msg.message2str m))
    | Parsing.Parse_error ->
      if !utest then (
        printf "\n ** %s" (Ustring.to_utf8 (Msg.message2str (Lexer.parse_error_message())));
        utest_fail := !utest_fail + 1;
        utest_fail_local := !utest_fail_local + 1)
      else
        fprintf stderr "%s\n"
	(Ustring.to_utf8 (Msg.message2str (Lexer.parse_error_message())))
  end; close_in fs1;
  if !utest && !utest_fail_local = 0 then printf " OK\n" else printf "\n"



(* Define the file slash, to make it platform independent *)
let sl = if Sys.win32 then "\\" else "/"

(* Add a slash at the end "\\" or "/" if not already available *)
let add_slash s =
  if String.length s = 0 || (String.sub s (String.length s - 1) 1) <> sl
  then s ^ sl else s

(* Expand a list of files and folders into a list of file names *)
let files_of_folders lst = List.fold_left (fun a v ->
  if Sys.is_directory v then
    (Sys.readdir v
        |> Array.to_list
        |> List.filter (fun x -> not (String.length x >= 1 && String.get x 0 = '.'))
        |> List.map (fun x -> (add_slash v) ^ x)
        |> List.filter (fun x -> not (Sys.is_directory x))
    ) @ a
  else v::a
) [] lst




(* Print out main menu *)
let menu() =
  printf "Usage: boot [run|test] <files>\n";
  printf "\n"


(* Main function. Checks arguments and reads file names *)
let main =
  (* Check command  *)
  (match Array.to_list Sys.argv |> List.tl with

  (* Run tests on one or more files *)
  | "test"::lst | "t"::lst -> (
    utest := true;
    (* Select the lexer and parser, depending on the DSL*)
    let eprog name =
      if Ustring.ends_with (us".ppl") (us name) then
        (eval_atom := Ppl.eval_atom;
         (Ppl.evalprog debruijn eval builtin) name)
      else evalprog name []
    in
    (* Evaluate each of the programs in turn *)
    List.iter eprog (files_of_folders lst);

    (* Print out unit test results, if applicable *)
    if !utest_fail = 0 then
      printf "\nUnit testing SUCCESSFUL after executing %d tests.\n"
        (!utest_ok)
            else
      printf "\nERROR! %d successful tests and %d failed tests.\n"
        (!utest_ok) (!utest_fail))

  | "parallel"::list::max_threads::lst | "p"::list::max_threads::lst -> (
    utest := true;
    printf "%s\n%!" list;
    set_max_threads (int_of_string max_threads);
    let plist = 
      list |> Str.split (Str.regexp ";\\|\\[\\|\\]") |> List.map int_of_string
    in
    (* Select the lexer and parser, depending on the DSL*)
    let eprog name =
      evalprog name plist 
    in
    (* Evaluate each of the programs in turn *)
    List.iter eprog (files_of_folders lst);

    (* Print out unit test results, if applicable *)
    if !utest_fail = 0 then
      printf "\nUnit testing SUCCESSFUL after executing %d tests.\n"
        (!utest_ok)
            else
      printf "\nERROR! %d successful tests and %d failed tests.\n"
        (!utest_ok) (!utest_fail))

  (* Run one program with program arguments *)
  | "run"::name::lst | name::lst -> (
    prog_argv := lst;
      if Ustring.ends_with (us".ppl") (us name) then
        (eval_atom := Ppl.eval_atom;
         (Ppl.evalprog debruijn eval builtin) name)
      (* else if Ustring.ends_with (us".par") (us name) then
       *   (Par.evalprog name) *)
      else evalprog name [])

  (* Show the menu *)
  | _ -> menu())
