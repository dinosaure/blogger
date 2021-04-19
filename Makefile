.PHONY: blogger clean clean-site server reload server-full

blogger:
	dune build

clean:
	dune clean

clean-site:
	rm -rf _site/

server:
	python3 -m http.server --directory _site/

reload: clean clean-site
	dune build
	./src/blogger.exe

server-full: reload
	python3 -m http.server --directory _site/
