.PHONY: blogger

blogger:
	dune build

clean:
	dune clean

clean-site:
	rm -R _site/
