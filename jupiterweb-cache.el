;;; jupiterweb-cache.el --- JSON cache read/write for JupiterWeb  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  rodrigues-am

;; This file is not part of GNU Emacs.

;;; Commentary:

;; JSON cache read/write, cache invalidation, and refresh commands for
;; the jupiterweb package.

;;; Code:

(require 'json)
(require 'jupiterweb-vars)
(require 'jupiterweb-http)
(require 'jupiterweb-parse)

(defun jupiterweb--cache-file-curriculum ()
  "Return the cache filename for the current curriculum."
  (expand-file-name
   (format "grade-codcg-%s-codcur-%s-codhab-%s-tipo-%s.json"
           jupiterweb-codcg jupiterweb-codcur jupiterweb-codhab jupiterweb-tipo)
   jupiterweb-cache-directory))

(defun jupiterweb--cache-file-discipline (sgldis)
  "Return the cache filename for discipline SGLDIS."
  (expand-file-name
   (format "disciplina-%s-codcur-%s-codhab-%s.json"
           sgldis jupiterweb-codcur jupiterweb-codhab)
   jupiterweb-cache-directory))

(defun jupiterweb--ensure-cache-directory ()
  "Ensure the cache directory exists."
  (unless (file-directory-p jupiterweb-cache-directory)
    (make-directory jupiterweb-cache-directory t))
  jupiterweb-cache-directory)

(defun jupiterweb--plist-to-json (data)
  "Recursively convert DATA for JSON serialization.
Converts plists to hash tables and lists-of-plists to vectors,
so that `json-serialize' can encode them correctly in Emacs 30+."
  (cond
   ((null data) nil)
   ((stringp data) data)
   ((numberp data) data)
   ((eq data t) t)
   ((keywordp data) (substring (symbol-name data) 1))
   ((symbolp data) (symbol-name data))
   ((listp data)
    ;; Check if it's a plist (first element is a keyword)
    (if (keywordp (car data))
        ;; It's a plist — convert to alist for json-serialize
        (let ((ht (make-hash-table :test 'equal))
              (tail data))
          (while tail
            (let ((key (substring (symbol-name (car tail)) 1))
                  (val (cadr tail)))
              (puthash key (jupiterweb--plist-to-json val) ht)
              (setq tail (cddr tail))))
          ht)
      ;; It's a list (array) — convert to vector
      (vconcat (mapcar #'jupiterweb--plist-to-json data))))
   (t data)))

(defun jupiterweb--json-read-plist (filename)
  "Read JSON from FILENAME and return a plist."
  (when (file-exists-p filename)
    (with-temp-buffer
      (insert-file-contents filename)
      (goto-char (point-min))
      (condition-case nil
          (let ((json-object-type 'plist)
                (json-array-type 'list)
                (json-key-type 'keyword))
            (json-read))
        (error nil)))))

(defun jupiterweb--json-write (filename data)
  "Write DATA as JSON to FILENAME."
  (jupiterweb--ensure-cache-directory)
  (with-temp-buffer
    (let ((json-encoding-pretty-print t))
      (insert (json-serialize (jupiterweb--plist-to-json data))))
    (write-region (point-min) (point-max) filename nil nil nil nil)))

(defun jupiterweb-cache-read-curriculum ()
  "Read curriculum data from the cache file."
  (let ((file (jupiterweb--cache-file-curriculum)))
    (when (file-exists-p file)
      (setq jupiterweb--curriculum-memory (jupiterweb--json-read-plist file))
      jupiterweb--curriculum-memory)))

(defun jupiterweb-cache-write-curriculum (curriculum)
  "Write CURRICULUM data to the cache file."
  (jupiterweb--json-write (jupiterweb--cache-file-curriculum) curriculum))

(defun jupiterweb-cache-read-discipline (sgldis)
  "Read discipline SGLDIS syllabus from the cache file."
  (let ((file (jupiterweb--cache-file-discipline sgldis)))
    (when (file-exists-p file)
      (let ((data (jupiterweb--json-read-plist file)))
        (when data
          (setq jupiterweb--discipline-memory
                (cons (cons sgldis data)
                      (assq-delete-all sgldis jupiterweb--discipline-memory))))
        data))))

(defun jupiterweb-cache-write-discipline (sgldis data)
  "Write discipline SGLDIS syllabus DATA to the cache file."
  (jupiterweb--json-write (jupiterweb--cache-file-discipline sgldis) data))

(defun jupiterweb-cache-curriculum-exists-p ()
  "Return non-nil if a curriculum cache file exists for the current course."
  (file-exists-p (jupiterweb--cache-file-curriculum)))

(defun jupiterweb-cache-discipline-exists-p (sgldis)
  "Return non-nil if a discipline cache file exists for SGLDIS."
  (file-exists-p (jupiterweb--cache-file-discipline sgldis)))

(defun jupiterweb-cache-clear-memory ()
  "Clear all in-memory caches."
  (setq jupiterweb--curriculum-memory nil
        jupiterweb--discipline-memory nil))

(defun jupiterweb-cache-clear-disk (&optional course-only)
  "Clear disk cache.  If COURSE-ONLY is non-nil, remove only the current course."
  (if course-only
      (let ((cur-file (jupiterweb--cache-file-curriculum)))
        (when (file-exists-p cur-file)
          (delete-file cur-file))
        (dolist (f (directory-files jupiterweb-cache-directory t
                                     (format "^disciplina-.*-codcur-%s-codhab-%s\\.json$"
                                             jupiterweb-codcur jupiterweb-codhab)))
          (delete-file f)))
    (when (file-directory-p jupiterweb-cache-directory)
      (dolist (f (directory-files jupiterweb-cache-directory t "\\.json$"))
        (when (file-regular-p f)
          (delete-file f))))))

(defun jupiterweb--ensure-curriculum ()
  "Return curriculum from memory, disk, or fetch according to policy."
  (or jupiterweb--curriculum-memory
      (jupiterweb-cache-read-curriculum)
      (when (memq jupiterweb-cache-fetch-policy '(lazy eager))
        (jupiterweb-refresh-curriculum-cache))))

(defun jupiterweb--ensure-discipline (sgldis)
  "Return discipline syllabus from memory, disk, or fetch according to policy."
  (let ((cached (assoc sgldis jupiterweb--discipline-memory)))
    (if cached
        (cdr cached)
      (or (jupiterweb-cache-read-discipline sgldis)
          (when (eq jupiterweb-cache-fetch-policy 'lazy)
            (condition-case err
                (jupiterweb-refresh-discipline-cache sgldis)
              (error
               (jupiterweb--build-syllabus-fallback sgldis nil
                 (format "Failed to fetch: %s" (error-message-string err))))))))))

;;;###autoload
(defun jupiterweb-refresh-curriculum-cache ()
  "Fetch, parse, cache, and return curriculum data."
  (interactive)
  (let* ((html (jupiterweb-fetch-curriculum-html))
         (curriculum (list :package "jupiterweb"
                           :kind "curriculum"
                           :schema-version 1
                           :codcg jupiterweb-codcg
                           :codcur jupiterweb-codcur
                           :codhab jupiterweb-codhab
                           :tipo jupiterweb-tipo
                           :source-url (jupiterweb--grade-url)
                           :fetched-at (format-time-string "%Y-%m-%dT%H:%M:%S%z")
                           :disciplines (jupiterweb-parse-curriculum html))))
    (when (null (plist-get curriculum :disciplines))
      (display-warning 'jupiterweb
                       "No discipline links found in curriculum HTML"))
    (setq jupiterweb--curriculum-memory curriculum)
    (jupiterweb-cache-write-curriculum curriculum)
    curriculum))

;;;###autoload
(defalias 'jupiterweb-refresh-grade-cache 'jupiterweb-refresh-curriculum-cache)

;;;###autoload
(defun jupiterweb-refresh-discipline-cache (sgldis)
  "Fetch, parse, cache, and return syllabus data for SGLDIS."
  (interactive "sDiscipline code (sgldis): ")
  (let* ((html (jupiterweb-fetch-discipline-html sgldis))
         (data (jupiterweb-parse-discipline html sgldis
                (jupiterweb--discipline-url sgldis))))
    (if (null data)
        (jupiterweb--build-syllabus-fallback sgldis nil
          "Could not parse discipline page")
      (let ((record (append data
                            (list :syllabus-status "cached"
                                  :fetched-at (format-time-string "%Y-%m-%dT%H:%M:%S%z")
                                  :raw-text html))))
        (setq jupiterweb--discipline-memory
              (cons (cons sgldis record)
                    (assq-delete-all sgldis jupiterweb--discipline-memory)))
        (jupiterweb-cache-write-discipline sgldis record)
        record))))

;;;###autoload
(defun jupiterweb-refresh-all-discipline-caches ()
  "Batch refresh all non-provisional discipline syllabi."
  (interactive)
  (let ((curriculum (jupiterweb--ensure-curriculum))
        (failures nil)
        (successes 0))
    (when curriculum
      (dolist (d (plist-get curriculum :disciplines))
        (let ((sgldis (plist-get d :sgldis)))
          (if (string-match-p "XXX$" sgldis)
              nil
            (sit-for jupiterweb-request-delay)
            (condition-case err
                (progn
                  (jupiterweb-refresh-discipline-cache sgldis)
                  (setq successes (1+ successes)))
              (error
               (push (list :sgldis sgldis :error (error-message-string err))
                     failures)))))))
    (list :successes successes
          :failures (nreverse failures)
          :total (+ successes (length failures)))))

(provide 'jupiterweb-cache)
;;; jupiterweb-cache.el ends here