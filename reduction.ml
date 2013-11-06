
open Types

(* *** REDUCTION *** *)

type cbn_state = 
    int                         (*size of context *)
    * (term Lazy.t) list        (*context*)
    * term                      (*term to reduce*) 
    * cbn_state list            (*stack*)

let dump_state (k,e,t,s) =
  Global.eprint ("k = "^string_of_int k^"\n");
  Global.eprint ("t = "^ Pp.string_of_term t^"\n");
  Global.eprint "e = [";
  List.iter (fun u -> Global.eprint (" ("^ Pp.string_of_term (Lazy.force u)^")")) e ;
  Global.eprint " ]\ns = [";
  List.iter (fun (_,_,u,_) -> Global.eprint (" {{ "^ Pp.string_of_term u^" }}")) s ;
  Global.eprint " ]\n"

let rec cbn_term_of_state (k,e,t,s:cbn_state) : term =
  let t = ( if k = 0 then t else Subst.psubst_l (k,e) 0 t ) in
    if s = [] then t 
    else mk_uapp ( t::(List.map cbn_term_of_state s) )
           
let rec split_stack (i:int) : cbn_state list -> (cbn_state list*cbn_state list) option = function 
  | l  when i=0 -> Some ([],l)
  | []          -> None
  | x::l        -> 
    ( match split_stack (i-1) l with
      | None            -> None
      | Some (s1,s2)    -> Some (x::s1,s2) )

let safe_find m v cases =
  try Some ( snd ( List.find (fun ((m',v'),_) -> ident_eq v v' && ident_eq m m') cases ) )
  with Not_found -> None

let rec remove c lst =
  match lst with
    | []        -> assert false
    | x::lst'   -> 
        if c==0 then lst'
        else x::(remove (c-1) lst')

let rec add_to_list lst s s' =
  match s,s' with
    | [] , []           -> Some lst
    | x::s1 , y::s2     -> add_to_list ((x,y)::lst) s1 s2
    | _ ,_              -> None

let rec cbn_reduce (config:cbn_state) : cbn_state = 
  match config with
    (* Weak normal terms *)
    | ( _ , _ , Type _ , _ )
    | ( _ , _ , Kind , _ )
    | ( _ , _ , Meta _ , _ )
    | ( _ , _ , Pi _ , _ )
    | ( _ , _ , Lam _ , [] )                    -> config
    | ( k , _ , DB (_,_,n) , _ ) when (n>=k)    -> config
    (* Bound variable (to be substitute) *)
    | ( k , e , DB (_,_,n) , s ) (*when n<k*)   -> cbn_reduce ( 0 , [] , Lazy.force (List.nth e n) , s )
    (* Beta redex *)
    | ( k , e , Lam (_,_,_,t) , p::s )          -> cbn_reduce ( k+1 , (lazy (cbn_term_of_state p))::e , t , s )
    (* Application *)
    | ( _ , _ , App ([]|[_]) , _ )              -> assert false
    | ( k , e , App (he::tl) , s )      ->
        let tl' = List.map ( fun t -> (k,e,t,[]) ) tl in
          cbn_reduce ( k , e , he , tl' @ s ) 
    (* Global variable*)
    | ( _ , _ , GVar (_,m,_), _ ) when m==empty -> config
    | ( _ , _ , GVar (_,m,v) , s )              -> 
        begin
          match Env.get_global_symbol dloc m v with
            | Env.Def (te,_)            -> cbn_reduce ( 0 , [] , te , s )
            | Env.Decl (_,None)         -> config
            | Env.Decl (_,Some (i,g))   -> 
                ( match split_stack i s with
                    | None                -> config
                    | Some (s1,s2)        ->
                        ( match rewrite s1 g with
                            | None              -> config
                            | Some (k,e,t)      -> cbn_reduce ( k , e , t , s2 ) 
                        )
                ) 
        end

and rewrite (args:cbn_state list) (g:gdt) : (int*(term Lazy.t) list*term) option = 
  match g with
    | Switch (i,cases,def)        -> 
        begin
          (* assert (i<Array.length args); *)
          match cbn_reduce (List.nth args i) with
            | ( _ , _ , GVar (_,m,v) , s )  -> 
                ( match safe_find m v cases , def with
                    | Some g , _        -> rewrite ((remove i args)@s) g
                    | None , Some g     -> rewrite args g
                    | _ , _             -> None )
            | ( _ , _ , _ , s ) -> 
                (match def with
                   | Some g     -> rewrite args g
                   | None       -> None )
        end
    | Test (lst,te,def)   -> 
        begin
          if state_conv (List.map (fun (i,j) -> (List.nth args i,List.nth args j) ) lst) then 
            Some ( List.length args (*TODO*) , List.map (fun a -> lazy (cbn_term_of_state a)) args , te )
          else
            match def with
              | None    -> None
              | Some g  -> rewrite args g
        end
  
and state_conv : (cbn_state*cbn_state) list -> bool = function
  | []                  -> true
  | (s1,s2)::lst        ->
      begin
        let t1 = cbn_term_of_state s1 in
        let t2 = cbn_term_of_state s2 in
          if term_eq t1 t2 then 
            state_conv lst
          else
            let s1' = cbn_reduce s1 in
            let s2' = cbn_reduce s2 in
              match s1',s2' with (*states are beta-delta head normal*)
                | ( _ , _ , Kind , s ) , ( _ , _ , Kind , s' ) 
                | ( _ , _ , Type _ , s ) , ( _ , _ , Type _ , s' )                      -> 
                (* assert ( List.length s == 0 && List.length s' == 0 ) *) state_conv lst 
                | ( k , _ , DB (_,_,n) , s ) , ( k' , _ , DB (_,_,n') , s' )            -> 
                    ( (*assert (k<=n && k'<=n') ;*) (n-k)=(n'-k') && 
                      match (add_to_list lst s s') with
                        | None          -> false
                        | Some lst'     -> state_conv lst' 
                    )
                | ( _ , _ , GVar (_,m,v) , s ) , ( _ , _ , GVar (_,m',v') ,s' )         -> 
                    ( ident_eq v v' && ident_eq m m' && 
                      match (add_to_list lst s s') with
                        | None          -> false
                        | Some lst'     -> state_conv lst' 
                    ) 
                | ( k , e , Lam (_,_,a,f) , s ) , ( k' , e' , Lam (_,_,a',f') , s' )          
                | ( k , e , Pi  (_,_,a,f) , s ) , ( k' , e' , Pi  (_,_,a',f') , s' )    -> 
                    let arg = Lazy.lazy_from_val (mk_unique ()) in 
                    let x = ( (k,e,a,[]) , (k',e',a',[]) ) in
                    let y = ( (k+1,arg::e,f,[]) , (k'+1,arg::e',f',[]) ) in
                      ( match add_to_list (x::y::lst) s s' with
                          | None        -> false
                          | Some lst'   -> state_conv lst' )
                | ( _ , _ , Meta _ , _ ) , _ | _ , ( _ , _ , Meta _ , _ )               -> assert false
                | ( _ , _ , _ , _ ) , ( _ , _ , _ , _ )                                 -> false
      end


(* Weak Normal Form *)          
let wnf (t:term) : term = cbn_term_of_state ( cbn_reduce ( 0 , [] , t , [] ) ) 

let rec cbn_term_of_state2 (k,e,t,s:cbn_state) : term =
  let t = ( if k = 0 then t else Subst.psubst_l (k,e) 0 t ) in
    if s = [] then t 
    else mk_uapp ( t::(List.map (fun st -> cbn_term_of_state2 (cbn_reduce st)) s ))

(* Head Normal Form *)          
let hnf (t:term) : term = cbn_term_of_state2 (cbn_reduce (0,[],t,[])) 

(* Strong Normal Form *)
let snf te = assert false (*TODO*) 


let are_convertible t1 t2 =
  state_conv [ ( (0,[],t1,[]) , (0,[],t2,[]) ) ]

(* *** UNIFICATION *** *)

let rec decompose (sub:(int*term) list) : (cbn_state*cbn_state) list -> ((int*term) list) option = function
  | []                  -> Some sub
  | (s1,s2)::lst        ->
      begin
        let t1 = cbn_term_of_state s1 in
        let t2 = cbn_term_of_state s2 in
          if term_eq t1 t2 then 
            decompose sub lst
          else
            let s1' = cbn_reduce s1 in
            let s2' = cbn_reduce s2 in
              match s1',s2' with 
                (* Base Cases*)
                | ( _ , _ , Kind , s ) , ( _ , _ , Kind , s' )  
                | ( _ , _ , Type _ , s ) , ( _ , _ , Type _ , s' )                      -> 
                (* assert ( List.length s == 0 && List.length s' == 0 ) *) decompose sub lst
                | ( _ , _ , GVar (_,m,v) , s ) , ( _ , _ , GVar (_,m',v') , s' )        -> 
                    if ident_eq v v' && ident_eq m m' then 
                      ( match (add_to_list lst s s') with
                        | None          ->      None
                        | Some lst'     -> decompose sub lst' )
                    else None 
                | ( k , _ , DB (_,_,n) , s ) , ( k' , _ , DB (_,_,n') , s' ) (* (n<k && n'<k') *)       -> 
                    if (n-k)=(n'-k') then 
                      ( match (add_to_list lst s s') with
                          | None        -> None
                          | Some lst'   -> decompose sub lst' )
                    else None
                (*Composed Cases*)
                | ( k , e , Lam (_,_,a,f) , s ) , ( k' , e' , Lam (_,_,a',f') , s' )          
                | ( k , e , Pi  (_,_,a,f) , s ) , ( k' , e' , Pi  (_,_,a',f') , s' )    -> 
                    let arg = Lazy.lazy_from_val (mk_unique ()) in
                    let x = ( (k,e,a,[]) , (k',e',a',[]) ) in
                    let y = ( (k+1,arg::e,f,[]) , (k'+1,arg::e',f',[]) ) in
                     ( match (add_to_list (x::y::lst) s s') with
                         | None         -> None
                         | Some lst'    -> decompose sub lst'
                     )
                (* Unification *)
                | ( ( _ , _ , Meta (_,n) , [] ) , st )
                | ( st , ( _ , _ , Meta (_,n) , [] ) )                                  -> 
                    decompose  ((n,cbn_term_of_state st)::sub) lst
                (* Ignored Cases *)
                | ( _ , _ , Meta (_,n) , _ ) , _ 
                | _ , ( _ , _ , Meta (_,n) , _ )                                        -> decompose sub lst
                (*Not Unifiable*)
                | ( _ , _ , _ , _ ) , ( _ , _ , _ , _ )                                 -> None
      end

let decompose_eq t1 t2 = decompose [] [ (0,[],t1,[]),(0,[],t2,[]) ]      
