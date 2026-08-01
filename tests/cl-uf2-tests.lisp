(defpackage #:cl-uf2-tests
  (:use #:cl #:iterate #:metabang-bind #:fiveam #:cl-uf2)
  (:export #:run-tests))

(in-package #:cl-uf2-tests)

(def-suite cl-uf2-tests
  :description "Round-trip and block-level tests for cl-uf2.")

(in-suite cl-uf2-tests)

(defun make-temp-dir ()
  (let ((dir (merge-pathnames
              (format nil "cl-uf2-test-~A/" (random most-positive-fixnum))
              (uiop:temporary-directory))))
    (ensure-directories-exist dir)
    dir))

(defmacro with-temp-dir ((dir) &body body)
  `(let ((,dir (make-temp-dir)))
     (unwind-protect
          (progn ,@body)
       (uiop:delete-directory-tree ,dir :validate t :if-does-not-exist :ignore))))

(defun path-in (dir name)
  (merge-pathnames name dir))

(defun write-bytes (path octets)
  (with-open-file (stream path :direction :output :if-exists :supersede
                                :element-type '(unsigned-byte 8))
    (write-sequence octets stream)))

(defun read-bytes (path)
  (with-open-file (stream path :direction :input :element-type '(unsigned-byte 8))
    (let ((octets (make-array (file-length stream) :element-type '(unsigned-byte 8))))
      (read-sequence octets stream)
      octets)))

(defun random-octets (length)
  (let ((octets (make-array length :element-type '(unsigned-byte 8))))
    (dotimes (i length)
      (setf (aref octets i) (random 256)))
    octets))

(defun hex (value)
  (format nil "~8,'0X" value))

;;;; Block-level tests.

(test block-encode-decode-round-trip
  (let ((block (make-uf2-block :flags +flag-family-id-present+
                               :target-address #x1000
                               :payload-size 16
                               :block-no 3
                               :block-totals 7
                               :family-id #xE48BFF56
                               :payload (make-array 16 :element-type '(unsigned-byte 8)
                                                      :initial-contents (list 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)))))
    (let* ((octets (encode-block block))
           (decoded (decode-block octets)))
      (is (= +block-size+ (length octets)))
      (is (block-check-p octets))
      (is (= +flag-family-id-present+ (uf2-block-flags decoded)))
      (is (= #x1000 (uf2-block-target-address decoded)))
      (is (= 16 (uf2-block-payload-size decoded)))
      (is (= 3 (uf2-block-block-no decoded)))
      (is (= 7 (uf2-block-block-totals decoded)))
      (is (= #xE48BFF56 (uf2-block-family-id decoded)))
      (is (equalp (list 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)
                  (coerce (uf2-block-payload decoded) 'list)))
      (is (= +magic-start0+ (read-u32-le octets 0)))
      (is (= +magic-start1+ (read-u32-le octets 4)))
      (is (= +magic-end+ (read-u32-le octets (+ +header-size+ +payload-max+)))))))

(test block-check-rejects-garbage
  (is (not (block-check-p (make-array +block-size+ :element-type '(unsigned-byte 8)
                                                      :initial-element 0))))
  (signals error (decode-block (make-array +block-size+ :element-type '(unsigned-byte 8)
                                                          :initial-element 0))))

(test block-payload-size-validation
  (let ((bad (make-array +block-size+ :element-type '(unsigned-byte 8)
                                       :initial-element 0)))
    ;; Valid magic numbers, payload size 0 (invalid).
    (write-u32-le +magic-start0+ bad 0)
    (write-u32-le +magic-start1+ bad 4)
    (write-u32-le 0 bad 16)
    (write-u32-le +magic-end+ bad (+ +header-size+ +payload-max+))
    (is (block-check-p bad))
    (signals error (decode-block bad))
    ;; Payload size 477 (> max, invalid).
    (write-u32-le 477 bad 16)
    (signals error (decode-block bad))))

;;;; parse-u32 tests.

(test parse-u32-hex-decimal-octal
  (is (= #x100 (parse-u32 "0x100")))
  (is (= #x100 (parse-u32 "0X100")))
  (is (= 100 (parse-u32 "100")))
  (is (= #o100 (parse-u32 "0100")))
  (is (= 0 (parse-u32 "0")))
  (is (= 0 (parse-u32 "0x0")))
  (is (null (parse-u32 nil)))
  (is (null (parse-u32 "")))
  (is (null (parse-u32 "0x")))
  (is (null (parse-u32 "zzz")))
  (is (null (parse-u32 "1a2b")))
  (is (= #xFFFFFFFF (parse-u32 "0xffffffff"))))

;;;; default-output-path tests.

(test default-output-path-swaps-extension
  (is (string= "firmware.uf2" (default-output-path #p"firmware.bin" nil)))
  (is (string= "firmware.bin" (default-output-path #p"firmware.uf2" t)))
  (is (string= "firmware.uf2.uf2" (default-output-path #p"firmware.uf2" nil)))
  (is (string= "firmware.bin.bin" (default-output-path #p"firmware.bin" t)))
  (is (string= "firmware.uf2" (default-output-path #p"firmware" nil))))

;;;; Overwrite handling tests.

(test output-overwrite-ok
  (with-temp-dir (dir)
    (let ((existing (path-in dir "exists.uf2"))
          (missing (path-in dir "missing.uf2")))
      (write-bytes existing (make-array 16 :element-type '(unsigned-byte 8)))
      ;; Missing output: consent without asking.
      (is (output-overwrite-ok missing nil
                               (lambda (p) (declare (ignore p))
                                 (error "must not be called"))))
      ;; Force: consent without asking.
      (is (output-overwrite-ok existing t nil))
      ;; Existing output: the confirm function decides.
      (is (output-overwrite-ok existing nil (lambda (p) (declare (ignore p)) t)))
      (is (not (output-overwrite-ok existing nil (lambda (p) (declare (ignore p)) nil)))))))

(test prompt-overwrite-answer
  (flet ((answer (line)
           (with-input-from-string (in line)
             (let ((*query-io* (make-two-way-stream in (make-broadcast-stream))))
               (prompt-overwrite "some/file.uf2")))))
    (is (answer "y\n"))
    (is (answer "Y\n"))
    (is (answer "yes\n"))
    (is (not (answer "n\n")))
    (is (not (answer "")))))

;;;; Conversion tests.

(defun round-trip-uf2 (bin &key (fixed t) (payload-size +default-payload+)
                            (flags 0) (target-address 0) (family-id 0))
  (with-temp-dir (dir)
    (let* ((in (path-in dir "input.bin"))
           (uf2 (path-in dir "converted.uf2"))
           (out (path-in dir "output.bin")))
      (write-bytes in bin)
      (bin-to-uf2 in uf2 :flags flags :target-address target-address
                        :family-id family-id :payload-size payload-size :fixed fixed)
      (uf2-to-bin uf2 out)
      (read-bytes out))))

(test bin-uf2-bin-round-trip-fixed
  ;; Fixed mode is lossless for any input size.
  (dolist (length '(0 1 256 257 476 1000 4096))
    (let ((original (random-octets length)))
      (is (equalp original (round-trip-uf2 original))))))

(test bin-uf2-bin-round-trip-padded
  ;; Padded (default) mode is only lossless when the input is a multiple
  ;; of the payload size; otherwise the last block is padded with zeros.
  (dolist (length '(256 512 1024))
    (let ((original (random-octets length)))
      (is (equalp original (round-trip-uf2 original :fixed nil))))))

(test bin-uf2-padded-mode-inflates-last-block
  (let ((original (random-octets 300)))
    (with-temp-dir (dir)
      (let* ((in (path-in dir "input.bin"))
             (uf2 (path-in dir "converted.uf2"))
             (out (path-in dir "output.bin")))
        (write-bytes in original)
        (bin-to-uf2 in uf2 :payload-size 256)
        (uf2-to-bin uf2 out)
        (let ((result (read-bytes out)))
          (is (= 512 (length result)))
          (is (equalp original (subseq result 0 300)))
          (is (every #'zerop (subseq result 300 512))))))))

(test bin-uf2-bin-round-trip-nonzero-base
  (let ((original (random-octets 600)))
    (is (equalp original (round-trip-uf2 original :target-address #x2000)))))

(test bin-uf2-fixed-mode
  (let ((original (random-octets 300)))
    (with-temp-dir (dir)
      (let ((in (path-in dir "input.bin"))
            (uf2-fixed (path-in dir "fixed.uf2"))
            (uf2-padded (path-in dir "padded.uf2"))
            (uf2-buf (make-array +block-size+ :element-type '(unsigned-byte 8))))
        (write-bytes in original)
        ;; Fixed mode: last block reports the true remaining length.
        (bin-to-uf2 in uf2-fixed :payload-size 256 :fixed t)
        (with-open-file (s uf2-fixed :direction :input :element-type '(unsigned-byte 8))
          (let ((n1 (read-sequence uf2-buf s))
                (n2 (read-sequence uf2-buf s)))
            (is (= +block-size+ n1))
            (is (= +block-size+ n2))
            (is (= 44 (read-u32-le uf2-buf 16)))))
        ;; Padded mode: last block keeps the full payload size.
        (bin-to-uf2 in uf2-padded :payload-size 256)
        (with-open-file (s uf2-padded :direction :input :element-type '(unsigned-byte 8))
          (let ((n1 (read-sequence uf2-buf s))
                (n2 (read-sequence uf2-buf s)))
            (declare (ignore n1 n2))
            (is (= 256 (read-u32-le uf2-buf 16)))))
        ;; Both decode back to the same binary (fixed) or to the original
        ;; followed by zero padding (padded).
        (uf2-to-bin uf2-fixed (path-in dir "out1.bin"))
        (is (equalp original (read-bytes (path-in dir "out1.bin"))))
        (uf2-to-bin uf2-padded (path-in dir "out2.bin"))
        (let ((padded (read-bytes (path-in dir "out2.bin"))))
          (is (= 512 (length padded)))
          (is (equalp original (subseq padded 0 300))))))))

(test bin-uf2-block-metadata
  (with-temp-dir (dir)
    (let* ((in (path-in dir "input.bin"))
           (uf2 (path-in dir "converted.uf2"))
           (block (make-array +block-size+ :element-type '(unsigned-byte 8))))
      (write-bytes in (random-octets 300))
      (bin-to-uf2 in uf2 :flags #x1000 :target-address #x1000
                        :family-id #xE48BFF56 :payload-size 128)
      (with-open-file (s uf2 :direction :input :element-type '(unsigned-byte 8))
        ;; Block 0
        (read-sequence block s)
        (is (= 128 (read-u32-le block 16)))
        (is (= 0 (read-u32-le block 20)))
        (is (= 3 (read-u32-le block 24)))
        (is (= #x1000 (read-u32-le block 8)))
        (is (= #x1000 (read-u32-le block 12)))
        (is (= #xE48BFF56 (read-u32-le block 28)))
        ;; Block 1: address advanced by 128
        (read-sequence block s)
        (is (= 1 (read-u32-le block 20)))
        (is (= #x1080 (read-u32-le block 12)))
        ;; Block 2: padded last block keeps the full payload size;
        ;; address advanced by 128.
        (read-sequence block s)
        (is (= 128 (read-u32-le block 16)))
        (is (= 2 (read-u32-le block 20)))
        (is (= #x1100 (read-u32-le block 12)))))))

(test uf2-dump-family-flag-consistency
  ;; The -i option sets FAMILY_ID_PRESENT; here we pass the flag directly and
  ;; verify that both the flag and the family id survive a round trip.
  (let ((original (random-octets 500)))
    (with-temp-dir (dir)
      (let* ((in (path-in dir "input.bin"))
             (uf2 (path-in dir "converted.uf2"))
             (out (path-in dir "output.bin"))
             (block (make-array +block-size+ :element-type '(unsigned-byte 8))))
        (write-bytes in original)
        (bin-to-uf2 in uf2 :flags +flag-family-id-present+
                          :family-id #x12345678 :payload-size 256 :fixed t)
        (with-open-file (s uf2 :direction :input :element-type '(unsigned-byte 8))
          (read-sequence block s)
          (is (= +flag-family-id-present+
                 (logand (read-u32-le block 8) +flag-family-id-present+)))
          (is (= #x12345678 (read-u32-le block 28))))
        (uf2-to-bin uf2 out)
        (is (equalp original (read-bytes out)))))))

(test uf2-to-bin-rejects-invalid-input
  (with-temp-dir (dir)
    (let ((bad-size (path-in dir "bad-size.uf2")))
      (write-bytes bad-size (make-array 100 :element-type '(unsigned-byte 8)
                                                :initial-element 0))
      (signals error (uf2-to-bin bad-size (path-in dir "out.bin"))))))

(test uf2-to-bin-rejects-bad-magic
  (with-temp-dir (dir)
    (let ((bad-magic (path-in dir "bad-magic.uf2")))
      (write-bytes bad-magic (make-array +block-size+ :element-type '(unsigned-byte 8)
                                                     :initial-element #xAA))
      (signals error (uf2-to-bin bad-magic (path-in dir "out.bin"))))))

(test uf2-dump-with-address-gaps
  ;; Blocks written at non-contiguous addresses produce a sparse binary;
  ;; the gaps read back as zeros.
  (let ((first (random-octets 64))
        (second (random-octets 64)))
    (with-temp-dir (dir)
      (let* ((uf2 (path-in dir "gaps.uf2"))
             (out (path-in dir "out.bin")))
        (with-open-file (s uf2 :direction :output :if-exists :supersede
                               :element-type '(unsigned-byte 8))
          (dolist (blk (list (make-uf2-block :flags 0 :target-address 0
                                             :payload-size 64 :block-no 0
                                             :block-totals 2 :family-id 0
                                             :payload first)
                             (make-uf2-block :flags 0 :target-address 4096
                                             :payload-size 64 :block-no 1
                                             :block-totals 2 :family-id 0
                                             :payload second)))
            (write-sequence (encode-block blk) s)))
        (uf2-to-bin uf2 out)
        (let ((result (read-bytes out)))
          (is (= 4160 (length result)))
          (is (equalp first (subseq result 0 64)))
          (is (every #'zerop (subseq result 64 4096)))
          (is (equalp second (subseq result 4096 4160))))))))

(defun run-tests ()
  (fiveam:run! 'cl-uf2-tests))
