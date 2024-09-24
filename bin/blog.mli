module Make_with_target (_ : sig
  val source : Yocaml.Path.t
  val target : Yocaml.Path.t
end) : sig
  val target : Yocaml.Path.t
  val process_all : host:string -> unit Yocaml.Eff.t
end

module Make (_ : sig
  val source : Yocaml.Path.t
end) : sig
  val target : Yocaml.Path.t
  val process_all : host:string -> unit Yocaml.Eff.t
end
