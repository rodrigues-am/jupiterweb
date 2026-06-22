;;; jupiterweb-cache.el --- JSON cache read/write for JupiterWeb  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  rodrigues-am

;; This file is not part of GNU Emacs.

;;; Commentary:

;; JSON cache read/write, cache invalidation, and refresh commands for
;; the jupiterweb package.

;;; Code:

(require 'json)
(require 'jupiterweb-vars)

(defun jupiterweb--cache-file-curriculum ()
  "Return the cache filename for the current curriculum."
  (error "jupiterweb--cache-file-curriculum not yet implemented"))

(defun jupiterweb--cache-file-discipline (sgldis)
  "Return the cache filename for discipline SGLDIS."
  (error "jupiterweb--cache-file-discipline not yet implemented"))

(defun jupiterweb--ensure-cache-directory ()
  "Ensure the cache directory exists."
  (error "jupiterweb--ensure-cache-directory not yet implemented"))

(defun jupiterweb-cache-read-curriculum ()
  "Read curriculum data from the cache file."
  (error "jupiterweb-cache-read-curriculum not yet implemented"))

(defun jupiterweb-cache-write-curriculum (curriculum)
  "Write CURRICULUM data to the cache file."
  (error "jupiterweb-cache-write-curriculum not yet implemented"))

(defun jupiterweb-cache-read-discipline (sgldis)
  "Read discipline SGLDIS syllabus from the cache file."
  (error "jupiterweb-cache-read-discipline not yet implemented"))

(defun jupiterweb-cache-write-discipline (sgldis data)
  "Write discipline SGLDIS syllabus DATA to the cache file."
  (error "jupiterweb-cache-write-discipline not yet implemented"))

(defun jupiterweb-cache-curriculum-exists-p ()
  "Return non-nil if a curriculum cache file exists for the current course."
  (error "jupiterweb-cache-curriculum-exists-p not yet implemented"))

(defun jupiterweb-cache-discipline-exists-p (sgldis)
  "Return non-nil if a discipline cache file exists for SGLDIS."
  (error "jupiterweb-cache-discipline-exists-p not yet implemented"))

(defun jupiterweb-cache-clear-memory ()
  "Clear all in-memory caches."
  (setq jupiterweb--curriculum-memory nil
        jupiterweb--discipline-memory nil))

(defun jupiterweb-cache-clear-disk (&optional course-only)
  "Clear disk cache.  If COURSE-ONLY is non-nil, remove only the current course."
  (error "jupiterweb-cache-clear-disk not yet implemented"))

(provide 'jupiterweb-cache)
;;; jupiterweb-cache.el ends here