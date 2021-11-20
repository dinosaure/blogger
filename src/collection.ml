open Yocaml

let article_path file =
  let filename = basename $ replace_extension file "html" in
  filename |> into "articles"
;;

let tag_path tag = add_extension tag "html" |> into "tags"

let get_article (module V : Metadata.VALIDABLE) article_file =
  let arr =
    Build.read_file_with_metadata
      (module V)
      (module Metadata.Article)
      article_file
  in
  let deps = Build.get_dependencies arr in
  let task = Build.get_task arr in
  let+ meta, _ = task () in
  deps, (meta, article_path article_file)
;;

let get_articles (module V : Metadata.VALIDABLE) path =
  let* files = read_child_files path File.is_markdown in
  let+ articles = Traverse.traverse (get_article (module V)) files in
  let deps, effects = List.split articles in
  Deps.Monoid.reduce deps, effects
;;

let article_object
    (type a)
    (module D : Key_value.DESCRIBABLE with type t = a)
    (article, url)
  =
  D.object_
    (("url", D.string url) :: Metadata.Article.inject (module D) article)
;;

module Articles = struct
  type t = (Metadata.Article.t * Filepath.t) list

  let sort ?(decreasing = true) articles =
    List.sort
      (fun (a, _) (b, _) ->
        let a_date = Metadata.Article.date a
        and b_date = Metadata.Article.date b in
        let r = Date.compare a_date b_date in
        if decreasing then ~-r else r)
      articles
  ;;

  let get_all (module V : Metadata.VALIDABLE) ?(decreasing = true) path =
    let+ deps, articles = get_articles (module V) path in
    let sorted_article = sort ~decreasing articles in
    Build.make deps (fun x -> return (x, sorted_article))
  ;;
end

module Tag = struct
  type t =
    { tag : string
    ; tags : (string * int) list
    ; articles : (Metadata.Article.t * string) list
    ; title : string option
    ; description : string option
    }

  let make ?title ?description tag articles tags =
    { tag; tags; articles = Articles.sort articles; title; description }
  ;;

  let inject
      (type a)
      (module D : Key_value.DESCRIBABLE with type t = a)
      { tag; tags; articles; title; description }
    =
    ("tag", D.string tag)
    :: ("articles", D.list (List.map (article_object (module D)) articles))
    :: ( "tags"
       , D.list
           (List.map
              (fun (tag, n) ->
                D.object_
                  [ "name", D.string tag
                  ; "link", D.string (tag_path tag)
                  ; "number", D.integer n
                  ])
              tags) )
    :: (Metadata.Page.inject (module D) $ Metadata.Page.make title description)
  ;;
end

module Tags = struct
  module M = Map.Make (String)

  let by_quantity ?(decreasing = true) (_, a) (_, b) =
    let r = Int.compare $ List.length a $ List.length b in
    if decreasing then ~-r else r
  ;;

  let group metas =
    List.fold_left
      (fun accumulator (article, path) ->
        List.fold_left
          (fun map tag ->
            match M.find_opt tag map with
            | Some articles -> M.add tag ((article, path) :: articles) map
            | None -> M.add tag [ article, path ] map)
          accumulator
          (Metadata.Article.tags article))
      M.empty
      metas
    |> M.map
         (List.sort (fun (a, _) (b, _) ->
              Metadata.Article.compare_by_date a b))
    |> M.to_seq
    |> List.of_seq
    |> List.sort by_quantity
  ;;

  let compute (module V : Metadata.VALIDABLE) path =
    let+ deps, articles = get_articles (module V) path in
    deps, group articles
  ;;
end
