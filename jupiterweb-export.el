;;; jupiterweb-export.el --- JSON export for JupiterWeb  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  rodrigues-am

;; This file is not part of GNU Emacs.

;;; Commentary:

;; JSON export of cached curriculum and discipline data for the
;; jupiterweb package.

;;; Code:

(require 'json)
(require 'jupiterweb-vars)

(defun jupiterweb-export-cache-json (file &optional fetch-missing)
  "Export current curriculum and cached syllabi to FILE as JSON."
  (error "jupiterweb-export-cache-json not yet implemented"))

(provide 'jupiterweb-export)
;;; jupiterweb-export.el ends here