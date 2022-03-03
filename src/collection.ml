open Yocaml

let get_article (module V : Metadata.VALIDABLE) article_file =
  let arr =
    Build.read_file_with_metadata
      (module V)
      (module Model.Article)
      article_file
  in
  let deps = Build.get_dependencies arr in
  let task = Build.get_task arr in
  let+ meta, _ = task () in
  deps, (meta, Model.article_path article_file)
;;

let get_articles (module V : Metadata.VALIDABLE) path =
  let* files = read_child_files path File.is_markdown in
  let+ articles = Traverse.traverse (get_article (module V)) files in
  let deps, effects = List.split articles in
  Deps.Monoid.reduce deps, effects
;;

module Articles = struct
  type t = (Model.Article.t * Filepath.t) list

  let get_all (module V : Metadata.VALIDABLE) ?(decreasing = true) path =
    let+ deps, articles = get_articles (module V) path in
    let sorted_article = Model.Articles.sort ~decreasing articles in
    Build.make deps (fun x -> return (x, sorted_article))
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
          (Model.Article.tags article))
      M.empty
      metas
    |> M.map
         (List.sort (fun (a, _) (b, _) -> Model.Article.compare_by_date a b))
    |> M.to_seq
    |> List.of_seq
    |> List.sort by_quantity
  ;;

  let compute (module V : Metadata.VALIDABLE) path =
    let+ deps, articles = get_articles (module V) path in
    deps, group articles
  ;;
end
