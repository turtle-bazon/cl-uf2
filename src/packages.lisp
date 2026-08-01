(defpackage #:cl-uf2
  (:use #:cl #:iterate #:metabang-bind)
  (:nicknames #:uf2)
  (:export
   ;; entry point
   #:main
   ;; format layer
   #:+magic-start0+
   #:+magic-start1+
   #:+magic-end+
   #:+flag-no-flash+
   #:+flag-file-container+
   #:+flag-family-id-present+
   #:+flag-md5-present+
   #:+flag-ext-tags-present+
   #:+header-size+
   #:+payload-max+
   #:+block-size+
   #:+default-payload+
   #:uf2-block
   #:make-uf2-block
   #:uf2-block-p
   #:uf2-block-flags
   #:uf2-block-target-address
   #:uf2-block-payload-size
   #:uf2-block-block-no
   #:uf2-block-block-totals
   #:uf2-block-family-id
   #:uf2-block-payload
   #:uf2-file-info
   #:make-uf2-file-info
   #:uf2-file-info-p
   #:uf2-file-info-path
   #:uf2-file-info-file-size
   #:uf2-file-info-uniform-p
   #:uf2-file-info-blocks
   #:read-u32-le
   #:write-u32-le
   #:block-check-p
   #:decode-block-header
   #:decode-block
   #:encode-block
   ;; conversions
   #:bin-to-uf2
   #:uf2-to-bin
   ;; inspection
   #:uf2-info
   #:print-uf2-info
   ;; CLI helpers
   #:parse-u32
   #:default-output-path
   #:prompt-overwrite
   #:output-overwrite-ok
   #:print-version
   #:print-usage
   #:print-summary))
