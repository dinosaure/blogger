open Yocaml

module Articles : sig
  type t = (Model.Article.t * Filepath.t) list

  val get_all
    :  (module Metadata.VALIDABLE)
    -> ?decreasing:bool
    -> Filepath.t
    -> ('a, 'a * t) Build.t Effect.t
end

module Tags : sig
  val compute
    :  (module Metadata.VALIDABLE)
    -> Filepath.t
    -> (Deps.t * (string * (Model.Article.t * string) list) list) Effect.t
end
