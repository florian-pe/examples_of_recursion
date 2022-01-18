#!/usr/bin/sbcl --script

; definition of a function "stringify-dsc" which stringify nested lists
; this function was originally needed in order to implement a toy Lisp interpreter

(defun say (l) (princ l) (terpri))

(defun join (list)
  (cond ((null list) "")
        (T (concatenate 'string (car list) (join (cdr list))))))

(defun is-quote (l)
  (eq (car l) 'QUOTE))

(defun stringify-dsc (l)
  (cond ((atom l) (stringify-atom l))
        (T        (join (list (stringify-list l))))))

(defun stringify-list (l)
  (cond ((atom (car l))
           (cond ((is-quote l) (join (list "'" (stringify-list (cadr l)))))
                 (T            (join (list "("
                                           (stringify-list-first (car l))
                                           (stringify-list-rest (cdr l)))))))
        (T (join (list "("
                       (stringify-list (car l))
                       (stringify-list-rest (cdr l)))))))

; a list is separated into its first element and the rest of elements to deal with spaces
; every element of a list, except the first is preceded by a space
; ex: '(a b c)

(defun stringify-list-first (l)
  (cond ((null l) "")      ; empty list

        ; first element is an atom
        ((atom l) (stringify-atom l))

        ; first element is a cons/list
        (T (join (list (stringify-list l))))))

(defun stringify-list-rest (l)
  (cond ((null l) ")")     ; end of the list

        ; dotted pair
        ((atom l) (join (list " . " (stringify-atom l) ")")))

        ; current element is an atom
        ((atom (car l)) (join (list " "
                                    (stringify-atom (car l))
                                    (stringify-list-rest (cdr l)))))
        ; current element is a cons/list
        (T (join (list " "
                       (stringify-list (car l))
                       (stringify-list-rest (cdr l)))))))


(defun stringify-atom (l) ; convert various types to string
  (cond ((null l) "NIL")
        (T (string l))))

(defun test-print (l)
  (progn
;          (say l)
         (say (stringify-dsc l))
         (say (string= (princ-to-string l) (stringify-dsc l)))
         ))


; atoms
(test-print ())
(test-print '())
(test-print 'a)

; lists
(test-print '(a))
(test-print '(a b c))

; lists of lists
(test-print '(a b c (d e f)))
(test-print '((a (b)) c (d e f)))
(test-print '((a (b)) c ((d ((e))) f)))

; nil in a list
(test-print '(a () c))
(test-print '(a nil c))

; dotted pairs
(test-print '(a . b))
(test-print '((a . b)))
(test-print '(a b . c))
(test-print '(a (b . c)))

; quote
(test-print '(a b c '(d e f)))
(test-print '(a '(b) c '(d '(e) f)))

(test-print '(a '(b) c (quote (d '(e) f))))
(test-print '(a '(b) c '(quote (d '(e) f))))

(test-print '(a '(b) c (quote '(d '(e) f))))
(test-print '(a '(b) c '(quote '(d '(e) f))))





