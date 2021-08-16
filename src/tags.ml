open Yocaml

type t =
  { tags : (string * (Metadata.Article.t * string) list) list
  ; title : string option
  ; description : string option
  }

let make ?title ?description tags = { tags; title; description }

let sort_by_quantity ?(decreasing = true) p =
  { p with
    tags =
      List.sort (fun (_, a) (_, b) ->
          let r = Int.compare $ List.length a $ List.length b in
          if decreasing then ~-r else r)
      $ List.map
          (fun (x, l) ->
            ( x
            , List.sort
                (fun (a, _) (b, _) ->
                  let r = Metadata.Article.compare_by_date a b in
                  if decreasing then ~-r else r)
                l ))
          p.tags
  }
;;

let inject
    (type a)
    (module D : Key_value.DESCRIBABLE with type t = a)
    { tags; title; description }
  =
  let article_object (article, url) =
    D.object_
      (("url", D.string url) :: Metadata.Article.inject (module D) article)
  in
  ( "tags"
  , D.list
      (List.map
         (fun (tag, articles) ->
           D.object_
             [ "tag", D.string tag
             ; "articles", D.list $ List.map article_object articles
             ])
         tags) )
  :: (Metadata.Page.inject (module D) $ Metadata.Page.make title description)
;;
