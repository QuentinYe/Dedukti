open Term
open Rule

let error_convertibility te ctx exp inf =
  Print.fail (get_loc te)
    "Error while typing '%a' in context:\n%a.\nExpected: %a\nInferred: %a."
      Pp.pp_term te Pp.pp_context ctx Pp.pp_term exp Pp.pp_term inf

let error_product te ctx inf =
  Print.fail (get_loc te)
    "Error while typing '%a' in context:\n%a.\nExpected: a product type.\nInferred: %a."
      Pp.pp_term te Pp.pp_context ctx Pp.pp_term inf

let error_product_pat pat ctx inf =
  Print.fail (get_loc_pat pat)
    "Error while typing '%a' in context:\n%a.\nExpected: a product type.\nInferred: %a."
      Pp.pp_pattern pat Pp.pp_context ctx Pp.pp_term inf

let error_not_a_sort te ctx inf =
  Print.fail (get_loc te)
    "Error while typing '%a' in context:\n%a.\nExpected: Type or Kind.\nInferred: %a."
      Pp.pp_term te Pp.pp_context ctx Pp.pp_term inf

let error_kind te ctx =
  Print.fail (get_loc te)
    "Error while typing '%a' in context:\n%a.\nExpected: anything but Kind.\nInferred: Kind."
      Pp.pp_term te Pp.pp_context ctx

let error_not_type te ctx inf =
  Print.fail (get_loc te)
    "Error while typing '%a' in context:\n%a.\nExpected: Type.\nInferred: %a."
      Pp.pp_term te Pp.pp_context ctx Pp.pp_term inf

(******************************************************************************)

let db_get_type l ctx n =
  try Subst.shift (n+1) (snd (List.nth ctx n))
  with Failure _ -> Print.fail l "Trying to type a open term."

let rec infer_rec (ctx:context) (te:term)  : term =
  match te with
    | Kind -> Print.fail dloc "Kind is not typable."
    | Type _ -> mk_Kind
    | DB (l,_,n) -> db_get_type l ctx n
    | Const (l,md,id) -> Env.get_type l md id
    | App (f,a,args) ->
        snd (List.fold_left (infer_rec_aux ctx) (f,infer_rec ctx f) (a::args))
    | Pi (_,x,a,b) ->
        let _ = is_type ctx a in
        let ctx2 = (x,a)::ctx in
          ( match infer_rec ctx2 b with
              | (Type _|Kind as tb) -> tb
              | ty_b -> error_not_a_sort b ctx2 ty_b )
    | Lam  (_,x,a,b) ->
        let _ = is_type ctx a in
        let ctx2 = (x,a)::ctx in
          ( match infer_rec ctx2 b with
              | Kind -> error_kind b ctx2
              | ty   -> mk_Pi dloc x a ty )

and infer_rec_aux ctx (f,ty_f) u =
  match Reduction.whnf ty_f , infer_rec ctx u with
    | ( Pi (_,_,a1,b) , a2 ) ->
        if Reduction.are_convertible a1 a2 then
          ( mk_App f u [] , Subst.subst b u )
        else error_convertibility u ctx a1 a2
    | ( _ , _ ) -> error_product f ctx ty_f

and is_type ctx a =
  match infer_rec ctx a with
    | Type _ -> ()
    | ty_a -> error_not_type a ctx ty_a

(******************************************************************************)
(*
let cpt = ref 0
let fresh () = incr cpt; !cpt
let mk_Joker l =
  let id = hstring ( "?" ^ string_of_int (fresh ())) in
    mk_Const l !Env.name id
 *)
let infer_pat (ctx:context) (pat:pattern) : term (*the type*) =

  let rec synth (ctx:context) : pattern -> term*term = function
    | MatchingVar (l,x,n,args) ->
        let args2 = List.map (fun (l,id,n) -> BoundVar (l,id,n,[])) args in
          List.fold_left (check_app ctx) (mk_DB l x n,db_get_type l ctx n) args2
    | BoundVar (l,x,n,args) ->
        List.fold_left (check_app ctx) (mk_DB l x n,db_get_type l ctx n) args
    | Pattern (l,md,id,args) ->
        List.fold_left (check_app ctx) (mk_Const l md id,Env.get_type l md id) args
    | Brackets t -> ( t , infer_rec ctx t )
    | Lambda (_,_,_) -> assert false
    | Joker _ -> assert false

  and check (ctx:context) (ty:term) : pattern -> term = function
      | Joker l -> (*mk_Joker l TODO*) failwith "Not implemented."
      | Lambda (l,x,pat2) as f ->
          ( match Reduction.whnf ty with
              | Pi (_,x,a1,b) ->
                  let u = check ((x,a1)::ctx) b pat2 in
                    mk_Lam l x a1 u
              | _ -> error_product_pat f ctx ty )
      | pat ->
          let (u,ty2) = synth ctx pat in
            if Reduction.are_convertible ty ty2 then u
            else error_convertibility u ctx ty ty2

  and check_app (ctx:context) (f,ty_f:term*term) (pat:pattern) : term*term =
    match Reduction.whnf ty_f, pat with
      | Pi (_,_,a,b), _ ->
          let u = check ctx a pat in
            ( mk_App f u [] , Subst.subst b u )
      | _, _ -> error_product f ctx ty_f

  in snd (synth ctx pat)

(******************************************************************************)

let infer pte =
  let te = Scoping.scope_term [] pte in
    ( te , infer_rec [] te )

let check pte pty =
  let te = Scoping.scope_term [] pte in
  let ty = Scoping.scope_term [] pty in
  let _  =  infer_rec [] ty in
  let ty2 = infer_rec [] te in
    if (Reduction.are_convertible ty ty2) then (te,ty)
    else error_convertibility te [] ty ty2

let is_a_type2 ctx pty =
  let ty = Scoping.scope_term ctx pty in
    match infer_rec ctx ty with
      | Type _ | Kind -> ty
      | s -> error_not_a_sort ty ctx s

let is_a_type = is_a_type2 []

let check_context =
  List.fold_left ( fun ctx (_,x,ty) -> (x,is_a_type2 ctx ty)::ctx ) []

let get_nb_args (esize:int) (p:pattern) : int array =
  let arr = Array.make esize (-1) in (* -1 means +inf *)
  let min a b =
    if a = -1 then b
    else if a<b then a else b
  in
  let rec aux k = function
    | BoundVar (_,_,_,args) | Pattern (_,_,_,args) -> List.iter (aux k) args
    | Lambda (_,_,pp) -> aux (k+1) pp
    | MatchingVar (_,id,n,args) ->
        arr.(n-k) <- min (arr.(n-k)) (List.length args)
    | Brackets _ | Joker _ -> ()
  in
    ( aux 0 p ; arr )

let check_nb_args (nb_args:int array) (te:term) : unit =
  let rec aux k = function
    | Kind | Type _ | Const _ -> ()
    | DB (l,id,n) ->
        if n>=k && nb_args.(n-k)>0 then
          Print.fail l "The variable '%a' must be applied to at least %i argument(s)."
            pp_ident id nb_args.(n-k)
    | App(DB(l,id,n),a1,args) when n>=k ->
        if ( nb_args.(n-k) > 1 + (List.length args) ) then
          Print.fail l "The variable '%a' must be applied to at least %i argument(s)."
            pp_ident id nb_args.(n-k)
        else List.iter (aux k) (a1::args)
    | App (f,a1,args) -> List.iter (aux k) (f::a1::args)
    | Lam (_,_,a,b) | Pi (_,_,a,b) -> (aux k a;  aux (k+1) b)
  in
    aux 0 te

let check_rule (l,pctx,id,pargs,pri) =
  let ctx = check_context pctx in
  let pat = Scoping.scope_pattern ctx (PPattern(l,None,id,pargs)) in
  let args = match pat with
    | Pattern (_,_,_,args) -> args
    | MatchingVar (l,_,_,_) -> Print.fail l "A pattern cannot be a variable."
    | _ -> assert false in
  let ty1 = infer_pat ctx pat in
  let rhs = Scoping.scope_term ctx pri in
  let ty2 = infer_rec ctx rhs in
    if (Reduction.are_convertible ty1 ty2) then
      let esize = List.length ctx in (*TODO*)
      let nb_args = get_nb_args esize pat in
      let _ = check_nb_args nb_args rhs in
        { l=l ; ctx=ctx ; md= !Env.name; id=id ; args=args ; rhs=rhs }
    else error_convertibility rhs ctx ty1 ty2
