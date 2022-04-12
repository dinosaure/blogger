open Yocaml

let article_path file =
  let filename = basename $ replace_extension file "html" in
  filename |> into "articles"
;;

let tag_path tag = add_extension tag "html" |> into "tags"

module Author = struct
  type t =
    { name : string
    ; link : string
    ; email : string
    ; avatar : string option
    }

  let equal a b =
    String.equal a.name b.name
    && String.equal a.link b.link
    && String.equal a.email b.email
    && Option.equal String.equal a.avatar b.avatar
  ;;

  let make name link email avatar = { name; link; email; avatar }

  let from (type a) (module V : Metadata.VALIDABLE with type t = a) obj =
    V.object_and
      (fun assoc ->
        let open Validate.Applicative in
        make
        <$> V.(required_assoc string) "name" assoc
        <*> V.(required_assoc string) "link" assoc
        <*> V.(required_assoc string) "email" assoc
        <*> V.(optional_assoc string) "avatar" assoc)
      obj
  ;;

  let default_user =
    make
      "dinosaure"
      "https://blog.osau.re/"
      "romain.calascibetta@gmail.com"
      None
  ;;

  let gravatar email =
    let tk = String.(lowercase_ascii $ trim email) in
    let hs = Digest.(to_hex $ string tk) in
    "https://www.gravatar.com/avatar/" ^ hs
  ;;

  let inject
      (type a)
      (module D : Key_value.DESCRIBABLE with type t = a)
      { name; link; email; avatar }
    =
    let avatar =
      match avatar with
      | Some uri -> uri
      | None -> gravatar email
    in
    D.
      [ "name", string name
      ; "link", string link
      ; "email", string email
      ; "avatar", string avatar
      ]
  ;;
end

module Co_author = struct
  type t =
    { author : Author.t
    ; contribution : string
    }

  let make author contribution = { author; contribution }

  let from (type a) (module V : Metadata.VALIDABLE with type t = a) obj =
    V.object_and
      (fun assoc ->
        let open Validate.Applicative in
        make
        <$> V.(required_assoc (Author.from (module V))) "author" assoc
        <*> V.(required_assoc string) "contribution" assoc)
      obj
  ;;

  let inject
      (type a)
      (module D : Key_value.DESCRIBABLE with type t = a)
      { author; contribution }
    =
    D.
      [ "author", object_ $ Author.inject (module D) author
      ; "contribution", string contribution
      ]
  ;;
end

module Article = struct
  type t =
    { article_title : string
    ; article_description : string
    ; tags : string list
    ; date : Date.t
    ; title : string option
    ; description : string option
    ; author : Author.t
    ; co_authors : Co_author.t list
    ; invited_article : bool
    }

  let date { date; _ } = date
  let tags { tags; _ } = tags

  let to_rss_item url article =
    Rss.(
      Item.make
        ~title:article.article_title
        ~link:url
        ~pub_date:article.date
        ~description:article.article_description
        ~guid:(Guid.link url)
        ())
  ;;

  let make
      article_title
      article_description
      tags
      date
      title
      description
      author
      co_authors
    =
    let author = Option.value ~default:Author.default_user author in
    let invited_article = not (Author.equal author Author.default_user) in
    { article_title
    ; article_description
    ; tags = List.map String.lowercase_ascii tags
    ; date
    ; title
    ; description
    ; author
    ; co_authors
    ; invited_article
    }
  ;;

  let from_string (module V : Metadata.VALIDABLE) = function
    | None -> Validate.error $ Error.Required_metadata [ "Article" ]
    | Some str ->
      let open Validate.Monad in
      V.from_string str
      >>= V.object_and (fun assoc ->
              let open Validate.Applicative in
              make
              <$> V.(required_assoc string) "article.title" assoc
              <*> V.(required_assoc string) "article.description" assoc
              <*> V.(optional_assoc_or ~default:[] (list_of string))
                    "tags"
                    assoc
              <*> V.required_assoc
                    (Metadata.Date.from (module V))
                    "date"
                    assoc
              <*> V.(optional_assoc string) "title" assoc
              <*> V.(optional_assoc string) "description" assoc
              <*> V.(optional_assoc (Author.from (module V))) "author" assoc
              <*> V.(
                    optional_assoc_or
                      ~default:[]
                      (list_of (Co_author.from (module V)))
                      "coauthors"
                      assoc))
  ;;

  let inject
      (type a)
      (module D : Key_value.DESCRIBABLE with type t = a)
      { article_title
      ; article_description
      ; tags
      ; date
      ; title
      ; description
      ; author
      ; co_authors
      ; invited_article
      }
    =
    let co_authors =
      List.map (fun c -> D.object_ $ Co_author.inject (module D) c) co_authors
    in
    let has_co_authors =
      match co_authors with
      | [] -> false
      | _ -> true
    in
    D.
      [ "root", string ".."
      ; ( "metadata"
        , object_
            [ "title", string article_title
            ; "description", string article_description
            ] )
      ; "tags", list (List.map string tags)
      ; "date", object_ $ Metadata.Date.inject (module D) date
      ; "author", object_ $ Author.inject (module D) author
      ; "coauthors", list co_authors
      ; "invited", boolean invited_article
      ; "has_coauthors", boolean has_co_authors
      ]
    @ Metadata.Page.inject (module D) (Metadata.Page.make title description)
  ;;

  let compare_by_date a b = Date.compare a.date b.date
end

module Articles = struct
  type t =
    { articles : (Article.t * string) list
    ; title : string option
    ; description : string option
    }

  let make ?title ?description articles = { articles; title; description }
  let title p = p.title
  let description p = p.description
  let articles p = p.articles
  let set_articles new_articles p = { p with articles = new_articles }
  let set_title new_title p = { p with title = new_title }
  let set_description new_desc p = { p with description = new_desc }

  let sort ?(decreasing = true) articles =
    List.sort
      (fun (a, _) (b, _) ->
        let a_date = Article.date a
        and b_date = Article.date b in
        let r = Date.compare a_date b_date in
        if decreasing then ~-r else r)
      articles
  ;;

  let sort_articles_by_date ?(decreasing = true) p =
    { p with articles = sort ~decreasing p.articles }
  ;;

  let inject
      (type a)
      (module D : Key_value.DESCRIBABLE with type t = a)
      { articles; title; description }
    =
    ( "articles"
    , D.list
        (List.map
           (fun (article, url) ->
             D.object_
               (("url", D.string url) :: Article.inject (module D) article))
           articles) )
    :: ("root", D.string ".")
    :: (Metadata.Page.inject (module D) $ Metadata.Page.make title description)
  ;;
end

let article_object
    (type a)
    (module D : Key_value.DESCRIBABLE with type t = a)
    (article, url)
  =
  D.object_ (("url", D.string url) :: Article.inject (module D) article)
;;

module Tag = struct
  type t =
    { tag : string
    ; tags : (string * int) list
    ; articles : (Article.t * string) list
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
    :: ("root", D.string "..")
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
