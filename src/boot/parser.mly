/*
   Miking is licensed under the MIT license.
   Copyright (C) David Broman. See file LICENSE.txt

   Modified copy of parser.mly for temporary parallel support. 
*/

%{

  open Ustring.Op
  open Msg
  open Ast

  (** Create a new info, taking left and right part *)
  let mkinfo fi1 fi2 =
    match (fi1,fi2) with
      | (Info(fn,r1,c1,_,_), Info(_,_,_,r2,c2)) -> Info(fn,r1,c1,r2,c2)
      | (Info(fn,r1,c1,r2,c2), NoInfo) -> Info(fn,r1,c1,r2,c2)
      | (NoInfo, Info(fn,r1,c1,r2,c2)) -> Info(fn,r1,c1,r2,c2)
      | (_,_) -> NoInfo

   (** Add fix-point, if recursive function *)
  let addrec x t =
    let rec hasx t = match t with
      | TmVar(_,y,_,_) ->  x =. y
      | TmLam(_,y,t1) -> if x =. y then false else hasx t1
      | TmClos(_,_,_,_,_) -> failwith "Cannot happen"
      | TmApp(_,t1,t2) -> hasx t1 || hasx t2
      | TmConst(_,_) -> false
      | TmFix(_) -> false
      | TmPEval(_) -> false
      | TmLater(_,_) -> false
      | TmNow(_) -> false	
      | TmIfexp(_,_,None) -> false
      | TmIfexp(_,_,Some(t1)) -> hasx t1
      | TmChar(_,_) -> false
      | TmExprSeq(_,t1,t2) -> hasx t1 || hasx t2
      | TmUC(fi,uct,ordered,uniqueness) ->
          let rec work uc = match uc with
          | UCNode(uc1,uc2) -> work uc1 || work uc2
          | UCLeaf(tms) -> List.exists hasx tms
          in work uct
      | TmUtest(fi,t1,t2,tnext) -> hasx t1 || hasx t2 || hasx tnext
      | TmMatch(fi,t1,cases) ->
          List.exists (fun (Case(_,_,t)) -> hasx t) cases
      | TmNop -> false
    in
    if hasx t then TmApp(NoInfo,TmFix(NoInfo), (TmLam(NoInfo,x,t))) else t


%}

/* Misc tokens */
%token EOF
%token <Ustring.ustring Ast.tokendata> IDENT
%token <Ustring.ustring Ast.tokendata> FUNIDENT
%token <Ustring.ustring Ast.tokendata> STRING
%token <Ustring.ustring Ast.tokendata> CHAR
%token <int Ast.tokendata> UINT
%token <float Ast.tokendata> UFLOAT

/* Keywords */
%token <unit Ast.tokendata> FUNC
%token <unit Ast.tokendata> FUNC2
%token <unit Ast.tokendata> DEF
%token <unit Ast.tokendata> IN
%token <unit Ast.tokendata> IF
%token <unit Ast.tokendata> IF2           /* Special handling if( */
%token <unit Ast.tokendata> THEN
%token <unit Ast.tokendata> ELSE
%token <unit Ast.tokendata> TRUE
%token <unit Ast.tokendata> FALSE
%token <unit Ast.tokendata> MATCH
%token <unit Ast.tokendata> UTEST
%token <unit Ast.tokendata> TYPE
%token <unit Ast.tokendata> DATA
%token <unit Ast.tokendata> LANG
%token <unit Ast.tokendata> MCORE
%token <unit Ast.tokendata> RAGNAR
%token <unit Ast.tokendata> LET
%token <unit Ast.tokendata> LAM
%token <unit Ast.tokendata> IN
%token <unit Ast.tokendata> NOP
%token <unit Ast.tokendata> FIX
%token <unit Ast.tokendata> PEVAL
%token <unit Ast.tokendata> IFEXP

%token <unit Ast.tokendata> NOW
%token <unit Ast.tokendata> LATER




%token <unit Ast.tokendata> EQ            /* "="  */
%token <unit Ast.tokendata> ARROW         /* "->"  */
%token <unit Ast.tokendata> ADD           /* "+"  */
%token <unit Ast.tokendata> SUB           /* "-"  */
%token <unit Ast.tokendata> MUL           /* "*"  */
%token <unit Ast.tokendata> DIV           /* "/"  */
%token <unit Ast.tokendata> MOD           /* "%"  */
%token <unit Ast.tokendata> LESS          /* "<"  */
%token <unit Ast.tokendata> LESSEQUAL     /* "<=" */
%token <unit Ast.tokendata> GREAT         /* ">"  */
%token <unit Ast.tokendata> GREATEQUAL    /* ">=" */
%token <unit Ast.tokendata> SHIFTLL       /* "<<" */
%token <unit Ast.tokendata> SHIFTRL       /* ">>" */
%token <unit Ast.tokendata> SHIFTRA       /* ">>>" */
%token <unit Ast.tokendata> EQUAL         /* "==" */
%token <unit Ast.tokendata> NOTEQUAL      /* "!=" */
%token <unit Ast.tokendata> NOT           /* "!"   */
%token <unit Ast.tokendata> OR            /* "||" */
%token <unit Ast.tokendata> AND           /* "&&" */
%token <unit Ast.tokendata> CONCAT        /* "++" */



/* Symbolic Tokens */
%token <unit Ast.tokendata> LPAREN        /* "("  */
%token <unit Ast.tokendata> RPAREN        /* ")"  */
%token <unit Ast.tokendata> LSQUARE       /* "["  */
%token <unit Ast.tokendata> RSQUARE       /* "]"  */
%token <unit Ast.tokendata> LCURLY        /* "{"  */
%token <unit Ast.tokendata> RCURLY        /* "}"  */
%token <unit Ast.tokendata> CONS          /* "::" */
%token <unit Ast.tokendata> COLON         /* ":"  */
%token <unit Ast.tokendata> COMMA         /* ","  */
%token <unit Ast.tokendata> DOT           /* "."  */
%token <unit Ast.tokendata> BAR           /* "|"  */
%token <unit Ast.tokendata> ARROW         /* "->" */
%token <unit Ast.tokendata> DARROW        /* "=>" */

%start main

%left OR  /*prec 2*/
%left AND  /*prec 3*/
%left LESS LESSEQUAL GREAT GREATEQUAL EQUAL NOTEQUAL /*prec 6*/
%left CONCAT
%left SHIFTLL SHIFTRL SHIFTRA
%nonassoc NOT /*prec8 */
%left ADD SUB /*prec 8*/
%left MUL DIV MOD /*prec 9*/




%type <Ast.tm> main

%%

main:
  | LANG RAGNAR ragnar_scope EOF
      { $3 }
  | LANG MCORE mcore_scope EOF
      { $3 }


/* ********************************* MCORE **************************************** */

mcore_scope:
  | { TmNop }
  | UTEST mc_atom mc_atom mcore_scope
      { let fi = mkinfo $1.i (tm_info $3) in
        TmUtest(fi,$2,$3,$4) }
  | LET IDENT EQ mc_term mcore_scope
      { let fi = mkinfo $1.i (tm_info $4) in
        TmApp(fi,TmLam(fi,$2.v,$5),$4) }

mc_term:
  | mc_left
      { $1 }
  | LAM IDENT COLON ty DOT mc_term
      { let fi = mkinfo $1.i (tm_info $6) in
        TmLam(fi,$2.v,$6) }
  | LET IDENT EQ mc_term IN mc_term
      { let fi = mkinfo $1.i (tm_info $4) in
        TmApp(fi,TmLam(fi,$2.v,$6),$4) }

mc_left:
  | mc_atom
      { $1 }
  | mc_left mc_atom
      { TmApp(NoInfo,$1,$2) }


mc_int:
  | UINT                 { TmConst($1.i,CInt($1.v)) }

mc_atom:
  | LPAREN mc_term RPAREN   { $2 }
  | IDENT                { TmVar($1.i,$1.v,noidx,false) }
  | CHAR                 { TmChar($1.i, List.hd (ustring2list $1.v)) }
  | STRING               { ustring2uctm $1.i $1.v }
  | UINT                 { TmConst($1.i,CInt($1.v)) }
  | UFLOAT               { TmConst($1.i,CFloat($1.v)) }
  | TRUE                 { TmConst($1.i,CBool(true)) }
  | FALSE                { TmConst($1.i,CBool(false)) }
  | NOP                  { TmNop }
  | FIX                  { TmFix($1.i) }
  | PEVAL                { TmPEval($1.i) }
  | LATER                { TmConst($1.i, Clater(None) ) }
  | NOW                  { TmConst($1.i, Cnow) }
  | IFEXP                { TmIfexp($1.i,None,None) }




/* ********************************* RAGNAR **************************************** */


ragnar_scope:
  | { TmNop }
  | term ragnar_scope  {
      match $2 with
      | TmNop -> $1
      | _ -> TmExprSeq(tm_info $1,$1,$2) }
  | DEF FUNIDENT identtyseq RPAREN oparrow body ragnar_scope
      { let fi = mkinfo $1.i (tm_info $6) in
        let rec mkfun lst = (match lst with
          | x::xs -> TmLam(fi,x,mkfun xs)
          | [] -> $6 ) in
        let f = if List.length $3 = 0 then [us"@no"] else $3 in
        TmApp(fi,TmLam(fi,$2.v,$7),addrec $2.v (mkfun f)) }
  | DEF IDENT body ragnar_scope
      { let fi = mkinfo $1.i (tm_info $3) in
        TmApp(fi,TmLam(fi,$2.v,$4),$3) }
  | TYPE IDENT ragnar_scope
      {$3}
  | TYPE FUNIDENT revtyargs RPAREN ragnar_scope
      {$5}
  | DATA IDENT DARROW ty ragnar_scope
      {$5}
  | DATA FUNIDENT revtyargs RPAREN DARROW ty ragnar_scope
      {$7}
  | UTEST term term ragnar_scope
      { let fi = mkinfo $1.i (tm_info $3) in
        TmUtest(fi,$2,$3,$4) }


oparrow:
  | {}
  | ARROW ty
    {}

body:
  | EQ term { $2 }
  | LCURLY ragnar_scope RCURLY { $2 }


term:
  | op                   { $1 }
  | IDENT ARROW term
      { let fi = mkinfo $1.i (tm_info $3) in
        TmLam(fi,$1.v,$3) }
  | FUNC IDENT term
      { let fi = mkinfo $1.i (tm_info $3) in
        TmLam(fi,$2.v,$3) }
  | FUNC LPAREN IDENT RPAREN term
      { let fi = mkinfo $1.i (tm_info $5) in
        TmLam(fi,$3.v,$5) }
  | FUNC2 IDENT RPAREN term
      { let fi = mkinfo $1.i (tm_info $4) in
        TmLam(fi,$2.v,$4) }
  | IF term THEN term ELSE term
      { let fi = mkinfo $1.i (tm_info $6) in
        TmApp(fi,TmApp(fi,TmApp(fi,TmIfexp(fi,None,None),$2),
              TmLam(tm_info $4,us"",$4)),
              TmLam(tm_info $6,us"",$6)) }
  | IF2 term RPAREN term ELSE term
      { let fi = mkinfo $1.i (tm_info $6) in
        TmApp(fi,TmApp(fi,TmApp(fi,TmIfexp(fi,None,None),$2),
              TmLam(tm_info $4,us"",$4)),
              TmLam(tm_info $6,us"",$6)) }
  | IF term term ELSE term
      { let fi = mkinfo $1.i (tm_info $5) in
        TmApp(fi,TmApp(fi,TmApp(fi,TmIfexp(fi,None,None),$2),
              TmLam(tm_info $3,us"",$3)),
              TmLam(tm_info $5,us"",$5)) }
  | MATCH term LCURLY cases RCURLY
      {TmMatch(mkinfo $1.i $5.i,$2, $4)}
  | PEVAL term
      { TmApp($1.i,TmPEval($1.i),$2) }

op:
  | atom                 { $1 }
  | op ADD op            { TmApp($2.i,TmApp($2.i,TmConst($2.i,Caddi(None)),$1),$3) }
  | op SUB op            { TmApp($2.i,TmApp($2.i,TmConst($2.i,Csubi(None)),$1),$3) }
  | op MUL op            { TmApp($2.i,TmApp($2.i,TmConst($2.i,Cmuli(None)),$1),$3) }
  | op DIV op            { TmApp($2.i,TmApp($2.i,TmConst($2.i,Cdivi(None)),$1),$3) }
  | op MOD op            { TmApp($2.i,TmApp($2.i,TmConst($2.i,Cmodi(None)),$1),$3) }
  | op LESS op           { TmApp($2.i,TmApp($2.i,TmConst($2.i,Clti(None)),$1),$3) }
  | op LESSEQUAL op      { TmApp($2.i,TmApp($2.i,TmConst($2.i,Cleqi(None)),$1),$3) }
  | op GREAT op          { TmApp($2.i,TmApp($2.i,TmConst($2.i,Cgti(None)),$1),$3)}
  | op GREATEQUAL op     { TmApp($2.i,TmApp($2.i,TmConst($2.i,Cgeqi(None)),$1),$3) }
  | op EQUAL op          { TmApp($2.i,TmApp($2.i,TmConst($2.i,CPolyEq(None)),$1),$3) }
  | op NOTEQUAL op       { TmApp($2.i,TmApp($2.i,TmConst($2.i,CPolyNeq(None)),$1),$3) }
  | op SHIFTLL op        { TmApp($2.i,TmApp($2.i,TmConst($2.i,Cslli(None)),$1),$3) }
  | op SHIFTRL op        { TmApp($2.i,TmApp($2.i,TmConst($2.i,Csrli(None)),$1),$3) }
  | op SHIFTRA op        { TmApp($2.i,TmApp($2.i,TmConst($2.i,Csrai(None)),$1),$3) }
  | NOT op               { TmApp($1.i,TmConst($1.i,Cnot),$2) }
  | op AND op            { TmApp($2.i,TmApp($2.i,TmConst($2.i,Cand(None)),$1),$3) }
  | op OR op             { TmApp($2.i,TmApp($2.i,TmConst($2.i,Cor(None)),$1),$3) }
  | op CONCAT op         { TmApp($2.i,TmApp($2.i,TmConst($2.i,CConcat(None)),$1),$3) }



atom:
  /* Function application */
  | FUNIDENT tmseq RPAREN
      { let fi = mkinfo $1.i $3.i in
        let rec mkapps lst =
          match lst with
          | t::ts ->  TmApp(fi,mkapps ts,t)
          | [] -> TmVar($1.i,$1.v,noidx,false)
        in
        (match Ustring.to_utf8 $1.v with
         | "seq"     -> TmUC($1.i,UCLeaf($2),UCOrdered,UCMultivalued)
         | _ -> mkapps (if List.length $2 = 0 then [TmNop] else (List.rev $2)))}
  | LPAREN term RPAREN   { $2 }
  | LPAREN SUB op RPAREN { TmApp($2.i,TmConst($2.i,Cnegi),$3)}
  | LSQUARE tmseq RSQUARE
       { TmUC($1.i,UCLeaf($2),UCOrdered,UCMultivalued) }
  | LCURLY ragnar_scope RCURLY  { $2 }
  | IDENT                { TmVar($1.i,$1.v,noidx,false) }
  | CHAR                 { TmChar($1.i, List.hd (ustring2list $1.v)) }
  | STRING               { ustring2uctm $1.i $1.v }
  | UINT                 { TmConst($1.i, CInt($1.v)) }
  | TRUE                 { TmConst($1.i, CBool(true)) }
  | FALSE                { TmConst($1.i, CBool(false)) }



patseq:
  |   {[]}
  | pattern commaop patseq
      {$1::$3}


pattern:
  | IDENT
      {PatIdent($1.i,$1.v)}
  | CHAR
      {PatChar($1.i,List.hd (ustring2list $1.v))}
  | STRING
      { let lst = List.map (fun x -> PatChar(NoInfo,x)) (ustring2list $1.v) in
        PatUC($1.i,lst,UCOrdered,UCMultivalued)}
  | UINT
      {PatInt($1.i,$1.v)}
  | TRUE
      {PatBool($1.i,true)}
  | FALSE
      {PatBool($1.i,false)}
  | pattern CONCAT pattern
      {PatConcat($2.i,$1,$3)}
  | LSQUARE patseq RSQUARE
      {PatUC($1.i,$2,UCOrdered,UCMultivalued)}
  | FUNIDENT patseq RPAREN
      {PatIdent($1.i,$1.v)}


commaop:
  | {}
  | COMMA {}

cases:
  |   {[]}
  | pattern DARROW term commaop cases
      { Case($2.i,$1,$3)::$5 }


tmseq:
    |   {[]}
    |   term commaop tmseq
        {$1::$3}


identtyseq:
    |   {[]}
    |   IDENT COLON ty commaop identtyseq
        {$1.v::$5}


ty:
  | tyatom
      {}
  | tyatom ARROW ty
      {}

tyatom:
  | IDENT
      {}
  | LPAREN RPAREN
      {}
  | LPAREN revtypetupleseq RPAREN
      {}
  | LSQUARE ty RSQUARE
      {}
  | FUNIDENT revtyargs RPAREN
      {}


revtypetupleseq:
  | ty
      {}
  | revtypetupleseq COMMA ty
      {}

tyarg:
  | ty
      {}
  | IDENT COLON ty
      {}

revtyargs:
  |   {}
  | tyarg
      {}
  | revtyargs COMMA tyarg
      {}
