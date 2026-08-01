(in-package #:cl-uf2)

;;;; Number parsing (strtoul base-0 semantics).

(defun parse-u32 (string)
  "Parse STRING as an unsigned 32-bit integer using strtoul base-0 rules:
hexadecimal with a 0x prefix, octal with a leading 0, decimal otherwise.
Return the value, or NIL when the input is not a valid number."
  (when (null string)
    (return-from parse-u32 nil))
  (let ((s (string-trim '(#\Space #\Tab #\Newline #\Return) string)))
    (when (zerop (length s))
      (return-from parse-u32 nil))
    (multiple-value-bind (value end)
        (cond
          ((and (>= (length s) 2)
                (char= (char s 0) #\0)
                (char-equal (char s 1) #\X))
           (and (>= (length s) 3)
                (parse-integer s :start 2 :radix 16 :junk-allowed t)))
          ((char= (char s 0) #\0)
           (parse-integer s :radix 8 :junk-allowed t))
          (t
           (parse-integer s :radix 10 :junk-allowed t)))
      (when (and value (= end (length s)))
        (logand value #xffffffff)))))

;;;; Conversions.

(defun bin-to-uf2 (input-path output-path
                   &key (flags 0) (target-address 0) (family-id 0)
                        (payload-size +default-payload+) (fixed nil))
  "Convert the binary file at INPUT-PATH into a UF2 file written to OUTPUT-PATH.
Returns (values input-size output-size family-id target-address flags
payload-size block-totals)."
  (with-open-file (in input-path :direction :input :element-type '(unsigned-byte 8))
    (with-open-file (out output-path :direction :output :if-exists :supersede
                         :element-type '(unsigned-byte 8))
      (let* ((file-size (file-length in))
             (block-totals (ceiling file-size payload-size))
             (buffer (make-array +read-buffer-size+ :element-type '(unsigned-byte 8)))
             (block (make-uf2-block :flags flags
                                    :block-totals block-totals
                                    :family-id family-id))
             (address target-address)
             (block-no 0))
        (iter
          (for len := (read-sequence buffer in))
          (while (plusp len))
          (iter
            (for off from 0 by payload-size)
            (while (< off len))
            (for remaining := (- len off))
            (for actual := (if (and fixed (< remaining payload-size))
                               remaining payload-size))
            (setf (uf2-block-block-no block)       block-no
                  (uf2-block-target-address block) address
                  (uf2-block-payload-size block)   actual
                  (uf2-block-payload block)
                  (let ((payload (make-array actual :element-type '(unsigned-byte 8)
                                                   :initial-element 0)))
                    (replace payload buffer :start2 off :end2 (+ off remaining))
                    payload))
            (write-sequence (encode-block block) out)
            (incf address actual)
            (incf block-no)))
        (finish-output out)
        (values file-size (file-length out) family-id target-address
                flags payload-size block-totals)))))

(defun uf2-to-bin (input-path output-path)
  "Convert the UF2 file at INPUT-PATH into a binary file written to OUTPUT-PATH.
Returns (values input-size output-size family-id target-address flags
payload-size block-totals)."
  (with-open-file (in input-path :direction :input :element-type '(unsigned-byte 8))
    (unless (zerop (mod (file-length in) +block-size+))
      (error "Illegal UF2 file, file size must be block size align (512 bytes) !"))
    (with-open-file (out output-path :direction :output :if-exists :supersede
                         :element-type '(unsigned-byte 8))
      (let ((buffer (make-array +read-buffer-size+ :element-type '(unsigned-byte 8)))
            (base-address 0)
            (family-id 0)
            (flags 0)
            (payload-size 0)
            (block-totals 0))
        (iter
          (for n := (read-sequence buffer in))
          (while (plusp n))
          (iter
            (for off from 0 by +block-size+)
            (while (< off n))
            (for blk := (decode-block buffer off))
            (when (zerop (uf2-block-block-no blk))
              (setf base-address (uf2-block-target-address blk)
                    family-id    (uf2-block-family-id blk)
                    flags        (uf2-block-flags blk)
                    payload-size (uf2-block-payload-size blk)
                    block-totals (uf2-block-block-totals blk)))
            (let ((address (uf2-block-target-address blk)))
              (when (< address base-address)
                (error "Illegal UF2 file, target address invalid !"))
              (file-position out (- address base-address))
              (write-sequence (uf2-block-payload blk) out))))
        (finish-output out)
        (values (file-length in) (file-length out) family-id base-address
                flags payload-size block-totals)))))

(defun uf2-info (input-path)
  "Scan the UF2 file at INPUT-PATH and collect the file summary into a
fresh uf2-file-info structure: block headers, file size and whether
all blocks share the same flags, payload size and family id."
  (with-open-file (in input-path :direction :input :element-type '(unsigned-byte 8))
    (unless (zerop (mod (file-length in) +block-size+))
      (error "Illegal UF2 file, file size must be block size align (512 bytes) !"))
    (let ((buffer (make-array +read-buffer-size+ :element-type '(unsigned-byte 8)))
          (blocks '()))
      (iter
        (for n := (read-sequence buffer in))
        (while (plusp n))
        (iter
          (for off from 0 by +block-size+)
          (while (< off n))
          (push (decode-block-header buffer off) blocks)))
      (let* ((blocks (nreverse blocks))
             (first-block (first blocks))
             (uniform-p (and first-block
                             (every (lambda (b)
                                      (and (= (uf2-block-flags b)
                                              (uf2-block-flags first-block))
                                           (= (uf2-block-payload-size b)
                                              (uf2-block-payload-size first-block))
                                           (= (uf2-block-family-id b)
                                              (uf2-block-family-id first-block))))
                                    blocks))))
        (make-uf2-file-info
         :path (namestring input-path)
         :file-size (file-length in)
         :uniform-p uniform-p
         :blocks blocks)))))

(defun print-uf2-info (info &key (all nil))
  "Print a summary of the UF2 file described by INFO followed by a
table of the first (up to 10) blocks, or of every block when ALL is set."
  (let* ((blocks (uf2-file-info-blocks info))
         (n (length blocks))
         (first-block (first blocks)))
    (format t "  UF2 file: ~A~%" (uf2-file-info-path info))
    (format t "Block Size: ~D~%Block Counts: ~D~%File Size: ~D~%"
            +block-size+ n (uf2-file-info-file-size info))
    (when first-block
      (format t "Flags: 0x~8,'0X~%Target Address: 0x~8,'0X~%Payload Size: ~D~%Family Identify: 0x~8,'0X~%"
              (uf2-block-flags first-block) (uf2-block-target-address first-block)
              (uf2-block-payload-size first-block) (uf2-block-family-id first-block)))
    (format t "Uniform blocks: ~A~%~%" (if (uf2-file-info-uniform-p info) "yes" "no"))
    (format t "  Block  Address      Flags      Payload  Family~%")
    (loop for b in blocks
          for i from 0
          while (or all (< i 10))
          do (format t "  ~5D  0x~8,'0X  0x~8,'0X  ~7D  0x~8,'0X~%"
                     (uf2-block-block-no b)
                     (uf2-block-target-address b)
                     (uf2-block-flags b)
                     (uf2-block-payload-size b)
                     (uf2-block-family-id b)))
    (when (and (not all) (> n 10))
      (format t "  ... and ~D more blocks~%" (- n 10)))))

(defun json-escape (string)
  "Return STRING with the characters special to JSON string literals escaped."
  (with-output-to-string (out)
    (loop for ch across string
          do (case ch
               (#\" (write-string "\\\"" out))
               (#\\ (write-string "\\\\" out))
               (#\Newline (write-string "\\n" out))
               (#\Return (write-string "\\r" out))
               (#\Tab (write-string "\\t" out))
               (otherwise
                (unless (< (char-code ch) #x20)
                  (write-char ch out)))))))

(defun print-json-block (block)
  "Print BLOCK as a JSON object."
  (format t "    {~%")
  (format t "      \"block_no\": ~D,~%" (uf2-block-block-no block))
  (format t "      \"target_address\": ~D,~%" (uf2-block-target-address block))
  (format t "      \"flags\": ~D,~%" (uf2-block-flags block))
  (format t "      \"payload_size\": ~D,~%" (uf2-block-payload-size block))
  (format t "      \"family_id\": ~D~%" (uf2-block-family-id block))
  (format t "    }"))

(defun print-uf2-info-json (info)
  "Print INFO as a JSON object including the full block list."
  (let* ((blocks (uf2-file-info-blocks info))
         (n (length blocks))
         (first-block (first blocks)))
    (format t "{~%")
    (format t "  \"path\": \"~A\",~%" (json-escape (uf2-file-info-path info)))
    (format t "  \"file_size\": ~D,~%" (uf2-file-info-file-size info))
    (format t "  \"block_size\": ~D,~%" +block-size+)
    (format t "  \"block_count\": ~D,~%" n)
    (format t "  \"uniform\": ~A,~%" (if (uf2-file-info-uniform-p info) "true" "false"))
    (if first-block
        (progn
          (format t "  \"first_block\": {~%")
          (format t "    \"block_no\": ~D,~%" (uf2-block-block-no first-block))
          (format t "    \"target_address\": ~D,~%" (uf2-block-target-address first-block))
          (format t "    \"flags\": ~D,~%" (uf2-block-flags first-block))
          (format t "    \"payload_size\": ~D,~%" (uf2-block-payload-size first-block))
          (format t "    \"family_id\": ~D~%" (uf2-block-family-id first-block))
          (format t "  },~%"))
        (format t "  \"first_block\": null,~%"))
    (format t "  \"blocks\": [~%")
    (loop for b in blocks
          for i from 0
          do (print-json-block b)
             (format t "~A~%" (if (= i (1- n)) "" ",")))
    (format t "  ]~%")
    (format t "}~%")))

;;;; Output path handling.

(defun prompt-overwrite (path)
  "Ask the user whether to overwrite PATH. Return T when consenting,
NIL otherwise (including at end of input)."
  (format *query-io* "File ~S already exists. Overwrite? [y/N] " path)
  (finish-output *query-io*)
  (let ((line (read-line *query-io* nil nil)))
    (when line
      (let ((answer (string-trim '(#\Space #\Tab #\Return #\Newline) line)))
        (and (plusp (length answer))
             (char-equal (char answer 0) #\y))))))

(defun output-overwrite-ok (output force confirm)
  "Return non-NIL when writing to OUTPUT is permitted: FORCE is set,
OUTPUT does not exist yet, or CONFIRM consents (CONFIRM takes one
argument, the output path)."
  (or force
      (not (probe-file output))
      (funcall confirm output)))

(defun default-output-path (input-path dump)
  "Derive an output filename from INPUT-PATH by swapping the extension to
.uf2 (or .bin in dump mode). When the input already carries the target
extension, the extension is doubled (.uf2.uf2 / .bin.bin)."
  (multiple-value-bind (name type)
      (uiop:split-name-type (namestring input-path))
    (let* ((target (if dump "bin" "uf2"))
           (new-type (if (and type (string= type target))
                         (format nil "~A.~A" target target)
                         target)))
      (format nil "~A.~A" name new-type))))

;;;; Summary reporting.

(defun print-summary (title input-size output-size family-id target-address
                            flags payload-size block-totals)
  (format t "  ~A~%Binary Size: ~D~%Family Identify: 0x~8,'0X~%Target Address: 0x~8,'0X~%UF2 Size: ~D~%UF2 Flags: 0x~8,'0X~%UF2 Block Size: ~D~%UF2 Block Counts: ~D~%~%"
          title input-size family-id target-address output-size
          flags payload-size block-totals))

(defun print-version (&optional (stream *standard-output*))
  (format stream "uf2 & bin convert tools (Common Lisp) v~A~%"
          (asdf:component-version (asdf:find-system :cl-uf2))))

(defun print-usage (&optional (stream *standard-output*))
  (write-string
   "Usage: uf2 to-uf2 [options] <INPUT> [<OUTPUT>]
       uf2 from-uf2 [options] <INPUT> [<OUTPUT>]
       uf2 info <INPUT>

to-uf2 converts a BIN file to UF2; from-uf2 converts a UF2 file to BIN;
info displays header information from a UF2 file.

Options for to-uf2:
    flags (-f)     Set UF2 block flags, default is 0x00000000;
    address (-a)   Set target address, default is 0x00000000;
    identify (-i)  Set family identify, default is 0x00000000;
    size (-s)      Set UF2 block payload size, default is 256 bytes;
    fixed (-F)     fixed UF2 block payload size if remaining valid data less then expected;
    force (-y)     force overwriting an existing output file;
    help (-h)      Print usage massages;

Options for from-uf2:
    force (-y)     force overwriting an existing output file;
    help (-h)      Print usage massages;

Options for info:
    all (-a)       Print all blocks, not only the first ten;
    machine (-m)   Print machine-readable JSON output with all blocks;
    help (-h)      Print usage massages;

Example:
    uf2 to-uf2 firmware.bin [firmware.uf2]
    uf2 from-uf2 firmware.uf2 [firmware.bin]
    uf2 info firmware.uf2

"
   stream)
  (print-version stream))

;;;; Command-line interface.

(defun parse-option-number (string message)
  (or (parse-u32 string)
      (error "~A (got ~S)" message string)))

(defun parse-flags (strings)
  (reduce (lambda (acc s)
            (logior acc (parse-option-number s "Illegal or unknown flags !")))
          strings :initial-value 0))

(defun parse-payload-size (string)
  (let ((value (parse-option-number string "Illegal or unknown payload size !")))
    (if (or (> value +payload-max+) (not (plusp value)))
        (error "Illegal payload size [0 ~~ 476] ! (got ~D)" value)
        value)))

(defun options->settings (cmd)
  (let ((address-str (clingon:getopt cmd :address))
        (identify-str (clingon:getopt cmd :identify))
        (size-str (clingon:getopt cmd :size)))
    (list :flags (parse-flags (clingon:getopt cmd :flags))
          :address (if address-str
                       (parse-option-number address-str "Illegal or unknown address !")
                       0)
          :family-id (if identify-str
                         (parse-option-number identify-str "Illegal or unknown identify !")
                         0)
          :identify-set (not (null identify-str))
          :payload-size (if size-str (parse-payload-size size-str) +default-payload+)
          :fixed (clingon:getopt cmd :fixed)
          :force (clingon:getopt cmd :force))))

(defun ensure-input-file (input)
  (unless input
    (error "No input file !"))
  (unless (probe-file input)
    (error "Can not open input file !"))
  input)

(defun convert (dump input output settings)
  (bind (((:values input-size output-size family-id target-address
                   flg psize totals)
          (if dump
              (uf2-to-bin input output)
              (bin-to-uf2 input output
                          :flags (getf settings :flags)
                          :target-address (getf settings :address)
                          :family-id (getf settings :family-id)
                          :payload-size (getf settings :payload-size)
                          :fixed (getf settings :fixed)))))
    (print-summary (if dump "Convert UF2 to BIN:" "Convert BIN to UF2:")
                  input-size output-size family-id target-address
                  flg psize totals)))

(defun conversion-handler (dump cmd)
  (handler-case
      (progn
        (when (clingon:getopt cmd :help)
          (print-usage)
          (clingon:exit 0))
        (let* ((settings (options->settings cmd))
               (args (clingon:command-arguments cmd))
               (input (ensure-input-file (first args)))
               (output (or (second args) (default-output-path input dump))))
          (unless (output-overwrite-ok output (getf settings :force)
                                       #'prompt-overwrite)
            (error "File ~S already exists, not overwritten !" output))
          (when (getf settings :identify-set)
            (setf (getf settings :flags)
                  (logior (getf settings :flags) +flag-family-id-present+)))
          (convert dump input output settings)))
    (file-error ()
      (format *error-output* "Can not open output file !~%")
      (clingon:exit 255))
    (error (e)
      (format *error-output* "~A~%" e)
      (clingon:exit 255))))

(defun to-uf2-handler (cmd)
  (conversion-handler nil cmd))

(defun from-uf2-handler (cmd)
  (conversion-handler t cmd))

(defun make-to-uf2-options ()
  (list
   (clingon:make-option :list
                        :short-name #\f
                        :long-name "flags"
                        :description "Set UF2 block flags, default is 0x00000000;"
                        :key :flags)
   (clingon:make-option :string
                        :short-name #\a
                        :long-name "address"
                        :description "Set target address, default is 0x00000000;"
                        :key :address)
   (clingon:make-option :string
                        :short-name #\i
                        :long-name "identify"
                        :description "Set family identify, default is 0x00000000;"
                        :key :identify)
   (clingon:make-option :string
                        :short-name #\s
                        :long-name "size"
                        :description "Set UF2 block payload size, default is 256 bytes;"
                        :key :size)
   (clingon:make-option :flag
                        :short-name #\F
                        :long-name "fixed"
                        :description "fixed UF2 block payload size if remaining valid data less then expected;"
                        :key :fixed)
   (clingon:make-option :flag
                        :short-name #\y
                        :long-name "force"
                        :description "force overwriting an existing output file;"
                        :key :force)
   (clingon:make-option :flag
                        :short-name #\h
                        :description "Print usage massages;"
                        :key :help)))

(defun make-from-uf2-options ()
  (list
   (clingon:make-option :flag
                        :short-name #\y
                        :long-name "force"
                        :description "force overwriting an existing output file;"
                        :key :force)
   (clingon:make-option :flag
                        :short-name #\h
                        :description "Print usage massages;"
                        :key :help)))

(defun make-to-uf2-command ()
  (clingon:make-command
   :name "to-uf2"
   :description "Convert a BIN file to UF2."
   :options (make-to-uf2-options)
   :handler #'to-uf2-handler))

(defun make-from-uf2-command ()
  (clingon:make-command
   :name "from-uf2"
   :description "Convert a UF2 file to BIN."
   :options (make-from-uf2-options)
   :handler #'from-uf2-handler))

(defun info-handler (cmd)
  (handler-case
      (progn
        (when (clingon:getopt cmd :help)
          (print-usage)
          (clingon:exit 0))
        (let ((input (ensure-input-file
                      (first (clingon:command-arguments cmd)))))
          (let ((info (uf2-info input)))
            (if (clingon:getopt cmd :machine)
                (print-uf2-info-json info)
                (print-uf2-info info :all (clingon:getopt cmd :all))))))
    (error (e)
      (format *error-output* "~A~%" e)
      (clingon:exit 255))))

(defun make-info-options ()
  (list
   (clingon:make-option :flag
                        :short-name #\a
                        :long-name "all"
                        :description "Print all blocks, not only the first ten;"
                        :key :all)
   (clingon:make-option :flag
                        :short-name #\m
                        :long-name "machine"
                        :description "Print machine-readable JSON output with all blocks;"
                        :key :machine)
   (clingon:make-option :flag
                        :short-name #\h
                        :description "Print usage massages;"
                        :key :help)))

(defun make-info-command ()
  (clingon:make-command
   :name "info"
   :description "Display UF2 file information."
   :options (make-info-options)
   :handler #'info-handler))

(defun make-sub-commands ()
  "Return the list of uf2 sub-commands. Additional tools are added here."
  (list (make-to-uf2-command) (make-from-uf2-command) (make-info-command)))

(defun make-uf2-command ()
  (clingon:make-command
   :name "uf2"
   :description "Microsoft UF2 & BIN format convert tools"
   :version (asdf:component-version (asdf:find-system :cl-uf2))
   :sub-commands (make-sub-commands)
   :handler (lambda (cmd)
              (declare (ignore cmd))
              (print-usage)
              (clingon:exit 0))))

(defun main ()
  (if (null (uiop:command-line-arguments))
      (progn
        (print-usage)
        (clingon:exit 0))
      (clingon:run (make-uf2-command))))
