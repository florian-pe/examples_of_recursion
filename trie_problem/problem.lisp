#!/usr/bin/sbcl --script

; implementation in Common Lisp of the Perl script solution

(require 'uiop)

(defun say (l) (princ l) (terpri))

(defvar root)
(defvar ptr)
(setq root (make-hash-table :test 'equal))

; (remhash 'key ht)
 
(mapcar
  (lambda (filepath)
    (setf ptr root)
;     (setq ptr root)
    (mapcar
      (lambda (file)
        (if (gethash file ptr)
            nil
            (let ((hash (make-hash-table :test 'equal)))
              (setf (gethash file ptr) hash)))
        (setf ptr (gethash file ptr)))
;         (setq ptr (gethash file ptr)))
      (uiop::split-string filepath :separator "/"))
    )
  '("dir1/file1.txt" "file2.txt" "dir1/file3.txt" "dir2/file4.txt"))

; (let ((keys (list)))
;   (maphash (lambda (k v) (setq keys (append keys (list k)))) root)
;   (say keys))


(defun cat (&rest list)
  (cond ((null list) "")
        ((null (cdr list)) (car list))
        (T (concatenate 'string (car list) (cat-list (cdr list))))))

(defun cat-list (list)
  (cond ((null list) "")
        ((null (cdr list)) (car list))
        (T (concatenate 'string (car list) (cat-list (cdr list))))))

(defun join (joiner list)
  (cond ((null list) "")
        ((null (cdr list)) (car list))
        (T (cat (car list) joiner (join joiner (cdr list))))))

(defun json-array (list)
  (cat "["
       (join "," list)
       "]"))

(defun json-object (list)
  (cat "{"
       (join "," list)
       "}"))

(defun json-pair (k v)
  (cat "\"" k "\":" v ))

(defun json-string (str)
  (cat "\"" str "\""))

(defun make-json (hash)
    (let ((array (list)))
      (maphash
        (lambda (k v)
          (setq array
                (append array
                        (list (json-object
                                (list
                                  (json-pair "name" (json-string k))
                                  (json-pair "children"
;                                              "[]")))))))
                                             (json-array (make-json (gethash k hash))))))))))
                                               
        hash)
      array))

(say (json-array (make-json root)))


