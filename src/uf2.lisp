(in-package #:cl-uf2)

;;;; UF2 format constants.
;;;; See <https://github.com/microsoft/uf2> for the official specification.

(defconstant +magic-start0+ #x0A324655 "First magic number (\"UF2\\n\").")
(defconstant +magic-start1+ #x9E5D5157 "Second magic number (randomly chosen).")
(defconstant +magic-end+    #x0AB16F30 "Final magic number (randomly chosen).")

(defconstant +flag-no-flash+          #x00000001 "Block should be skipped when writing the device flash.")
(defconstant +flag-file-container+    #x00001000 "Block is part of a file container.")
(defconstant +flag-family-id-present+ #x00002000 "The FamilyID field is valid.")
(defconstant +flag-md5-present+       #x00004000 "Block contains an MD5 checksum.")
(defconstant +flag-ext-tags-present+  #x00008000 "Block contains extension tags.")

(defconstant +header-size+      32 "UF2 block header size in bytes.")
(defconstant +payload-max+     476 "Maximum UF2 block payload size in bytes.")
(defconstant +block-size+      512 "Total UF2 block size in bytes.")
(defconstant +default-payload+ 256 "Default UF2 block payload size in bytes.")
(defconstant +read-buffer-size+ 4096 "Read buffer size in bytes for conversions.")

;;;; Little-endian unsigned 32-bit helpers.

(defun read-u32-le (octets offset)
  "Read an unsigned 32-bit little-endian integer from OCTETS at OFFSET."
  (iter
    (with value = 0)
    (for i from 3 downto 0)
    (setf value (logior (ash value 8) (aref octets (+ offset i))))
    (finally (return value))))

(defun write-u32-le (value octets offset)
  "Write VALUE as an unsigned 32-bit little-endian integer into OCTETS at OFFSET."
  (iter
    (for i from 0 below 4)
    (setf (aref octets (+ offset i))
          (logand (ash value (- (* 8 i))) #xFF))))

;;;; Block structure.

(defstruct (uf2-block (:constructor make-uf2-block))
  flags
  target-address
  payload-size
  block-no
  block-totals
  family-id
  payload)

(defun block-check-p (octets)
  "Return non-NIL when OCTETS carry the UF2 magic numbers."
  (and (= (read-u32-le octets 0) +magic-start0+)
       (= (read-u32-le octets 4) +magic-start1+)
       (= (read-u32-le octets (+ +header-size+ +payload-max+)) +magic-end+)))

(defun decode-block (octets)
  "Decode a 512-byte UF2 block held in OCTETS.
Signals an error when the magic numbers or the payload size are invalid."
  (unless (block-check-p octets)
    (error "Illegal UF2 file, block not UF2 block !"))
  (let ((payload-size (read-u32-le octets 16)))
    (unless (and (plusp payload-size) (<= payload-size +payload-max+))
      (error "Illegal UF2 file, block size invalid !"))
    (make-uf2-block
     :flags          (read-u32-le octets 8)
     :target-address (read-u32-le octets 12)
     :payload-size   payload-size
     :block-no       (read-u32-le octets 20)
     :block-totals   (read-u32-le octets 24)
     :family-id      (read-u32-le octets 28)
     :payload        (subseq octets +header-size+ (+ +header-size+ payload-size)))))

(defun encode-block (block)
  "Encode BLOCK into a fresh 512-byte octet vector.
The payload is padded with zeros up to the maximum payload size."
  (let ((octets (make-array +block-size+ :element-type '(unsigned-byte 8)
                                          :initial-element 0)))
    (write-u32-le +magic-start0+ octets 0)
    (write-u32-le +magic-start1+ octets 4)
    (write-u32-le (uf2-block-flags block)          octets 8)
    (write-u32-le (uf2-block-target-address block) octets 12)
    (write-u32-le (uf2-block-payload-size block)   octets 16)
    (write-u32-le (uf2-block-block-no block)       octets 20)
    (write-u32-le (uf2-block-block-totals block)   octets 24)
    (write-u32-le (uf2-block-family-id block)      octets 28)
    (replace octets (uf2-block-payload block) :start1 +header-size+)
    (write-u32-le +magic-end+ octets (+ +header-size+ +payload-max+))
    octets))
