open Basic
open Term

(** Rewrite rules *)

(** {2 Patterns} *)

(** Basic representation of pattern *)
type pattern =
  | Var      of loc * ident * int * pattern list (** Applied DB variable *)
  | Pattern  of loc * name * pattern list        (** Applied constant    *)
  | Lambda   of loc * ident * pattern            (** Lambda abstraction  *)
  | Brackets of term                             (** Bracket of a term   *)

val get_loc_pat : pattern -> loc

val pattern_to_term : pattern -> term

(** Efficient representation for well-formed linear Miller pattern *)
type wf_pattern =
  | LJoker
  | LVar      of ident * int * int list         (** Applied Miller variable *)
  | LLambda   of ident * wf_pattern             (** Lambda abstraction      *)
  | LPattern  of name * wf_pattern array        (** Applied constant        *)
  | LBoundVar of ident * int * wf_pattern array (** Locally bound variable  *)

(** {2 Linearization} *)

val allow_non_linear : bool ref

(** Constraints *)
type constr =
  | Linearity of int * int  (** DB indices [i] and [j] of the pattern should be convertible *)
  | Bracket   of int * term (** DB indices [i] should be convertible to the term [te] *)
  | Condition of term * term

(** {2 Rewrite Rules} *)

type rule_name =
  | Delta of name
  (** Rules associated to the definition of a constant *)
  | Gamma of bool * name
  (** Rules of lambda pi modulo. The first parameter indicates whether
      the name of the rule has been given by the user. *)

type condition = {left:term; right:term}

type 'a rule =
  {
    name : rule_name;
    ctx  : 'a;
    pat  : pattern;
    cond : condition option;
    rhs  : term
  }

type untyped_rule = untyped_context rule

type typed_rule = typed_context rule

(** {2 Errors} *)

type rule_error =
  | BoundVariableExpected          of pattern
  | DistinctBoundVariablesExpected of loc * ident
  | VariableBoundOutsideTheGuard   of term
  | UnboundVariable                of loc * ident * pattern
  | AVariableIsNotAPattern         of loc * ident
  | NonLinearRule                  of untyped_rule
  | NotEnoughArguments             of loc * ident * int * int * int
  | NonLinearNonEqArguments        of loc * ident

(** {2 Rule infos} *)

type rule_infos = {
  l           : loc;              (** location of the rule *)
  name        : rule_name;        (** name of the rule *)
  cst         : name;             (** name of the pattern constant *)
  args        : pattern list;     (** arguments list of the pattern constant *)
  cond        : condition option; (** optional condition to satisfy *)
  rhs         : term;             (** right hand side of the rule *)
  esize       : int;              (** size of the context *)
  pats        : wf_pattern array; (** free pattern without constraint *)
  constraints : constr list;
  (** constraints generated from the pattern to the free pattern *)
}

val pattern_of_rule_infos : rule_infos -> pattern

val to_rule_infos : untyped_rule -> (rule_infos, rule_error) error

(** {2 Printing} *)

val pp_rule_name       : rule_name       printer
val pp_untyped_rule    : untyped_rule    printer
val pp_typed_rule      : typed_rule      printer
val pp_pattern         : pattern         printer
val pp_wf_pattern      : wf_pattern      printer
val pp_untyped_context : untyped_context printer
val pp_typed_context   : typed_context   printer
val pp_rule_infos      : rule_infos      printer
