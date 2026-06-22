;;; jupiterweb-transient.el --- Transient menu for JupiterWeb  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  rodrigues-am

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Transient menu dispatcher for the jupiterweb package.
;; When Transient is not available, public commands still work.

;;; Code:

(eval-and-compile
  (require 'transient nil t))

(require 'jupiterweb-vars)
(require 'jupiterweb-cache)
(require 'jupiterweb-ui)
(require 'jupiterweb-export)

(when (featurep 'transient)

  (transient-define-prefix jupiterweb-dispatch ()
    "JupiterWeb dispatcher."
    :class 'transient-prefix
    [["Insert"
      ("n" "Insert Name (Code)" jupiterweb-insert-name-code)
      ("i" "Insert Code - Name" jupiterweb-insert-code-name)
      ("s" "Insert section" jupiterweb-insert-discipline-section)
      ("o" "Insert objectives" jupiterweb-insert-objectives)
      ("r" "Insert summary program" jupiterweb-insert-summary-program)
      ("p" "Insert program" jupiterweb-insert-program)
      ("a" "Insert assessment" jupiterweb-insert-assessment)
      ("b" "Insert bibliography" jupiterweb-insert-bibliography)]
     ["View"
      ("v" "View syllabus" jupiterweb-view-discipline)]]
    [["Cache"
      ("g" "Refresh curriculum" jupiterweb-refresh-curriculum-cache)
      ("d" "Refresh one discipline" jupiterweb-refresh-discipline-cache)
      ("A" "Refresh all disciplines" jupiterweb-refresh-all-discipline-caches)
      ("m" "Clear memory cache" jupiterweb-cache-clear-memory)
      ("C" "Clear disk cache" jupiterweb-cache-clear-disk)]
     ["Export"
      ("j" "Export to JSON" jupiterweb-export-cache-json)]
     ["Course"
      ("u" "Set course" jupiterweb-set-course)]]))

(unless (fboundp 'jupiterweb-dispatch)
  (defun jupiterweb-dispatch ()
    "Fallback dispatcher when Transient is unavailable."
    (interactive)
    (user-error "Transient is not available; call jupiterweb commands directly")))

(provide 'jupiterweb-transient)
;;; jupiterweb-transient.el ends here