;;; jupiterweb-vars.el --- Customization group and variables for jupiterweb  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  rodrigues-am

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Customization group, defcustom variables, and in-memory state for the
;; jupiterweb package.

;;; Code:

(defgroup jupiterweb nil
  "Query and insert USP JupiterWeb curriculum data."
  :group 'applications)

(defcustom jupiterweb-codcg "43"
  "USP unit code used by JupiterWeb."
  :type 'string
  :group 'jupiterweb)

(defcustom jupiterweb-codcur "43031"
  "USP course code used by JupiterWeb."
  :type 'string
  :group 'jupiterweb)

(defcustom jupiterweb-codhab "0"
  "USP habilitation code used by JupiterWeb."
  :type 'string
  :group 'jupiterweb)

(defcustom jupiterweb-tipo "N"
  "JupiterWeb curriculum type."
  :type 'string
  :group 'jupiterweb)

(defcustom jupiterweb-cache-directory
  (expand-file-name "jupiterweb/" user-emacs-directory)
  "Directory where jupiterweb stores JSON cache files."
  :type 'directory
  :group 'jupiterweb)

(defcustom jupiterweb-cache-fetch-policy 'lazy
  "When to fetch missing syllabus data: lazy, eager, or manual."
  :type '(choice
          (const :tag "Fetch syllabus on demand" lazy)
          (const :tag "Fetch all syllabi when refreshing curriculum" eager)
          (const :tag "Never fetch automatically" manual))
  :group 'jupiterweb)

(defcustom jupiterweb-http-timeout 40
  "Timeout in seconds for JupiterWeb HTTP requests."
  :type 'integer
  :group 'jupiterweb)

(defcustom jupiterweb-retries 3
  "Number of HTTP retries for JupiterWeb requests."
  :type 'integer
  :group 'jupiterweb)

(defcustom jupiterweb-request-delay 0.5
  "Delay in seconds between batch requests."
  :type 'number
  :group 'jupiterweb)

(defcustom jupiterweb-user-agent
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 jupiterweb.el"
  "User-Agent string used for JupiterWeb requests."
  :type 'string
  :group 'jupiterweb)

(defcustom jupiterweb-codhab-fallbacks '("0" "4")
  "Habilitation codes to try when fetching a discipline syllabus."
  :type '(repeat string)
  :group 'jupiterweb)

(defcustom jupiterweb-view-side 'right
  "Side used to display syllabus buffers."
  :type '(choice (const left) (const right) (const top) (const bottom))
  :group 'jupiterweb)

(defcustom jupiterweb-view-window-width 0.42
  "Relative width of the syllabus side window."
  :type 'number
  :group 'jupiterweb)

;; In-memory state

(defvar jupiterweb--curriculum-memory nil
  "In-memory cache for the current curriculum plist.")

(defvar jupiterweb--discipline-memory nil
  "In-memory cache for discipline syllabus plists, keyed by sgldis.")

(defun jupiterweb--current-course-key ()
  "Return a cons cell (codcur . codhab) identifying the current course."
  (cons jupiterweb-codcur jupiterweb-codhab))

(provide 'jupiterweb-vars)
;;; jupiterweb-vars.el ends here