;;; jupiterweb-http.el --- HTTP retrieval for JupiterWeb  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  rodrigues-am

;; This file is not part of GNU Emacs.

;;; Commentary:

;; HTTP retrieval, URL building, decoding, and retries for the
;; jupiterweb package.

;;; Code:

(require 'url)
(require 'url-parse)
(require 'jupiterweb-vars)
(require 'jupiterweb-parse)

(defun jupiterweb--grade-url (&optional codcg codcur codhab tipo)
  "Return the JupiterWeb curriculum URL for the selected course."
  (let ((cg (or codcg jupiterweb-codcg))
        (cc (or codcur jupiterweb-codcur))
        (ch (or codhab jupiterweb-codhab))
        (tp (or tipo jupiterweb-tipo)))
    (format "https://uspdigital.usp.br/jupiterweb/listarGradeCurricular?codcg=%s&codcur=%s&codhab=%s&tipo=%s"
            cg cc ch tp)))

(defun jupiterweb--discipline-url (sgldis &optional codcur codhab)
  "Return the JupiterWeb discipline URL for SGLDIS."
  (let ((cc (or codcur jupiterweb-codcur))
        (ch (or codhab jupiterweb-codhab)))
    (format "https://uspdigital.usp.br/jupiterweb/obterDisciplina?sgldis=%s&codcur=%s&codhab=%s"
            sgldis cc ch)))

(defun jupiterweb--with-retries (thunk &optional max-retries)
  "Call THUNK up to MAX-RETRIES times, returning the first non-nil result.
If MAX-RETRIES is nil, use `jupiterweb-retries'."
  (let ((attempts (or max-retries jupiterweb-retries))
        (result nil)
        (errors nil))
    (catch 'done
      (dotimes (i attempts)
        (condition-case err
            (progn
              (setq result (funcall thunk))
              (when result
                (throw 'done result)))
          (error
           (push err errors)
           (when (< (1+ i) attempts)
             (sit-for 1))))))
    (if result
        result
      (error "JupiterWeb: failed after %d attempts" attempts))))

(defun jupiterweb-http-get (url)
  "Return decoded HTML from URL as a string.
Respects `jupiterweb-http-timeout' and `jupiterweb-user-agent'.
Raises a clear error for network failures."
  (let ((url-request-extra-headers
         `(("User-Agent" . ,jupiterweb-user-agent)))
        (url-request-method "GET")
        (url-show-status nil))
    (condition-case err
        (let ((buffer (url-retrieve-synchronously url t nil
                                                    jupiterweb-http-timeout)))
          (if (null buffer)
              (error "JupiterWeb: could not retrieve URL %s" url)
            (with-current-buffer buffer
              (goto-char (point-min))
              (re-search-forward "\r?\n\r?\n" nil t)
              (let ((body (buffer-substring-no-properties (point) (point-max))))
                (kill-buffer)
                (jupiterweb--decode-response body)))))
      (error
       (signal (car err) (cdr err))))))

(defun jupiterweb-fetch-curriculum-html (&optional codcg codcur codhab tipo)
  "Fetch the current curriculum HTML."
  (let ((url (jupiterweb--grade-url codcg codcur codhab tipo)))
    (jupiterweb--with-retries
     (lambda () (jupiterweb-http-get url)))))

(defun jupiterweb-fetch-discipline-html (sgldis &optional codcur codhab)
  "Fetch a discipline syllabus HTML page."
  (let ((url (jupiterweb--discipline-url sgldis codcur codhab)))
    (jupiterweb--with-retries
     (lambda () (jupiterweb-http-get url)))))

(provide 'jupiterweb-http)
;;; jupiterweb-http.el ends here