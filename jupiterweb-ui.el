;;; jupiterweb-ui.el --- Selection, insertion, and view buffer for JupiterWeb  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  rodrigues-am

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Selection, insertion, Consult/Marginalia integration, and view buffer
;; for the jupiterweb package.

;;; Code:

(require 'jupiterweb-vars)
(require 'jupiterweb-cache)

;; Format helpers (JW-090)

(defun jupiterweb--format-name-code (discipline)
  "Return \"Name (Code)\" for DISCIPLINE plist."
  (format "%s (%s)" (or (plist-get discipline :name) "")
          (or (plist-get discipline :sgldis) "")))

(defun jupiterweb--format-code-name (discipline)
  "Return \"Code - Name\" for DISCIPLINE plist."
  (format "%s - %s" (or (plist-get discipline :sgldis) "")
          (or (plist-get discipline :name) "")))

;; Candidate builder (JW-091)

(defun jupiterweb--build-candidates ()
  "Build completion candidates from curriculum data."
  (let ((curriculum (jupiterweb--ensure-curriculum)))
    (when curriculum
      (mapcar (lambda (d)
                (cons (jupiterweb--format-name-code d) d))
              (plist-get curriculum :disciplines)))))

(defun jupiterweb--accent-insensitive-key (str)
  "Return an accent-insensitive search key for STR."
  (let* ((nfd (condition-case nil
                  (ucs-normalize-NFD-string str)
                (error str)))
         (chars (string-to-list nfd))
         (result nil))
    (dolist (ch chars)
      (let ((cat (condition-case nil
                    (get-char-code-property ch 'general-category)
                  (error nil))))
        (if (and cat (string-prefix-p "Mn" (symbol-name cat)))
            nil
          (push (downcase (string ch)) result))))
    (apply #'concat (nreverse result))))

;; Selection (JW-092)

(defun jupiterweb-select-discipline ()
  "Let user select a discipline by name or code."
  (let* ((candidates (jupiterweb--build-candidates))
         (display-candidates (mapcar #'car candidates))
         (selected (if (and (require 'consult nil t)
                           (fboundp 'consult-read))
                        (consult-read display-candidates
                                      :prompt "Select discipline: "
                                      :category 'jupiterweb-discipline)
                      (completing-read "Select discipline: " display-candidates nil t))))
    (when selected
      (cdr (assoc selected candidates)))))

;; Insert commands (JW-093, JW-094)

;;;###autoload
(defun jupiterweb-insert-name-code ()
  "Insert selected discipline as \"Name (Code)\"."
  (interactive)
  (let ((d (jupiterweb-select-discipline)))
    (when d
      (insert (jupiterweb--format-name-code d)))))

;;;###autoload
(defun jupiterweb-insert-code-name ()
  "Insert selected discipline as \"Code - Name\"."
  (interactive)
  (let ((d (jupiterweb-select-discipline)))
    (when d
      (insert (jupiterweb--format-code-name d)))))

;; View mode (JW-100)

(define-derived-mode jupiterweb-view-mode special-mode "JupiterWeb"
  "Read-only mode for viewing JupiterWeb syllabus data."
  (read-only-mode 1))

(defvar jupiterweb--view-origin-buffer nil
  "Origin buffer for view-mode insert commands.")
(make-variable-buffer-local 'jupiterweb--view-origin-buffer)

;; Syllabus renderer (JW-101)

(defun jupiterweb--render-syllabus (data)
  "Render syllabus DATA as formatted text for the view buffer."
  (let ((sep (make-string 40 ?\u2500)))
    (with-temp-buffer
      (insert (jupiterweb--format-code-name data) "\n")
      (when (plist-get data :name-en)
        (insert (plist-get data :name-en) "\n"))
      (insert "\n")
      (when (plist-get data :unit)
        (insert (format "Unit:\t\t%s\n" (plist-get data :unit))))
      (when (plist-get data :credits-lecture)
        (insert (format "Credits Lecture:\t%s\n" (plist-get data :credits-lecture))))
      (when (plist-get data :credits-work)
        (insert (format "Credits Work:\t%s\n" (plist-get data :credits-work))))
      (when (plist-get data :workload-total)
        (insert (format "Total Workload:\t%s h\n" (plist-get data :workload-total))))
      (when (plist-get data :type)
        (insert (format "Type:\t\t%s\n" (plist-get data :type))))
      (when (plist-get data :activation)
        (insert (format "Activation:\t%s\n" (plist-get data :activation))))
      (dolist (section '(("Objectives" :objectives)
                         ("Summary Program" :summary-program)
                         ("Program" :program)
                         ("Assessment" :assessment-method)
                         ("Bibliography" :bibliography)))
        (let ((title (car section))
              (key (cadr section)))
          (let ((content (plist-get data key)))
            (when content
              (insert "\n" sep "\n" title "\n" sep "\n\n" content "\n")))))
      (buffer-string))))

;; View command (JW-102)

;;;###autoload
(defun jupiterweb-view-discipline ()
  "View syllabus for a selected discipline in a side buffer."
  (interactive)
  (let* ((d (jupiterweb-select-discipline))
         (sgldis (plist-get d :sgldis))
         (origin-buffer (current-buffer)))
    (when d
      (let* ((data (jupiterweb--ensure-discipline sgldis))
             (buf-name (format "*JupiterWeb: %s - %s*"
                               sgldis (or (plist-get data :name) "")))
             (buf (get-buffer-create buf-name)))
        (with-current-buffer buf
          (jupiterweb-view-mode)
          (let ((inhibit-read-only t))
            (erase-buffer)
            (insert (jupiterweb--render-syllabus data))
            (goto-char (point-min)))
          (setq jupiterweb--view-origin-buffer origin-buffer))
        (display-buffer-in-side-window buf
                                        (list (cons 'side
                                                   (cond
                                                    ((eq jupiterweb-view-side 'right) 'right)
                                                    ((eq jupiterweb-view-side 'left) 'left)
                                                    ((eq jupiterweb-view-side 'top) 'top)
                                                    ((eq jupiterweb-view-side 'bottom) 'bottom)))
                                              (cons 'slot 0)
                                              (cons 'window-width
                                                   jupiterweb-view-window-width)))))))

;; Section list helper (JW-110)

(defun jupiterweb--section-list (syllabus)
  "Return available sections for a SYLLABUS object."
  (let ((sections '(("Objectives" :objectives)
                    ("Summary Program" :summary-program)
                    ("Program" :program)
                    ("Teaching Method" :teaching-method)
                    ("Assessment" :assessment-method)
                    ("Recovery Rule" :recovery-rule)
                    ("Bibliography" :bibliography)
                    ("Basic Bibliography" :basic-bibliography)
                    ("Complementary Bibliography" :complementary-bibliography)
                    ("Instructors" :instructors))))
    (cl-remove-if-not (lambda (s)
                        (plist-get syllabus (cadr s)))
                      sections)))

;; Generic section insert (JW-111)

;;;###autoload
(defun jupiterweb-insert-discipline-section ()
  "Select a discipline and a section, then insert the section text."
  (interactive)
  (let* ((d (jupiterweb-select-discipline))
         (sgldis (plist-get d :sgldis)))
    (when d
      (let* ((data (jupiterweb--ensure-discipline sgldis))
             (sections (jupiterweb--section-list data))
             (section-names (mapcar #'car sections))
             (selected (completing-read "Section: " section-names nil t))
             (section (assoc selected sections)))
        (when section
          (let ((content (plist-get data (cadr section))))
            (when content
              (insert content))))))))

;; Direct section insert commands (JW-112)

(defun jupiterweb--insert-section-by-key (key)
  "Insert the section identified by KEY for a selected discipline."
  (let* ((d (jupiterweb-select-discipline))
         (sgldis (plist-get d :sgldis)))
    (when d
      (let ((data (jupiterweb--ensure-discipline sgldis)))
        (let ((content (plist-get data key)))
          (when content
            (insert content)))))))

;;;###autoload
(defun jupiterweb-insert-objectives ()
  "Insert objectives for a selected discipline."
  (interactive)
  (jupiterweb--insert-section-by-key :objectives))

;;;###autoload
(defun jupiterweb-insert-summary-program ()
  "Insert summary program for a selected discipline."
  (interactive)
  (jupiterweb--insert-section-by-key :summary-program))

;;;###autoload
(defun jupiterweb-insert-program ()
  "Insert program for a selected discipline."
  (interactive)
  (jupiterweb--insert-section-by-key :program))

;;;###autoload
(defun jupiterweb-insert-assessment ()
  "Insert assessment for a selected discipline."
  (interactive)
  (jupiterweb--insert-section-by-key :assessment-method))

;;;###autoload
(defun jupiterweb-insert-bibliography ()
  "Insert bibliography for a selected discipline."
  (interactive)
  (jupiterweb--insert-section-by-key :bibliography))

;; Consult and Marginalia (JW-120, JW-121, JW-122)

(when (require 'marginalia nil t)
  (add-to-list 'marginalia-command-categories
               (cons 'jupiterweb-select-discipline
                     'jupiterweb-discipline)))

(provide 'jupiterweb-ui)
;;; jupiterweb-ui.el ends here