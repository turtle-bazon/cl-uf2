LISP ?= sbcl

.PHONY: build test clean

build:
	$(LISP) --non-interactive --load build.lisp

test:
	$(LISP) --non-interactive \
	  --eval '(ql:quickload "cl-uf2-tests")' \
	  --eval '(unless (cl-uf2-tests:run-tests) (uiop:quit 1))'

clean:
	rm -rf build
