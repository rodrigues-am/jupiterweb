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

(defun jupiterweb-http-get (url)
  "Return decoded HTML from URL as a string."
  (error "jupiterweb-http-get not yet implemented"))

(defun jupiterweb-fetch-curriculum-html (&optional codcg codcur codhab tipo)
  "Fetch the current curriculum HTML."
  (error "jupiterweb-fetch-curriculum-html not yet implemented"))

(defun jupiterweb-fetch-discipline-html (sgldis &optional codcur codhab)
  "Fetch a discipline syllabus HTML page."
  (error "jupiterweb-fetch-discipline-html not yet implemented"))

(provide 'jupiterweb-http)
;;; jupiterweb-http.el ends here