open Yocaml

let domain = "https://xhtmlboi.github.io"
let feed_url = into domain "feed.xml"

let articles_to_items articles =
  List.map
    (fun (article, url) ->
      Model.Article.to_rss_item (into domain url) article)
    articles
;;

let make ((), articles) =
  Yocaml.Rss.Channel.make
    ~title:"XHTMLBoy's Website"
    ~link:domain
    ~feed_link:feed_url
    ~description:
      "You are on a website dedicated to the enthusiasts of (valid) XHTML, \
       and of beautiful mechanics."
    ~generator:"YOCaml"
    ~webmaster:"xhtmlboi@gmail.com (The XHTMLBoy)"
    (articles_to_items articles)
;;
