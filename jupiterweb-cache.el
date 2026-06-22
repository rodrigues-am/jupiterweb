;;; jupiterweb-cache.el --- Fast Elisp cache read/write for JupiterWeb  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  rodrigues-am

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Fast Elisp cache read/write, legacy JSON cache reading, cache invalidation,
;; and refresh commands for the jupiterweb package.

;;; Code:

(require 'json)
(require 'subr-x)
(require 'jupiterweb-vars)
(require 'jupiterweb-http)
(require 'jupiterweb-parse)

(defun jupiterweb--cache-file-curriculum ()
  "Return the Emacs Lisp cache filename for the current curriculum."
  (expand-file-name
   (format "grade-codcg-%s-codcur-%s-codhab-%s-tipo-%s.el"
           jupiterweb-codcg jupiterweb-codcur jupiterweb-codhab jupiterweb-tipo)
   jupiterweb-cache-directory))

(defun jupiterweb--cache-file-curriculum-json ()
  "Return the legacy JSON cache filename for the current curriculum."
  (expand-file-name
   (format "grade-codcg-%s-codcur-%s-codhab-%s-tipo-%s.json"
           jupiterweb-codcg jupiterweb-codcur jupiterweb-codhab jupiterweb-tipo)
   jupiterweb-cache-directory))

(defun jupiterweb--cache-file-discipline (sgldis)
  "Return the Emacs Lisp cache filename for discipline SGLDIS."
  (expand-file-name
   (format "disciplina-%s-codcur-%s-codhab-%s.el"
           sgldis jupiterweb-codcur jupiterweb-codhab)
   jupiterweb-cache-directory))

(defun jupiterweb--cache-file-discipline-json (sgldis)
  "Return the legacy JSON cache filename for discipline SGLDIS."
  (expand-file-name
   (format "disciplina-%s-codcur-%s-codhab-%s.json"
           sgldis jupiterweb-codcur jupiterweb-codhab)
   jupiterweb-cache-directory))

(defun jupiterweb--ensure-cache-directory ()
  "Ensure the cache directory exists."
  (unless (file-directory-p jupiterweb-cache-directory)
    (make-directory jupiterweb-cache-directory t))
  jupiterweb-cache-directory)

(defun jupiterweb--log-file ()
  "Return the inspection log filename for JupiterWeb refresh operations."
  (expand-file-name "jupiterweb-refresh.log" jupiterweb-cache-directory))

(defun jupiterweb--log-event (kind status &rest fields)
  "Append a refresh log entry for KIND and STATUS with FIELDS.
KIND and STATUS are symbols.  FIELDS is a plist written as key=value pairs."
  (jupiterweb--ensure-cache-directory)
  (with-temp-buffer
    (insert (format "%s kind=%s status=%s"
                    (format-time-string "%Y-%m-%dT%H:%M:%S%z")
                    kind status))
    (while fields
      (let ((key (pop fields))
            (value (pop fields)))
        (when value
          (insert (format " %s=%S" (substring (symbol-name key) 1) value)))))
    (insert "\n")
    (append-to-file (point-min) (point-max) (jupiterweb--log-file))))

(defun jupiterweb--discipline-display-name (sgldis record fallback-name)
  "Return display name for SGLDIS using RECORD or FALLBACK-NAME."
  (or (and record (plist-get record :name))
      (and fallback-name (not (string-empty-p fallback-name)) fallback-name)
      sgldis))

(defun jupiterweb--discipline-cache-success-p (record)
  "Return non-nil when RECORD is a fully parsed discipline cache entry."
  (and record
       (not (equal (plist-get record :syllabus-status) "fallback"))
       (plist-get record :credits-lecture)
       (or (plist-get record :syllabus)
           (plist-get record :objectives)
           (plist-get record :summary-program)
           (plist-get record :bibliography))))

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

(defun jupiterweb--el-read-plist (filename)
  "Read a cached Elisp plist from FILENAME."
  (when (file-exists-p filename)
    (with-temp-buffer
      (insert-file-contents filename)
      (goto-char (point-min))
      (condition-case nil
          (read (current-buffer))
        (error nil)))))

(defun jupiterweb--el-write (filename data)
  "Write DATA as an Emacs Lisp expression to FILENAME."
  (jupiterweb--ensure-cache-directory)
  (with-temp-file filename
    (let ((print-level nil)
          (print-length nil)
          (print-circle t))
      (prin1 data (current-buffer))
      (insert "\n"))))

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
  (let* ((file (jupiterweb--cache-file-curriculum))
         (legacy-file (jupiterweb--cache-file-curriculum-json))
         (data (or (jupiterweb--el-read-plist file)
                   (jupiterweb--json-read-plist legacy-file))))
    (when data
      (setq jupiterweb--curriculum-memory data)
      data)))

(defun jupiterweb-cache-write-curriculum (curriculum)
  "Write CURRICULUM data to the cache file."
  (jupiterweb--el-write (jupiterweb--cache-file-curriculum) curriculum))

(defun jupiterweb-cache-read-discipline (sgldis)
  "Read discipline SGLDIS syllabus from the cache file."
  (let* ((file (jupiterweb--cache-file-discipline sgldis))
         (legacy-file (jupiterweb--cache-file-discipline-json sgldis))
         (data (or (jupiterweb--el-read-plist file)
                   (jupiterweb--json-read-plist legacy-file))))
    (when data
      (setq jupiterweb--discipline-memory
            (cons (cons sgldis data)
                  (assoc-delete-all sgldis jupiterweb--discipline-memory)))
      data)))

(defun jupiterweb-cache-write-discipline (sgldis data)
  "Write discipline SGLDIS syllabus DATA to the cache file."
  (jupiterweb--el-write (jupiterweb--cache-file-discipline sgldis) data))

(defun jupiterweb-cache-curriculum-exists-p ()
  "Return non-nil if a curriculum cache file exists for the current course."
  (or (file-exists-p (jupiterweb--cache-file-curriculum))
      (file-exists-p (jupiterweb--cache-file-curriculum-json))))

(defun jupiterweb-cache-discipline-exists-p (sgldis)
  "Return non-nil if a discipline cache file exists for SGLDIS."
  (or (file-exists-p (jupiterweb--cache-file-discipline sgldis))
      (file-exists-p (jupiterweb--cache-file-discipline-json sgldis))))

(defun jupiterweb-cache-clear-memory ()
  "Clear all in-memory caches."
  (interactive)
  (setq jupiterweb--curriculum-memory nil
        jupiterweb--discipline-memory nil))

(defun jupiterweb-cache-clear-disk (&optional course-only)
  "Clear disk cache.  If COURSE-ONLY is non-nil, remove only the current course."
  (interactive "P")
  (if course-only
      (let ((cur-file (jupiterweb--cache-file-curriculum))
            (legacy-cur-file (jupiterweb--cache-file-curriculum-json)))
        (when (file-exists-p cur-file)
          (delete-file cur-file))
        (when (file-exists-p legacy-cur-file)
          (delete-file legacy-cur-file))
        (dolist (f (directory-files jupiterweb-cache-directory t
                                     (format "^disciplina-.*-codcur-%s-codhab-%s\\.\\(el\\|json\\)$"
                                             jupiterweb-codcur jupiterweb-codhab)))
          (delete-file f)))
    (when (file-directory-p jupiterweb-cache-directory)
      (dolist (f (directory-files jupiterweb-cache-directory t "\\.\\(el\\|json\\)$"))
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

(defun jupiterweb--curriculum-discipline-name (sgldis)
  "Return the curriculum name for SGLDIS when available."
  (let ((curriculum (or jupiterweb--curriculum-memory
                        (jupiterweb-cache-read-curriculum)))
        (name nil))
    (dolist (d (plist-get curriculum :disciplines))
      (when (and (null name)
                 (equal (plist-get d :sgldis) sgldis))
        (setq name (plist-get d :name))))
    name))

(defun jupiterweb--update-curriculum-discipline-name (sgldis name)
  "Update cached curriculum entry SGLDIS with NAME when useful."
  (when (and jupiterweb--curriculum-memory name
             (not (string-empty-p name)))
    (let ((changed nil))
      (setq jupiterweb--curriculum-memory
            (plist-put
             jupiterweb--curriculum-memory
             :disciplines
             (mapcar
              (lambda (d)
                (if (equal (plist-get d :sgldis) sgldis)
                    (let ((record (copy-sequence d)))
                      (unless (equal (plist-get record :name) name)
                        (setq changed t)
                        (setq record (plist-put record :name name)))
                      record)
                  d))
              (plist-get jupiterweb--curriculum-memory :disciplines))))
      (when changed
        (jupiterweb-cache-write-curriculum jupiterweb--curriculum-memory)))))

;;;###autoload
(defun jupiterweb-refresh-curriculum-cache ()
  "Fetch, parse, cache, and return curriculum data."
  (interactive)
  (message "JupiterWeb: loading curriculum %s/%s/%s/%s"
           jupiterweb-codcg jupiterweb-codcur jupiterweb-codhab jupiterweb-tipo)
  (condition-case err
      (let* ((html (jupiterweb-fetch-curriculum-html))
             (disciplines (jupiterweb-parse-curriculum html))
             (curriculum (list :package "jupiterweb"
                               :kind "curriculum"
                               :schema-version 1
                               :codcg jupiterweb-codcg
                               :codcur jupiterweb-codcur
                               :codhab jupiterweb-codhab
                               :tipo jupiterweb-tipo
                               :source-url (jupiterweb--grade-url)
                               :fetched-at (format-time-string "%Y-%m-%dT%H:%M:%S%z")
                               :disciplines disciplines)))
        (when (null disciplines)
          (display-warning 'jupiterweb
                           "No discipline links found in curriculum HTML"))
        (setq jupiterweb--curriculum-memory curriculum)
        (jupiterweb-cache-write-curriculum curriculum)
        (if disciplines
            (progn
              (message "JupiterWeb: 🟩 Curriculum loaded successfully: %d disciplines cached."
                       (length disciplines))
              (jupiterweb--log-event 'curriculum 'success
                                     :codcg jupiterweb-codcg
                                     :codcur jupiterweb-codcur
                                     :codhab jupiterweb-codhab
                                     :tipo jupiterweb-tipo
                                     :disciplines (length disciplines)
                                     :file (jupiterweb--cache-file-curriculum)))
          (message "JupiterWeb: 🔴 Curriculum load failed: no discipline links found.")
          (jupiterweb--log-event 'curriculum 'not-found
                                 :codcg jupiterweb-codcg
                                 :codcur jupiterweb-codcur
                                 :codhab jupiterweb-codhab
                                 :tipo jupiterweb-tipo
                                 :reason "no discipline links found"
                                 :file (jupiterweb--cache-file-curriculum)))
        curriculum)
    (error
     (message "JupiterWeb: 🔴 Curriculum load failed: %s"
              (error-message-string err))
     (jupiterweb--log-event 'curriculum 'fetch-failed
                            :codcg jupiterweb-codcg
                            :codcur jupiterweb-codcur
                            :codhab jupiterweb-codhab
                            :tipo jupiterweb-tipo
                            :error (error-message-string err))
     (signal (car err) (cdr err)))))

;;;###autoload
(defalias 'jupiterweb-refresh-grade-cache 'jupiterweb-refresh-curriculum-cache)

;;;###autoload
(defun jupiterweb-refresh-discipline-cache (sgldis)
  "Fetch, parse, cache, and return syllabus data for SGLDIS."
  (interactive "sDiscipline code (sgldis): ")
  (let ((display-name (jupiterweb--curriculum-discipline-name sgldis)))
    (message "JupiterWeb: buscando disciplina %s%s"
             sgldis
             (if (and display-name
                      (not (string-empty-p display-name))
                      (not (string= display-name sgldis)))
                 (format " - %s" display-name)
               ""))
    (condition-case err
        (let* ((html (jupiterweb-fetch-discipline-html sgldis))
               (data (jupiterweb-parse-discipline html sgldis
                     (jupiterweb--discipline-url sgldis)))
               (record (if data
                           (append data
                                   (list :syllabus-status "cached"
                                         :fetched-at (format-time-string "%Y-%m-%dT%H:%M:%S%z")
                                         :raw-text html))
                         (jupiterweb--build-syllabus-fallback
                          sgldis display-name "Could not parse discipline page")))
               (name (jupiterweb--discipline-display-name sgldis record display-name)))
          (setq jupiterweb--discipline-memory
                (cons (cons sgldis record)
                      (assoc-delete-all sgldis jupiterweb--discipline-memory)))
          (jupiterweb-cache-write-discipline sgldis record)
          (jupiterweb--update-curriculum-discipline-name
           sgldis (plist-get record :name))
          (if (jupiterweb--discipline-cache-success-p record)
              (progn
                (message "JupiterWeb: 🟩 Discipline %s - %s loaded successfully!"
                         sgldis name)
                (jupiterweb--log-event 'discipline 'success
                                       :sgldis sgldis
                                       :name name
                                       :file (jupiterweb--cache-file-discipline sgldis)))
            (message "JupiterWeb: 🔴 Discipline %s - %s could not be parsed."
                     sgldis name)
            (jupiterweb--log-event 'discipline 'parse-failed
                                   :sgldis sgldis
                                   :name name
                                   :reason (or (plist-get record :observation)
                                               "Could not parse discipline page")
                                   :file (jupiterweb--cache-file-discipline sgldis)))
          record)
      (error
       (message "JupiterWeb: 🔴 Discipline %s%s failed: %s"
                sgldis
                (if (and display-name
                         (not (string-empty-p display-name))
                         (not (string= display-name sgldis)))
                    (format " - %s" display-name)
                  "")
                (error-message-string err))
       (jupiterweb--log-event 'discipline 'fetch-failed
                              :sgldis sgldis
                              :name display-name
                              :error (error-message-string err))
       (signal (car err) (cdr err))))))

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