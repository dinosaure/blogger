open Yocaml

let domain = "https://blog.osau.re"
let feed_url = into domain "feed.xml"

let articles_to_items articles =
  List.map
    (fun (article, url) ->
      Model.Article.to_rss_item (into domain url) article)
    articles
;;

let make ((), articles) =
  Yocaml.Rss.Channel.make
    ~title:"dinoblog"
    ~link:domain
    ~feed_link:feed_url
    ~description:"MirageOS and OCaml stuffs"
    ~generator:"yocaml"
    ~webmaster:"din@osau.re"
    (articles_to_items articles)
;;
