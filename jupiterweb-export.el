;;; jupiterweb-export.el --- JSON export for JupiterWeb  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  rodrigues-am

;; This file is not part of GNU Emacs.

;;; Commentary:

;; JSON export of cached curriculum and discipline data for the
;; jupiterweb package.

;;; Code:

(require 'json)
(require 'jupiterweb-vars)
(require 'jupiterweb-cache)

(defun jupiterweb--alist-to-json (data)
  "Recursively convert DATA for JSON serialization.
Converts alists to hash tables and lists to vectors."
  (cond
   ((null data) nil)
   ((stringp data) data)
   ((numberp data) data)
   ((eq data t) t)
   ((symbolp data) (symbol-name data))
   ((hash-table-p data)
    (let ((ht (make-hash-table :test 'equal)))
      (maphash (lambda (k v) (puthash k (jupiterweb--alist-to-json v) ht)) data)
      ht))
   ((listp data)
    (if (consp (car data))
        ;; It's an alist — convert to hash table
        (let ((ht (make-hash-table :test 'equal)))
          (dolist (pair data)
            (puthash (cond ((stringp (car pair)) (car pair))
                           ((symbolp (car pair)) (symbol-name (car pair)))
                           (t (format "%s" (car pair))))
                     (jupiterweb--alist-to-json (cdr pair))
                     ht))
          ht)
      ;; It's a plain list (array) — convert to vector
      (vconcat (mapcar #'jupiterweb--alist-to-json data))))
   (t data)))

(defun jupiterweb--plist-to-json-key (keyword)
  "Convert a keyword like :credits-lecture to \"credits_lecture\"."
  (let ((name (symbol-name keyword)))
    (replace-regexp-in-string "-" "_" (substring name 1))))

(defun jupiterweb--convert-discipline-to-json (discipline)
  "Convert a discipline plist to a JSON-compatible alist."
  (let ((result nil)
        (keys '(:sgldis :name :unit :block :syllabus-status
                :credits-lecture :credits-work :workload-total
                :workload-pcc :workload-internship :workload-extension
                :type :activation :deactivation :syllabus :objectives
                :summary-program :program :teaching-method
                :assessment-method :recovery-rule :bibliography
                :basic-bibliography :complementary-bibliography
                :sustainable-development-goals :instructors
                :instructors-list :source-url :fetched-at :name-en
                :group :extra :observation)))
    (dolist (key keys)
      (let ((val (plist-get discipline key)))
        (when val
          (push (cons (jupiterweb--plist-to-json-key key) val) result))))
    (nreverse result)))

;;;###autoload
(defun jupiterweb-export-cache-json (file &optional fetch-missing)
  "Export current curriculum and cached syllabi to FILE as JSON.
With prefix arg (FETCH-MISSING non-nil), fetch missing syllabi first."
  (interactive
   (list (read-file-name "Export to: ")
         current-prefix-arg))
  (let ((curriculum (jupiterweb--ensure-curriculum))
        (failures nil)
        (disciplines nil))
    (when curriculum
      (dolist (d (plist-get curriculum :disciplines))
        (let* ((sgldis (plist-get d :sgldis))
               (data (jupiterweb--ensure-discipline sgldis)))
          (if data
              (push (jupiterweb--convert-discipline-to-json
                     (append d (list :syllabus-status "cached")))
                    disciplines)
            (push (jupiterweb--convert-discipline-to-json
                   (append d (list :syllabus-status "missing")))
                  disciplines)
            (push (list :sgldis sgldis :error "No syllabus data") failures))))
      (let ((export-data (list (cons "package" "jupiterweb")
                               (cons "schema_version" 1)
                               (cons "exported_at" (format-time-string "%Y-%m-%dT%H:%M:%S%z"))
                               (cons "course"
                                     (list (cons "codcg" jupiterweb-codcg)
                                           (cons "codcur" jupiterweb-codcur)
                                           (cons "codhab" jupiterweb-codhab)
                                           (cons "tipo" jupiterweb-tipo)
                                           (cons "curriculum_source_url"
                                                 (jupiterweb--grade-url))))
                               (cons "disciplines" (nreverse disciplines))
                               (cons "failures" (nreverse failures)))))
        (jupiterweb--ensure-cache-directory)
        (with-temp-buffer
          (let ((json-encoding-pretty-print t))
            (insert (json-serialize (jupiterweb--alist-to-json export-data))))
          (write-region (point-min) (point-max) file nil nil nil nil))
        (message "Exported to %s" file)
        export-data))))

(provide 'jupiterweb-export)
;;; jupiterweb-export.el ends here