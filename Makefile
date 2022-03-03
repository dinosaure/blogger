.PHONY: blogger clean clean-site deps

blogger:
	dune build

clean:
	dune clean

clean-site:
	rm -rf _site/

deps:
	opam install . --deps-only --with-doc --with-test
	opam install yocaml
	opam install yocaml_unix yocaml_yaml yocaml_markdown yocaml_jingoo

fmt:
	dune build @fmt --auto-promote
