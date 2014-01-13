
open Types

val incr_NbConvTest : unit -> unit
val incr_NbTrivialTest : unit -> unit
val print_stats : unit -> unit

(* *** Global Options *** *)

val name        : ident ref
val out         : out_channel ref
val quiet       : bool ref
val export      : bool ref
val raphael     : bool ref
val color       : bool ref
val tpdb        : bool ref
val tpdb_file   : out_channel ref

val set_name     : ident -> unit
val set_filename : string -> unit
val set_out      : string -> unit
val set_tpdb     : string -> unit

(* *** Info messages *** *)

val sprint      : string -> unit        (* Print a string on standard output *)
val eprint      : string -> unit        (* Print a string on standard error *)
val vprint      : loc -> string Lazy.t -> unit  (* Print a string on standard error if in verbose mode *)
val error       : loc -> string -> unit (* Print an error message and exit *)
val warning     : loc -> string -> unit (* Print an warning message *)
val print_ok    : string -> unit        (* Print a success message *)



