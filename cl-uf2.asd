(asdf:defsystem "cl-uf2"
  :description "Microsoft UF2 & BIN format convert tools."
  :version "0.0.1.3"
  :license "GPL-3.0"
  :author "cl-uf2"
  :depends-on ("iterate" "metabang-bind" "clingon")
  :serial t
  :components
  ((:module "src"
    :serial t
    :components
    ((:file "packages")
     (:file "uf2")
     (:file "main"))))
  :build-operation "program-op"
  :build-pathname "build/uf2"
  :entry-point "cl-uf2:main")
