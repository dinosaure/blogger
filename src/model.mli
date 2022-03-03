open Yocaml

val article_path : Filepath.t -> Filepath.t
val tag_path : string -> Filepath.t

module Article : sig
  type t

  val date : t -> Date.t
  val tags : t -> string list
  val to_rss_item : string -> t -> Rss.Item.t
  val compare_by_date : t -> t -> int

  include Metadata.INJECTABLE with type t := t
  include Metadata.READABLE with type t := t
end

module Tag : sig
  type t

  val make
    :  ?title:string
    -> ?description:string
    -> string
    -> (Article.t * string) list
    -> (string * int) list
    -> t

  include Metadata.INJECTABLE with type t := t
end

module Articles : sig
  type t

  val make
    :  ?title:string
    -> ?description:string
    -> (Article.t * string) list
    -> t

  val sort
    :  ?decreasing:bool
    -> (Article.t * string) list
    -> (Article.t * string) list

  val sort_articles_by_date : ?decreasing:bool -> t -> t
  val articles : t -> (Article.t * string) list
  val title : t -> string option
  val description : t -> string option
  val set_title : string option -> t -> t
  val set_description : string option -> t -> t
  val set_articles : (Article.t * string) list -> t -> t

  include Metadata.INJECTABLE with type t := t
end
