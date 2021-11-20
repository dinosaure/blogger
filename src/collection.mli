open Yocaml

val article_path : Filepath.t -> Filepath.t
val tag_path : string -> Filepath.t

module Articles : sig
  type t = (Metadata.Article.t * Filepath.t) list

  val get_all
    :  (module Metadata.VALIDABLE)
    -> ?decreasing:bool
    -> Filepath.t
    -> ('a, 'a * t) Build.t Effect.t
end

module Tag : sig
  type t

  val make
    :  ?title:string
    -> ?description:string
    -> string
    -> (Metadata.Article.t * string) list
    -> (string * int) list
    -> t

  include Metadata.INJECTABLE with type t := t
end

module Tags : sig
  val compute
    :  (module Metadata.VALIDABLE)
    -> Filepath.t
    -> (Deps.t * (string * (Metadata.Article.t * string) list) list) Effect.t
end
