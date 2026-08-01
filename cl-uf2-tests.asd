(asdf:defsystem "cl-uf2-tests"
  :description "Test suite for cl-uf2."
  :version "0.0.1.0"
  :license "GPL-3.0"
  :author "cl-uf2"
  :depends-on ("cl-uf2" "fiveam")
  :serial t
  :components
  ((:module "tests"
    :serial t
    :components
    ((:file "cl-uf2-tests"))))
  :perform (test-op (o c)
             (unless (uiop:symbol-call :cl-uf2-tests :run-tests)
               (error "Some tests failed."))))
