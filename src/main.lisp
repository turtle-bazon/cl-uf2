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
             (buffer (make-array payload-size :element-type '(unsigned-byte 8)))
             (block (make-uf2-block :flags flags
                                    :block-totals block-totals
                                    :family-id family-id))
             (address target-address))
        (iter
          (for block-no from 0)
          (for len := (read-sequence buffer in))
          (while (plusp len))
          (for actual := (if (and fixed (< len payload-size)) len payload-size))
          (setf (uf2-block-block-no block)       block-no
                (uf2-block-target-address block) address
                (uf2-block-payload-size block)   actual
                (uf2-block-payload block)
                (let ((payload (make-array actual :element-type '(unsigned-byte 8)
                                                 :initial-element 0)))
                  (replace payload buffer :end2 len)
                  payload))
          (write-sequence (encode-block block) out)
          (incf address actual))
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
      (let ((buffer (make-array +block-size+ :element-type '(unsigned-byte 8)))
            (base-address 0)
            (family-id 0)
            (flags 0)
            (payload-size 0)
            (block-totals 0))
        (iter
          (for n := (read-sequence buffer in))
          (while (= n +block-size+))
          (for blk := (decode-block buffer))
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
            (write-sequence (uf2-block-payload blk) out)))
        (finish-output out)
        (values (file-length in) (file-length out) family-id base-address
                flags payload-size block-totals)))))

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

(defun print-usage (&optional (stream *standard-output*))
  (write-string
   "Usage: uf2 conv [--dump] [--flags=<flags>] [--address=<address>] [--identify=<identify>]
                [--size=<size>] [--fixed] [--help] <INPUT> [<OUTPUT>]

Options:
    dump (-d)      Dump UF2 payload to binary;
    flags (-f)     Set UF2 block flags, default is 0x00000000;
    address (-a)   Set target address, default is 0x00000000;
    identify (-i)  Set family identify, default is 0x00000000;
    size (-s)      Set UF2 block payload size, default is 256 bytes;
    fixed (-F)     fixed UF2 block payload size if remaining valid data less then expected;
    force (-y)     force overwriting an existing output file;
    help (-h)      Print usage massages;

Example:
    uf2 conv firmware.bin [firmware.uf2]
    uf2 conv -d firmware.uf2 [firmware.bin]

uf2 & bin convert tools (Common Lisp) v1.0.0
"
   stream))

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
    (list :dump (clingon:getopt cmd :dump)
          :flags (parse-flags (clingon:getopt cmd :flags))
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

(defun conv-handler (cmd)
  (handler-case
      (progn
        (when (clingon:getopt cmd :help)
          (print-usage)
          (clingon:exit 0))
        (let* ((settings (options->settings cmd))
               (dump (getf settings :dump))
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

(defun make-conv-options ()
  (list
   (clingon:make-option :flag
                        :short-name #\d
                        :long-name "dump"
                        :description "Dump UF2 payload to binary;"
                        :key :dump)
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

(defun make-conv-command ()
  (clingon:make-command
   :name "conv"
   :description "Convert between UF2 and BIN formats."
   :options (make-conv-options)
   :handler #'conv-handler))

(defun make-sub-commands ()
  "Return the list of uf2 sub-commands. Additional tools are added here."
  (list (make-conv-command)))

(defun make-uf2-command ()
  (clingon:make-command
   :name "uf2"
   :description "Microsoft UF2 & BIN format convert tools"
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
