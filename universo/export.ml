open Cfg

type model = Basic.name -> Term.term

module type Solver =
sig
  type t

  val mk_var  : string -> t

  val mk_prop : t

  val mk_type : int -> t

  val mk_succ : t -> t

  val mk_max  : t -> t -> t

  val mk_rule : t -> t -> t

  val mk_eq   : t -> t -> unit

  val solve   : unit -> int * model

  val reset   : unit -> unit
end

open Z3

type cfg_item = [`Model of bool | `Proof of bool | `Trace of bool | `TraceFile of string]

type cfg = cfg_item list

let cfg = [`Model(true);
           `Proof(true);
           `Trace(false)]

let string_of_cfg_item item =
  match item with
  | `Model(b) -> ("model", string_of_bool b)
  | `Proof(b) -> ("proof", string_of_bool b)
  | `Trace(b) -> ("trace", string_of_bool b)
  | `TraceFile(file) -> ("trace_file_name", file)

let string_of_cfg cfg = List.map string_of_cfg_item cfg

let ctx = mk_context (string_of_cfg cfg)

module Z3Syn =
struct

  type t = Expr.expr

  let solver = Solver.mk_simple_solver ctx

  let sort      = Sort.mk_uninterpreted_s ctx "Univ"

  (* Type 0 is impredictive *)
  let mk_univ i = Expr.mk_const_s ctx ("type"^(string_of_int i)) sort

  let mk_succ   = FuncDecl.mk_func_decl_s ctx "S" [sort] sort

  let mk_max    = FuncDecl.mk_func_decl_s ctx "M" [sort;sort] sort

  let mk_rule   = FuncDecl.mk_func_decl_s ctx "R" [sort;sort] sort

  let mk_eq l r = Boolean.mk_eq ctx l r

  let mk_succ l  =
    Expr.mk_app ctx mk_succ [l]

  let mk_max l1 l2 =
    Expr.mk_app ctx mk_max [l1;l2]

  let mk_rule l1 l2 =
   Expr.mk_app ctx mk_rule [l1;l2]

  let mk_axiom_succ i =
    mk_eq (mk_succ (mk_univ i)) (mk_univ (i+1))

  let mk_axiom_max i j =
    mk_eq (mk_max (mk_univ i) (mk_univ j)) (mk_univ (max i j))

  let mk_axiom_rule i j =
    if j = 0 then
      mk_eq (mk_rule (mk_univ i) (mk_univ 0)) (mk_univ 0)
    else
      mk_eq (mk_rule (mk_univ i) (mk_univ j)) (mk_univ (max i j))

  let mk_var s =
    Expr.mk_const_s ctx s sort

  let mk_type i = mk_univ (i + 1)

  let mk_prop = mk_univ 0

  let add expr = Solver.add solver [expr]

  let mk_eq l r = add (mk_eq l r)

  let register_axioms i =
    for i = 0 to i
    do
      add (mk_axiom_succ i);
      for j = 0 to i
      do
        add (mk_axiom_max i j);
        add (mk_axiom_rule i j);
      done;
    done

  let reset () = Solver.reset solver

  let rec check constraints i =
    reset ();
    register_axioms i;
    if i > Cfg.univ_max () then failwith "Probably the Constraints are inconsistent";
    match Solver.check solver [] with
    | Solver.UNSATISFIABLE ->
      Basic.debug 1 "No solution found with %d universes@." (i + 2);
      check constraints (i+1)
    | Solver.UNKNOWN -> failwith "This bug should be reported (check)"
    | Solver.SATISFIABLE -> failwith "yes"

  let solve constraints = check constraints 0
end

(*
module Z3LRA =
struct

  let solver = Solver.mk_simple_solver ctx

  let variables = Hashtbl.create 100

  let add_obj_var left right =
    let le = Arithmetic.mk_le ctx left right in
    Boolean.mk_ite ctx le right left

  let add_obj_sup i =
    let i = Arithmetic.Integer.mk_numeral_i ctx i in
    Hashtbl.iter (fun _ v ->
        let le = Arithmetic.mk_le ctx v i in Solver.add solver [le]) variables

  let register_variable var =
    let zvar = Arithmetic.Integer.mk_const_s ctx var in
    Hashtbl.add variables var zvar;
    let zero = Arithmetic.Integer.mk_numeral_i ctx 0 in
    let le = Arithmetic.mk_le ctx zero zvar in
    Solver.add solver [le];
    zvar

  let get_variable var =
    if Hashtbl.mem variables var then
      Hashtbl.find variables var
    else
      register_variable var

  let gen_constraint_univ var univ =
    let zvar = get_variable var in
    let level =
      match univ with
      | Prop ->
        Arithmetic.Integer.mk_numeral_i ctx 0
      | Type i ->
        Arithmetic.Integer.mk_numeral_i ctx (i+1)
    in
    let eq = Boolean.mk_eq ctx zvar level in
    Solver.add solver [eq]

  let gen_constraint_eq var var' =
    let zvar = get_variable var in
    let zvar' = get_variable var' in
    let eq = Boolean.mk_eq ctx zvar zvar' in
    Solver.add solver [eq]

  let gen_constraint_succ var var' =
    let zvar = get_variable var in
    let zvar' = get_variable var' in
    let one = Arithmetic.Integer.mk_numeral_i ctx 1 in
    let plus = Arithmetic.mk_add ctx [zvar;one] in
    let eq = Boolean.mk_eq ctx plus zvar' in
    Solver.add solver [eq]


  let z3_max x y =
    let le = Arithmetic.mk_le ctx x y in
    Boolean.mk_ite ctx le y x

  let gen_constraint_max var var' var'' =
    let zvar = get_variable var in
    let zvar' = get_variable var' in
    let zvar'' = get_variable var'' in
    let max = z3_max zvar zvar' in
    let eq = Boolean.mk_eq ctx max zvar'' in
    Solver.add solver [eq]

  let gen_constraint_rule var var' var'' =
    let x = get_variable var in
    let y = get_variable var' in
    let z = get_variable var'' in
    let zero = Arithmetic.Integer.mk_numeral_i ctx 0 in
    let zeq0 = Boolean.mk_eq ctx z zero in
    let maxxy = z3_max x y in
    let zeqmax = Boolean.mk_eq ctx z maxxy in
    let yeq0 = Boolean.mk_eq ctx y zero in
    let ite = Boolean.mk_ite ctx yeq0 zeq0 zeqmax in
    Solver.add solver [ite]

  let gen_constraint c =
    let sofi = string_of_var in
    match c with
    | Univ(n,u) -> gen_constraint_univ (sofi n) u
    | Eq(n,n') -> gen_constraint_eq (sofi n) (sofi n')
    | Succ(n,n') -> gen_constraint_succ (sofi n) (sofi n')
    | Max(n,n',n'') -> gen_constraint_max (sofi n) (sofi n') (sofi n'')
    | Rule(n,n',n'') -> gen_constraint_rule (sofi n) (sofi n') (sofi n'')

  let import cs =
    ConstraintsSet.iter gen_constraint cs

  let univ_of_int n =
    if n = 0 then
      Prop
    else
      Type(n-1)

  let var_solution model var =
    if Hashtbl.mem variables var then
      let zvar = Hashtbl.find variables var in
      match Model.get_const_interp_e model zvar with
      | None -> failwith "This bug should be reported (var_solution 1)"
      | Some e ->
        try
          let s = Arithmetic.Integer.numeral_to_string e in
          int_of_string s
        with _ -> failwith "This bug should be reported (var_solution 1)"
    else
      failwith (Format.sprintf "Variable %s not found" var)


  let rec check constraints i =
    let open Symbol in
    let open Expr in
    let open Arithmetic in
    if i > !univ_max then failwith "Probably the Constraints are inconsistent";
    Solver.reset solver;
    Hashtbl.clear variables;
    import constraints;
    add_obj_sup i;
    match Solver.check solver [] with
    | Solver.UNSATISFIABLE ->
      Basic.debug 1 "No solution found with %d universes@." (i+2);
      check constraints (i+1)
    | Solver.UNKNOWN -> failwith "This bug should be reported (check)"
    | Solver.SATISFIABLE ->
      match Solver.get_model solver with
      | None -> assert false
      | Some model ->
        let hmodel = Hashtbl.create 10001 in
        let find uvar =
          try
            uvar
            |> var_of_ident
            |> string_of_var
            |> var_solution model
            |> univ_of_int
            |> term_of_univ
          with _ -> term_of_univ Constraints.Prop
        in
        Basic.debug 2 "%s@." (Solver.to_string solver);
        Basic.debug 2 "%s@." (Model.to_string model);
        i,
        fun (uvar:Basic.ident) : Term.term ->
          if Hashtbl.mem hmodel uvar then
            Hashtbl.find hmodel uvar
          else
            let t = find uvar in
            Hashtbl.add hmodel uvar t;
            t

  let solve constraints = check constraints 0
end
*)