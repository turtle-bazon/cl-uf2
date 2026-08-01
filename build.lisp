(ql:quickload "cl-uf2")
(ensure-directories-exist #p"build/uf2")
(asdf:make "cl-uf2")
